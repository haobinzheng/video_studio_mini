import AVFoundation
import Foundation

/// Preview synthesis is bounded so long scripts (hundreds of sentences) stay responsive and a stuck `AVSpeechSynthesizer` cannot hang the UI indefinitely.
private enum NarrationPreviewLimits {
    /// After duration capping, merge adjacent utterances so we never run this many sequential `write` passes for a preview.
    static let maxSynthesisSegments = 36
    /// Hard cap per synthesized chunk (merged text) to avoid pathological TTS stalls.
    static let maxCharactersPerPreviewChunk = 4_000
    static let perSegmentTimeoutSeconds: TimeInterval = 90
}

@MainActor
struct NarrationPreviewBuilder {
    private final class PreviewSynthesisResumeState: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false

        func resumeSuccess(_ continuation: CheckedContinuation<TimeInterval, Error>, returning value: TimeInterval) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            lock.unlock()
            continuation.resume(returning: value)
        }

        func resumeFailure(_ continuation: CheckedContinuation<TimeInterval, Error>, error: Error) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            lock.unlock()
            continuation.resume(throwing: error)
        }

        func resumeTimeout(_ continuation: CheckedContinuation<TimeInterval, Error>) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            lock.unlock()
            continuation.resume(throwing: PreviewError.segmentSynthesisTimedOut)
        }
    }

    struct SubtitleCue: Codable, Identifiable {
        let id: UUID
        let text: String
        let start: TimeInterval
        let end: TimeInterval

        init(id: UUID = UUID(), text: String, start: TimeInterval, end: TimeInterval) {
            self.id = id
            self.text = text
            self.start = start
            self.end = end
        }
    }

    struct PreviewResult {
        let audioURL: URL
        let subtitleJSONURL: URL
        let cues: [SubtitleCue]
        let duration: TimeInterval
        /// Wall-clock [start, end) per TTS utterance, aligned with `cues` timing source; used to sync Media carousel to Edit Story blocks.
        let paragraphPlaybackRanges: [(start: TimeInterval, end: TimeInterval)]
    }

    private struct CueChunk {
        let text: String
        let weight: Double
    }

    func buildPreview(
        text: String,
        voiceIdentifier: String,
        speechRateMultiplier: Double = 1.0,
        maximumDuration: TimeInterval? = nil,
        forcedParagraphSegments: [String]? = nil,
        storyBlockTexts: [String]? = nil,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws -> PreviewResult {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments: [String]
        /// Per Edit block: how many TTS utterances belong to that block (preview only).
        var storyBlockUtteranceCounts: [Int]? = nil
        if let blockTexts = storyBlockTexts {
            let trimmedBlocks = blockTexts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !trimmedBlocks.isEmpty else {
                throw PreviewError.emptyNarration
            }
            let cappedBlocks = cappedPreviewSegments(from: trimmedBlocks, maximumDuration: maximumDuration)
            var flat: [String] = []
            var counts: [Int] = []
            for blockText in cappedBlocks {
                var subs = StoryScriptPartition.narrationSegmentsWholeScriptStyle(
                    blockText: blockText,
                    voiceIdentifier: voiceIdentifier
                )
                if subs.isEmpty {
                    subs = [" "]
                }
                counts.append(subs.count)
                flat.append(contentsOf: subs)
            }
            segments = flat
            storyBlockUtteranceCounts = counts
        } else if let forced = forcedParagraphSegments {
            let trimmed = forced
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !trimmed.isEmpty else {
                throw PreviewError.emptyNarration
            }
            segments = cappedPreviewSegments(from: trimmed, maximumDuration: maximumDuration)
        } else {
            guard !normalized.isEmpty else {
                throw PreviewError.emptyNarration
            }
            // Same utterance rules as Edit Story: one logical “block” = whole script here.
            var allSegments = StoryScriptPartition.narrationSegmentsWholeScriptStyle(
                blockText: normalized,
                voiceIdentifier: voiceIdentifier
            )
            if allSegments.isEmpty {
                allSegments = SpeechVoiceLibrary.narrationSegments(from: normalized, optimizeForLongForm: true)
            }
            let capped = cappedPreviewSegments(from: allSegments, maximumDuration: maximumDuration)
            // Capped previews (~20s sample) stay under `maxSynthesisSegments`. Full-length previews must **not**
            // merge: that audio is muxed into final export when Edit Story is off, and must match utterance
            // boundaries from `narrationSegmentsWholeScriptStyle`—same as Edit-on export (no preview bypass).
            let forSynthesis = maximumDuration == nil ? capped : Self.mergedPreviewSegments(capped)
            segments = forSynthesis
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        guard !segments.isEmpty else {
            throw PreviewError.emptyNarration
        }

        let workspace = try makeWorkspace()
        let outputAudioURL = workspace.appendingPathComponent("narration-preview.m4a")
        let outputJSONURL = workspace.appendingPathComponent("narration-preview.json")

        var utteranceURLs: [URL] = []
        var utteranceDurations: [TimeInterval] = []

        for (index, segment) in segments.enumerated() {
            let completion = Double(index) / Double(max(segments.count, 1))
            progressHandler?(completion * 0.72, "Rendering narration segment \(index + 1) of \(segments.count).")
            let utterance = SpeechVoiceLibrary.makeUtterance(
                from: segment,
                voiceIdentifier: voiceIdentifier,
                speechRateMultiplier: speechRateMultiplier
            )
            let utteranceURL = workspace.appendingPathComponent("utterance-preview-\(index).caf")
            let duration = try await renderUtteranceAudio(utterance, outputURL: utteranceURL)
            utteranceURLs.append(utteranceURL)
            utteranceDurations.append(duration)
        }

        let measuredDuration = max(utteranceDurations.reduce(0, +), 1)
        var playbackCursor: TimeInterval = 0
        var paragraphPlaybackRanges: [(start: TimeInterval, end: TimeInterval)] = []
        if let counts = storyBlockUtteranceCounts {
            var u = 0
            for c in counts {
                let blockDur = (u..<(u + c)).reduce(0.0) { partial, j in
                    partial + utteranceDurations[j]
                }
                u += c
                let end = playbackCursor + blockDur
                paragraphPlaybackRanges.append((start: playbackCursor, end: end))
                playbackCursor = end
            }
        } else {
            paragraphPlaybackRanges.reserveCapacity(utteranceDurations.count)
            for d in utteranceDurations {
                let end = playbackCursor + d
                paragraphPlaybackRanges.append((start: playbackCursor, end: end))
                playbackCursor = end
            }
        }
        progressHandler?(0.8, "Combining narration audio.")
        try await mergeAudioFiles(utteranceURLs, outputURL: outputAudioURL)
        progressHandler?(0.92, "Building caption cues.")
        let cues = buildCues(
            segments: segments,
            utteranceDurations: utteranceDurations,
            totalDuration: measuredDuration,
            voiceIdentifier: voiceIdentifier
        )
        try writeCues(cues, to: outputJSONURL)
        progressHandler?(1.0, "Narration preview is ready.")

        return PreviewResult(
            audioURL: outputAudioURL,
            subtitleJSONURL: outputJSONURL,
            cues: cues,
            duration: measuredDuration,
            paragraphPlaybackRanges: paragraphPlaybackRanges
        )
    }

    /// Merges adjacent segments so preview synthesis stays under `NarrationPreviewLimits.maxSynthesisSegments`.
    private static func mergedPreviewSegments(_ segments: [String]) -> [String] {
        guard segments.count > NarrationPreviewLimits.maxSynthesisSegments else { return segments }

        let batch = Int(
            ceil(Double(segments.count) / Double(NarrationPreviewLimits.maxSynthesisSegments))
        )
        var out: [String] = []
        var i = 0
        while i < segments.count {
            let end = min(i + batch, segments.count)
            var piece = segments[i..<end].joined(separator: " ")
            if piece.count > NarrationPreviewLimits.maxCharactersPerPreviewChunk {
                piece = String(piece.prefix(NarrationPreviewLimits.maxCharactersPerPreviewChunk))
            }
            out.append(piece)
            i = end
        }
        return out
    }

    private func cappedPreviewSegments(from segments: [String], maximumDuration: TimeInterval?) -> [String] {
        guard let maximumDuration else { return segments }
        let expanded = segments.flatMap { segment in
            PreviewNarrationSegmentBudget.splitToFitEstimatedBudget(
                segment,
                maxEstimatedSeconds: maximumDuration,
                estimate: { estimatedSeconds(for: $0) }
            )
        }
        var selected: [String] = []
        var accumulated: TimeInterval = 0
        for segment in expanded {
            let estimated = estimatedSeconds(for: segment)
            if !selected.isEmpty, accumulated + estimated > maximumDuration {
                break
            }
            selected.append(segment)
            accumulated += estimated
        }
        return selected
    }

    private func makeWorkspace() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let workspace = documents.appendingPathComponent("NarrationPreview", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return workspace
    }

    private func renderUtteranceAudio(_ utterance: AVSpeechUtterance, outputURL: URL) async throws -> TimeInterval {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let synthesizer = AVSpeechSynthesizer()
        let resumeState = PreviewSynthesisResumeState()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TimeInterval, Error>) in
            var audioFile: AVAudioFile?

            let timeoutWorkItem = DispatchWorkItem {
                resumeState.resumeTimeout(continuation)
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + NarrationPreviewLimits.perSegmentTimeoutSeconds,
                execute: timeoutWorkItem
            )

            synthesizer.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

                do {
                    if pcmBuffer.frameLength == 0 {
                        let sampleRate = audioFile?.processingFormat.sampleRate ?? 44_100
                        let length = audioFile?.length ?? 0
                        let duration = sampleRate > 0 ? Double(length) / sampleRate : 0
                        timeoutWorkItem.cancel()
                        resumeState.resumeSuccess(continuation, returning: duration)
                        return
                    }

                    if audioFile == nil {
                        audioFile = try AVAudioFile(forWriting: outputURL, settings: pcmBuffer.format.settings)
                    }

                    try audioFile?.write(from: pcmBuffer)
                } catch {
                    timeoutWorkItem.cancel()
                    resumeState.resumeFailure(continuation, error: error)
                }
            }
        }
    }

    private func mergeAudioFiles(_ urls: [URL], outputURL: URL) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw PreviewError.audioTrackCreationFailed
        }

        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let assetTrack = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let duration = try await asset.load(.duration)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: assetTrack, at: cursor)
            cursor = cursor + duration
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw PreviewError.exportFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        await exportSession.export()

        if let error = exportSession.error {
            throw error
        }

        guard exportSession.status == .completed else {
            throw PreviewError.exportFailed
        }
    }

    private func buildCues(
        segments: [String],
        utteranceDurations: [TimeInterval],
        totalDuration: TimeInterval,
        voiceIdentifier: String
    ) -> [SubtitleCue] {
        let voiceTag = SpeechVoiceLibrary.voiceLanguageTag(forVoiceIdentifier: voiceIdentifier)
        if SpeechVoiceLibrary.usesSentenceAlignedNarration(voiceLanguageTag: voiceTag) {
            return buildSentenceAlignedCues(
                segments: segments,
                utteranceDurations: utteranceDurations,
                totalDuration: totalDuration,
                voiceIdentifier: voiceIdentifier
            )
        }

        var cues: [SubtitleCue] = []
        var cursor: TimeInterval = 0

        for (index, segment) in segments.enumerated() {
            let chunks = captionChunks(for: segment, voiceIdentifier: voiceIdentifier)
            guard !chunks.isEmpty else { continue }

            let utteranceDuration = index < utteranceDurations.count ? utteranceDurations[index] : estimatedSeconds(for: segment)
            let totalChunkWeight = max(chunks.reduce(0) { $0 + $1.weight }, 0.1)

            for chunk in chunks {
                let duration = max((utteranceDuration * chunk.weight) / totalChunkWeight, minimumCueDuration(for: chunk.text))
                let start = cursor
                let end = min(cursor + duration, totalDuration)
                cues.append(SubtitleCue(text: SpeechVoiceLibrary.normalizedCaptionText(chunk.text), start: start, end: end))
                cursor = end
            }
        }

        if let lastIndex = cues.indices.last {
            cues[lastIndex] = SubtitleCue(
                id: cues[lastIndex].id,
                text: cues[lastIndex].text,
                start: cues[lastIndex].start,
                end: max(cues[lastIndex].end, totalDuration)
            )
        }

        return cues
    }

    /// One cue per TTS utterance; cue text follows **`splitForCaptions`** rows (phrase-aligned with speech).
    /// Cue **[start, end)** tracks **measured** TTS duration per segment (same as muxed audio). We do **not** apply a
    /// minimum display floor here—**`max(utterance, minimumCue)`** advanced the subtitle clock faster than speech,
    /// so prepared-preview export captions drifted behind narration while Edit-on (re-synth) stayed aligned.
    private func buildSentenceAlignedCues(
        segments: [String],
        utteranceDurations: [TimeInterval],
        totalDuration: TimeInterval,
        voiceIdentifier: String
    ) -> [SubtitleCue] {
        let tag = SpeechVoiceLibrary.voiceLanguageTag(forVoiceIdentifier: voiceIdentifier)
        var cues: [SubtitleCue] = []
        var cursor: TimeInterval = 0

        for (index, segment) in segments.enumerated() {
            let utteranceDuration = index < utteranceDurations.count ? utteranceDurations[index] : estimatedSeconds(for: segment)
            let text = SpeechVoiceLibrary.normalizedCaptionText(segment)
            if text.isEmpty {
                cursor = min(cursor + utteranceDuration, totalDuration)
                continue
            }

            let start = cursor
            let end = min(cursor + utteranceDuration, totalDuration)
            let lines = CaptionTextChunker.splitForCaptions(normalizedText: text, voiceLanguageTag: tag)
            let shown: String
            if lines.count > 1 {
                shown = CaptionTextChunker.strippedCaptionForDisplay(
                    lines.map { CaptionTextChunker.displayCaptionLine(for: $0) }.joined(separator: "\n")
                )
            } else {
                shown = CaptionTextChunker.strippedCaptionForDisplay(CaptionTextChunker.displayCaptionLine(for: text))
            }
            cues.append(SubtitleCue(text: shown, start: start, end: end))
            cursor = min(cursor + utteranceDuration, totalDuration)
        }

        if let lastIndex = cues.indices.last {
            cues[lastIndex] = SubtitleCue(
                id: cues[lastIndex].id,
                text: cues[lastIndex].text,
                start: cues[lastIndex].start,
                end: max(cues[lastIndex].end, totalDuration)
            )
        }

        return cues
    }

    private func captionChunks(for segment: String, voiceIdentifier: String) -> [CueChunk] {
        let normalizedSegment = SpeechVoiceLibrary.normalizedCaptionText(segment)
        let tag = SpeechVoiceLibrary.voiceLanguageTag(forVoiceIdentifier: voiceIdentifier)
        let pieces = CaptionTextChunker.splitForCaptions(normalizedText: normalizedSegment, voiceLanguageTag: tag)
        return pieces.map { piece in
            let display = CaptionTextChunker.displayCaptionLine(for: piece)
            let weight: Double
            if SpeechVoiceLibrary.containsCJKContent(in: SpeechVoiceLibrary.normalizedTimingText(piece)) {
                weight = cjkWeight(for: piece)
            } else {
                weight = englishWeight(for: piece)
            }
            return CueChunk(text: display, weight: weight)
        }
    }

    private func englishWeight(for text: String) -> Double {
        let timingText = SpeechVoiceLibrary.normalizedTimingText(text)
        let words = timingText.split(whereSeparator: \.isWhitespace)
        return max(Double(words.count), 1.0)
    }

    private func cjkWeight(for text: String) -> Double {
        let timingText = SpeechVoiceLibrary.normalizedTimingText(text)
        return max(Double(timingText.count) * 0.6, 1.0)
    }

    private func estimatedSeconds(for text: String) -> TimeInterval {
        let timingText = SpeechVoiceLibrary.normalizedTimingText(text)
        if timingText.contains(where: isCJK) {
            return max(Double(timingText.count) / 3.6, 0.8)
        }
        let words = timingText.split(whereSeparator: \.isWhitespace)
        return max(Double(words.count) / 2.4, 0.8)
    }

    private func minimumCueDuration(for text: String) -> TimeInterval {
        SpeechVoiceLibrary.normalizedTimingText(text).contains(where: isCJK) ? 0.9 : 0.7
    }

    private func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value)) ||
            (0x3400...0x4DBF).contains(Int(scalar.value))
        }
    }

    private func writeCues(_ cues: [SubtitleCue], to url: URL) throws {
        try SubtitleTimelineEngine.save(cues, to: url)
    }

    enum PreviewError: LocalizedError {
        case emptyNarration
        case audioTrackCreationFailed
        case exportFailed
        case segmentSynthesisTimedOut

        var errorDescription: String? {
            switch self {
            case .emptyNarration:
                return "Add narration text before building the preview."
            case .audioTrackCreationFailed:
                return "Could not create the narration preview track."
            case .exportFailed:
                return "Could not export the narration preview audio."
            case .segmentSynthesisTimedOut:
                return "Narration preview stopped waiting for speech output. Try a shorter script, a different voice, or build again."
            }
        }
    }
}

import AVFoundation
import Foundation

@MainActor
struct NarrationPreviewBuilder {
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
    }

    private struct CueChunk {
        let text: String
        let weight: Double
    }

    func buildPreview(text: String, voiceIdentifier: String) async throws -> PreviewResult {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = SpeechVoiceLibrary.narrationSegments(from: normalized, optimizeForLongForm: true)
        guard !segments.isEmpty else {
            throw PreviewError.emptyNarration
        }

        let workspace = try makeWorkspace()
        let outputAudioURL = workspace.appendingPathComponent("narration-preview.m4a")
        let outputJSONURL = workspace.appendingPathComponent("narration-preview.json")

        var utteranceURLs: [URL] = []
        var utteranceDurations: [TimeInterval] = []

        for (index, segment) in segments.enumerated() {
            let utterance = SpeechVoiceLibrary.makeUtterance(from: segment, voiceIdentifier: voiceIdentifier)
            let utteranceURL = workspace.appendingPathComponent("utterance-preview-\(index).caf")
            let duration = try await renderUtteranceAudio(utterance, outputURL: utteranceURL)
            utteranceURLs.append(utteranceURL)
            utteranceDurations.append(duration)
        }

        let measuredDuration = max(utteranceDurations.reduce(0, +), 1)
        try await mergeAudioFiles(utteranceURLs, outputURL: outputAudioURL)
        let cues = buildCues(segments: segments, utteranceDurations: utteranceDurations, totalDuration: measuredDuration)
        try writeCues(cues, to: outputJSONURL)

        return PreviewResult(
            audioURL: outputAudioURL,
            subtitleJSONURL: outputJSONURL,
            cues: cues,
            duration: measuredDuration
        )
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

        return try await withCheckedThrowingContinuation { continuation in
            var audioFile: AVAudioFile?
            var finished = false

            synthesizer.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

                do {
                    if pcmBuffer.frameLength == 0 {
                        let sampleRate = audioFile?.processingFormat.sampleRate ?? 44_100
                        let length = audioFile?.length ?? 0
                        let duration = sampleRate > 0 ? Double(length) / sampleRate : 0
                        if !finished {
                            finished = true
                            continuation.resume(returning: duration)
                        }
                        return
                    }

                    if audioFile == nil {
                        audioFile = try AVAudioFile(forWriting: outputURL, settings: pcmBuffer.format.settings)
                    }

                    try audioFile?.write(from: pcmBuffer)
                } catch {
                    if !finished {
                        finished = true
                        continuation.resume(throwing: error)
                    }
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

    private func buildCues(segments: [String], utteranceDurations: [TimeInterval], totalDuration: TimeInterval) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var cursor: TimeInterval = 0

        for (index, segment) in segments.enumerated() {
            let chunks = captionChunks(for: segment)
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

    private func captionChunks(for segment: String) -> [CueChunk] {
        let normalizedSegment = SpeechVoiceLibrary.normalizedCaptionText(segment)
        let phrases = normalizedSegment
            .components(separatedBy: CharacterSet(charactersIn: ",，、"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let source = phrases.isEmpty ? [normalizedSegment] : phrases
        return source.flatMap { phrase in
            if phrase.contains(" ") {
                let words = phrase.split(whereSeparator: \.isWhitespace).map(String.init)
                if words.count <= 10 {
                    return [CueChunk(text: balancedCaption(phrase), weight: englishWeight(for: phrase))]
                }

                var chunks: [CueChunk] = []
                var index = 0
                while index < words.count {
                    let end = min(index + 10, words.count)
                    let chunk = words[index..<end].joined(separator: " ")
                    chunks.append(CueChunk(text: balancedCaption(chunk), weight: englishWeight(for: chunk)))
                    index = end
                }
                return chunks
            } else {
                let characters = Array(phrase)
                if characters.count <= 12 {
                    return [CueChunk(text: phrase, weight: cjkWeight(for: phrase))]
                }

                var chunks: [CueChunk] = []
                var index = 0
                while index < characters.count {
                    let end = min(index + 12, characters.count)
                    let chunk = String(characters[index..<end])
                    chunks.append(CueChunk(text: chunk, weight: cjkWeight(for: chunk)))
                    index = end
                }
                return chunks
            }
        }
    }

    private func balancedCaption(_ text: String) -> String {
        let normalizedText = SpeechVoiceLibrary.normalizedCaptionText(text)
        let words = normalizedText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 8 else { return normalizedText }

        var bestIndex = words.count / 2
        var bestScore = Int.max
        for index in 3..<(words.count - 2) {
            let left = words[..<index].joined(separator: " ")
            let right = words[index...].joined(separator: " ")
            let score = abs(left.count - right.count)
            if score < bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return words[..<bestIndex].joined(separator: " ") + "\n" + words[bestIndex...].joined(separator: " ")
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

        var errorDescription: String? {
            switch self {
            case .emptyNarration:
                return "Add narration text before building the preview."
            case .audioTrackCreationFailed:
                return "Could not create the narration preview track."
            case .exportFailed:
                return "Could not export the narration preview audio."
            }
        }
    }
}

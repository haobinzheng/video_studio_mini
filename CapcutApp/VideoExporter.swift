import AVFoundation
import UIKit

struct VideoExporter {
    private let renderSize = CGSize(width: 1080, height: 1920)
    private let frameRate: Int32 = 30
    private let captionLagCompensation = CMTime(seconds: 0.30, preferredTimescale: 600)
    private let narrationDurationBias: Double = 1.90
    private let maximumVideoDuration = CMTime(seconds: 300, preferredTimescale: 600)

    private struct CaptionSegment {
        let text: String
        let timeRange: CMTimeRange
    }

    typealias ExternalCue = NarrationPreviewBuilder.SubtitleCue

    private struct NarrationTimeline {
        let duration: CMTime
        let captionSegments: [CaptionSegment]
        let utteranceAudioURLs: [URL]
    }

    private struct CaptionSlice {
        let text: String
        let sourceSegmentIndex: Int
        let weight: Double
        let terminalPauseWeight: Double
    }

    func exportVideo(
        images: [UIImage],
        narrationText: String,
        backgroundMusicURL: URL?,
        voiceIdentifier: String,
        externalCues: [ExternalCue] = [],
        externalNarrationAudioURL: URL? = nil
    ) async throws -> URL {
        guard !images.isEmpty else {
            throw ExportError.noPhotos
        }

        let workspace = try makeWorkspace()
        let slideshowURL = workspace.appendingPathComponent("slideshow.mov")
        let finalURL = workspace.appendingPathComponent("capcut-mini-video.mov")

        let narrationTimeline = try await synthesizeNarrationIfNeeded(
            text: narrationText,
            voiceIdentifier: voiceIdentifier,
            workspace: workspace,
            externalCues: externalCues,
            externalNarrationAudioURL: externalNarrationAudioURL
        )
        let minimumVisualDuration = CMTime(seconds: max(Double(images.count) * 1.6, 3), preferredTimescale: 600)
        let totalDuration = narrationTimeline.duration > .zero
            ? max(narrationTimeline.duration, minimumVisualDuration)
            : minimumVisualDuration

        try await renderSlideshow(
            images: images,
            captionSegments: narrationTimeline.captionSegments,
            totalDuration: totalDuration,
            outputURL: slideshowURL
        )
        try await mergeAudioAndVideo(
            videoURL: slideshowURL,
            narrationURLs: narrationTimeline.utteranceAudioURLs,
            backgroundMusicURL: backgroundMusicURL,
            totalDuration: totalDuration,
            outputURL: finalURL
        )

        return finalURL
    }

    private func makeWorkspace() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let workspace = documents.appendingPathComponent("RenderedVideos", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return workspace
    }

    @MainActor
    private func synthesizeNarrationIfNeeded(
        text: String,
        voiceIdentifier: String,
        workspace: URL,
        externalCues: [ExternalCue],
        externalNarrationAudioURL: URL?
    ) async throws -> NarrationTimeline {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !externalCues.isEmpty else {
            return NarrationTimeline(duration: .zero, captionSegments: [], utteranceAudioURLs: [])
        }

        if let externalNarrationAudioURL, !externalCues.isEmpty {
            let audioAsset = AVURLAsset(url: externalNarrationAudioURL)
            let audioDuration = try await audioAsset.load(.duration)
            let cueDuration = CMTime(seconds: externalCues.map(\.end).max() ?? 0, preferredTimescale: 600)
            let resolvedDuration = min(max(audioDuration, cueDuration, CMTime(seconds: 1, preferredTimescale: 600)), maximumVideoDuration)
            return NarrationTimeline(
                duration: resolvedDuration,
                captionSegments: captionSegments(from: externalCues),
                utteranceAudioURLs: [externalNarrationAudioURL]
            )
        }

        let narrationSegments = SpeechVoiceLibrary.narrationSegments(from: trimmedText)
        let utterances = narrationSegments.map {
            SpeechVoiceLibrary.makeUtterance(from: $0, voiceIdentifier: voiceIdentifier)
        }
        var utteranceAudioURLs: [URL] = []
        var utteranceDurations: [CMTime] = []

        for (index, utterance) in utterances.enumerated() {
            let utteranceURL = workspace.appendingPathComponent("utterance-\(index).caf")
            let duration = try await renderUtteranceAudio(utterance, outputURL: utteranceURL)
            utteranceAudioURLs.append(utteranceURL)
            utteranceDurations.append(duration)
        }

        let measuredNarrationDuration = utteranceDurations.reduce(CMTime.zero, +)
        let estimatedNarrationDuration = CMTime(
            seconds: estimatedNarrationSeconds(for: narrationSegments),
            preferredTimescale: 600
        )
        let biasedAudioDuration = CMTimeMultiplyByFloat64(measuredNarrationDuration, multiplier: narrationDurationBias)
        let totalDuration = min(
            max(biasedAudioDuration, estimatedNarrationDuration, CMTime(seconds: 1, preferredTimescale: 600)),
            maximumVideoDuration
        )
        let captionSegments = externalCues.isEmpty
            ? timedCaptionSegments(
                from: narrationSegments,
                utteranceDurations: utteranceDurations,
                totalDuration: totalDuration
            )
            : captionSegments(from: externalCues)
        let resolvedDuration = externalCues.isEmpty
            ? totalDuration
            : max(totalDuration, CMTime(seconds: externalCues.map(\.end).max() ?? 0, preferredTimescale: 600))

        return NarrationTimeline(
            duration: resolvedDuration,
            captionSegments: captionSegments,
            utteranceAudioURLs: utteranceAudioURLs
        )
    }

    @MainActor
    private func renderUtteranceAudio(_ utterance: AVSpeechUtterance, outputURL: URL) async throws -> CMTime {
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
                        let duration = Self.mediaDuration(for: audioFile)
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

    private func renderSlideshow(
        images: [UIImage],
        captionSegments: [CaptionSegment],
        totalDuration: CMTime,
        outputURL: URL
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: renderSize.width,
            AVVideoHeightKey: renderSize.height
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: renderSize.width,
                kCVPixelBufferHeightKey as String: renderSize.height
            ]
        )

        guard writer.canAdd(writerInput) else {
            throw ExportError.videoWriterSetupFailed
        }

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalFrames = max(Int(ceil(CMTimeGetSeconds(totalDuration) * Double(frameRate))), images.count)

        for frameIndex in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            let currentTime = CMTime(value: CMTimeValue(frameIndex), timescale: frameRate)
            let image = imageForTime(currentTime, images: images, totalDuration: totalDuration)
            let caption = captionText(for: currentTime, segments: captionSegments)
            let pixelBuffer = try makePixelBuffer(from: image, caption: caption)
            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: frameRate)
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        writerInput.markAsFinished()
        await finishWriting(writer: writer)

        if let error = writer.error {
            throw error
        }
    }

    private func finishWriting(writer: AVAssetWriter) async {
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }

    private func mergeAudioAndVideo(
        videoURL: URL,
        narrationURLs: [URL],
        backgroundMusicURL: URL?,
        totalDuration: CMTime,
        outputURL: URL
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)

        guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.missingVideoTrack
        }

        let videoDuration = try await videoAsset.load(.duration)
        try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: sourceVideoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        var audioMixParameters: [AVMutableAudioMixInputParameters] = []

        if !narrationURLs.isEmpty,
           let compositionNarrationTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            var narrationCursor = CMTime.zero

            for narrationURL in narrationURLs {
                let narrationAsset = AVURLAsset(url: narrationURL)
                if let narrationTrack = try await narrationAsset.loadTracks(withMediaType: .audio).first {
                    let narrationDuration = try await narrationAsset.load(.duration)
                    try compositionNarrationTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: narrationDuration),
                        of: narrationTrack,
                        at: narrationCursor
                    )
                    narrationCursor = narrationCursor + narrationDuration
                }
            }

            let narrationParameters = AVMutableAudioMixInputParameters(track: compositionNarrationTrack)
            narrationParameters.setVolume(1.0, at: .zero)
            audioMixParameters.append(narrationParameters)
        }

        if let backgroundMusicURL {
            let musicAsset = AVURLAsset(url: backgroundMusicURL)
            if let musicTrack = try await musicAsset.loadTracks(withMediaType: .audio).first,
               let compositionMusicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let musicDuration = try await musicAsset.load(.duration)
                var cursor = CMTime.zero

                while cursor < totalDuration {
                    let remaining = totalDuration - cursor
                    let segmentDuration = min(musicDuration, remaining)
                    try compositionMusicTrack.insertTimeRange(CMTimeRange(start: .zero, duration: segmentDuration), of: musicTrack, at: cursor)
                    cursor = cursor + segmentDuration
                    if musicDuration == .zero { break }
                }

                let musicParameters = AVMutableAudioMixInputParameters(track: compositionMusicTrack)
                musicParameters.setVolume(0.25, at: .zero)
                let fadeStart = CMTimeMaximum(.zero, totalDuration - CMTime(seconds: 1.2, preferredTimescale: 600))
                musicParameters.setVolumeRamp(fromStartVolume: 0.25, toEndVolume: 0.0, timeRange: CMTimeRange(start: fadeStart, duration: totalDuration - fadeStart))
                audioMixParameters.append(musicParameters)
            }
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.exportSessionFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = true

        if !audioMixParameters.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioMixParameters
            exportSession.audioMix = audioMix
        }

        await exportSession.export()

        if let error = exportSession.error {
            throw error
        }

        guard exportSession.status == .completed else {
            throw ExportError.exportFailed
        }
    }

    private func makePixelBuffer(from image: UIImage, caption: String?) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(renderSize.width),
            Int(renderSize.height),
            kCVPixelFormatType_32ARGB,
            attributes,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw ExportError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            throw ExportError.pixelBufferCreationFailed
        }

        // Use UIKit-style coordinates so images and caption text are upright.
        context.translateBy(x: 0, y: renderSize.height)
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: renderSize))

        let aspectFitRect = AVMakeRect(aspectRatio: image.size, insideRect: CGRect(origin: .zero, size: renderSize))
        UIGraphicsPushContext(context)
        image.draw(in: aspectFitRect)

        if let caption, !caption.isEmpty {
            drawCaption(caption, in: context)
        }
        UIGraphicsPopContext()

        return pixelBuffer
    }

    private func drawCaption(_ caption: String, in context: CGContext) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let maxTextWidth = renderSize.width - 180
        let maxTextHeight: CGFloat = 360
        let minimumFontSize: CGFloat = 28
        var fontSize: CGFloat = 52
        var measuredText = CGRect.zero
        var attributes: [NSAttributedString.Key: Any] = [:]

        while fontSize >= minimumFontSize {
            attributes = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]

            measuredText = (caption as NSString).boundingRect(
                with: CGSize(width: maxTextWidth, height: maxTextHeight),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            ).integral

            if measuredText.height <= maxTextHeight {
                break
            }

            fontSize -= 4
        }

        let boxPadding: CGFloat = 28
        let boxRect = CGRect(
            x: (renderSize.width - measuredText.width) / 2 - boxPadding,
            y: renderSize.height - measuredText.height - 220,
            width: measuredText.width + (boxPadding * 2),
            height: measuredText.height + (boxPadding * 2)
        )

        let boxPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 32)
        context.saveGState()
        context.setFillColor(UIColor.black.withAlphaComponent(0.58).cgColor)
        context.addPath(boxPath.cgPath)
        context.fillPath()
        context.restoreGState()

        let textRect = CGRect(
            x: (renderSize.width - measuredText.width) / 2,
            y: boxRect.minY + boxPadding,
            width: measuredText.width,
            height: measuredText.height
        )

        UIGraphicsPushContext(context)
        (caption as NSString).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        UIGraphicsPopContext()
    }

    private func captionText(for currentTime: CMTime, segments: [CaptionSegment]) -> String? {
        guard !segments.isEmpty else { return nil }

        let compensatedTime = CMTimeMaximum(.zero, currentTime - captionLagCompensation)

        for segment in segments where segment.timeRange.containsTime(compensatedTime) {
            return segment.text
        }

        if compensatedTime >= segments.last?.timeRange.end ?? .zero {
            return segments.last?.text
        }

        return segments.first?.text
    }

    private func imageForTime(_ currentTime: CMTime, images: [UIImage], totalDuration: CMTime) -> UIImage {
        guard let firstImage = images.first else {
            return UIImage()
        }
        guard images.count > 1 else {
            return firstImage
        }

        let totalSeconds = max(CMTimeGetSeconds(totalDuration), 0.1)
        let progress = min(max(CMTimeGetSeconds(currentTime) / totalSeconds, 0), 0.999_999)
        let index = min(Int(progress * Double(images.count)), images.count - 1)
        return images[index]
    }

    private static func mediaDuration(for audioFile: AVAudioFile?) -> CMTime {
        let sampleRate = audioFile?.processingFormat.sampleRate ?? 44_100
        let length = audioFile?.length ?? 0
        let seconds = sampleRate > 0 ? Double(length) / sampleRate : 0
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func captionSegments(from externalCues: [ExternalCue]) -> [CaptionSegment] {
        externalCues
            .sorted { $0.start < $1.start }
            .map {
                CaptionSegment(
                    text: formattedCaptionText($0.text),
                    timeRange: CMTimeRange(
                        start: CMTime(seconds: $0.start, preferredTimescale: 600),
                        end: CMTime(seconds: $0.end, preferredTimescale: 600)
                    )
                )
            }
    }

    private func timedCaptionSegments(
        from texts: [String],
        utteranceDurations: [CMTime],
        totalDuration: CMTime
    ) -> [CaptionSegment] {
        guard !texts.isEmpty else { return [] }

        let slices = makeCaptionSlices(from: texts)
        guard !slices.isEmpty else { return [] }

        let sourceWeights = sourceSegmentWeights(from: texts)
        let totalSourceWeight = max(sourceWeights.reduce(0.0, +), 0.1)
        let totalSeconds = CMTimeGetSeconds(totalDuration)
        var cursor = CMTime.zero
        var segments: [CaptionSegment] = []

        for sourceIndex in texts.indices {
            let group = slices.filter { $0.sourceSegmentIndex == sourceIndex }
            guard !group.isEmpty else { continue }

            let sourceBudget = sourceIndex < utteranceDurations.count
                ? CMTimeGetSeconds(utteranceDurations[sourceIndex]) * narrationDurationBias
                : totalSeconds * (sourceWeights[sourceIndex] / totalSourceWeight)
            let groupWeight = max(group.reduce(0.0) { $0 + $1.weight + $1.terminalPauseWeight }, 0.1)

            for slice in group {
                let share = (slice.weight + slice.terminalPauseWeight) / groupWeight
                var duration = CMTime(
                    seconds: max(sourceBudget * share, minimumCaptionSeconds(for: slice.text)),
                    preferredTimescale: 600
                )
                let remaining = totalDuration - cursor
                if duration > remaining, remaining > .zero {
                    duration = remaining
                }

                let timeRange = CMTimeRange(start: cursor, duration: duration)
                segments.append(CaptionSegment(text: formattedCaptionText(slice.text), timeRange: timeRange))
                cursor = cursor + duration
            }
        }

        if segments.isEmpty {
            return [CaptionSegment(text: formattedCaptionText(texts.joined(separator: " ")), timeRange: CMTimeRange(start: .zero, duration: totalDuration))]
        }

        if let lastIndex = segments.indices.last {
            let last = segments[lastIndex]
            segments[lastIndex] = CaptionSegment(
                text: last.text,
                timeRange: CMTimeRange(start: last.timeRange.start, end: totalDuration)
            )
        }

        return segments
    }

    private func splitCaptionText(_ text: String) -> [String] {
        let normalized = SpeechVoiceLibrary.normalizedCaptionText(text)
        guard !normalized.isEmpty else { return [] }

        let phraseSeparators = CharacterSet(charactersIn: ",，、:：")
        let phrases = normalized.components(separatedBy: phraseSeparators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sourcePhrases = phrases.isEmpty ? [normalized] : phrases
        return sourcePhrases.flatMap { phrase in
            if phrase.contains(" ") {
                return splitWordPhrase(phrase, maxWords: 12)
            } else {
                return splitCharacterPhrase(phrase, maxCharacters: 10)
            }
        }
    }

    private func splitWordPhrase(_ phrase: String, maxWords: Int) -> [String] {
        let words = phrase.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > maxWords else { return [phrase] }

        var chunks: [String] = []
        var index = 0
        while index < words.count {
            let end = min(index + maxWords, words.count)
            chunks.append(words[index..<end].joined(separator: " "))
            index = end
        }
        return chunks
    }

    private func splitCharacterPhrase(_ phrase: String, maxCharacters: Int) -> [String] {
        guard phrase.count > maxCharacters else { return [phrase] }

        var chunks: [String] = []
        var current = ""
        for character in phrase {
            current.append(character)
            if current.count >= maxCharacters {
                chunks.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private func formattedCaptionText(_ text: String) -> String {
        let normalizedText = SpeechVoiceLibrary.normalizedCaptionText(text)
        guard normalizedText.contains(" ") else { return normalizedText }

        let words = normalizedText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 6 else { return normalizedText }

        var bestIndex = words.count / 2
        var bestScore = Int.max

        for index in 2..<(words.count - 1) {
            let left = words[..<index].joined(separator: " ")
            let right = words[index...].joined(separator: " ")
            let score = abs(left.count - right.count)
            if score < bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        let firstLine = words[..<bestIndex].joined(separator: " ")
        let secondLine = words[bestIndex...].joined(separator: " ")
        return "\(firstLine)\n\(secondLine)"
    }

    private func makeCaptionSlices(from texts: [String]) -> [CaptionSlice] {
        texts.enumerated().flatMap { index, text in
            let chunks = splitCaptionText(text)
            return chunks.enumerated().map { chunkIndex, chunk in
                CaptionSlice(
                    text: chunk,
                    sourceSegmentIndex: index,
                    weight: speechWeight(for: chunk),
                    terminalPauseWeight: chunkIndex == chunks.count - 1 ? terminalPauseWeight(for: text) : 0
                )
            }
        }
    }

    private func sourceSegmentWeights(from texts: [String]) -> [Double] {
        texts.map { speechWeight(for: $0) + terminalPauseWeight(for: $0) }
    }

    private func speechWeight(for text: String) -> Double {
        if containsCJK(text) {
            let cjkCharacters = Double(text.filter { isCJK($0) }.count)
            let latinCharacters = Double(text.filter { $0.isASCII && $0.isLetter }.count)
            let punctuation = Double(text.filter { "，。、！？；：".contains($0) }.count)
            return max((cjkCharacters * 1.15) + (latinCharacters * 0.35) + (punctuation * 1.4), 1.0)
        }

        let words = text.split(whereSeparator: \.isWhitespace)
        let syllables = Double(words.reduce(0) { $0 + approximateSyllableCount(in: String($1)) })
        let punctuation = Double(text.filter { ",.!?;:".contains($0) }.count)
        return max((Double(words.count) * 1.1) + (syllables * 0.55) + (punctuation * 1.6), 1.0)
    }

    private func estimatedNarrationSeconds(for texts: [String]) -> Double {
        texts.reduce(0.0) { $0 + estimatedSecondsForSegment($1) }
    }

    private func estimatedSecondsForSegment(_ text: String) -> Double {
        if containsCJK(text) {
            let cjkCharacters = Double(text.filter { isCJK($0) }.count)
            let punctuation = Double(text.filter { "，。、！？；：".contains($0) }.count)
            return max((cjkCharacters / 3.6) + (punctuation * 0.34), 0.9)
        }

        let words = text.split(whereSeparator: \.isWhitespace)
        let syllables = Double(words.reduce(0) { $0 + approximateSyllableCount(in: String($1)) })
        let punctuation = Double(text.filter { ",.!?;:".contains($0) }.count)
        return max((Double(words.count) / 2.25) + (syllables * 0.06) + (punctuation * 0.18), 0.9)
    }

    private func minimumCaptionSeconds(for text: String) -> Double {
        containsCJK(text) ? 0.95 : 0.85
    }

    private func terminalPauseWeight(for text: String) -> Double {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return 0.4 }
        switch last {
        case ".", "!", "?", "。", "！", "？":
            return 2.4
        case ",", ";", ":", "，", "；", "：", "、":
            return 1.2
        default:
            return 0.4
        }
    }

    private func containsCJK(_ text: String) -> Bool {
        text.contains(where: isCJK)
    }

    private func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value)) ||
            (0x3400...0x4DBF).contains(Int(scalar.value)) ||
            (0x3040...0x30FF).contains(Int(scalar.value)) ||
            (0xAC00...0xD7AF).contains(Int(scalar.value))
        }
    }

    private func approximateSyllableCount(in word: String) -> Int {
        let lowered = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard !lowered.isEmpty else { return 1 }

        let vowels = Set("aeiouy")
        var count = 0
        var previousWasVowel = false

        for character in lowered {
            let isVowel = vowels.contains(character)
            if isVowel && !previousWasVowel {
                count += 1
            }
            previousWasVowel = isVowel
        }

        if lowered.hasSuffix("e"), count > 1 {
            count -= 1
        }

        return max(count, 1)
    }

    enum ExportError: LocalizedError {
        case noPhotos
        case videoWriterSetupFailed
        case pixelBufferCreationFailed
        case missingVideoTrack
        case exportSessionFailed
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .noPhotos:
                return "Pick at least one photo before creating a video."
            case .videoWriterSetupFailed:
                return "Video writer setup failed."
            case .pixelBufferCreationFailed:
                return "Could not render a video frame."
            case .missingVideoTrack:
                return "Generated video track is missing."
            case .exportSessionFailed:
                return "Could not create the export session."
            case .exportFailed:
                return "Video export did not complete."
            }
        }
    }
}

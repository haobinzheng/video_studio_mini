import AVFoundation
import UIKit

struct VideoExporter {
    private let renderSize = CGSize(width: 1080, height: 1920)
    private let frameRate: Int32 = 30
    private let captionLagCompensation = CMTime(seconds: 0.45, preferredTimescale: 600)
    private let narrationDurationBias: Double = 1.12
    private let maximumVideoDuration = CMTime(seconds: 300, preferredTimescale: 600)

    private struct CaptionSegment {
        let text: String
        let timeRange: CMTimeRange
    }

    private struct NarrationTimeline {
        let duration: CMTime
        let captionSegments: [CaptionSegment]
    }

    func exportVideo(
        images: [UIImage],
        narrationText: String,
        backgroundMusicURL: URL?,
        voiceIdentifier: String
    ) async throws -> URL {
        guard !images.isEmpty else {
            throw ExportError.noPhotos
        }

        let workspace = try makeWorkspace()
        let narrationURL = workspace.appendingPathComponent("narration.caf")
        let slideshowURL = workspace.appendingPathComponent("slideshow.mov")
        let finalURL = workspace.appendingPathComponent("capcut-mini-video.mov")

        let narrationTimeline = try await synthesizeNarrationIfNeeded(
            text: narrationText,
            voiceIdentifier: voiceIdentifier,
            outputURL: narrationURL
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
            narrationURL: narrationTimeline.duration.seconds > 0 ? narrationURL : nil,
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
    private func synthesizeNarrationIfNeeded(text: String, voiceIdentifier: String, outputURL: URL) async throws -> NarrationTimeline {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return NarrationTimeline(duration: .zero, captionSegments: [])
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let synthesizer = AVSpeechSynthesizer()
        let narrationSegments = SpeechVoiceLibrary.narrationSegments(from: trimmedText)
        let utterances = narrationSegments.map {
            SpeechVoiceLibrary.makeUtterance(from: $0, voiceIdentifier: voiceIdentifier)
        }

        return try await withCheckedThrowingContinuation { continuation in
            var audioFile: AVAudioFile?
            var utteranceIndex = 0
            var finished = false

            func writeNextUtterance() {
                guard utteranceIndex < utterances.count else {
                    let audioDuration = mediaDuration(for: audioFile)
                    let biasedAudioDuration = CMTimeMultiplyByFloat64(audioDuration, multiplier: narrationDurationBias)
                    let totalDuration = min(max(biasedAudioDuration, CMTime(seconds: 1, preferredTimescale: 600)), maximumVideoDuration)
                    let captionSegments = timedCaptionSegments(
                        from: narrationSegments,
                        totalDuration: totalDuration,
                        measuredDurations: []
                    )
                    if !finished {
                        finished = true
                        continuation.resume(returning: NarrationTimeline(duration: totalDuration, captionSegments: captionSegments))
                    }
                    return
                }

                let utterance = utterances[utteranceIndex]
                utteranceIndex += 1

                synthesizer.write(utterance) { buffer in
                    guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

                    do {
                        if pcmBuffer.frameLength == 0 {
                            writeNextUtterance()
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

            writeNextUtterance()
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
        narrationURL: URL?,
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

        if let narrationURL {
            let narrationAsset = AVURLAsset(url: narrationURL)
            if let narrationTrack = try await narrationAsset.loadTracks(withMediaType: .audio).first,
               let compositionNarrationTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let narrationDuration = try await narrationAsset.load(.duration)
                try compositionNarrationTrack.insertTimeRange(CMTimeRange(start: .zero, duration: narrationDuration), of: narrationTrack, at: .zero)
                let narrationParameters = AVMutableAudioMixInputParameters(track: compositionNarrationTrack)
                narrationParameters.setVolume(1.0, at: .zero)
                audioMixParameters.append(narrationParameters)
            }
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

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 52, weight: .semibold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph
        ]

        let maxTextWidth = renderSize.width - 180
        let measuredText = (caption as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: 220),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).integral

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

    private func mediaDuration(for audioFile: AVAudioFile?) -> CMTime {
        let sampleRate = audioFile?.processingFormat.sampleRate ?? 44_100
        let length = audioFile?.length ?? 0
        let seconds = sampleRate > 0 ? Double(length) / sampleRate : 0
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func timedCaptionSegments(
        from texts: [String],
        totalDuration: CMTime,
        measuredDurations: [CMTime]
    ) -> [CaptionSegment] {
        guard !texts.isEmpty else { return [] }

        let validDurations = measuredDurations.count == texts.count ? measuredDurations : estimatedDurations(for: texts, totalDuration: totalDuration)
        let summedDuration = validDurations.reduce(CMTime.zero, +)
        let scale = summedDuration > .zero ? CMTimeGetSeconds(totalDuration) / CMTimeGetSeconds(summedDuration) : 1.0

        var cursor = CMTime.zero
        var segments: [CaptionSegment] = []

        for (index, text) in texts.enumerated() {
            var duration = validDurations[index]
            if scale.isFinite, scale > 0 {
                duration = CMTimeMultiplyByFloat64(duration, multiplier: scale)
            }
            if duration <= .zero {
                duration = CMTime(seconds: max(CMTimeGetSeconds(totalDuration) / Double(texts.count), 0.6), preferredTimescale: 600)
            }

            let timeRange = CMTimeRange(start: cursor, duration: duration)
            segments.append(CaptionSegment(text: text, timeRange: timeRange))
            cursor = cursor + duration
        }

        if let lastIndex = segments.indices.last, cursor < totalDuration {
            let last = segments[lastIndex]
            segments[lastIndex] = CaptionSegment(
                text: last.text,
                timeRange: CMTimeRange(start: last.timeRange.start, end: totalDuration)
            )
        }

        return segments
    }

    private func estimatedDurations(for texts: [String], totalDuration: CMTime) -> [CMTime] {
        let totalWeight = max(texts.reduce(0.0) { $0 + estimatedWeight(for: $1) }, 1.0)
        return texts.map { text in
            let share = estimatedWeight(for: text) / totalWeight
            return CMTime(seconds: CMTimeGetSeconds(totalDuration) * share, preferredTimescale: 600)
        }
    }

    private func estimatedWeight(for text: String) -> Double {
        let characterWeight = Double(text.count)
        let punctuationBonus = Double(text.filter { ".,!?;:，。！？；：、".contains($0) }.count) * 2.5
        return max(characterWeight + punctuationBonus, 1.0)
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

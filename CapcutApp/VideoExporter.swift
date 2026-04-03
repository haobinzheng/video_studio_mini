import AVFoundation
import UIKit

struct VideoExporter {
    enum TimingMode: String, CaseIterable, Identifiable {
        case video = "Video"
        case story = "Story"
        case realLife = "Real-Life"

        var id: String { rawValue }
    }

    enum AspectRatio: String, CaseIterable, Identifiable {
        case vertical = "9:16"
        case classic = "4:3"

        var id: String { rawValue }

        var renderSize: CGSize {
            switch self {
            case .vertical:
                return CGSize(width: 720, height: 1280)
            case .classic:
                return CGSize(width: 960, height: 720)
            }
        }
    }

    enum RenderQuality {
        case preview
        case finalStandard
        case finalHigh

        var outputFileName: String {
            switch self {
            case .preview:
                return "capcut-mini-preview.mov"
            case .finalStandard, .finalHigh:
                return "capcut-mini-video.mov"
            }
        }

        var frameRate: Int32 {
            switch self {
            case .preview:
                return 8
            case .finalStandard:
                return 10
            case .finalHigh:
                return 12
            }
        }

        var maximumDuration: CMTime? {
            switch self {
            case .preview:
                return CMTime(seconds: 20, preferredTimescale: 600)
            case .finalStandard, .finalHigh:
                return nil
            }
        }

        func renderSize(for aspectRatio: AspectRatio) -> CGSize {
            switch (self, aspectRatio) {
            case (.preview, .vertical):
                return CGSize(width: 540, height: 960)
            case (.preview, .classic):
                return CGSize(width: 720, height: 540)
            case (.finalStandard, .vertical):
                return CGSize(width: 720, height: 1280)
            case (.finalStandard, .classic):
                return CGSize(width: 960, height: 720)
            case (.finalHigh, .vertical):
                return CGSize(width: 900, height: 1600)
            case (.finalHigh, .classic):
                return CGSize(width: 1200, height: 900)
            }
        }
    }

    enum FinalExportQuality: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case high = "High"

        var id: String { rawValue }

        var renderQuality: RenderQuality {
            switch self {
            case .standard:
                return .finalStandard
            case .high:
                return .finalHigh
            }
        }
    }

    struct MediaItem {
        enum Kind {
            case photo
            case video(url: URL, duration: CMTime)
        }

        let previewImage: UIImage
        let kind: Kind
    }

    private let captionLagCompensation = CMTime(seconds: 0.30, preferredTimescale: 600)
    private let narrationDurationBias: Double = 1.90

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

    private struct TimelineSegment {
        let mediaItem: MediaItem
        let timeRange: CMTimeRange
    }

    private struct RenderProfile {
        let renderSize: CGSize
        let frameRate: Int32
        let longFormOptimized: Bool
        let videoSampleStride: Int32
    }

    private struct VideoPressure {
        let totalVideoSeconds: Double
        let longestClipSeconds: Double
        let clipCount: Int
    }

    private struct StitchedVideoSegmentLayout {
        let timeRange: CMTimeRange
        let preferredTransform: CGAffineTransform
        let naturalSize: CGSize
    }

    private final class VideoFrameCache {
        private struct CachedFrame {
            let key: String
            let image: UIImage
        }

        private let frameRate: Int32
        private let renderSize: CGSize
        private let sampleStride: Int32
        private var generators: [URL: AVAssetImageGenerator] = [:]
        private var durations: [URL: CMTime] = [:]
        private var cachedFramesByURL: [URL: CachedFrame] = [:]

        init(frameRate: Int32, renderSize: CGSize, sampleStride: Int32) {
            self.frameRate = frameRate
            self.renderSize = renderSize
            self.sampleStride = max(sampleStride, 1)
        }

        func image(for url: URL, localTime: CMTime) async throws -> UIImage {
            let cacheKey = sampledFrameCacheKey(for: url, localTime: localTime)
            if let cachedFrame = cachedFramesByURL[url], cachedFrame.key == cacheKey {
                return cachedFrame.image
            }

            let generator = try await generatorForVideo(at: url)
            let assetDuration = durations[url] ?? .zero
            let frameStep = CMTime(value: 1, timescale: frameRate)
            let latestFrameTime = assetDuration > frameStep ? assetDuration - frameStep : .zero
            let sampledTime = sampledLocalTime(for: localTime)
            let safeTime = CMTimeMinimum(CMTimeMaximum(.zero, sampledTime), latestFrameTime)

            var actualTime = CMTime.zero
            let cgImage = try generator.copyCGImage(at: safeTime, actualTime: &actualTime)
            let image = UIImage(cgImage: cgImage)
            cachedFramesByURL[url] = CachedFrame(key: cacheKey, image: image)
            return image
        }

        private func generatorForVideo(at url: URL) async throws -> AVAssetImageGenerator {
            if let generator = generators[url] {
                return generator
            }

            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = renderSize
            let frameStep = CMTime(value: 1, timescale: frameRate)
            generator.requestedTimeToleranceBefore = frameStep
            generator.requestedTimeToleranceAfter = frameStep

            generators[url] = generator
            durations[url] = try await asset.load(.duration)
            return generator
        }

        private func sampledLocalTime(for localTime: CMTime) -> CMTime {
            let sampledRate = max(frameRate / sampleStride, 1)
            let seconds = CMTimeGetSeconds(localTime)
            guard seconds.isFinite else { return .zero }
            let sampledSeconds = (seconds * Double(sampledRate)).rounded(.down) / Double(sampledRate)
            return CMTime(seconds: max(sampledSeconds, 0), preferredTimescale: 600)
        }

        private func sampledFrameCacheKey(for url: URL, localTime: CMTime) -> String {
            let sampledTime = sampledLocalTime(for: localTime)
            return "\(url.path)|\(sampledTime.value)|\(sampledTime.timescale)"
        }
    }

    func estimatedExportSpec(
        mediaItems: [MediaItem],
        durationSeconds: Double,
        aspectRatio: AspectRatio,
        finalQuality: FinalExportQuality,
        timingMode: TimingMode
    ) -> String {
        if timingMode == .video {
            return "Original video stitch \(approximateDurationLabel(for: durationSeconds))"
        }

        let safeDuration = CMTime(seconds: max(durationSeconds, 1), preferredTimescale: 600)
        let timelineSegments = estimatedTimelineSegments(for: mediaItems, totalDuration: safeDuration)
        let pressure = videoPressure(for: timelineSegments)
        let profile = resolvedRenderProfile(
            for: finalQuality.renderQuality,
            aspectRatio: aspectRatio,
            duration: safeDuration,
            videoPressure: pressure,
            timingMode: timingMode,
            mediaItems: mediaItems
        )
        let width = Int(profile.renderSize.width.rounded())
        let height = Int(profile.renderSize.height.rounded())
        return "\(aspectRatio.rawValue) \(width)x\(height) \(approximateDurationLabel(for: durationSeconds))"
    }

    func exportVideo(
        mediaItems: [MediaItem],
        narrationText: String,
        backgroundMusicURL: URL?,
        backgroundMusicVolume: Double,
        narrationVolume: Double,
        videoAudioVolume: Double,
        voiceIdentifier: String,
        aspectRatio: AspectRatio,
        timingMode: TimingMode,
        renderQuality: RenderQuality = .finalStandard,
        externalCues: [ExternalCue] = [],
        externalNarrationAudioURL: URL? = nil,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws -> URL {
        guard !mediaItems.isEmpty else {
            throw ExportError.noPhotos
        }

        progressHandler?(0.08, "Preparing export workspace.")
        let workspace = try makeWorkspace()
        let slideshowURL = workspace.appendingPathComponent("slideshow.mov")
        let finalURL = workspace.appendingPathComponent(renderQuality.outputFileName)

        if timingMode == .video {
            progressHandler?(0.18, "Stitching your original video clips.")
            try await exportVideoStitch(
                mediaItems: mediaItems,
                backgroundMusicURL: backgroundMusicURL,
                backgroundMusicVolume: backgroundMusicVolume,
                videoAudioVolume: videoAudioVolume,
                maximumDuration: renderQuality.maximumDuration,
                outputURL: finalURL,
                progressHandler: progressHandler
            )
            progressHandler?(1.0, "Finalizing exported video.")
            return finalURL
        }

        let minimumVisualDuration = minimumVisualDuration(for: mediaItems)
        let shouldUseNarration = timingMode != .video
        let narrationTimeline: NarrationTimeline
        if shouldUseNarration {
            progressHandler?(0.16, "Preparing narration and captions.")
            narrationTimeline = try await synthesizeNarrationIfNeeded(
                text: narrationText,
                voiceIdentifier: voiceIdentifier,
                workspace: workspace,
                externalCues: externalCues,
                externalNarrationAudioURL: externalNarrationAudioURL
            )
        } else {
            narrationTimeline = NarrationTimeline(duration: .zero, captionSegments: [], utteranceAudioURLs: [])
        }

        let totalDuration: CMTime
        switch timingMode {
        case .video, .realLife:
            totalDuration = minimumVisualDuration
        case .story:
            totalDuration = narrationTimeline.duration > .zero
                ? narrationTimeline.duration
                : minimumVisualDuration
        }
        let resolvedDuration = renderQuality.maximumDuration.map { min(totalDuration, $0) } ?? totalDuration
        let baseTimelineSegments = try await makeTimelineSegments(for: mediaItems, totalDuration: totalDuration)
        let timelineSegments = timingMode == .story
            ? timelineSegmentsTrimmed(to: resolvedDuration, segments: baseTimelineSegments)
            : baseTimelineSegments
        let videoPressure = videoPressure(for: timelineSegments)
        let renderProfile = resolvedRenderProfile(
            for: renderQuality,
            aspectRatio: aspectRatio,
            duration: resolvedDuration,
            videoPressure: videoPressure,
            timingMode: timingMode,
            mediaItems: mediaItems
        )
        let trimmedCaptionSegments = timingMode == .realLife
            ? []
            : captionSegmentsTrimmed(to: resolvedDuration, segments: narrationTimeline.captionSegments)
        let trimmedNarrationURLs = try await narrationURLsTrimmed(
            narrationTimeline.utteranceAudioURLs,
            maxDuration: resolvedDuration
        )

        if timingMode == .realLife {
            progressHandler?(0.24, "Building a real-life composition.")
            try await exportRealLifeComposition(
                timelineSegments: timelineSegments,
                narrationURLs: trimmedNarrationURLs,
                backgroundMusicURL: backgroundMusicURL,
                backgroundMusicVolume: backgroundMusicVolume,
                narrationVolume: narrationVolume,
                videoAudioVolume: videoAudioVolume,
                totalDuration: resolvedDuration,
                renderSize: renderProfile.renderSize,
                frameRate: renderProfile.frameRate,
                workspace: workspace,
                outputURL: finalURL,
                progressHandler: progressHandler
            )
            progressHandler?(1.0, "Finalizing exported video.")
            return finalURL
        }

        progressHandler?(0.24, renderProfile.longFormOptimized ? "Optimizing a long-form render." : "Rendering video frames.")

        try await renderSlideshow(
            timelineSegments: timelineSegments,
            captionSegments: trimmedCaptionSegments,
            totalDuration: resolvedDuration,
            renderSize: renderProfile.renderSize,
            frameRate: renderProfile.frameRate,
            videoSampleStride: renderProfile.videoSampleStride,
            progressHandler: progressHandler,
            outputURL: slideshowURL
        )
        progressHandler?(0.9, "Mixing narration and background music.")
        try await mergeAudioAndVideo(
            videoURL: slideshowURL,
            timelineSegments: timelineSegments,
            narrationURLs: trimmedNarrationURLs,
            backgroundMusicURL: backgroundMusicURL,
            backgroundMusicVolume: backgroundMusicVolume,
            narrationVolume: narrationVolume,
            videoAudioVolume: videoAudioVolume,
            totalDuration: resolvedDuration,
            outputURL: finalURL
        )
        progressHandler?(1.0, "Finalizing exported video.")

        return finalURL
    }

    private func captionSegmentsTrimmed(to maxDuration: CMTime, segments: [CaptionSegment]) -> [CaptionSegment] {
        guard maxDuration > .zero else { return [] }

        var trimmed: [CaptionSegment] = []
        for segment in segments {
            if segment.timeRange.start >= maxDuration { break }
            let end = min(segment.timeRange.end, maxDuration)
            let duration = end - segment.timeRange.start
            guard duration > .zero else { continue }
            trimmed.append(
                CaptionSegment(
                    text: segment.text,
                    timeRange: CMTimeRange(start: segment.timeRange.start, duration: duration)
                )
            )
        }
        return trimmed
    }

    private func timelineSegmentsTrimmed(to maxDuration: CMTime, segments: [TimelineSegment]) -> [TimelineSegment] {
        guard maxDuration > .zero else { return [] }

        var trimmed: [TimelineSegment] = []
        for segment in segments {
            if segment.timeRange.start >= maxDuration { break }
            let end = min(segment.timeRange.end, maxDuration)
            let duration = end - segment.timeRange.start
            guard duration > .zero else { continue }
            trimmed.append(
                TimelineSegment(
                    mediaItem: segment.mediaItem,
                    timeRange: CMTimeRange(start: segment.timeRange.start, duration: duration)
                )
            )
        }
        return trimmed
    }

    private func narrationURLsTrimmed(_ narrationURLs: [URL], maxDuration: CMTime) async throws -> [URL] {
        guard maxDuration > .zero else { return [] }

        var trimmedURLs: [URL] = []
        var cursor = CMTime.zero

        for narrationURL in narrationURLs {
            guard cursor < maxDuration else { break }
            let narrationAsset = AVURLAsset(url: narrationURL)
            let narrationDuration = try await narrationAsset.load(.duration)
            let remaining = maxDuration - cursor

            if narrationDuration <= remaining {
                trimmedURLs.append(narrationURL)
                cursor = cursor + narrationDuration
            } else {
                let trimmedURL = try await trimmedAudioCopy(from: narrationURL, duration: remaining)
                trimmedURLs.append(trimmedURL)
                break
            }
        }

        return trimmedURLs
    }

    private func trimmedAudioCopy(from sourceURL: URL, duration: CMTime) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ExportError.exportSessionFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trimmed-audio-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = CMTimeRange(start: .zero, duration: duration)
        await exportSession.export()

        if let error = exportSession.error {
            throw error
        }

        guard exportSession.status == .completed else {
            throw ExportError.exportFailed
        }

        return outputURL
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
            let resolvedDuration = max(audioDuration, cueDuration, CMTime(seconds: 1, preferredTimescale: 600))
            return NarrationTimeline(
                duration: resolvedDuration,
                captionSegments: captionSegments(from: externalCues),
                utteranceAudioURLs: [externalNarrationAudioURL]
            )
        }

        let narrationSegments = SpeechVoiceLibrary.narrationSegments(from: trimmedText, optimizeForLongForm: true)
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
        let totalDuration = max(biasedAudioDuration, estimatedNarrationDuration, CMTime(seconds: 1, preferredTimescale: 600))
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
        timelineSegments: [TimelineSegment],
        captionSegments: [CaptionSegment],
        totalDuration: CMTime,
        renderSize: CGSize,
        frameRate: Int32,
        videoSampleStride: Int32,
        progressHandler: ((Double, String) -> Void)?,
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

        let videoFrameCache = VideoFrameCache(
            frameRate: frameRate,
            renderSize: renderSize,
            sampleStride: videoSampleStride
        )
        

        let totalFrames = max(Int(ceil(CMTimeGetSeconds(totalDuration) * Double(frameRate))), timelineSegments.count)

        for frameIndex in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            let currentTime = CMTime(value: CMTimeValue(frameIndex), timescale: frameRate)
            let caption = captionText(for: currentTime, segments: captionSegments)
            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: frameRate)
            let image = try await mediaFrameForTime(
                currentTime,
                timelineSegments: timelineSegments,
                videoFrameCache: videoFrameCache
            )
            try autoreleasepool {
                let pixelBuffer = try makePixelBuffer(from: image, caption: caption, renderSize: renderSize)
                if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                    throw writer.error ?? ExportError.videoWriterSetupFailed
                }
            }

            if frameIndex.isMultiple(of: 12) || frameIndex == totalFrames - 1 {
                let completion = Double(frameIndex + 1) / Double(max(totalFrames, 1))
                let progress = 0.24 + (completion * 0.61)
                progressHandler?(progress, "Rendering video frames (\(Int((completion * 100).rounded()))%).")
            }
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
        timelineSegments: [TimelineSegment],
        narrationURLs: [URL],
        backgroundMusicURL: URL?,
        backgroundMusicVolume: Double,
        narrationVolume: Double,
        videoAudioVolume: Double,
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

        let resolvedVideoVolume = Float(min(max(videoAudioVolume, 0), 1))
        if resolvedVideoVolume > 0 {
            for segment in timelineSegments {
                guard case let .video(url, _) = segment.mediaItem.kind else { continue }

                let clipAsset = AVURLAsset(url: url)
                guard let clipAudioTrack = try await clipAsset.loadTracks(withMediaType: .audio).first else {
                    continue
                }
                guard let compositionClipAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    continue
                }

                let clipDuration = try await clipAsset.load(.duration)
                let segmentDuration = min(segment.timeRange.duration, clipDuration)
                guard segmentDuration > .zero else { continue }

                try compositionClipAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: segmentDuration),
                    of: clipAudioTrack,
                    at: segment.timeRange.start
                )
                let clipAudioParameters = AVMutableAudioMixInputParameters(track: compositionClipAudioTrack)
                clipAudioParameters.setVolume(resolvedVideoVolume, at: .zero)
                audioMixParameters.append(clipAudioParameters)
            }
        }

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
            let resolvedNarrationVolume = Float(min(max(narrationVolume, 0), 1))
            narrationParameters.setVolume(resolvedNarrationVolume, at: .zero)
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
                let resolvedVolume = Float(min(max(backgroundMusicVolume, 0), 1))
                musicParameters.setVolume(resolvedVolume, at: .zero)
                let fadeStart = CMTimeMaximum(.zero, totalDuration - CMTime(seconds: 1.2, preferredTimescale: 600))
                musicParameters.setVolumeRamp(fromStartVolume: resolvedVolume, toEndVolume: 0.0, timeRange: CMTimeRange(start: fadeStart, duration: totalDuration - fadeStart))
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

    private func exportVideoStitch(
        mediaItems: [MediaItem],
        backgroundMusicURL: URL?,
        backgroundMusicVolume: Double,
        videoAudioVolume: Double,
        maximumDuration: CMTime?,
        outputURL: URL,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let videoItems = mediaItems.compactMap { item -> (url: URL, duration: CMTime)? in
            guard case let .video(url, duration) = item.kind else { return nil }
            return (url, duration)
        }

        guard !videoItems.isEmpty else {
            throw ExportError.noVideos
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.missingVideoTrack
        }

        var audioMixParameters: [AVMutableAudioMixInputParameters] = []
        let resolvedVideoVolume = Float(min(max(videoAudioVolume, 0), 1))
        let mayAttemptStrictPassthrough = backgroundMusicURL == nil && resolvedVideoVolume >= 0.999
        var segmentLayouts: [StitchedVideoSegmentLayout] = []
        let passthroughAudioTrack = mayAttemptStrictPassthrough
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil
        var cursor = CMTime.zero
        var referenceTransform: CGAffineTransform?
        var referenceNaturalSize: CGSize?
        let cappedDuration = maximumDuration

        for (index, item) in videoItems.enumerated() {
            progressHandler?(
                0.2 + (0.45 * (Double(index) / Double(max(videoItems.count, 1)))),
                "Stitching video \(index + 1) of \(videoItems.count)."
            )

            if let cappedDuration, cursor >= cappedDuration {
                break
            }

            let asset = AVURLAsset(url: item.url)
            guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw ExportError.missingVideoTrack
            }
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
            let naturalSize = try await sourceVideoTrack.load(.naturalSize)

            let assetDuration = try await asset.load(.duration)
            let baseClipDuration = min(item.duration, assetDuration)
            let remainingDuration = cappedDuration.map { $0 - cursor } ?? baseClipDuration
            let clipDuration = min(baseClipDuration, remainingDuration)
            guard clipDuration > .zero else { continue }

            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: clipDuration),
                of: sourceVideoTrack,
                at: cursor
            )
            segmentLayouts.append(
                StitchedVideoSegmentLayout(
                    timeRange: CMTimeRange(start: cursor, duration: clipDuration),
                    preferredTransform: preferredTransform,
                    naturalSize: naturalSize
                )
            )

            if referenceTransform == nil {
                referenceTransform = preferredTransform
                referenceNaturalSize = naturalSize
            }

            if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                if mayAttemptStrictPassthrough, let passthroughAudioTrack {
                    try passthroughAudioTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: clipDuration),
                        of: sourceAudioTrack,
                        at: cursor
                    )
                } else if resolvedVideoVolume > 0,
                          let compositionAudioTrack = composition.addMutableTrack(
                            withMediaType: .audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                          ) {
                    try compositionAudioTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: clipDuration),
                        of: sourceAudioTrack,
                        at: cursor
                    )
                    let clipAudioParameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
                    clipAudioParameters.setVolume(resolvedVideoVolume, at: cursor)
                    audioMixParameters.append(clipAudioParameters)
                }
            }

            cursor = cursor + clipDuration
        }

        let totalDuration = cursor
        guard totalDuration > .zero else {
            throw ExportError.noVideos
        }

        let canAttemptStrictPassthrough =
            backgroundMusicURL == nil &&
            resolvedVideoVolume >= 0.999 &&
            segmentLayouts.allSatisfy {
                guard let referenceTransform, let referenceNaturalSize else { return false }
                return $0.preferredTransform == referenceTransform && $0.naturalSize == referenceNaturalSize
            }

        if let backgroundMusicURL {
            progressHandler?(0.72, "Mixing background music into the stitched video.")
            let musicAsset = AVURLAsset(url: backgroundMusicURL)
            if let musicTrack = try await musicAsset.loadTracks(withMediaType: .audio).first,
               let compositionMusicTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let musicDuration = try await musicAsset.load(.duration)
                var musicCursor = CMTime.zero

                while musicCursor < totalDuration {
                    let remaining = totalDuration - musicCursor
                    let segmentDuration = min(musicDuration, remaining)
                    try compositionMusicTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: segmentDuration),
                        of: musicTrack,
                        at: musicCursor
                    )
                    musicCursor = musicCursor + segmentDuration
                    if musicDuration == .zero { break }
                }

                let musicParameters = AVMutableAudioMixInputParameters(track: compositionMusicTrack)
                let resolvedMusicVolume = Float(min(max(backgroundMusicVolume, 0), 1))
                musicParameters.setVolume(resolvedMusicVolume, at: .zero)
                let fadeStart = CMTimeMaximum(.zero, totalDuration - CMTime(seconds: 1.2, preferredTimescale: 600))
                musicParameters.setVolumeRamp(
                    fromStartVolume: resolvedMusicVolume,
                    toEndVolume: 0.0,
                    timeRange: CMTimeRange(start: fadeStart, duration: totalDuration - fadeStart)
                )
                audioMixParameters.append(musicParameters)
            }
        }

        do {
            try await exportStitchedComposition(
                composition,
                presetName: canAttemptStrictPassthrough ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality,
                outputURL: outputURL,
                audioMixParameters: canAttemptStrictPassthrough ? [] : audioMixParameters,
                videoComposition: canAttemptStrictPassthrough
                    ? nil
                    : makeVideoComposition(
                        for: compositionVideoTrack,
                        segmentLayouts: segmentLayouts,
                        totalDuration: totalDuration
                    ),
                progressMessage: canAttemptStrictPassthrough
                    ? "Exporting a passthrough video stitch."
                    : "Exporting the stitched video.",
                progressHandler: progressHandler
            )
        } catch {
            guard canAttemptStrictPassthrough else {
                throw error
            }

            progressHandler?(0.9, "Passthrough was not supported for these clips. Retrying with a high-quality stitch.")
            try await exportStitchedComposition(
                composition,
                presetName: AVAssetExportPresetHighestQuality,
                outputURL: outputURL,
                audioMixParameters: [],
                videoComposition: makeVideoComposition(
                    for: compositionVideoTrack,
                    segmentLayouts: segmentLayouts,
                    totalDuration: totalDuration
                ),
                progressMessage: "Exporting the stitched video.",
                progressHandler: progressHandler
            )
        }
    }

    private func exportRealLifeComposition(
        timelineSegments: [TimelineSegment],
        narrationURLs: [URL],
        backgroundMusicURL: URL?,
        backgroundMusicVolume: Double,
        narrationVolume: Double,
        videoAudioVolume: Double,
        totalDuration: CMTime,
        renderSize: CGSize,
        frameRate: Int32,
        workspace: URL,
        outputURL: URL,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws {
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.missingVideoTrack
        }

        var audioMixParameters: [AVMutableAudioMixInputParameters] = []
        var segmentLayouts: [StitchedVideoSegmentLayout] = []
        let resolvedVideoVolume = Float(min(max(videoAudioVolume, 0), 1))

        for (index, segment) in timelineSegments.enumerated() {
            let completion = Double(index) / Double(max(timelineSegments.count, 1))
            progressHandler?(0.24 + (completion * 0.40), "Composing media \(index + 1) of \(timelineSegments.count).")

            switch segment.mediaItem.kind {
            case .photo:
                let photoClipURL = workspace.appendingPathComponent("real-life-photo-\(index).mov")
                try await renderPhotoSegmentClip(
                    image: segment.mediaItem.previewImage,
                    duration: segment.timeRange.duration,
                    renderSize: renderSize,
                    frameRate: frameRate,
                    outputURL: photoClipURL
                )

                let photoAsset = AVURLAsset(url: photoClipURL)
                guard let photoVideoTrack = try await photoAsset.loadTracks(withMediaType: .video).first else {
                    throw ExportError.missingVideoTrack
                }
                let photoDuration = try await photoAsset.load(.duration)
                let clipDuration = min(segment.timeRange.duration, photoDuration)
                guard clipDuration > .zero else { continue }

                try compositionVideoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: clipDuration),
                    of: photoVideoTrack,
                    at: segment.timeRange.start
                )
                segmentLayouts.append(
                    StitchedVideoSegmentLayout(
                        timeRange: CMTimeRange(start: segment.timeRange.start, duration: clipDuration),
                        preferredTransform: .identity,
                        naturalSize: renderSize
                    )
                )

            case let .video(url, _):
                let asset = AVURLAsset(url: url)
                guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                    throw ExportError.missingVideoTrack
                }
                let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
                let naturalSize = try await sourceVideoTrack.load(.naturalSize)
                let assetDuration = try await asset.load(.duration)
                let clipDuration = min(segment.timeRange.duration, assetDuration)
                guard clipDuration > .zero else { continue }

                try compositionVideoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: clipDuration),
                    of: sourceVideoTrack,
                    at: segment.timeRange.start
                )
                segmentLayouts.append(
                    StitchedVideoSegmentLayout(
                        timeRange: CMTimeRange(start: segment.timeRange.start, duration: clipDuration),
                        preferredTransform: preferredTransform,
                        naturalSize: naturalSize
                    )
                )

                if resolvedVideoVolume > 0,
                   let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
                   let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                   ) {
                    try compositionAudioTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: clipDuration),
                        of: sourceAudioTrack,
                        at: segment.timeRange.start
                    )
                    let clipAudioParameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
                    clipAudioParameters.setVolume(resolvedVideoVolume, at: segment.timeRange.start)
                    audioMixParameters.append(clipAudioParameters)
                }
            }
        }

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
            let resolvedNarrationVolume = Float(min(max(narrationVolume, 0), 1))
            narrationParameters.setVolume(resolvedNarrationVolume, at: .zero)
            audioMixParameters.append(narrationParameters)
        }

        if let backgroundMusicURL {
            progressHandler?(0.72, "Mixing background music into the real-life video.")
            let musicAsset = AVURLAsset(url: backgroundMusicURL)
            if let musicTrack = try await musicAsset.loadTracks(withMediaType: .audio).first,
               let compositionMusicTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let musicDuration = try await musicAsset.load(.duration)
                var musicCursor = CMTime.zero

                while musicCursor < totalDuration {
                    let remaining = totalDuration - musicCursor
                    let segmentDuration = min(musicDuration, remaining)
                    try compositionMusicTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: segmentDuration),
                        of: musicTrack,
                        at: musicCursor
                    )
                    musicCursor = musicCursor + segmentDuration
                    if musicDuration == .zero { break }
                }

                let musicParameters = AVMutableAudioMixInputParameters(track: compositionMusicTrack)
                let resolvedMusicVolume = Float(min(max(backgroundMusicVolume, 0), 1))
                musicParameters.setVolume(resolvedMusicVolume, at: .zero)
                let fadeStart = CMTimeMaximum(.zero, totalDuration - CMTime(seconds: 1.2, preferredTimescale: 600))
                musicParameters.setVolumeRamp(
                    fromStartVolume: resolvedMusicVolume,
                    toEndVolume: 0.0,
                    timeRange: CMTimeRange(start: fadeStart, duration: totalDuration - fadeStart)
                )
                audioMixParameters.append(musicParameters)
            }
        }

        try await exportStitchedComposition(
            composition,
            presetName: AVAssetExportPresetHighestQuality,
            outputURL: outputURL,
            audioMixParameters: audioMixParameters,
            videoComposition: makeVideoComposition(
                for: compositionVideoTrack,
                segmentLayouts: segmentLayouts,
                totalDuration: totalDuration,
                targetRenderSize: renderSize
            ),
            progressMessage: "Exporting the real-life video.",
            progressHandler: progressHandler
        )
    }

    private func renderPhotoSegmentClip(
        image: UIImage,
        duration: CMTime,
        renderSize: CGSize,
        frameRate: Int32,
        outputURL: URL
    ) async throws {
        let photoItem = MediaItem(previewImage: image, kind: .photo)
        let timelineSegment = TimelineSegment(
            mediaItem: photoItem,
            timeRange: CMTimeRange(start: .zero, duration: duration)
        )
        try await renderSlideshow(
            timelineSegments: [timelineSegment],
            captionSegments: [],
            totalDuration: duration,
            renderSize: renderSize,
            frameRate: frameRate,
            videoSampleStride: 1,
            progressHandler: nil,
            outputURL: outputURL
        )
    }

    private func exportStitchedComposition(
        _ composition: AVMutableComposition,
        presetName: String,
        outputURL: URL,
        audioMixParameters: [AVMutableAudioMixInputParameters],
        videoComposition: AVMutableVideoComposition? = nil,
        progressMessage: String,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName) else {
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

        if let videoComposition {
            exportSession.videoComposition = videoComposition
        }

        progressHandler?(0.88, progressMessage)
        await exportSession.export()

        if let error = exportSession.error {
            throw error
        }

        guard exportSession.status == .completed else {
            throw ExportError.exportFailed
        }
    }

    private func makeVideoComposition(
        for compositionVideoTrack: AVMutableCompositionTrack,
        segmentLayouts: [StitchedVideoSegmentLayout],
        totalDuration: CMTime
    ) -> AVMutableVideoComposition {
        makeVideoComposition(
            for: compositionVideoTrack,
            segmentLayouts: segmentLayouts,
            totalDuration: totalDuration,
            targetRenderSize: nil
        )
    }

    private func makeVideoComposition(
        for compositionVideoTrack: AVMutableCompositionTrack,
        segmentLayouts: [StitchedVideoSegmentLayout],
        totalDuration: CMTime,
        targetRenderSize: CGSize?
    ) -> AVMutableVideoComposition {
        let renderSize = segmentLayouts.reduce(CGSize.zero) { currentMax, layout in
            let transformedBounds = CGRect(origin: .zero, size: layout.naturalSize)
                .applying(layout.preferredTransform)
                .standardized
            return CGSize(
                width: max(currentMax.width, transformedBounds.width),
                height: max(currentMax.height, transformedBounds.height)
            )
        }

        let chosenRenderSize = targetRenderSize ?? renderSize
        let safeRenderSize = CGSize(
            width: max(round(chosenRenderSize.width / 2) * 2, 2),
            height: max(round(chosenRenderSize.height / 2) * 2, 2)
        )

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        for layout in segmentLayouts {
            let fittedTransform = fittedTransform(
                preferredTransform: layout.preferredTransform,
                naturalSize: layout.naturalSize,
                renderSize: safeRenderSize
            )
            layerInstruction.setTransform(fittedTransform, at: layout.timeRange.start)
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = safeRenderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        return videoComposition
    }

    private func fittedTransform(
        preferredTransform: CGAffineTransform,
        naturalSize: CGSize,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let transformedBounds = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
        let translationToOrigin = CGAffineTransform(
            translationX: -transformedBounds.minX,
            y: -transformedBounds.minY
        )
        let centeredTranslation = CGAffineTransform(
            translationX: (renderSize.width - transformedBounds.width) / 2,
            y: (renderSize.height - transformedBounds.height) / 2
        )
        return preferredTransform.concatenating(translationToOrigin).concatenating(centeredTranslation)
    }

    private func makePixelBuffer(from image: UIImage, caption: String?, renderSize: CGSize) throws -> CVPixelBuffer {
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
            drawCaption(caption, in: context, renderSize: renderSize)
        }
        UIGraphicsPopContext()

        return pixelBuffer
    }

    private func estimatedTimelineSegments(for mediaItems: [MediaItem], totalDuration: CMTime) -> [TimelineSegment] {
        guard !mediaItems.isEmpty, totalDuration > .zero else { return [] }

        let videoItems = mediaItems.filter { if case .video = $0.kind { return true }; return false }
        let photoItems = mediaItems.filter { if case .photo = $0.kind { return true }; return false }
        let hasVideos = !videoItems.isEmpty
        let hasPhotos = !photoItems.isEmpty

        let totalVideoDuration = videoItems.reduce(CMTime.zero) { partial, item in
            switch item.kind {
            case .photo:
                return partial
            case let .video(_, duration):
                return partial + duration
            }
        }

        let photoDuration: CMTime = {
            guard hasPhotos else { return .zero }
            if !hasVideos {
                return CMTimeMultiplyByFloat64(totalDuration, multiplier: 1.0 / Double(photoItems.count))
            }
            let remainingForPhotos = CMTimeMaximum(.zero, totalDuration - totalVideoDuration)
            guard remainingForPhotos > .zero else { return .zero }
            return CMTimeMultiplyByFloat64(remainingForPhotos, multiplier: 1.0 / Double(photoItems.count))
        }()

        var segments: [TimelineSegment] = []
        var cursor = CMTime.zero
        var loopIndex = 0

        while cursor < totalDuration {
            let item = mediaItems[loopIndex % mediaItems.count]
            let duration: CMTime
            switch item.kind {
            case .photo:
                duration = photoDuration
            case let .video(_, clipDuration):
                duration = clipDuration
            }

            if duration <= .zero {
                loopIndex += 1
                if hasPhotos && hasVideos && loopIndex >= mediaItems.count {
                    break
                }
                continue
            }
            let remaining = totalDuration - cursor
            let clippedDuration = CMTimeMinimum(duration, remaining)
            segments.append(TimelineSegment(mediaItem: item, timeRange: CMTimeRange(start: cursor, duration: clippedDuration)))
            cursor = cursor + clippedDuration
            loopIndex += 1

            if hasPhotos && hasVideos && loopIndex >= mediaItems.count {
                break
            }
            if !hasVideos && loopIndex >= mediaItems.count {
                break
            }
        }

        return segments
    }

    private func drawCaption(_ caption: String, in context: CGContext, renderSize: CGSize) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let widthScale = max(min(renderSize.width / 720, 1.0), 0.5)
        let maxTextWidth = renderSize.width - max(72, 120 * widthScale)
        let maxTextHeight: CGFloat = max(140, 240 * widthScale)
        let minimumFontSize: CGFloat = max(14, 20 * widthScale)
        var fontSize: CGFloat = renderSize.width < renderSize.height ? max(18, 34 * widthScale) : max(16, 30 * widthScale)
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

            fontSize -= 2
        }

        let boxPadding: CGFloat = max(10, 16 * widthScale)
        let bottomInset = max(renderSize.height * 0.025, 24)
        let boxRect = CGRect(
            x: (renderSize.width - measuredText.width) / 2 - boxPadding,
            y: renderSize.height - measuredText.height - (boxPadding * 2) - bottomInset,
            width: measuredText.width + (boxPadding * 2),
            height: measuredText.height + (boxPadding * 2)
        )

        let boxPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 32)
        context.saveGState()
        context.setFillColor(UIColor.black.withAlphaComponent(0.42).cgColor)
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

    private func minimumVisualDuration(for mediaItems: [MediaItem]) -> CMTime {
        let videoDuration = mediaItems.reduce(CMTime.zero) { partial, item in
            switch item.kind {
            case .photo:
                return partial
            case let .video(_, duration):
                return partial + duration
            }
        }
        let photoCount = mediaItems.filter {
            if case .photo = $0.kind { return true }
            return false
        }.count
        let photoDuration = CMTime(seconds: max(Double(photoCount) * 1.6, photoCount > 0 ? 1.6 : 0), preferredTimescale: 600)
        return max(videoDuration + photoDuration, CMTime(seconds: 3, preferredTimescale: 600))
    }

    private func videoOnlyDuration(for mediaItems: [MediaItem]) -> CMTime {
        mediaItems.reduce(CMTime.zero) { partial, item in
            switch item.kind {
            case .photo:
                return partial
            case let .video(_, duration):
                return partial + duration
            }
        }
    }

    private func makeTimelineSegments(for mediaItems: [MediaItem], totalDuration: CMTime) async throws -> [TimelineSegment] {
        let photoItems = mediaItems.filter { if case .photo = $0.kind { return true }; return false }
        let videoItems = mediaItems.filter { if case .video = $0.kind { return true }; return false }
        let hasVideos = !videoItems.isEmpty
        let hasPhotos = !photoItems.isEmpty
        let totalVideoDuration = videoItems.reduce(CMTime.zero) { partial, item in
            switch item.kind {
            case .photo:
                return partial
            case let .video(_, duration):
                return partial + duration
            }
        }

        let perPhotoDuration: CMTime = {
            guard hasPhotos else { return .zero }
            if !hasVideos {
                return CMTimeMultiplyByFloat64(totalDuration, multiplier: 1.0 / Double(photoItems.count))
            }
            let remainingForPhotos = CMTimeMaximum(.zero, totalDuration - totalVideoDuration)
            guard remainingForPhotos > .zero else { return .zero }
            return CMTimeMultiplyByFloat64(remainingForPhotos, multiplier: 1.0 / Double(photoItems.count))
        }()

        var cursor = CMTime.zero
        var segments: [TimelineSegment] = []
        var loopIndex = 0

        while cursor < totalDuration {
            let item = mediaItems[loopIndex % mediaItems.count]
            let remainingDuration = totalDuration - cursor
            guard remainingDuration > .zero else { break }

            let intendedDuration: CMTime
            switch item.kind {
            case .photo:
                intendedDuration = perPhotoDuration
            case let .video(_, videoDuration):
                intendedDuration = videoDuration
            }

            if intendedDuration <= .zero {
                loopIndex += 1
                if hasPhotos && hasVideos && loopIndex >= mediaItems.count {
                    break
                }
                continue
            }

            let duration = min(intendedDuration, remainingDuration)
            guard duration > .zero else {
                loopIndex += 1
                continue
            }
            segments.append(
                TimelineSegment(
                    mediaItem: item,
                    timeRange: CMTimeRange(start: cursor, duration: duration)
                )
            )
            cursor = cursor + duration
            loopIndex += 1

            if hasPhotos && hasVideos && loopIndex >= mediaItems.count {
                break
            }
            if !hasVideos && loopIndex >= mediaItems.count {
                break
            }
        }

        return segments
    }

    private func mediaFrameForTime(
        _ currentTime: CMTime,
        timelineSegments: [TimelineSegment],
        videoFrameCache: VideoFrameCache
    ) async throws -> UIImage {
        guard let segment = timelineSegments.first(where: { $0.timeRange.containsTime(currentTime) }) ?? timelineSegments.last else {
            return UIImage()
        }

        switch segment.mediaItem.kind {
        case .photo:
            return segment.mediaItem.previewImage
        case let .video(url, duration):
            let localTime = min(currentTime - segment.timeRange.start, duration)
            do {
                return try await videoFrameCache.image(for: url, localTime: localTime)
            } catch {
                return segment.mediaItem.previewImage
            }
        }
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

        let phraseSeparators = CharacterSet(charactersIn: ",，、")
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
        let timingText = SpeechVoiceLibrary.normalizedTimingText(text)

        if containsCJK(timingText) {
            let cjkCharacters = Double(timingText.filter { isCJK($0) }.count)
            let latinCharacters = Double(timingText.filter { $0.isASCII && $0.isLetter }.count)
            return max((cjkCharacters * 1.15) + (latinCharacters * 0.35), 1.0)
        }

        let words = timingText.split(whereSeparator: \.isWhitespace)
        let syllables = Double(words.reduce(0) { $0 + approximateSyllableCount(in: String($1)) })
        return max((Double(words.count) * 1.1) + (syllables * 0.55), 1.0)
    }

    private func estimatedNarrationSeconds(for texts: [String]) -> Double {
        texts.reduce(0.0) { $0 + estimatedSecondsForSegment($1) }
    }

    private func estimatedSecondsForSegment(_ text: String) -> Double {
        let timingText = SpeechVoiceLibrary.normalizedTimingText(text)

        if containsCJK(timingText) {
            let cjkCharacters = Double(timingText.filter { isCJK($0) }.count)
            return max(cjkCharacters / 3.6, 0.9)
        }

        let words = timingText.split(whereSeparator: \.isWhitespace)
        let syllables = Double(words.reduce(0) { $0 + approximateSyllableCount(in: String($1)) })
        return max((Double(words.count) / 2.25) + (syllables * 0.06), 0.9)
    }

    private func minimumCaptionSeconds(for text: String) -> Double {
        containsCJK(SpeechVoiceLibrary.normalizedTimingText(text)) ? 0.95 : 0.85
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
        case noVideos
        case videoWriterSetupFailed
        case pixelBufferCreationFailed
        case missingVideoTrack
        case exportSessionFailed
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .noPhotos:
                return "Pick at least one photo before creating a video."
            case .noVideos:
                return "Import at least one video before using Video mode."
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

    private func resolvedRenderProfile(
        for quality: RenderQuality,
        aspectRatio: AspectRatio,
        duration: CMTime,
        videoPressure: VideoPressure,
        timingMode: TimingMode,
        mediaItems: [MediaItem]
    ) -> RenderProfile {
        let seconds = CMTimeGetSeconds(duration)
        let baseSize = quality.renderSize(for: aspectRatio)
        let baseRate = quality.frameRate
        let hasHeavyVideoLoad =
            videoPressure.clipCount >= 3 &&
            (videoPressure.totalVideoSeconds > 600 || videoPressure.longestClipSeconds > 240)

        if timingMode == .video {
            return RenderProfile(
                renderSize: preferredMediaDrivenRenderSize(for: mediaItems, aspectRatio: aspectRatio, minimumSize: baseSize),
                frameRate: baseRate,
                longFormOptimized: false,
                videoSampleStride: hasHeavyVideoLoad || seconds > 900 ? 2 : 1
            )
        }

        if timingMode == .realLife {
            if !seconds.isFinite || seconds <= 180 {
                return RenderProfile(renderSize: baseSize, frameRate: baseRate, longFormOptimized: false, videoSampleStride: 1)
            }

            switch quality {
            case .preview:
                return RenderProfile(renderSize: baseSize, frameRate: baseRate, longFormOptimized: false, videoSampleStride: 1)
            case .finalStandard:
                if hasHeavyVideoLoad || seconds > 900 {
                    return RenderProfile(
                        renderSize: aspectRatio == .vertical ? CGSize(width: 360, height: 640) : CGSize(width: 480, height: 360),
                        frameRate: 10,
                        longFormOptimized: true,
                        videoSampleStride: 1
                    )
                }
                if seconds > 420 {
                    return RenderProfile(
                        renderSize: aspectRatio == .vertical ? CGSize(width: 540, height: 960) : CGSize(width: 720, height: 540),
                        frameRate: 10,
                        longFormOptimized: true,
                        videoSampleStride: 1
                    )
                }
                return RenderProfile(
                    renderSize: aspectRatio == .vertical ? CGSize(width: 540, height: 960) : CGSize(width: 720, height: 540),
                    frameRate: baseRate,
                    longFormOptimized: false,
                    videoSampleStride: 1
                )
            case .finalHigh:
                if hasHeavyVideoLoad || seconds > 900 {
                    return RenderProfile(
                        renderSize: aspectRatio == .vertical ? CGSize(width: 540, height: 960) : CGSize(width: 720, height: 540),
                        frameRate: 12,
                        longFormOptimized: true,
                        videoSampleStride: 1
                    )
                }
                if seconds > 420 {
                    return RenderProfile(
                        renderSize: aspectRatio == .vertical ? CGSize(width: 720, height: 1280) : CGSize(width: 960, height: 720),
                        frameRate: 12,
                        longFormOptimized: true,
                        videoSampleStride: 1
                    )
                }
                return RenderProfile(
                    renderSize: aspectRatio == .vertical ? CGSize(width: 720, height: 1280) : CGSize(width: 960, height: 720),
                    frameRate: baseRate,
                    longFormOptimized: false,
                    videoSampleStride: 1
                )
            }
        }

        guard seconds.isFinite, seconds > 180 else {
            return RenderProfile(renderSize: baseSize, frameRate: baseRate, longFormOptimized: false, videoSampleStride: 1)
        }

        switch quality {
        case .preview:
            return RenderProfile(renderSize: baseSize, frameRate: baseRate, longFormOptimized: false, videoSampleStride: 1)
        case .finalStandard:
            if hasHeavyVideoLoad || seconds > 900 {
                return RenderProfile(
                    renderSize: aspectRatio == .vertical ? CGSize(width: 360, height: 640) : CGSize(width: 480, height: 360),
                    frameRate: 8,
                    longFormOptimized: true,
                    videoSampleStride: 2
                )
            }
            if seconds > 420 {
                return RenderProfile(
                    renderSize: aspectRatio == .vertical ? CGSize(width: 640, height: 1136) : CGSize(width: 854, height: 640),
                    frameRate: 6,
                    longFormOptimized: true,
                    videoSampleStride: 4
                )
            }
            return RenderProfile(
                renderSize: baseSize,
                frameRate: 8,
                longFormOptimized: true,
                videoSampleStride: 3
            )
        case .finalHigh:
            if hasHeavyVideoLoad || seconds > 900 {
                return RenderProfile(
                    renderSize: aspectRatio == .vertical ? CGSize(width: 360, height: 640) : CGSize(width: 480, height: 360),
                    frameRate: 10,
                    longFormOptimized: true,
                    videoSampleStride: 2
                )
            }
            if seconds > 420 {
                return RenderProfile(
                    renderSize: aspectRatio == .vertical ? CGSize(width: 720, height: 1280) : CGSize(width: 960, height: 720),
                    frameRate: 8,
                    longFormOptimized: true,
                    videoSampleStride: 3
                )
            }
            return RenderProfile(
                renderSize: aspectRatio == .vertical ? CGSize(width: 720, height: 1280) : CGSize(width: 960, height: 720),
                frameRate: 10,
                longFormOptimized: true,
                videoSampleStride: 2
            )
        }
    }

    private func preferredMediaDrivenRenderSize(
        for mediaItems: [MediaItem],
        aspectRatio: AspectRatio,
        minimumSize: CGSize
    ) -> CGSize {
        let largestMediaSize = mediaItems.reduce(CGSize.zero) { currentMax, item in
            let size = item.previewImage.size
            guard size.width > 0, size.height > 0 else { return currentMax }
            return CGSize(
                width: max(currentMax.width, size.width),
                height: max(currentMax.height, size.height)
            )
        }

        guard largestMediaSize.width > 0, largestMediaSize.height > 0 else {
            return minimumSize
        }

        let fitted = AVMakeRect(aspectRatio: aspectRatio == .vertical ? CGSize(width: 9, height: 16) : CGSize(width: 4, height: 3),
                                insideRect: CGRect(origin: .zero, size: largestMediaSize)).size

        let width = max(minimumSize.width, round(fitted.width / 2) * 2)
        let height = max(minimumSize.height, round(fitted.height / 2) * 2)
        return CGSize(width: width, height: height)
    }

    private func videoPressure(for timelineSegments: [TimelineSegment]) -> VideoPressure {
        var accumulatedVideoSeconds: Double = 0
        var longestClipSeconds: Double = 0
        var clipCount = 0

        for segment in timelineSegments {
            guard case .video = segment.mediaItem.kind else { continue }
            let clipSeconds = max(CMTimeGetSeconds(segment.timeRange.duration), 0)
            guard clipSeconds.isFinite, clipSeconds > 0 else { continue }
            accumulatedVideoSeconds += clipSeconds
            longestClipSeconds = max(longestClipSeconds, clipSeconds)
            clipCount += 1
        }

        return VideoPressure(
            totalVideoSeconds: accumulatedVideoSeconds,
            longestClipSeconds: longestClipSeconds,
            clipCount: clipCount
        )
    }

    private func approximateDurationLabel(for seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return String(format: "~%dh %02dm", hours, minutes)
        }
        return "~\(max(minutes, 1))min"
    }
}

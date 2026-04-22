import AVFoundation
import UIKit
import QuartzCore

struct VideoExporter {
    enum TimingMode: String, CaseIterable, Identifiable {
        case video = "Video"
        case story = "Story"
        case realLife = "Slideshow"

        var id: String { rawValue }
    }

    enum AspectRatio: String, CaseIterable, Identifiable {
        case widescreen = "16:9"
        case classic = "4:3"

        var id: String { rawValue }

        var renderSize: CGSize {
            switch self {
            case .widescreen:
                return CGSize(width: 1280, height: 720)
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
            case (.preview, .widescreen):
                return CGSize(width: 960, height: 540)
            case (.preview, .classic):
                return CGSize(width: 720, height: 540)
            case (.finalStandard, .widescreen):
                return CGSize(width: 1280, height: 720)
            case (.finalStandard, .classic):
                return CGSize(width: 960, height: 720)
            case (.finalHigh, .widescreen):
                return CGSize(width: 1600, height: 900)
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

    enum VideoModeFrameRate: String, CaseIterable, Identifiable {
        case fps24 = "24"
        case fps30 = "30"
        case fps60 = "60"

        var id: String { rawValue }

        var value: Int32 {
            switch self {
            case .fps24:
                return 24
            case .fps30:
                return 30
            case .fps60:
                return 60
            }
        }

        var displayName: String {
            "\(rawValue) fps"
        }
    }

    enum VideoModeResolution: String, CaseIterable, Identifiable {
        case p720 = "720p"
        case p1080 = "1080p"
        case p4k = "4K"

        var id: String { rawValue }

        var renderSize: CGSize {
            switch self {
            case .p720:
                return CGSize(width: 1280, height: 720)
            case .p1080:
                return CGSize(width: 1920, height: 1080)
            case .p4k:
                return CGSize(width: 3840, height: 2160)
            }
        }
    }

    /// On-screen caption look for story / slideshow exports (final video and caption-burn pass).
    enum CaptionStyle: String, CaseIterable, Identifiable, Hashable {
        /// Semibold white on soft dark pill — close to typical YouTube-style readability.
        case normal = "Normal"
        /// ~50% larger rounded bold type; tight dim plate + strong outline/shadow for light backgrounds.
        case stylish = "Stylish"

        var id: String { rawValue }
    }

    enum VideoModeQuality: String, CaseIterable, Identifiable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"

        var id: String { rawValue }

        var exportPresetName: String {
            switch self {
            case .low:
                return AVAssetExportPresetLowQuality
            case .medium:
                return AVAssetExportPresetMediumQuality
            case .high:
                return AVAssetExportPresetHighestQuality
            }
        }
    }

    struct VideoModeExportSettings {
        let frameRate: VideoModeFrameRate
        let resolution: VideoModeResolution
        let quality: VideoModeQuality
    }

    /// User-controlled overlay (Settings): text or image, burned into every exported video frame.
    struct WatermarkSettings: Equatable, Sendable {
        enum Mode: String, Sendable {
            case text
            case image
        }

        /// Where the watermark sits within the output frame (matches Settings → Watermark “Position”). Uses UIKit-style
        /// coordinates: origin top-left, y increases down (for **both** `CALayer` and string drawing in the flipped pixel buffer).
        enum Anchor: String, Sendable, CaseIterable, Identifiable, Equatable {
            case topLeft
            case topRight
            case bottomLeft
            case bottomRight

            var id: String { rawValue }
        }

        var isEnabled: Bool
        var mode: Mode
        var text: String
        var imageFileURL: URL?
        var anchor: Anchor
        /// 0.0...1.0: master strength (opacity) for the overlay; UI typically exposes ~0.1...1.0. PNG alpha is preserved and then multiplied by this.
        var opacity: CGFloat
        /// ~0.35...4.0: multiplies the resolution-based text/image size (FluxCut Pro; non‑Pro export uses 1.0).
        var sizeScale: CGFloat

        var isRenderable: Bool {
            guard isEnabled else { return false }
            switch mode {
            case .text:
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .image:
                guard let url = imageFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
                    return false
                }
                return true
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

    private struct CaptionSegment {
        let text: String
        let timeRange: CMTimeRange
    }

    typealias ExternalCue = NarrationPreviewBuilder.SubtitleCue

    /// Music beds on **global** script paragraph indices (independent of media blocks). Gaps use the combined mix.
    struct StoryMusicBedSpanExport: Sendable {
        let firstParagraphIndex: Int
        let lastParagraphIndex: Int
        /// Nil → combined `backgroundMusicURL` for this span.
        let soundtrackURL: URL?
    }

    /// Ordered story blocks: each covers an inclusive paragraph index range; `mediaIndices` index into the export `mediaItems` array.
    struct StoryBlockExportDescriptor: Sendable {
        struct Block: Sendable {
            let firstParagraphIndex: Int
            let lastParagraphIndex: Int
            let mediaIndices: [Int]
        }

        let blocks: [Block]
    }

    /// One story segment’s bed duration; `sourceURL` nil means silence for that span (no global fallback available).
    private struct StorySegmentMusicSlot: Sendable {
        let duration: CMTime
        let sourceURL: URL?
    }

    private struct NarrationTimeline {
        let duration: CMTime
        let captionSegments: [CaptionSegment]
        let utteranceAudioURLs: [URL]
        let utteranceDurations: [CMTime]
        /// Edit Story: utterance index ranges per block (blocks sorted by `firstParagraphIndex`). Nil when not using per-block whole-script narration.
        let storyBlockUtteranceRanges: [Range<Int>]?
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

    private struct EffectiveSlideshowExportSettings {
        let frameRate: Int32
        let renderSize: CGSize
        let presetName: String
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
        timingMode: TimingMode,
        includeCaptions: Bool = true,
        videoModeSettings: VideoModeExportSettings? = nil
    ) -> String {
        if timingMode == .video {
            if let videoModeSettings {
                return "\(videoModeSettings.resolution.rawValue) • \(videoModeSettings.frameRate.displayName) • \(videoModeSettings.quality.rawValue) • \(approximateDurationLabel(for: durationSeconds))"
            }
            return "Original video stitch \(approximateDurationLabel(for: durationSeconds))"
        }

        let safeDuration = CMTime(seconds: max(durationSeconds, 1), preferredTimescale: 600)
        let timelineSegments = estimatedTimelineSegments(
            for: mediaItems,
            totalDuration: safeDuration,
            timingMode: timingMode
        )
        let pressure = videoPressure(for: timelineSegments)
        let profile = resolvedRenderProfile(
            for: finalQuality.renderQuality,
            aspectRatio: aspectRatio,
            duration: safeDuration,
            videoPressure: pressure,
            timingMode: timingMode,
            mediaItems: mediaItems,
            includeCaptions: includeCaptions
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
        speechRateMultiplier: Double = 1.0,
        aspectRatio: AspectRatio,
        timingMode: TimingMode,
        includeCaptions: Bool = true,
        renderQuality: RenderQuality = .finalStandard,
        videoModeSettings: VideoModeExportSettings? = nil,
        externalCues: [ExternalCue] = [],
        externalNarrationAudioURL: URL? = nil,
        captionStyle: CaptionStyle = .normal,
        paragraphNarrationSegments: [String]? = nil,
        storyBlockDescriptor: StoryBlockExportDescriptor? = nil,
        storyMusicBedSpans: [StoryMusicBedSpanExport]? = nil,
        /// Isolates this run’s intermediates (TTS, slideshow, captions) and final `.mov` from any other concurrent or overlapping export.
        exportArtifactID: UUID,
        /// When set (e.g. `Documents/NarrationPreview` after full-length **prepareNarrationPreview**), Edit Story export copies `utterance-preview-*.caf` instead of re-synthesizing hundreds of segments.
        prebuiltUtteranceSourceDirectory: URL? = nil,
        watermarkSettings: WatermarkSettings? = nil,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws -> URL {
        guard !mediaItems.isEmpty else {
            throw ExportError.noPhotos
        }

        progressHandler?(0.08, "Preparing export workspace.")
        try Task.checkCancellation()
        let workspaceRoot = try makeWorkspace()
        let workspace = workspaceRoot.appendingPathComponent(exportArtifactID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
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
                videoModeSettings: renderQuality == .preview ? nil : videoModeSettings,
                outputURL: finalURL,
                watermarkSettings: watermarkSettings,
                progressHandler: progressHandler
            )
            progressHandler?(1.0, "Finalizing exported video.")
            return finalURL
        }

        let useStoryBlocks = timingMode == .story && storyBlockDescriptor != nil
        if useStoryBlocks, paragraphNarrationSegments?.isEmpty ?? true {
            throw ExportError.invalidStoryBlockPlan
        }

        let hasVideosInPool = mediaItems.contains {
            if case .video = $0.kind { return true }
            return false
        }
        let hasPhotosInPool = mediaItems.contains {
            if case .photo = $0.kind { return true }
            return false
        }
        var hasMixedStoryMedia = timingMode == .story && hasVideosInPool && hasPhotosInPool
        /// Story timeline has only video clips (no photos) — always use composition/export instead of per-frame slideshow rendering.
        var storyVideoOnlyMedia = timingMode == .story && hasVideosInPool && !hasPhotosInPool
        /// Story + captions needs a caption-burn pass; mixed and video-only use an intermediate file. Photo-only story still uses one-pass slideshow rendering.
        var storyUsesCaptionIntermediateFile =
            timingMode == .story && includeCaptions && hasVideosInPool && (hasMixedStoryMedia || !hasPhotosInPool)

        let minimumVisualDuration = minimumVisualDuration(for: mediaItems)
        let shouldUseNarration = timingMode != .video
        let narrationTimeline: NarrationTimeline
        if shouldUseNarration {
            progressHandler?(0.16, "Preparing narration and captions.")
            let storyBlockScripts: [String]?
            if useStoryBlocks,
               let paras = paragraphNarrationSegments,
               let desc = storyBlockDescriptor {
                let sortedBlocks = desc.blocks.sorted { $0.firstParagraphIndex < $1.firstParagraphIndex }
                storyBlockScripts = sortedBlocks.map { block in
                    paras[block.firstParagraphIndex...block.lastParagraphIndex].joined(separator: "\n\n")
                }
            } else {
                storyBlockScripts = nil
            }
            narrationTimeline = try await synthesizeNarrationIfNeeded(
                text: narrationText,
                voiceIdentifier: voiceIdentifier,
                speechRateMultiplier: speechRateMultiplier,
                workspace: workspace,
                externalCues: externalCues,
                externalNarrationAudioURL: externalNarrationAudioURL,
                forcedParagraphSegments: nil,
                storyBlockNarrationSegments: storyBlockScripts,
                renderQuality: renderQuality,
                prebuiltUtteranceSourceDirectory: prebuiltUtteranceSourceDirectory,
                progressHandler: progressHandler
            )
            if useStoryBlocks, narrationTimeline.storyBlockUtteranceRanges == nil {
                throw ExportError.invalidStoryBlockPlan
            }
            try Task.checkCancellation()
        } else {
            narrationTimeline = NarrationTimeline(
                duration: .zero,
                captionSegments: [],
                utteranceAudioURLs: [],
                utteranceDurations: [],
                storyBlockUtteranceRanges: nil
            )
        }

        /// Per-utterance lengths from files (when available) so audio mux matches frame schedule.
        var utteranceDurationsForCompose = narrationTimeline.utteranceDurations
        if !narrationTimeline.utteranceAudioURLs.isEmpty,
           narrationTimeline.utteranceAudioURLs.count == narrationTimeline.utteranceDurations.count {
            let fromFiles = try await utteranceDurationsFromAssetFiles(urls: narrationTimeline.utteranceAudioURLs)
            if fromFiles.count == narrationTimeline.utteranceDurations.count {
                utteranceDurationsForCompose = fromFiles
            }
        }

        let blockNarrationDurations: [CMTime]?
        if useStoryBlocks, let ranges = narrationTimeline.storyBlockUtteranceRanges {
            guard ranges.allSatisfy({ $0.lowerBound >= 0 && $0.upperBound <= utteranceDurationsForCompose.count }) else {
                throw ExportError.invalidStoryBlockPlan
            }
            blockNarrationDurations = ranges.map { range in
                range.reduce(CMTime.zero) { partial, index in
                    CMTimeAdd(partial, utteranceDurationsForCompose[index])
                }
            }
        } else {
            blockNarrationDurations = nil
        }

        let totalDuration: CMTime
        switch timingMode {
        case .video:
            totalDuration = minimumVisualDuration
        case .realLife:
            totalDuration = realLifeDuration(
                for: mediaItems,
                narrationDuration: narrationTimeline.duration
            )
        case .story:
            if useStoryBlocks {
                let sumUtterance = utteranceDurationsForCompose.reduce(CMTime.zero, +)
                totalDuration = sumUtterance > .zero ? sumUtterance : minimumVisualDuration
            } else {
                totalDuration = narrationTimeline.duration > .zero
                    ? narrationTimeline.duration
                    : minimumVisualDuration
            }
        }
        /// Preview render is capped at **20s** (including Edit Story) so users can verify captions and pacing quickly; use final export for full length.
        let resolvedDuration: CMTime
        if renderQuality == .preview, let previewCap = renderQuality.maximumDuration {
            resolvedDuration = CMTimeMinimum(totalDuration, previewCap)
        } else {
            resolvedDuration = totalDuration
        }
        let baseTimelineSegments: [TimelineSegment]
        if let descriptor = storyBlockDescriptor,
           timingMode == .story,
           let blockDurs = blockNarrationDurations,
           let paras = paragraphNarrationSegments {
            let sumUtterance = utteranceDurationsForCompose.reduce(CMTime.zero, +)
            baseTimelineSegments = try composeStoryBlockTimelineSegments(
                mediaItems: mediaItems,
                descriptor: descriptor,
                scriptParagraphCount: paras.count,
                blockNarrationDurations: blockDurs,
                totalNarrationDuration: sumUtterance
            )
        } else {
            if useStoryBlocks {
                throw ExportError.invalidStoryBlockPlan
            }
            baseTimelineSegments = try await makeTimelineSegments(
                for: mediaItems,
                totalDuration: totalDuration,
                timingMode: timingMode,
                includeCaptions: includeCaptions
            )
        }

        if useStoryBlocks {
            let hasVideosInTimeline = baseTimelineSegments.contains {
                if case .video = $0.mediaItem.kind { return true }
                return false
            }
            let hasPhotosInTimeline = baseTimelineSegments.contains {
                if case .photo = $0.mediaItem.kind { return true }
                return false
            }
            hasMixedStoryMedia = hasVideosInTimeline && hasPhotosInTimeline
            storyVideoOnlyMedia = hasVideosInTimeline && !hasPhotosInTimeline
            storyUsesCaptionIntermediateFile =
                includeCaptions && hasVideosInTimeline && (hasMixedStoryMedia || !hasPhotosInTimeline)
        }
        /// Always trim preview runs to **`resolvedDuration`**. Relying on **`resolvedDuration < totalDuration`** alone
        /// could skip trimming if **`CMTime`** ordering misbehaved; muxed audio longer than the video track then
        /// stretched **`AVAssetExportSession`** output to the full narration length after a full-length preview build.
        let shouldTrimTimelineToResolved: Bool
        if renderQuality == .preview, renderQuality.maximumDuration != nil {
            shouldTrimTimelineToResolved = true
        } else {
            shouldTrimTimelineToResolved = CMTimeCompare(resolvedDuration, totalDuration) < 0
        }
        let timelineSegments = shouldTrimTimelineToResolved
            ? timelineSegmentsTrimmed(to: resolvedDuration, segments: baseTimelineSegments)
            : baseTimelineSegments
        let videoPressure = videoPressure(for: timelineSegments)
        let renderProfile = resolvedRenderProfile(
            for: renderQuality,
            aspectRatio: aspectRatio,
            duration: resolvedDuration,
            videoPressure: videoPressure,
            timingMode: timingMode,
            mediaItems: mediaItems,
            includeCaptions: includeCaptions,
            videoModeSettings: videoModeSettings
        )
        let trimmedCaptionSegments = !includeCaptions
            ? []
            : captionSegmentsTrimmed(to: resolvedDuration, segments: narrationTimeline.captionSegments)
        let trimmedNarrationURLs = try await narrationURLsTrimmed(
            narrationTimeline.utteranceAudioURLs,
            maxDuration: resolvedDuration
        )

        let storySegmentMusicSlots: [StorySegmentMusicSlot]?
        if useStoryBlocks,
           let desc = storyBlockDescriptor,
           let ranges = narrationTimeline.storyBlockUtteranceRanges,
           let paras = paragraphNarrationSegments,
           !trimmedNarrationURLs.isEmpty {
            storySegmentMusicSlots = try await buildStorySegmentMusicSlots(
                storyParagraphCount: paras.count,
                descriptor: desc,
                musicSpans: storyMusicBedSpans ?? [],
                fallbackMusicURL: backgroundMusicURL,
                blockUtteranceRanges: ranges,
                trimmedNarrationURLs: trimmedNarrationURLs,
                resolvedTimelineDuration: resolvedDuration
            )
        } else {
            storySegmentMusicSlots = nil
        }

        let shouldUseSmoothStoryExport =
            timingMode == .story &&
            (storyVideoOnlyMedia
                || (renderQuality != .preview && (!includeCaptions || hasMixedStoryMedia)))

        if timingMode == .realLife || shouldUseSmoothStoryExport {
            let buildingLabel = timingMode == .realLife ? "Slideshow" : "Story"
            progressHandler?(0.24, "Building a \(buildingLabel) composition.")
            let effectiveSlideshowSettings = effectiveSlideshowExportSettings(
                requestedSettings: renderQuality == .preview ? nil : videoModeSettings,
                mediaItems: mediaItems,
                narrationDuration: narrationTimeline.duration,
                fallbackRenderSize: renderProfile.renderSize,
                fallbackFrameRate: renderProfile.frameRate
            )
            let willBurnCaptionsAfter = includeCaptions && (timingMode == .realLife || storyUsesCaptionIntermediateFile)
            let watermarkInComposition: WatermarkSettings? = (willBurnCaptionsAfter && (watermarkSettings?.isRenderable == true))
                ? nil
                : watermarkSettings
            let smoothOutputURL: URL
            if includeCaptions && (timingMode == .realLife || storyUsesCaptionIntermediateFile) {
                let captionBaseName: String
                if timingMode == .realLife {
                    captionBaseName = "slideshow-caption-base.mov"
                } else if hasMixedStoryMedia {
                    captionBaseName = "story-mixed-base.mov"
                } else {
                    captionBaseName = "story-video-caption-base.mov"
                }
                smoothOutputURL = workspace.appendingPathComponent(captionBaseName)
            } else {
                smoothOutputURL = finalURL
            }

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
                exportPresetName: effectiveSlideshowSettings.presetName,
                workspace: workspace,
                outputURL: smoothOutputURL,
                storySegmentMusic: storySegmentMusicSlots,
                timingMode: timingMode,
                watermarkSettings: watermarkInComposition,
                progressHandler: progressHandler
            )

            if includeCaptions && (timingMode == .realLife || storyUsesCaptionIntermediateFile) {
                progressHandler?(0.9, timingMode == .realLife
                    ? "Burning captions into the slideshow video."
                    : "Burning captions into the smooth story video.")
                try await burnCaptionsIntoVideo(
                    videoURL: smoothOutputURL,
                    captionSegments: trimmedCaptionSegments,
                    renderSize: renderProfile.renderSize,
                    frameRate: renderProfile.frameRate,
                    captionStyle: captionStyle,
                    outputURL: finalURL,
                    timingMode: timingMode,
                    watermarkSettings: watermarkSettings,
                    progressHandler: progressHandler
                )
            }

            progressHandler?(1.0, "Finalizing exported video.")
            return finalURL
        }

        progressHandler?(0.24, renderProfile.longFormOptimized ? "Optimizing a long-form render." : "Rendering video frames.")
        try Task.checkCancellation()

        try await renderSlideshow(
            timelineSegments: timelineSegments,
            captionSegments: trimmedCaptionSegments,
            totalDuration: resolvedDuration,
            renderSize: renderProfile.renderSize,
            frameRate: renderProfile.frameRate,
            videoSampleStride: renderProfile.videoSampleStride,
            captionStyle: captionStyle,
            watermarkSettings: watermarkSettings,
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
            outputURL: finalURL,
            storySegmentMusic: storySegmentMusicSlots
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

    /// Per-block narration duration on the export timeline, aligned to `trimmedNarrationURLs` (preview cap, partial last utterance, etc.).
    private func storyBlockPerBlockDurationsFromTrimmedNarration(
        blockUtteranceRanges: [Range<Int>],
        trimmedNarrationURLs: [URL]
    ) async throws -> [CMTime] {
        var utteranceDurations: [CMTime] = []
        utteranceDurations.reserveCapacity(trimmedNarrationURLs.count)
        for url in trimmedNarrationURLs {
            let asset = AVURLAsset(url: url)
            utteranceDurations.append(try await asset.load(.duration))
        }

        var prefix: [CMTime] = [.zero]
        for d in utteranceDurations {
            prefix.append(prefix.last! + d)
        }
        let n = utteranceDurations.count

        return blockUtteranceRanges.map { range in
            let a = range.lowerBound
            let b = range.upperBound
            if a >= n || a >= b { return CMTime.zero }
            let endIdx = min(b, n)
            return CMTimeSubtract(prefix[endIdx], prefix[a])
        }
    }

    private func reconcileStoryBlockMusicDurationsToTimeline(
        blockDurations: inout [CMTime],
        resolvedTimelineDuration: CMTime
    ) {
        guard !blockDurations.isEmpty else { return }
        let sum = blockDurations.reduce(CMTime.zero, +)
        let delta = CMTimeSubtract(resolvedTimelineDuration, sum)
        guard CMTimeCompare(delta, .zero) != 0, let lastIdx = blockDurations.indices.last else { return }
        let adjusted = CMTimeAdd(blockDurations[lastIdx], delta)
        blockDurations[lastIdx] = CMTimeMaximum(.zero, adjusted)
    }

    private func buildStorySegmentMusicSlots(
        storyParagraphCount: Int,
        descriptor: StoryBlockExportDescriptor,
        musicSpans: [StoryMusicBedSpanExport],
        fallbackMusicURL: URL?,
        blockUtteranceRanges: [Range<Int>],
        trimmedNarrationURLs: [URL],
        resolvedTimelineDuration: CMTime
    ) async throws -> [StorySegmentMusicSlot] {
        let sortedBlocks = descriptor.blocks.sorted { $0.firstParagraphIndex < $1.firstParagraphIndex }
        guard sortedBlocks.count == blockUtteranceRanges.count, storyParagraphCount > 0 else {
            throw ExportError.invalidStoryBlockPlan
        }

        var blockDurations = try await storyBlockPerBlockDurationsFromTrimmedNarration(
            blockUtteranceRanges: blockUtteranceRanges,
            trimmedNarrationURLs: trimmedNarrationURLs
        )
        reconcileStoryBlockMusicDurationsToTimeline(
            blockDurations: &blockDurations,
            resolvedTimelineDuration: resolvedTimelineDuration
        )

        var paragraphDurations = [CMTime](repeating: .zero, count: storyParagraphCount)
        for (block, dur) in zip(sortedBlocks, blockDurations) {
            guard CMTimeCompare(dur, .zero) > 0 else { continue }
            let bf = block.firstParagraphIndex
            let bl = block.lastParagraphIndex
            guard bf >= 0, bl < storyParagraphCount, bf <= bl else { throw ExportError.invalidStoryBlockPlan }
            let n = bl - bf + 1
            let sec = CMTimeGetSeconds(dur) / Double(n)
            let perPara = CMTime(seconds: sec, preferredTimescale: 600)
            for p in bf...bl {
                paragraphDurations[p] = perPara
            }
        }

        var paraSum = paragraphDurations.reduce(CMTime.zero, +)
        let paraDelta = CMTimeSubtract(resolvedTimelineDuration, paraSum)
        if CMTimeCompare(paraDelta, .zero) != 0, storyParagraphCount > 0 {
            let li = storyParagraphCount - 1
            paragraphDurations[li] = CMTimeMaximum(.zero, CMTimeAdd(paragraphDurations[li], paraDelta))
        }

        let sortedSpans = musicSpans.sorted { $0.firstParagraphIndex < $1.firstParagraphIndex }
        func resolvedURL(forParagraph p: Int) -> URL? {
            for span in sortedSpans {
                guard span.firstParagraphIndex <= span.lastParagraphIndex else { continue }
                let lo = max(0, span.firstParagraphIndex)
                let hi = min(storyParagraphCount - 1, span.lastParagraphIndex)
                if p >= lo, p <= hi {
                    return span.soundtrackURL ?? fallbackMusicURL
                }
            }
            return fallbackMusicURL
        }

        var slots: [StorySegmentMusicSlot] = []
        var runURL = resolvedURL(forParagraph: 0)
        var runDur = paragraphDurations[0]
        if storyParagraphCount == 1 {
            slots.append(StorySegmentMusicSlot(duration: runDur, sourceURL: runURL))
        } else {
            for p in 1..<storyParagraphCount {
                let u = resolvedURL(forParagraph: p)
                if urlPairMatchesTimelineMusic(u, runURL) {
                    runDur = CMTimeAdd(runDur, paragraphDurations[p])
                } else {
                    if CMTimeCompare(runDur, .zero) > 0 {
                        slots.append(StorySegmentMusicSlot(duration: runDur, sourceURL: runURL))
                    }
                    runURL = u
                    runDur = paragraphDurations[p]
                }
            }
            if CMTimeCompare(runDur, .zero) > 0 {
                slots.append(StorySegmentMusicSlot(duration: runDur, sourceURL: runURL))
            }
        }

        if slots.isEmpty {
            slots.append(StorySegmentMusicSlot(duration: resolvedTimelineDuration, sourceURL: fallbackMusicURL))
        }
        let slotSum = slots.reduce(CMTime.zero) { CMTimeAdd($0, $1.duration) }
        let slotDelta = CMTimeSubtract(resolvedTimelineDuration, slotSum)
        if CMTimeCompare(slotDelta, .zero) != 0, let li = slots.indices.last {
            slots[li] = StorySegmentMusicSlot(
                duration: CMTimeMaximum(.zero, CMTimeAdd(slots[li].duration, slotDelta)),
                sourceURL: slots[li].sourceURL
            )
        }
        return slots
    }

    /// Compare URLs for mux segment grouping (nil and nil match; same standardized file URL match).
    private func urlPairMatchesTimelineMusic(_ a: URL?, _ b: URL?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (x?, y?):
            return x.standardizedFileURL == y.standardizedFileURL
        default:
            return false
        }
    }

    private func appendLoopedSourceAudio(
        compositionTrack: AVMutableCompositionTrack,
        sourceURL: URL,
        outputStart: CMTime,
        fillDuration: CMTime
    ) async throws {
        guard CMTimeCompare(fillDuration, .zero) > 0 else { return }

        let musicAsset = AVURLAsset(url: sourceURL)
        guard let musicTrack = try await musicAsset.loadTracks(withMediaType: .audio).first else { return }

        let musicDuration = try await musicAsset.load(.duration)
        var cursor = outputStart
        let end = outputStart + fillDuration

        while CMTimeCompare(cursor, end) < 0 {
            let remaining = CMTimeSubtract(end, cursor)
            let segmentDuration = CMTimeMinimum(musicDuration, remaining)
            guard CMTimeCompare(segmentDuration, .zero) > 0 else { break }

            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: segmentDuration),
                of: musicTrack,
                at: cursor
            )
            cursor = cursor + segmentDuration
            if CMTimeCompare(musicDuration, .zero) == 0 { break }
        }
    }

    private func utteranceDurationsFromAssetFiles(urls: [URL]) async throws -> [CMTime] {
        var result: [CMTime] = []
        result.reserveCapacity(urls.count)
        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            result.append(duration)
        }
        return result
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
        try await awaitExportSession(exportSession)

        return outputURL
    }

    private func makeWorkspace() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let workspace = documents.appendingPathComponent("RenderedVideos", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return workspace
    }

    /// Copies `utterance-preview-0…n-1.caf` from **`NarrationPreviewBuilder`**’s workspace into this export’s
    /// `utterance-*.caf` when counts match, avoiding duplicate TTS after **prepareNarrationPreview** (Edit Story).
    private func copyPrebuiltNarrationUtterancesIfAvailable(
        sourceDirectory: URL,
        workspace: URL,
        utteranceCount: Int,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> (urls: [URL], durations: [CMTime])? {
        guard utteranceCount > 0 else { return nil }
        for i in 0..<utteranceCount {
            let src = sourceDirectory.appendingPathComponent("utterance-preview-\(i).caf")
            guard FileManager.default.fileExists(atPath: src.path) else { return nil }
        }
        var urls: [URL] = []
        var durations: [CMTime] = []
        urls.reserveCapacity(utteranceCount)
        durations.reserveCapacity(utteranceCount)
        for i in 0..<utteranceCount {
            let src = sourceDirectory.appendingPathComponent("utterance-preview-\(i).caf")
            let dst = workspace.appendingPathComponent("utterance-\(i).caf")
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: src, to: dst)
            let asset = AVURLAsset(url: dst)
            let d = try await asset.load(.duration)
            urls.append(dst)
            durations.append(d)
        }
        progressHandler?(0.2, "Reusing \(utteranceCount) prepared narration segments (no re-synthesis).")
        return (urls, durations)
    }

    /// Preview exports cap **output** duration (`RenderQuality.maximumDuration`); Edit Story bypass must not
    /// run full-script TTS for that preview—only enough utterances to cover the preview window (see budget).
    @MainActor
    private func synthesizeNarrationIfNeeded(
        text: String,
        voiceIdentifier: String,
        speechRateMultiplier: Double,
        workspace: URL,
        externalCues: [ExternalCue],
        externalNarrationAudioURL: URL?,
        forcedParagraphSegments: [String]? = nil,
        storyBlockNarrationSegments: [String]? = nil,
        renderQuality: RenderQuality = .finalStandard,
        prebuiltUtteranceSourceDirectory: URL? = nil,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws -> NarrationTimeline {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !externalCues.isEmpty || !(storyBlockNarrationSegments?.isEmpty ?? true) else {
            return NarrationTimeline(
                duration: .zero,
                captionSegments: [],
                utteranceAudioURLs: [],
                utteranceDurations: [],
                storyBlockUtteranceRanges: nil
            )
        }

        if let externalNarrationAudioURL, !externalCues.isEmpty {
            progressHandler?(0.22, "Using prepared narration audio.")
            let audioAsset = AVURLAsset(url: externalNarrationAudioURL)
            let audioDuration = try await audioAsset.load(.duration)
            let cueDuration = CMTime(seconds: externalCues.map(\.end).max() ?? 0, preferredTimescale: 600)
            let resolvedDuration = max(audioDuration, cueDuration, CMTime(seconds: 1, preferredTimescale: 600))
            return NarrationTimeline(
                duration: resolvedDuration,
                captionSegments: captionSegments(from: externalCues, voiceIdentifier: voiceIdentifier),
                utteranceAudioURLs: [externalNarrationAudioURL],
                utteranceDurations: [resolvedDuration],
                storyBlockUtteranceRanges: nil
            )
        }

        let narrationSegments: [String]
        let storyBlockUtteranceRanges: [Range<Int>]?
        if let blockScripts = storyBlockNarrationSegments, !blockScripts.isEmpty {
            var flat: [String] = []
            var ranges: [Range<Int>] = []
            var u = 0
            for blockScript in blockScripts {
                var subs = StoryScriptPartition.narrationSegmentsWholeScriptStyle(
                    blockText: blockScript,
                    voiceIdentifier: voiceIdentifier
                )
                if subs.isEmpty {
                    subs = [" "]
                }
                let start = u
                flat.append(contentsOf: subs)
                u += subs.count
                ranges.append(start..<u)
            }
            narrationSegments = flat
            storyBlockUtteranceRanges = ranges
        } else if let forced = forcedParagraphSegments, !forced.isEmpty {
            narrationSegments = forced
            storyBlockUtteranceRanges = nil
        } else {
            // Whole script as one block: same segmentation as each Edit Story block (`narrationSegmentsWholeScriptStyle`).
            var subs = StoryScriptPartition.narrationSegmentsWholeScriptStyle(
                blockText: trimmedText,
                voiceIdentifier: voiceIdentifier
            )
            if subs.isEmpty {
                subs = SpeechVoiceLibrary.narrationSegments(from: trimmedText, optimizeForLongForm: true)
            }
            if subs.isEmpty {
                subs = [" "]
            }
            narrationSegments = subs
            storyBlockUtteranceRanges = nil
        }

        var narrationSegmentsForSynth = narrationSegments
        var blockRangesForSynth = storyBlockUtteranceRanges
        if renderQuality == .preview, let previewCap = renderQuality.maximumDuration {
            let budgetSeconds = CMTimeGetSeconds(previewCap) + 12
            let capped = applyPreviewNarrationSynthesisBudget(
                segments: narrationSegmentsForSynth,
                blockRanges: blockRangesForSynth,
                maxEstimatedSeconds: budgetSeconds,
                speechRateMultiplier: speechRateMultiplier
            )
            narrationSegmentsForSynth = capped.segments
            blockRangesForSynth = capped.blockRanges
        }

        let utterances = narrationSegmentsForSynth.map {
            SpeechVoiceLibrary.makeUtterance(
                from: $0,
                voiceIdentifier: voiceIdentifier,
                speechRateMultiplier: speechRateMultiplier
            )
        }
        var utteranceAudioURLs: [URL] = []
        var utteranceDurations: [CMTime] = []

        if let sourceDir = prebuiltUtteranceSourceDirectory,
           blockRangesForSynth != nil,
           !utterances.isEmpty,
           let reused = try await copyPrebuiltNarrationUtterancesIfAvailable(
                sourceDirectory: sourceDir,
                workspace: workspace,
                utteranceCount: utterances.count,
                progressHandler: progressHandler
            ) {
            utteranceAudioURLs = reused.urls
            utteranceDurations = reused.durations
        } else {
            let totalUtterances = max(utterances.count, 1)
            for (index, utterance) in utterances.enumerated() {
                let step = Double(index + 1) / Double(totalUtterances)
                progressHandler?(0.16 + 0.07 * step, "Synthesizing narration \(index + 1) of \(utterances.count).")
                let utteranceURL = workspace.appendingPathComponent("utterance-\(index).caf")
                let duration = try await renderUtteranceAudio(utterance, outputURL: utteranceURL)
                utteranceAudioURLs.append(utteranceURL)
                utteranceDurations.append(duration)
            }
        }

        let measuredNarrationDuration = utteranceDurations.reduce(CMTime.zero, +)
        let effectiveRate = SpeechVoiceLibrary.effectiveSpeechRateMultiplier(for: speechRateMultiplier)
        let estimatedSecondsRaw = estimatedNarrationSeconds(for: narrationSegmentsForSynth)
        let estimatedSeconds = estimatedSecondsRaw / max(effectiveRate, 0.1)
        let estimatedNarrationDuration = CMTime(
            seconds: estimatedSeconds,
            preferredTimescale: 600
        )
        // Edit Story blocks: drive length from real TTS samples only. Bumping to estimated here
        // stretched the slideshow (or drift-padded the last segment) while audio stayed measured.
        let totalDuration: CMTime
        if blockRangesForSynth != nil {
            totalDuration = max(measuredNarrationDuration, CMTime(seconds: 1, preferredTimescale: 600))
        } else {
            totalDuration = max(measuredNarrationDuration, estimatedNarrationDuration, CMTime(seconds: 1, preferredTimescale: 600))
        }
        let captionSegments = externalCues.isEmpty
            ? timedCaptionSegments(
                from: narrationSegmentsForSynth,
                utteranceDurations: utteranceDurations,
                totalDuration: totalDuration,
                voiceIdentifier: voiceIdentifier
            )
            : captionSegments(from: externalCues, voiceIdentifier: voiceIdentifier)
        let resolvedDuration = externalCues.isEmpty
            ? totalDuration
            : max(totalDuration, CMTime(seconds: externalCues.map(\.end).max() ?? 0, preferredTimescale: 600))

        return NarrationTimeline(
            duration: resolvedDuration,
            captionSegments: captionSegments,
            utteranceAudioURLs: utteranceAudioURLs,
            utteranceDurations: utteranceDurations,
            storyBlockUtteranceRanges: blockRangesForSynth
        )
    }

    /// Limits how many utterances we **synthesize** for preview exports (output is still capped later). Uses the
    /// same per-segment timing heuristic as export estimates so long scripts do not run full TTS for a ~20s sample.
    ///
    /// **Edit Story:** `blockRanges` must stay **one entry per story block**. Older logic used `compactMap`, which
    /// dropped blocks with no utterances in the prefix—breaking alignment with `StoryBlockExportDescriptor` and
    /// throwing `invalidStoryBlockPlan` during preview. We clip each block’s utterance range to `0..<prefix.count`
    /// (empty `lo..<lo` means “no audio for this block in the preview sample”).
    private func applyPreviewNarrationSynthesisBudget(
        segments: [String],
        blockRanges: [Range<Int>]?,
        maxEstimatedSeconds: Double,
        speechRateMultiplier: Double
    ) -> (segments: [String], blockRanges: [Range<Int>]?) {
        guard maxEstimatedSeconds > 0 else { return (segments, blockRanges) }
        let effectiveRate = SpeechVoiceLibrary.effectiveSpeechRateMultiplier(for: speechRateMultiplier)
        func est(_ s: String) -> Double {
            estimatedSecondsForSegment(s) / max(effectiveRate, 0.1)
        }
        let expanded = segments.flatMap { seg in
            PreviewNarrationSegmentBudget.splitToFitEstimatedBudget(seg, maxEstimatedSeconds: maxEstimatedSeconds, estimate: est)
        }
        guard !expanded.isEmpty else { return (segments, blockRanges) }
        var sum = 0.0
        var k = 0
        for seg in expanded {
            sum += est(seg)
            k += 1
            if sum >= maxEstimatedSeconds { break }
        }
        k = max(k, 1)
        let prefix = Array(expanded.prefix(k))
        guard let ranges = blockRanges else { return (prefix, nil) }
        let n = prefix.count
        let clipped: [Range<Int>] = ranges.map { r in
            let hi = min(r.upperBound, n)
            let lo = min(r.lowerBound, hi)
            return lo..<hi
        }
        return (prefix, clipped)
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
        captionStyle: CaptionStyle = .normal,
        watermarkSettings: WatermarkSettings? = nil,
        progressHandler: ((Double, String) -> Void)?,
        outputURL: URL
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        // All keyframes: scene changes stay in sync with audio on decode (default GOP can hold the prior image briefly).
        let compression: [String: Any] = [
            AVVideoMaxKeyFrameIntervalKey: 1,
            AVVideoAllowFrameReorderingKey: false
        ]
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: renderSize.width,
            AVVideoHeightKey: renderSize.height,
            AVVideoCompressionPropertiesKey: compression
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

        let orderedTimelineSegments = timelineSegments.sorted {
            CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0
        }

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
                timelineSegments: orderedTimelineSegments,
                videoFrameCache: videoFrameCache
            )
            try autoreleasepool {
                let pixelBuffer = try makePixelBuffer(
                    from: image,
                    caption: caption,
                    renderSize: renderSize,
                    captionStyle: captionStyle,
                    watermarkSettings: watermarkSettings
                )
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
        outputURL: URL,
        storySegmentMusic: [StorySegmentMusicSlot]? = nil
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
        let compositionVideoAudioTrack = resolvedVideoVolume > 0
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil
        if resolvedVideoVolume > 0, let compositionVideoAudioTrack {
            for segment in timelineSegments {
                guard case let .video(url, _) = segment.mediaItem.kind else { continue }

                let clipAsset = AVURLAsset(url: url)
                guard let clipAudioTrack = try await clipAsset.loadTracks(withMediaType: .audio).first else {
                    continue
                }

                let clipDuration = try await clipAsset.load(.duration)
                let segmentDuration = min(segment.timeRange.duration, clipDuration)
                guard segmentDuration > .zero else { continue }

                try compositionVideoAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: segmentDuration),
                    of: clipAudioTrack,
                    at: segment.timeRange.start
                )
            }

            let clipAudioParameters = AVMutableAudioMixInputParameters(track: compositionVideoAudioTrack)
            clipAudioParameters.setVolume(resolvedVideoVolume, at: .zero)
            audioMixParameters.append(clipAudioParameters)
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

        if let slots = storySegmentMusic, !slots.isEmpty, slots.contains(where: { $0.sourceURL != nil }),
           let compositionMusicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            var musicCursor = CMTime.zero
            for slot in slots {
                if let url = slot.sourceURL {
                    try await appendLoopedSourceAudio(
                        compositionTrack: compositionMusicTrack,
                        sourceURL: url,
                        outputStart: musicCursor,
                        fillDuration: slot.duration
                    )
                }
                musicCursor = musicCursor + slot.duration
            }

            let musicParameters = AVMutableAudioMixInputParameters(track: compositionMusicTrack)
            let resolvedVolume = Float(min(max(backgroundMusicVolume, 0), 1))
            musicParameters.setVolume(resolvedVolume, at: .zero)
            let fadeStart = CMTimeMaximum(.zero, totalDuration - CMTime(seconds: 1.2, preferredTimescale: 600))
            musicParameters.setVolumeRamp(fromStartVolume: resolvedVolume, toEndVolume: 0.0, timeRange: CMTimeRange(start: fadeStart, duration: totalDuration - fadeStart))
            audioMixParameters.append(musicParameters)
        } else if let backgroundMusicURL {
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
        exportSession.timeRange = CMTimeRange(start: .zero, duration: totalDuration)

        if !audioMixParameters.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioMixParameters
            exportSession.audioMix = audioMix
        }

        try await awaitExportSession(exportSession)
    }

    private func exportVideoStitch(
        mediaItems: [MediaItem],
        backgroundMusicURL: URL?,
        backgroundMusicVolume: Double,
        videoAudioVolume: Double,
        maximumDuration: CMTime?,
        videoModeSettings: VideoModeExportSettings?,
        outputURL: URL,
        watermarkSettings: WatermarkSettings? = nil,
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
        let mayAttemptStrictPassthrough = false
        var segmentLayouts: [StitchedVideoSegmentLayout] = []
        let passthroughAudioTrack = mayAttemptStrictPassthrough
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil
        var cursor = CMTime.zero
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

        let videoModeRenderSize = preferredVideoModeRenderSize(
            for: segmentLayouts,
            requestedResolution: videoModeSettings?.resolution.renderSize
        )
        let canAttemptStrictPassthrough = false
        let frameRate = videoModeSettings?.frameRate.value ?? 30
        let presetName = videoModeSettings?.quality.exportPresetName ?? AVAssetExportPresetHighestQuality

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

        let stitchExportRange = CMTimeRange(start: .zero, duration: totalDuration)
        do {
            try await exportStitchedComposition(
                composition,
                presetName: canAttemptStrictPassthrough ? AVAssetExportPresetPassthrough : presetName,
                outputURL: outputURL,
                audioMixParameters: canAttemptStrictPassthrough ? [] : audioMixParameters,
                videoComposition: canAttemptStrictPassthrough
                    ? nil
                    : makeVideoComposition(
                        for: compositionVideoTrack,
                        segmentLayouts: segmentLayouts,
                        totalDuration: totalDuration,
                        targetRenderSize: videoModeRenderSize,
                        frameRate: frameRate,
                        preserveSourceScale: true,
                        watermarkSettings: watermarkSettings
                    ),
                exportTimeRange: stitchExportRange,
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
                presetName: presetName,
                outputURL: outputURL,
                audioMixParameters: audioMixParameters,
                videoComposition: makeVideoComposition(
                    for: compositionVideoTrack,
                    segmentLayouts: segmentLayouts,
                    totalDuration: totalDuration,
                    targetRenderSize: videoModeRenderSize,
                    frameRate: frameRate,
                    preserveSourceScale: true,
                    watermarkSettings: watermarkSettings
                ),
                exportTimeRange: stitchExportRange,
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
        exportPresetName: String,
        workspace: URL,
        outputURL: URL,
        storySegmentMusic: [StorySegmentMusicSlot]? = nil,
        timingMode: TimingMode,
        watermarkSettings: WatermarkSettings? = nil,
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
        let compositionVideoAudioTrack = resolvedVideoVolume > 0
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

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
                    outputURL: photoClipURL,
                    watermarkSettings: watermarkSettings
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
                   let compositionVideoAudioTrack {
                    try compositionVideoAudioTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: clipDuration),
                        of: sourceAudioTrack,
                        at: segment.timeRange.start
                    )
                }
            }
        }

        if let compositionVideoAudioTrack, resolvedVideoVolume > 0 {
            let clipAudioParameters = AVMutableAudioMixInputParameters(track: compositionVideoAudioTrack)
            clipAudioParameters.setVolume(resolvedVideoVolume, at: .zero)
            audioMixParameters.append(clipAudioParameters)
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

        if let slots = storySegmentMusic, !slots.isEmpty, slots.contains(where: { $0.sourceURL != nil }),
           let compositionMusicTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            progressHandler?(0.72, "Mixing per-segment music into the story video.")
            var musicCursor = CMTime.zero
            for slot in slots {
                if let url = slot.sourceURL {
                    try await appendLoopedSourceAudio(
                        compositionTrack: compositionMusicTrack,
                        sourceURL: url,
                        outputStart: musicCursor,
                        fillDuration: slot.duration
                    )
                }
                musicCursor = musicCursor + slot.duration
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
        } else if let backgroundMusicURL {
            let musicLabel = timingMode == .realLife ? "Slideshow" : "Story"
            progressHandler?(0.72, "Mixing background music into the \(musicLabel) video.")
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

        let realLifeRenderSize = preferredVideoModeRenderSize(
            for: segmentLayouts,
            requestedResolution: renderSize
        )

        try await exportStitchedComposition(
            composition,
            presetName: exportPresetName,
            outputURL: outputURL,
            audioMixParameters: audioMixParameters,
            videoComposition: makeVideoComposition(
                for: compositionVideoTrack,
                segmentLayouts: segmentLayouts,
                totalDuration: totalDuration,
                targetRenderSize: realLifeRenderSize,
                frameRate: frameRate,
                preserveSourceScale: true,
                watermarkSettings: watermarkSettings
            ),
            exportTimeRange: CMTimeRange(start: .zero, duration: totalDuration),
            progressMessage: "Exporting the \(timingMode.rawValue) video.",
            progressHandler: progressHandler
        )
    }

    private func burnCaptionsIntoVideo(
        videoURL: URL,
        captionSegments: [CaptionSegment],
        renderSize: CGSize,
        frameRate: Int32,
        captionStyle: CaptionStyle,
        outputURL: URL,
        timingMode: TimingMode,
        watermarkSettings: WatermarkSettings? = nil,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.missingVideoTrack
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.missingVideoTrack
        }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        for audioTrack in audioTracks {
            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continue
            }

            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioTrack,
                at: .zero
            )
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = CGSize(
            width: max(round(renderSize.width / 2) * 2, 2),
            height: max(round(renderSize.height / 2) * 2, 2)
        )
        videoComposition.frameDuration = CMTime(value: 1, timescale: frameRate)

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoComposition.renderSize)
        parentLayer.masksToBounds = true

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        let captionsLayer = makeCaptionOverlayLayer(
            for: captionSegments,
            renderSize: videoComposition.renderSize,
            captionStyle: captionStyle
        )
        parentLayer.addSublayer(captionsLayer)

        if let wms = watermarkSettings, wms.isRenderable, let wmLayer = makeStaticWatermarkLayer(renderSize: videoComposition.renderSize, settings: wms) {
            parentLayer.addSublayer(wmLayer)
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        try await exportStitchedComposition(
            composition,
            presetName: AVAssetExportPresetHighestQuality,
            outputURL: outputURL,
            audioMixParameters: [],
            videoComposition: videoComposition,
            exportTimeRange: CMTimeRange(start: .zero, duration: duration),
            progressMessage: "Exporting the \(timingMode.rawValue) video with captions.",
            progressHandler: progressHandler
        )
    }

    private func captionParagraphStyle() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return paragraph
    }

    /// Rounded system design reads softer on screen; bold keeps short captions clear without feeling as loud as heavy.
    private func readerFriendlyStylishFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        if let rounded = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: rounded, size: size)
        }
        return base
    }

    /// Stroke-only pass (clear fill + positive `strokeWidth`) drawn under the fill pass so Chinese text stays pure white.
    private func stylishOutlineAttributed(text: String, fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: readerFriendlyStylishFont(size: fontSize),
            .foregroundColor: UIColor.clear,
            .strokeColor: UIColor.black.withAlphaComponent(0.9),
            .strokeWidth: 2.85,
            .paragraphStyle: paragraph
        ])
    }

    private func stylishFillAttributed(text: String, fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.45)
        shadow.shadowOffset = CGSize(width: 0, height: 2)
        shadow.shadowBlurRadius = max(4, fontSize * 0.14)
        return NSAttributedString(string: text, attributes: [
            .font: readerFriendlyStylishFont(size: fontSize),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ])
    }

    private func normalCaptionAttributed(text: String, fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph
        ])
    }

    private struct CaptionLayoutResult {
        let textWidth: CGFloat
        let textHeight: CGFloat
        let boxPadding: CGFloat
        let cornerRadius: CGFloat
        let backgroundAlpha: CGFloat
        let borderWidth: CGFloat
        let borderColor: CGColor?
        let textLayerExtraHeight: CGFloat
        /// Used when `stylishOutline` / `stylishFill` are nil (Normal).
        let singleAttributed: NSAttributedString
        let stylishOutline: NSAttributedString?
        let stylishFill: NSAttributedString?
    }

    private func layoutCaptionForVideo(text: String, renderSize: CGSize, style: CaptionStyle) -> CaptionLayoutResult {
        let widthScale = max(min(renderSize.width / 720, 1.0), 0.5)
        let paragraph = captionParagraphStyle()
        if style == .stylish {
            paragraph.lineSpacing = max(4, 5 * widthScale)
        }
        let maxTextWidth = renderSize.width - max(72, 120 * widthScale)
        let maxTextHeight: CGFloat = style == .stylish
            ? max(200, 340 * widthScale)
            : max(140, 240 * widthScale)
        let minimumFontSize: CGFloat = style == .stylish
            ? max(15, 21 * widthScale)
            : max(14, 20 * widthScale)
        let portrait = renderSize.width < renderSize.height
        let baseStart: CGFloat = portrait ? max(18, 34 * widthScale) : max(16, 30 * widthScale)
        var fontSize: CGFloat = style == .stylish ? baseStart * 1.5 : baseStart

        var single = normalCaptionAttributed(text: text, fontSize: fontSize, paragraph: paragraph)
        var outline: NSAttributedString?
        var fill: NSAttributedString?
        var measuredW: CGFloat = 0
        var measuredH: CGFloat = 0

        while fontSize >= minimumFontSize {
            if style == .stylish {
                let o = stylishOutlineAttributed(text: text, fontSize: fontSize, paragraph: paragraph)
                let f = stylishFillAttributed(text: text, fontSize: fontSize, paragraph: paragraph)
                let r1 = o.boundingRect(
                    with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).integral
                let r2 = f.boundingRect(
                    with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).integral
                measuredW = max(r1.width, r2.width)
                measuredH = max(r1.height, r2.height)
                if measuredH <= maxTextHeight {
                    outline = o
                    fill = f
                    single = f
                    break
                }
            } else {
                single = normalCaptionAttributed(text: text, fontSize: fontSize, paragraph: paragraph)
                let r = single.boundingRect(
                    with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).integral
                measuredW = r.width
                measuredH = r.height
                if measuredH <= maxTextHeight { break }
            }
            fontSize -= 2
        }

        if style == .stylish, outline == nil || fill == nil {
            let o = stylishOutlineAttributed(text: text, fontSize: minimumFontSize, paragraph: paragraph)
            let f = stylishFillAttributed(text: text, fontSize: minimumFontSize, paragraph: paragraph)
            let r1 = o.boundingRect(
                with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).integral
            let r2 = f.boundingRect(
                with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).integral
            outline = o
            fill = f
            single = f
            measuredW = max(r1.width, r2.width)
            measuredH = max(r1.height, r2.height)
        }

        let boxPadding: CGFloat = style == .stylish
            ? max(10, 14 * widthScale)
            : max(10, 16 * widthScale)
        let cornerRadius: CGFloat = style == .stylish ? max(12, 18 * widthScale) : 32
        let backgroundAlpha: CGFloat = style == .stylish ? 0.40 : 0.42
        let borderWidth: CGFloat = 0
        let borderColor: CGColor? = nil
        let textLayerExtraHeight: CGFloat = style == .stylish ? 22 : 4

        return CaptionLayoutResult(
            textWidth: measuredW,
            textHeight: measuredH,
            boxPadding: boxPadding,
            cornerRadius: cornerRadius,
            backgroundAlpha: backgroundAlpha,
            borderWidth: borderWidth,
            borderColor: borderColor,
            textLayerExtraHeight: textLayerExtraHeight,
            singleAttributed: single,
            stylishOutline: style == .stylish ? outline : nil,
            stylishFill: style == .stylish ? fill : nil
        )
    }

    private func makeCaptionOverlayLayer(
        for segments: [CaptionSegment],
        renderSize: CGSize,
        captionStyle: CaptionStyle
    ) -> CALayer {
        let rootLayer = CALayer()
        rootLayer.frame = CGRect(origin: .zero, size: renderSize)

        for segment in segments where segment.timeRange.duration > .zero {
            let captionLayer = makeAnimatedCaptionLayer(
                text: segment.text,
                renderSize: renderSize,
                captionStyle: captionStyle
            )
            let startSeconds = max(CMTimeGetSeconds(segment.timeRange.start), 0)
            let durationSeconds = max(CMTimeGetSeconds(segment.timeRange.duration), 0.1)

            let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnimation.values = [0.0, 1.0, 1.0, 0.0]
            opacityAnimation.keyTimes = [0.0, 0.08, 0.92, 1.0]
            opacityAnimation.beginTime = AVCoreAnimationBeginTimeAtZero + startSeconds
            opacityAnimation.duration = durationSeconds
            opacityAnimation.isRemovedOnCompletion = false
            opacityAnimation.fillMode = .forwards
            captionLayer.add(opacityAnimation, forKey: "captionOpacity")
            rootLayer.addSublayer(captionLayer)
        }

        return rootLayer
    }

    private func makeAnimatedCaptionLayer(text: String, renderSize: CGSize, captionStyle: CaptionStyle) -> CALayer {
        let layout = layoutCaptionForVideo(text: text, renderSize: renderSize, style: captionStyle)
        let bottomInset = max(renderSize.height * 0.025, 24)
        let boxRect = CGRect(
            x: (renderSize.width - layout.textWidth) / 2 - layout.boxPadding,
            y: bottomInset,
            width: layout.textWidth + (layout.boxPadding * 2),
            height: layout.textHeight + (layout.boxPadding * 2)
        )

        let containerLayer = CALayer()
        containerLayer.frame = boxRect
        containerLayer.opacity = 0

        if layout.backgroundAlpha > 0 {
            let backgroundLayer = CALayer()
            backgroundLayer.frame = containerLayer.bounds
            backgroundLayer.backgroundColor = UIColor.black.withAlphaComponent(layout.backgroundAlpha).cgColor
            backgroundLayer.cornerRadius = layout.cornerRadius
            backgroundLayer.masksToBounds = true
            if layout.borderWidth > 0, let borderColor = layout.borderColor {
                backgroundLayer.borderWidth = layout.borderWidth
                backgroundLayer.borderColor = borderColor
            }
            containerLayer.addSublayer(backgroundLayer)
        }

        let textFrame = CGRect(
            x: layout.boxPadding,
            y: layout.boxPadding,
            width: layout.textWidth,
            height: layout.textHeight + layout.textLayerExtraHeight
        )

        if let outline = layout.stylishOutline, let fill = layout.stylishFill {
            let outlineLayer = CATextLayer()
            outlineLayer.frame = textFrame
            outlineLayer.string = outline
            outlineLayer.contentsScale = UIScreen.main.scale
            outlineLayer.alignmentMode = .center
            outlineLayer.isWrapped = true

            let fillLayer = CATextLayer()
            fillLayer.frame = textFrame
            fillLayer.string = fill
            fillLayer.contentsScale = UIScreen.main.scale
            fillLayer.alignmentMode = .center
            fillLayer.isWrapped = true

            containerLayer.addSublayer(outlineLayer)
            containerLayer.addSublayer(fillLayer)
        } else {
            let textLayer = CATextLayer()
            textLayer.frame = textFrame
            textLayer.string = layout.singleAttributed
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.alignmentMode = .center
            textLayer.isWrapped = true
            containerLayer.addSublayer(textLayer)
        }

        return containerLayer
    }

    private func renderPhotoSegmentClip(
        image: UIImage,
        duration: CMTime,
        renderSize: CGSize,
        frameRate: Int32,
        outputURL: URL,
        watermarkSettings: WatermarkSettings? = nil
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
            captionStyle: .normal,
            watermarkSettings: watermarkSettings,
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
        exportTimeRange: CMTimeRange? = nil,
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
        if let exportTimeRange {
            exportSession.timeRange = exportTimeRange
        }

        if !audioMixParameters.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioMixParameters
            exportSession.audioMix = audioMix
        }

        if let videoComposition {
            exportSession.videoComposition = videoComposition
        }

        progressHandler?(0.88, progressMessage)
        try await awaitExportSession(exportSession)
    }

    /// When the render task is cancelled (e.g. **Stop**), `cancelExport()` tears down the in-flight session; relying only on `Task.checkCancellation()` inside long `AVAssetExportSession` work would not stop encoding promptly.
    private func awaitExportSession(_ exportSession: AVAssetExportSession) async throws {
        try await withTaskCancellationHandler {
            await exportSession.export()
            if let error = exportSession.error {
                throw error
            }
            switch exportSession.status {
            case .completed:
                return
            case .cancelled:
                throw CancellationError()
            case .unknown, .waiting, .exporting, .failed:
                throw ExportError.exportFailed
            @unknown default:
                throw ExportError.exportFailed
            }
        } onCancel: {
            exportSession.cancelExport()
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
            targetRenderSize: nil,
            frameRate: 30,
            preserveSourceScale: false,
            watermarkSettings: nil
        )
    }

    private func makeVideoComposition(
        for compositionVideoTrack: AVMutableCompositionTrack,
        segmentLayouts: [StitchedVideoSegmentLayout],
        totalDuration: CMTime,
        targetRenderSize: CGSize?,
        frameRate: Int32,
        preserveSourceScale: Bool,
        watermarkSettings: WatermarkSettings? = nil
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
                renderSize: safeRenderSize,
                preserveSourceScale: preserveSourceScale
            )
            layerInstruction.setTransform(fittedTransform, at: layout.timeRange.start)
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = safeRenderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: frameRate)

        if let wms = watermarkSettings, wms.isRenderable, let wmLayer = makeStaticWatermarkLayer(
            renderSize: videoComposition.renderSize,
            settings: wms
        ) {
            let parentLayer = CALayer()
            parentLayer.frame = CGRect(origin: .zero, size: videoComposition.renderSize)
            parentLayer.masksToBounds = true
            let videoLayer = CALayer()
            videoLayer.frame = parentLayer.frame
            parentLayer.addSublayer(videoLayer)
            parentLayer.addSublayer(wmLayer)
            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parentLayer
            )
        }

        return videoComposition
    }

    private func preferredVideoModeRenderSize(
        for segmentLayouts: [StitchedVideoSegmentLayout],
        requestedResolution: CGSize?
    ) -> CGSize {
        let measuredSize = segmentLayouts.reduce(CGSize.zero) { currentMax, layout in
            let transformedSize = transformedVideoSize(for: layout)
            return CGSize(
                width: max(currentMax.width, transformedSize.width),
                height: max(currentMax.height, transformedSize.height)
            )
        }

        let defaultBase = CGSize(
            width: max(max(measuredSize.width, measuredSize.height), 2),
            height: max(min(measuredSize.width, measuredSize.height), 2)
        )
        var baseSize = requestedResolution ?? defaultBase
        let dominantOrientation = dominantVideoOrientation(for: segmentLayouts)

        switch dominantOrientation {
        case .vertical where baseSize.width > baseSize.height:
            baseSize = CGSize(width: baseSize.height, height: baseSize.width)
        case .horizontal where baseSize.height > baseSize.width:
            baseSize = CGSize(width: baseSize.height, height: baseSize.width)
        default:
            break
        }

        return baseSize
    }

    private func fittedTransform(
        preferredTransform: CGAffineTransform,
        naturalSize: CGSize,
        renderSize: CGSize,
        preserveSourceScale: Bool
    ) -> CGAffineTransform {
        let transformedBounds = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
        let safeWidth = max(transformedBounds.width, 1)
        let safeHeight = max(transformedBounds.height, 1)
        let fitScale = min(renderSize.width / safeWidth, renderSize.height / safeHeight)
        let scale = preserveSourceScale ? min(fitScale, 1) : fitScale
        let scaledWidth = safeWidth * scale
        let scaledHeight = safeHeight * scale
        let translationToOrigin = CGAffineTransform(
            translationX: -transformedBounds.minX,
            y: -transformedBounds.minY
        )
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
        let centeredTranslation = CGAffineTransform(
            translationX: (renderSize.width - scaledWidth) / 2,
            y: (renderSize.height - scaledHeight) / 2
        )
        return preferredTransform
            .concatenating(translationToOrigin)
            .concatenating(scaleTransform)
            .concatenating(centeredTranslation)
    }

    private enum VideoOrientation {
        case vertical
        case horizontal
    }

    private func dominantVideoOrientation(for segmentLayouts: [StitchedVideoSegmentLayout]) -> VideoOrientation {
        var verticalSeconds: Double = 0
        var horizontalSeconds: Double = 0

        for layout in segmentLayouts {
            let size = transformedVideoSize(for: layout)
            let seconds = CMTimeGetSeconds(layout.timeRange.duration)
            if size.height > size.width {
                verticalSeconds += seconds
            } else {
                horizontalSeconds += seconds
            }
        }

        return verticalSeconds > horizontalSeconds ? .vertical : .horizontal
    }

    private func transformedVideoSize(for layout: StitchedVideoSegmentLayout) -> CGSize {
        let transformedBounds = CGRect(origin: .zero, size: layout.naturalSize)
            .applying(layout.preferredTransform)
            .standardized
        return CGSize(width: transformedBounds.width, height: transformedBounds.height)
    }

    /// Pillarboxes / letterboxes: scales `image` down to fit `renderSize` and returns a **centered** rect in
    /// UIKit-style coordinates (matches flipped bitmap context below). Uses pixel dimensions from **`cgImage`** when
    /// present so aspect matches what **`UIImage.draw(in:)`** renders.
    private func centeredAspectFitRect(for image: UIImage, renderSize: CGSize) -> CGRect {
        let pixelWidth: CGFloat
        let pixelHeight: CGFloat
        if let cg = image.cgImage {
            pixelWidth = CGFloat(cg.width)
            pixelHeight = CGFloat(cg.height)
        } else {
            pixelWidth = image.size.width * image.scale
            pixelHeight = image.size.height * image.scale
        }
        guard pixelWidth > 0, pixelHeight > 0 else {
            return CGRect(origin: .zero, size: renderSize)
        }
        let rw = renderSize.width
        let rh = renderSize.height
        let scale = min(rw / pixelWidth, rh / pixelHeight)
        let fw = pixelWidth * scale
        let fh = pixelHeight * scale
        let x = (rw - fw) / 2
        let y = (rh - fh) / 2
        return CGRect(x: x, y: y, width: fw, height: fh)
    }

    // MARK: - Watermark layout (output pixels, scales with render size; no hardcoded “logo px” for all exports)

    /// Inset from each edge in **output** pixel space, clamped for safe margins on TV / players (tuned so brand marks read like typical web/video corner logos).
    private static func safeOutputPadding(_ renderSize: CGSize) -> CGFloat {
        let m = min(renderSize.width, renderSize.height)
        let fromScale = m * 0.012
        return min(28, max(10, fromScale))
    }

    private static func clampedWatermarkSizeScale(_ scale: CGFloat) -> CGFloat {
        min(4.0, max(0.35, scale))
    }

    /// Longest side of a uniform scale to final output. Reference: ~70px on the **short** side at 1080p (× `sizeScale` up to 4×), then scales with output size; cap allows large 4K marks.
    private static func watermarkImageMaxOutputSpan(_ renderSize: CGSize, sizeScale: CGFloat) -> CGFloat {
        let m = min(renderSize.width, renderSize.height)
        let at1080: CGFloat = 70
        let ref: CGFloat = 1080
        let s = clampedWatermarkSizeScale(sizeScale)
        // Hard cap relative to frame so a “YouTube-style” mark can be reached without unbounded size.
        let cap = min(0.32 * m, 768)
        return max(28, min(cap, at1080 * (m / ref) * s))
    }

    /// Settings preview: same formula as final export. Pass the preview **card** size (e.g. from `GeometryReader`).
    static func referenceWatermarkImageMaxSpanForPreview(previewSize: CGSize, sizeScale: CGFloat = 1.0) -> CGFloat {
        watermarkImageMaxOutputSpan(previewSize, sizeScale: sizeScale)
    }

    private static func layoutWatermarkText(
        _ text: String,
        renderSize: CGSize,
        sizeScale: CGFloat
    ) -> (string: NSAttributedString, size: CGSize) {
        let m = min(renderSize.width, renderSize.height)
        let baseAt1080: CGFloat = 18
        let ref: CGFloat = 1080
        let scale = clampedWatermarkSizeScale(sizeScale)
        let fontSize = max(9, min(160, baseAt1080 * (m / ref) * scale))
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.5)
        shadow.shadowOffset = CGSize(width: 0, height: 1.2)
        shadow.shadowBlurRadius = 1.2
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let str = NSAttributedString(string: trimmed, attributes: [
            .font: font,
            .foregroundColor: UIColor.white,
            .shadow: shadow
        ])
        let maxW = renderSize.width * 0.48
        let bounding = str.boundingRect(
            with: CGSize(width: maxW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let w = min(ceil(bounding.width) + 4, maxW)
        let h = ceil(bounding.height) + 2
        return (str, CGSize(width: w, height: h))
    }

    /// Uniformly fits the image into `maxSide` on the long side. **Allows upscaling** so small source PNGs still reach the target span (no `min(..., 1)` cap).
    private static func sizeForWatermarkImage(_ image: UIImage, maxSide: CGFloat) -> CGSize {
        let w = max(image.size.width, 1)
        let h = max(image.size.height, 1)
        let s = min(maxSide / w, maxSide / h)
        return CGSize(width: w * s, height: h * s)
    }

    private static func watermarkFrame(
        contentSize: CGSize,
        renderSize: CGSize,
        anchor: WatermarkSettings.Anchor
    ) -> CGRect {
        let pad = safeOutputPadding(renderSize)
        let w = contentSize.width
        let h = contentSize.height
        let W = renderSize.width
        let H = renderSize.height
        let x: CGFloat
        let y: CGFloat
        switch anchor {
        case .topLeft: x = pad; y = pad
        case .topRight: x = W - w - pad; y = pad
        case .bottomLeft: x = pad; y = H - h - pad
        case .bottomRight: x = W - w - pad; y = H - h - pad
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func textAlignmentForWatermark(_ anchor: WatermarkSettings.Anchor) -> CATextLayerAlignmentMode {
        switch anchor {
        case .topLeft, .bottomLeft: return .left
        case .topRight, .bottomRight: return .right
        }
    }

    private func makeStaticWatermarkLayer(renderSize: CGSize, settings: WatermarkSettings) -> CALayer? {
        let o = min(1, max(0, settings.opacity))
        switch settings.mode {
        case .text:
            let t = settings.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            let (attr, s) = Self.layoutWatermarkText(
                t,
                renderSize: renderSize,
                sizeScale: settings.sizeScale
            )
            let textLayer = CATextLayer()
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.string = attr
            textLayer.alignmentMode = Self.textAlignmentForWatermark(settings.anchor)
            textLayer.isWrapped = true
            textLayer.isOpaque = false
            textLayer.backgroundColor = nil
            textLayer.frame = Self.watermarkFrame(
                contentSize: s,
                renderSize: renderSize,
                anchor: settings.anchor
            )
            textLayer.opacity = Float(o)
            return textLayer
        case .image:
            guard let url = settings.imageFileURL,
                  let image = UIImage(contentsOfFile: url.path),
                  let cg = image.cgImage else { return nil }
            let maxSpan = Self.watermarkImageMaxOutputSpan(renderSize, sizeScale: settings.sizeScale)
            let out = Self.sizeForWatermarkImage(image, maxSide: maxSpan)
            let imageLayer = CALayer()
            imageLayer.contents = cg
            imageLayer.contentsGravity = .resizeAspect
            imageLayer.isOpaque = false
            imageLayer.frame = Self.watermarkFrame(
                contentSize: out,
                renderSize: renderSize,
                anchor: settings.anchor
            )
            imageLayer.opacity = Float(o)
            // Helps dark logos on dark video (separate from user opacity)
            imageLayer.masksToBounds = false
            imageLayer.shadowColor = UIColor.black.cgColor
            imageLayer.shadowOffset = CGSize(width: 0, height: 1)
            imageLayer.shadowRadius = 3.5
            imageLayer.shadowOpacity = 0.55
            imageLayer.shadowPath = UIBezierPath(
                rect: CGRect(origin: .zero, size: out)
            ).cgPath
            return imageLayer
        }
    }

    private func drawWatermarkInPixelBuffer(
        _ settings: WatermarkSettings,
        in context: CGContext,
        renderSize: CGSize
    ) {
        UIGraphicsPushContext(context)
        let o = min(1, max(0, settings.opacity))
        switch settings.mode {
        case .text:
            let t = settings.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else {
                UIGraphicsPopContext()
                return
            }
            let (attr, s) = Self.layoutWatermarkText(
                t,
                renderSize: renderSize,
                sizeScale: settings.sizeScale
            )
            let textRect = Self.watermarkFrame(
                contentSize: s,
                renderSize: renderSize,
                anchor: settings.anchor
            )
            context.saveGState()
            context.setAlpha(o)
            attr.draw(
                with: textRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            context.restoreGState()
        case .image:
            guard let url = settings.imageFileURL, let image = UIImage(contentsOfFile: url.path) else {
                UIGraphicsPopContext()
                return
            }
            let maxSpan = Self.watermarkImageMaxOutputSpan(renderSize, sizeScale: settings.sizeScale)
            let out = Self.sizeForWatermarkImage(image, maxSide: maxSpan)
            let r = Self.watermarkFrame(
                contentSize: out,
                renderSize: renderSize,
                anchor: settings.anchor
            )
            // Slight drop shadow + premultiplied PNG: blend at user opacity; image alpha is preserved.
            context.saveGState()
            let shadow = UIColor.black.withAlphaComponent(0.5)
            context.setShadow(
                offset: CGSize(width: 0, height: 1.5),
                blur: 3.2,
                color: shadow.cgColor
            )
            image.draw(in: r, blendMode: .normal, alpha: o)
            context.restoreGState()
        }
        UIGraphicsPopContext()
    }

    private func makePixelBuffer(
        from image: UIImage,
        caption: String?,
        renderSize: CGSize,
        captionStyle: CaptionStyle,
        watermarkSettings: WatermarkSettings? = nil
    ) throws -> CVPixelBuffer {
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

        let aspectFitRect = centeredAspectFitRect(for: image, renderSize: renderSize)
        UIGraphicsPushContext(context)
        image.draw(in: aspectFitRect)

        if let caption, !caption.isEmpty {
            drawCaption(caption, in: context, renderSize: renderSize, captionStyle: captionStyle)
        }
        if let wms = watermarkSettings, wms.isRenderable {
            drawWatermarkInPixelBuffer(wms, in: context, renderSize: renderSize)
        }
        UIGraphicsPopContext()

        return pixelBuffer
    }

    private func estimatedTimelineSegments(
        for mediaItems: [MediaItem],
        totalDuration: CMTime,
        timingMode: TimingMode
    ) -> [TimelineSegment] {
        guard !mediaItems.isEmpty, totalDuration > .zero else { return [] }

        if timingMode == .realLife {
            return realLifeTimelineSegments(for: mediaItems, totalDuration: totalDuration)
        }

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

    private func drawCaption(_ caption: String, in context: CGContext, renderSize: CGSize, captionStyle: CaptionStyle) {
        let layout = layoutCaptionForVideo(text: caption, renderSize: renderSize, style: captionStyle)
        let bottomInset = max(renderSize.height * 0.025, 24)
        let boxRect = CGRect(
            x: (renderSize.width - layout.textWidth) / 2 - layout.boxPadding,
            y: renderSize.height - layout.textHeight - (layout.boxPadding * 2) - bottomInset,
            width: layout.textWidth + (layout.boxPadding * 2),
            height: layout.textHeight + (layout.boxPadding * 2)
        )

        if layout.backgroundAlpha > 0 {
            let boxPath = UIBezierPath(roundedRect: boxRect, cornerRadius: layout.cornerRadius)
            context.saveGState()
            context.setFillColor(UIColor.black.withAlphaComponent(layout.backgroundAlpha).cgColor)
            context.addPath(boxPath.cgPath)
            context.fillPath()
            if layout.borderWidth > 0, let borderCG = layout.borderColor {
                context.setStrokeColor(borderCG)
                context.setLineWidth(layout.borderWidth)
                context.addPath(boxPath.cgPath)
                context.strokePath()
            }
            context.restoreGState()
        }

        let textRect = CGRect(
            x: (renderSize.width - layout.textWidth) / 2,
            y: boxRect.minY + layout.boxPadding,
            width: layout.textWidth,
            height: layout.textHeight + layout.textLayerExtraHeight
        )

        UIGraphicsPushContext(context)
        if let outline = layout.stylishOutline, let fill = layout.stylishFill {
            outline.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            fill.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        } else {
            layout.singleAttributed.draw(
                with: textRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
        UIGraphicsPopContext()
    }

    private func captionText(for currentTime: CMTime, segments: [CaptionSegment]) -> String? {
        guard !segments.isEmpty else { return nil }

        let lead = CMTime(seconds: SubtitleTimelineEngine.displayLeadSeconds, preferredTimescale: 600)
        let lookupTime = CMTimeMaximum(.zero, CMTimeAdd(currentTime, lead))

        for segment in segments where segment.timeRange.containsTime(lookupTime) {
            return segment.text
        }

        if lookupTime >= segments.last?.timeRange.end ?? .zero {
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

    private func realLifeVisualDuration(for mediaItems: [MediaItem]) -> CMTime {
        let photoCount = mediaItems.filter {
            if case .photo = $0.kind { return true }
            return false
        }.count
        let hasVideo = mediaItems.contains {
            if case .video = $0.kind { return true }
            return false
        }

        if !hasVideo && photoCount > 0 {
            return CMTime(seconds: max(Double(photoCount) * 8.0, 8.0), preferredTimescale: 600)
        }

        return minimumVisualDuration(for: mediaItems)
    }

    private func realLifeDuration(for mediaItems: [MediaItem], narrationDuration: CMTime) -> CMTime {
        let visualDuration = realLifeVisualDuration(for: mediaItems)
        guard narrationDuration > .zero else {
            return visualDuration
        }
        return max(visualDuration, narrationDuration)
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

    private func composeStoryBlockTimelineSegments(
        mediaItems: [MediaItem],
        descriptor: StoryBlockExportDescriptor,
        scriptParagraphCount: Int,
        blockNarrationDurations: [CMTime],
        totalNarrationDuration: CMTime
    ) throws -> [TimelineSegment] {
        guard scriptParagraphCount > 0, !blockNarrationDurations.isEmpty else { throw ExportError.invalidStoryBlockPlan }

        var covered = Set<Int>()
        let sortedBlocks = descriptor.blocks.sorted { $0.firstParagraphIndex < $1.firstParagraphIndex }
        guard sortedBlocks.count == blockNarrationDurations.count else { throw ExportError.invalidStoryBlockPlan }

        for block in sortedBlocks {
            guard !block.mediaIndices.isEmpty,
                  block.mediaIndices.allSatisfy({ $0 >= 0 && $0 < mediaItems.count }),
                  block.firstParagraphIndex >= 0,
                  block.lastParagraphIndex >= block.firstParagraphIndex,
                  block.lastParagraphIndex < scriptParagraphCount else {
                throw ExportError.invalidStoryBlockPlan
            }
            for idx in block.firstParagraphIndex...block.lastParagraphIndex {
                guard !covered.contains(idx) else { throw ExportError.invalidStoryBlockPlan }
                covered.insert(idx)
            }
        }
        guard covered.count == scriptParagraphCount else { throw ExportError.invalidStoryBlockPlan }

        var output: [TimelineSegment] = []
        var offset = CMTime.zero

        for (block, blockDuration) in zip(sortedBlocks, blockNarrationDurations) {
            let blockMedia = block.mediaIndices.map { mediaItems[$0] }
            var effectiveDuration = blockDuration
            if effectiveDuration <= .zero {
                effectiveDuration = CMTime(seconds: 0.1, preferredTimescale: 600)
            }
            let localSegments = timelineSegmentsForEditStoryBlock(mediaItems: blockMedia, blockDuration: effectiveDuration)
            for seg in localSegments {
                let shiftedStart = CMTimeAdd(offset, seg.timeRange.start)
                output.append(
                    TimelineSegment(
                        mediaItem: seg.mediaItem,
                        timeRange: CMTimeRange(start: shiftedStart, duration: seg.timeRange.duration)
                    )
                )
            }
            offset = CMTimeAdd(offset, effectiveDuration)
        }

        let drift = CMTimeSubtract(totalNarrationDuration, offset)
        let driftSeconds = CMTimeGetSeconds(drift)
        if abs(driftSeconds) > 0.05, let lastIndex = output.indices.last {
            let seg = output[lastIndex]
            let newDuration = CMTimeAdd(seg.timeRange.duration, drift)
            if newDuration > .zero {
                output[lastIndex] = TimelineSegment(
                    mediaItem: seg.mediaItem,
                    timeRange: CMTimeRange(start: seg.timeRange.start, duration: newDuration)
                )
            }
        }

        return output
    }

    private func timelineSegmentsForEditStoryBlock(mediaItems: [MediaItem], blockDuration: CMTime) -> [TimelineSegment] {
        guard blockDuration > .zero, !mediaItems.isEmpty else { return [] }

        let allPhotos = mediaItems.allSatisfy { item in
            if case .photo = item.kind { return true }
            return false
        }
        if allPhotos {
            return editStoryEvenSplitPhotoTimeline(mediaItems: mediaItems, blockDuration: blockDuration)
        }
        return editStoryMixedOrVideoCycleTimeline(mediaItems: mediaItems, blockDuration: blockDuration)
    }

    private func editStoryEvenSplitPhotoTimeline(mediaItems: [MediaItem], blockDuration: CMTime) -> [TimelineSegment] {
        let n = mediaItems.count
        guard n > 0 else { return [] }
        var segments: [TimelineSegment] = []
        var cursor = CMTime.zero
        for (index, item) in mediaItems.enumerated() {
            let remaining = CMTimeSubtract(blockDuration, cursor)
            guard remaining > .zero else { break }
            let isLast = index == n - 1
            let slot = isLast
                ? remaining
                : CMTimeMultiplyByFloat64(blockDuration, multiplier: 1.0 / Double(n))
            let slice = CMTimeMinimum(slot, remaining)
            guard slice > .zero else { break }
            segments.append(TimelineSegment(mediaItem: item, timeRange: CMTimeRange(start: cursor, duration: slice)))
            cursor = CMTimeAdd(cursor, slice)
        }
        return segments
    }

    /// Photos and videos: up to 10s per photo visit, natural clip length per video visit, cycling the list until the block ends.
    private func editStoryMixedOrVideoCycleTimeline(mediaItems: [MediaItem], blockDuration: CMTime) -> [TimelineSegment] {
        guard blockDuration > .zero, !mediaItems.isEmpty else { return [] }
        let tenSeconds = CMTime(seconds: 10, preferredTimescale: 600)
        let epsilon = CMTime(value: 1, timescale: 10_000)
        var segments: [TimelineSegment] = []
        var cursor = CMTime.zero
        var loopSafety = 0
        var mediaRound = 0

        while cursor < blockDuration - epsilon, loopSafety < 10_000 {
            loopSafety += 1
            let item = mediaItems[mediaRound % mediaItems.count]
            mediaRound += 1
            let remaining = CMTimeSubtract(blockDuration, cursor)
            guard remaining > epsilon else { break }

            let slot: CMTime
            switch item.kind {
            case .photo:
                slot = CMTimeMinimum(tenSeconds, remaining)
            case let .video(_, duration):
                slot = CMTimeMinimum(duration, remaining)
            }

            guard slot > epsilon else { continue }

            segments.append(TimelineSegment(mediaItem: item, timeRange: CMTimeRange(start: cursor, duration: slot)))
            cursor = CMTimeAdd(cursor, slot)
        }

        if cursor < blockDuration - epsilon, let last = segments.indices.last {
            let gap = CMTimeSubtract(blockDuration, cursor)
            let lastSeg = segments[last]
            segments[last] = TimelineSegment(
                mediaItem: lastSeg.mediaItem,
                timeRange: CMTimeRange(
                    start: lastSeg.timeRange.start,
                    duration: CMTimeAdd(lastSeg.timeRange.duration, gap)
                )
            )
        }

        return segments
    }

    private func makeTimelineSegments(
        for mediaItems: [MediaItem],
        totalDuration: CMTime,
        timingMode: TimingMode,
        includeCaptions: Bool = true
    ) async throws -> [TimelineSegment] {
        if timingMode == .realLife {
            return realLifeTimelineSegments(for: mediaItems, totalDuration: totalDuration)
        }

        let hasVideos = mediaItems.contains { if case .video = $0.kind { return true }; return false }
        let hasPhotos = mediaItems.contains { if case .photo = $0.kind { return true }; return false }

        if timingMode == .story && (!includeCaptions || (hasVideos && hasPhotos)) {
            return try storyCaptionOffTimelineSegments(
                for: mediaItems,
                totalDuration: totalDuration
            )
        }

        if timingMode == .story && includeCaptions && hasPhotos && !hasVideos {
            return storyCaptionOnPhotoOnlyTimelineSegments(
                for: mediaItems,
                totalDuration: totalDuration
            )
        }

        let photoItems = mediaItems.filter { if case .photo = $0.kind { return true }; return false }
        let videoItems = mediaItems.filter { if case .video = $0.kind { return true }; return false }
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

    private func storyCaptionOnPhotoOnlyTimelineSegments(
        for mediaItems: [MediaItem],
        totalDuration: CMTime
    ) -> [TimelineSegment] {
        guard !mediaItems.isEmpty, totalDuration > .zero else { return [] }

        let photoItems = mediaItems.filter { if case .photo = $0.kind { return true }; return false }
        guard !photoItems.isEmpty else { return [] }

        let rawSecondsPerPhoto = CMTimeGetSeconds(totalDuration) / Double(photoItems.count)
        let perPhotoDuration = CMTime(seconds: max(rawSecondsPerPhoto, 5.0), preferredTimescale: 600)

        var segments: [TimelineSegment] = []
        var cursor = CMTime.zero

        for item in photoItems {
            guard cursor < totalDuration else { break }
            let remaining = totalDuration - cursor
            let duration = min(perPhotoDuration, remaining)
            guard duration > .zero else { break }

            segments.append(
                TimelineSegment(
                    mediaItem: item,
                    timeRange: CMTimeRange(start: cursor, duration: duration)
                )
            )
            cursor = cursor + duration
        }

        return segments
    }

    private func storyCaptionOffTimelineSegments(
        for mediaItems: [MediaItem],
        totalDuration: CMTime
    ) throws -> [TimelineSegment] {
        guard !mediaItems.isEmpty, totalDuration > .zero else { return [] }

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
            let remainingForPhotos = CMTimeMaximum(.zero, totalDuration - totalVideoDuration)
            guard remainingForPhotos > .zero else { return .zero }
            let rawDuration = CMTimeGetSeconds(remainingForPhotos) / Double(photoItems.count)
            if rawDuration > 20 {
                return CMTime(seconds: 21, preferredTimescale: 600)
            }
            return CMTime(seconds: max(rawDuration, 5), preferredTimescale: 600)
        }()

        if hasPhotos, CMTimeGetSeconds(perPhotoDuration) > 20 {
            throw ExportError.storyNeedsMoreMedia
        }

        var segments: [TimelineSegment] = []
        var cursor = CMTime.zero
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

    private func realLifeTimelineSegments(for mediaItems: [MediaItem], totalDuration: CMTime) -> [TimelineSegment] {
        guard !mediaItems.isEmpty, totalDuration > .zero else { return [] }

        let hasVideos = mediaItems.contains {
            if case .video = $0.kind { return true }
            return false
        }
        let photoItems = mediaItems.filter {
            if case .photo = $0.kind { return true }
            return false
        }
        let photoCount = photoItems.count
        let hasPhotos = photoCount > 0
        let baseVisualDuration = realLifeVisualDuration(for: mediaItems)
        let shouldLoop = totalDuration > baseVisualDuration
        let allPhotos = !hasVideos && hasPhotos
        let perPhotoDuration: CMTime = {
            guard hasPhotos else { return .zero }
            if allPhotos {
                return CMTime(seconds: 8.0, preferredTimescale: 600)
            }
            return CMTime(seconds: 1.6, preferredTimescale: 600)
        }()

        var segments: [TimelineSegment] = []
        var cursor = CMTime.zero
        var loopIndex = 0

        while cursor < totalDuration {
            let item = mediaItems[loopIndex % mediaItems.count]
            let intendedDuration: CMTime
            switch item.kind {
            case .photo:
                intendedDuration = perPhotoDuration
            case let .video(_, videoDuration):
                intendedDuration = videoDuration
            }

            guard intendedDuration > .zero else {
                loopIndex += 1
                if !shouldLoop && loopIndex >= mediaItems.count {
                    break
                }
                continue
            }

            let remaining = totalDuration - cursor
            let duration = min(intendedDuration, remaining)
            guard duration > .zero else { break }

            segments.append(
                TimelineSegment(
                    mediaItem: item,
                    timeRange: CMTimeRange(start: cursor, duration: duration)
                )
            )
            cursor = cursor + duration
            loopIndex += 1

            if !shouldLoop && loopIndex >= mediaItems.count {
                break
            }
        }

        return segments
    }

    /// Active segment at `t`: last segment whose range start is ≤ `t` (timeline is sorted by start).
    /// Avoids edge cases where `containsTime` and discrete frame times sit on opposite sides of a cut.
    private func timelineSegment(at compositionTime: CMTime, segments: [TimelineSegment]) -> TimelineSegment? {
        guard !segments.isEmpty else { return nil }
        var chosen = segments[0]
        for seg in segments.dropFirst() {
            if CMTimeCompare(seg.timeRange.start, compositionTime) <= 0 {
                chosen = seg
            } else {
                break
            }
        }
        return chosen
    }

    private func mediaFrameForTime(
        _ currentTime: CMTime,
        timelineSegments: [TimelineSegment],
        videoFrameCache: VideoFrameCache
    ) async throws -> UIImage {
        guard let segment = timelineSegment(at: currentTime, segments: timelineSegments) else {
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

    private func captionSegments(from externalCues: [ExternalCue], voiceIdentifier: String) -> [CaptionSegment] {
        let voiceTag = SpeechVoiceLibrary.voiceLanguageTag(forVoiceIdentifier: voiceIdentifier)
        let sentenceAligned = SpeechVoiceLibrary.usesSentenceAlignedNarration(voiceLanguageTag: voiceTag)
        return externalCues
            .sorted { $0.start < $1.start }
            .map { cue in
                let text: String
                if sentenceAligned {
                    text = sentenceAlignedCaptionDisplayText(
                        for: cue.text,
                        voiceIdentifier: voiceIdentifier,
                        layout: .phraseRows
                    )
                } else {
                    text = formattedCaptionText(cue.text)
                }
                return CaptionSegment(
                    text: text,
                    timeRange: CMTimeRange(
                        start: CMTime(seconds: cue.start, preferredTimescale: 600),
                        end: CMTime(seconds: cue.end, preferredTimescale: 600)
                    )
                )
            }
    }

    private enum SentenceAlignedCaptionLayout {
        /// Matches prepared preview: **`splitForCaptions`** clause/phrase rows (can stack many short lines).
        case phraseRows
        /// Edit Story **on** (re-synth): one **`displayCaptionLine`** pass on the whole utterance — at most two balanced lines when space‑delimited words allow; avoids stacked micro‑rows from comma splits.
        case compactLines
    }

    /// Sentence-aligned display string. **`phraseRows`** matches **`NarrationPreviewBuilder`**; **`compactLines`** is for timed export when utterances are long blocks.
    private func sentenceAlignedCaptionDisplayText(
        for rawText: String,
        voiceIdentifier: String,
        layout: SentenceAlignedCaptionLayout
    ) -> String {
        let voiceTag = SpeechVoiceLibrary.voiceLanguageTag(forVoiceIdentifier: voiceIdentifier)
        let norm = SpeechVoiceLibrary.normalizedCaptionText(rawText)
        guard !norm.isEmpty else { return "" }

        switch layout {
        case .compactLines:
            return CaptionTextChunker.strippedCaptionForDisplay(CaptionTextChunker.displayCaptionLine(for: norm))
        case .phraseRows:
            let lines = CaptionTextChunker.splitForCaptions(normalizedText: norm, voiceLanguageTag: voiceTag)
            if lines.count > 1 {
                return CaptionTextChunker.strippedCaptionForDisplay(
                    lines.map { CaptionTextChunker.displayCaptionLine(for: $0) }.joined(separator: "\n")
                )
            }
            return CaptionTextChunker.strippedCaptionForDisplay(CaptionTextChunker.displayCaptionLine(for: norm))
        }
    }

    private func timedCaptionSegments(
        from texts: [String],
        utteranceDurations: [CMTime],
        totalDuration: CMTime,
        voiceIdentifier: String
    ) -> [CaptionSegment] {
        guard !texts.isEmpty else { return [] }

        let voiceTag = SpeechVoiceLibrary.voiceLanguageTag(forVoiceIdentifier: voiceIdentifier)
        if SpeechVoiceLibrary.usesSentenceAlignedNarration(voiceLanguageTag: voiceTag) {
            return sentenceAlignedTimedCaptionSegments(
                from: texts,
                utteranceDurations: utteranceDurations,
                totalDuration: totalDuration,
                voiceIdentifier: voiceIdentifier
            )
        }

        let slices = makeCaptionSlices(from: texts, voiceIdentifier: voiceIdentifier)
        // If every utterance stripped to nothing in splitCaptionText, slices are empty but TTS still ran;
        // do not return no captions (same recovery as the post-loop `segments.isEmpty` branch below).
        if slices.isEmpty {
            return [
                CaptionSegment(
                    text: formattedCaptionText(texts.joined(separator: " ")),
                    timeRange: CMTimeRange(start: .zero, duration: totalDuration)
                )
            ]
        }

        let sourceWeights = sourceSegmentWeights(from: texts)
        let totalSourceWeight = max(sourceWeights.reduce(0.0, +), 0.1)
        let totalSeconds = CMTimeGetSeconds(totalDuration)
        var cursor = CMTime.zero
        var segments: [CaptionSegment] = []

        for sourceIndex in texts.indices {
            let group = slices.filter { $0.sourceSegmentIndex == sourceIndex }
            guard !group.isEmpty else { continue }

            let sourceBudget = sourceIndex < utteranceDurations.count
                ? CMTimeGetSeconds(utteranceDurations[sourceIndex])
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

    /// One timed caption per utterance (Chinese / Japanese / Lao). Uses **`compactLines`** layout so long Edit Story
    /// utterances are not split into many short phrase rows (prepared preview uses **`phraseRows`**).
    private func sentenceAlignedTimedCaptionSegments(
        from texts: [String],
        utteranceDurations: [CMTime],
        totalDuration: CMTime,
        voiceIdentifier: String
    ) -> [CaptionSegment] {
        var segments: [CaptionSegment] = []
        var cursor = CMTime.zero

        for (index, rawText) in texts.enumerated() {
            let spoken = index < utteranceDurations.count ? utteranceDurations[index] : CMTime.zero
            let norm = SpeechVoiceLibrary.normalizedCaptionText(rawText)

            let remaining = totalDuration - cursor
            if remaining <= .zero { break }

            if norm.isEmpty {
                let step = CMTimeMinimum(spoken, remaining)
                cursor = cursor + step
                continue
            }

            // Match **`NarrationPreviewBuilder.buildSentenceAlignedCues`**: use measured utterance length only.
            // A minimum display floor here made each window longer than speech and cumulative caption lag vs audio.
            var pieceDur = spoken
            if pieceDur > remaining {
                pieceDur = remaining
            }

            let end = cursor + pieceDur
            let timeRange = CMTimeRange(start: cursor, end: end)
            let displayText = sentenceAlignedCaptionDisplayText(
                for: rawText,
                voiceIdentifier: voiceIdentifier,
                layout: .compactLines
            )
            segments.append(CaptionSegment(text: displayText, timeRange: timeRange))
            cursor = end
        }

        if segments.isEmpty {
            let joined = texts.joined(separator: " ")
            return [
                CaptionSegment(
                    text: sentenceAlignedCaptionDisplayText(
                        for: joined,
                        voiceIdentifier: voiceIdentifier,
                        layout: .compactLines
                    ),
                    timeRange: CMTimeRange(start: .zero, duration: totalDuration)
                )
            ]
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

    private func splitCaptionText(_ text: String, voiceIdentifier: String) -> [String] {
        let normalized = SpeechVoiceLibrary.normalizedCaptionText(text)
        guard !normalized.isEmpty else { return [] }
        let tag = SpeechVoiceLibrary.voiceLanguageTag(forVoiceIdentifier: voiceIdentifier)
        return CaptionTextChunker.splitForCaptions(normalizedText: normalized, voiceLanguageTag: tag)
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

    private func makeCaptionSlices(from texts: [String], voiceIdentifier: String) -> [CaptionSlice] {
        texts.enumerated().flatMap { index, text in
            let chunks = splitCaptionText(text, voiceIdentifier: voiceIdentifier)
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
        case storyNeedsMoreMedia
        case invalidStoryBlockPlan

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
            case .storyNeedsMoreMedia:
                return "Add more media."
            case .invalidStoryBlockPlan:
                return "Story block layout is invalid. Assign every script paragraph to a block with at least one medium."
            }
        }
    }

    private func resolvedRenderProfile(
        for quality: RenderQuality,
        aspectRatio: AspectRatio,
        duration: CMTime,
        videoPressure: VideoPressure,
        timingMode: TimingMode,
        mediaItems: [MediaItem],
        includeCaptions: Bool = true,
        videoModeSettings: VideoModeExportSettings? = nil
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
            let isPhotoOnlyRealLife = mediaItems.allSatisfy {
                if case .photo = $0.kind { return true }
                return false
            }
            if isPhotoOnlyRealLife {
                let photoMinimumSize: CGSize = {
                    switch quality {
                    case .preview:
                        return baseSize
                    case .finalStandard:
                        return aspectRatio == .widescreen ? CGSize(width: 1920, height: 1080) : CGSize(width: 1440, height: 1080)
                    case .finalHigh:
                        return aspectRatio == .widescreen ? CGSize(width: 2560, height: 1440) : CGSize(width: 1920, height: 1440)
                    }
                }()
                let maxLongEdge: CGFloat = {
                    switch quality {
                    case .preview:
                        return 1280
                    case .finalStandard:
                        return 1920
                    case .finalHigh:
                        return 2560
                    }
                }()

                return RenderProfile(
                    renderSize: preferredMediaDrivenRenderSize(
                        for: mediaItems,
                        aspectRatio: aspectRatio,
                        minimumSize: photoMinimumSize,
                        maximumLongEdge: maxLongEdge
                    ),
                    frameRate: baseRate,
                    longFormOptimized: false,
                    videoSampleStride: 1
                )
            }
            let effectiveSettings = effectiveSlideshowExportSettings(
                requestedSettings: quality == .preview ? nil : videoModeSettings,
                mediaItems: mediaItems,
                narrationDuration: duration,
                fallbackRenderSize: preferredMediaDrivenRenderSize(
                    for: mediaItems,
                    aspectRatio: aspectRatio,
                    minimumSize: baseSize
                ),
                fallbackFrameRate: {
                    switch quality {
                    case .preview:
                        return 12
                    case .finalStandard:
                        return 24
                    case .finalHigh:
                        return 30
                    }
                }()
            )

            return RenderProfile(
                renderSize: effectiveSettings.renderSize,
                frameRate: effectiveSettings.frameRate,
                longFormOptimized: false,
                videoSampleStride: 1
            )
        }

        if timingMode == .story {
            return RenderProfile(
                renderSize: preferredMediaDrivenRenderSize(
                    for: mediaItems,
                    aspectRatio: aspectRatio,
                    minimumSize: baseSize
                ),
                frameRate: {
                    switch quality {
                    case .preview:
                        return 12
                    case .finalStandard:
                        return 24
                    case .finalHigh:
                        return 30
                    }
                }(),
                longFormOptimized: false,
                videoSampleStride: 1
            )
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
                    renderSize: aspectRatio == .widescreen ? CGSize(width: 640, height: 360) : CGSize(width: 480, height: 360),
                    frameRate: 8,
                    longFormOptimized: true,
                    videoSampleStride: 2
                )
            }
            if seconds > 420 {
                return RenderProfile(
                    renderSize: aspectRatio == .widescreen ? CGSize(width: 1136, height: 640) : CGSize(width: 854, height: 640),
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
                    renderSize: aspectRatio == .widescreen ? CGSize(width: 640, height: 360) : CGSize(width: 480, height: 360),
                    frameRate: 10,
                    longFormOptimized: true,
                    videoSampleStride: 2
                )
            }
            if seconds > 420 {
                return RenderProfile(
                    renderSize: aspectRatio == .widescreen ? CGSize(width: 1280, height: 720) : CGSize(width: 960, height: 720),
                    frameRate: 8,
                    longFormOptimized: true,
                    videoSampleStride: 3
                )
            }
            return RenderProfile(
                renderSize: aspectRatio == .widescreen ? CGSize(width: 1280, height: 720) : CGSize(width: 960, height: 720),
                frameRate: 10,
                longFormOptimized: true,
                videoSampleStride: 2
            )
        }
    }

    private func preferredMediaDrivenRenderSize(
        for mediaItems: [MediaItem],
        aspectRatio: AspectRatio,
        minimumSize: CGSize,
        maximumLongEdge: CGFloat? = nil
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

        let fitted = AVMakeRect(aspectRatio: aspectRatio == .widescreen ? CGSize(width: 16, height: 9) : CGSize(width: 4, height: 3),
                                insideRect: CGRect(origin: .zero, size: largestMediaSize)).size

        let resolvedFitted: CGSize = {
            guard let maximumLongEdge else { return fitted }
            let longEdge = max(fitted.width, fitted.height)
            guard longEdge > maximumLongEdge, longEdge > 0 else { return fitted }
            let scale = maximumLongEdge / longEdge
            return CGSize(width: fitted.width * scale, height: fitted.height * scale)
        }()

        let width = max(minimumSize.width, round(resolvedFitted.width / 2) * 2)
        let height = max(minimumSize.height, round(resolvedFitted.height / 2) * 2)
        return CGSize(width: width, height: height)
    }

    private func effectiveSlideshowExportSettings(
        requestedSettings: VideoModeExportSettings?,
        mediaItems: [MediaItem],
        narrationDuration: CMTime,
        fallbackRenderSize: CGSize,
        fallbackFrameRate: Int32
    ) -> EffectiveSlideshowExportSettings {
        guard let requestedSettings else {
            return EffectiveSlideshowExportSettings(
                frameRate: fallbackFrameRate,
                renderSize: fallbackRenderSize,
                presetName: AVAssetExportPresetHighestQuality
            )
        }

        let mediaDuration = realLifeVisualDuration(for: mediaItems)
        let narrationIsLonger = narrationDuration > mediaDuration
        let selectedIsHeavyCombo =
            requestedSettings.resolution == .p4k &&
            requestedSettings.frameRate == .fps60 &&
            requestedSettings.quality == .high

        if narrationIsLonger && selectedIsHeavyCombo {
            return EffectiveSlideshowExportSettings(
                frameRate: VideoModeFrameRate.fps30.value,
                renderSize: VideoModeResolution.p1080.renderSize,
                presetName: VideoModeQuality.high.exportPresetName
            )
        }

        return EffectiveSlideshowExportSettings(
            frameRate: requestedSettings.frameRate.value,
            renderSize: requestedSettings.resolution.renderSize,
            presetName: requestedSettings.quality.exportPresetName
        )
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

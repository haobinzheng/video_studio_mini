import AVFoundation
import CryptoKit
import CoreTransferable
import NaturalLanguage
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let originalExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("picked-video-\(UUID().uuidString).\(originalExtension)")

            let parent = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try AppViewModelCopyUtilities.copyFileResolvingLargeSources(from: received.file, to: destination)
            return Self(url: destination)
        }
    }
}

/// Resolves imported movie files without loading multi‑gigabyte media into RAM (avoids `Data(contentsOf:)` OOM on long 4K clips).
/// Tries `moveItem` first so picker-provided temp files are adopted in O(1) when on the same volume.
private enum AppViewModelCopyUtilities {
    private static let streamChunkSize = 8 * 1024 * 1024

    static func copyFileResolvingLargeSources(from sourceURL: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            return
        } catch {
            // Cross-volume or sandbox quirk: fall back to copy/stream.
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            try copyFileByStreaming(from: sourceURL, to: destinationURL)
        }
    }

    private static func copyFileByStreaming(from sourceURL: URL, to destinationURL: URL) throws {
        guard sourceURL.isFileURL else {
            throw NSError(
                domain: "FluxCutFileCopy",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot stream-copy a non-file URL."]
            )
        }

        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destinationURL)
        defer { try? output.close() }

        while true {
            let chunk = try input.read(upToCount: streamChunkSize) ?? Data()
            if chunk.isEmpty { break }
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()
    }
}

@MainActor
final class AppViewModel: NSObject, ObservableObject {
    private static let savedNarrationDraftKey = "fluxcut.savedNarrationDraft"
    private static let hiddenVoiceIdentifiersKey = "fluxcut.hiddenVoiceIdentifiers"

    private struct StorageCleanupResult: Sendable {
        var removedItemCount: Int = 0
        var removedBytes: Int64 = 0
    }

    struct StorageUsageSnapshot: Sendable {
        var documentsBytes: Int64 = 0
        var cachesBytes: Int64 = 0
        var temporaryBytes: Int64 = 0

        var totalBytes: Int64 {
            documentsBytes + cachesBytes + temporaryBytes
        }
    }

    private final class ExportSessionBox: @unchecked Sendable {
        let session: AVAssetExportSession

        init(_ session: AVAssetExportSession) {
            self.session = session
        }
    }

    private static let videoPlaceholderImage: UIImage = {
        let size = CGSize(width: 640, height: 360)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1).setFill()
            context.fill(bounds)

            let accentRect = CGRect(x: 0, y: size.height * 0.66, width: size.width, height: size.height * 0.34)
            UIColor(red: 0.17, green: 0.20, blue: 0.28, alpha: 1).setFill()
            context.fill(accentRect)

            let configuration = UIImage.SymbolConfiguration(pointSize: 120, weight: .medium)
            let image = UIImage(systemName: "video.fill", withConfiguration: configuration)?
                .withTintColor(.white.withAlphaComponent(0.9), renderingMode: .alwaysOriginal)
            let iconSize = CGSize(width: 140, height: 140)
            let iconRect = CGRect(
                x: (size.width - iconSize.width) / 2,
                y: (size.height - iconSize.height) / 2 - 10,
                width: iconSize.width,
                height: iconSize.height
            )
            image?.draw(in: iconRect)
        }
    }()

    struct MediaItem: Identifiable, Equatable {
        enum Kind: Equatable {
            case photo
            case video(url: URL?, duration: Double, libraryIdentifier: String?)
        }

        let id: UUID
        let previewImage: UIImage
        let kind: Kind
        let sourceAssetID: UUID

        init(
            id: UUID = UUID(),
            previewImage: UIImage,
            kind: Kind,
            sourceAssetID: UUID = UUID()
        ) {
            self.id = id
            self.previewImage = previewImage
            self.kind = kind
            self.sourceAssetID = sourceAssetID
        }

        var isVideo: Bool {
            if case .video = kind { return true }
            return false
        }
    }

    struct VoiceOption: Identifiable {
        let id: String
        let name: String
        let language: String
        let languageGroup: String
        let languageLabel: String
        let regionLabel: String
        let qualityLabel: String
        let sortRank: Int
        let isFallback: Bool

        var displayName: String {
            let fallbackSuffix = isFallback ? " • Fallback" : ""
            return "\(name) • \(qualityLabel) • \(languageLabel)\(fallbackSuffix)"
        }
    }

    struct VoiceLanguageOption: Identifiable, Equatable {
        let id: String
        let label: String
        let voiceCount: Int
    }

    struct NarrationSpeedOption: Identifiable, Equatable {
        let multiplier: Double

        var id: Double { multiplier }
        var label: String { String(format: "%.1fx", multiplier) }
    }

    private enum ScriptLanguageFamily: String {
        case english = "en"
        case chinese = "zh"
        case japanese = "ja"
        case korean = "ko"
        case arabic = "ar"
        case unknown = "unknown"

        var label: String {
            switch self {
            case .english: return "English"
            case .chinese: return "Chinese"
            case .japanese: return "Japanese"
            case .korean: return "Korean"
            case .arabic: return "Arabic"
            case .unknown: return "Unknown"
            }
        }
    }

    struct DemoTrackOption: Identifiable {
        let id: String
        let name: String
        let description: String
        let fileName: String
        let fileExtension: String
    }

    struct MusicLibraryItem: Identifiable, Equatable {
        enum Source: String {
            case builtIn = "Built-In"
            case imported = "Imported"
            case extracted = "Extracted"
        }

        let id: String
        let name: String
        let duration: TimeInterval
        let description: String?
        let url: URL
        let source: Source
    }

    struct SoundtrackItem: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let name: String
        let duration: TimeInterval
    }

    @Published var mediaItems: [MediaItem] = []
    @Published var narrationText = """
    Welcome to FluxCut. This introduction is both a sample script and a quick user guide you can read or play out loud.

    Start in Script. Type or paste your narration, then choose an iPhone voice for playback and export. The voice list comes from Apple voices available to apps on your iPhone. You can select a voice, hide voices you do not want to see, and tap Reload iPhone Voices later if you install more enhanced or premium voices in iPhone settings.

    Use Play Script to hear the current script right away. Build Preview is an optional testing tool. It creates a shorter narration preview so you can check timing and subtitle flow before making the final video.

    In Media, import photos and videos, then review the order. In Music, you can import normal audio files or use a video soundtrack. FluxCut can extract audio from a video and let you reuse it as music.

    In Video, choose the aspect ratio, preview the result, and create the final render. You can also adjust the final mix for narration, original video sound, and music.

    Replace this introduction with your own script any time and start building your video.
    """ {
        didSet {
            saveNarrationDraft()
            if oldValue != narrationText {
                markAllVideoRendersDirty(reason: "Script updated. Build a new preview or final render to reflect the latest narration.")
                invalidateNarrationPreviewIfNeeded()
            }
        }
    }
    @Published var selectedPhotoItems: [PhotosPickerItem] = [] {
        didSet {
            guard !suppressSelectedPhotoItemsReload else {
                suppressSelectedPhotoItemsReload = false
                return
            }
            Task {
                await loadSelectedMedia(from: selectedPhotoItems)
            }
        }
    }
    @Published var currentSlideIndex = 0
    @Published var importedMusicName = "No music selected"
    @Published var isImportingMusic = false
    @Published var soundtrackItems: [SoundtrackItem] = []
    @Published var isLoadingMediaSelection = false
    @Published var isSpeaking = false
    @Published var isPreparingNarrationPreview = false
    @Published var isNarrationPreviewPlaying = false
    @Published var narrationPreviewDuration: Double = 0
    @Published var narrationPreviewCurrentTime: Double = 0
    @Published var narrationPreviewCaption = "Build a seekable preview to test subtitle sync."
    @Published var isMusicPlaying = false
    @Published var musicPlaybackDuration: Double = 0
    @Published var musicPlaybackCurrentTime: Double = 0
    @Published var isExportingVideo = false
    @Published var isPreparingVideoPreview = false
    @Published var exportProgress: Double = 0
    @Published var exportedVideoURL: URL?
    @Published var videoPreviewURL: URL?
    @Published var availableVoices: [VoiceOption] = []
    @Published var selectedVoiceLanguage = "" {
        didSet {
            guard oldValue != selectedVoiceLanguage else { return }
            selectBestVoiceForSelectedLanguage()
        }
    }
    @Published var selectedVoiceIdentifier = "" {
        didSet {
            if let matchingVoice = availableVoices.first(where: { $0.id == selectedVoiceIdentifier }),
               selectedVoiceLanguage != matchingVoice.languageGroup {
                selectedVoiceLanguage = matchingVoice.languageGroup
            }
            selectedVoiceName = selectedVoiceDisplayName
            if oldValue != selectedVoiceIdentifier {
                stopLiveNarrationPlayback(reason: "Voice updated. Tap Play Script to hear the new selection.")
                markAllVideoRendersDirty(reason: "Voice updated. Build a new preview or final render to hear the change.")
                invalidateNarrationPreviewIfNeeded()
            }
        }
    }
    @Published var selectedNarrationSpeed: Double = 1.0 {
        didSet {
            guard oldValue != selectedNarrationSpeed else { return }
            stopLiveNarrationPlayback(reason: "Speech speed updated. Tap Play Script to hear the new pacing.")
            markAllVideoRendersDirty(reason: "Speech speed updated. Build a new preview or final render to use the new pacing.")
            invalidateNarrationPreviewIfNeeded()
        }
    }
    @Published var selectedVoiceName = "No Apple voice selected yet."
    @Published var clipboardPreview = "Clipboard not checked yet."
    @Published var demoTracks: [DemoTrackOption] = [
        DemoTrackOption(id: "dream_culture", name: "Dream Culture", description: "Calming, relaxed, uplifting ambience", fileName: "dream_culture", fileExtension: "mp3"),
        DemoTrackOption(id: "local_forecast", name: "Local Forecast", description: "Bright, grooving, feel-good energy", fileName: "local_forecast", fileExtension: "mp3")
    ]
    @Published var selectedDemoTrackID = "dream_culture"
    @Published var selectedAspectRatio: VideoExporter.AspectRatio = .widescreen {
        didSet {
            if oldValue != selectedAspectRatio {
                hasPendingPreviewChanges = true
                hasPendingFinalVideoChanges = true
                invalidateRenderedVideo(reason: "Frame updated to \(selectedAspectRatio.rawValue). Build a new preview or final render to see the change.")
            }
        }
    }
    @Published var selectedTimingMode: VideoExporter.TimingMode = .story {
        didSet {
            if oldValue != selectedTimingMode {
                hasPendingPreviewChanges = true
                hasPendingFinalVideoChanges = true
                invalidateRenderedVideo(reason: "\(selectedTimingMode.rawValue) mode is active. Build a new preview or final render to see the change.")
            }
        }
    }
    @Published var selectedFinalExportQuality: VideoExporter.FinalExportQuality = .standard {
        didSet {
            if oldValue != selectedFinalExportQuality {
                hasPendingFinalVideoChanges = true
                exportedVideoURL = nil
                exportProgress = 0
                statusMessage = "Final quality updated to \(selectedFinalExportQuality.rawValue). Build a new final render to see the change."
            }
        }
    }
    @Published var selectedVideoModeFrameRate: VideoExporter.VideoModeFrameRate = .fps30 {
        didSet {
            if oldValue != selectedVideoModeFrameRate {
                hasPendingFinalVideoChanges = true
                exportedVideoURL = nil
                exportProgress = 0
                statusMessage = "\(selectedTimingMode.rawValue) frame rate updated to \(selectedVideoModeFrameRate.displayName). Build a new final render to use it."
            }
        }
    }
    @Published var selectedVideoModeResolution: VideoExporter.VideoModeResolution = .p1080 {
        didSet {
            if oldValue != selectedVideoModeResolution {
                hasPendingFinalVideoChanges = true
                exportedVideoURL = nil
                exportProgress = 0
                statusMessage = "\(selectedTimingMode.rawValue) resolution updated to \(selectedVideoModeResolution.rawValue). Build a new final render to use it."
            }
        }
    }
    @Published var selectedVideoModeQuality: VideoExporter.VideoModeQuality = .high {
        didSet {
            if oldValue != selectedVideoModeQuality {
                hasPendingFinalVideoChanges = true
                exportedVideoURL = nil
                exportProgress = 0
                statusMessage = "\(selectedTimingMode.rawValue) export quality updated to \(selectedVideoModeQuality.rawValue). Build a new final render to use it."
            }
        }
    }
    @Published var includesFinalCaptions = true {
        didSet {
            if oldValue != includesFinalCaptions {
                hasPendingFinalVideoChanges = true
                exportedVideoURL = nil
                exportProgress = 0
                statusMessage = includesFinalCaptions
                    ? "Captions will be included in the final export."
                    : "Final export will be created without captions."
            }
        }
    }
    @Published var musicVolume: Double = 0.6 {
        didSet {
            audioPlayer?.volume = Float(musicVolume)
            if oldValue != musicVolume {
                markAllVideoRendersDirty(reason: "Music level updated. Build a new preview or final render to hear the change.")
            }
        }
    }
    @Published var narrationVolume: Double = 1.0 {
        didSet {
            if oldValue != narrationVolume {
                markAllVideoRendersDirty(reason: "Narration level updated. Build a new preview or final render to hear the change.")
            }
        }
    }
    @Published var videoAudioVolume: Double = 0.0 {
        didSet {
            if oldValue != videoAudioVolume {
                markAllVideoRendersDirty(reason: "Video sound level updated. Build a new preview or final render to hear the change.")
            }
        }
    }
    @Published var statusMessage = "Pick photos, add a script, and import music to build your clip."
    @Published var hasPendingPreviewChanges = true
    @Published var hasPendingFinalVideoChanges = true
    @Published var voiceReloadFeedback = ""
    @Published var isClearingUnusedData = false
    @Published var isClearingCurrentProjectData = false
    @Published var storageCleanupFeedback = ""
    @Published var isRefreshingStorageUsage = false
    @Published var storageUsage = StorageUsageSnapshot()
    @Published var isLoadingMusicLibrary = false
    @Published var musicLibraryItems: [MusicLibraryItem] = []
    @Published var musicLibraryFeedback = ""

    private let videoExporter = VideoExporter()
    private let narrationPreviewBuilder = NarrationPreviewBuilder()
    private var audioPlayer: AVAudioPlayer?
    private var musicPlaybackTimer: Timer?
    private var narrationPreviewPlayer: AVAudioPlayer?
    private var narrationPreviewTimer: Timer?
    private var importedMusicURL: URL?
    private var narrationPreviewAudioURL: URL?
    private var narrationPreviewCues: [NarrationPreviewBuilder.SubtitleCue] = []
    private var narrationTimelineEngine = SubtitleTimelineEngine(cues: [])
    private var previewSourceText = ""
    private var previewSourceVoiceIdentifier = ""
    private var previewSourceSpeechRate: Double = 1.0
    private var narrationPreviewIsFullLength = false
    private var pendingUtteranceCount = 0
    private var didLoadFullVoiceList = false
    private var shouldPersistNarrationDraft = true
    private var hiddenVoiceIdentifiers: Set<String> = []
    private var allAvailableVoices: [VoiceOption] = []
    private var speechSynthesizer = AVSpeechSynthesizer()
    private var didConfigureAudioSession = false
    private var suppressSelectedPhotoItemsReload = false
    private var pickerItemsBySourceAssetID: [UUID: PhotosPickerItem] = [:]

    override init() {
        if let hidden = UserDefaults.standard.array(forKey: Self.hiddenVoiceIdentifiersKey) as? [String] {
            hiddenVoiceIdentifiers = Set(hidden)
        }
        let savedDraft = UserDefaults.standard.string(forKey: Self.savedNarrationDraftKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let savedDraft, !savedDraft.isEmpty {
            narrationText = savedDraft
        }
        super.init()
        speechSynthesizer.delegate = self
        allAvailableVoices = SpeechVoiceLibrary.initialVoiceOptions
        availableVoices = filteredVoices(from: allAvailableVoices)
        if availableVoices.isEmpty {
            availableVoices = allAvailableVoices
        }
        voiceReloadFeedback = availableVoices.isEmpty
            ? "No enhanced or premium voices loaded yet"
            : "\(availableVoices.count) high-quality Apple voices ready"
        if let firstVoice = availableVoices.first {
            selectedVoiceLanguage = firstVoice.languageGroup
            selectedVoiceIdentifier = firstVoice.id
            selectedVoiceName = firstVoice.displayName
        }
    }

    func playNarration() {
        guard !narrationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "Add some narration text before starting text-to-speech."
            return
        }

        guard !hasNarrationLanguageMismatch else {
            statusMessage = narrationLanguageWarning ?? "Selected voice language does not match the script."
            return
        }

        if availableVoices.isEmpty {
            reloadAvailableVoices(restoringHiddenVoices: false)
        }
        selectLanguageCompatibleVoiceIfNeeded(for: narrationText)
        reconcileSelectedVoice()
        let activeVoiceIdentifier = resolvedPlayableVoiceIdentifier()
        guard !activeVoiceIdentifier.isEmpty else {
            statusMessage = "Reload iPhone voices first, then try Play Script again."
            return
        }
        if selectedVoiceIdentifier != activeVoiceIdentifier {
            selectedVoiceIdentifier = activeVoiceIdentifier
            selectedVoiceName = selectedVoiceDisplayName
        }

        configureAudioSessionIfNeeded()

        if !speechSynthesizer.isSpeaking && pendingUtteranceCount > 0 {
            pendingUtteranceCount = 0
            isSpeaking = false
        }

        if speechSynthesizer.isSpeaking || isSpeaking {
            stopLiveNarrationPlayback(reason: "Narration stopped.")
            return
        }

        let utterances = SpeechVoiceLibrary.makeUtterances(
            from: narrationText,
            voiceIdentifier: activeVoiceIdentifier,
            speechRateMultiplier: selectedNarrationSpeed
        )
        guard !utterances.isEmpty else {
            statusMessage = "Add some narration text before starting text-to-speech."
            return
        }

        pendingUtteranceCount = utterances.count
        for utterance in utterances {
            speechSynthesizer.speak(utterance)
        }
        statusMessage = "Starting script playback with \(selectedVoiceDisplayName)."
    }

    func buildNarrationPreview() {
        let text = normalizedNarrationSourceText
        guard !text.isEmpty else {
            statusMessage = "Add some narration text before building the preview."
            return
        }

        guard !hasNarrationLanguageMismatch else {
            statusMessage = narrationLanguageWarning ?? "Selected voice language does not match the script."
            return
        }

        let voiceIdentifier = selectedVoiceIdentifier
        let speechRateMultiplier = selectedNarrationSpeed

        Task {
            do {
                try await prepareNarrationPreview(
                    text: text,
                    voiceIdentifier: voiceIdentifier,
                    speechRateMultiplier: speechRateMultiplier,
                    maximumDuration: 180,
                    startedMessage: "Generating seekable narration preview.",
                    completedMessage: "Seekable narration preview is ready."
                )
            } catch {
                narrationPreviewCaption = "Preview generation failed."
                statusMessage = error.localizedDescription.isEmpty ? "Could not build narration preview." : error.localizedDescription
            }
        }
    }

    func toggleNarrationPreviewPlayback() {
        guard let narrationPreviewPlayer else {
            statusMessage = "Build the narration preview first."
            return
        }

        if narrationPreviewPlayer.isPlaying {
            narrationPreviewPlayer.pause()
            stopNarrationPreviewTimer()
            isNarrationPreviewPlaying = false
            statusMessage = "Narration preview paused."
        } else {
            narrationPreviewPlayer.play()
            startNarrationPreviewTimer()
            isNarrationPreviewPlaying = true
            statusMessage = "Narration preview playing."
        }
    }

    func seekNarrationPreview(to time: Double) {
        guard let narrationPreviewPlayer else { return }
        let clamped = min(max(time, 0), narrationPreviewDuration)
        narrationPreviewPlayer.currentTime = clamped
        narrationPreviewCurrentTime = clamped
        updateNarrationPreviewCaption(for: clamped)
    }

    func stopNarrationPreview() {
        narrationPreviewPlayer?.stop()
        narrationPreviewPlayer?.currentTime = 0
        narrationPreviewCurrentTime = 0
        isNarrationPreviewPlaying = false
        stopNarrationPreviewTimer()
        updateNarrationPreviewCaption(for: 0)
    }

    func pasteNarrationFromClipboard() {
        guard let pastedText = UIPasteboard.general.string,
              !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "Clipboard is empty. Copy some text first, then tap Paste."
            clipboardPreview = "Clipboard is empty."
            return
        }

        narrationText = pastedText
        clipboardPreview = "\(pastedText.prefix(80))\(pastedText.count > 80 ? "..." : "")"
        statusMessage = "Narration text pasted from clipboard."
    }

    func appendNarrationFromClipboard() {
        guard let pastedText = UIPasteboard.general.string,
              !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "Clipboard is empty. Copy some text first, then tap Append."
            clipboardPreview = "Clipboard is empty."
            return
        }

        if narrationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            narrationText = pastedText
        } else {
            narrationText += "\n\n" + pastedText
        }
        clipboardPreview = "\(pastedText.prefix(80))\(pastedText.count > 80 ? "..." : "")"
        statusMessage = "Clipboard text appended to narration."
    }

    func inspectClipboard() {
        if let pastedText = UIPasteboard.general.string,
           !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clipboardPreview = "\(pastedText.prefix(120))\(pastedText.count > 120 ? "..." : "")"
            statusMessage = "Clipboard detected with \(pastedText.count) characters."
        } else {
            clipboardPreview = "Clipboard is empty."
            statusMessage = "No clipboard text detected."
        }
    }

    func copySampleTextToClipboard() {
        let sample = "Paste test from the app. If you can paste this into narration, clipboard sync is working."
        UIPasteboard.general.string = sample
        clipboardPreview = sample
        statusMessage = "Sample text copied to clipboard. Now try Paste or paste into another app."
    }

    func clearNarration() {
        stopLiveNarrationPlayback()
        narrationText = ""
        statusMessage = "Narration text cleared."
    }

    func recoverLastNarrationDraft() {
        let savedDraft = UserDefaults.standard.string(forKey: Self.savedNarrationDraftKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let savedDraft, !savedDraft.isEmpty else {
            statusMessage = "No saved script is available to recover."
            return
        }

        stopLiveNarrationPlayback()
        narrationText = savedDraft
        statusMessage = "Last saved script recovered."
    }

    func cleanupNarrationText() {
        let cleanedText = Self.cleanedNarrationText(from: narrationText)
        guard cleanedText != narrationText else {
            statusMessage = "Script is already clean for narration."
            return
        }

        stopLiveNarrationPlayback()
        narrationText = cleanedText
        statusMessage = "Script cleaned for narration."
    }

    private func stopLiveNarrationPlayback(reason: String? = nil) {
        speechSynthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        pendingUtteranceCount = 0
        resetSpeechSynthesizer()
        if let reason {
            statusMessage = reason
        }
    }

    func stopLiveNarrationSilently() {
        stopLiveNarrationPlayback()
    }

    func loadSampleNarration() {
        stopLiveNarrationPlayback()
        shouldPersistNarrationDraft = false
        narrationText = """
        Welcome to FluxCut. This introduction is both a sample script and a quick user guide you can read or play out loud.

        Start in Script. Type or paste your narration, then choose an iPhone voice for playback and export. The voice list comes from Apple voices available to apps on your iPhone. You can select a voice, hide voices you do not want to see, and tap Reload iPhone Voices later if you install more enhanced or premium voices in iPhone settings.

        Use Play Script to hear the current script right away. Build Preview is an optional testing tool. It creates a shorter narration preview so you can check timing and subtitle flow before making the final video.

        In Media, import photos and videos, then review the order. In Music, you can import normal audio files or use a video soundtrack. FluxCut can extract audio from a video and let you reuse it as music.

        In Video, choose the aspect ratio, preview the result, and create the final render. You can also adjust the final mix for narration, original video sound, and music.

        Replace this introduction with your own script any time and start building your video.
        """
        shouldPersistNarrationDraft = true
        statusMessage = "Introduction loaded."
    }

    func importMusic(from selectedURL: URL) {
        configureAudioSessionIfNeeded()
        Task {
            await importMusicAssets(from: [selectedURL], appendToQueue: false)
        }
    }

    func importMusic(from selectedURLs: [URL]) {
        configureAudioSessionIfNeeded()
        Task {
            await importMusicAssets(from: selectedURLs, appendToQueue: false)
        }
    }

    func addMusic(from selectedURLs: [URL]) {
        configureAudioSessionIfNeeded()
        Task {
            await importMusicAssets(from: selectedURLs, appendToQueue: true)
        }
    }

    func importMusicToLibrary(from selectedURLs: [URL]) {
        configureAudioSessionIfNeeded()
        Task {
            await saveMusicAssetsToLibrary(from: selectedURLs)
        }
    }

    func extractSoundtrackForExport(from item: PhotosPickerItem) async -> URL? {
        configureAudioSessionIfNeeded()
        guard let pickedURL = await importedVideoURL(from: item) else {
            statusMessage = "Could not load that video from Photos."
            return nil
        }

        do {
            let extractedURL = try await extractAudioTrackIfNeeded(from: pickedURL)
            statusMessage = "Soundtrack extracted. Choose a location to save or share it."
            return extractedURL
        } catch {
            statusMessage = error.localizedDescription.isEmpty ? "Could not extract a soundtrack from that video." : error.localizedDescription
            return nil
        }
    }

    func loadSelectedBundledMusic() {
        configureAudioSessionIfNeeded()

        guard let track = demoTracks.first(where: { $0.id == selectedDemoTrackID }) else {
            statusMessage = "Sample track not found."
            return
        }

        let bundledURL = Bundle.main.url(forResource: track.fileName, withExtension: track.fileExtension, subdirectory: "SampleMusic")
            ?? Bundle.main.url(forResource: track.fileName, withExtension: track.fileExtension)

        guard let bundledURL else {
            statusMessage = "Bundled sample music is missing from the app."
            return
        }

        do {
            stopMusic()
            let duration = Self.quickAudioDuration(for: bundledURL)
            soundtrackItems = [
                SoundtrackItem(
                    url: bundledURL,
                    name: track.name,
                    duration: duration
                )
            ]
            importedMusicURL = bundledURL
            importedMusicName = "\(track.name).\(track.fileExtension)"
            try prepareAudioPlayer(with: bundledURL)
            hasPendingPreviewChanges = true
            hasPendingFinalVideoChanges = true
            statusMessage = "\(track.name) is ready to play."
        } catch {
            statusMessage = "Could not load bundled sample music."
        }
    }

    func clearMusicSelection() {
        stopMusicSilently()
        stopMusicPlaybackTimer()
        audioPlayer = nil
        importedMusicURL = nil
        importedMusicName = "No music selected"
        soundtrackItems = []
        musicPlaybackCurrentTime = 0
        musicPlaybackDuration = 0
        isImportingMusic = false
        hasPendingPreviewChanges = true
        hasPendingFinalVideoChanges = true
        statusMessage = "Music cleared. Your video will export without background music."
    }

    func refreshMusicLibrary() {
        guard !isLoadingMusicLibrary else { return }

        isLoadingMusicLibrary = true
        Task {
            let items = await Self.loadMusicLibraryItems(demoTracks: demoTracks)
            musicLibraryItems = items
            isLoadingMusicLibrary = false
        }
    }

    func deleteMusicLibraryItem(_ item: MusicLibraryItem) {
        guard item.source == .imported else { return }

        stopMusicSilently()

        let remainingQueue = soundtrackItems.filter { $0.url.standardizedFileURL != item.url.standardizedFileURL }
        let shouldClearSelection = importedMusicURL?.standardizedFileURL == item.url.standardizedFileURL

        Task {
            if remainingQueue.count != soundtrackItems.count {
                if remainingQueue.isEmpty {
                    clearMusicSelection()
                } else {
                    await rebuildCombinedSoundtrack(from: remainingQueue, startedMessage: "Updating soundtrack after library delete...")
                }
            } else if shouldClearSelection {
                clearMusicSelection()
            }

            do {
                try FileManager.default.removeItem(at: item.url)
                statusMessage = "\(item.name) removed from Music Library."
                musicLibraryFeedback = "\(item.name) removed from Music Library."
            } catch {
                statusMessage = "Could not remove \(item.name) from Music Library."
                musicLibraryFeedback = "Could not remove \(item.name) from Music Library."
            }
            refreshMusicLibrary()
        }
    }

    func selectMusicLibraryItem(_ item: MusicLibraryItem) {
        previewMusicLibraryItem(item)
    }

    func previewMusicLibraryItem(_ item: MusicLibraryItem) {
        configureAudioSessionIfNeeded()

        do {
            stopMusicSilently()
            try prepareAudioPlayer(with: item.url)
            statusMessage = "\(item.name) is ready to preview."
        } catch {
            statusMessage = "Could not load that music item."
        }
    }

    func restoreProjectMusicAfterLibraryPreview() {
        stopMusicSilently()

        guard let importedMusicURL else {
            audioPlayer = nil
            musicPlaybackCurrentTime = 0
            musicPlaybackDuration = 0
            isMusicPlaying = false
            return
        }

        do {
            try prepareAudioPlayer(with: importedMusicURL)
        } catch {
            audioPlayer = nil
            musicPlaybackCurrentTime = 0
            musicPlaybackDuration = 0
            isMusicPlaying = false
        }
    }

    func addMusicLibraryItem(_ item: MusicLibraryItem) {
        let queueItem = SoundtrackItem(url: item.url, name: item.name, duration: item.duration)
        if soundtrackItems.isEmpty {
            Task {
                await rebuildCombinedSoundtrack(from: [queueItem], startedMessage: "Adding soundtrack to project...")
            }
        } else {
            Task {
                await rebuildCombinedSoundtrack(from: soundtrackItems + [queueItem], startedMessage: "Adding soundtrack to project...")
            }
        }
    }

    func addMusicLibraryItems(_ items: [MusicLibraryItem]) {
        let queueItems = items.map { SoundtrackItem(url: $0.url, name: $0.name, duration: $0.duration) }
        guard !queueItems.isEmpty else { return }

        let updatedQueue = soundtrackItems + queueItems
        Task {
            await rebuildCombinedSoundtrack(
                from: updatedQueue,
                startedMessage: queueItems.count == 1
                    ? "Adding soundtrack to project..."
                    : "Adding selected soundtracks to project..."
            )
        }
    }

    private func saveNarrationDraft() {
        guard shouldPersistNarrationDraft else { return }
        UserDefaults.standard.set(narrationText, forKey: Self.savedNarrationDraftKey)
    }

    func toggleMusicPlayback() {
        guard let audioPlayer else {
            statusMessage = "Import a background music file first."
            return
        }

        if audioPlayer.isPlaying {
            audioPlayer.pause()
            stopMusicPlaybackTimer()
            syncMusicPlaybackState()
            isMusicPlaying = false
            statusMessage = "Background music paused."
        } else {
            audioPlayer.play()
            startMusicPlaybackTimer()
            isMusicPlaying = true
            statusMessage = "Background music playing."
        }
    }

    func stopMusic() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        stopMusicPlaybackTimer()
        syncMusicPlaybackState()
        isMusicPlaying = false
        statusMessage = "Background music stopped."
    }

    func stopMusicSilently() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        stopMusicPlaybackTimer()
        syncMusicPlaybackState()
        isMusicPlaying = false
    }

    func seekMusic(to time: Double) {
        guard let audioPlayer else { return }
        let clampedTime = min(max(time, 0), audioPlayer.duration)
        audioPlayer.currentTime = clampedTime
        syncMusicPlaybackState()
    }

    func moveSoundtrackItem(withId sourceID: UUID, before targetID: UUID) {
        guard sourceID != targetID,
              let sourceIndex = soundtrackItems.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = soundtrackItems.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let movedItem = soundtrackItems[sourceIndex]
        soundtrackItems.remove(at: sourceIndex)
        let destinationIndex = soundtrackItems.firstIndex(where: { $0.id == targetID }) ?? targetIndex
        soundtrackItems.insert(movedItem, at: destinationIndex)
        Task {
            await rebuildCombinedSoundtrack(from: soundtrackItems, startedMessage: "Updating soundtrack order...")
        }
    }

    func removeMediaItem(withId itemID: UUID) {
        guard let itemIndex = mediaItems.firstIndex(where: { $0.id == itemID }) else { return }

        let previousMediaItems = mediaItems
        let removedItem = mediaItems.remove(at: itemIndex)
        if !mediaItems.contains(where: { $0.sourceAssetID == removedItem.sourceAssetID }) {
            pickerItemsBySourceAssetID.removeValue(forKey: removedItem.sourceAssetID)
        }
        refreshSelectedPhotoItemsFromMediaItems()
        if mediaItems.isEmpty {
            currentSlideIndex = 0
        } else {
            currentSlideIndex = min(currentSlideIndex, mediaItems.count - 1)
        }

        cleanupStaleMediaVideoCopies(from: previousMediaItems, keeping: mediaItems)

        hasPendingPreviewChanges = true
        hasPendingFinalVideoChanges = true
        statusMessage = mediaItems.isEmpty
            ? "All media removed from the project."
            : "Media item removed from the project."
    }

    func duplicateMediaItem(withId itemID: UUID) {
        guard let itemIndex = mediaItems.firstIndex(where: { $0.id == itemID }) else { return }

        let original = mediaItems[itemIndex]
        let duplicate = MediaItem(
            previewImage: original.previewImage,
            kind: original.kind,
            sourceAssetID: original.sourceAssetID
        )
        let insertionIndex = min(itemIndex + 1, mediaItems.count)
        mediaItems.insert(duplicate, at: insertionIndex)
        currentSlideIndex = insertionIndex
        refreshSelectedPhotoItemsFromMediaItems()
        hasPendingPreviewChanges = true
        hasPendingFinalVideoChanges = true
        statusMessage = "Media duplicated and inserted after the current item."
    }

    func removeSoundtrackItem(withId itemID: UUID) {
        guard let itemIndex = soundtrackItems.firstIndex(where: { $0.id == itemID }) else { return }
        soundtrackItems.remove(at: itemIndex)

        if soundtrackItems.isEmpty {
            clearMusicSelection()
            return
        }

        Task {
            await rebuildCombinedSoundtrack(from: soundtrackItems, startedMessage: "Removing track from soundtrack...")
        }
    }

    func nextSlide() {
        guard !mediaItems.isEmpty else { return }
        currentSlideIndex = (currentSlideIndex + 1) % mediaItems.count
    }

    func previousSlide() {
        guard !mediaItems.isEmpty else { return }
        currentSlideIndex = (currentSlideIndex - 1 + mediaItems.count) % mediaItems.count
    }

    func clearMediaSelection() {
        let previousMediaItems = mediaItems
        selectedPhotoItems = []
        pickerItemsBySourceAssetID = [:]
        mediaItems = []
        currentSlideIndex = 0
        cleanupStaleMediaVideoCopies(from: previousMediaItems, keeping: [])
        hasPendingPreviewChanges = true
        hasPendingFinalVideoChanges = true
        statusMessage = "Media cleared. Import a new set whenever you're ready."
    }

    func clearUnusedDataAndCache() {
        guard !isClearingUnusedData else { return }

        let keepURLs = currentProtectedStorageURLs()
        clearNarrationPreviewState(resetCaption: true)
        isClearingUnusedData = true
        storageCleanupFeedback = "Clearing unused data and cache..."
        statusMessage = "Clearing unused data and cache."

        Task {
            let result = await Task.detached(priority: .utility) {
                Self.performStorageCleanup(keeping: keepURLs)
            }.value

            isClearingUnusedData = false
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            let sizeLabel = formatter.string(fromByteCount: result.removedBytes)
            storageCleanupFeedback = result.removedItemCount == 0
                ? "No unused data was found."
                : "Removed \(result.removedItemCount) cached item(s) • \(sizeLabel)"
            statusMessage = result.removedItemCount == 0
                ? "No unused data was found to remove."
                : "Unused data and cache cleared."
            refreshStorageUsage()
        }
    }

    func clearCurrentProjectData() {
        guard !isClearingCurrentProjectData else { return }

        let currentMediaItems = mediaItems
        let currentMusicURL = importedMusicURL?.standardizedFileURL
        let currentSoundtrackItemURLs = soundtrackItems.map(\.url).map { $0.standardizedFileURL }
        let currentExportURL = exportedVideoURL?.standardizedFileURL
        let currentPreviewURL = videoPreviewURL?.standardizedFileURL

        stopMusicSilently()
        stopMusicPlaybackTimer()
        clearNarrationPreviewState(resetCaption: true)
        mediaItems = []
        selectedPhotoItems = []
        pickerItemsBySourceAssetID = [:]
        currentSlideIndex = 0
        importedMusicURL = nil
        importedMusicName = "No music selected"
        soundtrackItems = []
        musicPlaybackCurrentTime = 0
        musicPlaybackDuration = 0
        audioPlayer = nil
        exportedVideoURL = nil
        videoPreviewURL = nil
        exportProgress = 0
        hasPendingPreviewChanges = true
        hasPendingFinalVideoChanges = true
        isClearingCurrentProjectData = true
        storageCleanupFeedback = "Clearing current project data..."
        statusMessage = "Clearing current project data."

        Task {
            let result = await Task.detached(priority: .utility) {
                Self.performCurrentProjectCleanup(
                    mediaItems: currentMediaItems,
                    soundtrackItemURLs: currentSoundtrackItemURLs,
                    musicURL: currentMusicURL,
                    exportedVideoURL: currentExportURL,
                    previewVideoURL: currentPreviewURL
                )
            }.value

            isClearingCurrentProjectData = false
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            let sizeLabel = formatter.string(fromByteCount: result.removedBytes)
            storageCleanupFeedback = result.removedItemCount == 0
                ? "Current project data was already clear."
                : "Removed \(result.removedItemCount) current project item(s) • \(sizeLabel)"
            statusMessage = result.removedItemCount == 0
                ? "Current project data was already clear."
                : "Current project data cleared."
            refreshStorageUsage()
        }
    }

    func refreshStorageUsage() {
        guard !isRefreshingStorageUsage else { return }

        isRefreshingStorageUsage = true
        Task {
            let snapshot = await Task.detached(priority: .utility) {
                Self.measureStorageUsage()
            }.value

            storageUsage = snapshot
            isRefreshingStorageUsage = false
        }
    }

    func formattedStorageSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func moveMediaItem(withId sourceID: UUID, before targetID: UUID) {
        guard sourceID != targetID,
              let sourceIndex = mediaItems.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = mediaItems.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let movedItem = mediaItems[sourceIndex]
        mediaItems.remove(at: sourceIndex)
        let destinationIndex = mediaItems.firstIndex(where: { $0.id == targetID }) ?? targetIndex
        mediaItems.insert(movedItem, at: destinationIndex)
        refreshSelectedPhotoItemsFromMediaItems()
        currentSlideIndex = mediaItems.firstIndex(where: { $0.id == sourceID }) ?? 0
        hasPendingPreviewChanges = true
        hasPendingFinalVideoChanges = true
        statusMessage = "Media order updated."
    }

    private func invalidateRenderedVideo(reason: String) {
        videoPreviewURL = nil
        exportedVideoURL = nil
        exportProgress = 0
        statusMessage = reason
    }

    func buildVideo() {
        statusMessage = "Starting \(selectedTimingMode.rawValue) final render."
        runVideoRender(renderQuality: selectedFinalExportQuality.renderQuality, successMessage: "Video created successfully. Preview or share it below.")
    }

    func buildVideoPreview() {
        statusMessage = "Starting \(selectedTimingMode.rawValue) preview render."
        runVideoRender(renderQuality: .preview, successMessage: "Preview ready. Review the result below before creating the final video.")
    }

    private func runVideoRender(renderQuality: VideoExporter.RenderQuality, successMessage: String) {
        guard !isLoadingMediaSelection else {
            statusMessage = "Media is still loading. Please wait a moment, then try again."
            return
        }

        guard !hasNarrationLanguageMismatchForRender else {
            statusMessage = narrationLanguageWarning ?? "Selected voice language does not match the script."
            return
        }

        guard hasRenderableMediaForSelectedMode else {
            statusMessage = selectedTimingMode == .video
                ? "Import at least one video before using Video mode."
                : "Pick photos or videos before rendering."
            return
        }

        if renderQuality == .preview {
            isPreparingVideoPreview = true
            videoPreviewURL = nil
        } else {
            isExportingVideo = true
            exportedVideoURL = nil
        }
        exportProgress = 0.02
        statusMessage = renderQuality == .preview
            ? "Preparing a faster preview render."
            : "Preparing narration, captions, and media for export."

        let narrationText = normalizedNarrationSourceText
        let backgroundMusicURL = importedMusicURL
        let backgroundMusicVolume = musicVolume
        let narrationVolume = narrationVolume
        let videoAudioVolume = videoAudioVolume
        let voiceIdentifier = selectedVoiceIdentifier
        let speechRateMultiplier = selectedNarrationSpeed
        let exporter = videoExporter
        let aspectRatio = selectedAspectRatio
        let timingMode = selectedTimingMode
        let includeCaptions = renderQuality == .preview ? false : includesFinalCaptions
        let videoModeSettings = VideoExporter.VideoModeExportSettings(
            frameRate: selectedVideoModeFrameRate,
            resolution: selectedVideoModeResolution,
            quality: selectedVideoModeQuality
        )

        Task {
            do {
                let shouldPrepareNarration = timingMode != .video && !narrationText.isEmpty
                let requiresFullNarrationPreview = renderQuality != .preview && timingMode != .video
                if shouldPrepareNarration, needsPreviewRefresh(
                    for: narrationText,
                    voiceIdentifier: voiceIdentifier,
                    speechRateMultiplier: speechRateMultiplier,
                    requireFullLength: requiresFullNarrationPreview
                ) {
                    exportProgress = 0.08
                    try await prepareNarrationPreview(
                        text: narrationText,
                        voiceIdentifier: voiceIdentifier,
                        speechRateMultiplier: speechRateMultiplier,
                        maximumDuration: requiresFullNarrationPreview ? nil : (renderQuality == .preview ? 180 : nil),
                        startedMessage: renderQuality == .preview
                            ? "Preparing narration and captions for the quick preview."
                            : "Preparing narration and captions for video export.",
                        completedMessage: renderQuality == .preview
                            ? "Preview narration is ready. Building a short sample render now."
                            : "Narration and captions are ready. Rendering your video now.",
                        progressHandler: { progress, message in
                            self.exportProgress = 0.08 + (progress * 0.14)
                            self.statusMessage = message
                        }
                    )
                } else {
                    exportProgress = 0.22
                    statusMessage = renderQuality == .preview
                        ? "Building a short preview render."
                        : "Rendering your video. This can take a moment."
                }

                exportProgress = max(exportProgress, 0.24)
                statusMessage = renderQuality == .preview
                    ? "Preparing video files for preview."
                    : "Preparing video files for export."
                let exportMediaItems = try await resolveExportMediaItems()

                let previewAudioURL = (timingMode == .video || narrationText.isEmpty) ? nil : narrationPreviewAudioURL
                let previewCues = (timingMode == .video || narrationText.isEmpty) ? [] : narrationPreviewCues
                let exportedURL = try await Task.detached(priority: .userInitiated) {
                    try await exporter.exportVideo(
                        mediaItems: exportMediaItems,
                        narrationText: narrationText,
                        backgroundMusicURL: backgroundMusicURL,
                        backgroundMusicVolume: backgroundMusicVolume,
                        narrationVolume: narrationVolume,
                        videoAudioVolume: videoAudioVolume,
                        voiceIdentifier: voiceIdentifier,
                        aspectRatio: aspectRatio,
                        timingMode: timingMode,
                        includeCaptions: includeCaptions,
                        renderQuality: renderQuality,
                        videoModeSettings: (timingMode == .video || timingMode == .realLife) ? videoModeSettings : nil,
                        externalCues: previewCues,
                        externalNarrationAudioURL: previewAudioURL,
                        progressHandler: { progress, message in
                            Task { @MainActor in
                                self.exportProgress = progress
                                self.statusMessage = message
                            }
                        }
                    )
                }.value
                if renderQuality == .preview {
                    videoPreviewURL = exportedURL
                    hasPendingPreviewChanges = false
                } else {
                    exportedVideoURL = exportedURL
                    hasPendingPreviewChanges = false
                    hasPendingFinalVideoChanges = false
                }
                exportProgress = 1.0
                statusMessage = successMessage
            } catch {
                exportProgress = 0
                statusMessage = error.localizedDescription.isEmpty ? "Video export failed." : error.localizedDescription
            }

            if renderQuality == .preview {
                isPreparingVideoPreview = false
            } else {
                isExportingVideo = false
            }
        }
    }

    func loadAvailableVoicesIfNeeded() {
        guard !didLoadFullVoiceList else { return }
        didLoadFullVoiceList = true
        reloadAvailableVoices(restoringHiddenVoices: false)
    }

    func reloadAvailableVoices(restoringHiddenVoices: Bool = true) {
        resetSpeechSynthesizer()
        if restoringHiddenVoices {
            hiddenVoiceIdentifiers.removeAll()
            saveHiddenVoiceIdentifiers()
        }

        let loadedVoices = SpeechVoiceLibrary.voiceOptions
        if !loadedVoices.isEmpty {
            objectWillChange.send()
            allAvailableVoices = loadedVoices
            applyVoiceFiltersAndSelection()
            voiceReloadFeedback = "\(availableVoices.count) high-quality Apple voices loaded"
            statusMessage = "Voice list refreshed."
        } else {
            let restoredFallbackVoices = SpeechVoiceLibrary.voiceOptions
            if !restoredFallbackVoices.isEmpty {
                objectWillChange.send()
                allAvailableVoices = restoredFallbackVoices
                applyVoiceFiltersAndSelection()
                voiceReloadFeedback = "\(availableVoices.count) high-quality Apple voices loaded"
                statusMessage = "Voice list refreshed."
            } else {
                voiceReloadFeedback = "No enhanced or premium Apple voices found"
                statusMessage = "No enhanced or premium Apple voices were available from the speech framework on this device."
            }
        }
    }

    func selectVoiceLanguage(_ languageID: String) {
        selectedVoiceLanguage = languageID
    }

    func hideVoice(withId voiceID: String) {
        guard availableVoices.count > 1 else {
            statusMessage = "Keep at least one voice available in FluxCut."
            return
        }

        stopLiveNarrationPlayback()
        resetSpeechSynthesizer()
        hiddenVoiceIdentifiers.insert(voiceID)
        saveHiddenVoiceIdentifiers()
        applyVoiceFiltersAndSelection()

        if availableVoices.isEmpty {
            hiddenVoiceIdentifiers.remove(voiceID)
            saveHiddenVoiceIdentifiers()
            applyVoiceFiltersAndSelection()
        }
        invalidateNarrationPreviewIfNeeded()
        voiceReloadFeedback = "\(availableVoices.count) high-quality Apple voices shown"
        statusMessage = "Voice removed from this list. Tap Reload iPhone Voices to bring everything back."
    }

    private func loadSelectedMedia(from pickerItems: [PhotosPickerItem]) async {
        isLoadingMediaSelection = true
        defer {
            isLoadingMediaSelection = false
        }

        let previousMediaItems = mediaItems

        guard !pickerItems.isEmpty else {
            pickerItemsBySourceAssetID = [:]
            mediaItems = []
            currentSlideIndex = 0
            cleanupStaleMediaVideoCopies(from: previousMediaItems, keeping: [])
            statusMessage = "Media cleared. Pick new photos or videos to continue."
            return
        }

        statusMessage = "Importing \(pickerItems.count) item(s)…"
        let (loadedMedia, loadedPickerMap) = await loadMediaItemsInParallel(from: pickerItems)

        pickerItemsBySourceAssetID = loadedPickerMap
        mediaItems = loadedMedia
        currentSlideIndex = 0
        cleanupStaleMediaVideoCopies(from: previousMediaItems, keeping: loadedMedia)
        hasPendingPreviewChanges = true
        hasPendingFinalVideoChanges = true
        if loadedMedia.isEmpty {
            statusMessage = "No valid photos or videos were selected."
        } else if hasIncompletePickerVideoImports {
            statusMessage = "Media added. Large videos are still copying into FluxCut…"
        } else {
            statusMessage = "\(loadedMedia.count) media item(s) ready for your project."
        }
    }

    /// Builds media entries concurrently (each task suspends on I/O so imports overlap instead of running strictly one-by-one).
    private func loadMediaItemsInParallel(from pickerItems: [PhotosPickerItem]) async -> ([MediaItem], [UUID: PhotosPickerItem]) {
        let orderedRows = await withTaskGroup(of: (Int, MediaItem?, UUID).self) { group in
            for index in pickerItems.indices {
                group.addTask { @MainActor in
                    let item = pickerItems[index]
                    let sourceAssetID = UUID()
                    let media = await self.makeMediaItem(from: item, sourceAssetID: sourceAssetID)
                    return (index, media, sourceAssetID)
                }
            }

            var rows: [(Int, MediaItem?, UUID)] = []
            for await row in group {
                rows.append(row)
            }
            rows.sort { $0.0 < $1.0 }
            return rows
        }

        var media: [MediaItem] = []
        var map: [UUID: PhotosPickerItem] = [:]
        for (index, optionalMedia, sourceAssetID) in orderedRows {
            guard let mediaItem = optionalMedia else { continue }
            media.append(mediaItem)
            map[sourceAssetID] = pickerItems[index]
        }
        return (media, map)
    }

    func appendSelectedMedia(from pickerItems: [PhotosPickerItem], combinedSelection: [PhotosPickerItem]? = nil) async {
        guard !pickerItems.isEmpty else { return }

        isLoadingMediaSelection = true
        defer {
            isLoadingMediaSelection = false
        }

        let previousMediaItems = mediaItems
        statusMessage = "Importing \(pickerItems.count) added item(s)…"
        let (appendedMedia, newPickerEntries) = await loadMediaItemsInParallel(from: pickerItems)

        guard !appendedMedia.isEmpty else {
            statusMessage = "No valid photos or videos were selected."
            return
        }

        for (id, item) in newPickerEntries {
            pickerItemsBySourceAssetID[id] = item
        }

        mediaItems = previousMediaItems + appendedMedia

        if let combinedSelection {
            suppressSelectedPhotoItemsReload = true
            selectedPhotoItems = combinedSelection
        } else {
            refreshSelectedPhotoItemsFromMediaItems()
        }

        cleanupStaleMediaVideoCopies(from: previousMediaItems, keeping: mediaItems)
        hasPendingPreviewChanges = true
        hasPendingFinalVideoChanges = true
        statusMessage = hasIncompletePickerVideoImports
            ? "Added media. Large videos are still copying into FluxCut…"
            : "\(appendedMedia.count) media item(s) added to the end of your project."
    }

    private func makeMediaItem(from item: PhotosPickerItem, sourceAssetID: UUID) async -> MediaItem? {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
            if let libraryIdentifier = item.itemIdentifier,
               let videoAsset = await fetchVideoAsset(withLocalIdentifier: libraryIdentifier) {
                let media = MediaItem(
                    previewImage: Self.videoPlaceholderImage,
                    kind: .video(url: nil, duration: videoAsset.duration, libraryIdentifier: libraryIdentifier),
                    sourceAssetID: sourceAssetID
                )
                // Defer + no network for thumbs: keeps bulk import from competing with thumbnail generation.
                Task(priority: .utility) {
                    try? await Task.sleep(for: .milliseconds(400))
                    await self.prefetchVideoThumbnailFromLibrary(sourceAssetID: sourceAssetID, asset: videoAsset)
                }
                return media
            }

            // File-backed import can take a long time (multi‑GB). Show the clip immediately; finish copy in the background.
            let placeholder = MediaItem(
                previewImage: Self.videoPlaceholderImage,
                kind: .video(url: nil, duration: 0, libraryIdentifier: nil),
                sourceAssetID: sourceAssetID
            )
            Task { await self.completePickerVideoFileImport(pickerItem: item, sourceAssetID: sourceAssetID) }
            return placeholder
        } else if let data = try? await item.loadTransferable(type: Data.self),
                  let image = downsampledImage(from: data, maxDimension: 1280) {
            return MediaItem(
                previewImage: image.normalizedOrientationImage(),
                kind: .photo,
                sourceAssetID: sourceAssetID
            )
        }

        return nil
    }

    private func fetchVideoAsset(withLocalIdentifier localIdentifier: String) async -> PHAsset? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
                continuation.resume(returning: assets.firstObject)
            }
        }
    }

    private func makePhotoLibraryVideoThumbnail(for asset: PHAsset, allowNetwork: Bool = false) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = allowNetwork

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 320, height: 320),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.normalizedOrientationImage())
            }
        }
    }

    private func resolveExportMediaItems() async throws -> [VideoExporter.MediaItem] {
        var resolvedItems: [VideoExporter.MediaItem] = []
        var updatedMediaItems = mediaItems

        for index in mediaItems.indices {
            let item = mediaItems[index]
            let exportKind: VideoExporter.MediaItem.Kind

            switch item.kind {
            case .photo:
                exportKind = .photo
            case let .video(existingURL, duration, libraryIdentifier):
                let resolvedURL = try await resolveVideoURLForRender(
                    existingURL: existingURL,
                    libraryIdentifier: libraryIdentifier,
                    sourceAssetID: item.sourceAssetID
                )
                if existingURL == nil {
                    updatedMediaItems[index] = MediaItem(
                        id: item.id,
                        previewImage: item.previewImage,
                        kind: .video(url: resolvedURL, duration: duration, libraryIdentifier: libraryIdentifier),
                        sourceAssetID: item.sourceAssetID
                    )
                }
                exportKind = .video(url: resolvedURL, duration: CMTime(seconds: duration, preferredTimescale: 600))
            }

            resolvedItems.append(
                VideoExporter.MediaItem(
                    previewImage: item.previewImage,
                    kind: exportKind
                )
            )
        }

        mediaItems = updatedMediaItems
        return resolvedItems
    }

    private func resolveVideoURLForRender(
        existingURL: URL?,
        libraryIdentifier: String?,
        sourceAssetID: UUID
    ) async throws -> URL {
        if let existingURL {
            return existingURL
        }

        if let libraryIdentifier,
           let assetURL = await photoLibraryVideoURL(forLocalIdentifier: libraryIdentifier) {
            return assetURL
        }

        if let pickerItem = pickerItemsBySourceAssetID[sourceAssetID],
           let importedURL = await importedVideoURL(from: pickerItem) {
            return importedURL
        }

        throw NSError(
            domain: "FluxCutMediaImport",
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "FluxCut could not access one of the selected videos for rendering."]
        )
    }

    private func photoLibraryVideoURL(forLocalIdentifier localIdentifier: String) async -> URL? {
        guard let asset = await fetchVideoAsset(withLocalIdentifier: localIdentifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .automatic
            options.version = .current
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func cleanupStaleMediaVideoCopies(from previousItems: [MediaItem], keeping currentItems: [MediaItem]) {
        let activeURLs = Set(currentItems.compactMap({ self.mediaVideoURLIfManagedCopy(for: $0) }))

        for url in previousItems.compactMap({ self.mediaVideoURLIfManagedCopy(for: $0) }) where !activeURLs.contains(url) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func refreshSelectedPhotoItemsFromMediaItems() {
        let refreshedItems = orderedUniqueSourceAssetIDs().compactMap { pickerItemsBySourceAssetID[$0] }
        suppressSelectedPhotoItemsReload = true
        selectedPhotoItems = refreshedItems
    }

    private func orderedUniqueSourceAssetIDs() -> [UUID] {
        var seen = Set<UUID>()
        var ordered: [UUID] = []

        for item in mediaItems where seen.insert(item.sourceAssetID).inserted {
            ordered.append(item.sourceAssetID)
        }

        return ordered
    }

    func mediaDisplayLabel(for itemID: UUID) -> String {
        var baseNumberBySource: [UUID: Int] = [:]
        var occurrenceBySource: [UUID: Int] = [:]
        var nextBaseNumber = 1

        for item in mediaItems {
            if baseNumberBySource[item.sourceAssetID] == nil {
                baseNumberBySource[item.sourceAssetID] = nextBaseNumber
                nextBaseNumber += 1
            }

            let occurrence = occurrenceBySource[item.sourceAssetID, default: 0]
            let baseNumber = baseNumberBySource[item.sourceAssetID] ?? nextBaseNumber
            let label = occurrence == 0
                ? "#\(baseNumber)"
                : "#\(baseNumber)\(alphabeticDuplicateSuffix(for: occurrence))"

            if item.id == itemID {
                return label
            }

            occurrenceBySource[item.sourceAssetID] = occurrence + 1
        }

        return "#?"
    }

    private func alphabeticDuplicateSuffix(for occurrence: Int) -> String {
        guard occurrence > 0 else { return "" }

        var index = occurrence
        var suffix = ""
        while index > 0 {
            let remainder = (index - 1) % 26
            let scalar = UnicodeScalar(65 + remainder)!
            suffix = String(Character(scalar)) + suffix
            index = (index - 1) / 26
        }
        return suffix
    }

    private func mediaVideoURLIfManagedCopy(for item: MediaItem) -> URL? {
        guard case let .video(url, _, _) = item.kind,
              let url else {
            return nil
        }

        return Self.mediaVideoIfManagedCopyURL(for: url)
    }

    private func currentProtectedStorageURLs() -> Set<URL> {
        var urls = Set(mediaItems.compactMap({ self.mediaVideoURLIfManagedCopy(for: $0) }).map { $0.standardizedFileURL })
        urls.formUnion(soundtrackItems.map(\.url).map { $0.standardizedFileURL })
        urls.formUnion(Self.importedMusicLibraryURLs().map { $0.standardizedFileURL })

        if let exportedVideoURL {
            urls.insert(exportedVideoURL.standardizedFileURL)
        }
        if let videoPreviewURL {
            urls.insert(videoPreviewURL.standardizedFileURL)
        }
        if let importedMusicURL {
            urls.insert(importedMusicURL.standardizedFileURL)
        }

        return urls
    }

    nonisolated private static func performStorageCleanup(keeping protectedURLs: Set<URL>) -> StorageCleanupResult {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        var standardizedProtected = Set(protectedURLs.map { $0.standardizedFileURL })
        standardizedProtected.formUnion(importedMusicLibraryURLs().map { $0.standardizedFileURL })
        var result = StorageCleanupResult()

        let renderedVideosFolder = documents.appendingPathComponent("RenderedVideos", isDirectory: true)
        result = mergeCleanupResults(
            result,
            cleanupDirectoryContents(at: renderedVideosFolder, keeping: standardizedProtected)
        )

        let narrationPreviewFolder = documents.appendingPathComponent("NarrationPreview", isDirectory: true)
        result = mergeCleanupResults(
            result,
            cleanupDirectoryContents(at: narrationPreviewFolder, keeping: [])
        )

        let sharedAudioFolder = documents.appendingPathComponent("SharedAudio", isDirectory: true)
        result = mergeCleanupResults(
            result,
            cleanupDirectoryContents(at: sharedAudioFolder, keeping: standardizedProtected)
        )

        if let documentContents = try? fileManager.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for url in documentContents {
                let standardizedURL = url.standardizedFileURL
                guard !standardizedProtected.contains(standardizedURL) else { continue }
                result = mergeCleanupResults(result, removeItem(at: standardizedURL))
            }
        }

        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        result = mergeCleanupResults(
            result,
            cleanupDirectoryContents(at: caches, keeping: [])
        )

        result = mergeCleanupResults(
            result,
            cleanupDirectoryContents(at: fileManager.temporaryDirectory, keeping: [])
        )

        return result
    }

    nonisolated private static func performCurrentProjectCleanup(
        mediaItems: [MediaItem],
        soundtrackItemURLs: [URL],
        musicURL: URL?,
        exportedVideoURL: URL?,
        previewVideoURL: URL?
    ) -> StorageCleanupResult {
        var result = StorageCleanupResult()
        let protectedLibraryURLs = Set(importedMusicLibraryURLs().map { $0.standardizedFileURL })

        for url in mediaItems.compactMap({ Self.mediaVideoIfManagedCopyURL(for: $0) as URL? }) {
            result = mergeCleanupResults(result, removeItem(at: url.standardizedFileURL))
        }
        for url in soundtrackItemURLs {
            let standardizedURL = url.standardizedFileURL
            guard !protectedLibraryURLs.contains(standardizedURL) else { continue }
            result = mergeCleanupResults(result, removeItem(at: standardizedURL))
        }
        if let musicURL {
            let standardizedURL = musicURL.standardizedFileURL
            if !protectedLibraryURLs.contains(standardizedURL) {
                result = mergeCleanupResults(result, removeItem(at: standardizedURL))
            }
        }
        if let exportedVideoURL {
            result = mergeCleanupResults(result, removeItem(at: exportedVideoURL.standardizedFileURL))
        }
        if let previewVideoURL {
            result = mergeCleanupResults(result, removeItem(at: previewVideoURL.standardizedFileURL))
        }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        result = mergeCleanupResults(result, cleanupDirectoryContents(at: documents, keeping: protectedLibraryURLs))
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        result = mergeCleanupResults(result, cleanupDirectoryContents(at: caches, keeping: []))
        result = mergeCleanupResults(result, cleanupDirectoryContents(at: FileManager.default.temporaryDirectory, keeping: []))

        return result
    }

    nonisolated private static func cleanupDirectoryContents(at directoryURL: URL, keeping protectedURLs: Set<URL>) -> StorageCleanupResult {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return StorageCleanupResult()
        }

        var result = StorageCleanupResult()
        for url in contents {
            let standardizedURL = url.standardizedFileURL
            guard !protectedURLs.contains(standardizedURL) else { continue }
            result = mergeCleanupResults(result, removeItem(at: standardizedURL))
        }
        return result
    }

    nonisolated private static func removeItem(at url: URL) -> StorageCleanupResult {
        let size = itemSize(at: url)
        do {
            try FileManager.default.removeItem(at: url)
            return StorageCleanupResult(removedItemCount: 1, removedBytes: size)
        } catch {
            return StorageCleanupResult()
        }
    }

    nonisolated private static func itemSize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true {
            let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            var total: Int64 = 0
            while let child = enumerator?.nextObject() as? URL {
                let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values?.isRegularFile == true {
                    total += Int64(values?.fileSize ?? 0)
                }
            }
            return total
        }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    nonisolated private static func measureStorageUsage() -> StorageUsageSnapshot {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let temporary = fileManager.temporaryDirectory

        return StorageUsageSnapshot(
            documentsBytes: itemSize(at: documents),
            cachesBytes: itemSize(at: caches),
            temporaryBytes: itemSize(at: temporary)
        )
    }

    nonisolated private static func mergeCleanupResults(_ lhs: StorageCleanupResult, _ rhs: StorageCleanupResult) -> StorageCleanupResult {
        StorageCleanupResult(
            removedItemCount: lhs.removedItemCount + rhs.removedItemCount,
            removedBytes: lhs.removedBytes + rhs.removedBytes
        )
    }

    nonisolated private static func loadMusicLibraryItems(demoTracks: [DemoTrackOption]) async -> [MusicLibraryItem] {
        var items: [MusicLibraryItem] = []

        for track in demoTracks {
            let bundledURL = Bundle.main.url(forResource: track.fileName, withExtension: track.fileExtension, subdirectory: "SampleMusic")
                ?? Bundle.main.url(forResource: track.fileName, withExtension: track.fileExtension)

            guard let bundledURL else { continue }
            let duration = await audioDuration(for: bundledURL)
            items.append(
                MusicLibraryItem(
                    id: "builtin-\(track.id)",
                    name: track.name,
                    duration: duration,
                    description: track.description,
                    url: bundledURL,
                    source: .builtIn
                )
            )
        }

        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

        if let documentContents = try? fileManager.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in documentContents {
                guard let importedURL = importedAudioDocumentURL(url) else { continue }
                let duration = await audioDuration(for: importedURL)
                items.append(
                    MusicLibraryItem(
                        id: "imported-\(importedURL.lastPathComponent)",
                        name: displayMusicName(for: importedURL),
                        duration: duration,
                        description: "Saved import in FluxCut",
                        url: importedURL,
                        source: .imported
                    )
                )
            }
        }

        var dedupedItemsByKey: [String: MusicLibraryItem] = [:]
        for item in items {
            let key = "\(item.source.rawValue.lowercased())|\(item.name.lowercased())|\(Int(item.duration.rounded()))"
            if let existing = dedupedItemsByKey[key] {
                if item.name.localizedCaseInsensitiveCompare(existing.name) == .orderedAscending {
                    dedupedItemsByKey[key] = item
                }
            } else {
                dedupedItemsByKey[key] = item
            }
        }

        return dedupedItemsByKey.values.sorted { lhs, rhs in
            let lhsRank = sourceSortRank(lhs.source)
            let rhsRank = sourceSortRank(rhs.source)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    nonisolated private static func mediaVideoIfManagedCopyURL(for url: URL) -> URL? {
        guard url.lastPathComponent.hasPrefix("picked-video-") else {
            return nil
        }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let temporary = FileManager.default.temporaryDirectory
        let parent = url.deletingLastPathComponent()
        let grandparent = parent.deletingLastPathComponent()
        guard parent.standardizedFileURL == documents.standardizedFileURL
                || grandparent.standardizedFileURL == temporary.standardizedFileURL else { return nil }

        return url
    }

    nonisolated private static func importedAudioDocumentURL(_ url: URL) -> URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        guard url.deletingLastPathComponent().standardizedFileURL == documents.standardizedFileURL else { return nil }
        guard !url.hasDirectoryPath else { return nil }
        guard !url.lastPathComponent.hasPrefix("picked-video-") else { return nil }
        guard !url.lastPathComponent.hasPrefix("capcut-mini-") else { return nil }
        guard !url.lastPathComponent.hasPrefix(".") else { return nil }

        let ext = url.pathExtension.lowercased()
        let knownAudioExtensions = Set(["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "m4b"])
        if knownAudioExtensions.contains(ext) {
            return url
        }

        guard importedMediaType(for: url) == .audio else { return nil }
        return url
    }

    nonisolated private static func importedMusicLibraryURLs() -> [URL] {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        guard let documentContents = try? fileManager.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return documentContents.compactMap { importedAudioDocumentURL($0) }
    }

    nonisolated private static func mediaVideoIfManagedCopyURL(for item: MediaItem) -> URL? {
        guard case let .video(url, _, _) = item.kind,
              let url else {
            return nil
        }
        return Self.mediaVideoIfManagedCopyURL(for: url)
    }

    private func importedVideoURL(from item: PhotosPickerItem) async -> URL? {
        // Prefer a direct file URL when the picker provides one — avoids `PickedMovie`’s full export when possible.
        if let pickedURL = try? await item.loadTransferable(type: URL.self) {
            let accessed = pickedURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    pickedURL.stopAccessingSecurityScopedResource()
                }
            }
            if let copiedURL = try? copyImportedVideoFileToManagedTemporaryLocation(pickedURL) {
                cleanupTemporaryImportSourceIfNeeded(pickedURL)
                return copiedURL
            }
        }

        if let pickedMovie = try? await item.loadTransferable(type: PickedMovie.self) {
            return pickedMovie.url
        }

        // Do not use `Data` for video: long 4K clips can be many GB and loading them spikes RAM until iOS jetsams the app.
        return nil
    }

    /// Fills in file URL + duration for a placeholder row created when PhotoKit lookup misses but the picker still has a movie.
    private func completePickerVideoFileImport(pickerItem: PhotosPickerItem, sourceAssetID: UUID) async {
        guard let url = await importedVideoURL(from: pickerItem) else {
            removePendingPickerVideoPlaceholder(sourceAssetID: sourceAssetID)
            statusMessage = "Could not import a selected video."
            return
        }

        let duration = await videoDuration(for: url)
        guard let index = mediaItems.firstIndex(where: { $0.sourceAssetID == sourceAssetID }) else { return }
        let row = mediaItems[index]
        guard case let .video(existingURL, _, libraryIdentifier) = row.kind,
              existingURL == nil,
              libraryIdentifier == nil else {
            return
        }

        mediaItems[index] = MediaItem(
            id: row.id,
            previewImage: row.previewImage,
            kind: .video(url: url, duration: duration, libraryIdentifier: nil),
            sourceAssetID: sourceAssetID
        )

        hasPendingPreviewChanges = true
        hasPendingFinalVideoChanges = true

        let count = mediaItems.count
        statusMessage = count == 1 ? "1 media item ready for your project." : "\(count) media item(s) ready for your project."
    }

    private func removePendingPickerVideoPlaceholder(sourceAssetID: UUID) {
        guard let index = mediaItems.firstIndex(where: { $0.sourceAssetID == sourceAssetID }) else { return }
        guard case let .video(url, duration, lib) = mediaItems[index].kind,
              url == nil,
              lib == nil,
              duration == 0 else {
            return
        }

        let previous = mediaItems
        mediaItems.remove(at: index)
        pickerItemsBySourceAssetID.removeValue(forKey: sourceAssetID)
        currentSlideIndex = min(currentSlideIndex, max(0, mediaItems.count - 1))
        cleanupStaleMediaVideoCopies(from: previous, keeping: mediaItems)
        refreshSelectedPhotoItemsFromMediaItems()
    }

    private func prefetchVideoThumbnailFromLibrary(sourceAssetID: UUID, asset: PHAsset) async {
        guard let thumb = await makePhotoLibraryVideoThumbnail(for: asset) else { return }
        guard let index = mediaItems.firstIndex(where: { $0.sourceAssetID == sourceAssetID }) else { return }
        let row = mediaItems[index]
        guard case let .video(url, duration, libraryIdentifier) = row.kind else { return }
        mediaItems[index] = MediaItem(
            id: row.id,
            previewImage: thumb,
            kind: .video(url: url, duration: duration, libraryIdentifier: libraryIdentifier),
            sourceAssetID: sourceAssetID
        )
    }

    private func cleanupTemporaryImportSourceIfNeeded(_ url: URL) {
        guard url.isFileURL else { return }

        let temporaryPath = FileManager.default.temporaryDirectory.path
        let parentURL = url.deletingLastPathComponent()

        if parentURL.path.hasPrefix(temporaryPath) {
            try? FileManager.default.removeItem(at: parentURL)
        } else if url.path.hasPrefix(temporaryPath) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private var normalizedNarrationSourceText: String {
        narrationText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func needsPreviewRefresh(
        for text: String,
        voiceIdentifier: String,
        speechRateMultiplier: Double,
        requireFullLength: Bool = false
    ) -> Bool {
        narrationPreviewAudioURL == nil
            || narrationPreviewCues.isEmpty
            || previewSourceText != text
            || previewSourceVoiceIdentifier != voiceIdentifier
            || abs(previewSourceSpeechRate - speechRateMultiplier) > 0.0001
            || (requireFullLength && !narrationPreviewIsFullLength)
    }

    private func prepareNarrationPreview(
        text: String,
        voiceIdentifier: String,
        speechRateMultiplier: Double,
        maximumDuration: TimeInterval? = nil,
        startedMessage: String,
        completedMessage: String,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws {
        configureAudioSessionIfNeeded()
        isPreparingNarrationPreview = true
        clearNarrationPreviewState(resetCaption: true)
        narrationPreviewCaption = "Building narration preview..."
        statusMessage = startedMessage
        defer {
            isPreparingNarrationPreview = false
        }

        let preview = try await narrationPreviewBuilder.buildPreview(
            text: text,
            voiceIdentifier: voiceIdentifier,
            speechRateMultiplier: speechRateMultiplier,
            maximumDuration: maximumDuration,
            progressHandler: progressHandler
        )
        narrationPreviewPlayer = try AVAudioPlayer(contentsOf: preview.audioURL)
        narrationPreviewPlayer?.prepareToPlay()
        narrationPreviewAudioURL = preview.audioURL
        narrationPreviewDuration = preview.duration
        narrationPreviewCurrentTime = 0
        narrationPreviewCues = preview.cues
        narrationTimelineEngine = SubtitleTimelineEngine(cues: narrationPreviewCues)
        narrationPreviewCaption = preview.cues.first?.text ?? "Preview ready."
        previewSourceText = text
        previewSourceVoiceIdentifier = voiceIdentifier
        previewSourceSpeechRate = speechRateMultiplier
        narrationPreviewIsFullLength = maximumDuration == nil
        statusMessage = completedMessage
    }

    private func invalidateNarrationPreviewIfNeeded() {
        guard hasNarrationPreview || narrationPreviewDuration > 0 || narrationPreviewPlayer != nil else { return }
        clearNarrationPreviewState(resetCaption: true)
    }

    private func clearNarrationPreviewState(resetCaption: Bool) {
        narrationPreviewPlayer?.stop()
        narrationPreviewPlayer = nil
        narrationPreviewAudioURL = nil
        narrationPreviewDuration = 0
        narrationPreviewCurrentTime = 0
        narrationPreviewCues = []
        narrationTimelineEngine = SubtitleTimelineEngine(cues: [])
        previewSourceText = ""
        previewSourceVoiceIdentifier = ""
        previewSourceSpeechRate = 1.0
        narrationPreviewIsFullLength = false
        isNarrationPreviewPlaying = false
        stopNarrationPreviewTimer()
        if resetCaption {
            narrationPreviewCaption = "Build a seekable preview to test subtitle sync."
        }
    }

    private func videoDuration(for url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        return duration.map(CMTimeGetSeconds) ?? 0
    }

    private func makeVideoThumbnail(for url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 640, height: 640)
                let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func configureAudioSessionIfNeeded() {
        guard !didConfigureAudioSession else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo, options: [])
            try session.setActive(true)
            didConfigureAudioSession = true
        } catch {
            statusMessage = "Audio session setup failed."
        }
    }

    func prepareVideoPlaybackAudioSession() {
        configureAudioSessionIfNeeded()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            statusMessage = "Video playback audio could not start."
        }
    }

    private func copyImportedFileToDocuments(_ sourceURL: URL) throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileExtension = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let safeName = baseName.isEmpty ? "imported-audio" : baseName
        let destination = documents.appendingPathComponent("\(safeName)-\(UUID().uuidString).\(fileExtension)")

        try AppViewModelCopyUtilities.copyFileResolvingLargeSources(from: sourceURL, to: destination)
        return destination
    }

    private func copyImportedVideoFileToManagedTemporaryLocation(_ sourceURL: URL) throws -> URL {
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destination = managedTemporaryVideoURL(fileExtension: fileExtension)
        try AppViewModelCopyUtilities.copyFileResolvingLargeSources(from: sourceURL, to: destination)
        return destination
    }

    private func managedTemporaryVideoURL(fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("picked-video-\(UUID().uuidString).\(fileExtension)")
    }

    private func importMusicAssets(
        from selectedURLs: [URL],
        appendToQueue: Bool,
        shouldManageSecurityScope: Bool = true
    ) async {
        isImportingMusic = true
        statusMessage = selectedURLs.count > 1 ? "Importing soundtrack files..." : "Importing soundtrack..."
        defer {
            isImportingMusic = false
        }

        do {
            stopMusicSilently()
            var importedItems: [SoundtrackItem] = []

            for selectedURL in selectedURLs {
                let canAccess = shouldManageSecurityScope ? selectedURL.startAccessingSecurityScopedResource() : false
                defer {
                    if canAccess {
                        selectedURL.stopAccessingSecurityScopedResource()
                    }
                }

                let imported = try await prepareImportedMusicAsset(from: selectedURL)
                importedItems.append(
                    SoundtrackItem(
                        url: imported.url,
                        name: displayNameWithoutExtension(imported.displayName),
                        duration: imported.duration
                    )
                )
            }

            let updatedQueue = appendToQueue ? soundtrackItems + importedItems : importedItems
            await rebuildCombinedSoundtrack(
                from: updatedQueue,
                startedMessage: selectedURLs.count > 1 ? "Combining soundtrack files..." : "Preparing soundtrack..."
            )
            refreshMusicLibrary()
        } catch {
            statusMessage = error.localizedDescription.isEmpty ? "Could not import that music file." : error.localizedDescription
        }
    }

    private func saveMusicAssetsToLibrary(
        from selectedURLs: [URL],
        shouldManageSecurityScope: Bool = true
    ) async {
        isImportingMusic = true
        statusMessage = selectedURLs.count > 1 ? "Importing tracks into Music Library..." : "Importing track into Music Library..."
        defer {
            isImportingMusic = false
        }

        do {
            var importedCount = 0
            var existingCount = 0
            for selectedURL in selectedURLs {
                let canAccess = shouldManageSecurityScope ? selectedURL.startAccessingSecurityScopedResource() : false
                defer {
                    if canAccess {
                        selectedURL.stopAccessingSecurityScopedResource()
                    }
                }

                if let existingURL = try existingImportedAudioURL(matching: selectedURL) {
                    let _ = existingURL
                    existingCount += 1
                    continue
                }

                _ = try await prepareImportedMusicAsset(from: selectedURL)
                importedCount += 1
            }

            refreshMusicLibrary()
            switch (importedCount, existingCount) {
            case (0, let duplicates) where duplicates > 0:
                let message = duplicates == 1
                    ? "That music already exists in Music Library."
                    : "\(duplicates) music files already exist in Music Library."
                statusMessage = message
                musicLibraryFeedback = message
            case (let imported, 0):
                let message = imported == 1
                    ? "Music imported into Music Library."
                    : "\(imported) music files imported into Music Library."
                statusMessage = message
                musicLibraryFeedback = message
            case (let imported, let duplicates):
                let message = "\(imported) imported • \(duplicates) already existed"
                statusMessage = message
                musicLibraryFeedback = message
            default:
                statusMessage = "No music files were imported."
                musicLibraryFeedback = "No music files were imported."
            }
        } catch {
            statusMessage = error.localizedDescription.isEmpty ? "Could not import that music file into Music Library." : error.localizedDescription
            musicLibraryFeedback = statusMessage
        }
    }

    private func existingImportedAudioURL(matching sourceURL: URL) throws -> URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sourceSize = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let sourceName = Self.displayMusicName(for: sourceURL).lowercased()

        let documentContents = try FileManager.default.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        for url in documentContents {
            guard let importedURL = Self.importedAudioDocumentURL(url) else { continue }
            guard importedURL.pathExtension.lowercased() == sourceExtension else { continue }
            guard Self.displayMusicName(for: importedURL).lowercased() == sourceName else { continue }
            let importedSize = try importedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if importedSize == sourceSize {
                return importedURL
            }
        }

        return nil
    }

    private func prepareImportedMusicAsset(from sourceURL: URL) async throws -> (url: URL, displayName: String, wasExtractedFromVideo: Bool, duration: TimeInterval) {
        let sourceType = importedMediaType(for: sourceURL)
        switch sourceType {
        case .audio:
            let destination = try copyImportedFileToDocuments(sourceURL)
            return (destination, destination.lastPathComponent, false, await Self.audioDuration(for: destination))
        case .video:
            let extractedURL = try await extractAudioTrackIfNeeded(from: sourceURL)
            return (extractedURL, extractedURL.lastPathComponent, true, await Self.audioDuration(for: extractedURL))
        case .unknown:
            throw NSError(
                domain: "FluxCutMusicImport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "That file format is not supported for music. Use audio or a video with a soundtrack."]
            )
        }
    }

    private enum ImportedMediaType {
        case audio
        case video
        case unknown
    }

    nonisolated private static func importedMediaType(for url: URL) -> ImportedMediaType {
        guard let contentType = UTType(filenameExtension: url.pathExtension) else {
            return .unknown
        }
        if contentType.conforms(to: .audio) || contentType.conforms(to: .mpeg4Audio) || contentType.conforms(to: .mp3) || contentType.conforms(to: .wav) {
            return .audio
        }
        if contentType.conforms(to: .movie) || contentType.conforms(to: .video) || contentType.conforms(to: .mpeg4Movie) || contentType.conforms(to: .quickTimeMovie) {
            return .video
        }
        return .unknown
    }

    private func importedMediaType(for url: URL) -> ImportedMediaType {
        Self.importedMediaType(for: url)
    }

    private func extractAudioTrackIfNeeded(from sourceURL: URL) async throws -> URL {
        let destination = try extractedAudioCacheURL(for: sourceURL)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw NSError(
                domain: "FluxCutMusicImport",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "That video does not contain an audio track to use as music."]
            )
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(
                domain: "FluxCutMusicImport",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "FluxCut could not prepare audio extraction for that video."]
            )
        }

        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        exportSession.outputURL = destination
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = false

        let exportSessionBox = ExportSessionBox(exportSession)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSessionBox.session.exportAsynchronously {
                switch exportSessionBox.session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: exportSessionBox.session.error ?? NSError(
                        domain: "FluxCutMusicImport",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Audio extraction from that video failed."]
                    ))
                case .cancelled:
                    continuation.resume(throwing: NSError(
                        domain: "FluxCutMusicImport",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "Audio extraction was cancelled."]
                    ))
                default:
                    continuation.resume(throwing: NSError(
                        domain: "FluxCutMusicImport",
                        code: 6,
                        userInfo: [NSLocalizedDescriptionKey: "Audio extraction did not finish correctly."]
                    ))
                }
            }
        }

        return destination
    }

    private func rebuildCombinedSoundtrack(from items: [SoundtrackItem], startedMessage: String) async {
        isImportingMusic = true
        statusMessage = startedMessage
        defer {
            isImportingMusic = false
        }

        do {
            stopMusicSilently()
            soundtrackItems = items

            guard let prepared = try await prepareCombinedSoundtrack(from: items) else {
                clearMusicSelection()
                return
            }

            importedMusicURL = prepared.url
            importedMusicName = prepared.displayName
            try prepareAudioPlayer(with: prepared.url)
            hasPendingPreviewChanges = true
            hasPendingFinalVideoChanges = true
            statusMessage = items.count > 1
                ? "Combined soundtrack is ready to play."
                : "\(prepared.baseName) is ready to play."
        } catch {
            statusMessage = error.localizedDescription.isEmpty ? "Could not build the combined soundtrack." : error.localizedDescription
        }
    }

    private func prepareCombinedSoundtrack(from items: [SoundtrackItem]) async throws -> (url: URL, displayName: String, baseName: String)? {
        guard !items.isEmpty else { return nil }
        if items.count == 1, let single = items.first {
            return (single.url, single.url.lastPathComponent, single.name)
        }

        let outputURL = try combinedSoundtrackOutputURL()
        try await mergeAudioFilesSequentially(items.map(\.url), outputURL: outputURL)
        return (outputURL, outputURL.lastPathComponent, "Combined Soundtrack")
    }

    private func combinedSoundtrackOutputURL() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = documents.appendingPathComponent("CombinedAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("combined-soundtrack.m4a")
    }

    private func mergeAudioFilesSequentially(_ urls: [URL], outputURL: URL) async throws {
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "FluxCutMusicImport", code: 7, userInfo: [NSLocalizedDescriptionKey: "FluxCut could not prepare the combined soundtrack."])
        }

        var insertionTime = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let sourceTrack = tracks.first else { continue }
            try compositionTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceTrack, at: insertionTime)
            insertionTime = insertionTime + duration
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "FluxCutMusicImport", code: 8, userInfo: [NSLocalizedDescriptionKey: "FluxCut could not export the combined soundtrack."])
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = false
        let sessionBox = ExportSessionBox(exportSession)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionBox.session.exportAsynchronously {
                switch sessionBox.session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: sessionBox.session.error ?? NSError(domain: "FluxCutMusicImport", code: 9, userInfo: [NSLocalizedDescriptionKey: "Combined soundtrack export failed."]))
                case .cancelled:
                    continuation.resume(throwing: NSError(domain: "FluxCutMusicImport", code: 10, userInfo: [NSLocalizedDescriptionKey: "Combined soundtrack export was cancelled."]))
                default:
                    continuation.resume(throwing: NSError(domain: "FluxCutMusicImport", code: 11, userInfo: [NSLocalizedDescriptionKey: "Combined soundtrack did not finish correctly."]))
                }
            }
        }
    }

    private func extractedAudioCacheURL(for sourceURL: URL) throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sharedAudioFolder = documents.appendingPathComponent("SharedAudio", isDirectory: true)
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let safeBaseName = sanitizeFileComponent(baseName.isEmpty ? "video-soundtrack" : baseName)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? NSNumber)?.stringValue ?? "0"
        let rawKey = "\(safeBaseName.lowercased())|\(fileSize)|\(sourceURL.pathExtension.lowercased())"
        let digest = Insecure.MD5.hash(data: Data(rawKey.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12)
        return sharedAudioFolder.appendingPathComponent("\(safeBaseName)-\(digest).m4a")
    }

    private func sanitizeFileComponent(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalarView = text.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let cleaned = String(scalarView).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? "soundtrack" : cleaned
    }

    private func prepareAudioPlayer(with url: URL) throws {
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.delegate = self
        audioPlayer?.numberOfLoops = -1
        audioPlayer?.volume = Float(musicVolume)
        audioPlayer?.prepareToPlay()
        musicPlaybackDuration = audioPlayer?.duration ?? 0
        musicPlaybackCurrentTime = 0
        isMusicPlaying = false
    }

    var hasSelectedMusic: Bool {
        importedMusicURL != nil
    }

    var shareableMusicURL: URL? {
        importedMusicURL
    }

    func formattedMusicDuration(_ duration: TimeInterval) -> String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    nonisolated private static func audioDuration(for url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        return duration.map(CMTimeGetSeconds) ?? 0
    }

    nonisolated private static func quickAudioDuration(for url: URL) -> TimeInterval {
        if let player = try? AVAudioPlayer(contentsOf: url) {
            return player.duration
        }
        return 0
    }

    private func syncMusicPlaybackState() {
        musicPlaybackCurrentTime = audioPlayer?.currentTime ?? 0
        musicPlaybackDuration = audioPlayer?.duration ?? 0
    }

    private func startMusicPlaybackTimer() {
        stopMusicPlaybackTimer()
        musicPlaybackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncMusicPlaybackState()
            }
        }
    }

    private func stopMusicPlaybackTimer() {
        musicPlaybackTimer?.invalidate()
        musicPlaybackTimer = nil
    }

    private func displayNameWithoutExtension(_ name: String) -> String {
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? name : base
    }

    nonisolated private static func displayMusicName(for url: URL) -> String {
        let baseName = url.deletingPathExtension().lastPathComponent
        let withoutHashSuffix = baseName.replacingOccurrences(
            of: "-[0-9A-Fa-f]{12}$",
            with: "",
            options: .regularExpression
        )
        let withoutUUIDSuffix = withoutHashSuffix.replacingOccurrences(
            of: "-[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$",
            with: "",
            options: .regularExpression
        )
        let cleaned = withoutUUIDSuffix.replacingOccurrences(
            of: "-[0-9A-Fa-f]{8,}(?:-[0-9A-Fa-f]{2,})+$",
            with: "",
            options: .regularExpression
        )
        return cleaned.isEmpty ? baseName : cleaned
    }

    nonisolated private static func sourceSortRank(_ source: MusicLibraryItem.Source) -> Int {
        switch source {
        case .builtIn:
            return 0
        case .imported:
            return 1
        case .extracted:
            return 2
        }
    }

    private func startNarrationPreviewTimer() {
        stopNarrationPreviewTimer()
        narrationPreviewTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.narrationPreviewPlayer else { return }
                self.narrationPreviewCurrentTime = player.currentTime
                self.updateNarrationPreviewCaption(for: player.currentTime)
                if !player.isPlaying {
                    self.isNarrationPreviewPlaying = false
                    self.stopNarrationPreviewTimer()
                }
            }
        }
    }

    private func stopNarrationPreviewTimer() {
        narrationPreviewTimer?.invalidate()
        narrationPreviewTimer = nil
    }

    private func updateNarrationPreviewCaption(for time: Double) {
        let lead = SubtitleTimelineEngine.displayLeadSeconds
        let lookupTime = max(0, time - lead)
        if let cue = narrationTimelineEngine.cue(at: lookupTime) {
            narrationPreviewCaption = cue.text
        } else {
            narrationPreviewCaption = narrationPreviewCues.first?.text ?? "Build a seekable preview to test subtitle sync."
        }
    }

    private func downsampledImage(from data: Data, maxDimension: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    var selectedVoiceDisplayName: String {
        availableVoices.first(where: { $0.id == selectedVoiceIdentifier })?.displayName ?? "No Apple voice selected yet."
    }

    var availableVoiceLanguages: [VoiceLanguageOption] {
        let grouped = Dictionary(grouping: availableVoices, by: \.languageGroup)
        return grouped.compactMap { group, voices in
            guard let label = voices.first?.languageLabel else { return nil }
            return VoiceLanguageOption(id: group, label: label, voiceCount: voices.count)
        }
        .sorted { lhs, rhs in
            SpeechVoiceLibrary.preferredLanguageRank(lhs.id) > SpeechVoiceLibrary.preferredLanguageRank(rhs.id)
        }
    }

    var voicesForSelectedLanguage: [VoiceOption] {
        let matchingVoices = availableVoices.filter { $0.languageGroup == selectedVoiceLanguage }
        return matchingVoices.isEmpty ? availableVoices : matchingVoices
    }

    var selectedVoiceLanguageLabel: String {
        availableVoiceLanguages.first(where: { $0.id == selectedVoiceLanguage })?.label
            ?? voicesForSelectedLanguage.first?.languageLabel
            ?? "No high-quality language available"
    }

    var narrationSpeedOptions: [NarrationSpeedOption] {
        [0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.8, 2.0].map(NarrationSpeedOption.init)
    }

    var selectedNarrationSpeedLabel: String {
        String(format: "%.1fx", selectedNarrationSpeed)
    }

    var canHideVoices: Bool {
        availableVoices.count > 1
    }

    var narrationPreviewSummary: String {
        if isPreparingNarrationPreview {
            return "Generating preview audio and subtitle cues from your current script."
        }
        if narrationPreviewDuration > 0 {
            return "Scrub the timeline to inspect how the built-in subtitle engine follows the narration."
        }
        return "Build the preview to create a seekable narration pass with automatic caption cues."
    }

    var narrationPreviewMetaLine: String {
        guard narrationPreviewDuration > 0 else { return "No preview built yet" }
        return "\(formatPreviewTime(narrationPreviewDuration)) total"
    }

    var estimatedNarrationMetaLine: String {
        guard estimatedNarrationDurationSeconds > 0 else { return "Add a script to estimate pacing." }
        return "Narration Length: \(formatPreviewTime(estimatedNarrationDurationSeconds))"
    }

    var narrationLanguageWarning: String? {
        guard let detectedFamily = detectedNarrationLanguageFamily,
              hasNarrationLanguageMismatch else { return nil }
        return "Script looks like \(detectedFamily.label). Choose a matching narration voice before playing or rendering."
    }

    var estimatedExportSpecLine: String {
        let videoModeSettings = VideoExporter.VideoModeExportSettings(
            frameRate: selectedVideoModeFrameRate,
            resolution: selectedVideoModeResolution,
            quality: selectedVideoModeQuality
        )
        let exporterMediaItems = mediaItems.map { item in
            let kind: VideoExporter.MediaItem.Kind
            switch item.kind {
            case .photo:
                kind = .photo
            case let .video(url, duration, _):
                let resolvedURL = url ?? FileManager.default.temporaryDirectory.appendingPathComponent("estimated-video-placeholder.mov")
                kind = .video(url: resolvedURL, duration: CMTime(seconds: duration, preferredTimescale: 600))
            }
            return VideoExporter.MediaItem(previewImage: item.previewImage, kind: kind)
        }

        guard estimatedDurationSecondsForSelectedMode > 0 else {
            return selectedTimingMode == .video
                ? "Video mode • add videos to estimate export specs"
                : "\(selectedAspectRatio.rawValue) • add script or media to estimate export specs"
        }

        return videoExporter.estimatedExportSpec(
            mediaItems: exporterMediaItems,
            durationSeconds: estimatedDurationSecondsForSelectedMode,
            aspectRatio: selectedAspectRatio,
            finalQuality: selectedFinalExportQuality,
            timingMode: selectedTimingMode,
            includeCaptions: selectedTimingMode != .video ? includesFinalCaptions : false,
            videoModeSettings: (selectedTimingMode == .video || selectedTimingMode == .realLife) ? videoModeSettings : nil
        )
    }

    /// Placeholder row for a file-backed video still being copied from the picker (`url` and library id are both nil, duration not yet known).
    private var hasIncompletePickerVideoImports: Bool {
        mediaItems.contains {
            if case let .video(url, duration, lib) = $0.kind {
                return url == nil && lib == nil && duration == 0
            }
            return false
        }
    }

    var mediaSelectionMetaLine: String {
        guard !mediaItems.isEmpty else { return "No media selected yet." }

        if hasIncompletePickerVideoImports {
            let finishing = mediaItems.filter {
                if case let .video(url, duration, lib) = $0.kind {
                    return url == nil && lib == nil && duration == 0
                }
                return false
            }.count
            let suffix = finishing == 1 ? "1 video" : "\(finishing) videos"
            return "Copying \(suffix) into FluxCut…"
        }

        let photoCount = mediaItems.reduce(0) { partial, item in
            switch item.kind {
            case .photo:
                return partial + 1
            case .video:
                return partial
            }
        }

        let totalVideoSeconds = mediaItems.reduce(0.0) { partial, item in
            switch item.kind {
            case .photo:
                return partial
            case let .video(_, duration, _):
                return partial + duration
            }
        }

        let videoCount = mediaItems.reduce(0) { partial, item in
            switch item.kind {
            case .photo:
                return partial
            case .video:
                return partial + 1
            }
        }

        let photoLabel = photoCount == 1 ? "1 photo" : "\(photoCount) photos"
        let videoLabel = videoCount == 1 ? "1 video" : "\(videoCount) videos"
        let videoMinutes = max(Int((totalVideoSeconds / 60).rounded()), 0)
        let durationLabel = videoMinutes == 1 ? "1 min" : "\(videoMinutes) min"
        return "\(photoLabel) • \(videoLabel) • \(durationLabel)"
    }

    var mediaSelectionLoadingLine: String {
        if selectedPhotoItems.isEmpty {
            return "Loading media selection..."
        }
        let itemCount = selectedPhotoItems.count
        return itemCount == 1 ? "Loading 1 selected item..." : "Loading \(itemCount) selected items..."
    }

    var canStartVideoPreviewRender: Bool {
        !isLoadingMediaSelection
            && !hasIncompletePickerVideoImports
            && hasRenderableMediaForSelectedMode
            && !isExportingVideo
            && !isPreparingVideoPreview
            && !isPreparingNarrationPreview
            && !hasNarrationLanguageMismatchForRender
            && storyCaptionOffPlanningWarning == nil
    }

    var canStartFinalVideoRender: Bool {
        !isLoadingMediaSelection
            && !hasIncompletePickerVideoImports
            && hasRenderableMediaForSelectedMode
            && !isExportingVideo
            && !isPreparingVideoPreview
            && !isPreparingNarrationPreview
            && hasPendingFinalVideoChanges
            && !hasNarrationLanguageMismatchForRender
            && storyCaptionOffPlanningWarning == nil
    }

    var activeStatusMessage: String {
        storyCaptionOffPlanningWarning ?? statusMessage
    }

    var canPlayNarration: Bool {
        !isPreparingNarrationPreview && !hasNarrationLanguageMismatch
    }

    var canBuildNarrationPreview: Bool {
        !isPreparingNarrationPreview && !hasNarrationLanguageMismatch
    }

    var hasNarrationPreview: Bool {
        !isPreparingNarrationPreview
            && narrationPreviewDuration > 0
            && !narrationPreviewCues.isEmpty
            && previewSourceText == normalizedNarrationSourceText
            && previewSourceVoiceIdentifier == selectedVoiceIdentifier
            && abs(previewSourceSpeechRate - selectedNarrationSpeed) <= 0.0001
    }

    private func formatPreviewTime(_ value: TimeInterval) -> String {
        let totalSeconds = max(Int(value.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var estimatedNarrationDurationSeconds: Double {
        let normalized = normalizedNarrationSourceText
        guard !normalized.isEmpty else { return 0 }

        let segments = SpeechVoiceLibrary.narrationSegments(from: normalized, optimizeForLongForm: true)
        let baseEstimate = max(segments.reduce(0.0) { partial, segment in
            let timingText = SpeechVoiceLibrary.normalizedTimingText(segment)
            if SpeechVoiceLibrary.containsCJKContent(in: timingText) {
                return partial + max(Double(timingText.count) / 3.6, 0.8)
            }
            let words = timingText.split(whereSeparator: \.isWhitespace)
            return partial + max(Double(words.count) / 2.4, 0.8)
        }, 1)
        return max(baseEstimate / max(SpeechVoiceLibrary.effectiveSpeechRateMultiplier(for: selectedNarrationSpeed), 0.1), 1)
    }

    private var estimatedMediaOnlyDurationSeconds: Double {
        guard !mediaItems.isEmpty else { return 0 }

        let totalVideoSeconds = mediaItems.reduce(0.0) { partial, item in
            switch item.kind {
            case .photo:
                return partial
            case let .video(_, duration, _):
                return partial + max(duration, 0)
            }
        }

        let photoCount = mediaItems.reduce(0) { partial, item in
            switch item.kind {
            case .photo:
                return partial + 1
            case .video:
                return partial
            }
        }

        if totalVideoSeconds == 0, photoCount > 0 {
            return 300
        }

        let photoSeconds = max(Double(photoCount) * 1.6, photoCount > 0 ? 1.6 : 0)
        return max(totalVideoSeconds + photoSeconds, 3)
    }

    private var estimatedVideoOnlyDurationSeconds: Double {
        let totalVideoSeconds = mediaItems.reduce(0.0) { partial, item in
            switch item.kind {
            case .photo:
                return partial
            case let .video(_, duration, _):
                return partial + max(duration, 0)
            }
        }

        return totalVideoSeconds
    }

    private var estimatedDurationSecondsForSelectedMode: Double {
        switch selectedTimingMode {
        case .video:
            return estimatedVideoOnlyDurationSeconds
        case .realLife:
            if estimatedNarrationDurationSeconds > 0 {
                return max(estimatedMediaOnlyDurationSeconds, estimatedNarrationDurationSeconds)
            }
            return estimatedMediaOnlyDurationSeconds
        case .story:
            return estimatedNarrationDurationSeconds > 0 ? estimatedNarrationDurationSeconds : estimatedMediaOnlyDurationSeconds
        }
    }

    var storyCaptionOffPlanningWarning: String? {
        guard selectedTimingMode == .story,
              !includesFinalCaptions else { return nil }

        let narrationSeconds = estimatedNarrationDurationSeconds
        guard narrationSeconds > 0 else { return nil }

        let photoCount = mediaItems.reduce(0) { partial, item in
            switch item.kind {
            case .photo:
                return partial + 1
            case .video:
                return partial
            }
        }
        guard photoCount > 0 else { return nil }

        let totalVideoSeconds = mediaItems.reduce(0.0) { partial, item in
            switch item.kind {
            case .photo:
                return partial
            case let .video(_, duration, _):
                return partial + max(duration, 0)
            }
        }

        let rawPhotoTime = max(narrationSeconds - totalVideoSeconds, 0) / Double(photoCount)
        guard rawPhotoTime > 20 else { return nil }
        return "Story without captions needs more media. Add more photos or videos so each photo would be 20 seconds or less."
    }

    private var hasRenderableMediaForSelectedMode: Bool {
        switch selectedTimingMode {
        case .video:
            return mediaItems.contains(where: \.isVideo)
        case .story, .realLife:
            return !mediaItems.isEmpty
        }
    }

    private var hasNarrationLanguageMismatchForRender: Bool {
        selectedTimingMode != .video && hasNarrationLanguageMismatch
    }

    private var hasNarrationLanguageMismatch: Bool {
        guard !normalizedNarrationSourceText.isEmpty,
              let detectedFamily = detectedNarrationLanguageFamily else {
            return false
        }
        return !Self.voiceLanguageGroup(selectedVoiceLanguage, isCompatibleWith: detectedFamily)
    }

    private var detectedNarrationLanguageFamily: ScriptLanguageFamily? {
        Self.detectNarrationLanguageFamily(for: normalizedNarrationSourceText)
    }

    private func markAllVideoRendersDirty(reason: String) {
        hasPendingPreviewChanges = true
        hasPendingFinalVideoChanges = true
        if exportedVideoURL != nil || videoPreviewURL != nil {
            statusMessage = reason
        }
    }

    private func filteredVoices(from voices: [VoiceOption]) -> [VoiceOption] {
        voices.filter { !hiddenVoiceIdentifiers.contains($0.id) }
    }

    private func saveHiddenVoiceIdentifiers() {
        UserDefaults.standard.set(Array(hiddenVoiceIdentifiers), forKey: Self.hiddenVoiceIdentifiersKey)
    }

    private func applyVoiceFiltersAndSelection() {
        availableVoices = filteredVoices(from: allAvailableVoices)
        if availableVoices.isEmpty {
            availableVoices = allAvailableVoices
        }
        reconcileSelectedVoiceLanguage()
        reconcileSelectedVoice()
    }

    private func reconcileSelectedVoice() {
        let matchingVoices = voicesForSelectedLanguage
        if !matchingVoices.contains(where: { $0.id == selectedVoiceIdentifier }) {
            selectedVoiceIdentifier = matchingVoices.first?.id ?? availableVoices.first?.id ?? ""
        } else {
            selectedVoiceName = selectedVoiceDisplayName
        }
    }

    private func reconcileSelectedVoiceLanguage() {
        let availableLanguages = availableVoiceLanguages
        if availableLanguages.contains(where: { $0.id == selectedVoiceLanguage }) {
            return
        }
        selectedVoiceLanguage = availableLanguages.first?.id ?? ""
    }

    private func selectBestVoiceForSelectedLanguage() {
        let matchingVoices = availableVoices.filter { $0.languageGroup == selectedVoiceLanguage }
        guard let bestVoice = matchingVoices.first else {
            if !availableVoices.isEmpty {
                reconcileSelectedVoiceLanguage()
                reconcileSelectedVoice()
            }
            return
        }

        if selectedVoiceIdentifier != bestVoice.id {
            selectedVoiceIdentifier = bestVoice.id
        } else {
            selectedVoiceName = bestVoice.displayName
        }
    }

    private func selectLanguageCompatibleVoiceIfNeeded(for text: String) {
        guard !availableVoices.isEmpty else { return }

        if availableVoices.contains(where: { $0.id == selectedVoiceIdentifier }) {
            return
        }

        let expectsCJKVoice = SpeechVoiceLibrary.containsCJKContent(in: text)
        let selectedIsCompatible = availableVoices.contains {
            $0.id == selectedVoiceIdentifier && Self.voiceOption($0, isCompatibleWithCJK: expectsCJKVoice)
        }

        if selectedIsCompatible {
            return
        }

        if let matchingVisibleVoice = availableVoices.first(where: {
            Self.voiceOption($0, isCompatibleWithCJK: expectsCJKVoice)
        }) {
            selectedVoiceLanguage = matchingVisibleVoice.languageGroup
            selectedVoiceIdentifier = matchingVisibleVoice.id
            selectedVoiceName = matchingVisibleVoice.displayName
        }
    }

    private func resolvedPlayableVoiceIdentifier() -> String {
        if availableVoices.contains(where: { $0.id == selectedVoiceIdentifier }) {
            return selectedVoiceIdentifier
        }
        if let firstVisibleVoice = availableVoices.first?.id {
            return firstVisibleVoice
        }
        if let firstAvailableVoice = allAvailableVoices.first?.id {
            return firstAvailableVoice
        }
        if let firstSystemVoice = SpeechVoiceLibrary.voiceOptions.first?.id {
            return firstSystemVoice
        }
        if let firstFallback = SpeechVoiceLibrary.initialVoiceOptions.first?.id {
            return firstFallback
        }
        return ""
    }

    private static func cleanedNarrationText(from text: String) -> String {
        let rawLines = text.components(separatedBy: .newlines)
        let cleanedLines = rawLines
            .map(cleanupNarrationLine)
            .filter { !$0.isEmpty }

        var finalLines = cleanedLines
        for index in cleanedLines.indices.dropLast() {
            let line = cleanedLines[index]
            let nextLine = cleanedLines[index + 1]
            guard shouldAppendPausePeriod(to: line, before: nextLine) else { continue }
            finalLines[index] = line + pauseTerminator(for: line, nextLine: nextLine)
        }

        if let lastIndex = finalLines.lastIndex(where: { !$0.isEmpty }) {
            let line = finalLines[lastIndex]
            if shouldAppendTerminalPausePeriod(to: line) {
                finalLines[lastIndex] = line + pauseTerminator(for: line, nextLine: line)
            }
        }

        return finalLines.joined(separator: "\n")
    }

    private static func cleanupNarrationLine(_ line: String) -> String {
        var cleaned = line.trimmingCharacters(in: narrationTrimCharacterSet)
        guard !cleaned.isEmpty else { return "" }

        cleaned = trimmedLeadingNarrationJunk(from: cleaned)

        cleaned = cleaned.replacingOccurrences(
            of: #"^[\(\uff08]?\d+[\)\uff09]?[.)\uff0e\uff09](?=\s*[\p{L}\p{N}])\s*"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"^\d+\s*[-:\uff1a](?=\s*[\p{L}\p{N}])\s*"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"^[一二三四五六七八九十百千万零〇两甲乙丙丁戊己庚辛壬癸]+[、.)\uff09\uff0e](?=\s*[\p{L}\p{N}])\s*"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return cleaned.trimmingCharacters(in: narrationTrimCharacterSet)
    }

    private static func trimmedLeadingNarrationJunk(from text: String) -> String {
        let junk = CharacterSet(charactersIn: ".-–—,:;!?，。！？•‣◦⁃∙ \t\u{3000}")
        let scalars = text.unicodeScalars
        let trimmedScalars = scalars.drop(while: { junk.contains($0) })
        return String(String.UnicodeScalarView(trimmedScalars))
    }

    private static func shouldAppendPausePeriod(to line: String, before nextLine: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: narrationTrimCharacterSet)
        guard !trimmed.isEmpty else { return false }
        guard containsNarrationContent(trimmed) else { return false }
        guard !trimmed.hasSuffix(",") else { return false }
        guard !endsWithPausePunctuation(trimmed) else { return false }
        return containsNarrationContent(nextLine)
    }

    private static func shouldAppendTerminalPausePeriod(to line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: narrationTrimCharacterSet)
        guard !trimmed.isEmpty else { return false }
        guard containsNarrationContent(trimmed) else { return false }
        guard !trimmed.hasSuffix(",") else { return false }
        return !endsWithPausePunctuation(trimmed)
    }

    private static func pauseTerminator(for line: String, nextLine: String) -> String {
        if containsChineseStyleText(line) || containsChineseStyleText(nextLine) {
            return "。"
        }
        return "."
    }

    private static func containsChineseStyleText(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3000...0x303F, 0xFF00...0xFFEF:
                return true
            default:
                return false
            }
        }
    }

    private static func containsNarrationContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar)
                || CharacterSet.decimalDigits.contains(scalar)
                || containsChineseStyleScalar(scalar)
        }
    }

    private static func containsChineseStyleScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF:
            return true
        default:
            return false
        }
    }

    private static func endsWithPausePunctuation(_ line: String) -> Bool {
        let trailingTrimmed = line.trimmingCharacters(in: narrationTrimCharacterSet)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'”“‘’)]}）】》」』」』）】》,，"))
        guard let lastCharacter = trailingTrimmed.last else { return false }
        return ".!?;:。！？；：…".contains(lastCharacter)
    }

    private static let narrationTrimCharacterSet = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "\u{3000}"))

    private static func detectNarrationLanguageFamily(for text: String) -> ScriptLanguageFamily? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(normalized)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let (language, confidence) = hypotheses.first, confidence >= 0.55 else {
            return nil
        }

        switch language {
        case .english:
            return .english
        case .simplifiedChinese, .traditionalChinese:
            return .chinese
        case .japanese:
            return .japanese
        case .korean:
            return .korean
        case .arabic:
            return .arabic
        default:
            return nil
        }
    }

    private static func voiceLanguageGroup(_ group: String, isCompatibleWith family: ScriptLanguageFamily) -> Bool {
        switch family {
        case .english:
            return group == "en"
        case .chinese:
            return group == "zh" || group == "yue" || group == "wuu"
        case .japanese:
            return group == "ja"
        case .korean:
            return group == "ko"
        case .arabic:
            return group == "ar"
        case .unknown:
            return true
        }
    }

    private static func voiceOption(_ option: VoiceOption, isCompatibleWithCJK expectsCJKVoice: Bool) -> Bool {
        if expectsCJKVoice {
            return option.language.hasPrefix("zh")
                || option.language.hasPrefix("yue")
                || option.language.hasPrefix("wuu")
                || option.language.hasPrefix("ja")
                || option.language.hasPrefix("ko")
        }
        return option.language.hasPrefix("en")
    }

    private func resetSpeechSynthesizer() {
        speechSynthesizer.delegate = nil
        speechSynthesizer = AVSpeechSynthesizer()
        speechSynthesizer.delegate = self
    }
}

extension AppViewModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isMusicPlaying = false
        }
    }
}

extension AppViewModel: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
            self.statusMessage = "Script is playing with \(self.selectedVoiceDisplayName)."
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.pendingUtteranceCount = max(0, self.pendingUtteranceCount - 1)
            if self.pendingUtteranceCount == 0 {
                self.isSpeaking = false
                self.statusMessage = "Narration finished."
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.pendingUtteranceCount = 0
        }
    }
}

private extension UIImage {
    func normalizedOrientationImage() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

enum SpeechVoiceLibrary {
    private static let noveltyVoiceKeywords = [
        "bad news",
        "good news",
        "organ",
        "bells",
        "boing",
        "bubbles",
        "whisper",
        "wobble",
        "zarvox",
        "trinoids",
        "hysterical"
    ]

    static var voiceOptions: [AppViewModel.VoiceOption] {
        let preferred = preferredEnhancedPremiumVoices
        if !preferred.isEmpty {
            return preferred
        }
        return fallbackVoices
    }

    static var preferredEnhancedPremiumVoices: [AppViewModel.VoiceOption] {
        mapVoices(
            AVSpeechSynthesisVoice.speechVoices().filter {
                !isNoveltyVoice($0) &&
                qualityRank(qualityLabel(for: $0)) >= 2
            },
            isFallback: false
        )
    }

    static var initialVoiceOptions: [AppViewModel.VoiceOption] {
        let preferred = preferredEnhancedPremiumVoices
        if !preferred.isEmpty {
            return preferred
        }
        return fallbackVoices
    }

    static func voice(for identifier: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: identifier)
            ?? AVSpeechSynthesisVoice(language: identifier)
            ?? defaultVoice
    }

    /// BCP-47 language tag from the resolved voice (drives `CaptionTextChunker` / `NLTokenizer`).
    static func voiceLanguageTag(forVoiceIdentifier identifier: String) -> String {
        voice(for: identifier)?.language ?? ""
    }

    /// One TTS utterance (and one caption) per sentence for Chinese, Japanese, and Lao family voices only.
    static func usesSentenceAlignedNarration(voiceLanguageTag: String) -> Bool {
        let id = voiceLanguageTag.lowercased().replacingOccurrences(of: "_", with: "-")
        guard !id.isEmpty else { return false }
        return id.hasPrefix("zh") || id.hasPrefix("yue") || id.hasPrefix("wuu")
            || id.hasPrefix("ja") || id.hasPrefix("lo")
    }

    static func makeUtterances(
        from text: String,
        voiceIdentifier: String,
        speechRateMultiplier: Double = 1.0,
        optimizeForLongForm: Bool = false
    ) -> [AVSpeechUtterance] {
        narrationSegments(from: text, optimizeForLongForm: optimizeForLongForm).map {
            makeUtterance(from: $0, voiceIdentifier: voiceIdentifier, speechRateMultiplier: speechRateMultiplier)
        }
    }

    static func narrationSegments(from text: String, optimizeForLongForm: Bool = false) -> [String] {
        chunkedText(from: text, optimizeForLongForm: optimizeForLongForm)
    }

    static func normalizedCaptionText(_ text: String) -> String {
        collapseCaptionWhitespace(in: normalizeSpeechText(text))
    }

    static func normalizedTimingText(_ text: String) -> String {
        let normalized = normalizedCaptionText(text)
        let withoutSilentSymbols = normalized.replacingOccurrences(
            of: "[()\\[\\]{}\"“”‘’]",
            with: " ",
            options: .regularExpression
        )
        let punctuationSoftened = withoutSilentSymbols.replacingOccurrences(
            of: "[.。,;:!?，；：！？、]+",
            with: " ",
            options: .regularExpression
        )
        return punctuationSoftened
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func makeUtterance(from text: String, voiceIdentifier: String, speechRateMultiplier: Double = 1.0) -> AVSpeechUtterance {
        let selectedVoice = resolvedVoice(for: text, preferredIdentifier: voiceIdentifier)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = speakingRate(for: selectedVoice, multiplier: speechRateMultiplier)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.02
        utterance.postUtteranceDelay = postUtteranceDelay(for: text.last)
        return utterance
    }

    static func effectiveSpeechRateMultiplier(for selectedMultiplier: Double) -> Double {
        switch selectedMultiplier {
        case ..<0.85:
            return 0.80
        case ..<0.95:
            return 0.90
        case ..<1.05:
            return 1.00
        case ..<1.15:
            return 1.12
        case ..<1.25:
            return 1.24
        case ..<1.35:
            return 1.36
        case ..<1.45:
            return 1.50
        case ..<1.65:
            return 1.66
        case ..<1.90:
            return 1.86
        default:
            return 2.00
        }
    }

    private static var defaultVoice: AVSpeechSynthesisVoice? {
        if let preferredLanguageVoice = preferredLanguageVoices().first {
            return preferredLanguageVoice
        }

        let preferredVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            !isNoveltyVoice($0) &&
            qualityRank(qualityLabel(for: $0)) >= 2
        }
        if !preferredVoices.isEmpty {
            return preferredVoices.sorted {
                let lhsRank = preferredNameRank($0.name)
                let rhsRank = preferredNameRank($1.name)
                if lhsRank != rhsRank {
                    return lhsRank > rhsRank
                }
                return qualityRank(qualityLabel(for: $0)) > qualityRank(qualityLabel(for: $1))
            }.first
        }

        let fallbackVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            !isNoveltyVoice($0) && qualityRank(qualityLabel(for: $0)) >= 2
        }
        if !fallbackVoices.isEmpty {
            return fallbackVoices.sorted {
                let lhsRank = preferredNameRank($0.name)
                let rhsRank = preferredNameRank($1.name)
                if lhsRank != rhsRank {
                    return lhsRank > rhsRank
                }
                let lhsLanguageRank = preferredLanguageRank($0.language)
                let rhsLanguageRank = preferredLanguageRank($1.language)
                if lhsLanguageRank != rhsLanguageRank {
                    return lhsLanguageRank > rhsLanguageRank
                }
                return $0.name < $1.name
            }.first
        }

        return AVSpeechSynthesisVoice.speechVoices().first(where: { !isNoveltyVoice($0) && qualityRank(qualityLabel(for: $0)) >= 2 })
    }

    private static func resolvedVoice(for text: String, preferredIdentifier: String) -> AVSpeechSynthesisVoice? {
        let preferredVoice = voice(for: preferredIdentifier)
        if let preferredVoice {
            return preferredVoice
        }
        let expectsCJKVoice = containsCJKContent(in: text)

        let candidateVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            !isNoveltyVoice($0) &&
            qualityRank(qualityLabel(for: $0)) >= 2 &&
            isVoice($0, compatibleWithCJK: expectsCJKVoice)
        }

        if !candidateVoices.isEmpty {
            return candidateVoices.sorted {
                let lhsLanguageRank = preferredLanguageRank($0.language)
                let rhsLanguageRank = preferredLanguageRank($1.language)
                if lhsLanguageRank != rhsLanguageRank {
                    return lhsLanguageRank > rhsLanguageRank
                }

                let lhsQuality = qualityRank(qualityLabel(for: $0))
                let rhsQuality = qualityRank(qualityLabel(for: $1))
                if lhsQuality != rhsQuality {
                    return lhsQuality > rhsQuality
                }

                return $0.name < $1.name
            }.first
        }

        return defaultVoice
    }

    private static func chunkedText(from text: String, optimizeForLongForm: Bool) -> [String] {
        let normalized = normalizedCaptionText(text)

        guard !normalized.isEmpty else { return [] }

        let punctuation = CharacterSet(charactersIn: ".!?;。！？；\n")
        let pieces = normalized.components(separatedBy: punctuation)
        let chunks = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !chunks.isEmpty {
            return optimizeForLongForm
                ? coalescedNarrationChunks(from: chunks, sourceText: normalized)
                : chunks
        }

        return [normalized]
    }

    private static func coalescedNarrationChunks(from chunks: [String], sourceText: String) -> [String] {
        guard chunks.count > 24 else { return chunks }

        let isCJK = containsCJKContent(in: sourceText)
        let targetUnits: Int
        let hardUnits: Int

        if isCJK {
            targetUnits = chunks.count > 80 ? 110 : 80
            hardUnits = targetUnits + 28
        } else {
            targetUnits = chunks.count > 80 ? 36 : 28
            hardUnits = targetUnits + 10
        }

        var merged: [String] = []
        var currentParts: [String] = []
        var currentUnits = 0

        func flushCurrent() {
            guard !currentParts.isEmpty else { return }
            merged.append(currentParts.joined(separator: isCJK ? " " : " "))
            currentParts.removeAll(keepingCapacity: true)
            currentUnits = 0
        }

        for chunk in chunks {
            let normalizedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedChunk.isEmpty else { continue }

            let chunkUnits: Int = {
                if isCJK {
                    return normalizedChunk.count
                } else {
                    return max(normalizedChunk.split(whereSeparator: \.isWhitespace).count, 1)
                }
            }()

            if currentParts.isEmpty {
                currentParts = [normalizedChunk]
                currentUnits = chunkUnits
                continue
            }

            let nextUnits = currentUnits + chunkUnits
            if nextUnits <= targetUnits || currentUnits < (targetUnits / 2) {
                currentParts.append(normalizedChunk)
                currentUnits = nextUnits
            } else {
                flushCurrent()
                currentParts = [normalizedChunk]
                currentUnits = chunkUnits
            }

            if currentUnits >= hardUnits {
                flushCurrent()
            }
        }

        flushCurrent()
        return merged.isEmpty ? chunks : merged
    }

    private static func normalizeSpeechText(_ text: String) -> String {
        var normalized = text

        let replacements: [(String, String)] = [
            ("U.S.", "United States"),
            ("U. S.", "United States"),
            ("U.K.", "United Kingdom"),
            ("U. K.", "United Kingdom"),
            ("U.N.", "United Nations"),
            ("U. N.", "United Nations"),
            ("E.U.", "European Union"),
            ("E. U.", "European Union"),
            ("UCLA", "U C L A"),
            ("UCSD", "U C S D"),
            ("GDP", "G D P"),
            ("AI", "A I")
        ]

        for (source, target) in replacements {
            normalized = normalized.replacingOccurrences(of: source, with: target)
        }

        return normalized
    }

    static func containsCJKContent(in text: String) -> Bool {
        text.contains { character in
            guard let scalar = character.unicodeScalars.first else { return false }
            return (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }
    }

    private static func isVoice(_ voice: AVSpeechSynthesisVoice, compatibleWithCJK expectsCJKVoice: Bool) -> Bool {
        if expectsCJKVoice {
            return voice.language.hasPrefix("zh")
                || voice.language.hasPrefix("yue")
                || voice.language.hasPrefix("ja")
                || voice.language.hasPrefix("ko")
                || voice.language.hasPrefix("wuu")
        }

        return voice.language.hasPrefix("en")
    }

    private static func collapseCaptionWhitespace(in text: String) -> String {
        let newlineFlattened = text.replacingOccurrences(of: "\n", with: " ")
        let collapsed = newlineFlattened.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let trimmedPunctuation = collapsed.replacingOccurrences(
            of: "\\s+([,.;:!?，。；：！？、])",
            with: "$1",
            options: .regularExpression
        )
        return trimmedPunctuation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func qualityLabel(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium:
            return "Premium"
        case .enhanced:
            return "Enhanced"
        default:
            return "Default"
        }
    }

    private static func qualityRank(_ label: String) -> Int {
        switch label {
        case "Premium":
            return 3
        case "Enhanced":
            return 2
        default:
            return 1
        }
    }

    private static func preferredNameRank(_ name: String) -> Int {
        let lowered = name.lowercased()
        if lowered.contains("ava") { return 100 }
        if lowered.contains("edan") || lowered.contains("evan") { return 95 }
        if lowered.contains("fung") { return 90 }
        if lowered.contains("liang") { return 85 }
        if lowered.contains("samantha") { return 80 }
        if lowered.contains("moira") { return 78 }
        if lowered.contains("daniel") { return 76 }
        if lowered.contains("ting-ting") { return 74 }
        if lowered.contains("sin-ji") { return 72 }
        if lowered.contains("mei-jia") { return 70 }
        return 0
    }

    private static func languageLabel(for code: String) -> String {
        if code.hasPrefix("wuu") {
            return "Shanghainese"
        }
        if code.hasPrefix("ja") {
            return "Japanese"
        }
        if code.hasPrefix("yue") {
            return "Cantonese"
        }
        if code.hasPrefix("zh") {
            if code.contains("Hans") || code.contains("CN") {
                return "Mandarin"
            }
            if code.contains("Hant") || code.contains("TW") {
                return "Chinese Traditional"
            }
            return "Chinese"
        }
        if code.hasPrefix("en") {
            return "English"
        }
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? code) ?? code
    }

    private static func regionLabel(for code: String) -> String {
        let locale = Locale(identifier: code)
        if let regionCode = locale.region?.identifier,
           let regionName = Locale.current.localizedString(forRegionCode: regionCode) {
            return regionName
        }
        return code
    }

    private static func speakingRate(for voice: AVSpeechSynthesisVoice?, multiplier: Double) -> Float {
        let effectiveMultiplier = effectiveSpeechRateMultiplier(for: multiplier)
        guard let voice else {
            return Float(min(max(0.42 * effectiveMultiplier, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
        }
        let baseRate: Double
        if voice.language.hasPrefix("zh") {
            baseRate = voice.quality == .premium ? 0.36 : 0.38
        } else {
            baseRate = voice.quality == .premium ? 0.40 : 0.42
        }
        let scaled = baseRate * effectiveMultiplier
        return Float(min(max(scaled, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
    }

    private static func postUtteranceDelay(for lastCharacter: Character?) -> TimeInterval {
        switch lastCharacter {
        case ",", "，", "、":
            return 0.12
        case ":", "：":
            return 0.16
        default:
            return 0.22
        }
    }

    private static var fallbackVoices: [AppViewModel.VoiceOption] {
        mapVoices(
            AVSpeechSynthesisVoice.speechVoices().filter {
                !isNoveltyVoice($0) && qualityRank(qualityLabel(for: $0)) >= 2
            },
            isFallback: true
        )
    }

    private static func mapVoices(_ voices: [AVSpeechSynthesisVoice], isFallback: Bool) -> [AppViewModel.VoiceOption] {
        voices
            .map { voice in
                AppViewModel.VoiceOption(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    languageGroup: languageGroup(for: voice.language),
                    languageLabel: languageLabel(for: voice.language),
                    regionLabel: regionLabel(for: voice.language),
                    qualityLabel: qualityLabel(for: voice),
                    sortRank: qualityRank(qualityLabel(for: voice)),
                    isFallback: isFallback
                )
            }
            .sorted { lhs, rhs in
                let lhsLanguageRank = preferredLanguageRank(lhs.language)
                let rhsLanguageRank = preferredLanguageRank(rhs.language)
                if lhsLanguageRank != rhsLanguageRank {
                    return lhsLanguageRank > rhsLanguageRank
                }
                let lhsNameRank = preferredNameRank(lhs.name)
                let rhsNameRank = preferredNameRank(rhs.name)
                if lhsNameRank != rhsNameRank {
                    return lhsNameRank > rhsNameRank
                }
                if lhs.sortRank != rhs.sortRank {
                    return lhs.sortRank > rhs.sortRank
                }
                return lhs.name < rhs.name
            }
    }

    private static func isNoveltyVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let lowered = voice.name.lowercased()
        return noveltyVoiceKeywords.contains { lowered.contains($0) }
    }

    static func preferredLanguageRank(_ language: String) -> Int {
        switch language {
        case let code where code.hasPrefix("en-US"):
            return 100
        case let code where code.hasPrefix("en-GB"):
            return 95
        case let code where code.hasPrefix("ja"):
            return 92
        case let code where code.hasPrefix("wuu"):
            return 91
        case let code where code.hasPrefix("zh-CN"):
            return 90
        case let code where code.hasPrefix("zh-HK"):
            return 85
        case let code where code.hasPrefix("zh"):
            return 80
        case let code where code.hasPrefix("yue-HK"):
            return 75
        case let code where code.hasPrefix("yue"):
            return 70
        case let code where code.hasPrefix("en"):
            return 65
        default:
            return 0
        }
    }

    private static func languageGroup(for code: String) -> String {
        if code.hasPrefix("wuu") { return "wuu" }
        if code.hasPrefix("yue") { return "yue" }
        if code.hasPrefix("zh") { return "zh" }
        if code.hasPrefix("ja") { return "ja" }
        if code.hasPrefix("en") { return "en" }
        return Locale(identifier: code).language.languageCode?.identifier ?? code
    }

    private static func preferredLanguageVoices() -> [AVSpeechSynthesisVoice] {
        ["en-US", "en-GB", "yue-HK", "zh-CN", "zh-HK"]
            .compactMap { AVSpeechSynthesisVoice(language: $0) }
            .filter { !isNoveltyVoice($0) }
    }
}

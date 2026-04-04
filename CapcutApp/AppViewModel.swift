import AVFoundation
import CryptoKit
import CoreTransferable
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
            let fileName = received.file.lastPathComponent.isEmpty
                ? "picked-movie-\(UUID().uuidString).mov"
                : received.file.lastPathComponent
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(fileName)

            let parent = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}

@MainActor
final class AppViewModel: NSObject, ObservableObject {
    private static let savedNarrationDraftKey = "fluxcut.savedNarrationDraft"
    private static let hiddenVoiceIdentifiersKey = "fluxcut.hiddenVoiceIdentifiers"

    struct MediaItem: Identifiable, Equatable {
        enum Kind: Equatable {
            case photo
            case video(url: URL, duration: Double)
        }

        let id = UUID()
        let previewImage: UIImage
        let kind: Kind

        var isVideo: Bool {
            if case .video = kind { return true }
            return false
        }
    }

    struct VoiceOption: Identifiable {
        let id: String
        let name: String
        let language: String
        let languageLabel: String
        let qualityLabel: String
        let sortRank: Int
        let isFallback: Bool

        var displayName: String {
            let fallbackSuffix = isFallback ? " • Fallback" : ""
            return "\(name) • \(qualityLabel) • \(languageLabel)\(fallbackSuffix)"
        }
    }

    struct DemoTrackOption: Identifiable {
        let id: String
        let name: String
        let description: String
        let fileName: String
        let fileExtension: String
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
            Task {
                await loadSelectedMedia(from: selectedPhotoItems)
            }
        }
    }
    @Published var currentSlideIndex = 0
    @Published var importedMusicName = "No music selected"
    @Published var isImportingMusic = false
    @Published var isLoadingMediaSelection = false
    @Published var isSpeaking = false
    @Published var isPreparingNarrationPreview = false
    @Published var isNarrationPreviewPlaying = false
    @Published var narrationPreviewDuration: Double = 0
    @Published var narrationPreviewCurrentTime: Double = 0
    @Published var narrationPreviewCaption = "Build a seekable preview to test subtitle sync."
    @Published var isMusicPlaying = false
    @Published var isExportingVideo = false
    @Published var isPreparingVideoPreview = false
    @Published var exportProgress: Double = 0
    @Published var exportedVideoURL: URL?
    @Published var videoPreviewURL: URL?
    @Published var availableVoices: [VoiceOption] = []
    @Published var selectedVoiceIdentifier = "" {
        didSet {
            selectedVoiceName = selectedVoiceDisplayName
            if oldValue != selectedVoiceIdentifier {
                stopLiveNarrationPlayback(reason: "Voice updated. Tap Play Script to hear the new selection.")
                markAllVideoRendersDirty(reason: "Voice updated. Build a new preview or final render to hear the change.")
                invalidateNarrationPreviewIfNeeded()
            }
        }
    }
    @Published var selectedVoiceName = "No Apple voice selected yet."
    @Published var clipboardPreview = "Clipboard not checked yet."
    @Published var demoTracks: [DemoTrackOption] = [
        DemoTrackOption(id: "dream_culture", name: "Dream Culture", description: "Calming, relaxed, uplifting ambience", fileName: "dream_culture", fileExtension: "mp3"),
        DemoTrackOption(id: "local_forecast", name: "Local Forecast", description: "Bright, grooving, feel-good energy", fileName: "local_forecast", fileExtension: "mp3")
    ]
    @Published var selectedDemoTrackID = "dream_culture"
    @Published var selectedAspectRatio: VideoExporter.AspectRatio = .vertical {
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

    private let videoExporter = VideoExporter()
    private let narrationPreviewBuilder = NarrationPreviewBuilder()
    private var audioPlayer: AVAudioPlayer?
    private var narrationPreviewPlayer: AVAudioPlayer?
    private var narrationPreviewTimer: Timer?
    private var importedMusicURL: URL?
    private var narrationPreviewAudioURL: URL?
    private var narrationPreviewCues: [NarrationPreviewBuilder.SubtitleCue] = []
    private var narrationTimelineEngine = SubtitleTimelineEngine(cues: [])
    private var previewSourceText = ""
    private var previewSourceVoiceIdentifier = ""
    private var narrationPreviewIsFullLength = false
    private var pendingUtteranceCount = 0
    private var didLoadFullVoiceList = false
    private var shouldPersistNarrationDraft = true
    private var hiddenVoiceIdentifiers: Set<String> = []
    private var allAvailableVoices: [VoiceOption] = []
    private var speechSynthesizer = AVSpeechSynthesizer()
    private var didConfigureAudioSession = false

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
            ? "No iPhone voices loaded yet"
            : "\(availableVoices.count) iPhone voices ready"
        if let firstVoice = availableVoices.first {
            selectedVoiceIdentifier = firstVoice.id
            selectedVoiceName = firstVoice.displayName
        }
    }

    func playNarration() {
        guard !narrationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "Add some narration text before starting text-to-speech."
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
            voiceIdentifier: activeVoiceIdentifier
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

        let voiceIdentifier = selectedVoiceIdentifier

        Task {
            do {
                try await prepareNarrationPreview(
                    text: text,
                    voiceIdentifier: voiceIdentifier,
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
            await importMusicAsset(from: selectedURL)
        }
    }

    func importMusicVideo(from item: PhotosPickerItem) async {
        configureAudioSessionIfNeeded()
        guard let pickedURL = await importedVideoURL(from: item) else {
            statusMessage = "Could not load that video from Photos."
            return
        }

        await importMusicAsset(from: pickedURL, shouldManageSecurityScope: false)
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
        audioPlayer = nil
        importedMusicURL = nil
        importedMusicName = "No music selected"
        isImportingMusic = false
        hasPendingPreviewChanges = true
        hasPendingFinalVideoChanges = true
        statusMessage = "Music cleared. Your video will export without background music."
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
            isMusicPlaying = false
            statusMessage = "Background music paused."
        } else {
            audioPlayer.play()
            isMusicPlaying = true
            statusMessage = "Background music playing."
        }
    }

    func stopMusic() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isMusicPlaying = false
        statusMessage = "Background music stopped."
    }

    func stopMusicSilently() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isMusicPlaying = false
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
        selectedPhotoItems = []
        mediaItems = []
        currentSlideIndex = 0
        hasPendingPreviewChanges = true
        hasPendingFinalVideoChanges = true
        statusMessage = "Media cleared. Import a new set whenever you're ready."
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

        let exportMediaItems = mediaItems.map { item in
            let exportKind: VideoExporter.MediaItem.Kind

            switch item.kind {
            case .photo:
                exportKind = .photo
            case let .video(url, duration):
                exportKind = .video(url: url, duration: CMTime(seconds: duration, preferredTimescale: 600))
            }

            return VideoExporter.MediaItem(
                previewImage: item.previewImage,
                kind: exportKind
            )
        }
        let narrationText = normalizedNarrationSourceText
        let backgroundMusicURL = importedMusicURL
        let backgroundMusicVolume = musicVolume
        let narrationVolume = narrationVolume
        let videoAudioVolume = videoAudioVolume
        let voiceIdentifier = selectedVoiceIdentifier
        let exporter = videoExporter
        let aspectRatio = selectedAspectRatio
        let timingMode = selectedTimingMode
        let includeCaptions = renderQuality == .preview ? false : includesFinalCaptions

        Task {
            do {
                let shouldPrepareNarration = timingMode != .video && !narrationText.isEmpty
                let requiresFullNarrationPreview = renderQuality != .preview && timingMode != .video
                if shouldPrepareNarration, needsPreviewRefresh(
                    for: narrationText,
                    voiceIdentifier: voiceIdentifier,
                    requireFullLength: requiresFullNarrationPreview
                ) {
                    exportProgress = 0.08
                    try await prepareNarrationPreview(
                        text: narrationText,
                        voiceIdentifier: voiceIdentifier,
                        maximumDuration: requiresFullNarrationPreview ? nil : (renderQuality == .preview ? 180 : nil),
                        startedMessage: renderQuality == .preview
                            ? "Preparing narration and captions for the quick preview."
                            : "Preparing narration and captions for video export.",
                        completedMessage: renderQuality == .preview
                            ? "Preview narration is ready. Building a short sample render now."
                            : "Narration and captions are ready. Rendering your video now."
                    )
                } else {
                    exportProgress = 0.22
                    statusMessage = renderQuality == .preview
                        ? "Building a short preview render."
                        : "Rendering your video. This can take a moment."
                }

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
            availableVoices = filteredVoices(from: allAvailableVoices)
            if availableVoices.isEmpty {
                availableVoices = allAvailableVoices
            }
            reconcileSelectedVoice()
            voiceReloadFeedback = "\(availableVoices.count) iPhone voices loaded"
            statusMessage = "Voice list refreshed."
        } else {
            let restoredFallbackVoices = SpeechVoiceLibrary.voiceOptions
            if !restoredFallbackVoices.isEmpty {
                objectWillChange.send()
                allAvailableVoices = restoredFallbackVoices
                availableVoices = filteredVoices(from: allAvailableVoices)
                if availableVoices.isEmpty {
                    availableVoices = allAvailableVoices
                }
                reconcileSelectedVoice()
                voiceReloadFeedback = "\(availableVoices.count) iPhone voices loaded"
                statusMessage = "Voice list refreshed."
            } else {
                voiceReloadFeedback = "No iPhone voices found"
                statusMessage = "No Apple voices were available from the speech framework on this device."
            }
        }
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
        availableVoices = filteredVoices(from: allAvailableVoices)

        if availableVoices.isEmpty {
            hiddenVoiceIdentifiers.remove(voiceID)
            saveHiddenVoiceIdentifiers()
            availableVoices = filteredVoices(from: allAvailableVoices)
        }

        reconcileSelectedVoice()
        invalidateNarrationPreviewIfNeeded()
        voiceReloadFeedback = "\(availableVoices.count) iPhone voices shown"
        statusMessage = "Voice removed from this list. Tap Reload iPhone Voices to bring everything back."
    }

    private func loadSelectedMedia(from pickerItems: [PhotosPickerItem]) async {
        isLoadingMediaSelection = true
        defer {
            isLoadingMediaSelection = false
        }

        guard !pickerItems.isEmpty else {
            mediaItems = []
            currentSlideIndex = 0
            statusMessage = "Media cleared. Pick new photos or videos to continue."
            return
        }

        var loadedMedia: [MediaItem] = []

        for item in pickerItems {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
                if let videoURL = await importedVideoURL(from: item),
                   let previewImage = await makeVideoThumbnail(for: videoURL) {
                    let duration = await videoDuration(for: videoURL)
                    loadedMedia.append(
                        MediaItem(
                            previewImage: previewImage,
                            kind: .video(url: videoURL, duration: duration)
                        )
                    )
                }
            } else if let data = try? await item.loadTransferable(type: Data.self),
                      let image = downsampledImage(from: data, maxDimension: 1280) {
                loadedMedia.append(MediaItem(previewImage: image.normalizedOrientationImage(), kind: .photo))
            }
        }

        mediaItems = loadedMedia
        currentSlideIndex = 0
        hasPendingPreviewChanges = true
        hasPendingFinalVideoChanges = true
        statusMessage = loadedMedia.isEmpty
            ? "No valid photos or videos were selected."
            : "\(loadedMedia.count) media item(s) ready for your project."
    }

    private func importedVideoURL(from item: PhotosPickerItem) async -> URL? {
        if let pickedMovie = try? await item.loadTransferable(type: PickedMovie.self),
           let copiedURL = try? copyImportedFileToDocuments(pickedMovie.url) {
            return copiedURL
        }

        if let pickedURL = try? await item.loadTransferable(type: URL.self),
           let copiedURL = try? copyImportedFileToDocuments(pickedURL) {
            return copiedURL
        }

        guard let videoData = try? await item.loadTransferable(type: Data.self) else {
            return nil
        }

        let videoType = item.supportedContentTypes.first(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) })
        let preferredExtension = videoType?.preferredFilenameExtension ?? "mov"
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destination = documents.appendingPathComponent("picked-video-\(UUID().uuidString).\(preferredExtension)")

        do {
            try videoData.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    private var normalizedNarrationSourceText: String {
        narrationText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func needsPreviewRefresh(for text: String, voiceIdentifier: String, requireFullLength: Bool = false) -> Bool {
        narrationPreviewAudioURL == nil
            || narrationPreviewCues.isEmpty
            || previewSourceText != text
            || previewSourceVoiceIdentifier != voiceIdentifier
            || (requireFullLength && !narrationPreviewIsFullLength)
    }

    private func prepareNarrationPreview(
        text: String,
        voiceIdentifier: String,
        maximumDuration: TimeInterval? = nil,
        startedMessage: String,
        completedMessage: String
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
            maximumDuration: maximumDuration
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
                generator.maximumSize = CGSize(width: 1280, height: 1280)
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

    private func copyImportedFileToDocuments(_ sourceURL: URL) throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileExtension = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let safeName = baseName.isEmpty ? "imported-audio" : baseName
        let destination = documents.appendingPathComponent("\(safeName)-\(UUID().uuidString).\(fileExtension)")

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            let data = try Data(contentsOf: sourceURL)
            try data.write(to: destination, options: .atomic)
        }
        return destination
    }

    private func importMusicAsset(from selectedURL: URL, shouldManageSecurityScope: Bool = true) async {
        isImportingMusic = true
        statusMessage = "Importing soundtrack..."
        defer {
            isImportingMusic = false
        }

        do {
            stopMusicSilently()
            let canAccess = shouldManageSecurityScope ? selectedURL.startAccessingSecurityScopedResource() : false
            defer {
                if canAccess {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }

            let imported = try await prepareImportedMusicAsset(from: selectedURL)
            importedMusicURL = imported.url
            importedMusicName = imported.displayName
            try prepareAudioPlayer(with: imported.url)
            hasPendingPreviewChanges = true
            hasPendingFinalVideoChanges = true
            statusMessage = imported.wasExtractedFromVideo
                ? "Video soundtrack extracted and ready to play."
                : "Music imported and ready to play."
        } catch {
            statusMessage = error.localizedDescription.isEmpty ? "Could not import that music file." : error.localizedDescription
        }
    }

    private func prepareImportedMusicAsset(from sourceURL: URL) async throws -> (url: URL, displayName: String, wasExtractedFromVideo: Bool) {
        let sourceType = importedMediaType(for: sourceURL)
        switch sourceType {
        case .audio:
            let destination = try copyImportedFileToDocuments(sourceURL)
            return (destination, destination.lastPathComponent, false)
        case .video:
            let extractedURL = try await extractAudioTrackIfNeeded(from: sourceURL)
            return (extractedURL, extractedURL.lastPathComponent, true)
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

    private func importedMediaType(for url: URL) -> ImportedMediaType {
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

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: exportSession.error ?? NSError(
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
        isMusicPlaying = false
    }

    var hasSelectedMusic: Bool {
        importedMusicURL != nil
    }

    var shareableMusicURL: URL? {
        importedMusicURL
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
        if let cue = narrationTimelineEngine.cue(at: time) {
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

    var estimatedExportSpecLine: String {
        let exporterMediaItems = mediaItems.map { item in
            let kind: VideoExporter.MediaItem.Kind
            switch item.kind {
            case .photo:
                kind = .photo
            case let .video(url, duration):
                kind = .video(url: url, duration: CMTime(seconds: duration, preferredTimescale: 600))
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
            timingMode: selectedTimingMode
        )
    }

    var mediaSelectionMetaLine: String {
        guard !mediaItems.isEmpty else { return "No media selected yet." }

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
            case let .video(_, duration):
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
            && hasRenderableMediaForSelectedMode
            && !isExportingVideo
            && !isPreparingVideoPreview
            && !isPreparingNarrationPreview
            && hasPendingPreviewChanges
    }

    var canStartFinalVideoRender: Bool {
        !isLoadingMediaSelection
            && hasRenderableMediaForSelectedMode
            && !isExportingVideo
            && !isPreparingVideoPreview
            && !isPreparingNarrationPreview
            && hasPendingFinalVideoChanges
    }

    var hasNarrationPreview: Bool {
        !isPreparingNarrationPreview
            && narrationPreviewDuration > 0
            && !narrationPreviewCues.isEmpty
            && previewSourceText == normalizedNarrationSourceText
            && previewSourceVoiceIdentifier == selectedVoiceIdentifier
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
        return max(segments.reduce(0.0) { partial, segment in
            let timingText = SpeechVoiceLibrary.normalizedTimingText(segment)
            if SpeechVoiceLibrary.containsCJKContent(in: timingText) {
                return partial + max(Double(timingText.count) / 3.6, 0.8)
            }
            let words = timingText.split(whereSeparator: \.isWhitespace)
            return partial + max(Double(words.count) / 2.4, 0.8)
        }, 1)
    }

    private var estimatedMediaOnlyDurationSeconds: Double {
        guard !mediaItems.isEmpty else { return 0 }

        let totalVideoSeconds = mediaItems.reduce(0.0) { partial, item in
            switch item.kind {
            case .photo:
                return partial
            case let .video(_, duration):
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
            case let .video(_, duration):
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
            return estimatedMediaOnlyDurationSeconds
        case .story:
            return estimatedNarrationDurationSeconds > 0 ? estimatedNarrationDurationSeconds : estimatedMediaOnlyDurationSeconds
        }
    }

    private var hasRenderableMediaForSelectedMode: Bool {
        switch selectedTimingMode {
        case .video:
            return mediaItems.contains(where: \.isVideo)
        case .story, .realLife:
            return !mediaItems.isEmpty
        }
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

    private func reconcileSelectedVoice() {
        if !availableVoices.contains(where: { $0.id == selectedVoiceIdentifier }) {
            selectedVoiceIdentifier = availableVoices.first?.id ?? ""
        } else {
            selectedVoiceName = selectedVoiceDisplayName
        }
    }

    private func selectLanguageCompatibleVoiceIfNeeded(for text: String) {
        guard !availableVoices.isEmpty else { return }

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

    private static func voiceOption(_ option: VoiceOption, isCompatibleWithCJK expectsCJKVoice: Bool) -> Bool {
        if expectsCJKVoice {
            return option.language.hasPrefix("zh") || option.language.hasPrefix("yue")
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
    private static let supportedPrefixes = ["en", "zh", "yue"]
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
        let fallback = fallbackVoices
        if !fallback.isEmpty {
            return fallback
        }
        return staticFallbackVoices
    }

    static var preferredEnhancedPremiumVoices: [AppViewModel.VoiceOption] {
        mapVoices(
            AVSpeechSynthesisVoice.speechVoices().filter {
                isSupportedLanguage($0.language) &&
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
        return staticFallbackVoices
    }

    static func voice(for identifier: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: identifier)
            ?? AVSpeechSynthesisVoice(language: identifier)
            ?? defaultVoice
    }

    static func makeUtterances(from text: String, voiceIdentifier: String, optimizeForLongForm: Bool = false) -> [AVSpeechUtterance] {
        narrationSegments(from: text, optimizeForLongForm: optimizeForLongForm).map {
            makeUtterance(from: $0, voiceIdentifier: voiceIdentifier)
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

    static func makeUtterance(from text: String, voiceIdentifier: String) -> AVSpeechUtterance {
        let selectedVoice = resolvedVoice(for: text, preferredIdentifier: voiceIdentifier)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = speakingRate(for: selectedVoice)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.02
        utterance.postUtteranceDelay = postUtteranceDelay(for: text.last)
        return utterance
    }

    private static var defaultVoice: AVSpeechSynthesisVoice? {
        if let preferredLanguageVoice = preferredLanguageVoices().first {
            return preferredLanguageVoice
        }

        let preferredVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            isSupportedLanguage($0.language) &&
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
            isSupportedLanguage($0.language) && !isNoveltyVoice($0)
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

        let firstFallbackIdentifier = staticFallbackVoices.first?.id ?? "en-US"
        return AVSpeechSynthesisVoice(language: firstFallbackIdentifier)
    }

    private static func resolvedVoice(for text: String, preferredIdentifier: String) -> AVSpeechSynthesisVoice? {
        let preferredVoice = voice(for: preferredIdentifier)
        let expectsCJKVoice = containsCJKContent(in: text)

        if let preferredVoice, isVoice(preferredVoice, compatibleWithCJK: expectsCJKVoice) {
            return preferredVoice
        }

        let candidateVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            isSupportedLanguage($0.language) &&
            !isNoveltyVoice($0) &&
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
            return voice.language.hasPrefix("zh") || voice.language.hasPrefix("yue")
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
        return code
    }

    private static func speakingRate(for voice: AVSpeechSynthesisVoice?) -> Float {
        guard let voice else { return 0.42 }
        if voice.language.hasPrefix("zh") {
            return voice.quality == .premium ? 0.36 : 0.38
        }
        return voice.quality == .premium ? 0.40 : 0.42
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
                isSupportedLanguage($0.language) && !isNoveltyVoice($0)
            },
            isFallback: true
        )
    }

    private static var staticFallbackVoices: [AppViewModel.VoiceOption] {
        [
            AppViewModel.VoiceOption(
                id: "en-US",
                name: "English (US)",
                language: "en-US",
                languageLabel: "English",
                qualityLabel: "Default",
                sortRank: 1,
                isFallback: true
            ),
            AppViewModel.VoiceOption(
                id: "yue-HK",
                name: "Cantonese (Hong Kong)",
                language: "yue-HK",
                languageLabel: "Cantonese",
                qualityLabel: "Default",
                sortRank: 1,
                isFallback: true
            ),
            AppViewModel.VoiceOption(
                id: "zh-CN",
                name: "Mandarin (Simplified)",
                language: "zh-CN",
                languageLabel: "Mandarin",
                qualityLabel: "Default",
                sortRank: 1,
                isFallback: true
            )
        ]
    }

    private static func mapVoices(_ voices: [AVSpeechSynthesisVoice], isFallback: Bool) -> [AppViewModel.VoiceOption] {
        voices
            .map { voice in
                AppViewModel.VoiceOption(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    languageLabel: languageLabel(for: voice.language),
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

    private static func isSupportedLanguage(_ language: String) -> Bool {
        supportedPrefixes.contains { language.hasPrefix($0) }
    }

    private static func isNoveltyVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let lowered = voice.name.lowercased()
        return noveltyVoiceKeywords.contains { lowered.contains($0) }
    }

    private static func preferredLanguageRank(_ language: String) -> Int {
        switch language {
        case let code where code.hasPrefix("en-US"):
            return 100
        case let code where code.hasPrefix("en-GB"):
            return 95
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

    private static func preferredLanguageVoices() -> [AVSpeechSynthesisVoice] {
        ["en-US", "en-GB", "yue-HK", "zh-CN", "zh-HK"]
            .compactMap { AVSpeechSynthesisVoice(language: $0) }
            .filter { !isNoveltyVoice($0) }
    }
}

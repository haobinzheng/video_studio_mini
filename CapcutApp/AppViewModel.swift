import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class AppViewModel: NSObject, ObservableObject {
    struct PhotoItem: Identifiable, Equatable {
        let id = UUID()
        let image: UIImage
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
    }

    @Published var photos: [PhotoItem] = []
    @Published var narrationText = "Welcome to my CapCut-style video. Add your own script here."
    @Published var selectedPhotoItems: [PhotosPickerItem] = [] {
        didSet {
            Task {
                await loadSelectedPhotos(from: selectedPhotoItems)
            }
        }
    }
    @Published var currentSlideIndex = 0
    @Published var importedMusicName = "No music selected"
    @Published var isSpeaking = false
    @Published var isMusicPlaying = false
    @Published var isExportingVideo = false
    @Published var exportedVideoURL: URL?
    var availableVoices: [VoiceOption] = []
    @Published var selectedVoiceIdentifier = "" {
        didSet {
            selectedVoiceName = selectedVoiceDisplayName
        }
    }
    @Published var selectedVoiceName = "No Apple voice selected yet."
    @Published var clipboardPreview = "Clipboard not checked yet."
    @Published var demoTracks: [DemoTrackOption] = [
        DemoTrackOption(id: "calm_breeze", name: "Calm Breeze", description: "Airy ambient pad with chimes", fileName: "calm_breeze"),
        DemoTrackOption(id: "city_pop", name: "City Pop", description: "Clean upbeat synth groove", fileName: "city_pop"),
        DemoTrackOption(id: "piano_moment", name: "Piano Moment", description: "Gentle piano with soft echo", fileName: "piano_moment")
    ]
    @Published var selectedDemoTrackID = "calm_breeze"
    @Published var musicVolume: Double = 0.6 {
        didSet {
            audioPlayer?.volume = Float(musicVolume)
        }
    }
    @Published var statusMessage = "Pick photos, add a script, and import music to build your clip."

    private let videoExporter = VideoExporter()
    private var audioPlayer: AVAudioPlayer?
    private var importedMusicURL: URL?
    private var pendingUtteranceCount = 0
    private var didLoadFullVoiceList = false
    private lazy var speechSynthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()
    private var didConfigureAudioSession = false

    override init() {
        super.init()
        availableVoices = SpeechVoiceLibrary.initialVoiceOptions
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

        configureAudioSessionIfNeeded()

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            pendingUtteranceCount = 0
            statusMessage = "Narration stopped."
            return
        }

        let utterances = SpeechVoiceLibrary.makeUtterances(
            from: narrationText,
            voiceIdentifier: selectedVoiceIdentifier
        )
        guard !utterances.isEmpty else {
            statusMessage = "Add some narration text before starting text-to-speech."
            return
        }

        pendingUtteranceCount = utterances.count
        for utterance in utterances {
            speechSynthesizer.speak(utterance)
        }
        isSpeaking = true
        statusMessage = "Narration is playing with \(selectedVoiceDisplayName)."
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
        narrationText = ""
        statusMessage = "Narration text cleared."
    }

    func loadSampleNarration() {
        narrationText = """
        Welcome to my photo story. These images capture a few favorite moments, and this short voiceover helps turn them into a simple video draft. You can replace this sample with your own script any time.
        """
        statusMessage = "Sample narration loaded."
    }

    func importMusic(from selectedURL: URL) {
        configureAudioSessionIfNeeded()

        let canAccess = selectedURL.startAccessingSecurityScopedResource()
        defer {
            if canAccess {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let destination = try copyImportedFileToDocuments(selectedURL)
            importedMusicURL = destination
            importedMusicName = destination.lastPathComponent
            try prepareAudioPlayer(with: destination)
            statusMessage = "Music imported and ready to play."
        } catch {
            statusMessage = "Could not import that music file."
        }
    }

    func loadSelectedBundledMusic() {
        configureAudioSessionIfNeeded()

        guard let track = demoTracks.first(where: { $0.id == selectedDemoTrackID }) else {
            statusMessage = "Sample track not found."
            return
        }

        let bundledURL = Bundle.main.url(forResource: track.fileName, withExtension: "wav", subdirectory: "SampleMusic")
            ?? Bundle.main.url(forResource: track.fileName, withExtension: "wav")

        guard let bundledURL else {
            statusMessage = "Bundled sample music is missing from the app."
            return
        }

        do {
            importedMusicURL = bundledURL
            importedMusicName = "\(track.name).wav"
            try prepareAudioPlayer(with: bundledURL)
            statusMessage = "\(track.name) is ready to play."
        } catch {
            statusMessage = "Could not load bundled sample music."
        }
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

    func nextSlide() {
        guard !photos.isEmpty else { return }
        currentSlideIndex = (currentSlideIndex + 1) % photos.count
    }

    func previousSlide() {
        guard !photos.isEmpty else { return }
        currentSlideIndex = (currentSlideIndex - 1 + photos.count) % photos.count
    }

    func buildVideo() {
        guard !photos.isEmpty else {
            statusMessage = "Pick photos before creating a video."
            return
        }

        isExportingVideo = true
        exportedVideoURL = nil
        statusMessage = "Rendering your video. This can take a moment."

        let images = photos.map(\.image)
        let narrationText = narrationText
        let backgroundMusicURL = importedMusicURL

        Task {
            do {
                let exportedURL = try await videoExporter.exportVideo(
                    images: images,
                    narrationText: narrationText,
                    backgroundMusicURL: backgroundMusicURL,
                    voiceIdentifier: selectedVoiceIdentifier
                )
                exportedVideoURL = exportedURL
                statusMessage = "Video created successfully. Preview or share it below."
            } catch {
                statusMessage = error.localizedDescription.isEmpty ? "Video export failed." : error.localizedDescription
            }

            isExportingVideo = false
        }
    }

    func loadAvailableVoicesIfNeeded() {
        guard !didLoadFullVoiceList else { return }
        didLoadFullVoiceList = true

        let loadedVoices = SpeechVoiceLibrary.voiceOptions
        if !loadedVoices.isEmpty {
            objectWillChange.send()
            availableVoices = loadedVoices
            if !availableVoices.contains(where: { $0.id == selectedVoiceIdentifier }) {
                selectedVoiceIdentifier = availableVoices.first?.id ?? ""
            } else {
                selectedVoiceName = selectedVoiceDisplayName
            }
        } else {
            statusMessage = "No Apple voices were available from the speech framework on this device."
        }
    }

    private func loadSelectedPhotos(from pickerItems: [PhotosPickerItem]) async {
        guard !pickerItems.isEmpty else {
            photos = []
            currentSlideIndex = 0
            statusMessage = "Photos cleared. Pick new photos to continue."
            return
        }

        var loadedPhotos: [PhotoItem] = []

        for item in pickerItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loadedPhotos.append(PhotoItem(image: image.normalizedOrientationImage()))
            }
        }

        photos = loadedPhotos
        currentSlideIndex = 0
        statusMessage = loadedPhotos.isEmpty
            ? "No valid photos were selected."
            : "\(loadedPhotos.count) photo(s) ready for your project."
    }

    private func configureAudioSessionIfNeeded() {
        guard !didConfigureAudioSession else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            didConfigureAudioSession = true
        } catch {
            statusMessage = "Audio session setup failed."
        }
    }

    private func copyImportedFileToDocuments(_ sourceURL: URL) throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destination = documents.appendingPathComponent(sourceURL.lastPathComponent)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private func prepareAudioPlayer(with url: URL) throws {
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.delegate = self
        audioPlayer?.numberOfLoops = -1
        audioPlayer?.volume = Float(musicVolume)
        audioPlayer?.prepareToPlay()
        isMusicPlaying = false
    }

    var selectedVoiceDisplayName: String {
        availableVoices.first(where: { $0.id == selectedVoiceIdentifier })?.displayName ?? "No Apple voice selected yet."
    }
}

extension AppViewModel: @preconcurrency AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isMusicPlaying = false
        }
    }
}

extension AppViewModel: @preconcurrency AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
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

    static func makeUtterances(from text: String, voiceIdentifier: String) -> [AVSpeechUtterance] {
        narrationSegments(from: text).map { makeUtterance(from: $0, voiceIdentifier: voiceIdentifier) }
    }

    static func narrationSegments(from text: String) -> [String] {
        chunkedText(from: text)
    }

    static func makeUtterance(from text: String, voiceIdentifier: String) -> AVSpeechUtterance {
        let selectedVoice = voice(for: voiceIdentifier)
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

    private static func chunkedText(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        let punctuation = CharacterSet(charactersIn: ".!?;。！？；\n")
        let pieces = normalized.components(separatedBy: punctuation)
        let chunks = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !chunks.isEmpty {
            return chunks
        }

        return [normalized]
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
                let lhsNameRank = preferredNameRank(lhs.name)
                let rhsNameRank = preferredNameRank(rhs.name)
                if lhsNameRank != rhsNameRank {
                    return lhsNameRank > rhsNameRank
                }
                let lhsLanguageRank = preferredLanguageRank(lhs.language)
                let rhsLanguageRank = preferredLanguageRank(rhs.language)
                if lhsLanguageRank != rhsLanguageRank {
                    return lhsLanguageRank > rhsLanguageRank
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
        case let code where code.hasPrefix("yue-HK"):
            return 90
        case let code where code.hasPrefix("zh-CN"):
            return 85
        case let code where code.hasPrefix("zh-HK"):
            return 80
        case let code where code.hasPrefix("zh"):
            return 75
        case let code where code.hasPrefix("en"):
            return 70
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

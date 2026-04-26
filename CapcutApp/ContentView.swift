import AVKit
import Combine
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Settings (Terms of Use; Privacy Policy and Feedback are in-app screens)
private enum AppSettingsLinks {
    /// Standard Apple Terms (replace with your own Terms of Use URL if you publish custom terms).
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

struct ContentView: View {
    private struct ShareableFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    enum StudioStep: String, CaseIterable, Identifiable {
        case narration = "Script"
        case photos = "Media"
        case music = "Music"
        case editStory = "Pro"
        case video = "Video"

        var id: String { rawValue }
    }

    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var proIAP: ProEntitlementManager
    @State private var isMusicLibraryImporterPresented = false
    @State private var selectedMusicVideoItem: PhotosPickerItem?
    @State private var extractedSoundtrackShareFile: ShareableFile?
    @State private var selectedStep: StudioStep = .narration
    @State private var draggedMediaItem: AppViewModel.MediaItem?
    @State private var draggedSoundtrackItem: AppViewModel.SoundtrackItem?
    @State private var appendPhotoItems: [PhotosPickerItem] = []
    @State private var renderPreviewPlayer = AVPlayer()
    @State private var scriptScrollProxy: ScrollViewProxy?
    @State private var isSettingsPresented = false
    @State private var isMusicBrowserPresented = false
    @State private var isRenderPlayerExpanded = false
    @State private var voicePendingHide: AppViewModel.VoiceOption?
    @State private var musicLibrarySearchText = ""
    @State private var pendingMusicLibraryDeletion: AppViewModel.MusicLibraryItem?
    @State private var pendingMediaDeletion: AppViewModel.MediaItem?
    @State private var selectedMusicLibraryItemIDs: Set<String> = []
    @State private var previewingMusicLibraryItemID: String?
    @State private var isNarrationPreviewSectionVisible = false
    @State private var selectedStoryParagraphIndices: Set<Int> = []
    @State private var isStoryBlockAssignSheetPresented = false
    @State private var assignSheetRange: ClosedRange<Int>?
    @State private var assignSheetDraftMediaIDs: [UUID] = []
    @State private var assignSheetSlideIndex = 0
    @State private var assignSheetBlockOrdinal = 1
    @State private var draggedAssignSheetMediaID: UUID?
    @State private var selectedMusicStoryParagraphIndices: Set<Int> = []
    @State private var isStoryMusicAssignSheetPresented = false
    @State private var musicAssignSheetRange: ClosedRange<Int>?
    @State private var musicAssignSheetSegmentOrdinal = 1
    @State private var musicAssignDraftChoice: AppViewModel.MusicSegmentSoundtrackChoice?
    /// Paragraphs the user selected for this music assign (passed through on Done).
    @State private var musicAssignUserParagraphRange: ClosedRange<Int>?
    @State private var storyMusicAssignBlockingMessage: String?

    private enum EditStoryEditorTab: String, CaseIterable {
        case media = "Media"
        case music = "Music"
    }

    @State private var editStoryEditorTab: EditStoryEditorTab = .media
    /// Persists Edit → Script paragraphs “How assigning works” disclosure (Media / Music share one expansion state).
    @AppStorage("fluxcut.editStoryHelpExpanded") private var editStoryHelpExpanded = false
    @FocusState private var isNarrationFocused: Bool

    private var assignSheetBlockScriptText: String {
        guard let range = assignSheetRange else { return "" }
        let paras = viewModel.storyScriptParagraphs
        guard !paras.isEmpty,
              range.lowerBound >= 0,
              range.upperBound < paras.count else { return "" }
        return paras[range.lowerBound...range.upperBound].joined(separator: "\n\n")
    }

    private var musicAssignSheetScriptText: String {
        guard let range = musicAssignSheetRange else { return "" }
        let paras = viewModel.storyScriptParagraphs
        guard !paras.isEmpty,
              range.lowerBound >= 0,
              range.upperBound < paras.count else { return "" }
        return paras[range.lowerBound...range.upperBound].joined(separator: "\n\n")
    }

    private var visibleStudioSteps: [StudioStep] {
        StudioStep.allCases
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    brandHeader
                    stepPicker
                }
                .padding(20)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture {
                    isNarrationFocused = false
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            activeSection
                            statusSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .background {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    isNarrationFocused = false
                                }
                        }
                    }
                    .scrollDismissesKeyboard(.automatic)
                    .onAppear {
                        scriptScrollProxy = proxy
                    }
                }
            }
            .background(appBackground)
            .onAppear { viewModel.reconcileProWatermarkGate() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isSettingsPresented) {
                settingsSheet
            }
            .sheet(isPresented: $isMusicBrowserPresented) {
                musicLibrarySheet
            }
            .fullScreenCover(isPresented: $isRenderPlayerExpanded) {
                expandedRenderPlayerView
            }
            .fullScreenCover(isPresented: $isStoryBlockAssignSheetPresented) {
                storyBlockAssignSheet
            }
            .fullScreenCover(isPresented: $isStoryMusicAssignSheetPresented) {
                storyMusicAssignSheet
            }
            .alert("Cannot assign music", isPresented: Binding(
                get: { storyMusicAssignBlockingMessage != nil },
                set: { if !$0 { storyMusicAssignBlockingMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    storyMusicAssignBlockingMessage = nil
                }
            } message: {
                Text(storyMusicAssignBlockingMessage ?? "")
            }
            .confirmationDialog(
                "Hide Voice?",
                isPresented: Binding(
                    get: { voicePendingHide != nil },
                    set: { if !$0 { voicePendingHide = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Hide", role: .destructive) {
                    if let voice = voicePendingHide {
                        viewModel.hideVoice(withId: voice.id)
                    }
                    voicePendingHide = nil
                }
                Button("Cancel", role: .cancel) {
                    voicePendingHide = nil
                }
            } message: {
                if let voice = voicePendingHide {
                    Text("\(voice.name) will be removed from the narration voice list. Reload iPhone Voices will bring it back.")
                }
            }
            .alert(item: $pendingMediaDeletion) { item in
                Alert(
                    title: Text("Delete Media?"),
                    message: Text("This removes \(viewModel.mediaDisplayLabel(for: item.id)) from the current project."),
                    primaryButton: .destructive(Text("Delete")) {
                        viewModel.removeMediaItem(withId: item.id)
                    },
                    secondaryButton: .cancel()
                )
            }
            .onChange(of: selectedMusicVideoItem) { _, newValue in
                guard let newValue else { return }
                let picked = newValue
                selectedMusicVideoItem = nil
                Task { @MainActor in
                    if let url = await viewModel.extractSoundtrackForExport(from: picked) {
                        extractedSoundtrackShareFile = ShareableFile(url: url)
                    }
                }
            }
            .onChange(of: selectedStep) { oldStep, newStep in
                if oldStep == .narration && newStep != .narration {
                    viewModel.stopLiveNarrationSilently()
                    viewModel.stopNarrationPreview()
                }
                if oldStep == .music && newStep != .music {
                    viewModel.stopMusicSilently()
                }
                if oldStep == .editStory && newStep != .editStory {
                    viewModel.stopMusicSilently()
                    selectedMusicStoryParagraphIndices = []
                    resetStoryMusicAssignSheetState()
                    isStoryMusicAssignSheetPresented = false
                }
                if oldStep == .video && newStep != .video {
                    pauseRenderPlaybackForTabSwitch()
                }
                if newStep == .video {
                    updateRenderPreviewPlayer(for: activeRenderedVideoURL)
                }
                if newStep == .narration {
                    viewModel.ensureNarrationVoiceSelectedForScriptTab()
                }
            }
            .onChange(of: viewModel.videoPreviewURL) { _, _ in
                updateRenderPreviewPlayer(for: activeRenderedVideoURL)
            }
            .onChange(of: viewModel.exportedVideoURL) { _, _ in
                updateRenderPreviewPlayer(for: activeRenderedVideoURL)
            }
            .onChange(of: viewModel.hasPendingFinalVideoChanges) { _, _ in
                updateRenderPreviewPlayer(for: activeRenderedVideoURL)
            }
            .onChange(of: viewModel.isPreparingVideoPreview) { _, isPreparing in
                if isPreparing {
                    deactivateRenderPlaybackForNewRender()
                } else {
                    // Preview finished or was never started; restore last good URL (e.g. after cancelling a preview rebuild).
                    updateRenderPreviewPlayer(for: activeRenderedVideoURL)
                }
            }
            .onChange(of: viewModel.isExportingVideo) { _, isExporting in
                if isExporting {
                    deactivateRenderPlaybackForNewRender()
                } else {
                    // Final render finished or stopped — put preview (or final) back in the player without requiring URL @Published to change.
                    updateRenderPreviewPlayer(for: activeRenderedVideoURL)
                }
            }
            .onChange(of: viewModel.isEditStoryProEnabled) { _, enabled in
                if !enabled {
                    selectedStoryParagraphIndices = []
                    selectedMusicStoryParagraphIndices = []
                }
            }
            .onChange(of: appendPhotoItems) { _, newItems in
                let existingItems = viewModel.selectedPhotoItems
                guard !newItems.isEmpty else { return }
                guard newItems.count > existingItems.count else {
                    appendPhotoItems = existingItems
                    return
                }
                Task {
                    let appendedItems = Array(newItems.dropFirst(existingItems.count))
                    let newMediaIDs = await viewModel.appendSelectedMedia(from: appendedItems, combinedSelection: newItems)
                    await MainActor.run {
                        appendPhotoItems = viewModel.selectedPhotoItems
                        if isStoryBlockAssignSheetPresented, !newMediaIDs.isEmpty {
                            for id in newMediaIDs where !assignSheetDraftMediaIDs.contains(id) {
                                assignSheetDraftMediaIDs.append(id)
                            }
                            if let lastImported = newMediaIDs.last,
                               let idx = viewModel.mediaItems.firstIndex(where: { $0.id == lastImported }) {
                                assignSheetSlideIndex = idx
                            }
                        }
                    }
                }
            }
        }
    }

    private var appBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.95, blue: 0.90),
                Color(red: 0.97, green: 0.84, blue: 0.71),
                Color(red: 0.89, green: 0.56, blue: 0.40)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var stepPicker: some View {
        HStack(spacing: 10) {
            ForEach(visibleStudioSteps) { step in
                Button {
                    isNarrationFocused = false
                    selectedStep = step
                } label: {
                    Text(step.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Group {
                                if selectedStep == step {
                                    Capsule().fill(Color.orange)
                                } else {
                                    Capsule().fill(Color.white.opacity(0.7))
                                }
                            }
                        )
                        .foregroundStyle(selectedStep == step ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 12) {
                    FluxCutLogoMark(size: 48)

                    Text("FluxCut")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 8)

                Button {
                    isNarrationFocused = false
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }

            Text("Script. Media. Music. All in Flow.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var fluxCutProIAPBlock: some View {
        if viewModel.isEditStoryProEnabled {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FluxCut Pro is active")
                        .font(.subheadline.weight(.semibold))
                    Text("Edit Story, full script, and watermark tools are available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if proIAP.isLoadingProducts {
                    ProgressView("Contacting the App Store…")
                } else if proIAP.product == nil {
                    Text("Product not loaded. Add the in-app purchase in App Store Connect, or use a StoreKit .storekit file in Xcode for testing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await proIAP.purchase() }
                } label: {
                    HStack {
                        if proIAP.purchaseInProgress {
                            ProgressView()
                        }
                        Text("Unlock FluxCut Pro")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(proIAP.purchaseInProgress)
                Button("Restore purchases") {
                    Task { await proIAP.restorePurchases() }
                }
                .disabled(proIAP.restoreInProgress)
                if proIAP.restoreInProgress {
                    ProgressView()
                        .controlSize(.small)
                }
                if let err = proIAP.lastErrorMessage, !err.isEmpty {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else if let s = proIAP.lastStatusMessage, !s.isEmpty {
                    Text(s)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        settingsAboutView
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }

                    Link(destination: AppSettingsLinks.termsOfUse) {
                        Label("Terms of Use", systemImage: "doc.plaintext")
                    }

                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }

                    NavigationLink {
                        FeedbackSubmissionView()
                    } label: {
                        Label("Feedback", systemImage: "envelope.fill")
                    }

                    HStack {
                        Text("Version")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(appVersionLabel)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                }

                Section {
                    fluxCutProIAPBlock
                } header: {
                    Text("FluxCut Pro")
                } footer: {
                    Text("Unlocks the full Pro tab, unlimited script length, watermarks, and related tools. Purchase is a one-time in-app buy through the App Store. Use the same Apple ID and tap Restore on a new device. Mark strength in Watermark settings means opacity: lower = more see-through the video.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    NavigationLink {
                        storageSettingsView
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "externaldrive.fill.badge.person.crop")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Color.blue.opacity(0.92))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Storage")
                                    .font(.subheadline.weight(.semibold))
                                Text("Usage, unused data, and current project cleanup")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Storage")
                }

                Section {
                    NavigationLink {
                        WatermarkSettingsDetailView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Text("Watermark")
                            Spacer()
                            Text(viewModel.isEditStoryProEnabled ? (viewModel.isWatermarkEnabled ? "On" : "Off") : "Pro")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Video")
                }

                Section {
                    NavigationLink {
                        settingsFAQView
                    } label: {
                        Label("Frequently Asked Questions", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("Help")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.refreshStorageUsage()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isSettingsPresented = false
                    }
                }
            }
        }
    }

    private var settingsAboutView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("FluxCut")
                    .font(.title.weight(.bold))
                Text(
                    "A major part of FluxCut is how you can share your experiences: use Video mode and Slideshow mode, with a full script or with no script—whichever fits your story."
                )
                .font(.body)
                .foregroundStyle(.primary)
                Text(
                    "FluxCut turns your script, photos, videos, and music into narrated videos on your iPhone. Work in Script, Media, Music, and Video, and use the Pro tab for Edit Story with Pro features when you have Pro enabled."
                )
                .font(.body)
                .foregroundStyle(.primary)
                Text(
                    "Manage narration voices, media, music, and exports from Settings and Storage. Clear unused data whenever your device storage needs attention."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                HStack {
                    Text("Version")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(appVersionLabel)
                        .font(.body.weight(.semibold))
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var settingsFAQView: some View {
        List {
            Section {
                faqRow(
                    question: "What is FluxCut?",
                    answer: "FluxCut is a video studio app that combines narration, media, music, and optional captions into exported videos. You write or paste a script, pick Apple voices, arrange media, add music, then preview and render in the Video tab."
                )
                faqRow(
                    question: "Which voices can I use?",
                    answer: "FluxCut lists Enhanced and Premium voices from the system. Add or download voices in Settings → Accessibility → VoiceOver → Speech (for example Add Rotor Voice on iOS 26.3.1), then tap Reload iPhone Voices in the Script tab if needed. Siri-only personas are not available to third-party apps."
                )
            } header: {
                Text("Getting started")
            }

            Section {
                faqRow(
                    question: "What is Play Script vs Build Preview?",
                    answer: "Play Script uses text-to-speech to hear your current script quickly. Build Preview generates a short seekable narration sample with caption cues so you can check timing before exporting—useful for longer scripts and subtitle sync."
                )
                faqRow(
                    question: "What does Clean Up do?",
                    answer: "Clean Up normalizes paragraph breaks so blank lines separate ideas (paragraphs). That matches Edit Story with Pro features and consistent narration segmentation."
                )
            } header: {
                Text("Script & narration")
            }

            Section {
                faqRow(
                    question: "How do Media and Music work?",
                    answer: "Media is your photo and video pool in story order. Music can be imported files, extracted video soundtracks, or the Music Library. Levels and mixes are adjusted in the Video tab for the final render."
                )
                faqRow(
                    question: "What is the Pro tab?",
                    answer: "The Pro tab hosts Edit Story with Pro features: assign script paragraphs to media blocks and optional music segments when Pro is enabled. Without Pro, you can browse the tab to see how assignments work."
                )
            } header: {
                Text("Media, music & Pro")
            }

            Section {
                faqRow(
                    question: "What is the difference between preview and final video?",
                    answer: "Preview is a faster, shorter render to check layout and captions. Create Video produces the full-length export at your chosen quality and aspect ratio."
                )
                faqRow(
                    question: "What is Story timing mode?",
                    answer: "Story mode paces visuals to narration. Other modes may apply when Edit Story with Pro features is off and your project supports them. With Edit Story on, Video mode is aligned to Story blocks."
                )
            } header: {
                Text("Video export")
            }

            Section {
                faqRow(
                    question: "What is FluxCut Pro?",
                    answer: "FluxCut Pro is a one-time in-app purchase that unlocks the full Pro tab, removes free-tier script limits, and includes watermarking and related tools. Buy in Settings under FluxCut Pro, or in the Pro tab, then use Restore on a new device with the same Apple ID."
                )
                faqRow(
                    question: "Clear Unused Data vs Clear Current Project?",
                    answer: "Clear Unused Data removes stale renders and cache not tied to your current project. Clear Current Project wipes the active project’s working copies, previews, and narration preview data—use when you want a fresh start."
                )
            } header: {
                Text("Pro & storage")
            }
        }
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func faqRow(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(.subheadline.weight(.semibold))
            Text(answer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var storageSettingsView: some View {
        List {
            Section {
                HStack {
                    Text("Current Usage")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if viewModel.isRefreshingStorageUsage {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(viewModel.formattedStorageSize(viewModel.storageUsage.totalBytes))
                            .font(.headline.weight(.semibold))
                    }
                }

                HStack {
                    Text("Documents")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.formattedStorageSize(viewModel.storageUsage.documentsBytes))
                }

                HStack {
                    Text("Caches")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.formattedStorageSize(viewModel.storageUsage.cachesBytes))
                }

                HStack {
                    Text("Temporary")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.formattedStorageSize(viewModel.storageUsage.temporaryBytes))
                }

                Button {
                    viewModel.refreshStorageUsage()
                } label: {
                    HStack {
                        if viewModel.isRefreshingStorageUsage {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.isRefreshingStorageUsage ? "Refreshing..." : "Refresh Storage")
                    }
                }
                .disabled(viewModel.isRefreshingStorageUsage)
            } header: {
                Text("Storage Usage")
            }

            Section {
                Text("Clear old rendered videos, narration preview files, extracted cache, and stale imported media copies that are no longer part of the current project.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)

                Button(role: .destructive) {
                    viewModel.clearUnusedDataAndCache()
                } label: {
                    HStack {
                        if viewModel.isClearingUnusedData {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.isClearingUnusedData ? "Clearing..." : "Clear Unused Data and Cache")
                    }
                }
                .disabled(viewModel.isClearingUnusedData)
            } header: {
                Text("Unused Data")
            }

            Section {
                Text("Remove the active project's copied media, selected music working file, current preview, current final video, and narration preview data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)

                Button(role: .destructive) {
                    viewModel.clearCurrentProjectData()
                } label: {
                    HStack {
                        if viewModel.isClearingCurrentProjectData {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.isClearingCurrentProjectData ? "Clearing..." : "Clear Current Project Data")
                    }
                }
                .disabled(viewModel.isClearingCurrentProjectData)
            } header: {
                Text("Current Project")
            }

            if !viewModel.storageCleanupFeedback.isEmpty {
                Section {
                    Text(viewModel.storageCleanupFeedback)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                } header: {
                    Text("Last Action")
                }
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.refreshStorageUsage()
        }
    }

    private var musicLibrarySheet: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("\(filteredMusicLibraryItems.count) tracks available")
                            .font(.headline.weight(.semibold))
                        Spacer()
                        if viewModel.isLoadingMusicLibrary {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Button {
                        viewModel.refreshMusicLibrary()
                    } label: {
                        HStack {
                            if viewModel.isLoadingMusicLibrary {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(viewModel.isLoadingMusicLibrary ? "Refreshing..." : "Refresh Music Library")
                        }
                    }
                    .disabled(viewModel.isLoadingMusicLibrary)

                    if !viewModel.musicLibraryFeedback.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.blue.opacity(0.92))
                            Text(viewModel.musicLibraryFeedback)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 6)
                    }
                }

                ForEach(filteredMusicLibraryItems) { item in
                    Button {
                        toggleMusicLibrarySelection(for: item)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Spacer(minLength: 8)

                                    Text(viewModel.formattedMusicDuration(item.duration))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }

                                if let description = item.description, !description.isEmpty {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }

                            if selectedMusicLibraryItemIDs.contains(item.id) {
                                Button {
                                    if previewingMusicLibraryItemID != item.id {
                                        viewModel.previewMusicLibraryItem(item)
                                        previewingMusicLibraryItemID = item.id
                                    }
                                    if previewingMusicLibraryItemID == item.id, !viewModel.isMusicPlaying {
                                        viewModel.toggleMusicPlayback()
                                    } else if previewingMusicLibraryItemID == item.id {
                                        viewModel.toggleMusicPlayback()
                                    }
                                } label: {
                                    Image(systemName: isActivelyPreviewingMusicLibraryItem(item) ? "pause.fill" : "play.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 38, height: 38)
                                        .background(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.30, green: 0.61, blue: 0.85),
                                                    Color(red: 0.18, green: 0.39, blue: 0.73)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            in: Circle()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(selectedMusicLibraryItemIDs.contains(item.id) ? Color.blue.opacity(0.14) : Color.white.opacity(0.001))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(selectedMusicLibraryItemIDs.contains(item.id) ? Color.blue.opacity(0.28) : Color.clear, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if item.source == .imported {
                            Button(role: .destructive) {
                                pendingMusicLibraryDeletion = item
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Music Library")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $isMusicLibraryImporterPresented,
                allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav],
                allowsMultipleSelection: true
            ) { result in
                if case let .success(urls) = result, !urls.isEmpty {
                    // Synchronous security-scoped access + copy; do not use `importMusicToLibrary` (it defers with `Task` and breaks scoped URLs).
                    viewModel.ingestPickedFilesIntoMusicLibraryFromFileImporter(urls)
                    selectedStep = .music
                }
            }
            .searchable(text: $musicLibrarySearchText, prompt: "Search music")
            .onAppear {
                viewModel.refreshMusicLibrary()
            }
            .alert(item: $pendingMusicLibraryDeletion) { item in
                Alert(
                    title: Text("Delete Music?"),
                    message: Text("\(item.name) will be removed from Music Library."),
                    primaryButton: .destructive(Text("Delete")) {
                        viewModel.deleteMusicLibraryItem(item)
                    },
                    secondaryButton: .cancel()
                )
            }
            .sheet(item: $extractedSoundtrackShareFile) { file in
                ShareSheet(items: [file.url])
            }
            .onDisappear {
                selectedMusicLibraryItemIDs = []
                previewingMusicLibraryItemID = nil
                musicLibrarySearchText = ""
                viewModel.restoreProjectMusicAfterLibraryPreview()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Exit") {
                        isMusicBrowserPresented = false
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        guard !selectedMusicLibrarySelections.isEmpty else { return }
                        viewModel.addMusicLibraryItems(selectedMusicLibrarySelections)
                        selectedMusicLibraryItemIDs = []
                        isMusicBrowserPresented = false
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .fontWeight(.semibold)
                    }
                    .disabled(selectedMusicLibrarySelections.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $selectedMusicVideoItem,
                        matching: .videos,
                        photoLibrary: PHPhotoLibrary.shared()
                    ) {
                        Label("Extract Soundtracks", systemImage: "film.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.44, green: 0.36, blue: 0.78))
                    .disabled(viewModel.isImportingMusic || viewModel.isExtractingSoundtrackInBackground)

                    Button {
                        isMusicLibraryImporterPresented = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.19, green: 0.48, blue: 0.82))
                    .disabled(viewModel.isImportingMusic || viewModel.isExtractingSoundtrackInBackground)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
            }
        }
        .overlay {
            if viewModel.isExtractingSoundtrackInBackground {
                musicLibrarySoundtrackExtractionOverlay
            }
        }
        .animation(.easeInOut(duration: 0.22), value: viewModel.isExtractingSoundtrackInBackground)
    }

    /// Shown on the Music Library sheet while a video is being prepared and audio is extracted, before the system Save/share sheet appears.
    private var musicLibrarySoundtrackExtractionOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(
                    viewModel.statusMessage.isEmpty
                        ? "Preparing and extracting audio…"
                        : viewModel.statusMessage
                )
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            }
            .padding(24)
            .frame(maxWidth: 300)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }

    private var filteredMusicLibraryItems: [AppViewModel.MusicLibraryItem] {
        let query = musicLibrarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.musicLibraryItems }
        return viewModel.musicLibraryItems.filter { item in
            item.name.localizedCaseInsensitiveContains(query)
                || (item.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var selectedMusicLibrarySelections: [AppViewModel.MusicLibraryItem] {
        viewModel.musicLibraryItems.filter { selectedMusicLibraryItemIDs.contains($0.id) }
    }

    private func toggleMusicLibrarySelection(for item: AppViewModel.MusicLibraryItem) {
        if selectedMusicLibraryItemIDs.contains(item.id) {
            selectedMusicLibraryItemIDs.remove(item.id)
            if previewingMusicLibraryItemID == item.id {
                previewingMusicLibraryItemID = nil
                viewModel.stopMusicSilently()
            }
        } else {
            selectedMusicLibraryItemIDs.insert(item.id)
        }
    }

    private func isActivelyPreviewingMusicLibraryItem(_ item: AppViewModel.MusicLibraryItem) -> Bool {
        previewingMusicLibraryItemID == item.id && viewModel.isMusicPlaying
    }

    private var expandedRenderPlayerView: some View {
        ZStack {
            Color.black.opacity(0.96)
                .ignoresSafeArea()

            RenderPlayerViewController(player: renderPreviewPlayer)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isVideoCardPlayingFinalExport ? "Final Video" : "Preview Sample")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Fullscreen playback")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer()

                    Button {
                        dismissExpandedRenderPlayer()
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 15, weight: .bold))
                            .padding(12)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                Spacer()
            }
        }
        .interactiveDismissDisabled(viewModel.isExportingVideo || viewModel.isPreparingVideoPreview)
    }

    private var appVersionLabel: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildNumber) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        case let (.none, .some(build)):
            return build
        default:
            return "1.0"
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        switch selectedStep {
        case .photos:
            photoSection
        case .narration:
            narrationSection
        case .music:
            musicSection
        case .editStory:
            editStorySection
        case .video:
            videoSection
        }
    }

    private var contiguousStoryParagraphSelection: Bool {
        guard !selectedStoryParagraphIndices.isEmpty else { return false }
        let sorted = selectedStoryParagraphIndices.sorted()
        for i in sorted.indices.dropLast() where sorted[i + 1] != sorted[i] + 1 {
            return false
        }
        return true
    }

    private func toggleStoryParagraphSelection(_ index: Int) {
        guard viewModel.isEditStoryProEnabled, viewModel.storyUsesBlockTimeline else { return }
        if selectedStoryParagraphIndices.contains(index) {
            selectedStoryParagraphIndices.remove(index)
            return
        }
        if selectedStoryParagraphIndices.isEmpty {
            selectedStoryParagraphIndices = [index]
            return
        }

        let lo = selectedStoryParagraphIndices.min() ?? index
        let hi = selectedStoryParagraphIndices.max() ?? index
        let adjacent = index + 1 == lo || index - 1 == hi
        if !adjacent {
            selectedStoryParagraphIndices = [index]
            return
        }

        let candidate = selectedStoryParagraphIndices.union([index])
        let newLo = candidate.min()!
        let newHi = candidate.max()!
        guard candidate.count == newHi - newLo + 1 else {
            selectedStoryParagraphIndices = [index]
            return
        }

        guard mediaBlockSelectionMutexAllowsClosedRange(newLo...newHi) else {
            viewModel.statusMessage =
                "Can't extend here: that paragraph is in another block or would mix assigned and unassigned text. Deselect and choose a contiguous range in one block, or only unassigned paragraphs."
            return
        }

        selectedStoryParagraphIndices.insert(index)
    }

    /// A valid media-block selection is either **only unassigned** paragraphs (contiguous) or **only** paragraphs inside **one** existing block (contiguous sub-range of that block).
    private func mediaBlockSelectionMutexAllowsClosedRange(_ range: ClosedRange<Int>) -> Bool {
        let lo = range.lowerBound
        let hi = range.upperBound
        var seenBlockID: UUID?
        for i in lo...hi {
            let block = viewModel.storyEditBlockContainingParagraph(i)
            if let b = block {
                if let sid = seenBlockID, sid != b.id {
                    return false
                }
                seenBlockID = b.id
            } else {
                if seenBlockID != nil {
                    return false
                }
            }
        }
        if let b = viewModel.storyEditBlockContainingParagraph(lo), seenBlockID != nil {
            return lo >= b.firstParagraphIndex && hi <= b.lastParagraphIndex
        }
        return true
    }

    private func assignSheetDraftOrdinal(for id: UUID) -> Int? {
        assignSheetDraftMediaIDs.enumerated().first { $0.element == id }.map { $0.offset + 1 }
    }

    private func doubleTapAssignSheetMedia(_ id: UUID) {
        if let index = assignSheetDraftMediaIDs.firstIndex(of: id) {
            assignSheetDraftMediaIDs.remove(at: index)
        } else {
            assignSheetDraftMediaIDs.append(id)
        }
    }

    private func assignSheetAddMediaToDraft(_ id: UUID) {
        guard !assignSheetDraftMediaIDs.contains(id) else { return }
        assignSheetDraftMediaIDs.append(id)
    }

    private func assignSheetRemoveMediaFromDraft(_ id: UUID) {
        if let index = assignSheetDraftMediaIDs.firstIndex(of: id) {
            assignSheetDraftMediaIDs.remove(at: index)
        }
    }

    private func moveAssignSheetDraftMedia(draggedId: UUID, before targetId: UUID) {
        guard draggedId != targetId,
              let sourceIndex = assignSheetDraftMediaIDs.firstIndex(of: draggedId),
              assignSheetDraftMediaIDs.contains(targetId) else { return }
        assignSheetDraftMediaIDs.remove(at: sourceIndex)
        let destinationIndex = assignSheetDraftMediaIDs.firstIndex(of: targetId) ?? 0
        assignSheetDraftMediaIDs.insert(draggedId, at: destinationIndex)
    }

    private func openStoryBlockAssignSheet() {
        guard viewModel.isEditStoryProEnabled,
              viewModel.storyUsesBlockTimeline,
              contiguousStoryParagraphSelection,
              !selectedStoryParagraphIndices.isEmpty else { return }
        let sorted = selectedStoryParagraphIndices.sorted()
        guard let lo = sorted.first, let hi = sorted.last else { return }
        assignSheetRange = lo...hi
        assignSheetBlockOrdinal = viewModel.previewStoryBlockOrdinalForAssignment(firstParagraphIndex: lo, lastParagraphIndex: hi)
        if let existing = viewModel.storyEditBlockCoveringExactRange(lo...hi) {
            assignSheetDraftMediaIDs = existing.mediaItemIDs
        } else {
            assignSheetDraftMediaIDs = []
        }
        if viewModel.mediaItems.isEmpty {
            assignSheetSlideIndex = 0
        } else {
            assignSheetSlideIndex = min(assignSheetSlideIndex, viewModel.mediaItems.count - 1)
            assignSheetSlideIndex = max(0, assignSheetSlideIndex)
        }
        draggedAssignSheetMediaID = nil
        isStoryBlockAssignSheetPresented = true
    }

    private func confirmStoryBlockAssignSheet() {
        guard let range = assignSheetRange, !assignSheetDraftMediaIDs.isEmpty else { return }
        viewModel.assignStoryMediaToParagraphRange(range, mediaItemIDs: assignSheetDraftMediaIDs)
        isStoryBlockAssignSheetPresented = false
        assignSheetRange = nil
        assignSheetDraftMediaIDs = []
        draggedAssignSheetMediaID = nil
        selectedStoryParagraphIndices = []
    }

    private func cancelStoryBlockAssignSheet() {
        isStoryBlockAssignSheetPresented = false
        assignSheetRange = nil
        assignSheetDraftMediaIDs = []
        draggedAssignSheetMediaID = nil
    }

    private var contiguousMusicStoryParagraphSelection: Bool {
        guard !selectedMusicStoryParagraphIndices.isEmpty else { return false }
        let sorted = selectedMusicStoryParagraphIndices.sorted()
        for i in sorted.indices.dropLast() where sorted[i + 1] != sorted[i] + 1 {
            return false
        }
        return true
    }

    private func toggleMusicStoryParagraphSelection(_ index: Int) {
        guard viewModel.isEditStoryProEnabled else { return }
        if selectedMusicStoryParagraphIndices.contains(index) {
            selectedMusicStoryParagraphIndices.remove(index)
            return
        }
        if selectedMusicStoryParagraphIndices.isEmpty {
            selectedMusicStoryParagraphIndices = [index]
            return
        }

        let lo = selectedMusicStoryParagraphIndices.min() ?? index
        let hi = selectedMusicStoryParagraphIndices.max() ?? index
        let adjacent = index + 1 == lo || index - 1 == hi
        if !adjacent {
            selectedMusicStoryParagraphIndices = [index]
            return
        }

        let candidate = selectedMusicStoryParagraphIndices.union([index])
        let newLo = candidate.min()!
        let newHi = candidate.max()!
        guard candidate.count == newHi - newLo + 1 else {
            selectedMusicStoryParagraphIndices = [index]
            return
        }

        guard musicSegmentSelectionMutexAllowsClosedRange(newLo...newHi) else {
            viewModel.statusMessage =
                "Can't extend here: that paragraph is in another music segment or would mix assigned and unassigned lines. Deselect and choose a contiguous range in one segment, or only unassigned paragraphs."
            return
        }

        selectedMusicStoryParagraphIndices.insert(index)
    }

    /// Same mutex as media blocks: selection is either only paragraphs with **no** music segment, or only paragraphs inside **one** existing segment.
    private func musicSegmentSelectionMutexAllowsClosedRange(_ range: ClosedRange<Int>) -> Bool {
        let lo = range.lowerBound
        let hi = range.upperBound
        var seenSegmentID: UUID?
        for i in lo...hi {
            let segment = viewModel.storyMusicBedSegmentContainingParagraph(i)
            if let s = segment {
                if let sid = seenSegmentID, sid != s.id {
                    return false
                }
                seenSegmentID = s.id
            } else {
                if seenSegmentID != nil {
                    return false
                }
            }
        }
        if let s = viewModel.storyMusicBedSegmentContainingParagraph(lo), seenSegmentID != nil {
            return lo >= s.firstParagraphIndex && hi <= s.lastParagraphIndex
        }
        return true
    }

    private func resetStoryMusicAssignSheetState() {
        musicAssignSheetRange = nil
        musicAssignDraftChoice = nil
        musicAssignUserParagraphRange = nil
    }

    private func openStoryMusicAssignSheet() {
        guard viewModel.isEditStoryProEnabled,
              contiguousMusicStoryParagraphSelection,
              !selectedMusicStoryParagraphIndices.isEmpty else { return }
        let sorted = selectedMusicStoryParagraphIndices.sorted()
        guard let lo = sorted.first, let hi = sorted.last else { return }
        if let reason = viewModel.validateMusicAssignmentSelection(lo...hi) {
            viewModel.statusMessage = reason
            storyMusicAssignBlockingMessage = reason
            return
        }
        musicAssignSheetSegmentOrdinal = viewModel.storyMusicSegmentOrdinalForAssignSheet(selectionLo: lo)
        musicAssignUserParagraphRange = lo...hi
        musicAssignSheetRange = lo...hi
        if let existing = viewModel.storyMusicBedSegmentForExactRange(lo...hi) {
            if let trackID = existing.soundtrackItemID {
                musicAssignDraftChoice = .libraryTrack(trackID)
            } else {
                musicAssignDraftChoice = .musicTabMix
            }
        } else {
            musicAssignDraftChoice = nil
        }
        isStoryMusicAssignSheetPresented = true
    }

    private func confirmStoryMusicAssignSheet() {
        guard let choice = musicAssignDraftChoice,
              let paragraphRange = musicAssignUserParagraphRange else { return }
        viewModel.applyMusicSegmentAssignment(choice: choice, paragraphRange: paragraphRange)
        viewModel.stopMusicSilently()
        isStoryMusicAssignSheetPresented = false
        resetStoryMusicAssignSheetState()
        selectedMusicStoryParagraphIndices = []
    }

    private func toggleMusicAssignSheetPlayback() {
        guard musicAssignDraftChoice != nil else { return }
        if viewModel.isMusicPlaying {
            viewModel.toggleMusicPlayback()
            return
        }
        switch musicAssignDraftChoice {
        case .musicTabMix:
            _ = viewModel.prepareCombinedMixPreview()
            viewModel.toggleMusicPlayback()
        case .libraryTrack(let id):
            guard let item = viewModel.soundtrackItems.first(where: { $0.id == id }) else { return }
            viewModel.previewStorySoundtrackItem(item)
            viewModel.toggleMusicPlayback()
        case .none:
            break
        }
    }

    private func cancelStoryMusicAssignSheet() {
        viewModel.stopMusicSilently()
        isStoryMusicAssignSheetPresented = false
        resetStoryMusicAssignSheetState()
    }

    private func blockAssignPoolThumbnail(item: AppViewModel.MediaItem, index: Int) -> some View {
        let draftOrder = assignSheetDraftOrdinal(for: item.id)
        return ZStack(alignment: .topTrailing) {
            Image(uiImage: item.previewImage)
                .resizable()
                .scaledToFill()
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            assignSheetSlideIndex == index ? Color.orange : Color.clear,
                            lineWidth: 3
                        )
                }
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                .id("\(item.id.uuidString)-\(ObjectIdentifier(item.previewImage as AnyObject))")

            if item.isVideo {
                Image(systemName: "video.fill")
                    .font(.caption2.weight(.bold))
                    .padding(6)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(6)
            }

            if let order = draftOrder {
                Text("\(order)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Color.green.opacity(0.92), in: Circle())
                    .padding(6)
            }
        }
        .frame(width: 78, height: 78)
        .overlay(alignment: .bottomTrailing) {
            Text(viewModel.mediaDisplayLabel(for: item.id))
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.95), in: Capsule())
                .foregroundStyle(.white)
                .padding(6)
        }
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                doubleTapAssignSheetMedia(item.id)
            }
        )
        .onTapGesture {
            assignSheetSlideIndex = index
        }
    }

    @ViewBuilder
    private func assignSheetDraftAssignedCell(mediaID: UUID) -> some View {
        if let item = viewModel.mediaItems.first(where: { $0.id == mediaID }),
           let position = assignSheetDraftMediaIDs.firstIndex(of: mediaID),
           let poolIndex = viewModel.mediaItems.firstIndex(where: { $0.id == mediaID }) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: item.previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    assignSheetSlideIndex == poolIndex ? Color.orange : Color.clear,
                                    lineWidth: 2
                                )
                        }
                        .id("\(item.id.uuidString)-\(ObjectIdentifier(item.previewImage as AnyObject))")
                    if item.isVideo {
                        Image(systemName: "video.fill")
                            .font(.caption2.weight(.bold))
                            .padding(4)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(4)
                    }
                }
                Text("\(position + 1)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .highPriorityGesture(
                TapGesture(count: 2).onEnded {
                    doubleTapAssignSheetMedia(mediaID)
                }
            )
            .onTapGesture {
                assignSheetSlideIndex = poolIndex
            }
            .onDrag {
                draggedAssignSheetMediaID = mediaID
                return NSItemProvider(object: mediaID.uuidString as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: AssignSheetDraftReorderDropDelegate(
                    targetId: mediaID,
                    draggedId: $draggedAssignSheetMediaID,
                    onReorder: moveAssignSheetDraftMedia
                )
            )
        }
    }

    @ViewBuilder
    private func assignSheetDraftAssignedSection() -> some View {
        if !assignSheetDraftMediaIDs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Assigned to this block (order)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Drag to reorder. Tap a thumbnail to show it in the preview above; double-tap to remove it from the block.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(assignSheetDraftMediaIDs, id: \.self) { mediaID in
                            assignSheetDraftAssignedCell(mediaID: mediaID)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
        }
    }

    @ViewBuilder
    private func assignSheetTabPage(index: Int, item: AppViewModel.MediaItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.08))
            mediaStage(for: item, isActive: assignSheetSlideIndex == index)
                .frame(maxWidth: .infinity, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
        .overlay(alignment: .topLeading) {
            if item.isVideo {
                Label("Video", systemImage: "video.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(14)
            }
        }
        .overlay(alignment: .topTrailing) {
            if assignSheetSlideIndex == index {
                HStack(spacing: 8) {
                    Button {
                        assignSheetAddMediaToDraft(item.id)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.black.opacity(0.62), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(assignSheetDraftMediaIDs.contains(item.id))
                    .opacity(assignSheetDraftMediaIDs.contains(item.id) ? 0.35 : 1)
                    .accessibilityLabel("Add clip to block")

                    Button {
                        assignSheetRemoveMediaFromDraft(item.id)
                    } label: {
                        Image(systemName: "minus")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.black.opacity(0.62), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!assignSheetDraftMediaIDs.contains(item.id))
                    .opacity(!assignSheetDraftMediaIDs.contains(item.id) ? 0.35 : 1)
                    .accessibilityLabel("Remove clip from block")
                }
                .padding(14)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 8) {
                Text(viewModel.mediaDisplayLabel(for: item.id))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
                Text("\(index + 1)/\(viewModel.mediaItems.count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(14)
        }
        .tag(index)
    }

    @ViewBuilder
    private func assignSheetNonEmptyMediaColumn() -> some View {
        VStack(spacing: 14) {
            TabView(selection: $assignSheetSlideIndex) {
                ForEach(Array(viewModel.mediaItems.enumerated()), id: \.offset) { index, item in
                    assignSheetTabPage(index: index, item: item)
                }
            }
            .frame(height: 280)
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.mediaItems.enumerated()), id: \.element.id) { index, item in
                        blockAssignPoolThumbnail(item: item, index: index)
                    }

                    PhotosPicker(
                        selection: $appendPhotoItems,
                        maxSelectionCount: nil,
                        selectionBehavior: .ordered,
                        matching: .any(of: [.images, .videos]),
                        photoLibrary: PHPhotoLibrary.shared()
                    ) {
                        mediaAppendThumbnail
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            appendPhotoItems = viewModel.selectedPhotoItems
                        }
                    )
                }
                .padding(.vertical, 4)
            }

            if !assignSheetBlockScriptText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Block script")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(assignSheetBlockScriptText)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 72, maxHeight: 160)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Studio Tip")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Swipe the big preview to browse; videos always start when ready (Play during loading is optional early start). Tap a pool thumbnail to jump here. The + at the end of the strip imports into the pool and adds those clips to this block. Use + / − on the preview to add or remove the current clip from the block, or double-tap a pool thumbnail. Assigned clips: drag to reorder; tap to preview, double-tap to remove.")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.82))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var storyBlockAssignSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let range = assignSheetRange {
                        Text("Paragraphs \(range.lowerBound + 1)–\(range.upperBound + 1)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "text.bubble.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(
                                assignSheetRange.map { viewModel.blockNarrationEstimateMetaLine(paragraphRange: $0) }
                                    ?? viewModel.estimatedNarrationMetaLine
                            )
                            .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Color(red: 0.63, green: 0.24, blue: 0.10))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.66), in: Capsule())

                        if viewModel.isLoadingMediaSelection {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(viewModel.mediaSelectionLoadingLine)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(Color(red: 0.63, green: 0.24, blue: 0.10))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.66), in: Capsule())
                        } else if !viewModel.mediaItems.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 12, weight: .bold))
                                Text(viewModel.mediaSelectionMetaLine)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(Color(red: 0.63, green: 0.24, blue: 0.10))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.66), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if viewModel.mediaItems.contains(where: \.isVideo) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Video Volume In Final Video")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Slider(value: $viewModel.videoAudioVolume, in: 0...1)
                                .tint(.orange)
                            Text("Blend the original sound from your video clips into the final mix.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    assignSheetDraftAssignedSection()

                    if viewModel.mediaItems.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Import media from your library to add clips to this block.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            PhotosPicker(
                                selection: $viewModel.selectedPhotoItems,
                                maxSelectionCount: nil,
                                selectionBehavior: .ordered,
                                matching: .any(of: [.images, .videos]),
                                photoLibrary: PHPhotoLibrary.shared()
                            ) {
                                HStack(spacing: 10) {
                                    Image(systemName: "square.stack.3d.up.fill")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("Import Media")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .foregroundStyle(.white)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.94, green: 0.46, blue: 0.22),
                                            Color(red: 0.80, green: 0.26, blue: 0.10)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else {
                        assignSheetNonEmptyMediaColumn()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.95, blue: 0.90),
                        Color(red: 0.97, green: 0.84, blue: 0.71),
                        Color(red: 0.89, green: 0.56, blue: 0.40)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Block \(assignSheetBlockOrdinal)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelStoryBlockAssignSheet()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        confirmStoryBlockAssignSheet()
                    }
                    .fontWeight(.semibold)
                    .disabled(assignSheetDraftMediaIDs.isEmpty)
                }
            }
        }
    }

    private var storyMusicAssignSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Segment \(musicAssignSheetSegmentOrdinal)")
                            .font(.title2.weight(.semibold))
                        if let range = musicAssignSheetRange {
                            Text("Paragraphs \(range.lowerBound + 1)–\(range.upperBound + 1)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("One soundtrack per segment, always from 0:00. Shorter narration trims the bed; longer narration loops. Reusing the same file on another segment starts at 0:00 again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !musicAssignSheetScriptText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Segment script")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ScrollView {
                                Text(musicAssignSheetScriptText)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 72, maxHeight: 200)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    Text("Sound library")
                        .font(.headline)

                    Text("Tap a row to select it, then use the blue play button on that row to preview (same as Music → Music Library). Tap Done to save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        musicAssignSoundLibraryRow(
                            title: "Music Mix (default)",
                            durationText: musicAssignMixDurationLabel,
                            subtitle: "Combined tracks from your Music tab queue",
                            isSelected: musicAssignDraftChoice == .musicTabMix,
                            isPlayingPreview: musicAssignDraftChoice == .musicTabMix && viewModel.isMusicPlaying
                        ) {
                            musicAssignDraftChoice = .musicTabMix
                        } onPlayTap: {
                            musicAssignDraftChoice = .musicTabMix
                            toggleMusicAssignSheetPlayback()
                        }
                        ForEach(viewModel.soundtrackItems) { item in
                            Divider()
                                .padding(.leading, 12)
                            musicAssignSoundLibraryRow(
                                title: item.name,
                                durationText: viewModel.formattedMusicDuration(item.duration),
                                subtitle: "In soundtrack queue",
                                isSelected: musicAssignDraftChoice == .libraryTrack(item.id),
                                isPlayingPreview: musicAssignDraftChoice == .libraryTrack(item.id) && viewModel.isMusicPlaying
                            ) {
                                musicAssignDraftChoice = .libraryTrack(item.id)
                            } onPlayTap: {
                                musicAssignDraftChoice = .libraryTrack(item.id)
                                toggleMusicAssignSheetPlayback()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    }

                    if viewModel.soundtrackItems.isEmpty {
                        Text("No tracks in the queue yet—add audio in the Music tab, or use the default mix row.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.95, blue: 0.90),
                        Color(red: 0.97, green: 0.84, blue: 0.71),
                        Color(red: 0.89, green: 0.56, blue: 0.40)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Assign segment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelStoryMusicAssignSheet()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        confirmStoryMusicAssignSheet()
                    }
                    .disabled(musicAssignDraftChoice == nil)
                }
            }
        }
    }

    /// Total duration label for the Music-tab mix row (matches Music Library row timing affordance).
    private var musicAssignMixDurationLabel: String? {
        let total = viewModel.soundtrackItems.reduce(0.0) { $0 + $1.duration }
        guard total > 0 else { return nil }
        return viewModel.formattedMusicDuration(total)
    }

    /// Same track row chrome as **Music → Music Library** (`musicLibrarySheet`): title + duration row, subtitle, blue selection, gradient play when selected.
    private func musicAssignSoundLibraryRow(
        title: String,
        durationText: String?,
        subtitle: String?,
        isSelected: Bool,
        isPlayingPreview: Bool,
        onSelect: @escaping () -> Void,
        onPlayTap: @escaping () -> Void
    ) -> some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 8)

                        if let durationText {
                            Text(durationText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                if isSelected {
                    Button {
                        onPlayTap()
                    } label: {
                        Image(systemName: isPlayingPreview ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.30, green: 0.61, blue: 0.85),
                                        Color(red: 0.18, green: 0.39, blue: 0.73)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.14) : Color.white.opacity(0.001))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.blue.opacity(0.28) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func storyScriptParagraphRow(
        index: Int,
        text: String,
        isSelected: Bool,
        assignmentCaption: String,
        musicTabMediaBlockCaption: String? = nil
    ) -> some View {
        let stripeColor = (index % 2 == 0) ? Color.blue.opacity(0.35) : Color.purple.opacity(0.32)
        let isUnassigned = assignmentCaption == "Unassigned"
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(stripeColor)
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 4) {
                if let mediaCap = musicTabMediaBlockCaption {
                    Text(mediaCap)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.secondary.opacity(0.85))
                }
                Text(assignmentCaption)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isUnassigned ? Color.orange.opacity(0.95) : .secondary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.orange.opacity(0.16) : Color.white.opacity(0.45))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 2)
        }
    }

    /// Edit → Media: Assign + Clear (kept above the fixed-height paragraph `ScrollView`, like Script tab controls above the editor).
    private var editStoryMediaAssignButtonRow: some View {
        HStack(spacing: 12) {
            Button {
                openStoryBlockAssignSheet()
            } label: {
                Label("Assign", systemImage: "square.and.arrow.down.on.square")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(
                !viewModel.isEditStoryProEnabled
                    || !viewModel.storyUsesBlockTimeline
                    || !contiguousStoryParagraphSelection
                    || selectedStoryParagraphIndices.isEmpty
            )

            Button {
                viewModel.clearAllStoryEditBlocks()
                selectedStoryParagraphIndices = []
                selectedMusicStoryParagraphIndices = []
            } label: {
                Label("Clear", systemImage: "eraser")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.isEditStoryProEnabled || !viewModel.storyUsesBlockTimeline || viewModel.storyEditBlocks.isEmpty)
        }
    }

    /// Same fixed height as the Script tab editor so paragraph lists scroll inside the card while actions stay visible.
    private static let editStoryParagraphScrollMaxHeight: CGFloat = 320

    /// Edit → Music: Assign + Clear music (same layout as media: actions above scrolling paragraph list).
    private var editStoryMusicAssignButtonRow: some View {
        HStack(spacing: 12) {
            Button {
                openStoryMusicAssignSheet()
            } label: {
                Label("Assign", systemImage: "music.note.list")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(
                !viewModel.isEditStoryProEnabled
                    || !contiguousMusicStoryParagraphSelection
                    || selectedMusicStoryParagraphIndices.isEmpty
            )

            Button {
                viewModel.clearAllStorySegmentSoundtracks()
                selectedMusicStoryParagraphIndices = []
            } label: {
                Label("Clear music", systemImage: "eraser")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.isEditStoryProEnabled || !viewModel.storyUsesBlockTimeline || viewModel.storyMusicBedSegments.isEmpty)
        }
    }

    private func storyMediaBlockCaption(forParagraphIndex index: Int) -> String {
        if let b = viewModel.storyBlockOrdinal(forParagraphIndex: index) {
            return "Block \(b)"
        }
        return "Unassigned"
    }

    @ViewBuilder
    private func editStoryMediaParagraphRow(index: Int, text: String) -> some View {
        if viewModel.isEditStoryProEnabled {
            Button {
                toggleStoryParagraphSelection(index)
            } label: {
                storyScriptParagraphRow(
                    index: index,
                    text: text,
                    isSelected: selectedStoryParagraphIndices.contains(index),
                    assignmentCaption: storyMediaBlockCaption(forParagraphIndex: index)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            storyScriptParagraphRow(
                index: index,
                text: text,
                isSelected: false,
                assignmentCaption: storyMediaBlockCaption(forParagraphIndex: index)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(0.95)
        }
    }

    @ViewBuilder
    private func editStoryMusicParagraphRow(index: Int, text: String) -> some View {
        if viewModel.isEditStoryProEnabled {
            Button {
                toggleMusicStoryParagraphSelection(index)
            } label: {
                storyScriptParagraphRow(
                    index: index,
                    text: text,
                    isSelected: selectedMusicStoryParagraphIndices.contains(index),
                    assignmentCaption: viewModel.storyMusicAssignmentCaption(forParagraphIndex: index)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            storyScriptParagraphRow(
                index: index,
                text: text,
                isSelected: false,
                assignmentCaption: viewModel.storyMusicAssignmentCaption(forParagraphIndex: index)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(0.95)
        }
    }

    private var editStoryMediaParagraphsOpacity: Double {
        if !viewModel.isEditStoryProEnabled {
            return 0.55
        }
        return viewModel.storyUsesBlockTimeline ? 1 : 0.5
    }

    private var editStoryMediaParagraphsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Script paragraphs")
                .font(.headline)
            Text(
                viewModel.storyUsesBlockTimeline
                    ? "Select a contiguous paragraph range, then Assign."
                    : "Turn on Edit Story with Pro features to select paragraphs and assign media to blocks."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            DisclosureGroup(isExpanded: $editStoryHelpExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import and order tracks in the Music tab. Use the Music sub-tab here to assign beds to paragraphs.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Tap paragraphs to select a contiguous range (only unassigned lines, or only lines inside one existing block—never both). Assign stays above the list while you scroll—same idea as the Script window. Use + / − on the large preview, double-tap pool thumbnails, or tap assigned clips to preview and double-tap to remove.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            } label: {
                Text("How assigning works")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.orange)
            .disabled(!viewModel.isEditStoryProEnabled || !viewModel.storyUsesBlockTimeline)
            editStoryMediaAssignButtonRow
            if viewModel.storyScriptParagraphs.isEmpty {
                Text("No paragraphs yet—add Script text with blank lines between ideas, or run Clean Up on pasted text.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(viewModel.storyScriptParagraphs.enumerated()), id: \.offset) { index, text in
                            editStoryMediaParagraphRow(index: index, text: text)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: Self.editStoryParagraphScrollMaxHeight)
                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(editStoryMediaParagraphsOpacity)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var editStoryMusicParagraphsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Script paragraphs")
                .font(.headline)
            Text("Select a contiguous range for one music segment, then Assign.")
                .font(.caption)
                .foregroundStyle(.secondary)
            DisclosureGroup(isExpanded: $editStoryHelpExpanded) {
                Text("Music spans are independent of media blocks. Select a contiguous range that is either only unassigned lines or only lines inside one existing segment (not both). Assign stays above the scrolling list. Tap Assign to set the soundtrack for that range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            } label: {
                Text("How assigning works")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.orange)
            .disabled(!viewModel.isEditStoryProEnabled)
            editStoryMusicAssignButtonRow
            if viewModel.storyScriptParagraphs.isEmpty {
                Text("No paragraphs yet—add Script text with blank lines between ideas, or run Clean Up on pasted text.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(viewModel.storyScriptParagraphs.enumerated()), id: \.offset) { index, text in
                            editStoryMusicParagraphRow(index: index, text: text)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: Self.editStoryParagraphScrollMaxHeight)
                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(viewModel.isEditStoryProEnabled ? 1 : 0.55)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var editStorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pro")
                .font(.title2.weight(.semibold))

            if !viewModel.isEditStoryProEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.title3)
                            .foregroundStyle(Color.orange)
                        Text(
                            "Unlock FluxCut Pro to use Edit Story, unlock the full script, and use watermarks. You can read the sections below; controls stay inactive until you purchase or restore."
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    fluxCutProIAPBlock
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Edit Story with Pro features", isOn: $viewModel.storyUsesBlockTimeline)
                    .font(.subheadline.weight(.semibold))
                    .onChange(of: viewModel.storyUsesBlockTimeline) { _, _ in
                        selectedStoryParagraphIndices = []
                        selectedMusicStoryParagraphIndices = []
                    }
                    .disabled(!viewModel.isEditStoryProEnabled)
            }
            .padding(14)
            .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if viewModel.storyUsesBlockTimeline, !viewModel.storyBlockValidationErrors().isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Video export is blocked until this is fixed", systemImage: "exclamationmark.octagon.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.orange)
                    ForEach(Array(viewModel.storyBlockValidationErrors().enumerated()), id: \.offset) { _, line in
                        Text("• \(line)")
                            .font(.caption.weight(.semibold))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if viewModel.storyUsesBlockTimeline {
                Picker("Editor", selection: $editStoryEditorTab) {
                    ForEach(EditStoryEditorTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!viewModel.isEditStoryProEnabled)
            }

            if !viewModel.storyUsesBlockTimeline || editStoryEditorTab == .media {
                editStoryMediaParagraphsPanel
            }

            if viewModel.storyUsesBlockTimeline, editStoryEditorTab == .music {
                editStoryMusicParagraphsPanel
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Media")
                    .font(.title2.weight(.semibold))
                Spacer()
                if viewModel.mediaItems.isEmpty {
                    PhotosPicker(
                        selection: $viewModel.selectedPhotoItems,
                        maxSelectionCount: nil,
                        selectionBehavior: .ordered,
                        matching: .any(of: [.images, .videos]),
                        photoLibrary: PHPhotoLibrary.shared()
                    ) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.white.opacity(0.18))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import Media")
                                    .font(.subheadline.weight(.semibold))
                                Text("Photos and videos")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.94, green: 0.46, blue: 0.22),
                                Color(red: 0.80, green: 0.26, blue: 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(viewModel.estimatedNarrationMetaLine)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color(red: 0.63, green: 0.24, blue: 0.10))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.66), in: Capsule())

                if viewModel.isLoadingMediaSelection {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(viewModel.mediaSelectionLoadingLine)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color(red: 0.63, green: 0.24, blue: 0.10))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.66), in: Capsule())
                } else if !viewModel.mediaItems.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 12, weight: .bold))
                        Text(viewModel.mediaSelectionMetaLine)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color(red: 0.63, green: 0.24, blue: 0.10))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.66), in: Capsule())
                }

                if !viewModel.mediaItems.isEmpty {
                    Button {
                        viewModel.clearMediaSelection()
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.14))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.red.opacity(0.92))
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Clear Media")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Start over with a fresh selection")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.red.opacity(0.12), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if viewModel.mediaItems.contains(where: \.isVideo) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video Volume In Final Video")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.videoAudioVolume, in: 0...1)
                        .tint(.orange)
                    Text("Blend the original sound from your video clips into the final mix.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if viewModel.mediaItems.isEmpty {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.65))
                    .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 14) {
                    TabView(selection: $viewModel.currentSlideIndex) {
                        ForEach(Array(viewModel.mediaItems.enumerated()), id: \.offset) { index, item in
                            ZStack {
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .fill(Color.black.opacity(0.08))
                                mediaStage(for: item, isActive: viewModel.currentSlideIndex == index)
                                    .frame(maxWidth: .infinity, maxHeight: 280)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                            .frame(height: 280)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .topLeading) {
                                if item.isVideo {
                                    Label("Video", systemImage: "video.fill")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.black.opacity(0.55), in: Capsule())
                                        .foregroundStyle(.white)
                                        .padding(14)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if viewModel.currentSlideIndex == index {
                                    Menu {
                                        Button {
                                            viewModel.duplicateMediaItem(withId: item.id)
                                        } label: {
                                            Label("Duplicate", systemImage: "plus.square.on.square")
                                        }

                                        Button(role: .destructive) {
                                            pendingMediaDeletion = item
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 30, height: 30)
                                            .background(Color.black.opacity(0.62), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(14)
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                HStack(spacing: 8) {
                                    Text(viewModel.mediaDisplayLabel(for: item.id))
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.orange.opacity(0.9), in: Capsule())
                                        .foregroundStyle(.white)

                                    Text("\(index + 1)/\(viewModel.mediaItems.count)")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.black.opacity(0.55), in: Capsule())
                                        .foregroundStyle(.white)
                                }
                                .padding(14)
                            }
                            .tag(index)
                        }
                    }
                    .frame(height: 280)
                    .tabViewStyle(.page(indexDisplayMode: .automatic))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(viewModel.mediaItems.enumerated()), id: \.element.id) { index, item in
                                mediaThumbnail(item: item, index: index)
                                    .onDrag {
                                        draggedMediaItem = item
                                        return NSItemProvider(object: item.id.uuidString as NSString)
                                    }
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: MediaReorderDropDelegate(
                                            targetItem: item,
                                            draggedItem: $draggedMediaItem,
                                            viewModel: viewModel
                                        )
                                    )
                            }

                            PhotosPicker(
                                selection: $appendPhotoItems,
                                maxSelectionCount: nil,
                                selectionBehavior: .ordered,
                                matching: .any(of: [.images, .videos]),
                                photoLibrary: PHPhotoLibrary.shared()
                            ) {
                                mediaAppendThumbnail
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    appendPhotoItems = viewModel.selectedPhotoItems
                                }
                            )
                        }
                        .padding(.vertical, 4)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Studio Tip")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Swipe to review your media. Videos always start when ready; you can also tap Play while loading to begin early. Drag thumbnails to reorder before script, music, and export.")
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.82))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private func mediaStage(for item: AppViewModel.MediaItem, isActive: Bool) -> some View {
        switch item.kind {
        case .photo:
            Image(uiImage: item.previewImage)
                .resizable()
                .scaledToFit()
        case .video:
            ProjectVideoStageView(item: item, isActive: isActive, viewModel: viewModel)
        }
    }

    private func mediaThumbnail(item: AppViewModel.MediaItem, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: item.previewImage)
                .resizable()
                .scaledToFill()
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            viewModel.currentSlideIndex == index ? Color.orange : Color.clear,
                            lineWidth: 3
                        )
                }
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                .id("\(item.id.uuidString)-\(ObjectIdentifier(item.previewImage as AnyObject))")

            if item.isVideo {
                Image(systemName: "video.fill")
                    .font(.caption2.weight(.bold))
                    .padding(6)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
        .frame(width: 78, height: 78)
        .overlay(alignment: .bottomTrailing) {
            Text(viewModel.mediaDisplayLabel(for: item.id))
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.95), in: Capsule())
                .foregroundStyle(.white)
                .padding(6)
        }
        .onTapGesture {
            viewModel.currentSlideIndex = index
        }
    }

    private var mediaAppendThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .frame(width: 78, height: 78)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            Color.orange.opacity(0.55),
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                }

            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.orange)
        }
    }

    private var narrationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear
                .frame(height: 1)
                .id("script-top")

            Text("Script")
                .font(.title2.weight(.semibold))
                .onTapGesture { isNarrationFocused = false }
            Text("Edit Story with Pro features uses paragraphs as text between blank lines. Use an empty line between ideas, or tap Clean Up to insert breaks when pasted text only has single line breaks.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .onTapGesture { isNarrationFocused = false }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.14))
                            .frame(width: 30, height: 30)
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.orange.opacity(0.92))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Narration Voice")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(viewModel.selectedVoiceName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                viewModel.reloadAvailableVoices()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(Color.blue.opacity(0.9))
                    Text("Reload iPhone Voices")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.blue.opacity(0.10), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                Text(viewModel.voiceReloadFeedback)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.blue.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.72), in: Capsule())

            Text("Reload after adding Enhanced or Premium under Settings → Accessibility → VoiceOver → Speech (e.g. Add Rotor Voice on iOS 26.3.1). Pick the matching language above. Siri voices are not available to FluxCut on iOS.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let narrationLanguageWarning = viewModel.narrationLanguageWarning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(narrationLanguageWarning)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.orange.opacity(0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.72), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("Language")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Menu {
                        ForEach(viewModel.availableVoiceLanguages) { language in
                            Button {
                                viewModel.selectVoiceLanguage(language.id)
                                isNarrationFocused = false
                            } label: {
                                if language.id == viewModel.selectedVoiceLanguage {
                                    Label("\(language.label) (\(language.voiceCount))", systemImage: "checkmark")
                                } else {
                                    Text("\(language.label) (\(language.voiceCount))")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(viewModel.selectedVoiceLanguageLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.82), in: Capsule())
                    }
                    .disabled(viewModel.availableVoiceLanguages.isEmpty)
                }

                HStack(spacing: 10) {
                    Text("Speed")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Menu {
                        ForEach(viewModel.narrationSpeedOptions) { option in
                            Button {
                                viewModel.selectedNarrationSpeed = option.multiplier
                                isNarrationFocused = false
                            } label: {
                                if option.multiplier == viewModel.selectedNarrationSpeed {
                                    Label(option.label, systemImage: "checkmark")
                                } else {
                                    Text(option.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(viewModel.selectedNarrationSpeedLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.82), in: Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Voice")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(viewModel.voicesForSelectedLanguage) { option in
                                // HStack (not ZStack): a full-width selection Button overlapped a hide control; taps never reached the top control reliably.
                                HStack(alignment: .center, spacing: 0) {
                                    Button {
                                        viewModel.selectedVoiceIdentifier = option.id
                                        isNarrationFocused = false
                                    } label: {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(option.name)
                                                    .font(.headline)
                                                    .foregroundStyle(.primary)
                                                HStack(spacing: 6) {
                                                    Text(option.qualityLabel)
                                                        .font(.caption.weight(.semibold))
                                                    if option.regionLabel != option.languageLabel {
                                                        Text(option.regionLabel)
                                                            .font(.caption)
                                                    }
                                                }
                                                .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 8)
                                            if option.id == viewModel.selectedVoiceIdentifier {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.borderless)

                                    if viewModel.canHideVoices {
                                        Button {
                                            voicePendingHide = option
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(Color.red.opacity(0.9))
                                                .frame(minWidth: 44, minHeight: 44)
                                                .contentShape(Rectangle())
                                        }
                                        // ScrollView + Button: borderless avoids the scroll gesture swallowing taps (iOS).
                                        .buttonStyle(.borderless)
                                        .padding(.trailing, 4)
                                        .accessibilityLabel("Hide voice")
                                        .accessibilityHint("Asks for confirmation, then removes this voice from the list")
                                        .zIndex(1)
                                    }
                                }
                                .background(
                                    Color.white.opacity(option.id == viewModel.selectedVoiceIdentifier ? 0.95 : 0.72),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                            }
                        }
                        .padding(.top, 2)
                    }
                    .frame(maxHeight: 180)
                }

                Text("Tap the red remove control (same icon as the Music soundtrack queue) to hide a voice. Reload iPhone Voices brings hidden voices back.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .onAppear {
                viewModel.loadAvailableVoicesIfNeeded()
            }
            // Do not disable this whole block when the voice list is empty — it prevented remove taps from
            // reaching the trailing control in some states; rows are empty anyway when there are no voices.

            HStack(spacing: 10) {
                scriptMetaPill(
                    title: "Length",
                    value: viewModel.scriptLengthPillValue,
                    systemImage: "text.alignleft"
                )

                Button {
                    viewModel.clearNarration()
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.14))
                                .frame(width: 28, height: 28)
                            Image(systemName: "trash.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.red.opacity(0.92))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Clear Text")
                                .font(.caption.weight(.semibold))
                            Text("Start fresh")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.red.opacity(0.10), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .disabled(
                    viewModel.isPreparingNarrationPreview
                        || viewModel.narrationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            Button {
                viewModel.recoverLastNarrationDraft()
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.14))
                            .frame(width: 28, height: 28)
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.blue.opacity(0.92))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Recover Last Script")
                            .font(.caption.weight(.semibold))
                        Text("Restore saved draft")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.blue.opacity(0.10), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .disabled(viewModel.isPreparingNarrationPreview)

            HStack(spacing: 10) {
                inlineScriptActionButton(
                    title: viewModel.isSpeaking ? "Stop Script" : "Play Script",
                    systemImage: viewModel.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill"
                ) {
                    viewModel.playNarration()
                }
                .opacity(viewModel.canPlayNarration ? 1 : 0.6)
                .disabled(!viewModel.canPlayNarration)

                inlineScriptActionButton(title: "Introduction", systemImage: "text.badge.plus") {
                    viewModel.loadSampleNarration()
                }
            }
            .disabled(viewModel.isPreparingNarrationPreview)

            HStack(spacing: 10) {
                scriptJumpButton(
                    title: isNarrationPreviewSectionVisible ? "Hide Preview" : "Preview",
                    systemImage: isNarrationPreviewSectionVisible ? "eye.slash" : "waveform.path.ecg"
                ) {
                    isNarrationFocused = false
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isNarrationPreviewSectionVisible.toggle()
                    }
                    if !isNarrationPreviewSectionVisible {
                        viewModel.stopNarrationPreview()
                    } else {
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scriptScrollProxy?.scrollTo("script-preview", anchor: .top)
                            }
                        }
                    }
                }

                scriptJumpButton(title: "Clean Up", systemImage: "wand.and.stars") {
                    isNarrationFocused = false
                    viewModel.cleanupNarrationText()
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            scriptScrollProxy?.scrollTo("script-top", anchor: .top)
                        }
                    }
                }
                .opacity(viewModel.narrationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
                .disabled(viewModel.narrationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextEditor(text: $viewModel.narrationText)
                .frame(maxWidth: .infinity, minHeight: 320, maxHeight: 320)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .focused($isNarrationFocused)

            if isNarrationPreviewSectionVisible {
                narrationPreviewSection
                    .id("script-preview")
            }

            Color.clear
                .frame(height: 1)
                .id("script-bottom")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var narrationPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview")
                        .font(.headline)
                }
                Spacer()
                if viewModel.isPreparingNarrationPreview {
                    ProgressView()
                        .tint(.purple)
                }
            }

            Button {
                isNarrationFocused = false
                viewModel.buildNarrationPreview()
            } label: {
                HStack {
                    Image(systemName: viewModel.isPreparingNarrationPreview ? "hourglass" : "waveform.badge.magnifyingglass")
                    Text(viewModel.isPreparingNarrationPreview ? "Building Preview..." : "Build Preview")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.purple, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(viewModel.canBuildNarrationPreview ? 1 : 0.6)
            .disabled(!viewModel.canBuildNarrationPreview)

            HStack(spacing: 12) {
                previewControlButton(
                    title: viewModel.isNarrationPreviewPlaying ? "Pause" : "Play",
                    systemImage: viewModel.isNarrationPreviewPlaying ? "pause.fill" : "play.fill",
                    tint: .orange,
                    isEnabled: viewModel.hasNarrationPreview
                ) {
                    isNarrationFocused = false
                    viewModel.toggleNarrationPreviewPlayback()
                }

                previewControlButton(
                    title: "Stop",
                    systemImage: "stop.fill",
                    tint: .red,
                    isEnabled: viewModel.hasNarrationPreview
                ) {
                    isNarrationFocused = false
                    viewModel.stopNarrationPreview()
                }
            }

            if viewModel.narrationPreviewDuration > 0 {
                HStack {
                    Label("Preview ready", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Text(viewModel.narrationPreviewMetaLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Slider(
                    value: Binding(
                        get: { viewModel.narrationPreviewCurrentTime },
                        set: { viewModel.seekNarrationPreview(to: $0) }
                    ),
                    in: 0...max(viewModel.narrationPreviewDuration, 0.1)
                )
                .tint(.purple)

                HStack {
                    Text(formatTime(viewModel.narrationPreviewCurrentTime))
                    Spacer()
                    Text(formatTime(viewModel.narrationPreviewDuration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Current Caption")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    narrationPreviewCaptionStyledText(viewModel.narrationPreviewCaption, style: viewModel.captionStyle)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120, alignment: .topLeading)
                .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func previewControlButton(
        title: String,
        systemImage: String,
        tint: Color,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? tint : .gray.opacity(0.7))
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isEnabled ? Color.white.opacity(0.85) : Color.white.opacity(0.45))
        )
        .opacity(isEnabled ? 1 : 0.75)
        .disabled(!isEnabled)
    }

    private func scriptMetaPill(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.orange.opacity(0.9))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.78), in: Capsule())
    }

    private func inlineScriptActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 42)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.82))
        )
    }

    private func scriptJumpButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.82))
        )
    }

    private var videoAspectRatioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.green.opacity(0.92))
                Text("Choose Your Frame")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            Picker("Aspect Ratio", selection: $viewModel.selectedAspectRatio) {
                ForEach(VideoExporter.AspectRatio.allCases) { ratio in
                    Text(ratio.rawValue).tag(ratio)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.selectedTimingMode == .video)
            .opacity(viewModel.selectedTimingMode == .video ? 0.55 : 1)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.green.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.green.opacity(0.25), lineWidth: 1)
        )
    }

    private var videoQualityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.green.opacity(0.92))
                Text("Final Quality")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            Text("Use `Standard` for faster, safer exports or `High` for a sharper final video.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Final Quality", selection: $viewModel.selectedFinalExportQuality) {
                ForEach(VideoExporter.FinalExportQuality.allCases) { quality in
                    Text(quality.rawValue).tag(quality)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.green.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.green.opacity(0.25), lineWidth: 1)
        )
    }

    private var videoTimingModeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "timeline.selection")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.green.opacity(0.92))
                Text("Video Mode")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            Picker("Video Mode", selection: $viewModel.selectedTimingMode) {
                ForEach(viewModel.selectableVideoTimingModes) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.green.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.green.opacity(0.25), lineWidth: 1)
        )
    }

    private var videoModeExportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.green.opacity(0.92))
                Text("Video Mode Export")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Frame Rate")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Frame Rate", selection: $viewModel.selectedVideoModeFrameRate) {
                    ForEach(VideoExporter.VideoModeFrameRate.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Resolution")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Resolution", selection: $viewModel.selectedVideoModeResolution) {
                    ForEach(VideoExporter.VideoModeResolution.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Quality")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Quality", selection: $viewModel.selectedVideoModeQuality) {
                    ForEach(VideoExporter.VideoModeQuality.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.green.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.green.opacity(0.25), lineWidth: 1)
        )
    }

    private var estimatedExportSpecCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Estimated Export Spec")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(viewModel.estimatedExportSpecLine)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Music")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                musicHeaderCard
                musicActionButtons
                if viewModel.isImportingMusic {
                    musicImportingPill
                }
                if viewModel.isExtractingSoundtrackInBackground {
                    musicSoundtrackExtractingPill
                }
                if !viewModel.soundtrackItems.isEmpty {
                    soundtrackQueueCard
                }
                if viewModel.hasSelectedMusic {
                    clearMusicButton
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if viewModel.hasSelectedMusic {
                soundtrackReviewCard
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Volume In Video")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.musicVolume, in: 0...1)
                    .tint(.blue)
            }
            .padding(14)
            .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 12) {
                Button {
                    viewModel.toggleMusicPlayback()
                } label: {
                    Label(viewModel.isMusicPlaying ? "Pause Music" : "Play Music", systemImage: viewModel.isMusicPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!viewModel.hasSelectedMusic)

                Button {
                    viewModel.stopMusic()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!viewModel.hasSelectedMusic)
            }

            if let shareableMusicURL = viewModel.shareableMusicURL {
                ShareLink(item: shareableMusicURL) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.white.opacity(0.18))
                                .frame(width: 30, height: 30)
                            Image(systemName: "square.and.arrow.up.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Export Soundtrack")
                                .font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.61, blue: 0.48),
                            Color(red: 0.10, green: 0.36, blue: 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .disabled(viewModel.isImportingMusic)
                .opacity(viewModel.isImportingMusic ? 0.55 : 1)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var musicHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.20, green: 0.45, blue: 0.86),
                                    Color(red: 0.12, green: 0.24, blue: 0.62)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Music")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Text(viewModel.importedMusicName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: viewModel.hasSelectedMusic ? "waveform.circle.fill" : "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.88))
                Text(viewModel.hasSelectedMusic ? "Ready for soundtrack mixing" : "No music selected yet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.49, blue: 0.86),
                    Color(red: 0.12, green: 0.27, blue: 0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var musicActionButtons: some View {
        VStack(spacing: 12) {
            Button {
                viewModel.refreshMusicLibrary()
                isMusicBrowserPresented = true
            } label: {
                musicActionLabel(title: "Music Library", systemImage: "music.note.list")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.23, green: 0.58, blue: 0.63),
                        Color(red: 0.11, green: 0.35, blue: 0.39)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .disabled(viewModel.isImportingMusic)
        }
    }

    private var musicImportingPill: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Preparing soundtrack...")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.blue.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.72), in: Capsule())
    }

    private var musicSoundtrackExtractingPill: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Extracting the soundtrack. Stay on Music Library; the Save sheet appears when the file is ready.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.purple.opacity(0.95))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.72), in: Capsule())
    }

    private var soundtrackQueueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Soundtrack Queue")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(viewModel.soundtrackItems.count) track\(viewModel.soundtrackItems.count == 1 ? "" : "s") in order")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.soundtrackItems.count > 1 {
                    Text("Drag to reorder")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 10) {
                ForEach(viewModel.soundtrackItems) { item in
                    soundtrackQueueRow(for: item)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var soundtrackReviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Soundtrack Review")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.formattedMusicDuration(viewModel.musicPlaybackCurrentTime)) / \(viewModel.formattedMusicDuration(viewModel.musicPlaybackDuration))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { viewModel.musicPlaybackCurrentTime },
                    set: { viewModel.seekMusic(to: $0) }
                ),
                in: 0...max(viewModel.musicPlaybackDuration, 0.1)
            )
            .tint(.blue)
            .disabled(viewModel.musicPlaybackDuration <= 0)
        }
        .padding(14)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var clearMusicButton: some View {
        Button {
            viewModel.clearMusicSelection()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.red.opacity(0.92))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Clear Music")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Export with narration only")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.red.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func musicActionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func soundtrackQueueRow(for item: AppViewModel.SoundtrackItem) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "music.note")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.blue.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(viewModel.formattedMusicDuration(item.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.removeSoundtrackItem(withId: item.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.9))
            }
            .buttonStyle(.plain)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
        .onDrag {
            draggedSoundtrackItem = item
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(
            of: [.text],
            delegate: SoundtrackReorderDropDelegate(
                targetItem: item,
                draggedItem: $draggedSoundtrackItem,
                viewModel: viewModel
            )
        )
    }

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Video")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.14))
                            .frame(width: 30, height: 30)
                        Image(systemName: "film.stack")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.green.opacity(0.92))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Format")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(viewModel.selectedAspectRatio.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }

                videoAspectRatioCard
                videoTimingModeCard
                if viewModel.selectedTimingMode == .video || viewModel.selectedTimingMode == .realLife {
                    videoModeExportCard
                }
                if viewModel.selectedTimingMode == .story {
                    videoQualityCard
                }
                estimatedExportSpecCard
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text("Final Mix")
                    .font(.headline)

                Toggle(isOn: $viewModel.includesFinalCaptions) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Include Captions")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(
                            viewModel.includesFinalCaptions
                                ? "Burned into preview sample (~20s) and final video when captions are on."
                                : "Preview sample and final video have no burned-in captions."
                        )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.72))
                    }
                }
                .toggleStyle(.switch)
                .disabled(viewModel.selectedTimingMode == .video)
                .opacity(viewModel.selectedTimingMode == .video ? 0.45 : 1)

                if viewModel.selectedTimingMode != .video, viewModel.includesFinalCaptions {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Caption look")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Caption look", selection: $viewModel.captionStyle) {
                            ForEach(VideoExporter.CaptionStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(
                            viewModel.captionStyle == .normal
                                ? "YouTube-style: semibold white on a soft dark rounded bar."
                                : "Larger rounded bold white type on a tight dim plate, with outline and soft shadow."
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Original Video Sound")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.videoAudioVolume, in: 0...1)
                        .tint(.orange)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Narration")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.narrationVolume, in: 0...1)
                        .tint(.blue)
                        .disabled(viewModel.selectedTimingMode == .video)
                        .opacity(viewModel.selectedTimingMode == .video ? 0.45 : 1)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Music")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.musicVolume, in: 0...1)
                        .tint(.green)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(spacing: 12) {
                if viewModel.isStoryBlockExportBlocking {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.split.3x1.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Edit Story with Pro features has a blocking layout issue. Open the Pro tab and fix the warnings to export.")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.orange.opacity(0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if let poolStoryBlock = viewModel.storyPoolTimelineExportBlockingReason {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 12, weight: .bold))
                        Text(poolStoryBlock)
                            .font(.caption.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Color.orange.opacity(0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if viewModel.selectedTimingMode != .video, let narrationLanguageWarning = viewModel.narrationLanguageWarning {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(narrationLanguageWarning)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.orange.opacity(0.94))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button {
                    deactivateRenderPlaybackForNewRender()
                    viewModel.buildVideoPreview()
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white.opacity(0.18))
                                .frame(width: 34, height: 34)
                            Image(systemName: viewModel.isLoadingMediaSelection ? "hourglass" : "play.rectangle.fill")
                                .font(.system(size: 15, weight: .bold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.isLoadingMediaSelection ? "Loading Media..." : (viewModel.isPreparingVideoPreview ? "Building Preview..." : "Preview Video"))
                                .font(.subheadline.weight(.bold))
                                .lineLimit(1)
                            Text(viewModel.hasPendingPreviewChanges ? "Preview Sample" : "Up to date")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.23, green: 0.49, blue: 0.93),
                            Color(red: 0.13, green: 0.26, blue: 0.67)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .opacity(viewModel.canStartVideoPreviewRender ? 1 : 0.6)
                .disabled(!viewModel.canStartVideoPreviewRender)

                Button {
                    deactivateRenderPlaybackForNewRender()
                    viewModel.buildVideo()
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white.opacity(0.18))
                                .frame(width: 34, height: 34)
                            Image(systemName: viewModel.isLoadingMediaSelection ? "hourglass" : "film.stack")
                                .font(.system(size: 15, weight: .bold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.isLoadingMediaSelection ? "Loading Media..." : (viewModel.isExportingVideo ? "Rendering..." : "Create Video"))
                                .font(.subheadline.weight(.bold))
                            Text(viewModel.hasPendingFinalVideoChanges ? "\(viewModel.selectedFinalExportQuality.rawValue) final export" : "Up to date")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.84))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.63, blue: 0.31),
                            Color(red: 0.07, green: 0.36, blue: 0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .opacity(viewModel.canStartFinalVideoRender ? 1 : 0.6)
                .disabled(!viewModel.canStartFinalVideoRender)

                Group {
                    if let exportedVideoURL = viewModel.exportedVideoURL {
                        ShareLink(item: exportedVideoURL) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.white.opacity(0.18))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Share Video")
                                        .font(.subheadline.weight(.bold))
                                    Text("Exported final file")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.84))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.92, green: 0.53, blue: 0.18),
                                    Color(red: 0.73, green: 0.34, blue: 0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                    } else {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white.opacity(0.18))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Share Video")
                                    .font(.subheadline.weight(.bold))
                                Text("Available after final render")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.gray.opacity(0.45))
                        )
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if viewModel.isExportingVideo || viewModel.isPreparingVideoPreview {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: viewModel.exportProgress, total: 1)
                        .tint(.green)

                    HStack {
                        Text(viewModel.isPreparingVideoPreview ? "Preview progress" : "Rendering progress")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int((viewModel.exportProgress * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        viewModel.stopActiveVideoRender()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red.opacity(0.9))
                }
                .padding(14)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if let displayedVideoURL = activeRenderedVideoURL {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        RenderPlayerViewController(player: renderPreviewPlayer)
                            .frame(maxWidth: .infinity)
                            .frame(height: 320)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        Text(isVideoCardPlayingFinalExport ? "Final Video" : "Preview Sample")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.68), in: Capsule())
                            .padding(12)

                        VStack {
                            HStack {
                                Spacer()

                                Button {
                                    isRenderPlayerExpanded = true
                                } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(10)
                                        .background(Color.black.opacity(0.68), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .padding(12)
                            }

                            Spacer()
                        }
                    }

                    HStack(spacing: 10) {
                        Text("AirPlay")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        AirPlayRoutePicker()
                            .frame(width: 36, height: 36)

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isVideoCardPlayingFinalExport ? "Final Video" : "Preview Video")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let fileSize = formattedFileSize(for: displayedVideoURL) {
                            Text("File Size: \(fileSize)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.65))
                    .frame(maxHeight: .infinity)
                    .overlay {
                        VStack(spacing: 8) {
                            Text((viewModel.isExportingVideo || viewModel.isPreparingVideoPreview) ? "Rendering your video..." : "Your Final Video Preview")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(24)
                    }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var statusSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(viewModel.activeStatusMessage)
                .font(.subheadline)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func narrationPreviewCaptionStyledText(_ text: String, style: VideoExporter.CaptionStyle) -> some View {
        switch style {
        case .normal:
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
        case .stylish:
            Text(text)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 4, x: 0, y: 2)
                .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formattedFileSize(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return nil
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }

    /// Resolved URL for the Video tab player. When the final export is **stale** (`hasPendingFinalVideoChanges`) but a preview file exists, show the preview so a fresh ~20s sample is visible instead of a stale final blocking it.
    private var activeRenderedVideoURL: URL? {
        guard !viewModel.isExportingVideo, !viewModel.isPreparingVideoPreview else {
            return nil
        }
        if viewModel.hasPendingFinalVideoChanges, let preview = viewModel.videoPreviewURL {
            return preview
        }
        return viewModel.exportedVideoURL ?? viewModel.videoPreviewURL
    }

    /// Whether the in-tab / fullscreen player is actually playing the on-disk **final** export (vs a preview sample file).
    private var isVideoCardPlayingFinalExport: Bool {
        guard !viewModel.isExportingVideo, !viewModel.isPreparingVideoPreview,
              let active = activeRenderedVideoURL,
              let final = viewModel.exportedVideoURL else { return false }
        return active.standardizedFileURL == final.standardizedFileURL
    }

    private func updateRenderPreviewPlayer(for url: URL?) {
        renderPreviewPlayer.pause()
        guard let url else {
            renderPreviewPlayer.replaceCurrentItem(with: nil)
            return
        }

        viewModel.prepareVideoPlaybackAudioSession()
        renderPreviewPlayer.allowsExternalPlayback = true
        renderPreviewPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
        renderPreviewPlayer.isMuted = false
        renderPreviewPlayer.volume = 1.0
        renderPreviewPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    private func dismissExpandedRenderPlayer() {
        isRenderPlayerExpanded = false
    }

    private func deactivateRenderPlaybackForNewRender() {
        isRenderPlayerExpanded = false
        renderPreviewPlayer.pause()
        renderPreviewPlayer.seek(to: .zero)
        renderPreviewPlayer.replaceCurrentItem(with: nil)
    }

    private func pauseRenderPlaybackForTabSwitch() {
        isRenderPlayerExpanded = false
        renderPreviewPlayer.pause()
        renderPreviewPlayer.seek(to: .zero)
    }
}

private struct AssignSheetDraftReorderDropDelegate: DropDelegate {
    let targetId: UUID
    @Binding var draggedId: UUID?
    let onReorder: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedId else { return }
        onReorder(draggedId, targetId)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedId = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct MediaReorderDropDelegate: DropDelegate {
    let targetItem: AppViewModel.MediaItem
    @Binding var draggedItem: AppViewModel.MediaItem?
    let viewModel: AppViewModel

    func dropEntered(info: DropInfo) {
        guard let draggedItem else { return }
        viewModel.moveMediaItem(withId: draggedItem.id, before: targetItem.id)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct SoundtrackReorderDropDelegate: DropDelegate {
    let targetItem: AppViewModel.SoundtrackItem
    @Binding var draggedItem: AppViewModel.SoundtrackItem?
    let viewModel: AppViewModel

    func dropEntered(info: DropInfo) {
        guard let draggedItem else { return }
        viewModel.moveSoundtrackItem(withId: draggedItem.id, before: targetItem.id)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// `AVPlayerViewController` with **resizeAspect** for correct letterboxing. Used for Video tab + fullscreen; avoids SwiftUI `VideoPlayer` layout issues with some exports.
private struct RenderPlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
    }
}

/// Big-stage video for **Media** and **Edit → Assign**: resolves PhotoKit / in-flight import URLs (often `nil` right after picking) then shows `LoopingVideoPreview` + Play.
private struct ProjectVideoStageView: View {
    let item: AppViewModel.MediaItem
    let isActive: Bool
    @ObservedObject var viewModel: AppViewModel

    @State private var resolvedPlaybackURL: URL?
    @State private var playbackResolveDidFail = false
    @State private var resolveRetryNonce = 0

    private var playbackURL: URL? {
        item.embeddedVideoFileURL ?? resolvedPlaybackURL
    }

    var body: some View {
        Group {
            if let url = playbackURL {
                LoopingVideoPreview(url: url, placeholder: item.previewImage, isActive: isActive)
                    .id(url.absoluteString)
            } else {
                ZStack {
                    Image(uiImage: item.previewImage)
                        .resizable()
                        .scaledToFit()

                    if isActive {
                        if playbackResolveDidFail {
                            VStack(spacing: 10) {
                                Text("Could not load video")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button {
                                    playbackResolveDidFail = false
                                    resolveRetryNonce += 1
                                } label: {
                                    Text("Try again")
                                        .font(.caption.weight(.semibold))
                                }
                                .tint(.orange)
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            ProgressView()
                                .scaleEffect(1.15)
                                .tint(Color.orange)
                        }
                    }
                }
            }
        }
        .onChange(of: item) { _, newItem in
            if newItem.embeddedVideoFileURL != nil {
                playbackResolveDidFail = false
                resolvedPlaybackURL = nil
            }
        }
        .task(id: "\(item.id.uuidString)-\(isActive)-\(resolveRetryNonce)") {
            await runPlaybackResolvePipeline()
        }
    }

    private func runPlaybackResolvePipeline() async {
        guard isActive, item.isVideo, item.embeddedVideoFileURL == nil else {
            await MainActor.run { playbackResolveDidFail = false }
            return
        }
        await MainActor.run { playbackResolveDidFail = false }
        let url = await viewModel.resolveVideoPreviewPlaybackURL(for: item)
        await MainActor.run {
            if let url {
                resolvedPlaybackURL = url
                playbackResolveDidFail = false
            } else if viewModel.isVideoFileImportInProgress(for: item) {
                playbackResolveDidFail = false
            } else {
                playbackResolveDidFail = true
            }
        }
    }
}

private final class LoopingVideoPlayerStore: ObservableObject {
    let player: AVQueuePlayer
    private let looper: AVPlayerLooper
    /// Template item passed to `AVPlayerLooper`; replicas actually play, so readiness must also follow `looper.status`.
    private let templateItem: AVPlayerItem
    private var itemStatusCancellable: AnyCancellable?
    private var looperStatusCancellable: AnyCancellable?

    @Published private(set) var isReadyForPlayback = false
    @Published private(set) var loadDidFail = false

    /// Big-preview slide is visible.
    private var isSlideActiveForPreview = false

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        self.templateItem = item
        self.looper = looper
        self.player = queuePlayer

        itemStatusCancellable = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshReadinessAndMaybePlay()
            }

        looperStatusCancellable = looper.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshReadinessAndMaybePlay()
            }

        DispatchQueue.main.async { [weak self] in
            self?.refreshReadinessAndMaybePlay()
        }
    }

    /// `AVPlayerLooper` drives real looping; `.ready` often arrives while the template item is still `.unknown`.
    private func refreshReadinessAndMaybePlay() {
        if looper.status == .failed || templateItem.status == .failed {
            loadDidFail = true
            isReadyForPlayback = false
            return
        }
        let canShowVideo = looper.status == .ready || templateItem.status == .readyToPlay
        isReadyForPlayback = canShowVideo
        if canShowVideo {
            loadDidFail = false
        }
        if isSlideActiveForPreview, canShowVideo {
            play()
        }
    }

    func play() {
        player.play()
    }

    func pauseAndReset() {
        player.pause()
        player.seek(to: .zero)
    }

    /// Call from the view when the TabView slide becomes active/inactive.
    func setSlideActiveForPreview(_ active: Bool) {
        isSlideActiveForPreview = active
        if active {
            refreshReadinessAndMaybePlay()
            // Request playback even before `.ready` so AVFoundation starts once the looper/item can play (same as manual Play).
            player.play()
        } else {
            pauseAndReset()
        }
    }
}

/// Muted looping preview for the big Media / Edit-Assign stage. **Every** clip calls `play()` when the item becomes **ready** (consistent auto-start). **Play** during buffering is an optional early start only; it does not change the ready-time behavior (`play()` is safe to repeat).
private struct LoopingVideoPreview: View {
    let url: URL
    let placeholder: UIImage
    let isActive: Bool

    @StateObject private var store: LoopingVideoPlayerStore
    /// Hides the manual **Play** control after the user taps it (spinner only until ready); does not gate auto `play()` when ready.
    @State private var userChoseEarlyPlay = false

    init(url: URL, placeholder: UIImage, isActive: Bool) {
        self.url = url
        self.placeholder = placeholder
        self.isActive = isActive
        _store = StateObject(wrappedValue: LoopingVideoPlayerStore(url: url))
    }

    var body: some View {
        ZStack {
            Image(uiImage: placeholder)
                .resizable()
                .scaledToFit()

            VideoPlayer(player: store.player)
                .allowsHitTesting(false)
                .opacity(store.isReadyForPlayback || userChoseEarlyPlay ? 1 : 0)

            if isActive && !store.isReadyForPlayback && !store.loadDidFail {
                ZStack {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(Color.orange)
                    if !userChoseEarlyPlay {
                        Button {
                            userChoseEarlyPlay = true
                            store.play()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 76, height: 76)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.94, green: 0.46, blue: 0.22),
                                            Color(red: 0.80, green: 0.26, blue: 0.10)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: Circle()
                                )
                                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play video preview")
                    }
                }
            }

            if isActive && store.loadDidFail {
                Text("Could not play preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .onAppear {
            store.setSlideActiveForPreview(isActive)
            if !isActive {
                userChoseEarlyPlay = false
            }
        }
        .onChange(of: isActive) { _, visible in
            store.setSlideActiveForPreview(visible)
            if !visible {
                userChoseEarlyPlay = false
            }
        }
        .onDisappear {
            userChoseEarlyPlay = false
            store.setSlideActiveForPreview(false)
        }
    }
}

private struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = UIColor.systemBlue
        view.activeTintColor = UIColor.systemOrange
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

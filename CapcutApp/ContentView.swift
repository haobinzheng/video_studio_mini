import AVKit
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private struct ShareableFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    enum StudioStep: String, CaseIterable, Identifiable {
        case narration = "Script"
        case photos = "Media"
        case music = "Music"
        case editStory = "Edit"
        case video = "Video"

        var id: String { rawValue }
    }

    @ObservedObject var viewModel: AppViewModel
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
    @State private var previewingStorySoundtrackItemID: UUID?
    @FocusState private var isNarrationFocused: Bool

    private var visibleStudioSteps: [StudioStep] {
        StudioStep.allCases.filter { step in
            step != .editStory || viewModel.isEditStoryProEnabled
        }
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

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            activeSection
                            statusSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .onAppear {
                        scriptScrollProxy = proxy
                    }
                }
            }
            .background(appBackground)
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
            .alert(item: $voicePendingHide) { voice in
                Alert(
                    title: Text("Hide Voice?"),
                    message: Text("\(voice.name) will be removed from the narration voice list. Reload iPhone Voices will bring it back."),
                    primaryButton: .destructive(Text("Hide")) {
                        viewModel.hideVoice(withId: voice.id)
                    },
                    secondaryButton: .cancel()
                )
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
                Task {
                    let extractedURL = await viewModel.extractSoundtrackForExport(from: newValue)
                    await MainActor.run {
                        selectedMusicVideoItem = nil
                        if let extractedURL {
                            extractedSoundtrackShareFile = ShareableFile(url: extractedURL)
                        }
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
                    previewingStorySoundtrackItemID = nil
                }
                if oldStep == .video && newStep != .video {
                    pauseRenderPlaybackForTabSwitch()
                }
                if newStep == .video {
                    updateRenderPreviewPlayer(for: activeRenderedVideoURL)
                }
            }
            .onChange(of: viewModel.videoPreviewURL) { _, newValue in
                updateRenderPreviewPlayer(for: newValue)
            }
            .onChange(of: viewModel.exportedVideoURL) { _, newValue in
                updateRenderPreviewPlayer(for: newValue ?? viewModel.videoPreviewURL)
            }
            .onChange(of: viewModel.isPreparingVideoPreview) { _, isPreparing in
                if isPreparing {
                    deactivateRenderPlaybackForNewRender()
                }
            }
            .onChange(of: viewModel.isExportingVideo) { _, isExporting in
                if isExporting {
                    deactivateRenderPlaybackForNewRender()
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
                    await viewModel.appendSelectedMedia(from: appendedItems, combinedSelection: newItems)
                    await MainActor.run {
                        appendPhotoItems = viewModel.selectedPhotoItems
                    }
                }
            }
            .onChange(of: viewModel.isEditStoryProEnabled) { _, enabled in
                if !enabled, selectedStep == .editStory {
                    selectedStep = .narration
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("App")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("FluxCut")
                    }
                    HStack {
                        Text("Version")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(appVersionLabel)
                    }
                    Text("Manage voices, media, music, and exports from one place. Clear unused data here whenever storage grows too much.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } header: {
                    Text("About")
                }

                Section {
                    Toggle("Show Edit tab", isOn: $viewModel.isEditStoryProEnabled)
                    Text("Turn off to hide the Edit workspace (placeholder for a Pro entitlement later).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Pro (preview)")
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
                    viewModel.importMusicToLibrary(from: urls)
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
                    .disabled(viewModel.isImportingMusic)

                    Button {
                        isMusicLibraryImporterPresented = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.19, green: 0.48, blue: 0.82))
                    .disabled(viewModel.isImportingMusic)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
            }
        }
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

            FullscreenPlayerContainer(player: renderPreviewPlayer)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.exportedVideoURL != nil ? "Final Video" : "Preview Sample")
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
        if selectedStoryParagraphIndices.contains(index) {
            selectedStoryParagraphIndices.remove(index)
        } else if selectedStoryParagraphIndices.isEmpty {
            selectedStoryParagraphIndices = [index]
        } else {
            let lo = selectedStoryParagraphIndices.min() ?? index
            let hi = selectedStoryParagraphIndices.max() ?? index
            if index + 1 == lo || index - 1 == hi {
                selectedStoryParagraphIndices.insert(index)
            } else {
                selectedStoryParagraphIndices = [index]
            }
        }
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

    private func openStoryBlockAssignSheet() {
        guard contiguousStoryParagraphSelection, !selectedStoryParagraphIndices.isEmpty else { return }
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
        isStoryBlockAssignSheetPresented = true
    }

    private func confirmStoryBlockAssignSheet() {
        guard let range = assignSheetRange, !assignSheetDraftMediaIDs.isEmpty else { return }
        viewModel.assignStoryMediaToParagraphRange(range, mediaItemIDs: assignSheetDraftMediaIDs)
        isStoryBlockAssignSheetPresented = false
        assignSheetRange = nil
        assignSheetDraftMediaIDs = []
        selectedStoryParagraphIndices = []
    }

    private func cancelStoryBlockAssignSheet() {
        isStoryBlockAssignSheetPresented = false
        assignSheetRange = nil
        assignSheetDraftMediaIDs = []
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

    private var storyBlockAssignSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let range = assignSheetRange {
                        Text("Paragraphs \(range.lowerBound + 1)–\(range.upperBound + 1)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text("Music for this block will be added in a future update.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)

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

                    if !assignSheetDraftMediaIDs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Assigned to this block (order)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(assignSheetDraftMediaIDs.enumerated()), id: \.offset) { position, mediaID in
                                        if let item = viewModel.mediaItems.first(where: { $0.id == mediaID }) {
                                            VStack(spacing: 4) {
                                                Image(uiImage: item.previewImage)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 64, height: 64)
                                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                Text("\(position + 1)")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

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
                        VStack(spacing: 14) {
                            TabView(selection: $assignSheetSlideIndex) {
                                ForEach(Array(viewModel.mediaItems.enumerated()), id: \.offset) { index, item in
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                                            .fill(Color.black.opacity(0.08))
                                        mediaStage(for: item, isActive: assignSheetSlideIndex == index)
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

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Studio Tip")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("Swipe the stage to review media. Tap a thumbnail to jump here. Double-tap a thumbnail to add or remove it from this block (green number = play order).")
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

    private func storyParagraphRow(index: Int, text: String, blockOrdinal: Int?, isSelected: Bool) -> some View {
        let stripeColor = ((blockOrdinal ?? 0) % 2 == 1) ? Color.blue.opacity(0.35) : Color.purple.opacity(0.32)
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(stripeColor)
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 4) {
                if let b = blockOrdinal {
                    Text("Block \(b)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Unassigned")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.orange.opacity(0.95))
                }
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

    private var editStorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use block timeline (Story mode)", isOn: $viewModel.storyUsesBlockTimeline)
                    .font(.subheadline.weight(.semibold))
                Text("Paragraphs (blank-line separated) map to media. Export uses paragraph-aligned narration and per-block visuals when the layout is valid.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reset to one block (all paragraphs, all media)") {
                    viewModel.resetStoryEditBlocksToDefault()
                    selectedStoryParagraphIndices = []
                }
                .font(.caption.weight(.semibold))
                .disabled(!viewModel.storyUsesBlockTimeline || viewModel.storyScriptParagraphs.isEmpty || viewModel.mediaItems.isEmpty)
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Music queue")
                    .font(.headline)
                Text("Same order as the Music tab. Final export still uses the combined mix from Music for now.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if viewModel.soundtrackItems.isEmpty {
                    Text("No tracks in the queue yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.soundtrackItems) { item in
                        HStack {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                if previewingStorySoundtrackItemID == item.id, viewModel.isMusicPlaying {
                                    viewModel.toggleMusicPlayback()
                                } else {
                                    viewModel.previewStorySoundtrackItem(item)
                                    previewingStorySoundtrackItemID = item.id
                                    if !viewModel.isMusicPlaying {
                                        viewModel.toggleMusicPlayback()
                                    }
                                }
                            } label: {
                                Image(systemName: previewingStorySoundtrackItemID == item.id && viewModel.isMusicPlaying ? "pause.fill" : "play.fill")
                                    .font(.body.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Script paragraphs")
                    .font(.headline)
                Text("Tap paragraphs to select a contiguous range, then tap Assign to open the media picker. Double-tap thumbnails in the sheet to add or remove clips in play order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .disabled(!contiguousStoryParagraphSelection || selectedStoryParagraphIndices.isEmpty)

                    Button {
                        viewModel.clearAllStoryEditBlocks()
                        selectedStoryParagraphIndices = []
                    } label: {
                        Label("Clear", systemImage: "eraser")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.storyUsesBlockTimeline || viewModel.storyEditBlocks.isEmpty)
                }
                if viewModel.storyScriptParagraphs.isEmpty {
                    Text("No paragraphs yet—add text in Script with blank lines between ideas.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(viewModel.storyScriptParagraphs.enumerated()), id: \.offset) { index, text in
                        Button {
                            toggleStoryParagraphSelection(index)
                        } label: {
                            storyParagraphRow(
                                index: index,
                                text: text,
                                blockOrdinal: viewModel.storyBlockOrdinal(forParagraphIndex: index),
                                isSelected: selectedStoryParagraphIndices.contains(index)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                        Text("Swipe to review your media, then drag thumbnails to reorder the sequence before you move on to script, music, and export.")
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
        case let .video(url, _, _):
            if let url {
                LoopingVideoPreview(url: url, placeholder: item.previewImage, isActive: isActive)
            } else {
                Image(uiImage: item.previewImage)
                    .resizable()
                    .scaledToFit()
            }
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
                                HStack(spacing: 10) {
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
                                            Spacer()
                                            if option.id == viewModel.selectedVoiceIdentifier {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                        .padding(12)
                                        .background(
                                            Color.white.opacity(option.id == viewModel.selectedVoiceIdentifier ? 0.95 : 0.72),
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    Menu {
                                        Button(role: .destructive) {
                                            voicePendingHide = option
                                        } label: {
                                            Label("Hide Voice", systemImage: "eye.slash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(Color.secondary.opacity(0.85))
                                            .padding(4)
                                    }
                                    .disabled(!viewModel.canHideVoices)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                    .frame(maxHeight: 180)
                }

                Text("Use the more button to hide a voice. Reload iPhone Voices brings hidden voices back.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .onAppear {
                viewModel.loadAvailableVoicesIfNeeded()
            }
            .disabled(viewModel.availableVoices.isEmpty)

            HStack(spacing: 10) {
                scriptMetaPill(
                    title: "Length",
                    value: "\(viewModel.narrationText.count) characters",
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
                .onTapGesture {
                    isNarrationFocused = true
                }

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
        .contentShape(Rectangle())
        .onTapGesture {
            isNarrationFocused = false
        }
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
                ForEach(VideoExporter.TimingMode.allCases) { mode in
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
                        Text(viewModel.includesFinalCaptions ? "Captions on for final video" : "Final video without captions")
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
                        Text("Edit has a blocking layout issue. Open the Edit tab and fix the warnings to export.")
                            .font(.caption.weight(.semibold))
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
                }
                .padding(14)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if let displayedVideoURL = activeRenderedVideoURL {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        VideoPlayer(player: renderPreviewPlayer)
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        Text(viewModel.exportedVideoURL != nil ? "Final Video" : "Preview Sample")
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
                        Text(viewModel.exportedVideoURL != nil ? "Final Video" : "Preview Video")
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

    private var activeRenderedVideoURL: URL? {
        guard !viewModel.isExportingVideo, !viewModel.isPreparingVideoPreview else {
            return nil
        }

        return viewModel.exportedVideoURL ?? viewModel.videoPreviewURL
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

private struct FullscreenPlayerContainer: UIViewControllerRepresentable {
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

private final class LoopingVideoPlayerStore: ObservableObject {
    let player: AVQueuePlayer
    private let looper: AVPlayerLooper

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none
        self.looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        self.player = queuePlayer
    }

    func setActive(_ isActive: Bool) {
        if isActive {
            player.play()
        } else {
            player.pause()
            player.seek(to: .zero)
        }
    }
}

private struct LoopingVideoPreview: View {
    let url: URL
    let placeholder: UIImage
    let isActive: Bool

    @StateObject private var store: LoopingVideoPlayerStore

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
        }
        .onAppear {
            store.setActive(isActive)
        }
        .onChange(of: isActive) { _, newValue in
            store.setActive(newValue)
        }
        .onDisappear {
            store.setActive(false)
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

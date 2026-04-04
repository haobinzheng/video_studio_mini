import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    enum StudioStep: String, CaseIterable, Identifiable {
        case narration = "Script"
        case photos = "Media"
        case music = "Music"
        case video = "Video"

        var id: String { rawValue }
    }

    @ObservedObject var viewModel: AppViewModel
    @State private var isMusicImporterPresented = false
    @State private var selectedMusicVideoItem: PhotosPickerItem?
    @State private var selectedStep: StudioStep = .narration
    @State private var isVoiceListExpanded = false
    @State private var draggedMediaItem: AppViewModel.MediaItem?
    @State private var renderPreviewPlayer = AVPlayer()
    @State private var scriptScrollProxy: ScrollViewProxy?
    @State private var isSettingsPresented = false
    @State private var isMusicBrowserPresented = false
    @FocusState private var isNarrationFocused: Bool

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
            .fileImporter(
                isPresented: $isMusicImporterPresented,
                allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav, .movie, .video, .mpeg4Movie, .quickTimeMovie]
            ) { result in
                if case let .success(url) = result {
                    viewModel.importMusic(from: url)
                    selectedStep = .music
                }
            }
            .onChange(of: selectedMusicVideoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    await viewModel.importMusicVideo(from: newValue)
                    await MainActor.run {
                        selectedMusicVideoItem = nil
                        selectedStep = .music
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
                if oldStep == .video && newStep != .video {
                    renderPreviewPlayer.pause()
                    renderPreviewPlayer.seek(to: .zero)
                }
            }
            .onChange(of: viewModel.videoPreviewURL) { _, newValue in
                updateRenderPreviewPlayer(for: newValue)
            }
            .onChange(of: viewModel.exportedVideoURL) { _, newValue in
                updateRenderPreviewPlayer(for: newValue ?? viewModel.videoPreviewURL)
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
            ForEach(StudioStep.allCases) { step in
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
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.94, green: 0.46, blue: 0.22),
                                        Color(red: 0.79, green: 0.23, blue: 0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)

                        Image(systemName: "film.stack.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text("FluxCut Studio")
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
                        Text("FluxCut Studio")
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
                        Text("\(viewModel.musicLibraryItems.count) built-in tracks")
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
                }

                ForEach(viewModel.musicLibraryItems) { item in
                    Button {
                        viewModel.selectMusicLibraryItem(item)
                        isMusicBrowserPresented = false
                    } label: {
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
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Music Library")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.refreshMusicLibrary()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isMusicBrowserPresented = false
                    }
                }
            }
        }
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
        case .video:
            videoSection
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Media")
                    .font(.title2.weight(.semibold))
                Spacer()
                PhotosPicker(
                    selection: $viewModel.selectedPhotoItems,
                    maxSelectionCount: nil,
                    selectionBehavior: .ordered,
                    matching: .any(of: [.images, .videos])
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
                    .overlay {
                        Text("Your selected media will appear here.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
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
                            .overlay(alignment: .bottomTrailing) {
                                HStack(spacing: 8) {
                                    Text("#\(index + 1)")
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
        case let .video(url, _):
            LoopingVideoPreview(url: url, placeholder: item.previewImage, isActive: isActive)
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
            Text("\(index + 1)")
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
                        Text("Voice")
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

            DisclosureGroup(isExpanded: $isVoiceListExpanded) {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.availableVoices) { option in
                            HStack(spacing: 10) {
                                Button {
                                    viewModel.selectedVoiceIdentifier = option.id
                                    isVoiceListExpanded = false
                                    isNarrationFocused = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(option.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Text("\(option.qualityLabel) • \(option.languageLabel)\(option.isFallback ? " • Fallback" : "")")
                                                .font(.caption)
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

                                Button {
                                    viewModel.hideVoice(withId: option.id)
                                } label: {
                                    Image(systemName: "trash.circle.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(viewModel.canHideVoices ? Color.red.opacity(0.88) : Color.gray.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .disabled(!viewModel.canHideVoices)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .frame(maxHeight: 180)
            } label: {
                HStack {
                    Text("Selected voice")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(viewModel.selectedVoiceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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

                inlineScriptActionButton(title: "Introduction", systemImage: "text.badge.plus") {
                    viewModel.loadSampleNarration()
                }
            }
            .disabled(viewModel.isPreparingNarrationPreview)

            HStack(spacing: 10) {
                scriptJumpButton(title: "Top", systemImage: "arrow.up.to.line") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scriptScrollProxy?.scrollTo("script-top", anchor: .top)
                    }
                }

                scriptJumpButton(title: "Preview", systemImage: "waveform.path.ecg") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scriptScrollProxy?.scrollTo("script-preview", anchor: .top)
                    }
                }

                scriptJumpButton(title: "Bottom", systemImage: "arrow.down.to.line") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scriptScrollProxy?.scrollTo("script-bottom", anchor: .bottom)
                    }
                }
            }

            TextEditor(text: $viewModel.narrationText)
                .frame(maxWidth: .infinity, minHeight: 320, maxHeight: 320)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .focused($isNarrationFocused)

            narrationPreviewSection
                .id("script-preview")

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
            .disabled(viewModel.isPreparingNarrationPreview)

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
                    Text(viewModel.narrationPreviewCaption)
                        .font(.body.weight(.semibold))
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

                VStack(spacing: 12) {
                    Button {
                        isMusicImporterPresented = true
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.white.opacity(0.18))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "waveform.badge.plus")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import Audio")
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
                                Color(red: 0.20, green: 0.45, blue: 0.86),
                                Color(red: 0.12, green: 0.24, blue: 0.62)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .disabled(viewModel.isImportingMusic)
                    .opacity(viewModel.isImportingMusic ? 0.55 : 1)

                    Button {
                        viewModel.refreshMusicLibrary()
                        isMusicBrowserPresented = true
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.white.opacity(0.18))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Music Library")
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
                                Color(red: 0.23, green: 0.58, blue: 0.63),
                                Color(red: 0.11, green: 0.35, blue: 0.39)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .disabled(viewModel.isImportingMusic)

                    PhotosPicker(
                        selection: $selectedMusicVideoItem,
                        matching: .videos
                    ) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.white.opacity(0.18))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "film.badge.plus")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Extract Soundtracks")
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
                                Color(red: 0.30, green: 0.56, blue: 0.82),
                                Color(red: 0.13, green: 0.31, blue: 0.52)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .disabled(viewModel.isImportingMusic)
                    .opacity(viewModel.isImportingMusic ? 0.55 : 1)
                }

                if viewModel.isImportingMusic {
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

                if viewModel.hasSelectedMusic {
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                if viewModel.selectedTimingMode == .video {
                    videoModeExportCard
                }
                if viewModel.selectedTimingMode != .video {
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
                .disabled(viewModel.selectedTimingMode != .story)
                .opacity(viewModel.selectedTimingMode == .story ? 1 : 0.45)

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
                Button {
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
                    renderPreviewPlayer.pause()
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

            if let displayedVideoURL = viewModel.exportedVideoURL ?? viewModel.videoPreviewURL {
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
            Text(viewModel.statusMessage)
                .font(.subheadline)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(.white)
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

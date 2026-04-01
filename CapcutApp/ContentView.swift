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
    @State private var selectedStep: StudioStep = .narration
    @State private var isVoiceListExpanded = false
    @State private var draggedMediaItem: AppViewModel.MediaItem?
    @State private var renderPreviewPlayer = AVPlayer()
    @FocusState private var isNarrationFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    brandHeader
                    stepPicker
                    activeSection
                    statusSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(appBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $isMusicImporterPresented,
                allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav]
            ) { result in
                if case let .success(url) = result {
                    viewModel.importMusic(from: url)
                    selectedStep = .music
                }
            }
            .onChange(of: selectedStep) { oldStep, newStep in
                if oldStep == .narration && newStep != .narration {
                    viewModel.stopLiveNarrationSilently()
                }
                if oldStep == .music && newStep != .music {
                    viewModel.stopMusicSilently()
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
        HStack(spacing: 14) {
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
                    .frame(width: 56, height: 56)

                Image(systemName: "film.stack.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("FluxCut Studio")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Script, media, music, and video in one fast studio flow.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                Text("Import photos and videos in order, then review and shape the sequence of your story.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.77, green: 0.28, blue: 0.12),
                                Color(red: 0.48, green: 0.16, blue: 0.08)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

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
            Text("Script")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text("Write your script, choose a voice, and preview the narration before you render the final video.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.77, green: 0.28, blue: 0.12),
                                Color(red: 0.48, green: 0.16, blue: 0.08)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

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

            DisclosureGroup(isExpanded: $isVoiceListExpanded) {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.availableVoices) { option in
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

            if let selectedVoice = viewModel.availableVoices.first(where: { $0.id == viewModel.selectedVoiceIdentifier }),
               selectedVoice.isFallback {
                Text("Premium Apple voices are not fully exposed here, so FluxCut is using the best available fallback voice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                .disabled(viewModel.narrationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

            HStack(spacing: 10) {
                inlineScriptActionButton(
                    title: viewModel.isSpeaking ? "Stop Voice" : "Play Voice",
                    systemImage: viewModel.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill"
                ) {
                    viewModel.playNarration()
                }

                inlineScriptActionButton(title: "Sample", systemImage: "text.badge.plus") {
                    viewModel.loadSampleNarration()
                }
            }

            TextEditor(text: $viewModel.narrationText)
                .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .focused($isNarrationFocused)

            narrationPreviewSection
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var narrationPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview")
                        .font(.headline)
                    Text("Optional: build a seekable preview to inspect subtitle timing before export.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.isPreparingNarrationPreview {
                    ProgressView()
                        .tint(.purple)
                }
            }

            Text(viewModel.narrationPreviewSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                viewModel.buildNarrationPreview()
            } label: {
                HStack {
                    Image(systemName: viewModel.isPreparingNarrationPreview ? "hourglass" : "waveform.badge.magnifyingglass")
                    Text(viewModel.isPreparingNarrationPreview ? "Building Preview..." : "Build Preview")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("Testing tool")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
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
                    viewModel.toggleNarrationPreviewPlayback()
                }

                previewControlButton(
                    title: "Stop",
                    systemImage: "stop.fill",
                    tint: .red,
                    isEnabled: viewModel.hasNarrationPreview
                ) {
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

                Text(viewModel.narrationPreviewCaption)
                    .font(.body.weight(.semibold))
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .padding(14)
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
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.82))
        )
    }

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Music")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text("Import `.mp3`, `.m4a`, or `.wav` music, then set the level used in the final video mix.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.77, green: 0.28, blue: 0.12),
                                Color(red: 0.48, green: 0.16, blue: 0.08)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.14))
                            .frame(width: 30, height: 30)
                        Image(systemName: "music.note")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.blue.opacity(0.92))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Current Track")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(viewModel.importedMusicName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

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
                            Text("Import Music")
                                .font(.subheadline.weight(.semibold))
                            Text("MP3, M4A, WAV")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.82))
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Built-In Soundtracks")
                    .font(.headline)
                Picker("Demo Track", selection: $viewModel.selectedDemoTrackID) {
                    ForEach(viewModel.demoTracks) { track in
                        Text("\(track.name) • \(track.description)").tag(track.id)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onChange(of: viewModel.selectedDemoTrackID) { _, _ in
                viewModel.loadSelectedBundledMusic()
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
                Text("Choose the final format, start the render, and review your finished video in one place.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.20, green: 0.56, blue: 0.28),
                                Color(red: 0.08, green: 0.34, blue: 0.18)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

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

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.split.3x1")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.green.opacity(0.92))
                        Text("Choose Your Frame")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                    }

                    Text("Pick `9:16` for vertical stories or `4:3` for a wider studio-style frame.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Aspect Ratio", selection: $viewModel.selectedAspectRatio) {
                        ForEach(VideoExporter.AspectRatio.allCases) { ratio in
                            Text(ratio.rawValue).tag(ratio)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text("Final Mix")
                    .font(.headline)

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
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Music")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.musicVolume, in: 0...1)
                        .tint(.green)
                }

                Text("Adjust the final mix here, then use Preview Video to test the rendered balance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                            Text("Quick 8-second sample")
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
                .opacity((viewModel.isExportingVideo || viewModel.isPreparingVideoPreview || viewModel.isLoadingMediaSelection) ? 0.6 : 1)
                .disabled(viewModel.isExportingVideo || viewModel.isPreparingVideoPreview || viewModel.isLoadingMediaSelection)

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
                            Text("\(viewModel.selectedFinalExportQuality.rawValue) final export")
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
                .opacity((viewModel.isExportingVideo || viewModel.isPreparingVideoPreview || viewModel.isLoadingMediaSelection) ? 0.6 : 1)
                .disabled(viewModel.isExportingVideo || viewModel.isPreparingVideoPreview || viewModel.isLoadingMediaSelection)

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
                    VideoPlayer(player: renderPreviewPlayer)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.exportedVideoURL != nil ? "Final Video" : "Preview Render")
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

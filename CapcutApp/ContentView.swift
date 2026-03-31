import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    enum StudioStep: String, CaseIterable, Identifiable {
        case photos = "Photos"
        case narration = "Script"
        case music = "Music"
        case video = "Video"

        var id: String { rawValue }
    }

    @ObservedObject var viewModel: AppViewModel
    @State private var isMusicImporterPresented = false
    @State private var selectedStep: StudioStep = .narration
    @State private var isVoiceListExpanded = false
    @State private var isScriptToolsExpanded = false
    @FocusState private var isNarrationFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    compactHeader
                    stepPicker
                    activeSection
                    statusSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(appBackground)
            .navigationTitle("Studio")
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
        }
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CapCut Mini Studio")
                .font(.title.weight(.bold))
            Text("Pick photos, voice, music, and export your video.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
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
                Text("1. Media")
                    .font(.title2.weight(.semibold))
                Spacer()
                PhotosPicker(
                    selection: $viewModel.selectedPhotoItems,
                    matching: .any(of: [.images, .videos])
                ) {
                    Label("Choose Media", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            Text("Pick photos or muted video clips, then move to Narration, Music, and Video.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.mediaItems.isEmpty {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.65))
                    .frame(maxHeight: .infinity)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 40))
                            Text("Your selected photos and videos will appear here.")
                                .font(.headline)
                        }
                        .foregroundStyle(.secondary)
                    }
            } else {
                VStack(spacing: 14) {
                    Image(uiImage: viewModel.mediaItems[viewModel.currentSlideIndex].previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 280)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if viewModel.mediaItems[viewModel.currentSlideIndex].isVideo {
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
                            Text("\(viewModel.currentSlideIndex + 1)/\(viewModel.mediaItems.count)")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.55), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(14)
                        }

                    HStack(spacing: 12) {
                        Button {
                            viewModel.previousSlide()
                        } label: {
                            Label("Previous", systemImage: "chevron.left")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            viewModel.nextSlide()
                        } label: {
                            Label("Next", systemImage: "chevron.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var narrationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("2. Text to Speech")
                .font(.title2.weight(.semibold))

            Text("Write your script, pick a voice, then build a seekable preview before exporting the final video.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Voice quality: \(viewModel.selectedVoiceName)")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                Text("Enhanced or Premium Apple voices are not currently exposed here, so the app is showing fallback voices instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Script length: \(viewModel.narrationText.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.clearNarration()
                } label: {
                    Label("Clear Text", systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.narrationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextEditor(text: $viewModel.narrationText)
                .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .focused($isNarrationFocused)

            narrationPreviewSection
            scriptToolsSection
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
                    tint: .orange
                ) {
                    viewModel.toggleNarrationPreviewPlayback()
                }

                previewControlButton(
                    title: "Stop",
                    systemImage: "stop.fill",
                    tint: .gray
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

    private var scriptToolsSection: some View {
        DisclosureGroup(isExpanded: $isScriptToolsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    scriptToolButton(title: "Paste", systemImage: "doc.on.clipboard") {
                        viewModel.pasteNarrationFromClipboard()
                    }

                    scriptToolButton(title: "Sample", systemImage: "text.badge.plus") {
                        viewModel.loadSampleNarration()
                    }
                }

                HStack(spacing: 10) {
                    scriptToolButton(
                        title: viewModel.isSpeaking ? "Stop Voice" : "Play Voice",
                        systemImage: viewModel.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill"
                    ) {
                        viewModel.playNarration()
                    }

                    scriptToolButton(title: "Clear", systemImage: "xmark.circle") {
                        viewModel.clearNarration()
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Script Tools")
                .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func previewControlButton(
        title: String,
        systemImage: String,
        tint: Color,
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
        .foregroundStyle(tint)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.85))
        )
    }

    private func scriptToolButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
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
            Text("3. Background Music")
                .font(.title2.weight(.semibold))

            Text("Choose one of the built-in sample tracks, or import your own audio file later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Selected Track")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(viewModel.importedMusicName)
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    isMusicImporterPresented = true
                } label: {
                    Label("Import From Files", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Built-in Sample Music")
                    .font(.headline)
                Picker("Demo Track", selection: $viewModel.selectedDemoTrackID) {
                    ForEach(viewModel.demoTracks) { track in
                        Text("\(track.name) • \(track.description)").tag(track.id)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    viewModel.loadSelectedBundledMusic()
                } label: {
                    Label("Use Selected Sample Track", systemImage: "music.note.list")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Volume")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.musicVolume, in: 0...1)
                    .tint(.blue)
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.toggleMusicPlayback()
                } label: {
                    Label(viewModel.isMusicPlaying ? "Pause Music" : "Play Music", systemImage: viewModel.isMusicPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button {
                    viewModel.stopMusic()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("4. Create Video")
                .font(.title2.weight(.semibold))

            Text("This step builds narration and captions automatically, then renders your selected media with background music if available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Aspect Ratio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Aspect Ratio", selection: $viewModel.selectedAspectRatio) {
                    ForEach(VideoExporter.AspectRatio.allCases) { ratio in
                        Text(ratio.rawValue).tag(ratio)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.buildVideo()
                } label: {
                    Label(
                        viewModel.isLoadingMediaSelection
                            ? "Loading Media..."
                            : (viewModel.isExportingVideo ? "Rendering..." : "Create Video"),
                        systemImage: viewModel.isLoadingMediaSelection ? "hourglass" : "film.stack"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(viewModel.isExportingVideo || viewModel.isLoadingMediaSelection)

                if let exportedVideoURL = viewModel.exportedVideoURL {
                    ShareLink(item: exportedVideoURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let exportedVideoURL = viewModel.exportedVideoURL {
                VideoPlayer(player: AVPlayer(url: exportedVideoURL))
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text(exportedVideoURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.65))
                    .frame(maxHeight: .infinity)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "video.badge.waveform")
                                .font(.system(size: 40))
                            Text("Your rendered video will appear here.")
                                .font(.headline)
                        }
                        .foregroundStyle(.secondary)
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
}

import PhotosUI
import SwiftUI
import UIKit

private struct WatermarkStylePreviewCardSizeKey: PreferenceKey {
    static var defaultValue: CGSize = CGSize(width: 1, height: 1)
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Watermark options (reference: Settings row → full-screen style page with import and corner position).
struct WatermarkSettingsDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var importPickerItem: PhotosPickerItem?
    @State private var stylePreviewCardSize: CGSize = CGSize(width: 1, height: 1)
    @FocusState private var nameFieldFocused: Bool

    private var isWatermarkProUnlocked: Bool { viewModel.isEditStoryProEnabled }

    var body: some View {
        List {
            if !isWatermarkProUnlocked {
                Section {
                    Text("Adding a watermark to exports is a FluxCut Pro feature. Purchase FluxCut Pro in Settings (FluxCut Pro), then you can use watermarks in exported videos.")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
            Section {
                Toggle("Add Watermark", isOn: $viewModel.isWatermarkEnabled)
                    .disabled(!isWatermarkProUnlocked)
            } footer: {
                Text("When on, a text or image layer is composited on exported preview and final videos. Requires Pro.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Format", selection: $viewModel.watermarkKind) {
                    ForEach(AppViewModel.WatermarkKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!isWatermarkProUnlocked)

                NavigationLink {
                    watermarkNameEditor
                } label: {
                    HStack {
                        Text("Watermark name")
                        Spacer()
                        Text(viewModel.watermarkText.isEmpty ? "—" : String(viewModel.watermarkText.prefix(28)))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .disabled(!isWatermarkProUnlocked)
            } header: {
                Text("Name")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Mark strength")
                        Spacer()
                        Text(watermarkOpacityLabel)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $viewModel.watermarkOpacity,
                        in: 0.1...1.0,
                        step: 0.01
                    )
                    .disabled(!isWatermarkProUnlocked)
                }
                if isWatermarkProUnlocked {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Size")
                            ProBadgePill()
                            Spacer()
                            Text(watermarkSizeLabel)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: $viewModel.watermarkSizeScale,
                            in: 0.35...4.0,
                            step: 0.05
                        )
                    }
                }
            } header: {
                Text("Appearance")
            } footer: {
                Group {
                    if isWatermarkProUnlocked {
                        Text("Lower = more see-through; higher = more solid (10–100%). Size: 35–400% of the default, capped by output resolution. Image marks get a light shadow for contrast. Pro feature.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Pro is required to adjust appearance.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                stylePreview
                importWatermarkControl
            } header: {
                Text("Style")
            } footer: {
                Text(
                    "The logo scales with final resolution (about 70px on the short side at 1080p at 100% size before the Size control). Inset from edges is about 10–28 output pixels. Small source images are scaled up to match the target. Use a PNG with an alpha channel for a clean mark with no background box. Position applies to text and image."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Section {
                positionRow
            } header: {
                Text("Position")
            }
        }
        .navigationTitle("Watermark")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.reconcileProWatermarkGate() }
        .onChange(of: importPickerItem) { _, newValue in
            Task {
                guard let item = newValue else { return }
                defer { importPickerItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    if let image = UIImage(data: data), let png = image.pngData() {
                        _ = try? viewModel.importWatermarkImageData(png)
                    } else {
                        _ = try? viewModel.importWatermarkImageData(data)
                    }
                }
            }
        }
    }

    private var watermarkNameEditor: some View {
        Form {
            Section {
                TextField("Watermark name", text: $viewModel.watermarkText, axis: .vertical)
                    .focused($nameFieldFocused)
            } footer: {
                Text("This text is shown when the format is Text, and as a stand-in in the style preview for image mode when no image is set.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Watermark name")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var watermarkOpacityLabel: String {
        String(format: "%.0f%%", viewModel.watermarkOpacity * 100)
    }

    private var watermarkSizeLabel: String {
        String(format: "%.0f%%", viewModel.watermarkSizeScale * 100)
    }

    private var stylePreview: some View {
        let ratio: CGFloat = 16 / 9
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(white: 0.19),
                        Color(white: 0.10),
                        Color(white: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(ratio, contentMode: .fit)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: WatermarkStylePreviewCardSizeKey.self, value: g.size)
                }
            )
            .onPreferenceChange(WatermarkStylePreviewCardSizeKey.self) { stylePreviewCardSize = $0 }
            .overlay(alignment: previewContentAlignment) {
                watermarkMarkContent(previewSize: stylePreviewCardSize)
                    .padding(10)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }

    private var previewContentAlignment: Alignment {
        switch viewModel.watermarkPosition {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    @ViewBuilder
    private func watermarkMarkContent(previewSize: CGSize) -> some View {
        let w = max(1, previewSize.width)
        let h = max(1, previewSize.height)
        let safeSize = CGSize(width: w, height: h)
        let m = min(w, h)
        let sizeScale: CGFloat = isWatermarkProUnlocked ? CGFloat(viewModel.watermarkSizeScale) : 1.0
        let maxImageSpan = VideoExporter.referenceWatermarkImageMaxSpanForPreview(
            previewSize: safeSize,
            sizeScale: sizeScale
        )
        let textFont = max(8, min(52, 18 * m / 1080 * sizeScale))
        Group {
            if viewModel.watermarkKind == .image, viewModel.hasWatermarkImageOnDisk, let u = viewModel.watermarkImageURLForExport(),
               let img = UIImage(contentsOfFile: u.path) {
                Image(uiImage: img)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: maxImageSpan, maxHeight: maxImageSpan)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            } else {
                let t = viewModel.watermarkText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    Text(t)
                        .font(.system(size: textFont, weight: .semibold, design: .default))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                        .multilineTextAlignment(leadingAlignmentForText)
                        .frame(maxWidth: w * 0.48, alignment: markTextBlockAlignment)
                } else {
                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .opacity(viewModel.watermarkOpacity)
    }

    /// Clips/aligns the text block in the style preview to match each corner.
    private var markTextBlockAlignment: Alignment {
        switch viewModel.watermarkPosition {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    private var leadingAlignmentForText: TextAlignment {
        switch viewModel.watermarkPosition {
        case .topLeft, .bottomLeft: return .leading
        case .topRight, .bottomRight: return .trailing
        }
    }

    private var importWatermarkControl: some View {
        HStack(alignment: .top, spacing: 14) {
            PhotosPicker(selection: $importPickerItem, matching: .images) {
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 80, height: 80)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title2)
                                    .foregroundStyle(.primary)
                                Text("Import\nwatermark")
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isWatermarkProUnlocked)
            if viewModel.hasWatermarkImageOnDisk, let u = viewModel.watermarkImageURLForExport() {
                VStack(alignment: .leading, spacing: 6) {
                    if let img = UIImage(contentsOfFile: u.path) {
                        Image(uiImage: img)
                            .renderingMode(.original)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(maxHeight: 100)
                    }
                    Button("Remove image", role: .destructive) {
                        viewModel.clearWatermarkImageFile()
                    }
                    .font(.subheadline)
                    .disabled(!isWatermarkProUnlocked)
                }
            } else {
                Text("Use a transparent PNG. Alpha is preserved; no background is added in export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var positionRow: some View {
        HStack(spacing: 6) {
            ForEach(VideoExporter.WatermarkSettings.Anchor.allCases) { anchor in
                let selected = viewModel.watermarkPosition == anchor
                Button {
                    viewModel.watermarkPosition = anchor
                } label: {
                    VStack(spacing: 2) {
                        ForEach(anchorLineLabels(for: anchor), id: \.self) { line in
                            Text(line)
                                .font(.caption2.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                selected ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isWatermarkProUnlocked)
            }
        }
    }

    private func anchorLineLabels(for anchor: VideoExporter.WatermarkSettings.Anchor) -> [String] {
        switch anchor {
        case .topLeft: return ["Top", "Left"]
        case .topRight: return ["Top", "Right"]
        case .bottomLeft: return ["Bottom", "Left"]
        case .bottomRight: return ["Bottom", "Right"]
        }
    }
}

private struct ProBadgePill: View {
    var body: some View {
        Text("Pro")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.2))
            )
    }
}

import SwiftUI

enum FluxCutLogoStyle: String, CaseIterable, Identifiable {
    case hiddenFRibbon
    case flowRibbon
    case cutRibbon
    case treeFlow

    var id: String { rawValue }
}

enum FluxCutBrandLibrary {
    static let activeLogoStyle: FluxCutLogoStyle = .treeFlow
}

struct FluxCutLogoMark: View {
    var size: CGFloat
    var style: FluxCutLogoStyle = FluxCutBrandLibrary.activeLogoStyle

    var body: some View {
        ZStack {
            background

            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height

                switch style {
                case .hiddenFRibbon:
                    hiddenFRibbon(in: CGSize(width: w, height: h))
                case .flowRibbon:
                    flowRibbon(in: CGSize(width: w, height: h))
                case .cutRibbon:
                    cutRibbon(in: CGSize(width: w, height: h))
                case .treeFlow:
                    treeFlow(in: CGSize(width: w, height: h))
                }
            }
            .padding(size * 0.14)
        }
        .frame(width: size, height: size)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.10, blue: 0.19),
                        Color(red: 0.10, green: 0.19, blue: 0.30)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func hiddenFRibbon(in size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        let bandHeight = h * 0.18
        let ribbonGradient = LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.66, blue: 0.24),
                Color(red: 0.94, green: 0.38, blue: 0.18),
                Color(red: 0.20, green: 0.67, blue: 0.77)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        return ZStack {
            RoundedRectangle(cornerRadius: bandHeight * 0.46, style: .continuous)
                .fill(ribbonGradient)
                .frame(width: w * 0.62, height: bandHeight)
                .offset(x: w * 0.08, y: h * 0.18)

            RoundedRectangle(cornerRadius: bandHeight * 0.46, style: .continuous)
                .fill(ribbonGradient)
                .frame(width: w * 0.56, height: bandHeight)
                .offset(x: w * 0.04, y: h * 0.47)

            RoundedRectangle(cornerRadius: bandHeight * 0.46, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.66, blue: 0.24),
                            Color(red: 0.94, green: 0.38, blue: 0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: bandHeight, height: h * 0.50)
                .offset(x: -w * 0.18, y: h * 0.12)

            FluxCutFoldShape()
                .fill(Color.black.opacity(0.18))
                .frame(width: w * 0.16, height: h * 0.16)
                .offset(x: w * 0.14, y: h * 0.32)

            FluxCutCutTailShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.52, blue: 0.20),
                            Color(red: 0.14, green: 0.63, blue: 0.78)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: w * 0.50, height: h * 0.18)
                .offset(x: -w * 0.04, y: h * 0.30)
        }
        .shadow(color: Color.black.opacity(0.14), radius: self.size * 0.05, x: 0, y: self.size * 0.04)
    }

    private func flowRibbon(in size: CGSize) -> some View {
        let w = size.width
        let h = size.height

        return ZStack {
            FluxCutWaveRibbonShape()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.69, blue: 0.30),
                            Color(red: 0.95, green: 0.41, blue: 0.24),
                            Color(red: 0.18, green: 0.70, blue: 0.78)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: h * 0.18, lineCap: .round, lineJoin: .round)
                )
                .frame(width: w * 0.70, height: h * 0.70)

            FluxCutWaveShadowShape()
                .fill(Color.black.opacity(0.16))
                .frame(width: w * 0.20, height: h * 0.16)
                .offset(x: w * 0.15, y: h * 0.19)
        }
        .shadow(color: Color.black.opacity(0.14), radius: self.size * 0.05, x: 0, y: self.size * 0.04)
    }

    private func cutRibbon(in size: CGSize) -> some View {
        let w = size.width
        let h = size.height

        return ZStack {
            FluxCutAngularRibbonShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.71, blue: 0.28),
                            Color(red: 0.95, green: 0.42, blue: 0.21),
                            Color(red: 0.19, green: 0.67, blue: 0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: w * 0.72, height: h * 0.72)

            FluxCutCutNotchShape()
                .fill(Color.black.opacity(0.18))
                .frame(width: w * 0.18, height: h * 0.18)
                .offset(x: w * 0.10, y: h * 0.07)
        }
        .shadow(color: Color.black.opacity(0.14), radius: self.size * 0.05, x: 0, y: self.size * 0.04)
    }

    private func treeFlow(in size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        let barkGradient = LinearGradient(
            colors: [
                Color(red: 0.46, green: 0.28, blue: 0.17),
                Color(red: 0.30, green: 0.18, blue: 0.11)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        return ZStack {
            FluxCutTreeTrunkShape()
                .fill(barkGradient)
                .frame(width: w * 0.24, height: h * 0.58)
                .offset(y: h * 0.14)

            FluxCutTreeBranchShape(side: .left)
                .fill(barkGradient)
                .frame(width: w * 0.30, height: h * 0.28)
                .offset(x: -w * 0.16, y: -h * 0.02)

            FluxCutTreeBranchShape(side: .right)
                .fill(barkGradient)
                .frame(width: w * 0.30, height: h * 0.28)
                .offset(x: w * 0.16, y: -h * 0.02)

            FluxCutTreeCanopyShape()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.00, green: 0.78, blue: 0.38),
                            Color(red: 0.95, green: 0.51, blue: 0.22),
                            Color(red: 0.19, green: 0.70, blue: 0.66)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: w * 0.42
                    )
                )
                .frame(width: w * 0.68, height: h * 0.50)
                .offset(y: -h * 0.18)

            FluxCutTreeCutoutShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.10, blue: 0.19),
                            Color(red: 0.10, green: 0.19, blue: 0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: w * 0.28, height: h * 0.22)
                .offset(y: -h * 0.14)

            ForEach(Array(treeLeafSpecs.enumerated()), id: \.offset) { _, spec in
                FluxCutLeafShape()
                    .fill(spec.color)
                    .frame(width: w * spec.width, height: h * spec.height)
                    .rotationEffect(.degrees(spec.rotation))
                    .offset(x: w * spec.x, y: h * spec.y)
            }
        }
        .shadow(color: Color.black.opacity(0.14), radius: self.size * 0.05, x: 0, y: self.size * 0.04)
    }

    private var treeLeafSpecs: [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, rotation: Double, color: Color)] {
        [
            (-0.28, -0.22, 0.12, 0.08, -32, Color(red: 0.98, green: 0.73, blue: 0.24)),
            (-0.36, -0.10, 0.11, 0.08, -12, Color(red: 0.20, green: 0.73, blue: 0.63)),
            (-0.20, -0.34, 0.11, 0.08, -50, Color(red: 0.96, green: 0.57, blue: 0.18)),
            (-0.06, -0.38, 0.10, 0.07, -10, Color(red: 0.24, green: 0.76, blue: 0.69)),
            (0.10, -0.34, 0.10, 0.07, 8, Color(red: 0.98, green: 0.70, blue: 0.25)),
            (0.26, -0.22, 0.12, 0.08, 28, Color(red: 0.97, green: 0.66, blue: 0.23)),
            (0.34, -0.08, 0.11, 0.08, 44, Color(red: 0.95, green: 0.48, blue: 0.20)),
            (0.18, 0.01, 0.10, 0.07, -12, Color(red: 0.18, green: 0.71, blue: 0.65)),
            (0.00, 0.04, 0.10, 0.07, 10, Color(red: 0.97, green: 0.69, blue: 0.25)),
            (-0.18, 0.00, 0.10, 0.07, 24, Color(red: 0.20, green: 0.73, blue: 0.66))
        ]
    }
}

private struct FluxCutFoldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.maxX * 0.82, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.maxY * 0.72))
        path.closeSubpath()
        return path
    }
}

private struct FluxCutCutTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.62))
        path.addLine(to: CGPoint(x: rect.maxX * 0.84, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.26))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct FluxCutWaveRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.20))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.minY + rect.height * 0.30),
            control1: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.06),
            control2: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.18),
            control1: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.58),
            control2: CGPoint(x: rect.minX + rect.width * 0.50, y: rect.maxY - rect.height * 0.02)
        )
        return path
    }
}

private struct FluxCutWaveShadowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.26))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.76, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY * 0.70))
        path.closeSubpath()
        return path
    }
}

private struct FluxCutAngularRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.minY + rect.height * 0.44))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.maxY - rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY - rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.18))
        path.closeSubpath()
        return path
    }
}

private struct FluxCutCutNotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.72, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct FluxCutTreeTrunkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.04))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.maxY),
            control1: CGPoint(x: rect.midX - rect.width * 0.30, y: rect.minY + rect.height * 0.18),
            control2: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.74)
        )
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.04),
            control1: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.minY + rect.height * 0.74),
            control2: CGPoint(x: rect.midX + rect.width * 0.30, y: rect.minY + rect.height * 0.18)
        )
        path.closeSubpath()
        return path
    }
}

private struct FluxCutTreeCanopyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.02))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.midY - rect.height * 0.06),
            control1: CGPoint(x: rect.midX + rect.width * 0.22, y: rect.minY - rect.height * 0.02),
            control2: CGPoint(x: rect.maxX + rect.width * 0.02, y: rect.minY + rect.height * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.maxY - rect.height * 0.14),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.00),
            control2: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.maxY - rect.height * 0.02)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.maxY - rect.height * 0.14),
            control1: CGPoint(x: rect.midX + rect.width * 0.10, y: rect.maxY + rect.height * 0.02),
            control2: CGPoint(x: rect.midX - rect.width * 0.10, y: rect.maxY + rect.height * 0.02)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY - rect.height * 0.06),
            control1: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.02),
            control2: CGPoint(x: rect.minX - rect.width * 0.02, y: rect.minY + rect.height * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.02),
            control1: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.18),
            control2: CGPoint(x: rect.midX - rect.width * 0.22, y: rect.minY - rect.height * 0.02)
        )
        path.closeSubpath()
        return path
    }
}

private struct FluxCutTreeCutoutShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.18),
            control1: CGPoint(x: rect.midX - rect.width * 0.26, y: rect.maxY - rect.height * 0.26),
            control2: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.54)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.minY + rect.height * 0.54),
            control2: CGPoint(x: rect.midX + rect.width * 0.26, y: rect.maxY - rect.height * 0.26)
        )
        path.closeSubpath()
        return path
    }
}

private struct FluxCutLeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct FluxCutTreeBranchShape: Shape {
    enum Side {
        case left
        case right
    }

    let side: Side

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if side == .left {
            path.move(to: CGPoint(x: rect.maxX * 0.80, y: rect.maxY))
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.28),
                control1: CGPoint(x: rect.maxX * 0.56, y: rect.maxY - rect.height * 0.20),
                control2: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.46)
            )
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.16))
            path.addCurve(
                to: CGPoint(x: rect.maxX * 0.88, y: rect.maxY),
                control1: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.46),
                control2: CGPoint(x: rect.maxX * 0.64, y: rect.maxY - rect.height * 0.18)
            )
        } else {
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.maxY))
            path.addCurve(
                to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.28),
                control1: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.maxY - rect.height * 0.20),
                control2: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.minY + rect.height * 0.46)
            )
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY + rect.height * 0.16))
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY),
                control1: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.minY + rect.height * 0.46),
                control2: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.18)
            )
        }
        path.closeSubpath()
        return path
    }
}

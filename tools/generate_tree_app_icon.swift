import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "")
guard !outputURL.path.isEmpty else {
    fputs("Usage: swift generate_tree_app_icon.swift /path/to/output.png\n", stderr)
    exit(1)
}

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("Could not create graphics context.\n", stderr)
    exit(1)
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> NSColor {
    NSColor(calibratedRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
}

func cgColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    color(r, g, b, a).cgColor
}

func roundedRectPath(in rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

let backgroundRect = CGRect(origin: .zero, size: size)
let bgGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        cgColor(15, 25, 42),
        cgColor(25, 41, 68)
    ] as CFArray,
    locations: [0.0, 1.0]
)!

context.addPath(roundedRectPath(in: backgroundRect, radius: 226))
context.clip()
context.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])

func fillEllipse(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, color: NSColor, alpha: CGFloat = 1.0) {
    context.setFillColor(color.withAlphaComponent(alpha).cgColor)
    let rect = CGRect(x: center.x - radiusX, y: center.y - radiusY, width: radiusX * 2, height: radiusY * 2)
    context.fillEllipse(in: rect)
}

func fillLeaf(center: CGPoint, width: CGFloat, height: CGFloat, rotation: CGFloat, color: NSColor) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: rotation)

    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: height / 2))
    path.addQuadCurve(to: CGPoint(x: width / 2, y: 0), control: CGPoint(x: width / 2, y: height / 2))
    path.addQuadCurve(to: CGPoint(x: 0, y: -height / 2), control: CGPoint(x: width / 2, y: -height / 2))
    path.addQuadCurve(to: CGPoint(x: -width / 2, y: 0), control: CGPoint(x: -width / 2, y: -height / 2))
    path.addQuadCurve(to: CGPoint(x: 0, y: height / 2), control: CGPoint(x: -width / 2, y: height / 2))
    path.closeSubpath()

    context.addPath(path)
    context.setFillColor(color.cgColor)
    context.fillPath()
    context.restoreGState()
}

func fillPath(_ builder: (CGMutablePath) -> Void, color: NSColor) {
    let path = CGMutablePath()
    builder(path)
    context.addPath(path)
    context.setFillColor(color.cgColor)
    context.fillPath()
}

let canopyGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        cgColor(253, 201, 93),
        cgColor(243, 125, 49),
        cgColor(40, 188, 171)
    ] as CFArray,
    locations: [0.0, 0.56, 1.0]
)!

let canopyPath = CGMutablePath()
canopyPath.move(to: CGPoint(x: 512, y: 824))
canopyPath.addCurve(to: CGPoint(x: 812, y: 612), control1: CGPoint(x: 684, y: 838), control2: CGPoint(x: 826, y: 748))
canopyPath.addCurve(to: CGPoint(x: 660, y: 344), control1: CGPoint(x: 812, y: 468), control2: CGPoint(x: 746, y: 362))
canopyPath.addCurve(to: CGPoint(x: 512, y: 402), control1: CGPoint(x: 620, y: 338), control2: CGPoint(x: 570, y: 364))
canopyPath.addCurve(to: CGPoint(x: 364, y: 344), control1: CGPoint(x: 454, y: 364), control2: CGPoint(x: 404, y: 338))
canopyPath.addCurve(to: CGPoint(x: 212, y: 612), control1: CGPoint(x: 278, y: 362), control2: CGPoint(x: 212, y: 468))
canopyPath.addCurve(to: CGPoint(x: 512, y: 824), control1: CGPoint(x: 198, y: 748), control2: CGPoint(x: 340, y: 838))
canopyPath.closeSubpath()

context.saveGState()
context.addPath(canopyPath)
context.clip()
context.drawRadialGradient(
    canopyGradient,
    startCenter: CGPoint(x: 512, y: 650),
    startRadius: 30,
    endCenter: CGPoint(x: 512, y: 650),
    endRadius: 340,
    options: []
)
context.restoreGState()

let barkTop = color(124, 74, 46)
let barkBottom = color(82, 49, 31)
let barkGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [barkTop.cgColor, barkBottom.cgColor] as CFArray,
    locations: [0.0, 1.0]
)!

let trunkPath = CGMutablePath()
trunkPath.move(to: CGPoint(x: 512, y: 606))
trunkPath.addCurve(to: CGPoint(x: 380, y: 104), control1: CGPoint(x: 410, y: 534), control2: CGPoint(x: 352, y: 272))
trunkPath.addLine(to: CGPoint(x: 446, y: 104))
trunkPath.addCurve(to: CGPoint(x: 512, y: 322), control1: CGPoint(x: 452, y: 188), control2: CGPoint(x: 482, y: 272))
trunkPath.addCurve(to: CGPoint(x: 578, y: 104), control1: CGPoint(x: 542, y: 272), control2: CGPoint(x: 572, y: 188))
trunkPath.addLine(to: CGPoint(x: 644, y: 104))
trunkPath.addCurve(to: CGPoint(x: 512, y: 606), control1: CGPoint(x: 672, y: 272), control2: CGPoint(x: 614, y: 534))
trunkPath.closeSubpath()

context.saveGState()
context.addPath(trunkPath)
context.clip()
context.drawLinearGradient(barkGradient, start: CGPoint(x: 512, y: 606), end: CGPoint(x: 512, y: 104), options: [])
context.restoreGState()

fillPath({ path in
    path.move(to: CGPoint(x: 502, y: 570))
    path.addCurve(to: CGPoint(x: 258, y: 638), control1: CGPoint(x: 420, y: 560), control2: CGPoint(x: 308, y: 588))
    path.addCurve(to: CGPoint(x: 220, y: 720), control1: CGPoint(x: 228, y: 656), control2: CGPoint(x: 212, y: 688))
    path.addLine(to: CGPoint(x: 250, y: 734))
    path.addCurve(to: CGPoint(x: 404, y: 668), control1: CGPoint(x: 284, y: 706), control2: CGPoint(x: 346, y: 680))
    path.addCurve(to: CGPoint(x: 520, y: 628), control1: CGPoint(x: 444, y: 656), control2: CGPoint(x: 486, y: 640))
    path.addLine(to: CGPoint(x: 502, y: 570))
    path.closeSubpath()
}, color: barkTop)

fillPath({ path in
    path.move(to: CGPoint(x: 522, y: 570))
    path.addCurve(to: CGPoint(x: 766, y: 638), control1: CGPoint(x: 604, y: 560), control2: CGPoint(x: 716, y: 588))
    path.addCurve(to: CGPoint(x: 804, y: 720), control1: CGPoint(x: 796, y: 656), control2: CGPoint(x: 812, y: 688))
    path.addLine(to: CGPoint(x: 774, y: 734))
    path.addCurve(to: CGPoint(x: 620, y: 668), control1: CGPoint(x: 740, y: 706), control2: CGPoint(x: 678, y: 680))
    path.addCurve(to: CGPoint(x: 504, y: 628), control1: CGPoint(x: 580, y: 656), control2: CGPoint(x: 538, y: 640))
    path.addLine(to: CGPoint(x: 522, y: 570))
    path.closeSubpath()
}, color: barkTop)

let leafColors = [
    color(253, 191, 55),
    color(247, 155, 41),
    color(40, 188, 171),
    color(251, 207, 97),
    color(248, 136, 58),
    color(70, 198, 172)
]

let leafSpecs: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Int)] = [
    (302, 710, 86, 54, -0.55, 0),
    (388, 760, 78, 48, -0.08, 2),
    (468, 794, 74, 46, 0.15, 1),
    (560, 796, 74, 46, -0.12, 2),
    (646, 760, 78, 48, 0.12, 0),
    (726, 706, 86, 54, 0.55, 1),
    (262, 620, 78, 48, -0.70, 2),
    (758, 620, 78, 48, 0.70, 0),
    (328, 560, 72, 44, -0.45, 1),
    (694, 560, 72, 44, 0.45, 2),
    (418, 520, 72, 44, -0.18, 0),
    (608, 520, 72, 44, 0.18, 1),
    (512, 492, 76, 46, 0.0, 2)
]

for spec in leafSpecs {
    fillLeaf(
        center: CGPoint(x: spec.0, y: spec.1),
        width: spec.2,
        height: spec.3,
        rotation: spec.4,
        color: leafColors[spec.5]
    )
}

fillEllipse(center: CGPoint(x: 512, y: 626), radiusX: 30, radiusY: 38, color: color(110, 63, 42))
fillPath({ path in
    path.move(to: CGPoint(x: 512, y: 590))
    path.addLine(to: CGPoint(x: 482, y: 532))
    path.addLine(to: CGPoint(x: 508, y: 532))
    path.addLine(to: CGPoint(x: 482, y: 462))
    path.addLine(to: CGPoint(x: 512, y: 526))
    path.addLine(to: CGPoint(x: 542, y: 462))
    path.addLine(to: CGPoint(x: 516, y: 532))
    path.addLine(to: CGPoint(x: 542, y: 532))
    path.closeSubpath()
}, color: color(110, 63, 42))

let borderPath = roundedRectPath(in: backgroundRect.insetBy(dx: 16, dy: 16), radius: 208)
context.addPath(borderPath)
context.setStrokeColor(color(255, 255, 255, 0.11).cgColor)
context.setLineWidth(8)
context.strokePath()

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Could not encode PNG.\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL)

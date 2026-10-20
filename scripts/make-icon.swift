// Draws the Termos app icon (a black thermos on a white background) and writes
// Sources/Termos/Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
let output = root.appendingPathComponent("Sources/Termos/Resources/AppIcon.icns")

/// Draws the icon on a 1024×1024 canvas (origin bottom-left).
func drawIcon(in context: CGContext) {
    let black = CGColor(gray: 0.08, alpha: 1)
    let white = CGColor(gray: 1, alpha: 1)

    // Background: the standard macOS icon shape, inset to leave room for the shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
    context.addPath(tilePath)
    context.setFillColor(white)
    context.fillPath()
    context.restoreGState()

    context.addPath(tilePath)
    context.setStrokeColor(CGColor(gray: 0, alpha: 0.10))
    context.setLineWidth(2)
    context.strokePath()

    context.setFillColor(black)
    context.setStrokeColor(black)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // The thermos sits slightly left of center to balance the handle.
    let cx: CGFloat = 482

    // Handle on the right side.
    let handle = CGMutablePath()
    handle.move(to: CGPoint(x: cx + 115, y: 555))
    handle.addLine(to: CGPoint(x: cx + 170, y: 555))
    handle.addQuadCurve(to: CGPoint(x: cx + 210, y: 515), control: CGPoint(x: cx + 210, y: 555))
    handle.addLine(to: CGPoint(x: cx + 210, y: 340))
    handle.addQuadCurve(to: CGPoint(x: cx + 170, y: 300), control: CGPoint(x: cx + 210, y: 300))
    handle.addLine(to: CGPoint(x: cx + 115, y: 300))
    context.setLineWidth(34)
    context.addPath(handle)
    context.strokePath()

    // Body: a tall cylinder narrowing at the shoulder.
    // Rounded at the bottom only, so the sides run straight into the shoulder.
    let body = CGRect(x: cx - 130, y: 180, width: 260, height: 430)
    context.addPath(CGPath(roundedRect: body, cornerWidth: 46, cornerHeight: 46, transform: nil))
    context.fillPath()
    context.fill(CGRect(x: cx - 130, y: 300, width: 260, height: 310))
    let shoulder = CGMutablePath()
    shoulder.move(to: CGPoint(x: cx - 130, y: 610))
    shoulder.addLine(to: CGPoint(x: cx + 130, y: 610))
    shoulder.addLine(to: CGPoint(x: cx + 98, y: 690))
    shoulder.addLine(to: CGPoint(x: cx - 98, y: 690))
    shoulder.closeSubpath()
    context.addPath(shoulder)
    context.fillPath()

    // Stopper ring, separated by thin white gaps.
    let ring = CGRect(x: cx - 104, y: 700, width: 208, height: 26)
    context.addPath(CGPath(roundedRect: ring, cornerWidth: 6, cornerHeight: 6, transform: nil))
    context.fillPath()

    // The cup, upside down on top: wider at its rim (bottom).
    let cup = CGMutablePath()
    cup.move(to: CGPoint(x: cx - 120, y: 736))
    cup.addLine(to: CGPoint(x: cx + 120, y: 736))
    cup.addLine(to: CGPoint(x: cx + 106, y: 838))
    cup.addQuadCurve(to: CGPoint(x: cx + 84, y: 858), control: CGPoint(x: cx + 104, y: 858))
    cup.addLine(to: CGPoint(x: cx - 84, y: 858))
    cup.addQuadCurve(to: CGPoint(x: cx - 106, y: 838), control: CGPoint(x: cx - 104, y: 858))
    cup.closeSubpath()
    context.addPath(cup)
    context.fillPath()

    // White details on the body: a band near the base and a terminal prompt ">_".
    context.setStrokeColor(white)
    context.setLineCap(.butt)
    context.setLineWidth(12)
    let band = CGMutablePath()
    band.move(to: CGPoint(x: cx - 130, y: 240))
    band.addLine(to: CGPoint(x: cx + 130, y: 240))
    context.addPath(band)
    context.strokePath()

    context.setLineCap(.round)
    context.setLineWidth(28)
    let chevron = CGMutablePath()
    chevron.move(to: CGPoint(x: cx - 64, y: 480))
    chevron.addLine(to: CGPoint(x: cx - 8, y: 425))
    chevron.addLine(to: CGPoint(x: cx - 64, y: 370))
    context.addPath(chevron)
    context.strokePath()

    let underscore = CGMutablePath()
    underscore.move(to: CGPoint(x: cx + 20, y: 365))
    underscore.addLine(to: CGPoint(x: cx + 74, y: 365))
    context.addPath(underscore)
    context.strokePath()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(in: context)
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try render(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

// A full-size preview next to the icon, handy for reviewing the design.
try render(size: 1024).write(to: output.deletingPathExtension().appendingPathExtension("png"))
print("Wrote \(output.path)")

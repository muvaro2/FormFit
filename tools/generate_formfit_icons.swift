import AppKit
import Foundation

let outputPaths = Array(CommandLine.arguments.dropFirst())

guard !outputPaths.isEmpty else {
    fputs("Usage: generate_formfit_icons.swift <output-path> [<output-path> ...]\n", stderr)
    exit(1)
}

let canvasSize = CGSize(width: 1024, height: 1024)
let orange = NSColor(deviceRed: 1.0, green: 0.42, blue: 0.21, alpha: 1.0)
let orangeDeep = NSColor(deviceRed: 0.84, green: 0.28, blue: 0.14, alpha: 1.0)
let glow = NSColor(deviceRed: 1.0, green: 0.42, blue: 0.21, alpha: 0.12)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Unable to create bitmap graphics context.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

let context = graphicsContext.cgContext

context.setAllowsAntialiasing(true)
context.interpolationQuality = .high

NSColor.white.setFill()
context.fill(CGRect(origin: .zero, size: canvasSize))

let largeGlow = NSBezierPath(ovalIn: CGRect(x: 660, y: 700, width: 250, height: 250))
glow.setFill()
largeGlow.fill()

let softGlow = NSBezierPath(ovalIn: CGRect(x: 120, y: 110, width: 210, height: 210))
NSColor(deviceRed: 0.84, green: 0.28, blue: 0.14, alpha: 0.06).setFill()
softGlow.fill()

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = glow
shadow.shadowBlurRadius = 32
shadow.shadowOffset = NSSize(width: 0, height: -8)
shadow.set()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

let firstAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 470, weight: .black),
    .foregroundColor: orange,
    .paragraphStyle: paragraph
]

let secondAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 470, weight: .black),
    .foregroundColor: orangeDeep,
    .paragraphStyle: paragraph
]

let firstF = NSAttributedString(string: "F", attributes: firstAttributes)
let secondF = NSAttributedString(string: "F", attributes: secondAttributes)

firstF.draw(in: CGRect(x: 190, y: 355, width: 340, height: 440))
secondF.draw(in: CGRect(x: 455, y: 220, width: 340, height: 440))

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

guard
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Failed to encode PNG.\n", stderr)
    exit(1)
}

for path in outputPaths {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
    )
    try pngData.write(to: url)
    print("Wrote \(url.path)")
}

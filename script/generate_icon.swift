import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func render(size: Int, name: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let background = NSBezierPath(roundedRect: NSRect(x: 68, y: 68, width: 888, height: 888), xRadius: 195, yRadius: 195)
    NSColor(calibratedRed: 0.16, green: 0.28, blue: 0.52, alpha: 1).setFill()
    background.fill()

    let shield = NSBezierPath()
    shield.move(to: NSPoint(x: 512, y: 828))
    shield.curve(to: NSPoint(x: 250, y: 725), controlPoint1: NSPoint(x: 390, y: 760), controlPoint2: NSPoint(x: 330, y: 744))
    shield.line(to: NSPoint(x: 264, y: 492))
    shield.curve(to: NSPoint(x: 512, y: 210), controlPoint1: NSPoint(x: 276, y: 348), controlPoint2: NSPoint(x: 380, y: 258))
    shield.curve(to: NSPoint(x: 760, y: 492), controlPoint1: NSPoint(x: 644, y: 258), controlPoint2: NSPoint(x: 748, y: 348))
    shield.line(to: NSPoint(x: 774, y: 725))
    shield.curve(to: NSPoint(x: 512, y: 828), controlPoint1: NSPoint(x: 694, y: 744), controlPoint2: NSPoint(x: 634, y: 760))
    shield.close()
    NSColor.white.setFill()
    shield.fill()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 360, weight: .semibold),
        .foregroundColor: NSColor(calibratedRed: 0.16, green: 0.28, blue: 0.52, alpha: 1)
    ]
    let letter = "Q" as NSString
    let dimensions = letter.size(withAttributes: attributes)
    letter.draw(at: NSPoint(x: 512 - dimensions.width / 2, y: 472 - dimensions.height / 2), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
}

for points in [16, 32, 128, 256, 512] {
    try render(size: points, name: "icon_\(points)x\(points).png")
    try render(size: points * 2, name: "icon_\(points)x\(points)@2x.png")
}

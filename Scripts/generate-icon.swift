import AppKit

let output = CommandLine.arguments[1]
let canvas = 1024
let color = NSColor(red: 0.12, green: 0.48, blue: 1, alpha: 1)
guard let representation = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvas,
    pixelsHigh: canvas,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create icon bitmap")
}

representation.size = NSSize(width: canvas, height: canvas)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)

let configuration = NSImage.SymbolConfiguration(pointSize: 720, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
guard let symbol = NSImage(systemSymbolName: "switch.2", accessibilityDescription: "Codex Meter")?
    .withSymbolConfiguration(configuration) else {
    fatalError("Missing SF Symbol switch.2")
}
let size = symbol.size
let origin = NSPoint(x: (CGFloat(canvas) - size.width) / 2, y: (CGFloat(canvas) - size.height) / 2)
symbol.draw(in: NSRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: 1)

NSGraphicsContext.restoreGraphicsState()
try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))

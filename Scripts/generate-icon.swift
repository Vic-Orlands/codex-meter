import AppKit

let output = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

NSGraphicsContext.current!.cgContext.scaleBy(x: 4, y: 4)
NSColor(red: 0.12, green: 0.48, blue: 1, alpha: 1).setStroke()

func stroke(_ points: [NSPoint], curves: [(NSPoint, NSPoint, NSPoint)] = []) {
    let path = NSBezierPath()
    path.lineWidth = 16
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    for curve in curves { path.curve(to: curve.0, controlPoint1: curve.1, controlPoint2: curve.2) }
    path.stroke()
}

let top = NSBezierPath()
top.lineWidth = 16
top.lineCapStyle = .round
top.lineJoinStyle = .round
top.move(to: NSPoint(x: 96, y: 216))
top.line(to: NSPoint(x: 208, y: 216))
top.curve(to: NSPoint(x: 216, y: 208), controlPoint1: NSPoint(x: 212, y: 216), controlPoint2: NSPoint(x: 216, y: 212))
top.line(to: NSPoint(x: 216, y: 104))
top.curve(to: NSPoint(x: 208, y: 96), controlPoint1: NSPoint(x: 216, y: 100), controlPoint2: NSPoint(x: 212, y: 96))
top.line(to: NSPoint(x: 104, y: 96))
top.stroke()
stroke([NSPoint(x: 104, y: 120), NSPoint(x: 80, y: 96), NSPoint(x: 104, y: 72)])

let bottom = NSBezierPath()
bottom.lineWidth = 16
bottom.lineCapStyle = .round
bottom.lineJoinStyle = .round
bottom.move(to: NSPoint(x: 160, y: 40))
bottom.line(to: NSPoint(x: 48, y: 40))
bottom.curve(to: NSPoint(x: 40, y: 48), controlPoint1: NSPoint(x: 44, y: 40), controlPoint2: NSPoint(x: 40, y: 44))
bottom.line(to: NSPoint(x: 40, y: 152))
bottom.curve(to: NSPoint(x: 48, y: 160), controlPoint1: NSPoint(x: 40, y: 156), controlPoint2: NSPoint(x: 44, y: 160))
bottom.line(to: NSPoint(x: 152, y: 160))
bottom.stroke()
stroke([NSPoint(x: 152, y: 184), NSPoint(x: 176, y: 160), NSPoint(x: 152, y: 136)])

image.unlockFocus()
let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))

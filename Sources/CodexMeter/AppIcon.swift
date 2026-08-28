import AppKit
import SwiftUI

struct SwitchLogo: View {
    let size: CGFloat
    var color: Color = .primary

    var body: some View {
        Canvas { context, canvasSize in
                let scale = min(canvasSize.width, canvasSize.height) / 256
                context.scaleBy(x: scale, y: scale)
                let style = StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round)

                var topFrame = Path()
                topFrame.move(to: CGPoint(x: 96, y: 40))
                topFrame.addLine(to: CGPoint(x: 208, y: 40))
                topFrame.addCurve(to: CGPoint(x: 216, y: 48), control1: CGPoint(x: 212, y: 40), control2: CGPoint(x: 216, y: 44))
                topFrame.addLine(to: CGPoint(x: 216, y: 152))
                topFrame.addCurve(to: CGPoint(x: 208, y: 160), control1: CGPoint(x: 216, y: 156), control2: CGPoint(x: 212, y: 160))
                topFrame.addLine(to: CGPoint(x: 104, y: 160))
                context.stroke(topFrame, with: .color(color), style: style)

                var leftArrow = Path()
                leftArrow.move(to: CGPoint(x: 104, y: 136))
                leftArrow.addLine(to: CGPoint(x: 80, y: 160))
                leftArrow.addLine(to: CGPoint(x: 104, y: 184))
                context.stroke(leftArrow, with: .color(color), style: style)

                var bottomFrame = Path()
                bottomFrame.move(to: CGPoint(x: 160, y: 216))
                bottomFrame.addLine(to: CGPoint(x: 48, y: 216))
                bottomFrame.addCurve(to: CGPoint(x: 40, y: 208), control1: CGPoint(x: 44, y: 216), control2: CGPoint(x: 40, y: 212))
                bottomFrame.addLine(to: CGPoint(x: 40, y: 104))
                bottomFrame.addCurve(to: CGPoint(x: 48, y: 96), control1: CGPoint(x: 40, y: 100), control2: CGPoint(x: 44, y: 96))
                bottomFrame.addLine(to: CGPoint(x: 152, y: 96))
                context.stroke(bottomFrame, with: .color(color), style: style)

                var rightArrow = Path()
                rightArrow.move(to: CGPoint(x: 152, y: 72))
                rightArrow.addLine(to: CGPoint(x: 176, y: 96))
                rightArrow.addLine(to: CGPoint(x: 152, y: 120))
                context.stroke(rightArrow, with: .color(color), style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ProviderProductIcon: View {
    enum Product { case codex, cursor }
    let product: Product
    let size: CGFloat

    var body: some View {
        Group {
            if let image = appImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else if product == .codex {
                Image(systemName: "brain.head.profile")
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else {
                Image(systemName: "cursorarrow")
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var appImage: NSImage? {
        let path = product == .cursor ? "/Applications/Cursor.app" : "/Applications/ChatGPT.app"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }
}

@MainActor
enum AppIconRenderer {
    static func make() -> NSImage {
        let renderer = ImageRenderer(content: SwitchLogo(size: 512, color: Color(red: 0.12, green: 0.48, blue: 1)))
        renderer.scale = 2
        return renderer.nsImage ?? NSImage(size: NSSize(width: 512, height: 512))
    }

    static func menuBarImage() -> NSImage {
        let renderer = ImageRenderer(content: SwitchLogo(size: 19, color: .black))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 19, height: 19))
        image.isTemplate = true
        return image
    }
}

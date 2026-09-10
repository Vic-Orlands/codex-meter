import AppKit
import SwiftUI

enum MeterSymbol {
    static let app = "switch.2"
}

struct SwitchLogo: View {
    let size: CGFloat
    var color: Color = .primary

    var body: some View {
        Image(systemName: MeterSymbol.app)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
            .symbolRenderingMode(.monochrome)
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
            if let image = ProductIconCache.image(for: product) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    // macOS app icons include transparent padding; crop so the mark fills iconSize.
                    .scaleEffect(1.18)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

private enum ProductIconCache {
    static func image(for product: ProviderProductIcon.Product) -> NSImage? {
        switch product {
        case .codex: return codex
        case .cursor: return cursor
        }
    }

    private static let codex = icon(
        bundleIDs: ["com.openai.chat", "com.openai.codex"],
        paths: ["/Applications/ChatGPT.app", "/Applications/Codex.app"]
    )
    private static let cursor = icon(
        bundleIDs: ["com.todesktop.230313mzl4w4u92"],
        paths: ["/Applications/Cursor.app"]
    )

    private static func icon(bundleIDs: [String], paths: [String]) -> NSImage? {
        for identifier in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return sized(NSWorkspace.shared.icon(forFile: url.path))
            }
        }
        for path in paths where FileManager.default.fileExists(atPath: path) {
            return sized(NSWorkspace.shared.icon(forFile: path))
        }
        return nil
    }

    private static func sized(_ image: NSImage) -> NSImage {
        image.size = NSSize(width: 64, height: 64)
        return image
    }
}

@MainActor
enum AppIconRenderer {
    static func make() -> NSImage {
        let renderer = ImageRenderer(content: SwitchLogo(size: 512, color: Color.accentColor))
        renderer.scale = 2
        return renderer.nsImage ?? NSImage(systemSymbolName: MeterSymbol.app, accessibilityDescription: "Codex Meter") ?? NSImage(size: NSSize(width: 512, height: 512))
    }
}

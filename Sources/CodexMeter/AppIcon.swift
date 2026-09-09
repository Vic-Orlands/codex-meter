import AppKit
import SwiftUI

enum MeterSymbol {
    static let app = "switch.2"
    static let codex = "brain.head.profile"
    static let cursor = "cursorarrow"
}

struct SwitchLogo: View {
    let size: CGFloat
    var color: Color = .primary

    var body: some View {
        Image(systemName: MeterSymbol.app)
            .font(.system(size: size * 0.72, weight: .semibold))
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
                    .scaledToFit()
            } else {
                Image(systemName: product == .codex ? MeterSymbol.codex : MeterSymbol.cursor)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.12)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
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

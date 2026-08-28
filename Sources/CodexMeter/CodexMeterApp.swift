import AppKit
import SwiftUI

@main
struct CodexMeterApp: App {
    @StateObject private var store = AccountStore()
    @AppStorage("showDockIcon") private var showDockIcon = false

    init() {
        NSApplication.shared.applicationIconImage = AppIconRenderer.make()
        NSApplication.shared.setActivationPolicy(UserDefaults.standard.bool(forKey: "showDockIcon") ? .regular : .accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
                .task { store.start() }
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: AppIconRenderer.menuBarImage())
                Text(menuTitle)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
            }
            .accessibilityLabel("Codex Meter, \(menuTitle)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(store)
        }
    }

    private var menuTitle: String {
        guard let remaining = store.activeSnapshot?.rateLimits?.primary?.remainingPercent else { return "" }
        return "\(remaining)%"
    }
}

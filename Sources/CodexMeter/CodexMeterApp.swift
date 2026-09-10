import AppKit
import SwiftUI

@main
struct CodexMeterApp: App {
    @StateObject private var store = AccountStore()
    @AppStorage("showDockIcon") private var showDockIcon = false

    init() {
        if !SingleInstance.claim() {
            exit(0)
        }
        NSApplication.shared.applicationIconImage = AppIconRenderer.make()
        NSApplication.shared.setActivationPolicy(UserDefaults.standard.bool(forKey: "showDockIcon") ? .regular : .accessory)
        LoginItemService.applyPreference()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: MeterSymbol.app)
                    .symbolRenderingMode(.monochrome)
                Text(menuTitle)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
            }
            .accessibilityLabel("Codex Meter, \(menuTitle)")
            .task { store.start() }
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

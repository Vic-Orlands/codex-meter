import Foundation
import ServiceManagement

enum LoginItemService {
    static let preferenceKey = "openAtLogin"
    static let installedAppURL = URL(fileURLWithPath: "/Applications/Codex Meter.app")

    private static let launchAgentLabel = "com.vicorlands.CodexMeter"

    static var isEnabledPreference: Bool {
        if UserDefaults.standard.object(forKey: preferenceKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: preferenceKey)
    }

    static func applyPreference() {
        setEnabled(isEnabledPreference)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        if enabled {
            enable()
        } else {
            disable()
        }
    }

    static func isRunningFromInstalledApp(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        standardizedPath(for: bundleURL) == standardizedPath(for: installedAppURL)
    }

    @discardableResult
    static func enable() -> Bool {
        if isRunningFromInstalledApp() {
            if registerMainApp() {
                removeLaunchAgent()
                return true
            }
            return installLaunchAgent()
        }

        // Dist and project-local binaries must not register themselves as a login item.
        unregisterMainApp()
        return installLaunchAgent()
    }

    static func disable() {
        unregisterMainApp()
        removeLaunchAgent()
    }

    @discardableResult
    private static func registerMainApp() -> Bool {
        do {
            try SMAppService.mainApp.register()
        } catch {
            // Already registered is success; anything else may still be enabled.
        }
        return SMAppService.mainApp.status == .enabled
    }

    private static func unregisterMainApp() {
        guard SMAppService.mainApp.status != .notRegistered else { return }
        try? SMAppService.mainApp.unregister()
    }

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    @discardableResult
    private static func installLaunchAgent() -> Bool {
        let executable = installedAppURL.appendingPathComponent("Contents/MacOS/CodexMeter")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return false }

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [executable.path],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]

        do {
            let agentsDir = launchAgentURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: launchAgentURL, options: .atomic)
        } catch {
            return false
        }

        bootoutLaunchAgent()
        return bootstrapLaunchAgent()
    }

    private static func removeLaunchAgent() {
        bootoutLaunchAgent()
        try? FileManager.default.removeItem(at: launchAgentURL)
    }

    private static func bootstrapLaunchAgent() -> Bool {
        launchctl(["bootstrap", "gui/\(getuid())", launchAgentURL.path])
    }

    private static func bootoutLaunchAgent() {
        _ = launchctl(["bootout", "gui/\(getuid())/\(launchAgentLabel)"])
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func standardizedPath(for url: URL) -> String {
        let resolved = FileManager.default.fileExists(atPath: url.path)
            ? url.resolvingSymlinksInPath()
            : url
        var path = resolved.standardizedFileURL.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

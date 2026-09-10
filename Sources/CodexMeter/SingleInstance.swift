import AppKit

enum SingleInstance {
    static let bundleIdentifier = "com.vicorlands.CodexMeter"

    /// Activates an already-running copy and returns `false` so this process can exit.
    static func claim() -> Bool {
        let others = existingInstances()
        guard let existing = others.first else { return true }
        existing.activate()
        return false
    }

    static func existingInstances(
        identifier: String? = nil,
        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> [NSRunningApplication] {
        let bundleID = identifier ?? Bundle.main.bundleIdentifier ?? bundleIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }
    }
}

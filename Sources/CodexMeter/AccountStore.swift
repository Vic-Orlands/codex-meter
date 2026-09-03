import AppKit
import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var profiles: [AccountProfile] = []
    @Published private(set) var snapshots: [UUID: AccountSnapshot] = [:]
    @Published private(set) var activeID: UUID?
    @Published private(set) var cursorSnapshot: CursorSnapshot?
    @Published private(set) var cursorError: String?
    @Published private(set) var accountErrors: [UUID: String] = [:]
    @Published private(set) var isRefreshing = false
    @Published var alertMessage: String?

    @Published var customCodexPath: String {
        didSet { UserDefaults.standard.set(customCodexPath, forKey: "customCodexPath") }
    }

    private let fileManager: FileManager
    private let appSupport: URL
    private let liveCodexHome: URL
    private let restartsCodexDesktopOnSwitch: Bool
    private var hasStarted = false
    private var pendingRefreshRequest: RefreshRequest = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []
    private var lastCodexRefreshAttempt: Date?
    private var lastCursorSummaryRefreshAttempt: Date?
    private var lastCursorActivityRefreshAttempt: Date?
    private var lastCursorActivityRefresh: Date?
    private var configURL: URL { appSupport.appendingPathComponent("accounts.json") }

    init(
        fileManager: FileManager = .default,
        appSupport: URL? = nil,
        liveCodexHome: URL? = nil,
        restartsCodexDesktopOnSwitch: Bool = true
    ) {
        self.fileManager = fileManager
        self.appSupport = appSupport ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CodexMeter", isDirectory: true)
        self.liveCodexHome = liveCodexHome ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        self.restartsCodexDesktopOnSwitch = restartsCodexDesktopOnSwitch
        self.customCodexPath = UserDefaults.standard.string(forKey: "customCodexPath") ?? ""
        load()
    }

    var activeSnapshot: AccountSnapshot? { activeID.flatMap { snapshots[$0] } }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if profiles.isEmpty { try importCurrentAccount() }
            installObservers()
            refreshAll()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func refreshAll(includeCursorActivity: Bool = false) {
        enqueueRefresh([.codex, .cursorSummary, includeCursorActivity ? .cursorActivity : []])
    }

    func refreshVisibleData(showingCursor: Bool) {
        var request: RefreshRequest = []
        if shouldRefreshCodex() {
            request.insert(.codex)
        }
        if showingCursor {
            if shouldRefreshCursorSummary() {
                request.insert(.cursorSummary)
            }
            if shouldRefreshCursorActivity() {
                request.formUnion([.cursorSummary, .cursorActivity])
            }
        }
        enqueueRefresh(request)
    }

    func addAccount() {
        let id = UUID()
        let home = appSupport.appendingPathComponent("Accounts/\(id.uuidString)", isDirectory: true)
        let name = "Account \(profiles.count + 1)"
        let executable = CodexAppServer.locateExecutable(customPath: customCodexPath)
        isRefreshing = true

        Task.detached(priority: .userInitiated) {
            do {
                let snapshot = try CodexAppServer.login(codexHome: home, executable: executable) { url in
                    DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                }
                await MainActor.run {
                    let profile = AccountProfile(id: id, name: snapshot.email ?? name, codexHome: home.path)
                    self.profiles.append(profile)
                    self.snapshots[id] = snapshot
                    self.isRefreshing = false
                    self.save()
                }
            } catch {
                await MainActor.run {
                    self.isRefreshing = false
                    self.alertMessage = CodexAppServer.userFacingMessage(for: error)
                }
            }
        }
    }

    func switchAccount(to profile: AccountProfile) {
        do {
            let liveAuth = liveCodexHome.appendingPathComponent("auth.json")
            if let current = activeID.flatMap({ id in profiles.first(where: { $0.id == id }) }), fileManager.fileExists(atPath: liveAuth.path) {
                try atomicCopy(from: liveAuth, to: current.homeURL.appendingPathComponent("auth.json"))
            }
            let selectedAuth = profile.homeURL.appendingPathComponent("auth.json")
            guard fileManager.fileExists(atPath: selectedAuth.path) else { throw CodexMeterError.missingAuth }
            try fileManager.createDirectory(at: liveCodexHome, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try atomicCopy(from: selectedAuth, to: liveAuth)
            activeID = profile.id
            save()
            if restartsCodexDesktopOnSwitch { restartCodexDesktop() }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func rename(_ profile: AccountProfile, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    private func importCurrentAccount() throws {
        let source = liveCodexHome.appendingPathComponent("auth.json")
        guard fileManager.fileExists(atPath: source.path) else { return }
        let id = UUID()
        let home = appSupport.appendingPathComponent("Accounts/\(id.uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try atomicCopy(from: source, to: home.appendingPathComponent("auth.json"))
        profiles = [AccountProfile(id: id, name: "Current account", codexHome: home.path)]
        activeID = id
        save()
    }

    private func atomicCopy(from source: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".auth-\(UUID().uuidString).tmp")
        try fileManager.copyItem(at: source, to: temporary)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    deinit {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        appObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private func installObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshVisibleData(showingCursor: false)
                }
            }
        )

        appObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshVisibleData(showingCursor: false)
                }
            }
        )
    }

    private func enqueueRefresh(_ request: RefreshRequest) {
        guard !request.isEmpty else { return }
        pendingRefreshRequest.formUnion(request)
        guard !isRefreshing else { return }
        let nextRequest = pendingRefreshRequest
        pendingRefreshRequest = []
        runRefresh(nextRequest)
    }

    private func runRefresh(_ request: RefreshRequest) {
        guard !request.isEmpty else { return }

        if request.contains(.codex) {
            syncActiveAuthIfNeeded()
            lastCodexRefreshAttempt = Date()
        }
        if request.contains(.cursorSummary) {
            lastCursorSummaryRefreshAttempt = Date()
        }
        if request.contains(.cursorActivity) {
            lastCursorActivityRefreshAttempt = Date()
        }

        isRefreshing = true
        let profilesToRefresh = request.contains(.codex) ? profiles : []
        let executable = CodexAppServer.locateExecutable(customPath: customCodexPath)
        let includeCursorSummary = request.contains(.cursorSummary)
        let includeCursorActivity = request.contains(.cursorActivity)

        Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: RefreshResult.self) { group in
                if request.contains(.codex) {
                    group.addTask {
                        var results: [UUID: Result<AccountSnapshot, Error>] = [:]
                        for profile in profilesToRefresh {
                            do {
                                results[profile.id] = .success(try CodexAppServer.snapshot(codexHome: profile.homeURL, executable: executable))
                            } catch {
                                results[profile.id] = .failure(error)
                            }
                        }
                        return .accounts(results)
                    }
                }

                if includeCursorSummary {
                    group.addTask {
                        do {
                            return .cursor(.success(try await CursorUsageClient.snapshot(includeActivity: includeCursorActivity)), includeActivity: includeCursorActivity)
                        } catch {
                            return .cursor(.failure(error), includeActivity: includeCursorActivity)
                        }
                    }
                }

                for await result in group {
                    switch result {
                    case .accounts(let results):
                        await MainActor.run {
                            for (id, result) in results {
                                switch result {
                                case .success(let snapshot):
                                    self.snapshots[id] = snapshot
                                    self.accountErrors[id] = nil
                                case .failure(let error):
                                    self.accountErrors[id] = CodexAppServer.userFacingMessage(for: error)
                                }
                            }
                            let allFailed = !results.isEmpty && results.values.allSatisfy { if case .failure = $0 { true } else { false } }
                            if allFailed, self.snapshots.isEmpty,
                               let first = results.values.first, case .failure(let error) = first {
                                self.alertMessage = CodexAppServer.userFacingMessage(for: error)
                            }
                        }
                    case .cursor(let result, let includeActivity):
                        switch result {
                        case .success(let snapshot):
                            await MainActor.run {
                                var updated = snapshot
                                if !includeActivity, let existing = self.cursorSnapshot {
                                    updated.dailyUsage = existing.dailyUsage
                                    updated.totalTokens = existing.totalTokens
                                }
                                self.cursorSnapshot = updated
                                self.cursorError = nil
                                if includeActivity {
                                    self.lastCursorActivityRefresh = Date()
                                }
                            }
                        case .failure(let error):
                            await MainActor.run { self.cursorError = error.localizedDescription }
                        }
                    }
                }

                await MainActor.run {
                    self.isRefreshing = false
                    if !self.pendingRefreshRequest.isEmpty {
                        let nextRequest = self.pendingRefreshRequest
                        self.pendingRefreshRequest = []
                        self.runRefresh(nextRequest)
                    }
                }
            }
        }
    }

    private func shouldRefreshCodex(now: Date = Date()) -> Bool {
        guard !profiles.isEmpty else { return false }
        if snapshots.count < profiles.count || !accountErrors.isEmpty {
            return retryEligible(lastCodexRefreshAttempt, now: now)
        }
        guard let lastFetch = snapshots.values.map(\.fetchedAt).max() else { return true }
        return now.timeIntervalSince(lastFetch) >= 300
    }

    private func shouldRefreshCursorSummary(now: Date = Date()) -> Bool {
        if cursorSnapshot == nil || cursorError != nil {
            return retryEligible(lastCursorSummaryRefreshAttempt, now: now)
        }
        guard let fetchedAt = cursorSnapshot?.fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= 600
    }

    private func shouldRefreshCursorActivity(now: Date = Date()) -> Bool {
        if cursorSnapshot?.dailyUsage.isEmpty != false {
            return retryEligible(lastCursorActivityRefreshAttempt, now: now)
        }
        guard let lastCursorActivityRefresh else { return true }
        return now.timeIntervalSince(lastCursorActivityRefresh) >= 3600
    }

    private func retryEligible(_ lastAttempt: Date?, now: Date, minimumInterval: TimeInterval = 60) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= minimumInterval
    }

    private func syncActiveAuthIfNeeded() {
        guard let active = activeID.flatMap({ id in profiles.first(where: { $0.id == id }) }) else { return }
        let liveAuth = liveCodexHome.appendingPathComponent("auth.json")
        let destination = active.homeURL.appendingPathComponent("auth.json")
        guard fileManager.fileExists(atPath: liveAuth.path) else { return }
        guard authNeedsSync(from: liveAuth, to: destination) else { return }
        try? atomicCopy(from: liveAuth, to: destination)
    }

    private func authNeedsSync(from source: URL, to destination: URL) -> Bool {
        guard fileManager.fileExists(atPath: destination.path) else { return true }
        guard let sourceAttributes = try? fileManager.attributesOfItem(atPath: source.path),
              let destinationAttributes = try? fileManager.attributesOfItem(atPath: destination.path) else {
            return true
        }
        let sourceSize = sourceAttributes[.size] as? NSNumber
        let destinationSize = destinationAttributes[.size] as? NSNumber
        if sourceSize != destinationSize {
            return true
        }
        let sourceModified = sourceAttributes[.modificationDate] as? Date
        let destinationModified = destinationAttributes[.modificationDate] as? Date
        return sourceModified != destinationModified
    }

    private func restartCodexDesktop() {
        let bundleIdentifier = "com.openai.codex"
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).forEach { $0.terminate() }

        Task { @MainActor in
            for _ in 0..<20 {
                if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty else {
                alertMessage = "The account was switched, but Codex could not be restarted. Quit and reopen Codex to load it."
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            do {
                _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            } catch {
                alertMessage = "The account was switched, but Codex could not be reopened: \(error.localizedDescription)"
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AccountConfig.self, from: data) else { return }
        profiles = config.profiles
        activeID = config.activeID
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(AccountConfig(profiles: profiles, activeID: activeID))
            try data.write(to: configURL, options: .atomic)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct AccountConfig: Codable {
    let profiles: [AccountProfile]
    let activeID: UUID?
}

private enum RefreshResult {
    case accounts([UUID: Result<AccountSnapshot, Error>])
    case cursor(Result<CursorSnapshot, Error>, includeActivity: Bool)
}

private struct RefreshRequest: OptionSet {
    let rawValue: Int

    static let codex = RefreshRequest(rawValue: 1 << 0)
    static let cursorSummary = RefreshRequest(rawValue: 1 << 1)
    static let cursorActivity = RefreshRequest(rawValue: 1 << 2)
}

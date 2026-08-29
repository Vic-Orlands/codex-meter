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
    private var refreshTask: Task<Void, Never>?
    private var lastCursorActivityRefresh: Date?
    private var hasStarted = false
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
            refresh()
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    self?.refresh()
                }
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        if let active = activeID.flatMap({ id in profiles.first(where: { $0.id == id }) }) {
            let liveAuth = liveCodexHome.appendingPathComponent("auth.json")
            if fileManager.fileExists(atPath: liveAuth.path) {
                try? atomicCopy(from: liveAuth, to: active.homeURL.appendingPathComponent("auth.json"))
            }
        }
        isRefreshing = true
        let profilesToRefresh = profiles
        let executable = CodexAppServer.locateExecutable(customPath: customCodexPath)
        let includeCursorActivity = lastCursorActivityRefresh.map { Date().timeIntervalSince($0) >= 3600 } ?? true

        Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: RefreshResult.self) { group in
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

                group.addTask {
                    do {
                        return .cursor(.success(try await CursorUsageClient.snapshot(includeActivity: false)))
                    } catch {
                        return .cursor(.failure(error))
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
                    case .cursor(let result):
                        switch result {
                        case .success(let snapshot):
                            await MainActor.run {
                                var updated = snapshot
                                if let existing = self.cursorSnapshot {
                                    updated.dailyUsage = existing.dailyUsage
                                    updated.totalTokens = existing.totalTokens
                                }
                                self.cursorSnapshot = updated
                                self.cursorError = nil
                            }
                            if includeCursorActivity {
                                await MainActor.run { self.lastCursorActivityRefresh = Date() }
                                Task.detached(priority: .utility) {
                                    guard let activity = try? await CursorUsageClient.activity() else { return }
                                    await MainActor.run {
                                        guard var current = self.cursorSnapshot else { return }
                                        current.dailyUsage = activity.dailyUsage
                                        current.totalTokens = activity.totalTokens
                                        self.cursorSnapshot = current
                                    }
                                }
                            }
                        case .failure(let error):
                            await MainActor.run { self.cursorError = error.localizedDescription }
                        }
                    }
                }

                await MainActor.run { self.isRefreshing = false }
            }
        }
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
    case cursor(Result<CursorSnapshot, Error>)
}

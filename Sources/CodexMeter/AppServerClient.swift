import Foundation
import SystemConfiguration

enum CodexAppServer {
    static func snapshot(codexHome: URL, executable: URL? = nil) throws -> AccountSnapshot {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                return try snapshotOnce(codexHome: codexHome, executable: executable)
            } catch {
                lastError = error
                guard shouldRetry(error), attempt == 0 else { throw error }
                Thread.sleep(forTimeInterval: 1.2)
            }
        }
        throw lastError ?? CodexMeterError.invalidResponse
    }

    static func shouldRetry(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("error sending request")
            || message.contains("failed to fetch")
            || message.contains("timed out")
            || message.contains("connection reset")
            || message.contains("network connection")
            || message.contains("connection was lost")
            || message.contains("could not resolve")
            || message.contains("closed unexpectedly")
    }

    static func userFacingMessage(for error: Error) -> String {
        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("error sending request") || lower.contains("failed to fetch") {
            return "Couldn’t reach ChatGPT usage. Check your network, VPN, or HTTP proxy. GUI apps don’t inherit proxy settings from ~/.zshrc."
        }
        return raw
    }

    private static func snapshotOnce(codexHome: URL, executable: URL?) throws -> AccountSnapshot {
        let session = try Session(codexHome: codexHome, executable: executable, timeout: 30)
        defer { session.stop() }
        try session.initialize()

        let account: AccountResponse = try session.request("account/read", params: ["refreshToken": false])
        guard let details = account.account else { throw CodexMeterError.signedOut }
        let limits: RateLimitsResponse = try session.requestRetrying("account/rateLimits/read")
        let usage = try? session.request("account/usage/read", as: UsageResponse.self)

        return AccountSnapshot(
            email: details.email,
            planType: details.planType ?? limits.rateLimits.planType,
            rateLimits: limits.rateLimits,
            resetCredits: limits.rateLimitResetCredits?.availableCount,
            usage: usage?.summary,
            dailyUsage: usage?.dailyUsageBuckets ?? []
        )
    }

    static func login(
        codexHome: URL,
        executable: URL? = nil,
        openURL: @escaping (URL) -> Void
    ) throws -> AccountSnapshot {
        let session = try Session(codexHome: codexHome, executable: executable, timeout: 300)
        defer { session.stop() }
        try session.initialize()
        let response: LoginStartResponse = try session.request(
            "account/login/start",
            params: ["type": "chatgpt", "codexStreamlinedLogin": true]
        )

        guard let rawURL = response.authUrl ?? response.verificationUrl,
              let url = URL(string: rawURL) else {
            throw CodexMeterError.invalidResponse
        }
        openURL(url)
        try session.waitForNotification("account/login/completed", loginId: response.loginId)
        session.stop()
        return try snapshot(codexHome: codexHome, executable: executable)
    }

    static func locateExecutable(customPath: String? = nil) -> URL? {
        let candidates = [
            customPath,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path
        ].compactMap { $0 }.filter { !$0.isEmpty }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        return CodexLaunchEnvironment.resolveNativeExecutable(URL(fileURLWithPath: path))
    }
}

enum CodexLaunchEnvironment {
    static let proxyKeys = [
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
        "http_proxy", "https_proxy", "all_proxy", "no_proxy"
    ]

    static func make(codexHome: URL, executable: URL, processEnvironment: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = processEnvironment
        merge(proxyVariables: systemProxyVariables(), into: &environment)
        environment["PATH"] = augmentedPath(environment["PATH"], executable: executable)
        environment["CODEX_HOME"] = codexHome.path
        environment["HOME"] = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        return environment
    }

    static func augmentedPath(_ existing: String?, executable: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let extras = [
            executable.deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            home.appendingPathComponent(".local/bin").path,
            "/usr/bin",
            "/bin"
        ]
        var parts = extras
        for part in (existing ?? "").split(separator: ":").map(String.init) where !part.isEmpty && !parts.contains(part) {
            parts.append(part)
        }
        return parts.joined(separator: ":")
    }

    static func resolveNativeExecutable(_ url: URL) -> URL {
        let resolved = url.resolvingSymlinksInPath()
        guard isShebangScript(resolved) else { return url }
        let packageRoot = resolved.deletingLastPathComponent().deletingLastPathComponent()
        let triple = currentTriple()
        let candidates = [
            packageRoot.appendingPathComponent("vendor/\(triple)/bin/codex"),
            packageRoot.appendingPathComponent("node_modules/@openai/codex-darwin-arm64/vendor/\(triple)/bin/codex"),
            packageRoot.appendingPathComponent("node_modules/@openai/codex-darwin-x64/vendor/\(triple)/bin/codex"),
            packageRoot.appendingPathComponent("node_modules/@openai/codex-linux-arm64/vendor/\(triple)/bin/codex"),
            packageRoot.appendingPathComponent("node_modules/@openai/codex-linux-x64/vendor/\(triple)/bin/codex")
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) ?? url
    }

    static func isShebangScript(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return handle.readData(ofLength: 2) == Data([0x23, 0x21])
    }

    static func currentTriple() -> String {
        #if arch(arm64)
        return "aarch64-apple-darwin"
        #else
        return "x86_64-apple-darwin"
        #endif
    }

    static func merge(proxyVariables: [String: String], into environment: inout [String: String]) {
        for (key, value) in proxyVariables where environment[key]?.isEmpty != false && !value.isEmpty {
            environment[key] = value
        }
    }

    static func systemProxyVariables() -> [String: String] {
        guard let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return [:] }
        var variables: [String: String] = [:]

        if let https = proxyURL(
            enabled: settings[kSCPropNetProxiesHTTPSEnable as String] as? Int,
            host: settings[kSCPropNetProxiesHTTPSProxy as String] as? String,
            port: settings[kSCPropNetProxiesHTTPSPort as String] as? Int
        ) {
            variables["HTTPS_PROXY"] = https
            variables["https_proxy"] = https
        }

        if let http = proxyURL(
            enabled: settings[kSCPropNetProxiesHTTPEnable as String] as? Int,
            host: settings[kSCPropNetProxiesHTTPProxy as String] as? String,
            port: settings[kSCPropNetProxiesHTTPPort as String] as? Int
        ) {
            variables["HTTP_PROXY"] = http
            variables["http_proxy"] = http
            if variables["HTTPS_PROXY"] == nil {
                variables["HTTPS_PROXY"] = http
                variables["https_proxy"] = http
            }
        }

        if let socks = proxyURL(
            enabled: settings[kSCPropNetProxiesSOCKSEnable as String] as? Int,
            host: settings[kSCPropNetProxiesSOCKSProxy as String] as? String,
            port: settings[kSCPropNetProxiesSOCKSPort as String] as? Int,
            scheme: "socks5"
        ), variables["HTTP_PROXY"] == nil, variables["HTTPS_PROXY"] == nil {
            variables["ALL_PROXY"] = socks
            variables["all_proxy"] = socks
        }

        if let exceptions = settings[kSCPropNetProxiesExceptionsList as String] as? [String], !exceptions.isEmpty {
            let value = exceptions.joined(separator: ",")
            variables["NO_PROXY"] = value
            variables["no_proxy"] = value
        }

        return variables
    }

    private static func proxyURL(enabled: Int?, host: String?, port: Int?, scheme: String = "http") -> String? {
        guard enabled == 1, let host, !host.isEmpty, let port, port > 0 else { return nil }
        return "\(scheme)://\(host):\(port)"
    }
}

private final class Session {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private var buffered = Data()
    private var stderr = Data()
    private let stderrLock = NSLock()
    private var nextID = 1
    private let timeout: TimeInterval
    private var deadline: Date

    init(codexHome: URL, executable: URL?, timeout: TimeInterval) throws {
        guard let executable = executable ?? CodexAppServer.locateExecutable() else {
            throw CodexMeterError.codexNotFound
        }
        self.timeout = timeout
        self.deadline = Date().addingTimeInterval(timeout)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.environment = CodexLaunchEnvironment.make(codexHome: codexHome, executable: executable)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput
        errorOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.stderrLock.lock()
            self?.stderr.append(data)
            self?.stderrLock.unlock()
        }
        try process.run()
    }

    func initialize() throws {
        let id = nextRequestID()
        try send([
            "method": "initialize",
            "id": id,
            "params": [
                "clientInfo": ["name": "codex-meter", "title": "Codex Meter", "version": "0.1.0"],
                "capabilities": ["experimentalApi": true]
            ]
        ])
        _ = try response(id: id)
        try send(["method": "initialized", "params": [:]])
    }

    func request<T: Decodable>(_ method: String, params: [String: Any] = [:], as type: T.Type = T.self) throws -> T {
        let id = nextRequestID()
        try send(["method": method, "id": id, "params": params])
        let object = try response(id: id)
        guard let result = object["result"] else {
            let message = ((object["error"] as? [String: Any])?["message"] as? String) ?? "Codex app-server request failed."
            throw CodexMeterError.server(message)
        }
        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func requestRetrying<T: Decodable>(_ method: String, params: [String: Any] = [:], as type: T.Type = T.self) throws -> T {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                return try request(method, params: params, as: type)
            } catch {
                lastError = error
                guard CodexAppServer.shouldRetry(error), attempt == 0 else { throw error }
                Thread.sleep(forTimeInterval: 1.2)
            }
        }
        throw lastError ?? CodexMeterError.invalidResponse
    }

    func waitForNotification(_ method: String, loginId: String) throws {
        while Date() < deadline {
            let object = try readObject()
            guard object["method"] as? String == method else { continue }
            let params = object["params"] as? [String: Any]
            guard params?["loginId"] as? String == loginId else { continue }
            if let success = params?["success"] as? Bool, !success {
                throw CodexMeterError.server((params?["error"] as? String) ?? "Codex login failed.")
            }
            return
        }
        throw CodexMeterError.server("Codex login timed out.")
    }

    func stop() {
        errorOutput.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    private func nextRequestID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func response(id: Int) throws -> [String: Any] {
        deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let object = try readObject()
            if object["id"] as? Int == id { return object }
        }
        throw CodexMeterError.server("Codex app-server timed out.")
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func readObject() throws -> [String: Any] {
        while Date() < deadline {
            if let newline = buffered.firstIndex(of: 0x0A) {
                let line = buffered[..<newline]
                buffered.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw CodexMeterError.invalidResponse
                }
                return object
            }
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty {
                if process.isRunning {
                    Thread.sleep(forTimeInterval: 0.05)
                    continue
                }
                throw CodexMeterError.server(stderrText().isEmpty ? "Codex app-server closed unexpectedly." : stderrText())
            }
            buffered.append(chunk)
        }
        throw CodexMeterError.server("Codex app-server timed out.")
    }

    private func stderrText() -> String {
        stderrLock.lock()
        defer { stderrLock.unlock() }
        return String(data: stderr, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

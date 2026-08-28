import Foundation

enum CodexAppServer {
    static func snapshot(codexHome: URL, executable: URL? = nil) throws -> AccountSnapshot {
        let session = try Session(codexHome: codexHome, executable: executable, timeout: 20)
        defer { session.stop() }
        try session.initialize()

        let account: AccountResponse = try session.request("account/read", params: ["refreshToken": false])
        guard let details = account.account else { throw CodexMeterError.signedOut }
        let limits: RateLimitsResponse = try session.request("account/rateLimits/read")
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
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }
}

private final class Session {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private var buffered = Data()
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
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexHome.path
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput
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
        while true {
            if let newline = buffered.firstIndex(of: 0x0A) {
                let line = buffered[..<newline]
                buffered.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw CodexMeterError.invalidResponse
                }
                return object
            }
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else {
                let errorText = String(data: errorOutput.fileHandleForReading.availableData, encoding: .utf8) ?? ""
                throw CodexMeterError.server(errorText.isEmpty ? "Codex app-server closed unexpectedly." : errorText)
            }
            buffered.append(chunk)
        }
    }
}

import Foundation
import XCTest
@testable import CodexMeter

final class ModelsTests: XCTestCase {
    @MainActor
    func testSwitchAccountUpdatesLiveCodexHome() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let support = root.appendingPathComponent("support")
        let live = root.appendingPathComponent("live")
        let firstID = UUID()
        let secondID = UUID()
        let firstHome = support.appendingPathComponent("Accounts/\(firstID.uuidString)")
        let secondHome = support.appendingPathComponent("Accounts/\(secondID.uuidString)")
        try FileManager.default.createDirectory(at: firstHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try Data("first-live".utf8).write(to: live.appendingPathComponent("auth.json"))
        try Data("first-stored".utf8).write(to: firstHome.appendingPathComponent("auth.json"))
        try Data("second-stored".utf8).write(to: secondHome.appendingPathComponent("auth.json"))

        let config: [String: Any] = [
            "profiles": [
                ["id": firstID.uuidString, "name": "First", "codexHome": firstHome.path],
                ["id": secondID.uuidString, "name": "Second", "codexHome": secondHome.path],
            ],
            "activeID": firstID.uuidString,
        ]
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: config).write(to: support.appendingPathComponent("accounts.json"))
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AccountStore(appSupport: support, liveCodexHome: live, restartsCodexDesktopOnSwitch: false)
        store.switchAccount(to: store.profiles[1])

        XCTAssertEqual(store.activeID, secondID)
        XCTAssertEqual(try Data(contentsOf: live.appendingPathComponent("auth.json")), Data("second-stored".utf8))
        XCTAssertEqual(try Data(contentsOf: firstHome.appendingPathComponent("auth.json")), Data("first-live".utf8))
        let permissions = try FileManager.default.attributesOfItem(atPath: live.appendingPathComponent("auth.json").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testDecodesRateLimits() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":37,"windowDurationMins":300,"resetsAt":1900000000},"secondary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1900100000},"credits":{"hasCredits":true,"unlimited":false,"balance":"12.50"},"individualLimit":null,"planType":"plus"},"rateLimitResetCredits":{"availableCount":2}}"#.utf8)
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        XCTAssertEqual(response.rateLimits.primary?.remainingPercent, 63)
        XCTAssertEqual(response.rateLimits.secondary?.remainingPercent, 88)
        XCTAssertEqual(response.rateLimits.credits?.balance, "12.50")
        XCTAssertEqual(response.rateLimitResetCredits?.availableCount, 2)
    }

    func testDecodesDailyActivity() throws {
        let data = Data(#"{"summary":{"lifetimeTokens":12000,"currentStreakDays":3},"dailyUsageBuckets":[{"startDate":"2026-08-27","tokens":4200}]}"#.utf8)
        let response = try JSONDecoder().decode(UsageResponse.self, from: data)
        XCTAssertEqual(response.summary.currentStreakDays, 3)
        XCTAssertEqual(response.dailyUsageBuckets?.first?.tokens, 4200)
    }

    func testRemainingPercentIsClamped() {
        XCTAssertEqual(RateLimitWindow(usedPercent: -8, windowDurationMins: nil, resetsAt: nil).remainingPercent, 100)
        XCTAssertEqual(RateLimitWindow(usedPercent: 130, windowDurationMins: nil, resetsAt: nil).remainingPercent, 0)
    }

    func testRetriesTransientAppServerTransportErrors() {
        XCTAssertTrue(CodexAppServer.shouldRetry(CodexMeterError.server("error sending request for url")))
        XCTAssertTrue(CodexAppServer.shouldRetry(CodexMeterError.server("failed to fetch codex rate limits")))
        XCTAssertTrue(CodexAppServer.shouldRetry(CodexMeterError.server("The network connection was lost")))
        XCTAssertFalse(CodexAppServer.shouldRetry(CodexMeterError.signedOut))
    }

    func testTransportErrorsUseANetworkFacingMessage() {
        let message = CodexAppServer.userFacingMessage(for: CodexMeterError.server(
            "failed to fetch codex rate limits: error sending request for url (https://chatgpt.com/backend-api/wham/usage)"
        ))
        XCTAssertTrue(message.contains("ChatGPT usage"))
        XCTAssertTrue(message.contains("proxy") || message.contains("VPN"))
        XCTAssertEqual(CodexAppServer.userFacingMessage(for: CodexMeterError.signedOut), CodexMeterError.signedOut.localizedDescription)
    }

    func testAugmentedPathIncludesHomebrewAndExecutableDirectory() {
        let executable = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let path = CodexLaunchEnvironment.augmentedPath("/usr/bin:/bin", executable: executable)
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
        XCTAssertTrue(path.split(separator: ":").contains("/opt/homebrew/bin"))
        XCTAssertTrue(path.contains("/usr/bin"))
    }

    func testMergeProxyDoesNotOverrideExistingValues() {
        var environment = ["HTTPS_PROXY": "http://127.0.0.1:9"]
        CodexLaunchEnvironment.merge(proxyVariables: ["HTTPS_PROXY": "http://example:8080", "HTTP_PROXY": "http://example:8080"], into: &environment)
        XCTAssertEqual(environment["HTTPS_PROXY"], "http://127.0.0.1:9")
        XCTAssertEqual(environment["HTTP_PROXY"], "http://example:8080")
    }

    func testResolvesNpmWrapperToNativeVendorBinary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let wrapper = root.appendingPathComponent("bin/codex.js")
        let native = root.appendingPathComponent("vendor/\(CodexLaunchEnvironment.currentTriple())/bin/codex")
        try FileManager.default.createDirectory(at: wrapper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: native.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/usr/bin/env node\n".utf8).write(to: wrapper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        try Data("native".utf8).write(to: native)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: native.path)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(CodexLaunchEnvironment.resolveNativeExecutable(wrapper), native)
        XCTAssertTrue(CodexLaunchEnvironment.isShebangScript(wrapper))
        XCTAssertFalse(CodexLaunchEnvironment.isShebangScript(native))
    }

    func testLiveOfficialAppServerWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["CODEX_METER_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_METER_LIVE_TEST=1 to test the installed official Codex app-server.")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let snapshot = try CodexAppServer.snapshot(codexHome: home)
        XCTAssertNotNil(snapshot.rateLimits?.primary)
    }

    func testLiveCursorUsageWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CURSOR_METER_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set CURSOR_METER_LIVE_TEST=1 to test the signed-in Cursor session.")
        }
        let snapshot = try await CursorUsageClient.snapshot(includeActivity: true)
        XCTAssertGreaterThanOrEqual(snapshot.planPercentUsed, 0)
        XCTAssertLessThanOrEqual(snapshot.planPercentUsed, 100)
    }
}

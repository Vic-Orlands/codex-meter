import Foundation
import XCTest
@testable import CodexMeter

final class ModelsTests: XCTestCase {
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

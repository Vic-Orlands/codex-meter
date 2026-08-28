import Foundation

struct AccountProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let codexHome: String

    var homeURL: URL { URL(fileURLWithPath: codexHome, isDirectory: true) }
}

struct AccountSnapshot: Equatable {
    var email: String?
    var planType: String?
    var rateLimits: RateLimitSnapshot?
    var resetCredits: Int?
    var usage: UsageSummary?
    var dailyUsage: [DailyUsageBucket] = []
    var fetchedAt = Date()

    static let signedOut = AccountSnapshot()
}

struct RateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot
    let rateLimitResetCredits: ResetCreditsSummary?
}

struct RateLimitSnapshot: Decodable, Equatable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: CreditsSnapshot?
    let individualLimit: SpendControlSnapshot?
    let planType: String?
}

struct RateLimitWindow: Decodable, Equatable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int?

    var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }
    var resetDate: Date? { resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
}

struct CreditsSnapshot: Decodable, Equatable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

struct SpendControlSnapshot: Decodable, Equatable {
    let limit: String
    let used: String
    let remainingPercent: Int
    let resetsAt: Int
}

struct ResetCreditsSummary: Decodable {
    let availableCount: Int
}

struct AccountResponse: Decodable {
    let account: AccountDetails?
}

struct AccountDetails: Decodable {
    let type: String
    let email: String?
    let planType: String?
}

struct UsageResponse: Decodable {
    let summary: UsageSummary
    let dailyUsageBuckets: [DailyUsageBucket]?
}

struct UsageSummary: Decodable, Equatable {
    let lifetimeTokens: Int?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
    let peakDailyTokens: Int?
    let longestRunningTurnSec: Int?
}

struct DailyUsageBucket: Decodable, Equatable {
    let startDate: String
    let tokens: Int
}

struct LoginStartResponse: Decodable {
    let type: String
    let loginId: String
    let authUrl: String?
    let verificationUrl: String?
    let userCode: String?
}

enum CodexMeterError: LocalizedError {
    case codexNotFound
    case invalidResponse
    case server(String)
    case signedOut
    case missingAuth

    var errorDescription: String? {
        switch self {
        case .codexNotFound: "Codex CLI was not found. Install it or set its path in Settings."
        case .invalidResponse: "The Codex app-server returned an unreadable response."
        case .server(let message): message
        case .signedOut: "This account is signed out."
        case .missingAuth: "No Codex auth.json was found for this account."
        }
    }
}

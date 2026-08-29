import Foundation
import SQLite3

struct CursorSnapshot: Equatable {
    let email: String?
    let membershipType: String?
    let billingCycleStart: Date?
    let billingCycleEnd: Date?
    let planUsedCents: Int
    let planLimitCents: Int
    let planPercentUsed: Double
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
    let onDemandUsedCents: Int
    let onDemandLimitCents: Int?
    var totalTokens: Int
    var dailyUsage: [DailyUsageBucket]
    let fetchedAt: Date
}

struct CursorActivitySnapshot: Equatable {
    let dailyUsage: [DailyUsageBucket]
    let totalTokens: Int
}

enum CursorProviderError: LocalizedError {
    case cursorNotInstalled
    case signedOut
    case sessionExpired
    case database(String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .cursorNotInstalled: "Cursor’s local account database was not found."
        case .signedOut: "Cursor is not signed in. Open Cursor and sign in first."
        case .sessionExpired: "Cursor’s local session has expired. Open Cursor so it can refresh the session."
        case .database(let message): "Could not read Cursor’s local session: \(message)"
        case .api(let message): "Cursor usage request failed: \(message)"
        }
    }
}

enum CursorUsageClient {
    static func snapshot(includeActivity: Bool) async throws -> CursorSnapshot {
        let token = try CursorTokenStore().load()
        let identity = try CursorIdentity(token: token)
        guard identity.expiresAt.timeIntervalSinceNow > 60 else { throw CursorProviderError.sessionExpired }

        let cookie = "WorkosCursorSessionToken=\(identity.userID)%3A%3A\(token)"
        async let summaryData = request(path: "/api/usage-summary", cookie: cookie)
        async let userData = try? request(path: "/api/auth/me", cookie: cookie)
        let summary = try JSONDecoder().decode(CursorUsageSummary.self, from: await summaryData)
        let userPayload = await userData
        let user = userPayload.flatMap { try? JSONDecoder().decode(CursorUserInfo.self, from: $0) }

        let activity = includeActivity ? (try? await fetchActivity(cookie: cookie)) : nil
        let plan = summary.individualUsage?.plan
        let overall = summary.individualUsage?.overall
        let pooled = summary.teamUsage?.pooled
        let used = plan?.used ?? overall?.used ?? pooled?.used ?? 0
        let limit = plan?.limit ?? overall?.limit ?? pooled?.limit ?? 0
        let percentage = plan?.totalPercentUsed ?? percentage(used: used, limit: limit)

        return CursorSnapshot(
            email: user?.email ?? identity.email,
            membershipType: summary.membershipType,
            billingCycleStart: parseDate(summary.billingCycleStart),
            billingCycleEnd: parseDate(summary.billingCycleEnd),
            planUsedCents: used,
            planLimitCents: limit,
            planPercentUsed: max(0, min(100, percentage)),
            autoPercentUsed: plan?.autoPercentUsed,
            apiPercentUsed: plan?.apiPercentUsed,
            onDemandUsedCents: summary.individualUsage?.onDemand?.used ?? summary.teamUsage?.onDemand?.used ?? 0,
            onDemandLimitCents: summary.individualUsage?.onDemand?.limit ?? summary.teamUsage?.onDemand?.limit,
            totalTokens: activity?.totalTokens ?? 0,
            dailyUsage: activity?.daily ?? [],
            fetchedAt: Date()
        )
    }

    static func activity() async throws -> CursorActivitySnapshot {
        let token = try CursorTokenStore().load()
        let identity = try CursorIdentity(token: token)
        guard identity.expiresAt.timeIntervalSinceNow > 60 else { throw CursorProviderError.sessionExpired }
        let cookie = "WorkosCursorSessionToken=\(identity.userID)%3A%3A\(token)"
        let activity = try await fetchActivity(cookie: cookie)
        return CursorActivitySnapshot(dailyUsage: activity.daily, totalTokens: activity.totalTokens)
    }

    private static func request(path: String, cookie: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://cursor.com\(path)")!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CursorProviderError.api("Invalid response") }
        if response.statusCode == 401 || response.statusCode == 403 { throw CursorProviderError.sessionExpired }
        guard response.statusCode == 200 else { throw CursorProviderError.api("HTTP \(response.statusCode)") }
        return data
    }

    private static func fetchActivity(cookie: String) async throws -> (daily: [DailyUsageBucket], totalTokens: Int) {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.date(byAdding: .day, value: -111, to: calendar.startOfDay(for: Date()))!
        var events: [CursorUsageEvent] = []

        for page in 1...20 {
            var request = URLRequest(url: URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            request.httpBody = try JSONEncoder().encode(CursorUsageEventsRequest(
                page: page,
                pageSize: 1000,
                startDate: String(Int64(start.timeIntervalSince1970 * 1000)),
                endDate: String(Int64(Date().timeIntervalSince1970 * 1000))
            ))

            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw CursorProviderError.api("Token history is unavailable")
            }
            let result = try JSONDecoder().decode(CursorUsageEventsPage.self, from: data)
            events.append(contentsOf: result.usageEventsDisplay)
            if result.usageEventsDisplay.count < 1000 { break }
        }

        var daily: [String: Int] = [:]
        var total = 0
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        for event in events {
            guard let timestamp = event.timestampMS, timestamp > 0 else { continue }
            let tokens = event.tokenUsage?.totalTokens ?? 0
            guard tokens > 0 else { continue }
            let key = formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000))
            daily[key, default: 0] += tokens
            total += tokens
        }

        return (daily.keys.sorted().map { DailyUsageBucket(startDate: $0, tokens: daily[$0] ?? 0) }, total)
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private static func percentage(used: Int, limit: Int) -> Double {
        guard limit > 0 else { return 0 }
        return Double(used) / Double(limit) * 100
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct CursorTokenStore {
    private let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path

    func load() throws -> String {
        guard FileManager.default.fileExists(atPath: path) else { throw CursorProviderError.cursorNotInstalled }
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = database.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:)) ?? "SQLite open failed"
            sqlite3_close(database)
            throw CursorProviderError.database(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM ItemTable WHERE key = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK else {
            throw CursorProviderError.database("Could not prepare the read-only query")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, "cursorAuth/accessToken", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) else {
            throw CursorProviderError.signedOut
        }
        let token = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw CursorProviderError.signedOut }
        return token
    }
}

private struct CursorIdentity {
    let userID: String
    let email: String?
    let expiresAt: Date

    init(token: String) throws {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { throw CursorProviderError.signedOut }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = object["sub"] as? String,
              let expiration = object["exp"] as? NSNumber,
              let userID = subject.split(separator: "|").last.map(String.init),
              !userID.isEmpty else {
            throw CursorProviderError.signedOut
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard userID.unicodeScalars.allSatisfy(allowed.contains) else { throw CursorProviderError.signedOut }
        self.userID = userID
        self.email = object["email"] as? String
        self.expiresAt = Date(timeIntervalSince1970: expiration.doubleValue)
    }
}

private struct CursorUsageSummary: Decodable {
    let billingCycleStart: String?
    let billingCycleEnd: String?
    let membershipType: String?
    let individualUsage: CursorIndividualUsage?
    let teamUsage: CursorTeamUsage?
}

private struct CursorIndividualUsage: Decodable {
    let plan: CursorPlanUsage?
    let onDemand: CursorMoneyUsage?
    let overall: CursorMoneyUsage?
}

private struct CursorTeamUsage: Decodable {
    let onDemand: CursorMoneyUsage?
    let pooled: CursorMoneyUsage?
}

private struct CursorPlanUsage: Decodable {
    let used: Int?
    let limit: Int?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
    let totalPercentUsed: Double?
}

private struct CursorMoneyUsage: Decodable {
    let used: Int?
    let limit: Int?
}

private struct CursorUserInfo: Decodable {
    let email: String?
}

private struct CursorUsageEventsRequest: Encodable {
    let page: Int
    let pageSize: Int
    let startDate: String
    let endDate: String
}

private struct CursorUsageEventsPage: Decodable {
    let usageEventsDisplay: [CursorUsageEvent]

    private enum CodingKeys: String, CodingKey { case usageEventsDisplay }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usageEventsDisplay = (try? container.decode([CursorUsageEvent].self, forKey: .usageEventsDisplay)) ?? []
    }
}

private struct CursorUsageEvent: Decodable {
    let timestampMS: Int64?
    let tokenUsage: CursorEventTokenUsage?

    private enum CodingKeys: String, CodingKey { case timestamp, tokenUsage }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestampMS = Self.int64(container, key: .timestamp)
        tokenUsage = try? container.decode(CursorEventTokenUsage.self, forKey: .tokenUsage)
    }

    private static func int64(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int64? {
        if let value = try? container.decode(Int64.self, forKey: key) { return value }
        if let value = try? container.decode(String.self, forKey: key) { return Int64(value) }
        if let value = try? container.decode(Double.self, forKey: key) { return Int64(exactly: value) }
        return nil
    }
}

private struct CursorEventTokenUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int
    let cacheReadTokens: Int

    private enum CodingKeys: String, CodingKey { case inputTokens, outputTokens, cacheWriteTokens, cacheReadTokens }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = Self.int(container, key: .inputTokens)
        outputTokens = Self.int(container, key: .outputTokens)
        cacheWriteTokens = Self.int(container, key: .cacheWriteTokens)
        cacheReadTokens = Self.int(container, key: .cacheReadTokens)
    }

    var totalTokens: Int {
        [inputTokens, outputTokens, cacheWriteTokens, cacheReadTokens].reduce(0) { partial, value in
            value > 0 ? partial + value : partial
        }
    }

    private static func int(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(String.self, forKey: key) { return Int(value) ?? 0 }
        if let value = try? container.decode(Double.self, forKey: key) { return Int(exactly: value) ?? 0 }
        return 0
    }
}

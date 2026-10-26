import CryptoKit
import Foundation

/// The `sessionKey` cookies of Claude Desktop's signed-in claude.ai sessions: the default profile plus
/// any Parall-wrapped copies (each keeps its own `--user-data-dir` under `Parall/<name>`). They share
/// Desktop's "Claude Safe Storage" key, the same one `ClaudeDesktopAuthStore` already reads.
struct ClaudeDesktopSessionReader: Sendable {
    private static let profileRoots = ["Library/Application Support/Claude"]
    private static let parallRoot = "Library/Application Support/Parall"
    private static let cookieFiles = ["Cookies", "Network/Cookies"]
    private static let host = ".claude.ai"

    var sqlite: SQLiteAccessing = SQLiteCLIAccessor()
    var keyReader: ClaudeDesktopSafeStorageKeyReading = ClaudeDesktopSafeStorageKeyReader()
    var homeDirectory: @Sendable () -> URL = { FileManager.default.homeDirectoryForCurrentUser }
    var keyCache = SafeStorageKeyCache()

    func sessionKeys() throws -> [String] {
        let databases = cookieDatabases()
        guard !databases.isEmpty else { return [] }
        guard let key = try safeStorageKey() else { return [] }
        let sql = """
        SELECT hex(encrypted_value) FROM cookies
        WHERE name = 'sessionKey' AND host_key = '\(Self.host)'
        ORDER BY last_update_utc DESC LIMIT 1;
        """
        let hostHash = Data(SHA256.hash(data: Data(Self.host.utf8)))
        var keys: [String] = []
        for database in databases {
            guard let hex = try sqlite.queryValue(path: database, sql: sql),
                  let stored = Data(hexString: hex)
            else { continue }
            let decrypted = try ClaudeDesktopAuthStore.decrypt(stored, key: key)
            guard decrypted.starts(with: hostHash),
                  let session = String(data: decrypted.dropFirst(hostHash.count), encoding: .utf8),
                  session.hasPrefix("sk-ant-"),
                  !keys.contains(session)
            else { continue }
            keys.append(session)
        }
        return keys
    }

    private func cookieDatabases() -> [String] {
        let home = homeDirectory()
        let fileManager = FileManager.default
        let parall = home.appendingPathComponent(Self.parallRoot)
        let parallProfiles = ((try? fileManager.contentsOfDirectory(atPath: parall.path)) ?? [])
            .sorted()
            .map { "\(Self.parallRoot)/\($0)" }
        return (Self.profileRoots + parallProfiles).flatMap { root in
            Self.cookieFiles.map { home.appendingPathComponent(root).appendingPathComponent($0).path }
        }
        .filter { fileManager.fileExists(atPath: $0) }
    }

    private func safeStorageKey() throws -> Data? {
        if let cached = keyCache.value { return cached }
        guard let password = try keyReader.readPassword(allowInteraction: false) else { return nil }
        let key = try ClaudeDesktopAuthStore.deriveKey(password: password)
        keyCache.value = key
        return key
    }
}

/// Real Claude billing dates from `claude.ai/api/organizations/{org}/subscription_details`, the endpoint
/// claude.ai's billing settings read. It refuses OAuth tokens, so it goes through a Claude Desktop
/// session (opt-in, `ClaudeDesktopBillingSetting`). Results are shared across Claude cards and kept for
/// an hour: billing changes rarely and every card would otherwise repeat the same calls.
actor ClaudeDesktopBilling {
    static let shared = ClaudeDesktopBilling()
    private static let ttl: TimeInterval = 60 * 60

    private let sessions: ClaudeDesktopSessionReader
    private let http: HTTPClient
    private let now: @Sendable () -> Date
    private var cache: [String: (renewal: SubscriptionRenewal?, fetchedAt: Date)] = [:]

    init(
        sessions: ClaudeDesktopSessionReader = ClaudeDesktopSessionReader(),
        http: HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.sessions = sessions
        self.http = http
        self.now = now
    }

    func renewal(organization: String) async -> SubscriptionRenewal? {
        let organization = organization.lowercased()
        if let cached = cache[organization], now().timeIntervalSince(cached.fetchedAt) < Self.ttl {
            return cached.renewal
        }
        let renewal = await fetch(organization: organization)
        cache[organization] = (renewal, now())
        return renewal
    }

    /// Tries each Desktop session in turn: a session only sees the organizations its login belongs to.
    private func fetch(organization: String) async -> SubscriptionRenewal? {
        let keys: [String]
        do {
            keys = try sessions.sessionKeys()
        } catch ClaudeDesktopCredentialError.permissionRequired {
            AppLog.warn(LogTag.plugin("claude"), "Claude Desktop billing: keychain access to Claude Safe Storage not granted")
            return nil
        } catch {
            AppLog.error(LogTag.plugin("claude"), "Claude Desktop billing: session read failed: \(error.localizedDescription)")
            return nil
        }
        guard let url = URL(string: "https://claude.ai/api/organizations/\(organization)/subscription_details") else {
            return nil
        }
        for key in keys {
            let response: HTTPResponse
            do {
                response = try await http.send(HTTPRequest(
                    method: "GET",
                    url: url,
                    headers: ["Cookie": "sessionKey=\(key)", "Accept": "application/json", "User-Agent": "OpenUsage"],
                    timeout: 10
                ))
            } catch {
                AppLog.warn(LogTag.plugin("claude"), "Claude Desktop billing request failed: \(error.localizedDescription)")
                return nil
            }
            if [401, 403, 404].contains(response.statusCode) { continue }
            guard (200..<300).contains(response.statusCode) else {
                AppLog.warn(LogTag.plugin("claude"), "Claude Desktop billing returned HTTP \(response.statusCode)")
                return nil
            }
            return Self.renewal(subscriptionDetails: response.body)
        }
        AppLog.info(LogTag.plugin("claude"), "Claude Desktop billing: no Desktop session for this organization (\(keys.count) checked)")
        return nil
    }

    static func renewal(subscriptionDetails body: Data) -> SubscriptionRenewal? {
        guard let details = ProviderParse.jsonObject(body),
              let status = details["status"] as? String,
              ["active", "trialing", "past_due"].contains(status)
        else { return nil }

        if let end = date(details["plan_ending_at"]) ?? date(details["plan_ending_before"]) {
            return SubscriptionRenewal(date: end, status: .ends)
        }
        if let downgrade = details["scheduled_downgrade"] as? [String: Any], let when = date(downgrade["date"]) {
            return SubscriptionRenewal(date: when, status: .downgrades, newPlan: planName(downgrade["plan_type"]))
        }
        return (date(details["next_charge_at"]) ?? date(details["next_charge_date"]))
            .map { SubscriptionRenewal(date: $0, status: .renews) }
    }

    /// `max_5x_monthly` → "Max 5x", `pro_annual` → "Pro".
    static func planName(_ value: Any?) -> String? {
        guard var plan = (value as? String)?.lowercased(), !plan.isEmpty else { return nil }
        for suffix in ["_monthly", "_annual", "_yearly"] where plan.hasSuffix(suffix) {
            plan.removeLast(suffix.count)
        }
        return plan.split(separator: "_")
            .map { $0.first?.isNumber == true ? String($0) : $0.capitalized }
            .joined(separator: " ")
    }

    /// Timestamps, or the legacy UTC calendar dates (`2026-11-13`), which read as midday UTC so they stay
    /// on the same calendar day in every time zone the UI renders in.
    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        if text.count == 10 { return OpenUsageISO8601.date(from: text + "T12:00:00Z") }
        return OpenUsageISO8601.date(from: text)
    }
}

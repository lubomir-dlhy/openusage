import Foundation

struct ClaudeRefreshResponse: Decodable, Hashable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Double?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct ClaudeProfileResponse: Decodable, Hashable, Sendable {
    struct Account: Decodable, Hashable, Sendable {
        var hasClaudeMax: Bool?
        var hasClaudePro: Bool?

        enum CodingKeys: String, CodingKey {
            case hasClaudeMax = "has_claude_max"
            case hasClaudePro = "has_claude_pro"
        }
    }

    struct Organization: Decodable, Hashable, Sendable {
        var organizationType: String?
        var rateLimitTier: String?

        enum CodingKeys: String, CodingKey {
            case organizationType = "organization_type"
            case rateLimitTier = "rate_limit_tier"
        }
    }

    var account: Account?
    var organization: Organization?
}

enum ClaudeUsageError: Error, LocalizedError, Equatable {
    case connectionFailed
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return ProviderUsageErrorText.connectionFailed
        case .invalidResponse:
            return ProviderUsageErrorText.invalidResponse
        case .requestFailed(let statusCode):
            return ProviderUsageErrorText.requestFailed(statusCode: statusCode)
        }
    }
}

struct ClaudeUsageClient: Sendable {
    private static let scopes = "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"

    var httpClient: HTTPClient

    init(httpClient: HTTPClient = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    func refreshToken(_ refreshToken: String, config: ClaudeOAuthConfig) async throws -> HTTPResponse {
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
            "scope": Self.scopes
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        return try await httpClient.send(
            HTTPRequest(
                method: "POST",
                url: config.refreshURL,
                headers: ["Content-Type": "application/json"],
                body: bodyData,
                timeout: 15
            )
        )
    }

    func fetchUsage(accessToken: String, config: ClaudeOAuthConfig) async throws -> HTTPResponse {
        try await httpClient.send(
            HTTPRequest(
                method: "GET",
                url: config.usageURL,
                headers: [
                    "Authorization": "Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))",
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "anthropic-beta": "oauth-2025-04-20",
                    "User-Agent": "claude-code/2.1.69"
                ],
                timeout: 10
            )
        )
    }

    func fetchProfile(accessToken: String, config: ClaudeOAuthConfig) async throws -> HTTPResponse {
        try await httpClient.send(
            HTTPRequest(
                method: "GET",
                url: config.profileURL,
                headers: [
                    "Authorization": "Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))",
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "User-Agent": "claude-code/2.1.69"
                ],
                timeout: 10
            )
        )
    }
}

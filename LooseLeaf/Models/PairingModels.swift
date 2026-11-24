import Foundation

// MARK: - OAuth2 / OIDC 账号会话模型

public struct AccountProfile: Codable, Equatable, Sendable {
    public var sub: String?
    public var name: String?
    public var email: String?

    public init(sub: String? = nil, name: String? = nil, email: String? = nil) {
        self.sub = sub
        self.name = name
        self.email = email
    }
}

public struct ConfirmPairingRequest: Codable, Sendable {
    public var code: String?
    public var ticket: String?
    public var deviceName: String
    public var platform: String
    public var deviceModel: String

    enum CodingKeys: String, CodingKey {
        case code
        case ticket
        case deviceName = "device_name"
        case platform
        case deviceModel = "device_model"
    }

    public init(
        code: String? = nil,
        ticket: String? = nil,
        deviceName: String,
        platform: String = "macos",
        deviceModel: String = "Mac"
    ) {
        self.code = code ?? ticket
        self.ticket = ticket ?? code
        self.deviceName = deviceName
        self.platform = platform
        self.deviceModel = deviceModel
    }
}

public struct ConfirmPairingResponse: Codable, Sendable {
    public var accessToken: String?
    public var sessionId: String?
    public var deviceId: String
    public var deviceName: String
    public var platform: String
    public var pairedAt: String
    public var deviceToken: String
    public var initialized: Bool
    public var hubUrl: String?
    public var account: AccountProfile?

    public var resolvedToken: String {
        if let token = accessToken, !token.isEmpty { return token }
        return deviceToken
    }

    public var resolvedSessionId: String {
        if let sid = sessionId, !sid.isEmpty { return sid }
        return deviceId
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case sessionId = "session_id"
        case deviceId = "device_id"
        case deviceName = "device_name"
        case platform
        case pairedAt = "paired_at"
        case deviceToken = "device_token"
        case initialized
        case hubUrl = "hub_url"
        case account
    }
}

public struct AuthSessionResponse: Codable, Sendable {
    public var isAdmin: Bool
    public var role: String
    public var sessionId: String?
    public var deviceId: String?
    public var platform: String?
    public var account: AccountProfile?

    enum CodingKeys: String, CodingKey {
        case isAdmin = "is_admin"
        case role
        case sessionId = "session_id"
        case deviceId = "device_id"
        case platform
        case account
    }
}

public struct LogoutResponse: Codable, Sendable {
    public var loggedOut: Bool?

    enum CodingKeys: String, CodingKey {
        case loggedOut = "logged_out"
    }
}

public struct TrustedDevice: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var deviceId: String
    public var name: String
    public var platform: String
    public var deviceModel: String?
    public var status: String
    public var pairedAt: String
    public var lastActiveAt: String
    public var isCurrent: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case name
        case platform
        case deviceModel = "device_model"
        case status
        case pairedAt = "paired_at"
        case lastActiveAt = "last_active_at"
        case isCurrent = "is_current"
    }
}

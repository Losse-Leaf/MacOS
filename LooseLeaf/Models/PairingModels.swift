import Foundation

// MARK: - 设备免密配对与鉴权模型 (Device Pairing & Auth)

public struct ConfirmPairingRequest: Codable, Sendable {
    public var ticket: String?
    public var deviceName: String
    public var platform: String
    public var deviceModel: String

    enum CodingKeys: String, CodingKey {
        case ticket
        case deviceName = "device_name"
        case platform
        case deviceModel = "device_model"
    }

    public init(
        ticket: String? = nil,
        deviceName: String,
        platform: String = "macos",
        deviceModel: String = "Mac"
    ) {
        self.ticket = ticket
        self.deviceName = deviceName
        self.platform = platform
        self.deviceModel = deviceModel
    }
}

public struct ConfirmPairingResponse: Codable, Sendable {
    public var deviceId: String
    public var deviceName: String
    public var platform: String
    public var pairedAt: String
    public var deviceToken: String
    public var initialized: Bool
    public var hubUrl: String?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
        case platform
        case pairedAt = "paired_at"
        case deviceToken = "device_token"
        case initialized
        case hubUrl = "hub_url"
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

import Foundation

/// 主理人身份档案 (CuratorProfile)
/// 严格遵守：全数据后端动态下发，空态优先，严禁在客户端硬编码人名、地名或版权信息
public struct CuratorProfile: Codable, Equatable, Sendable {
    public var name: String
    public var title: String
    public var bio: String
    public var location: String
    public var currentCity: String
    public var avatarUrl: String
    public var avatarKey: String?
    public var motto: String
    public var manifesto: String
    public var email: String?
    public var github: String?
    public var socialLinks: [String: String]?
    public var edcGear: [GearItem]
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case name
        case title
        case bio
        case location
        case currentCity = "current_city"
        case avatarUrl = "avatar_url"
        case avatarKey = "avatar_key"
        case motto
        case manifesto
        case email
        case github
        case socialLinks = "social_links"
        case edcGear = "edc_gear"
        case updatedAt = "updated_at"
    }

    public init(
        name: String = "",
        title: String = "",
        bio: String = "",
        location: String = "",
        currentCity: String = "",
        avatarUrl: String = "",
        avatarKey: String? = nil,
        motto: String = "",
        manifesto: String = "",
        email: String? = nil,
        github: String? = nil,
        socialLinks: [String: String]? = nil,
        edcGear: [GearItem] = [],
        updatedAt: String? = nil
    ) {
        self.name = name
        self.title = title
        self.bio = bio
        self.location = location
        self.currentCity = currentCity
        self.avatarUrl = avatarUrl
        self.avatarKey = avatarKey
        self.motto = motto
        self.manifesto = manifesto
        self.email = email
        self.github = github
        self.socialLinks = socialLinks
        self.edcGear = edcGear
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        bio = (try? container.decode(String.self, forKey: .bio)) ?? ""
        location = (try? container.decode(String.self, forKey: .location)) ?? ""
        currentCity = (try? container.decode(String.self, forKey: .currentCity)) ?? ""
        avatarUrl = (try? container.decode(String.self, forKey: .avatarUrl)) ?? ""
        avatarKey = try? container.decodeIfPresent(String.self, forKey: .avatarKey)
        motto = (try? container.decode(String.self, forKey: .motto)) ?? ""
        manifesto = (try? container.decode(String.self, forKey: .manifesto)) ?? ""
        email = try? container.decodeIfPresent(String.self, forKey: .email)
        github = try? container.decodeIfPresent(String.self, forKey: .github)
        socialLinks = try? container.decodeIfPresent([String: String].self, forKey: .socialLinks)
        edcGear = (try? container.decodeIfPresent([GearItem].self, forKey: .edcGear)) ?? []
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    /// 动态展示当前所在地点（优先 current_city，回退 location，为空则返回空字符串）
    public var displayCity: String {
        if !currentCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return currentCity
        }
        return location
    }
}

/// 更新主理人档案请求载荷 (PUT /api/v1/profile)
/// 遵循 RC-132 定案：不携带 edc_gear，防止覆盖独立设备生命周期接口
public struct UpdateProfileRequest: Codable, Sendable {
    public var name: String?
    public var title: String?
    public var bio: String?
    public var location: String?
    public var currentCity: String?
    public var avatarKey: String?
    public var motto: String?
    public var manifesto: String?
    public var email: String?
    public var github: String?

    enum CodingKeys: String, CodingKey {
        case name
        case title
        case bio
        case location
        case currentCity = "current_city"
        case avatarKey = "avatar_key"
        case motto
        case manifesto
        case email
        case github
    }

    public init(
        name: String? = nil,
        title: String? = nil,
        bio: String? = nil,
        location: String? = nil,
        currentCity: String? = nil,
        avatarKey: String? = nil,
        motto: String? = nil,
        manifesto: String? = nil,
        email: String? = nil,
        github: String? = nil
    ) {
        self.name = name
        self.title = title
        self.bio = bio
        self.location = location
        self.currentCity = currentCity
        self.avatarKey = avatarKey
        self.motto = motto
        self.manifesto = manifesto
        self.email = email
        self.github = github
    }
}

/// 站点全局配置 (SiteConfig, GET /api/v1/config)
public struct SiteConfig: Codable, Equatable, Sendable {
    public var siteName: String
    public var siteSubtitle: String?
    public var siteDesc: String?
    public var curatorName: String
    public var defaultLocation: String
    public var initialized: Bool
    public var initialLiquidBalance: Int64?

    enum CodingKeys: String, CodingKey {
        case siteName = "site_name"
        case siteSubtitle = "site_subtitle"
        case siteDesc = "site_desc"
        case curatorName = "curator_name"
        case defaultLocation = "default_location"
        case initialized
        case initialLiquidBalance = "initial_liquid_balance"
    }

    public init(
        siteName: String = "",
        siteSubtitle: String? = nil,
        siteDesc: String? = nil,
        curatorName: String = "",
        defaultLocation: String = "",
        initialized: Bool = false,
        initialLiquidBalance: Int64? = 0
    ) {
        self.siteName = siteName
        self.siteSubtitle = siteSubtitle
        self.siteDesc = siteDesc
        self.curatorName = curatorName
        self.defaultLocation = defaultLocation
        self.initialized = initialized
        self.initialLiquidBalance = initialLiquidBalance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        siteName = (try? container.decode(String.self, forKey: .siteName)) ?? ""
        siteSubtitle = try? container.decodeIfPresent(String.self, forKey: .siteSubtitle)
        siteDesc = try? container.decodeIfPresent(String.self, forKey: .siteDesc)
        curatorName = (try? container.decode(String.self, forKey: .curatorName)) ?? ""
        defaultLocation = (try? container.decode(String.self, forKey: .defaultLocation)) ?? ""
        initialized = (try? container.decode(Bool.self, forKey: .initialized)) ?? false
        initialLiquidBalance = try? container.decodeIfPresent(Int64.self, forKey: .initialLiquidBalance)
    }
}

/// 系统初始化状态探针 (GET /api/v1/system/status)
public struct SystemStatus: Codable, Equatable, Sendable {
    public var initialized: Bool
    public var hasPasscodeSet: Bool
    public var siteName: String
    public var curatorName: String

    enum CodingKeys: String, CodingKey {
        case initialized
        case hasPasscodeSet = "has_passcode_set"
        case siteName = "site_name"
        case curatorName = "curator_name"
    }
}

// MARK: - 设备免密配对与鉴权模型 (Device Pairing & Auth)

public struct ConfirmPairingRequest: Codable, Sendable {
    public var ticket: String?
    public var pinCode: String?
    public var deviceName: String
    public var platform: String
    public var deviceModel: String

    enum CodingKeys: String, CodingKey {
        case ticket
        case pinCode = "pin_code"
        case deviceName = "device_name"
        case platform
        case deviceModel = "device_model"
    }

    public init(
        ticket: String? = nil,
        pinCode: String? = nil,
        deviceName: String,
        platform: String = "macos",
        deviceModel: String = "Mac"
    ) {
        self.ticket = ticket
        self.pinCode = pinCode
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

public struct VerifyPasscodeRequest: Codable, Sendable {
    public var passcode: String
    public var deviceName: String

    enum CodingKeys: String, CodingKey {
        case passcode
        case deviceName = "device_name"
    }

    public init(passcode: String, deviceName: String) {
        self.passcode = passcode
        self.deviceName = deviceName
    }
}

public struct VerifyPasscodeResponse: Codable, Sendable {
    public var token: String
    public var deviceId: String
    public var deviceName: String

    enum CodingKeys: String, CodingKey {
        case token
        case deviceId = "device_id"
        case deviceName = "device_name"
    }
}

public struct PairInitRequest: Codable, Sendable {
    public var hubUrl: String?
    public var deviceHint: String?

    enum CodingKeys: String, CodingKey {
        case hubUrl = "hub_url"
        case deviceHint = "device_hint"
    }

    public init(hubUrl: String? = nil, deviceHint: String? = nil) {
        self.hubUrl = hubUrl
        self.deviceHint = deviceHint
    }
}

public struct PairTicketResponse: Codable, Equatable, Sendable {
    public var ticket: String
    public var pinCode: String
    public var hubUrl: String
    public var qrPayload: String
    public var qrCodeDataUrl: String?
    public var expiresAt: String
    public var expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case ticket
        case pinCode = "pin_code"
        case hubUrl = "hub_url"
        case qrPayload = "qr_payload"
        case qrCodeDataUrl = "qr_code_data_url"
        case expiresAt = "expires_at"
        case expiresInSeconds = "expires_in_seconds"
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

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case name
        case platform
        case deviceModel = "device_model"
        case status
        case pairedAt = "paired_at"
        case lastActiveAt = "last_active_at"
    }
}

// MARK: - 造物、三维心愿与山川足迹模型

public struct Project: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var subtitle: String?
    public var description: String
    public var story: String?
    public var category: String?
    public var githubUrl: String?
    public var status: String?
    public var featured: Bool?
    public var order: Int?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case description
        case story
        case category
        case githubUrl = "github_url"
        case status
        case featured
        case order
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: Int,
        title: String,
        subtitle: String? = nil,
        description: String,
        story: String? = nil,
        category: String? = nil,
        githubUrl: String? = nil,
        status: String? = "Active",
        featured: Bool? = false,
        order: Int? = 0,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.story = story
        self.category = category
        self.githubUrl = githubUrl
        self.status = status
        self.featured = featured
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Wish: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var kind: String // "item" | "travel" | "milestone"
    public var note: String?
    public var spec: String?
    public var cityCode: String?
    public var cityName: String?
    public var budget: Int64 // 单位：分
    public var actualCost: Int64 // 单位：分
    public var resolutionType: String?
    public var actualTitle: String?
    public var targetDate: String?
    public var status: String // "wanting" | "fulfilled" | "relinquished" | "shelved"
    public var fulfilledAt: String?
    public var transactionId: Int?
    public var lifeEntryId: Int?
    public var footprintId: Int?
    public var gearId: String?
    public var attachments: [Attachment]
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case note
        case spec
        case cityCode = "city_code"
        case cityName = "city_name"
        case budget
        case actualCost = "actual_cost"
        case resolutionType = "resolution_type"
        case actualTitle = "actual_title"
        case targetDate = "target_date"
        case status
        case fulfilledAt = "fulfilled_at"
        case transactionId = "transaction_id"
        case lifeEntryId = "life_entry_id"
        case footprintId = "footprint_id"
        case gearId = "gear_id"
        case attachments
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        kind = (try? container.decode(String.self, forKey: .kind)) ?? "item"
        note = try? container.decodeIfPresent(String.self, forKey: .note)
        spec = try? container.decodeIfPresent(String.self, forKey: .spec)
        cityCode = try? container.decodeIfPresent(String.self, forKey: .cityCode)
        cityName = try? container.decodeIfPresent(String.self, forKey: .cityName)
        budget = (try? container.decode(Int64.self, forKey: .budget)) ?? 0
        actualCost = (try? container.decode(Int64.self, forKey: .actualCost)) ?? 0
        resolutionType = try? container.decodeIfPresent(String.self, forKey: .resolutionType)
        actualTitle = try? container.decodeIfPresent(String.self, forKey: .actualTitle)
        targetDate = try? container.decodeIfPresent(String.self, forKey: .targetDate)
        status = (try? container.decode(String.self, forKey: .status)) ?? "wanting"
        fulfilledAt = try? container.decodeIfPresent(String.self, forKey: .fulfilledAt)
        transactionId = try? container.decodeIfPresent(Int.self, forKey: .transactionId)
        lifeEntryId = try? container.decodeIfPresent(Int.self, forKey: .lifeEntryId)
        footprintId = try? container.decodeIfPresent(Int.self, forKey: .footprintId)
        gearId = try? container.decodeIfPresent(String.self, forKey: .gearId)
        attachments = (try? container.decodeIfPresent([Attachment].self, forKey: .attachments)) ?? []
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public init(
        id: Int,
        title: String,
        kind: String = "item",
        note: String? = nil,
        spec: String? = nil,
        cityCode: String? = nil,
        cityName: String? = nil,
        budget: Int64 = 0,
        actualCost: Int64 = 0,
        status: String = "wanting",
        attachments: [Attachment] = []
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.note = note
        self.spec = spec
        self.cityCode = cityCode
        self.cityName = cityName
        self.budget = budget
        self.actualCost = actualCost
        self.status = status
        self.attachments = attachments
    }
}

public struct WishesListResponse: Codable, Sendable {
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let wishes: [Wish]

    enum CodingKeys: String, CodingKey {
        case total
        case page
        case pageSize = "page_size"
        case wishes
    }
}

public struct CreateWishRequest: Codable, Sendable {
    public var title: String
    public var kind: String
    public var note: String?
    public var spec: String?
    public var cityCode: String?
    public var cityName: String?
    public var budget: Int64
    public var targetDate: String?
    public var attachmentIds: [Int]

    enum CodingKeys: String, CodingKey {
        case title
        case kind
        case note
        case spec
        case cityCode = "city_code"
        case cityName = "city_name"
        case budget
        case targetDate = "target_date"
        case attachmentIds = "attachment_ids"
    }

    public init(
        title: String,
        kind: String = "item",
        note: String? = nil,
        spec: String? = nil,
        cityCode: String? = nil,
        cityName: String? = nil,
        budget: Int64 = 0,
        targetDate: String? = nil,
        attachmentIds: [Int] = []
    ) {
        self.title = title
        self.kind = kind
        self.note = note
        self.spec = spec
        self.cityCode = cityCode
        self.cityName = cityName
        self.budget = budget
        self.targetDate = targetDate
        self.attachmentIds = attachmentIds
    }
}

public struct Footprint: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var cityCode: String
    public var cityName: String
    public var title: String?
    public var visitedAt: String
    public var departedAt: String?
    public var note: String?
    public var lifeEntryId: Int?
    public var wishId: Int?
    public var attachments: [Attachment]
    public var entriesCount: Int?
    public var totalSpent: Int64?
    public var transactionCount: Int?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case cityCode = "city_code"
        case cityName = "city_name"
        case title
        case visitedAt = "visited_at"
        case departedAt = "departed_at"
        case note
        case lifeEntryId = "life_entry_id"
        case wishId = "wish_id"
        case attachments
        case entriesCount = "entries_count"
        case totalSpent = "total_spent"
        case transactionCount = "transaction_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        cityCode = (try? container.decode(String.self, forKey: .cityCode)) ?? ""
        cityName = (try? container.decode(String.self, forKey: .cityName)) ?? ""
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        visitedAt = (try? container.decode(String.self, forKey: .visitedAt)) ?? FormatUtils.beijingISOString()
        departedAt = try? container.decodeIfPresent(String.self, forKey: .departedAt)
        note = try? container.decodeIfPresent(String.self, forKey: .note)
        lifeEntryId = try? container.decodeIfPresent(Int.self, forKey: .lifeEntryId)
        wishId = try? container.decodeIfPresent(Int.self, forKey: .wishId)
        attachments = (try? container.decodeIfPresent([Attachment].self, forKey: .attachments)) ?? []
        entriesCount = try? container.decodeIfPresent(Int.self, forKey: .entriesCount)
        totalSpent = try? container.decodeIfPresent(Int64.self, forKey: .totalSpent)
        transactionCount = try? container.decodeIfPresent(Int.self, forKey: .transactionCount)
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

public struct CreateFootprintRequest: Codable, Sendable {
    public var cityCode: String
    public var cityName: String
    public var title: String?
    public var visitedAt: String
    public var departedAt: String?
    public var note: String?
    public var attachmentIds: [Int]

    enum CodingKeys: String, CodingKey {
        case cityCode = "city_code"
        case cityName = "city_name"
        case title
        case visitedAt = "visited_at"
        case departedAt = "departed_at"
        case note
        case attachmentIds = "attachment_ids"
    }

    public init(
        cityCode: String,
        cityName: String,
        title: String? = nil,
        visitedAt: String = FormatUtils.beijingDateString(),
        departedAt: String? = nil,
        note: String? = nil,
        attachmentIds: [Int] = []
    ) {
        self.cityCode = cityCode
        self.cityName = cityName
        self.title = title
        self.visitedAt = visitedAt
        self.departedAt = departedAt
        self.note = note
        self.attachmentIds = attachmentIds
    }
}

// MARK: - 媒体预签名与直传载荷 (R2 Presign & Unified Upload)

public struct PresignUploadRequest: Codable, Sendable {
    public var filename: String
    public var contentType: String
    public var size: Int64

    enum CodingKeys: String, CodingKey {
        case filename
        case contentType = "content_type"
        case size
    }

    public init(filename: String, contentType: String, size: Int64) {
        self.filename = filename
        self.contentType = contentType
        self.size = size
    }
}

public struct PresignUploadResponse: Codable, Sendable {
    public var uploadId: String
    public var objectKey: String
    public var uploadUrl: String
    public var expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case uploadId = "upload_id"
        case objectKey = "object_key"
        case uploadUrl = "upload_url"
        case expiresIn = "expires_in"
    }
}

public struct CompleteUploadRequest: Codable, Sendable {
    public var uploadId: String
    public var objectKey: String
    public var originalFilename: String
    public var mimeType: String
    public var size: Int64
    public var width: Int
    public var height: Int

    enum CodingKeys: String, CodingKey {
        case uploadId = "upload_id"
        case objectKey = "object_key"
        case originalFilename = "original_filename"
        case mimeType = "mime_type"
        case size
        case width
        case height
    }

    public init(
        uploadId: String,
        objectKey: String,
        originalFilename: String,
        mimeType: String,
        size: Int64,
        width: Int,
        height: Int
    ) {
        self.uploadId = uploadId
        self.objectKey = objectKey
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.size = size
        self.width = width
        self.height = height
    }
}

public struct UnifiedUploadResponse: Codable, Sendable {
    public var objectKey: String
    public var url: String
    public var expiresIn: Int
    public var filename: String
    public var mimeType: String
    public var size: Int64
    public var width: Int?
    public var height: Int?
    public var attachmentId: Int

    enum CodingKeys: String, CodingKey {
        case objectKey = "object_key"
        case url
        case expiresIn = "expires_in"
        case filename
        case mimeType = "mime_type"
        case size
        case width
        case height
        case attachmentId = "attachment_id"
    }
}

public struct HealthCheckResponse: Codable, Sendable {
    public var status: String
    public var service: String
    public var version: String?
    public var runtime: String?
    public var storageR2: Bool?
    public var message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case service
        case version
        case runtime
        case storageR2 = "storage_r2"
        case message
    }
}

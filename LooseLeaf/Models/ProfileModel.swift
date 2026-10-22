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

public struct VerifyPasscodeRequest: Codable, Sendable {
    public var passcode: String
    public var deviceName: String
    public var platform: String
    public var deviceModel: String

    enum CodingKeys: String, CodingKey {
        case passcode
        case deviceName = "device_name"
        case platform
        case deviceModel = "device_model"
    }

    public init(passcode: String, deviceName: String, platform: String = "macos", deviceModel: String = "Mac") {
        self.passcode = passcode
        self.deviceName = deviceName
        self.platform = platform
        self.deviceModel = deviceModel
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

public struct NetworkCandidate: Codable, Equatable, Sendable, Identifiable {
    public var id: String { url }
    public var type: String
    public var label: String
    public var ip: String
    public var url: String
    public var isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case label
        case ip
        case url
        case isDefault = "is_default"
    }
}

public struct PairTicketResponse: Codable, Equatable, Sendable {
    public var ticket: String
    public var hubUrl: String
    public var qrPayload: String
    public var qrCodeDataUrl: String?
    public var expiresAt: String
    public var expiresInSeconds: Int
    public var candidates: [NetworkCandidate]?

    enum CodingKeys: String, CodingKey {
        case ticket
        case hubUrl = "hub_url"
        case qrPayload = "qr_payload"
        case qrCodeDataUrl = "qr_code_data_url"
        case expiresAt = "expires_at"
        case expiresInSeconds = "expires_in_seconds"
        case candidates
    }
}

public struct PairQRResponse: Codable, Equatable, Sendable {
    public var hubUrl: String
    public var ticket: String
    public var qrPayload: String
    public var qrCodeDataUrl: String

    enum CodingKeys: String, CodingKey {
        case hubUrl = "hub_url"
        case ticket
        case qrPayload = "qr_payload"
        case qrCodeDataUrl = "qr_code_data_url"
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
    /// 许下心愿的时刻（可回填为过去日期以支撑「补档」）
    public var plantedAt: String?
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
        case plantedAt = "planted_at"
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
        plantedAt = try? container.decodeIfPresent(String.self, forKey: .plantedAt)
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
    /// 许下心愿的时刻（可选，支持补录过去的心愿）
    public var plantedAt: String?
    /// 附件 id 列表
    ///
    /// 关键：必须是**可选**。
    /// 非可选 `[Int]`（默认 `[]`）会被 JSONEncoder 必定写出 `"attachment_ids": []`，
    /// 而后端把「空数组」理解为「解除全部附件绑定」——
    /// 于是在**没有附件 UI** 的编辑弹窗里改个标题，
    /// 服务端也会把该心愿的照片 `wish_id` 置空（跨端更刺眼：
    /// 用 web 传了图，再用 mac 改个字，图片就没了）。
    /// nil = 本次不携带附件字段（保持原样）。
    public var attachmentIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case title
        case kind
        case note
        case spec
        case cityCode = "city_code"
        case cityName = "city_name"
        case budget
        case targetDate = "target_date"
        case plantedAt = "planted_at"
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
        plantedAt: String? = nil,
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
        self.plantedAt = plantedAt
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

    public init(
        id: Int,
        cityCode: String,
        cityName: String,
        title: String? = nil,
        visitedAt: String = FormatUtils.beijingISOString(),
        departedAt: String? = nil,
        note: String? = nil,
        lifeEntryId: Int? = nil,
        wishId: Int? = nil,
        attachments: [Attachment] = [],
        entriesCount: Int? = nil,
        totalSpent: Int64? = nil,
        transactionCount: Int? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.cityCode = cityCode
        self.cityName = cityName
        self.title = title
        self.visitedAt = visitedAt
        self.departedAt = departedAt
        self.note = note
        self.lifeEntryId = lifeEntryId
        self.wishId = wishId
        self.attachments = attachments
        self.entriesCount = entriesCount
        self.totalSpent = totalSpent
        self.transactionCount = transactionCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
    /// 缩略图地址（中枢自己的路由）
    /// 缺省时按 `url` 推导不出来，故为可选；老后端返回时为 nil，客户端会退回原图
    public var thumbnailUrl: String?

    enum CodingKeys: String, CodingKey {
        case objectKey = "object_key"
        case url
        case thumbnailUrl = "thumbnail_url"
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

/// 首次装帧初始化请求 (POST /api/v1/system/bootstrap)
public struct BootstrapRequest: Codable, Sendable {
    public var curatorName: String
    public var location: String
    public var masterPasscode: String
    public var confirmPasscode: String
    public var hubUrl: String

    enum CodingKeys: String, CodingKey {
        case curatorName = "curator_name"
        case location
        case masterPasscode = "master_passcode"
        case confirmPasscode = "confirm_passcode"
        case hubUrl = "hub_url"
    }

    public init(
        curatorName: String,
        location: String,
        masterPasscode: String,
        confirmPasscode: String,
        hubUrl: String
    ) {
        self.curatorName = curatorName
        self.location = location
        self.masterPasscode = masterPasscode
        self.confirmPasscode = confirmPasscode
        self.hubUrl = hubUrl
    }
}

/// 圆满心愿请求载荷 (POST /api/v1/wishes/:id/resolve)
public struct ResolveWishRequest: Codable, Sendable {
    public var fulfilledAt: String
    public var actualCost: Int64
    public var resolutionType: String // exact | altered | relinquished
    public var actualTitle: String?
    public var createTransaction: Bool
    public var createGearAsset: Bool
    public var createLifeEntry: Bool
    public var createFootprint: Bool
    public var entryContent: String?
    public var attachmentIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case fulfilledAt = "fulfilled_at"
        case actualCost = "actual_cost"
        case resolutionType = "resolution_type"
        case actualTitle = "actual_title"
        case createTransaction = "create_transaction"
        case createGearAsset = "create_gear_asset"
        case createLifeEntry = "create_life_entry"
        case createFootprint = "create_footprint"
        case entryContent = "entry_content"
        case attachmentIds = "attachment_ids"
    }

    public init(
        fulfilledAt: String = FormatUtils.beijingISOString(),
        actualCost: Int64,
        resolutionType: String = "exact",
        actualTitle: String? = nil,
        createTransaction: Bool = true,
        createGearAsset: Bool = false,
        createLifeEntry: Bool = true,
        createFootprint: Bool = false,
        entryContent: String? = nil,
        attachmentIds: [Int]? = nil
    ) {
        self.fulfilledAt = fulfilledAt
        self.actualCost = actualCost
        self.resolutionType = resolutionType
        self.actualTitle = actualTitle
        self.createTransaction = createTransaction
        self.createGearAsset = createGearAsset
        self.createLifeEntry = createLifeEntry
        self.createFootprint = createFootprint
        self.entryContent = entryContent
        self.attachmentIds = attachmentIds
    }
}

/// 新建或修改造物项目请求 (POST / PUT /api/v1/projects)
public struct CreateProjectRequest: Codable, Sendable {
    public var title: String
    public var subtitle: String?
    public var description: String
    /// 项目故事（设计手记）
    ///
    /// 关键（MC-04）：这个字段**后端早就支持**（`ProjectRequest.Story`），
    /// Web 端也能编辑，但桌面端的请求模型里压根没有它 ——
    /// 于是「用 Web 写了一段项目故事，再用桌面端改个标题」，
    /// 故事就**没法在桌面端维护**（后端更新接口是指针语义、不会清空，
    /// 但桌面端用户根本看不到、也改不了它）。
    public var story: String?
    public var category: String?
    public var status: String?
    public var githubUrl: String?
    /// 展示顺序（数值小的靠前）
    ///
    /// 同样后端支持、Web 端的请求模型里有，桌面端补齐。
    /// 为 nil 时**不携带**该字段 —— 后端更新接口是指针语义，省略即保持原值。
    public var order: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case description
        case story
        case category
        case status
        case githubUrl = "github_url"
        case order
    }

    public init(
        title: String,
        subtitle: String? = nil,
        description: String,
        story: String? = nil,
        category: String? = "开源造物",
        status: String? = "持续维护",
        githubUrl: String? = nil,
        order: Int? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.story = story
        self.category = category
        self.status = status
        self.githubUrl = githubUrl
        self.order = order
    }
}

/// 随身器材转售回血请求 (POST /api/v1/assets/gear/:id/sell)
public struct SellGearRequest: Codable, Sendable {
    public var soldPriceCents: Int64
    public var soldDate: String
    public var note: String?

    enum CodingKeys: String, CodingKey {
        case soldPriceCents = "sold_price_cents"
        case soldDate = "sold_date"
        case note
    }

    public init(
        soldPriceCents: Int64,
        soldDate: String = FormatUtils.beijingDateString(),
        note: String? = nil
    ) {
        self.soldPriceCents = soldPriceCents
        self.soldDate = soldDate
        self.note = note
    }
}

// MARK: - 城市回忆抽屉聚合模型 (GET /api/v1/footprints/cities/:city_code/drawer)

public struct CityVisitStats: Codable, Equatable, Sendable {
    public var totalVisits: Int
    public var firstVisitedAt: String
    public var latestVisitedAt: String

    enum CodingKeys: String, CodingKey {
        case totalVisits = "total_visits"
        case firstVisitedAt = "first_visited_at"
        case latestVisitedAt = "latest_visited_at"
    }

    public init(totalVisits: Int = 0, firstVisitedAt: String = "", latestVisitedAt: String = "") {
        self.totalVisits = totalVisits
        self.firstVisitedAt = firstVisitedAt
        self.latestVisitedAt = latestVisitedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalVisits = (try? container.decode(Int.self, forKey: .totalVisits)) ?? 0
        firstVisitedAt = (try? container.decode(String.self, forKey: .firstVisitedAt)) ?? ""
        latestVisitedAt = (try? container.decode(String.self, forKey: .latestVisitedAt)) ?? ""
    }
}

public struct DrawerCategoryStat: Codable, Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var amount: Int64

    public init(name: String, amount: Int64) {
        self.name = name
        self.amount = amount
    }
}

public struct DrawerLedgerSummary: Codable, Equatable, Sendable {
    public var totalSpent: Int64
    public var transactionCount: Int
    public var categories: [DrawerCategoryStat]

    enum CodingKeys: String, CodingKey {
        case totalSpent = "total_spent"
        case transactionCount = "transaction_count"
        case categories
    }

    public init(totalSpent: Int64 = 0, transactionCount: Int = 0, categories: [DrawerCategoryStat] = []) {
        self.totalSpent = totalSpent
        self.transactionCount = transactionCount
        self.categories = categories
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalSpent = (try? container.decode(Int64.self, forKey: .totalSpent)) ?? 0
        transactionCount = (try? container.decode(Int.self, forKey: .transactionCount)) ?? 0
        categories = (try? container.decodeIfPresent([DrawerCategoryStat].self, forKey: .categories)) ?? []
    }
}

public struct CityMemoryDrawerResponse: Codable, Equatable, Sendable {
    public var cityCode: String
    public var cityName: String
    public var visitStats: CityVisitStats
    public var footprints: [Footprint]
    public var entries: [LifeEntry]
    public var ledgerSummary: DrawerLedgerSummary

    enum CodingKeys: String, CodingKey {
        case cityCode = "city_code"
        case cityName = "city_name"
        case visitStats = "visit_stats"
        case footprints
        case entries
        case ledgerSummary = "ledger_summary"
    }

    public init(
        cityCode: String,
        cityName: String,
        visitStats: CityVisitStats = CityVisitStats(),
        footprints: [Footprint] = [],
        entries: [LifeEntry] = [],
        ledgerSummary: DrawerLedgerSummary = DrawerLedgerSummary()
    ) {
        self.cityCode = cityCode
        self.cityName = cityName
        self.visitStats = visitStats
        self.footprints = footprints
        self.entries = entries
        self.ledgerSummary = ledgerSummary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cityCode = (try? container.decode(String.self, forKey: .cityCode)) ?? ""
        cityName = (try? container.decode(String.self, forKey: .cityName)) ?? ""
        visitStats = (try? container.decode(CityVisitStats.self, forKey: .visitStats)) ?? CityVisitStats()
        footprints = (try? container.decodeIfPresent([Footprint].self, forKey: .footprints)) ?? []
        entries = (try? container.decodeIfPresent([LifeEntry].self, forKey: .entries)) ?? []
        ledgerSummary = (try? container.decode(DrawerLedgerSummary.self, forKey: .ledgerSummary)) ?? DrawerLedgerSummary()
    }
}

public struct ProvinceVisitedCity: Codable, Identifiable, Equatable, Sendable {
    public var id: String { cityCode }
    public var cityCode: String
    public var cityName: String
    public var visitCount: Int

    enum CodingKeys: String, CodingKey {
        case cityCode = "city_code"
        case cityName = "city_name"
        case visitCount = "visit_count"
    }

    public init(cityCode: String, cityName: String, visitCount: Int = 1) {
        self.cityCode = cityCode
        self.cityName = cityName
        self.visitCount = visitCount
    }
}

public struct ProvinceMemoryDrawerResponse: Codable, Equatable, Sendable {
    public var adcode: String
    public var provinceName: String
    public var provinceShort: String
    public var footprints: [Footprint]
    public var visitedCities: [ProvinceVisitedCity]
    public var entries: [LifeEntry]
    public var photos: [Attachment]
    public var visitStats: CityVisitStats
    public var ledgerSummary: DrawerLedgerSummary

    enum CodingKeys: String, CodingKey {
        case adcode
        case provinceName = "province_name"
        case provinceShort = "province_short"
        case footprints
        case visitedCities = "visited_cities"
        case entries
        case photos
        case visitStats = "visit_stats"
        case ledgerSummary = "ledger_summary"
    }

    public init(
        adcode: String = "",
        provinceName: String = "",
        provinceShort: String = "",
        footprints: [Footprint] = [],
        visitedCities: [ProvinceVisitedCity] = [],
        entries: [LifeEntry] = [],
        photos: [Attachment] = [],
        visitStats: CityVisitStats = CityVisitStats(),
        ledgerSummary: DrawerLedgerSummary = DrawerLedgerSummary()
    ) {
        self.adcode = adcode
        self.provinceName = provinceName
        self.provinceShort = provinceShort
        self.footprints = footprints
        self.visitedCities = visitedCities
        self.entries = entries
        self.photos = photos
        self.visitStats = visitStats
        self.ledgerSummary = ledgerSummary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        adcode = (try? container.decode(String.self, forKey: .adcode)) ?? ""
        provinceName = (try? container.decode(String.self, forKey: .provinceName)) ?? ""
        provinceShort = (try? container.decode(String.self, forKey: .provinceShort)) ?? ""
        footprints = (try? container.decodeIfPresent([Footprint].self, forKey: .footprints)) ?? []
        visitedCities = (try? container.decodeIfPresent([ProvinceVisitedCity].self, forKey: .visitedCities)) ?? []
        entries = (try? container.decodeIfPresent([LifeEntry].self, forKey: .entries)) ?? []
        photos = (try? container.decodeIfPresent([Attachment].self, forKey: .photos)) ?? []
        visitStats = (try? container.decode(CityVisitStats.self, forKey: .visitStats)) ?? CityVisitStats()
        ledgerSummary = (try? container.decode(DrawerLedgerSummary.self, forKey: .ledgerSummary)) ?? DrawerLedgerSummary()
    }
}

// MARK: - 年度生活年鉴五幕画卷模型 (GET /api/v1/almanac/summary?year=...)

public struct AlmanacPrologue: Codable, Equatable, Sendable {
    public var totalEntries: Int
    public var totalWords: Int
    public var activeDays: Int
    public var firstDate: String
    public var lastDate: String
    public var wishesFulfilled: Int
    public var citiesVisited: Int
    public var txCount: Int

    enum CodingKeys: String, CodingKey {
        case totalEntries = "total_entries"
        case totalWords = "total_words"
        case activeDays = "active_days"
        case firstDate = "first_date"
        case lastDate = "last_date"
        case wishesFulfilled = "wishes_fulfilled"
        case citiesVisited = "cities_visited"
        case txCount = "tx_count"
    }

    public init(
        totalEntries: Int = 0,
        totalWords: Int = 0,
        activeDays: Int = 0,
        firstDate: String = "",
        lastDate: String = "",
        wishesFulfilled: Int = 0,
        citiesVisited: Int = 0,
        txCount: Int = 0
    ) {
        self.totalEntries = totalEntries
        self.totalWords = totalWords
        self.activeDays = activeDays
        self.firstDate = firstDate
        self.lastDate = lastDate
        self.wishesFulfilled = wishesFulfilled
        self.citiesVisited = citiesVisited
        self.txCount = txCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalEntries = (try? container.decode(Int.self, forKey: .totalEntries)) ?? 0
        totalWords = (try? container.decode(Int.self, forKey: .totalWords)) ?? 0
        activeDays = (try? container.decode(Int.self, forKey: .activeDays)) ?? 0
        firstDate = (try? container.decode(String.self, forKey: .firstDate)) ?? ""
        lastDate = (try? container.decode(String.self, forKey: .lastDate)) ?? ""
        wishesFulfilled = (try? container.decode(Int.self, forKey: .wishesFulfilled)) ?? 0
        citiesVisited = (try? container.decode(Int.self, forKey: .citiesVisited)) ?? 0
        txCount = (try? container.decode(Int.self, forKey: .txCount)) ?? 0
    }
}

public struct AlmanacCityItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String { cityCode }
    public var cityCode: String
    public var cityName: String

    enum CodingKeys: String, CodingKey {
        case cityCode = "city_code"
        case cityName = "city_name"
    }

    public init(cityCode: String, cityName: String) {
        self.cityCode = cityCode
        self.cityName = cityName
    }
}

public struct AlmanacAtlas: Codable, Equatable, Sendable {
    public var totalCities: Int
    public var cities: [AlmanacCityItem]
    public var footprints: [Footprint]

    enum CodingKeys: String, CodingKey {
        case totalCities = "total_cities"
        case cities
        case footprints
    }

    public init(totalCities: Int = 0, cities: [AlmanacCityItem] = [], footprints: [Footprint] = []) {
        self.totalCities = totalCities
        self.cities = cities
        self.footprints = footprints
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalCities = (try? container.decode(Int.self, forKey: .totalCities)) ?? 0
        cities = (try? container.decodeIfPresent([AlmanacCityItem].self, forKey: .cities)) ?? []
        footprints = (try? container.decodeIfPresent([Footprint].self, forKey: .footprints)) ?? []
    }
}

public struct AlmanacWishes: Codable, Equatable, Sendable {
    public var wishes: [Wish]
    public var fulfilledCount: Int
    public var wantingCount: Int
    public var totalBudget: Int64
    public var totalActual: Int64

    enum CodingKeys: String, CodingKey {
        case wishes
        case fulfilledCount = "fulfilled_count"
        case wantingCount = "wanting_count"
        case totalBudget = "total_budget"
        case totalActual = "total_actual"
    }

    public init(
        wishes: [Wish] = [],
        fulfilledCount: Int = 0,
        wantingCount: Int = 0,
        totalBudget: Int64 = 0,
        totalActual: Int64 = 0
    ) {
        self.wishes = wishes
        self.fulfilledCount = fulfilledCount
        self.wantingCount = wantingCount
        self.totalBudget = totalBudget
        self.totalActual = totalActual
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wishes = (try? container.decodeIfPresent([Wish].self, forKey: .wishes)) ?? []
        fulfilledCount = (try? container.decode(Int.self, forKey: .fulfilledCount)) ?? 0
        wantingCount = (try? container.decode(Int.self, forKey: .wantingCount)) ?? 0
        totalBudget = (try? container.decode(Int64.self, forKey: .totalBudget)) ?? 0
        totalActual = (try? container.decode(Int64.self, forKey: .totalActual)) ?? 0
    }
}

public struct AlmanacHighlights: Codable, Equatable, Sendable {
    public var spring: LifeEntry?
    public var summer: LifeEntry?
    public var autumn: LifeEntry?
    public var winter: LifeEntry?
    public var photos: [Attachment]

    public init(
        spring: LifeEntry? = nil,
        summer: LifeEntry? = nil,
        autumn: LifeEntry? = nil,
        winter: LifeEntry? = nil,
        photos: [Attachment] = []
    ) {
        self.spring = spring
        self.summer = summer
        self.autumn = autumn
        self.winter = winter
        self.photos = photos
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spring = try? container.decodeIfPresent(LifeEntry.self, forKey: .spring)
        summer = try? container.decodeIfPresent(LifeEntry.self, forKey: .summer)
        autumn = try? container.decodeIfPresent(LifeEntry.self, forKey: .autumn)
        winter = try? container.decodeIfPresent(LifeEntry.self, forKey: .winter)
        photos = (try? container.decodeIfPresent([Attachment].self, forKey: .photos)) ?? []
    }
}

public struct AlmanacFinances: Codable, Equatable, Sendable {
    public var totalIncome: Int64
    public var totalExpense: Int64
    public var balance: Int64
    public var wishExpenses: Int64
    public var wishSpendingRatio: Double
    public var categories: [DrawerCategoryStat]

    enum CodingKeys: String, CodingKey {
        case totalIncome = "total_income"
        case totalExpense = "total_expense"
        case balance
        case wishExpenses = "wish_expenses"
        case wishSpendingRatio = "wish_spending_ratio"
        case categories
    }

    public init(
        totalIncome: Int64 = 0,
        totalExpense: Int64 = 0,
        balance: Int64 = 0,
        wishExpenses: Int64 = 0,
        wishSpendingRatio: Double = 0.0,
        categories: [DrawerCategoryStat] = []
    ) {
        self.totalIncome = totalIncome
        self.totalExpense = totalExpense
        self.balance = balance
        self.wishExpenses = wishExpenses
        self.wishSpendingRatio = wishSpendingRatio
        self.categories = categories
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalIncome = (try? container.decode(Int64.self, forKey: .totalIncome)) ?? 0
        totalExpense = (try? container.decode(Int64.self, forKey: .totalExpense)) ?? 0
        balance = (try? container.decode(Int64.self, forKey: .balance)) ?? 0
        wishExpenses = (try? container.decode(Int64.self, forKey: .wishExpenses)) ?? 0
        wishSpendingRatio = (try? container.decode(Double.self, forKey: .wishSpendingRatio)) ?? 0.0
        categories = (try? container.decodeIfPresent([DrawerCategoryStat].self, forKey: .categories)) ?? []
    }
}

public struct AnnualAlmanacResponse: Codable, Equatable, Sendable {
    public var year: Int
    public var prologue: AlmanacPrologue
    public var atlas: AlmanacAtlas
    public var wishes: AlmanacWishes
    public var highlights: AlmanacHighlights
    public var finances: AlmanacFinances

    public init(
        year: Int = FormatUtils.beijingCurrentYearMonth().year,
        prologue: AlmanacPrologue = AlmanacPrologue(),
        atlas: AlmanacAtlas = AlmanacAtlas(),
        wishes: AlmanacWishes = AlmanacWishes(),
        highlights: AlmanacHighlights = AlmanacHighlights(),
        finances: AlmanacFinances = AlmanacFinances()
    ) {
        self.year = year
        self.prologue = prologue
        self.atlas = atlas
        self.wishes = wishes
        self.highlights = highlights
        self.finances = finances
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        year = (try? container.decode(Int.self, forKey: .year)) ?? FormatUtils.beijingCurrentYearMonth().year
        prologue = (try? container.decode(AlmanacPrologue.self, forKey: .prologue)) ?? AlmanacPrologue()
        atlas = (try? container.decode(AlmanacAtlas.self, forKey: .atlas)) ?? AlmanacAtlas()
        wishes = (try? container.decode(AlmanacWishes.self, forKey: .wishes)) ?? AlmanacWishes()
        highlights = (try? container.decode(AlmanacHighlights.self, forKey: .highlights)) ?? AlmanacHighlights()
        finances = (try? container.decode(AlmanacFinances.self, forKey: .finances)) ?? AlmanacFinances()
    }
}

public struct OnThisDayResponse: Codable, Equatable, Sendable {
    public var month: Int
    public var day: Int
    public var entries: [LifeEntry]

    public init(month: Int = 1, day: Int = 1, entries: [LifeEntry] = []) {
        self.month = month
        self.day = day
        self.entries = entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        month = (try? container.decode(Int.self, forKey: .month)) ?? 1
        day = (try? container.decode(Int.self, forKey: .day)) ?? 1
        entries = (try? container.decodeIfPresent([LifeEntry].self, forKey: .entries)) ?? []
    }
}

public struct GlobalSearchResponse: Codable, Equatable, Sendable {
    public var query: String
    public var entries: [LifeEntry]
    public var footprints: [Footprint]
    public var wishes: [Wish]
    public var projects: [Project]

    public init(
        query: String = "",
        entries: [LifeEntry] = [],
        footprints: [Footprint] = [],
        wishes: [Wish] = [],
        projects: [Project] = []
    ) {
        self.query = query
        self.entries = entries
        self.footprints = footprints
        self.wishes = wishes
        self.projects = projects
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = (try? container.decode(String.self, forKey: .query)) ?? ""
        entries = (try? container.decodeIfPresent([LifeEntry].self, forKey: .entries)) ?? []
        footprints = (try? container.decodeIfPresent([Footprint].self, forKey: .footprints)) ?? []
        wishes = (try? container.decodeIfPresent([Wish].self, forKey: .wishes)) ?? []
        projects = (try? container.decodeIfPresent([Project].self, forKey: .projects)) ?? []
    }
}

public struct CategoryResetResponse: Codable, Sendable {
    public var items: [CategoryOption]?
    public var byScope: [String: [String]]?

    enum CodingKeys: String, CodingKey {
        case items
        case byScope = "by_scope"
    }
}



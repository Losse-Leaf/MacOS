import Foundation

// MARK: - 三维心愿单与圆满模型 (Wishes & Resolution)

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
    public var isPrivate: Bool?
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
        case isPrivate = "is_private"
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
        isPrivate = try? container.decodeIfPresent(Bool.self, forKey: .isPrivate)
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
    /// 附件 id 列表（必须为可选：nil = 本次不携带附件字段，避免无图修订误解绑跨端附件）
    public var attachmentIds: [Int]?
    public var clearAttachments: Bool?
    public var isPrivate: Bool?

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
        case clearAttachments = "clear_attachments"
        case isPrivate = "is_private"
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
        attachmentIds: [Int]? = nil,
        clearAttachments: Bool? = nil,
        isPrivate: Bool? = nil
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
        self.clearAttachments = clearAttachments
        self.isPrivate = isPrivate
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

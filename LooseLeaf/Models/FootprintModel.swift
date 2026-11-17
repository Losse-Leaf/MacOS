import Foundation

// MARK: - 山川足迹与城市回忆抽屉模型 (Footprints & City Memory Drawer)

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
    public var isPrivate: Bool?
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
        case isPrivate = "is_private"
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
        isPrivate = try? container.decodeIfPresent(Bool.self, forKey: .isPrivate)
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
    /// 必须为可选：无图修订足迹时传 nil 省略字段，防止将 Web/移动端上传的旅程照片静默解绑
    public var attachmentIds: [Int]?
    public var clearAttachments: Bool?
    public var isPrivate: Bool?

    enum CodingKeys: String, CodingKey {
        case cityCode = "city_code"
        case cityName = "city_name"
        case title
        case visitedAt = "visited_at"
        case departedAt = "departed_at"
        case note
        case attachmentIds = "attachment_ids"
        case clearAttachments = "clear_attachments"
        case isPrivate = "is_private"
    }

    public init(
        cityCode: String,
        cityName: String,
        title: String? = nil,
        visitedAt: String = FormatUtils.beijingDateString(),
        departedAt: String? = nil,
        note: String? = nil,
        attachmentIds: [Int]? = nil,
        clearAttachments: Bool? = nil,
        isPrivate: Bool? = nil
    ) {
        self.cityCode = cityCode
        self.cityName = cityName
        self.title = title
        self.visitedAt = visitedAt
        self.departedAt = departedAt
        self.note = note
        self.attachmentIds = attachmentIds
        self.clearAttachments = clearAttachments
        self.isPrivate = isPrivate
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

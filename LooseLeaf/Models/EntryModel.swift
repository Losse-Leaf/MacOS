import Foundation

/// 标准 RESTful API v1 统一响应信封
public struct APIEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    public let code: Int
    public let message: String
    public let data: T?
}

/// 生活档案底层四维母体类型 (RC-128)
public enum EntryType: String, Codable, CaseIterable, Identifiable, Sendable {
    case life = "life"
    case travel = "travel"
    case project = "project"
    case wish = "wish"
    case transaction = "transaction"
    /// 器物（添置随身设备等二级对象在时间流里的伴生散页）
    case gear = "gear"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .life: return "日常"
        case .travel: return "游历"
        case .project: return "造物"
        case .wish: return "心愿"
        case .transaction: return "账目"
        case .gear: return "器物"
        }
    }

    /// 时间流 / 详情页上的**形态徽章文案**（全应用唯一真源）
    ///
    /// 关键：此前这份映射有四份实现（时间流卡片、详情页、StreamView 的死代码、
    /// 导出器），其中详情页那份**漏了 gear 分支** ——
    /// 于是器物条目在时间流上显示「器物印记」，在详情页却显示「日常随笔」。
    public var badgeLabel: String {
        switch self {
        case .travel: return "山川游历"
        case .project: return "造物演进"
        case .wish: return "心愿印记"
        case .transaction: return "柴米油盐"
        case .gear: return "器物印记"
        default: return "日常随笔"
        }
    }

    public var symbolName: String {
        switch self {
        case .life: return "leaf"
        case .travel: return "safari"
        case .project: return "hammer"
        case .wish: return "sparkles"
        case .transaction: return "creditcard"
        case .gear: return "shippingbox"
        }
    }
}

/// 顶层展厅过滤分类视角
public enum ArchiveCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case daily = "daily"
    case travel = "travel"
    case project = "project"
    case wish = "wish"
    case transaction = "transaction"
    case gear = "gear"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "全部印记"
        case .daily: return "日常"
        case .travel: return "游历"
        case .project: return "造物"
        case .wish: return "心愿"
        case .transaction: return "账目"
        case .gear: return "器物"
        }
    }
}

/// 附件与多媒体对象实体
/// 批量换签的请求载荷
public struct BatchSignRequest: Codable, Sendable {
    public var keys: [String]
    public var expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case keys
        case expiresIn = "expires_in"
    }

    public init(keys: [String], expiresIn: Int? = nil) {
        self.keys = keys
        self.expiresIn = expiresIn
    }
}

/// 批量换签的响应
public struct BatchSignResponse: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public var objectKey: String
        public var url: String
        /// 缩略图签名地址（与原图是两条不同的签名，客户端拼不出来）
        public var thumbnailUrl: String?
        public var expiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case objectKey = "object_key"
            case url
            case thumbnailUrl = "thumbnail_url"
            case expiresIn = "expires_in"
        }
    }

    public var items: [Item]

    enum CodingKeys: String, CodingKey {
        case items
    }
}

/// 换签后的一对地址
public struct RefreshedMediaURLs: Sendable {
    public var url: String
    public var thumbnailUrl: String?

    public init(url: String, thumbnailUrl: String?) {
        self.url = url
        self.thumbnailUrl = thumbnailUrl
    }
}

public struct Attachment: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public var entryId: Int?
    public var wishId: Int?
    public var footprintId: Int?
    public var objectKey: String
    public var originalFilename: String
    public var mimeType: String
    public var size: Int64
    public var width: Int?
    public var height: Int?
    public var url: String
    /// 缩略图地址（中枢自己的路由，稳定可缓存）
    ///
    /// 关键：列表与详情用缩略图，**只有灯箱（点开大图）才用原图**。
    /// 原图动辄 1.5MB，从对象存储拉一次要 4 秒；滚动时间流时每张新卡片都在拉原图，
    /// 网络与解码把主线程打满，表现为「滑动卡」「点开转圈」。
    public var thumbnailUrl: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
        case wishId = "wish_id"
        case footprintId = "footprint_id"
        case objectKey = "object_key"
        case originalFilename = "original_filename"
        case mimeType = "mime_type"
        case size
        case width
        case height
        case url
        case thumbnailUrl = "thumbnail_url"
        case createdAt = "created_at"
    }

    public init(
        id: Int,
        entryId: Int? = nil,
        wishId: Int? = nil,
        footprintId: Int? = nil,
        objectKey: String,
        originalFilename: String,
        mimeType: String,
        size: Int64,
        width: Int? = nil,
        height: Int? = nil,
        url: String,
        thumbnailUrl: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.entryId = entryId
        self.wishId = wishId
        self.footprintId = footprintId
        self.objectKey = objectKey
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.size = size
        self.width = width
        self.height = height
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.createdAt = createdAt
    }
}

/// 统一生活时间线档案条目 (LifeEntry)
/// 作为一级母体记录，承载文字、现场相片、所处地点与关联造物/心愿/足迹
public struct LifeEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var type: String
    public var title: String
    public var content: String
    public var occurredAt: String
    public var location: String?
    public var cityCode: String?
    public var cityName: String?
    public var projectId: Int?
    public var project: Project?
    public var wishId: Int?
    public var wish: Wish?
    /// 器物伴生散页（器物 id 为字符串）
    public var gearId: String?
    public var footprintId: Int?
    public var attachments: [Attachment]
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    /// 客户端离线同步状态标记 ("synced", "pending_create", "pending_update", "pending_delete")
    public var syncStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case content
        case occurredAt = "occurred_at"
        case location
        case cityCode = "city_code"
        case cityName = "city_name"
        case projectId = "project_id"
        case project
        case wishId = "wish_id"
        case wish
        case gearId = "gear_id"
        case footprintId = "footprint_id"
        case attachments
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncStatus = "sync_status"
    }

    public init(
        id: Int,
        type: String = EntryType.life.rawValue,
        title: String,
        content: String,
        occurredAt: String,
        location: String? = nil,
        cityCode: String? = nil,
        cityName: String? = nil,
        projectId: Int? = nil,
        project: Project? = nil,
        wishId: Int? = nil,
        wish: Wish? = nil,
        gearId: String? = nil,
        footprintId: Int? = nil,
        attachments: [Attachment] = [],
        deletedAt: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        syncStatus: String? = "synced"
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.content = content
        self.occurredAt = occurredAt
        self.location = location
        self.cityCode = cityCode
        self.cityName = cityName
        self.projectId = projectId
        self.project = project
        self.wishId = wishId
        self.wish = wish
        self.gearId = gearId
        self.footprintId = footprintId
        self.attachments = attachments
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStatus = syncStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = (try? container.decode(String.self, forKey: .type)) ?? EntryType.life.rawValue
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        content = (try? container.decode(String.self, forKey: .content)) ?? ""
        occurredAt = (try? container.decode(String.self, forKey: .occurredAt)) ?? FormatUtils.beijingISOString()
        location = try? container.decodeIfPresent(String.self, forKey: .location)
        cityCode = try? container.decodeIfPresent(String.self, forKey: .cityCode)
        cityName = try? container.decodeIfPresent(String.self, forKey: .cityName)
        projectId = try? container.decodeIfPresent(Int.self, forKey: .projectId)
        project = try? container.decodeIfPresent(Project.self, forKey: .project)
        wishId = try? container.decodeIfPresent(Int.self, forKey: .wishId)
        wish = try? container.decodeIfPresent(Wish.self, forKey: .wish)
        gearId = try? container.decodeIfPresent(String.self, forKey: .gearId)
        footprintId = try? container.decodeIfPresent(Int.self, forKey: .footprintId)
        attachments = (try? container.decodeIfPresent([Attachment].self, forKey: .attachments)) ?? []
        deletedAt = try? container.decodeIfPresent(String.self, forKey: .deletedAt)
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
        syncStatus = (try? container.decodeIfPresent(String.self, forKey: .syncStatus)) ?? "synced"
    }

    /// 匹配顶层分类视角 (与 Web 端 getEntryCategory 逻辑严格对齐)
    public func matches(category: ArchiveCategory) -> Bool {
        switch category {
        case .all:
            return true
        case .daily:
            return type == EntryType.life.rawValue
        case .travel:
            return type == EntryType.travel.rawValue || !(cityCode ?? "").isEmpty
        case .project:
            return type == EntryType.project.rawValue || (projectId ?? 0) > 0
        case .wish:
            return type == EntryType.wish.rawValue || (wishId ?? 0) > 0
        case .transaction:
            return type == "transaction"
        case .gear:
            return type == "gear" || !(gearId ?? "").isEmpty
        }
    }

    /// 提取北京时间戳派生结构（不落库，展示时实时计算）
    public var parsedDate: FormatUtils.ParsedBeijingDate {
        FormatUtils.parseOccurredDate(occurredAt)
    }

    /// 如果该条目是由 Transaction 合成的伴生条目，解析其关联的真实账目 ID
    public var associatedTransactionId: Int64? {
        guard type == "transaction" else { return nil }
        if id <= -1_000_000 {
            return Int64(abs(id) - 1_000_000)
        }
        return id > 0 ? Int64(id) : nil
    }
}

/// 分页查询生活档案列表响应结构
public struct EntriesListResponse: Codable, Sendable {
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let entries: [LifeEntry]

    enum CodingKeys: String, CodingKey {
        case total
        case page
        case pageSize = "page_size"
        case entries
    }
}

/// 新建生活记录请求载荷
public struct CreateEntryRequest: Codable, Equatable, Sendable {
    public var type: String
    public var title: String
    public var content: String
    public var occurredAt: String
    public var location: String?
    public var cityCode: String?
    public var cityName: String?
    public var projectId: Int?
    public var wishId: Int?
    public var footprintId: Int?
    public var attachmentIds: [Int]
    /// 幂等创建键（契约 C）：离线发件箱 CREATE 事件在入队时生成 UUID 并
    /// **持久化进载荷**，重试/复活复用同一个 —— 服务端按它查重，
    /// 命中返回已有记录，杜绝同一篇手稿被重复上传成两份。
    /// 在线直发与发件箱重试统一携带；nil 仅代表升级前的旧载荷，发送前会补签。
    public var clientRequestId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case title
        case content
        case occurredAt = "occurred_at"
        case location
        case cityCode = "city_code"
        case cityName = "city_name"
        case projectId = "project_id"
        case wishId = "wish_id"
        case footprintId = "footprint_id"
        case attachmentIds = "attachment_ids"
        case clientRequestId = "client_request_id"
    }

    public init(
        type: String = EntryType.life.rawValue,
        title: String = "",
        content: String,
        occurredAt: String = FormatUtils.beijingISOString(),
        location: String? = nil,
        cityCode: String? = nil,
        cityName: String? = nil,
        projectId: Int? = nil,
        wishId: Int? = nil,
        footprintId: Int? = nil,
        attachmentIds: [Int] = [],
        clientRequestId: String? = nil
    ) {
        self.type = type
        self.title = title
        self.content = content
        self.occurredAt = occurredAt
        self.location = location
        self.cityCode = cityCode
        self.cityName = cityName
        self.projectId = projectId
        self.wishId = wishId
        self.footprintId = footprintId
        self.attachmentIds = attachmentIds
        self.clientRequestId = clientRequestId
    }
}

/// 编辑生活记录请求载荷
public struct UpdateEntryRequest: Codable, Equatable, Sendable {
    public var type: String?
    public var title: String?
    public var content: String?
    public var occurredAt: String?
    public var location: String?
    public var cityCode: String?
    public var cityName: String?
    /// 显式清空属地城市（契约 A）：true 时服务端清空 city_code，
    /// 优先于 city_code 字段。此前「清空城市」发 nil（省略）会被
    /// 后端按「保持原值」处理 —— 用户清了城市，保存后原样还在。
    public var clearCity: Bool?
    public var projectId: Int?
    public var wishId: Int?
    public var footprintId: Int?
    public var attachmentIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case type
        case title
        case content
        case occurredAt = "occurred_at"
        case location
        case cityCode = "city_code"
        case cityName = "city_name"
        case clearCity = "clear_city"
        case projectId = "project_id"
        case wishId = "wish_id"
        case footprintId = "footprint_id"
        case attachmentIds = "attachment_ids"
    }

    public init(
        type: String? = nil,
        title: String? = nil,
        content: String? = nil,
        occurredAt: String? = nil,
        location: String? = nil,
        cityCode: String? = nil,
        cityName: String? = nil,
        clearCity: Bool? = nil,
        projectId: Int? = nil,
        wishId: Int? = nil,
        footprintId: Int? = nil,
        attachmentIds: [Int]? = nil
    ) {
        self.type = type
        self.title = title
        self.content = content
        self.occurredAt = occurredAt
        self.location = location
        self.cityCode = cityCode
        self.cityName = cityName
        self.clearCity = clearCity
        self.projectId = projectId
        self.wishId = wishId
        self.footprintId = footprintId
        self.attachmentIds = attachmentIds
    }
}

/// 全局档案指标统计 (GET /api/v1/stats)
public struct GlobalStats: Codable, Equatable, Sendable {
    public var totalEntries: Int
    public var totalPhotos: Int
    public var totalProjects: Int
    public var monthExpense: Int64
    public var currentYear: Int
    public var currentMonth: Int

    enum CodingKeys: String, CodingKey {
        case totalEntries = "total_entries"
        case totalPhotos = "total_photos"
        case totalProjects = "total_projects"
        case monthExpense = "month_expense"
        case currentYear = "current_year"
        case currentMonth = "current_month"
    }

    public init(
        totalEntries: Int = 0,
        totalPhotos: Int = 0,
        totalProjects: Int = 0,
        monthExpense: Int64 = 0,
        currentYear: Int = FormatUtils.beijingCurrentYearMonth().year,
        currentMonth: Int = FormatUtils.beijingCurrentYearMonth().month
    ) {
        self.totalEntries = totalEntries
        self.totalPhotos = totalPhotos
        self.totalProjects = totalProjects
        self.monthExpense = monthExpense
        self.currentYear = currentYear
        self.currentMonth = currentMonth
    }
}

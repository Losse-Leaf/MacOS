import CoreGraphics
import Foundation

/// 标准 RESTful API v1 统一响应信封
public struct APIEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    public let code: Int
    public let message: String
    public let data: T?
}

/// 生活档案底层形态类型
public enum EntryType: String, Codable, CaseIterable, Identifiable, Sendable {
    case life = "life"
    case wish = "wish"
    case transaction = "transaction"

    public var id: String { rawValue }

    /// 允许用户在新建/编辑手稿中手动切换的生活形态（排除系统合成的 transaction）
    public static var editableCases: [EntryType] {
        [.life, .wish]
    }

    public var label: String {
        switch self {
        case .life: return "日常"
        case .wish: return "心愿"
        case .transaction: return "账目"
        }
    }

    /// 时间流 / 详情页上的**形态徽章文案**（全应用唯一真源）
    public var badgeLabel: String {
        switch self {
        case .wish: return "心愿印记"
        case .transaction: return "柴米油盐"
        case .life: return "日常随笔"
        }
    }

    public var symbolName: String {
        switch self {
        case .life: return ArchiveIcon.entryLife.systemName
        case .wish: return ArchiveIcon.entryWish.systemName
        case .transaction: return ArchiveIcon.entryTransaction.systemName
        }
    }
}

/// 散页原生分类（方式 A：与后端及 Vesper Space 四大展区 1:1 对齐）
public enum EntryCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily = ""
    case photography = "Photography"
    case travel = "Travel"
    case stillLife = "Still Life"
    case motion = "Motion"

    public var id: String { rawValue }

    /// 归一化解析后端取值或中英文别名（与后端 `normalizeEntryCategory` 严格对齐，未知值回落为 `.daily`）
    public init(normalized raw: String?) {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "", "daily", "life", "日常", "日常随笔":
            self = .daily
        case "photography", "摄影":
            self = .photography
        case "travel", "旅途", "旅行":
            self = .travel
        case "still life", "still_life", "still-life", "stilllife", "静物", "器物":
            self = .stillLife
        case "motion", "video", "影像":
            self = .motion
        default:
            self = .daily
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try? container.decode(String.self)
        self = EntryCategory(normalized: raw)
    }

    /// 画廊四大展区分类（不含默认日常）
    public static var galleryCases: [EntryCategory] {
        [.photography, .travel, .stillLife, .motion]
    }

    /// 胶囊选择器与筛选栏短文案
    public var label: String {
        switch self {
        case .daily: return "日常"
        case .photography: return "摄影"
        case .travel: return "旅途"
        case .stillLife: return "静物"
        case .motion: return "影像"
        }
    }

    /// 时间流与详情页上的徽章文案
    public var badgeLabel: String {
        switch self {
        case .daily: return "日常随笔"
        case .photography: return "摄影"
        case .travel: return "旅途"
        case .stillLife: return "静物"
        case .motion: return "影像"
        }
    }

    /// 对应 SF Symbol 图标名
    public var symbolName: String {
        switch self {
        case .daily: return "doc.text"
        case .photography: return "camera"
        case .travel: return "map"
        case .stillLife: return "cup.and.saucer"
        case .motion: return "film"
        }
    }
}

/// 时间流顶层过滤视角（覆盖基础视角与 Vesper Space 四大画廊分区）
public enum ArchiveCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case daily = "daily"
    case photography = "Photography"
    case travel = "Travel"
    case stillLife = "Still Life"
    case motion = "Motion"
    case wish = "wish"
    case transaction = "transaction"

    public var id: String { rawValue }

    /// 基础形态视角（全部 / 日常 / 心愿 / 账目）
    public static var primaryCases: [ArchiveCategory] {
        [.all, .daily, .wish, .transaction]
    }

    /// 画廊内容分区视角（摄影 / 旅途 / 静物 / 影像）
    public static var galleryCases: [ArchiveCategory] {
        [.photography, .travel, .stillLife, .motion]
    }

    public var label: String {
        switch self {
        case .all: return "全部印记"
        case .daily: return "日常"
        case .photography: return "摄影"
        case .travel: return "旅途"
        case .stillLife: return "静物"
        case .motion: return "影像"
        case .wish: return "心愿"
        case .transaction: return "账目"
        }
    }

    /// 若为画廊内容分区，返回对应的 `EntryCategory`
    public var entryCategory: EntryCategory? {
        switch self {
        case .photography: return .photography
        case .travel: return .travel
        case .stillLife: return .stillLife
        case .motion: return .motion
        default: return nil
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

    /// 解析可直接展示或导出的完整媒体 URL（列表/详情优先走缩略图，灯箱/导出传 `preferThumbnail: false` 走原图）
    public func resolvedDisplayURL(preferThumbnail: Bool = true) -> URL? {
        let raw: String
        if preferThumbnail, let thumb = thumbnailUrl, !thumb.isEmpty {
            raw = thumb
        } else {
            raw = url
        }
        return APIClient.shared.resolveMediaURL(raw)
    }

    /// 附件原始像素尺寸（用于异步显影前锁定占位框宽高比）
    public var intrinsicSize: CGSize? {
        guard let w = width, let h = height, w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }
}

/// 统一生活时间线档案条目 (LifeEntry)
/// 作为一级母体记录，承载文字、现场相片、所处地点与关联心愿
public struct LifeEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var type: String
    public var category: String
    public var title: String
    public var content: String
    public var occurredAt: String
    public var location: String?
    public var wishId: Int?
    public var wish: Wish?
    public var isPrivate: Bool
    public var attachments: [Attachment]
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    /// 客户端离线同步状态标记 ("synced", "pending_create", "pending_update", "pending_delete")
    public var syncStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case category
        case title
        case content
        case occurredAt = "occurred_at"
        case location
        case wishId = "wish_id"
        case wish
        case isPrivate = "is_private"
        case attachments
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncStatus = "sync_status"
    }

    public init(
        id: Int,
        type: String = EntryType.life.rawValue,
        category: String = "",
        title: String,
        content: String,
        occurredAt: String,
        location: String? = nil,
        wishId: Int? = nil,
        wish: Wish? = nil,
        isPrivate: Bool = false,
        attachments: [Attachment] = [],
        deletedAt: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        syncStatus: String? = "synced"
    ) {
        self.id = id
        self.type = type
        self.category = category
        self.title = title
        self.content = content
        self.occurredAt = occurredAt
        self.location = location
        self.wishId = wishId
        self.wish = wish
        self.isPrivate = isPrivate
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
        category = (try? container.decodeIfPresent(String.self, forKey: .category)) ?? ""
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        content = (try? container.decode(String.self, forKey: .content)) ?? ""
        occurredAt = (try? container.decode(String.self, forKey: .occurredAt)) ?? FormatUtils.beijingISOString()
        location = try? container.decodeIfPresent(String.self, forKey: .location)
        wishId = try? container.decodeIfPresent(Int.self, forKey: .wishId)
        wish = try? container.decodeIfPresent(Wish.self, forKey: .wish)
        isPrivate = (try? container.decodeIfPresent(Bool.self, forKey: .isPrivate)) ?? false
        attachments = (try? container.decodeIfPresent([Attachment].self, forKey: .attachments)) ?? []
        deletedAt = try? container.decodeIfPresent(String.self, forKey: .deletedAt)
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
        syncStatus = (try? container.decodeIfPresent(String.self, forKey: .syncStatus)) ?? "synced"
    }

    /// 归一化后的散页原生分类（仅对 `type == "life"` 具业务语义，未知值回落为 `.daily`）
    public var resolvedCategory: EntryCategory {
        EntryCategory(normalized: category)
    }

    /// 时间流 / 详情页 / 全局检索共享的徽章文案（全应用唯一事实源）
    public var displayBadgeLabel: String {
        switch EntryType(rawValue: type) {
        case .wish:
            return EntryType.wish.badgeLabel
        case .transaction:
            return EntryType.transaction.badgeLabel
        case .life, .none:
            return resolvedCategory.badgeLabel
        }
    }

    private static let legacyPlaceholderTitles: Set<String> = ["无题随笔", "无题"]
    private static let legacyPlaceholderPrefixes: [String] = ["现场快门 · ", "现场记录 · "]

    /// 标题是否值得单独成行（与 Android v2.2.1 `hasDistinctTitle` 规则 1:1 对齐）
    ///
    /// 以下情形视为派生标题或历史占位，卡片与详情页隐藏独立标题行，避免同一句话出现两次：
    /// - 标题为空或纯空白；
    /// - 历史占位标题（"无题随笔"、"无题"、"现场快门 · "、"现场记录 · " 前缀）；
    /// - 去掉末尾省略号后与正文开头完全重叠的派生标题。
    public var hasDistinctTitle: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if Self.legacyPlaceholderTitles.contains(trimmed) { return false }
        if Self.legacyPlaceholderPrefixes.contains(where: { trimmed.hasPrefix($0) }) { return false }

        var core = trimmed
        if core.hasSuffix("…") {
            core.removeLast()
        }
        if core.hasSuffix("...") {
            core.removeLast(3)
        }
        core = core.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return false }

        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return !( !body.isEmpty && body.hasPrefix(core) )
    }

    /// 匹配顶层分类视角（画廊四区按原生分类精确匹配，`.daily` 保持匹配全部 `life` 散页）
    public func matches(category: ArchiveCategory) -> Bool {
        switch category {
        case .all:
            return true
        case .daily:
            return type == EntryType.life.rawValue
        case .photography:
            return type == EntryType.life.rawValue && EntryCategory(normalized: self.category) == .photography
        case .travel:
            return type == EntryType.life.rawValue && EntryCategory(normalized: self.category) == .travel
        case .stillLife:
            return type == EntryType.life.rawValue && EntryCategory(normalized: self.category) == .stillLife
        case .motion:
            return type == EntryType.life.rawValue && EntryCategory(normalized: self.category) == .motion
        case .wish:
            return type == EntryType.wish.rawValue || (wishId ?? 0) > 0
        case .transaction:
            return type == EntryType.transaction.rawValue
        }
    }

    /// 提取北京时间戳派生结构（不落库，展示时实时计算）
    public var parsedDate: FormatUtils.ParsedBeijingDate {
        FormatUtils.parseOccurredDate(occurredAt)
    }

    /// 如果该条目是由 Transaction 合成的伴生条目，解析其关联的真实账目 ID
    public var associatedTransactionId: Int64? {
        guard type == "transaction" else { return nil }
        // 与 TransactionModel.toLifeEntry 的可逆编码互逆：txId - 1_000_000 ⇄ +1_000_000。
        // 合成条目 id 恒为负（正负账目 id 都会减 1_000_000），待同步账目原样还原为负 id。
        guard id <= -1 else { return nil }
        return Int64(id + 1_000_000)
    }

    /// 构造用于撤销恢复或失败重传的完整创建请求载荷
    public func toCreateRequest() -> CreateEntryRequest {
        CreateEntryRequest(
            type: type,
            category: category,
            title: title,
            content: content,
            occurredAt: occurredAt,
            location: location,
            wishId: wishId,
            isPrivate: isPrivate,
            attachmentIds: attachments.map(\.id)
        )
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
    public var category: String
    public var title: String
    public var content: String
    public var occurredAt: String
    public var location: String?
    public var wishId: Int?
    public var isPrivate: Bool?
    public var attachmentIds: [Int]
    /// 幂等创建键（契约 C）：离线发件箱 CREATE 事件在入队时生成 UUID 并
    /// **持久化进载荷**，重试/复活复用同一个 —— 服务端按它查重，
    /// 命中返回已有记录，杜绝同一篇手稿被重复上传成两份。
    /// 在线直发与发件箱重试统一携带；nil 仅代表升级前的旧载荷，发送前会补签。
    public var clientRequestId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case category
        case title
        case content
        case occurredAt = "occurred_at"
        case location
        case wishId = "wish_id"
        case isPrivate = "is_private"
        case attachmentIds = "attachment_ids"
        case clientRequestId = "client_request_id"
    }

    public init(
        type: String = EntryType.life.rawValue,
        category: String = "",
        title: String = "",
        content: String,
        occurredAt: String = FormatUtils.beijingISOString(),
        location: String? = nil,
        wishId: Int? = nil,
        isPrivate: Bool? = nil,
        attachmentIds: [Int] = [],
        clientRequestId: String? = nil
    ) {
        self.type = type
        self.category = category
        self.title = title
        self.content = content
        self.occurredAt = occurredAt
        self.location = location
        self.wishId = wishId
        self.isPrivate = isPrivate
        self.attachmentIds = attachmentIds
        self.clientRequestId = clientRequestId
    }

    /// 兼容旧版离线发件箱快照（无 `category` 字段时安全回落为空串）
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? EntryType.life.rawValue
        category = (try? container.decodeIfPresent(String.self, forKey: .category)) ?? ""
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        content = try container.decode(String.self, forKey: .content)
        occurredAt = (try? container.decodeIfPresent(String.self, forKey: .occurredAt)) ?? FormatUtils.beijingISOString()
        location = try? container.decodeIfPresent(String.self, forKey: .location)
        wishId = try? container.decodeIfPresent(Int.self, forKey: .wishId)
        isPrivate = try? container.decodeIfPresent(Bool.self, forKey: .isPrivate)
        attachmentIds = (try? container.decodeIfPresent([Int].self, forKey: .attachmentIds)) ?? []
        clientRequestId = try? container.decodeIfPresent(String.self, forKey: .clientRequestId)
    }
}

/// 编辑生活记录请求载荷
public struct UpdateEntryRequest: Codable, Equatable, Sendable {
    public var type: String?
    /// 散页原生分类三态：`nil` 表示不修改（服务端保持原值）；`""` 表示显式归回「日常」；非空值设置对应画廊分区
    public var category: String?
    public var title: String?
    public var content: String?
    public var occurredAt: String?
    public var location: String?
    public var wishId: Int?
    public var isPrivate: Bool?
    public var attachmentIds: [Int]?
    /// 显式清空全部已绑附件（契约三态铁律：删除最后一张照片时需传 `attachment_ids: []` + `clear_attachments: true`）
    public var clearAttachments: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case category
        case title
        case content
        case occurredAt = "occurred_at"
        case location
        case wishId = "wish_id"
        case isPrivate = "is_private"
        case attachmentIds = "attachment_ids"
        case clearAttachments = "clear_attachments"
    }

    public init(
        type: String? = nil,
        category: String? = nil,
        title: String? = nil,
        content: String? = nil,
        occurredAt: String? = nil,
        location: String? = nil,
        wishId: Int? = nil,
        isPrivate: Bool? = nil,
        attachmentIds: [Int]? = nil,
        clearAttachments: Bool? = nil
    ) {
        self.type = type
        self.category = category
        self.title = title
        self.content = content
        self.occurredAt = occurredAt
        self.location = location
        self.wishId = wishId
        self.isPrivate = isPrivate
        self.attachmentIds = attachmentIds
        self.clearAttachments = clearAttachments
    }
}

/// 全局档案指标统计 (GET /api/v1/stats)
public struct GlobalStats: Codable, Equatable, Sendable {
    public var totalEntries: Int
    public var totalPhotos: Int
    public var monthExpense: Int64
    public var currentYear: Int
    public var currentMonth: Int

    enum CodingKeys: String, CodingKey {
        case totalEntries = "total_entries"
        case totalPhotos = "total_photos"
        case monthExpense = "month_expense"
        case currentYear = "current_year"
        case currentMonth = "current_month"
    }

    public init(
        totalEntries: Int = 0,
        totalPhotos: Int = 0,
        monthExpense: Int64 = 0,
        currentYear: Int = FormatUtils.beijingCurrentYearMonth().year,
        currentMonth: Int = FormatUtils.beijingCurrentYearMonth().month
    ) {
        self.totalEntries = totalEntries
        self.totalPhotos = totalPhotos
        self.monthExpense = monthExpense
        self.currentYear = currentYear
        self.currentMonth = currentMonth
    }
}

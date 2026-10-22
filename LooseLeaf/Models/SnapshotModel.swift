import Foundation

/// 离线发件箱动作类型 (Outbox Pattern)
/// 说明：本文件承载「主应用与 Widget 共享」的本地快照模型，二者均需编译本文件（Widget 以只读方式解码快照）。
public enum OutboxActionKind: String, Codable, Sendable {
    case createEntry = "create_entry"
    case deleteEntry = "delete_entry"
    case createTransaction = "create_transaction"
    case deleteTransaction = "delete_transaction"
}

/// 离线待同步队列项
public struct OutboxItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: OutboxActionKind
    public var localTempId: Int
    public var targetServerId: Int?
    public var entryRequest: CreateEntryRequest?
    public var transactionRequest: CreateTransactionRequest?
    public var retryCount: Int
    public var lastError: String?
    public var createdAt: String

    public init(
        id: UUID = UUID(),
        kind: OutboxActionKind,
        localTempId: Int,
        targetServerId: Int? = nil,
        entryRequest: CreateEntryRequest? = nil,
        transactionRequest: CreateTransactionRequest? = nil,
        retryCount: Int = 0,
        lastError: String? = nil,
        createdAt: String = FormatUtils.beijingISOString()
    ) {
        self.id = id
        self.kind = kind
        self.localTempId = localTempId
        self.targetServerId = targetServerId
        self.entryRequest = entryRequest
        self.transactionRequest = transactionRequest
        self.retryCount = retryCount
        self.lastError = lastError
        self.createdAt = createdAt
    }
}

/// 本地持久化快照结构
public struct LocalArchiveSnapshot: Codable, Sendable {
    /// 快照结构版本号：任何字段增删都必须递增，并在此处实现迁移链，
    /// 否则老用户快照会命中「解码失败 → 隔离备份」路径，表现为「档案凭空消失」。
    public static let currentSchemaVersion: Int = 3

    public var schemaVersion: Int
    public var entries: [LifeEntry]
    public var transactions: [Transaction]
    public var transactionSummary: TransactionSummary
    public var profile: CuratorProfile
    public var siteConfig: SiteConfig
    public var stats: GlobalStats
    public var outbox: [OutboxItem]
    public var lastEntriesSyncCursor: String?
    public var lastTransactionsSyncCursor: String?
    /// 快照里的媒体签名地址最后一次**换签**的时间
    ///
    /// 关键：快照持久化了 `attachment.url` / `thumbnailUrl`，
    /// 而它们是**会过期**的签名地址（本机媒体签名 30 分钟、R2 预签名同理）。
    /// 快照离线读出来时，这些地址可能早已失效 ⇒ 相纸显示「载入失败」
    /// （磁盘缓存热时能兜住，冷缓存就兜不住）。
    ///
    /// 这个字段记录「上次换签时间」——
    /// nil 表示「还不知道」（v2 快照迁移上来就是 nil）⇒ 下次启动立即换签一次。
    public var mediaURLsRefreshedAt: String?
    public var updatedAt: String

    public init(
        schemaVersion: Int = LocalArchiveSnapshot.currentSchemaVersion,
        entries: [LifeEntry] = [],
        transactions: [Transaction] = [],
        transactionSummary: TransactionSummary = TransactionSummary(),
        profile: CuratorProfile = CuratorProfile(),
        siteConfig: SiteConfig = SiteConfig(),
        stats: GlobalStats = GlobalStats(),
        outbox: [OutboxItem] = [],
        lastEntriesSyncCursor: String? = nil,
        lastTransactionsSyncCursor: String? = nil,
        mediaURLsRefreshedAt: String? = nil,
        updatedAt: String = FormatUtils.beijingISOString()
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
        self.transactions = transactions
        self.transactionSummary = transactionSummary
        self.profile = profile
        self.siteConfig = siteConfig
        self.stats = stats
        self.outbox = outbox
        self.lastEntriesSyncCursor = lastEntriesSyncCursor
        self.lastTransactionsSyncCursor = lastTransactionsSyncCursor
        self.mediaURLsRefreshedAt = mediaURLsRefreshedAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case entries
        case transactions
        case transactionSummary
        case profile
        case siteConfig
        case stats
        case outbox
        case lastEntriesSyncCursor
        case lastTransactionsSyncCursor
        case mediaURLsRefreshedAt = "media_urls_refreshed_at"
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 老快照没有 schemaVersion 字段时按 v1 解释，并在迁移链中升级。
        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 1
        entries = (try? container.decode([LifeEntry].self, forKey: .entries)) ?? []
        transactions = (try? container.decode([Transaction].self, forKey: .transactions)) ?? []
        transactionSummary = (try? container.decode(TransactionSummary.self, forKey: .transactionSummary)) ?? TransactionSummary()
        profile = (try? container.decode(CuratorProfile.self, forKey: .profile)) ?? CuratorProfile()
        siteConfig = (try? container.decode(SiteConfig.self, forKey: .siteConfig)) ?? SiteConfig()
        stats = (try? container.decode(GlobalStats.self, forKey: .stats)) ?? GlobalStats()
        outbox = (try? container.decode([OutboxItem].self, forKey: .outbox)) ?? []
        lastEntriesSyncCursor = try? container.decodeIfPresent(String.self, forKey: .lastEntriesSyncCursor)
        lastTransactionsSyncCursor = try? container.decodeIfPresent(String.self, forKey: .lastTransactionsSyncCursor)
        mediaURLsRefreshedAt = try? container.decodeIfPresent(String.self, forKey: .mediaURLsRefreshedAt)
        updatedAt = (try? container.decode(String.self, forKey: .updatedAt)) ?? FormatUtils.beijingISOString()
    }

    /// 按 `schemaVersion` 逐级迁移到当前版本。
    /// 新增字段一律提供安全默认值；**不得**在此处丢弃任何历史数据。
    ///
    /// - Returns: 迁移后的快照；**nil = 这份快照来自更新版本的应用，拒绝迁移**。
    ///
    /// 关键（未来版本护栏）：快照版本**高于**当前版本时，
    /// 说明用户把应用**降级**了。此时若照旧迁移（把版本号改小），
    /// 新版引入的字段会在解码时被 `try? decode ?? 默认值` 悄悄吃掉 ——
    /// 也就是**静默丢数据**。所以这里必须**拒绝迁移**，
    /// 由调用方把原文件隔离备份并提示用户，绝不覆盖。
    public func migrated(to targetVersion: Int = LocalArchiveSnapshot.currentSchemaVersion) -> LocalArchiveSnapshot? {
        guard schemaVersion <= targetVersion else {
            // 未来版本：拒绝迁移（调用方负责隔离与提示）
            return nil
        }
        var copy = self
        if copy.schemaVersion < 2 {
            // v1 → v2：引入 schemaVersion 字段本身（语义无损）。
            copy.schemaVersion = 2
        }
        if copy.schemaVersion < 3 {
            // v2 → v3：引入 mediaURLsRefreshedAt（语义无损）。
            //
            // 关键：留 nil 而不是「当前时间」——
            // nil 表示「还不知道这些签名地址有没有过期」，
            // 下次启动就会换签一次；而填当前时间等于假装刚换过，
            // 那份从磁盘读出来的、**可能早已失效**的地址就会被继续信任。
            copy.schemaVersion = 3
            copy.mediaURLsRefreshedAt = nil
        }
        copy.schemaVersion = targetVersion
        return copy
    }
}

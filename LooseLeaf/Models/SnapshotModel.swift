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
    public static let currentSchemaVersion: Int = 2

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
        updatedAt = (try? container.decode(String.self, forKey: .updatedAt)) ?? FormatUtils.beijingISOString()
    }

    /// 按 `schemaVersion` 逐级迁移到当前版本。
    /// 新增字段一律提供安全默认值；**不得**在此处丢弃任何历史数据。
    public func migrated(to targetVersion: Int = LocalArchiveSnapshot.currentSchemaVersion) -> LocalArchiveSnapshot {
        var copy = self
        if copy.schemaVersion < 2 {
            // v1 → v2：引入 schemaVersion 字段本身（语义无损）。
            copy.schemaVersion = 2
        }
        copy.schemaVersion = targetVersion
        return copy
    }
}

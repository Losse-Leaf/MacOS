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
}

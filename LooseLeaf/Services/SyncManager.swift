import Foundation
import Network
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 离线发件箱动作类型 (Outbox Pattern)
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

/// 本地持久化与小组件共享快照结构
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

/// 本地优先存储与离线发件箱同步调度引擎 (Local-First & Sync Outbox Engine)
/// 严格遵循 docs/macos.md §4 与 docs/ecosystem.md §7 规范
@MainActor
public final class SyncManager {
    public static let shared = SyncManager()

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.looseleaf.archive.network.monitor")

    public private(set) var isOnline: Bool = true
    public private(set) var isFlushingOutbox: Bool = false
    public var onSnapshotUpdated: ((LocalArchiveSnapshot) -> Void)?

    private var snapshot: LocalArchiveSnapshot

    private init() {
        self.snapshot = Self.loadFromDisk() ?? LocalArchiveSnapshot()
        startNetworkMonitor()
    }

    // MARK: - 本地磁盘缓存路径 (支持主应用与 WidgetKit 小组件共享读取)

    public nonisolated static var sharedStorageDirectory: URL {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.looseleaf.archive.shared") {
            return groupURL
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("LooseLeaf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public nonisolated static var snapshotFileURL: URL {
        sharedStorageDirectory.appendingPathComponent("archive_snapshot.json")
    }

    public nonisolated static func loadFromDisk() -> LocalArchiveSnapshot? {
        let url = snapshotFileURL
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LocalArchiveSnapshot.self, from: data)
    }

    public func currentSnapshot() -> LocalArchiveSnapshot {
        snapshot
    }

    public func saveSnapshot(_ updated: LocalArchiveSnapshot) {
        var copy = updated
        copy.updatedAt = FormatUtils.beijingISOString()
        self.snapshot = copy
        if let data = try? JSONEncoder().encode(copy) {
            try? data.write(to: Self.snapshotFileURL, options: .atomic)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        onSnapshotUpdated?(copy)
    }

    // MARK: - 网络监听与自动补发 (NWPathMonitor)

    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = online
                if online && (wasOffline || !self.snapshot.outbox.isEmpty) {
                    await self.flushOutbox()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - 写入流：在线直发 + 断网自动转入 Outbox 队列

    /// 提交新生活记录（在线直接落库，离线或网络阻断时写入本地 Outbox 乐观更新）
    public func submitEntry(_ req: CreateEntryRequest) async throws -> (entry: LifeEntry, queuedOffline: Bool) {
        if isOnline {
            do {
                let created = try await APIClient.shared.createEntry(req)
                mergeEntries([created], isDelta: true)
                return (created, false)
            } catch let apiErr as APIError {
                // 401 未授权或 400 参数错误直接抛出，不进离线队列
                switch apiErr {
                case .unauthorized, .serverError(code: 400, _):
                    throw apiErr
                default:
                    break
                }
            } catch {
                // 网络中断：降级转入本地 Outbox
            }
        }

        let tempId = -Int(Date().timeIntervalSince1970 * 1000) % 900_000 - 1
        let optimistic = LifeEntry(
            id: tempId,
            type: req.type,
            title: req.title,
            content: req.content,
            occurredAt: req.occurredAt,
            location: req.location,
            cityCode: req.cityCode,
            cityName: req.cityName,
            projectId: req.projectId,
            wishId: req.wishId,
            footprintId: req.footprintId,
            featured: req.featured,
            syncStatus: "pending_create"
        )

        var current = snapshot
        current.entries.insert(optimistic, at: 0)
        current.outbox.append(OutboxItem(
            kind: .createEntry,
            localTempId: tempId,
            entryRequest: req
        ))
        saveSnapshot(current)
        return (optimistic, true)
    }

    /// 提交新记账流水（在线直接落库，离线或网络阻断时写入本地 Outbox 乐观更新）
    public func submitTransaction(_ req: CreateTransactionRequest) async throws -> (transaction: Transaction, queuedOffline: Bool) {
        if isOnline {
            do {
                let created = try await APIClient.shared.createTransaction(req)
                mergeTransactions([created], isDelta: true)
                return (created, false)
            } catch let apiErr as APIError {
                switch apiErr {
                case .unauthorized, .serverError(code: 400, _):
                    throw apiErr
                default:
                    break
                }
            } catch {
                // 网络中断：降级转入本地 Outbox
            }
        }

        let tempId = -Int(Date().timeIntervalSince1970 * 1000) % 900_000 - 1
        let optimistic = Transaction(
            id: tempId,
            amount: req.amount,
            type: req.type,
            category: req.category,
            title: req.title,
            note: req.note,
            paymentMethod: req.paymentMethod,
            wishId: req.wishId,
            footprintId: req.footprintId,
            cityCode: req.cityCode,
            occurredAt: req.occurredAt,
            syncStatus: "pending_create"
        )

        var current = snapshot
        current.transactions.insert(optimistic, at: 0)
        if req.type == "expense" {
            current.transactionSummary.totalExpense += req.amount
            current.transactionSummary.categoryBreakdown[req.category, default: 0] += req.amount
        } else {
            current.transactionSummary.totalIncome += req.amount
        }
        current.transactionSummary.balance = current.transactionSummary.totalIncome - current.transactionSummary.totalExpense
        current.outbox.append(OutboxItem(
            kind: .createTransaction,
            localTempId: tempId,
            transactionRequest: req
        ))
        saveSnapshot(current)
        return (optimistic, true)
    }

    /// 排空并同步本地 Outbox 待发送队列
    public func flushOutbox() async {
        guard !isFlushingOutbox, !snapshot.outbox.isEmpty else { return }
        isFlushingOutbox = true
        defer { isFlushingOutbox = false }

        var remaining: [OutboxItem] = []
        var current = snapshot

        for var item in current.outbox {
            do {
                switch item.kind {
                case .createEntry:
                    if let req = item.entryRequest {
                        let created = try await APIClient.shared.createEntry(req)
                        current.entries.removeAll { $0.id == item.localTempId }
                        current.entries.insert(created, at: 0)
                    }
                case .deleteEntry:
                    if let targetId = item.targetServerId {
                        try await APIClient.shared.deleteEntry(id: targetId)
                        current.entries.removeAll { $0.id == targetId }
                    }
                case .createTransaction:
                    if let req = item.transactionRequest {
                        let created = try await APIClient.shared.createTransaction(req)
                        current.transactions.removeAll { $0.id == item.localTempId }
                        current.transactions.insert(created, at: 0)
                    }
                case .deleteTransaction:
                    if let targetId = item.targetServerId {
                        try await APIClient.shared.deleteTransaction(id: targetId)
                        current.transactions.removeAll { $0.id == targetId }
                    }
                }
            } catch {
                item.retryCount += 1
                item.lastError = error.localizedDescription
                remaining.append(item)
            }
        }

        current.outbox = remaining
        saveSnapshot(current)
    }

    // MARK: - 增量拉取与软删除对账合并 (Delta Sync & LWW Reconciliation)

    public func mergeEntries(_ incoming: [LifeEntry], isDelta: Bool) {
        var current = snapshot
        if !isDelta {
            let pendingLocal = current.entries.filter { ($0.syncStatus ?? "synced") != "synced" }
            let validRemote = incoming.filter { ($0.deletedAt ?? "").isEmpty }
            current.entries = pendingLocal + validRemote
        } else {
            var map = Dictionary(uniqueKeysWithValues: current.entries.map { ($0.id, $0) })
            for entry in incoming {
                if let deleted = entry.deletedAt, !deleted.isEmpty {
                    map.removeValue(forKey: entry.id)
                } else {
                    var syncedEntry = entry
                    syncedEntry.syncStatus = "synced"
                    map[entry.id] = syncedEntry
                }
            }
            current.entries = map.values.sorted {
                let d1 = FormatUtils.parseFlexDate($0.occurredAt) ?? .distantPast
                let d2 = FormatUtils.parseFlexDate($1.occurredAt) ?? .distantPast
                if d1 != d2 { return d1 > d2 }
                return $0.id > $1.id
            }
        }
        current.lastEntriesSyncCursor = FormatUtils.beijingISOString()
        saveSnapshot(current)
    }

    public func mergeTransactions(_ incoming: [Transaction], isDelta: Bool) {
        var current = snapshot
        if !isDelta {
            let pendingLocal = current.transactions.filter { ($0.syncStatus ?? "synced") != "synced" }
            let validRemote = incoming.filter { ($0.deletedAt ?? "").isEmpty }
            current.transactions = pendingLocal + validRemote
        } else {
            var map = Dictionary(uniqueKeysWithValues: current.transactions.map { ($0.id, $0) })
            for tx in incoming {
                if let deleted = tx.deletedAt, !deleted.isEmpty {
                    map.removeValue(forKey: tx.id)
                } else {
                    var syncedTx = tx
                    syncedTx.syncStatus = "synced"
                    map[tx.id] = syncedTx
                }
            }
            current.transactions = map.values.sorted {
                let d1 = FormatUtils.parseFlexDate($0.occurredAt) ?? .distantPast
                let d2 = FormatUtils.parseFlexDate($1.occurredAt) ?? .distantPast
                if d1 != d2 { return d1 > d2 }
                return $0.id > $1.id
            }
        }
        current.lastTransactionsSyncCursor = FormatUtils.beijingISOString()
        saveSnapshot(current)
    }
}

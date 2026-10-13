import Foundation
import Network
import os

/// 本地优先存储与离线发件箱同步调度引擎 (Local-First & Sync Outbox Engine)
/// 严格遵循 docs/macos.md §4 与 docs/ecosystem.md §7 规范
/// 注：OutboxItem / LocalArchiveSnapshot 已移至 Models/SnapshotModel.swift
@MainActor
public final class SyncManager {
    public static let shared = SyncManager()

    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "sync")

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

    // MARK: - 本地临时 ID 生成

    private nonisolated(unsafe) static var tempIdSequence: Int = 0
    private static let tempIdLock = NSLock()

    /// 生成离线乐观记录的本地临时 ID（负值，与服务器正 ID 区分）。
    /// 毫秒时间戳 × 1000 + 进程内自增序号：跨毫秒近似有序，同毫秒内连续调用也不会碰撞。
    nonisolated static func makeLocalTempId() -> Int {
        tempIdLock.lock()
        let seq = tempIdSequence % 1000
        tempIdSequence += 1
        tempIdLock.unlock()
        return -(Int(Date().timeIntervalSince1970 * 1000) * 1000 + seq)
    }

    // MARK: - 本地磁盘缓存路径

    /// App Group 标识符（容器不可用时自动回退到 Application Support）
    public nonisolated static let appGroupIdentifier = "group.com.looseleaf.archive"

    /// 快照文件名（archive_snapshot_v1.json）
    public nonisolated static var sharedStorageDirectory: URL {
        let dir: URL
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            dir = groupURL.appendingPathComponent("LooseLeafArchive", isDirectory: true)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            dir = appSupport.appendingPathComponent("LooseLeafArchive", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public nonisolated static var snapshotFileURL: URL {
        sharedStorageDirectory.appendingPathComponent("archive_snapshot_v1.json")
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
                Self.logger.info("Network status: \(online ? "online" : "offline", privacy: .public)")
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

        let tempId = Self.makeLocalTempId()
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

        let tempId = Self.makeLocalTempId()
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

        Self.logger.info("Flushing outbox: \(self.snapshot.outbox.count) item(s) queued")

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
        Self.logger.info("Outbox flush finished, \(remaining.count) item(s) still pending")
    }

    // MARK: - 增量拉取与软删除对账合并 (Delta Sync & LWW Reconciliation)

    /// 计算增量响应中的最新服务端游标 (取 `updated_at` / `deleted_at` 最大值)。
    /// 使用服务端时间戳而非本地时钟，避免时钟漂移导致增量漏拉；无有效时间戳时返回 nil（保持旧游标不推进）。
    nonisolated static func latestServerCursor(_ timestamps: [String?]) -> String? {
        timestamps.compactMap { $0 }.filter { !$0.isEmpty }.max()
    }

    public func mergeEntries(_ incoming: [LifeEntry], isDelta: Bool) {
        var current = snapshot
        current.entries = Self.mergedEntries(current: current.entries, incoming: incoming, isDelta: isDelta)
        if let latest = Self.latestServerCursor(incoming.flatMap { [$0.updatedAt, $0.deletedAt] }) {
            current.lastEntriesSyncCursor = latest
        }
        saveSnapshot(current)
    }

    /// 时间流合并（纯函数，可单测）：
    /// 全量覆盖时保留本地未同步项；增量时执行软删除对账并按北京时间倒序排列。
    nonisolated static func mergedEntries(current: [LifeEntry], incoming: [LifeEntry], isDelta: Bool) -> [LifeEntry] {
        if !isDelta {
            let pendingLocal = current.filter { ($0.syncStatus ?? "synced") != "synced" }
            let validRemote = incoming.filter { ($0.deletedAt ?? "").isEmpty }
            return pendingLocal + validRemote
        }
        var map = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for entry in incoming {
            if let deleted = entry.deletedAt, !deleted.isEmpty {
                map.removeValue(forKey: entry.id)
            } else {
                var syncedEntry = entry
                syncedEntry.syncStatus = "synced"
                map[entry.id] = syncedEntry
            }
        }
        return map.values.sorted {
            let d1 = FormatUtils.parseFlexDate($0.occurredAt) ?? .distantPast
            let d2 = FormatUtils.parseFlexDate($1.occurredAt) ?? .distantPast
            if d1 != d2 { return d1 > d2 }
            return $0.id > $1.id
        }
    }

    public func mergeTransactions(_ incoming: [Transaction], isDelta: Bool) {
        var current = snapshot
        current.transactions = Self.mergedTransactions(current: current.transactions, incoming: incoming, isDelta: isDelta)
        if let latest = Self.latestServerCursor(incoming.flatMap { [$0.updatedAt, $0.deletedAt] }) {
            current.lastTransactionsSyncCursor = latest
        }
        saveSnapshot(current)
    }

    /// 账目合并（纯函数，可单测）：语义与 `mergedEntries` 一致。
    nonisolated static func mergedTransactions(current: [Transaction], incoming: [Transaction], isDelta: Bool) -> [Transaction] {
        if !isDelta {
            let pendingLocal = current.filter { ($0.syncStatus ?? "synced") != "synced" }
            let validRemote = incoming.filter { ($0.deletedAt ?? "").isEmpty }
            return pendingLocal + validRemote
        }
        var map = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for tx in incoming {
            if let deleted = tx.deletedAt, !deleted.isEmpty {
                map.removeValue(forKey: tx.id)
            } else {
                var syncedTx = tx
                syncedTx.syncStatus = "synced"
                map[tx.id] = syncedTx
            }
        }
        return map.values.sorted {
            let d1 = FormatUtils.parseFlexDate($0.occurredAt) ?? .distantPast
            let d2 = FormatUtils.parseFlexDate($1.occurredAt) ?? .distantPast
            if d1 != d2 { return d1 > d2 }
            return $0.id > $1.id
        }
    }
}

import Foundation
import Network
import os

/// 本地优先存储与离线发件箱同步调度引擎 (Local-First & Sync Outbox Engine)
/// 严格遵循 docs/macos.md §4 与 docs/ecosystem.md §7 规范
/// 注：OutboxItem / LocalArchiveSnapshot 已移至 Models/SnapshotModel.swift
@MainActor
public final class SyncManager {
    public static let shared = SyncManager()

    nonisolated private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "sync")

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.looseleaf.archive.network.monitor")
    private let diskWriteQueue = DispatchQueue(label: "com.looseleaf.archive.snapshot.io", qos: .utility)

    public private(set) var isOnline: Bool = true
    public private(set) var isFlushingOutbox: Bool = false
    public var onSnapshotUpdated: ((LocalArchiveSnapshot) -> Void)?
    public var onNetworkStatusChanged: ((Bool) -> Void)?

    private var snapshot: LocalArchiveSnapshot
    private var pendingWrite: DispatchWorkItem?

    private init() {
        self.snapshot = Self.loadFromDisk() ?? LocalArchiveSnapshot()
        startNetworkMonitor()
    }

    // MARK: - 本地临时 ID 生成

    private nonisolated(unsafe) static var tempIdSequence: Int = 0
    private nonisolated static let tempIdLock = NSLock()

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

    /// 快照文件名（archive_snapshot_v1.json）
    /// 本地快照目录 (存储于 ~/Library/Application Support/LooseLeaf/ 保证沙箱环境下 100% 可靠读写)
    public nonisolated static var sharedStorageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("LooseLeaf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public nonisolated static var snapshotFileURL: URL {
        sharedStorageDirectory.appendingPathComponent("archive_snapshot_v1.json")
    }

    /// 最近一次本地快照加载失败的原因（供启动期提示，nil 表示加载正常或文件不存在）
    nonisolated(unsafe) public private(set) static var lastLoadFailureMessage: String?

    public nonisolated static func loadFromDisk() -> LocalArchiveSnapshot? {
        let url = snapshotFileURL
        guard let data = try? Data(contentsOf: url) else {
            lastLoadFailureMessage = nil
            return nil
        }
        do {
            lastLoadFailureMessage = nil
            return try JSONDecoder().decode(LocalArchiveSnapshot.self, from: data)
        } catch {
            // 解码失败绝不静默重建：先把原文件隔离备份，否则随后任何一次 saveSnapshot
            // 都会用空快照原子覆盖掉用户仅存的一份本地档案。
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backupURL = url.deletingLastPathComponent()
                .appendingPathComponent("archive_snapshot_v1.corrupt-\(stamp).json")
            let moved = (try? FileManager.default.moveItem(at: url, to: backupURL)) != nil
            lastLoadFailureMessage = moved
                ? "本地快照无法解析，已隔离备份为 \(backupURL.lastPathComponent)，本次以空档案启动，请勿继续录入以免混淆。"
                : "本地快照无法解析且备份失败，请立即手动备份 \(url.path) 后再启动。"
            Self.logger.error("Snapshot decode failed: \(error.localizedDescription, privacy: .public); backup moved: \(moved)")
            return nil
        }
    }

    public func currentSnapshot() -> LocalArchiveSnapshot {
        snapshot
    }

    /// 原子更新站点配置、主理人档案与统计（始终基于当前最新 snapshot 原地打补丁，杜绝并发拉取时冲刷条目数据）
    public func updateConfigAndProfile(siteConfig: SiteConfig?, profile: CuratorProfile?, stats: GlobalStats?) {
        var latest = snapshot
        if let siteConfig { latest.siteConfig = siteConfig }
        if let profile { latest.profile = profile }
        if let stats { latest.stats = stats }
        saveSnapshot(latest)
    }

    /// 原子更新月度记账概览
    public func updateTransactionSummary(_ summary: TransactionSummary) {
        var latest = snapshot
        latest.transactionSummary = summary
        saveSnapshot(latest)
    }

    public func saveSnapshot(_ updated: LocalArchiveSnapshot) {
        var copy = updated
        copy.updatedAt = FormatUtils.beijingISOString()
        self.snapshot = copy
        // 立即通知 UI 响应刷新，保证 0ms 上屏
        onSnapshotUpdated?(copy)
        scheduleDiskWrite(copy)
    }

    /// 合并 0.35 秒内的连续保存：一次全量刷新会触发 5 次 save，没必要写 5 次盘。
    private func scheduleDiskWrite(_ copy: LocalArchiveSnapshot) {
        pendingWrite?.cancel()
        let fileURL = Self.snapshotFileURL
        let item = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(copy) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
        pendingWrite = item
        diskWriteQueue.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    /// 退出前同步落盘，确保防抖窗口内的最后一次修改不丢失
    public func flushSnapshotToDiskIfNeeded() {
        pendingWrite?.cancel()
        pendingWrite = nil
        let copy = snapshot
        let fileURL = Self.snapshotFileURL
        if let data = try? JSONEncoder().encode(copy) {
            try? data.write(to: fileURL, options: .atomic)
        }
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
                self.onNetworkStatusChanged?(online)
                if online && (wasOffline || !self.snapshot.outbox.isEmpty) {
                    await self.flushOutbox()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - 写入流：在线直发 + 断网自动转入 Outbox 队列

    /// 提交新生活记录（在线直接落库，离线或网络阻断时写入本地 Outbox 乐观更新）
    public func submitEntry(_ req: CreateEntryRequest, attachments: [Attachment] = []) async throws -> (entry: LifeEntry, queuedOffline: Bool) {
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
            attachments: attachments,
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

        let itemsToFlush = snapshot.outbox

        for item in itemsToFlush {
            // 确保该项目尚未被外部清除
            guard self.snapshot.outbox.contains(where: { $0.id == item.id }) else { continue }
            do {
                switch item.kind {
                case .createEntry:
                    if let req = item.entryRequest {
                        let created = try await APIClient.shared.createEntry(req)
                        var latest = self.snapshot
                        latest.entries.removeAll { $0.id == item.localTempId }
                        latest.entries.insert(created, at: 0)
                        latest.outbox.removeAll { $0.id == item.id }
                        self.saveSnapshot(latest)
                    }
                case .deleteEntry:
                    if let targetId = item.targetServerId {
                        try await APIClient.shared.deleteEntry(id: targetId)
                        var latest = self.snapshot
                        latest.entries.removeAll { $0.id == targetId }
                        latest.outbox.removeAll { $0.id == item.id }
                        self.saveSnapshot(latest)
                    }
                case .createTransaction:
                    if let req = item.transactionRequest {
                        let created = try await APIClient.shared.createTransaction(req)
                        var latest = self.snapshot
                        latest.transactions.removeAll { $0.id == item.localTempId }
                        latest.transactions.insert(created, at: 0)
                        latest.outbox.removeAll { $0.id == item.id }
                        self.saveSnapshot(latest)
                    }
                case .deleteTransaction:
                    if let targetId = item.targetServerId {
                        try await APIClient.shared.deleteTransaction(id: targetId)
                        var latest = self.snapshot
                        latest.transactions.removeAll { $0.id == targetId }
                        latest.outbox.removeAll { $0.id == item.id }
                        self.saveSnapshot(latest)
                    }
                }
            } catch {
                var latest = self.snapshot
                if let idx = latest.outbox.firstIndex(where: { $0.id == item.id }) {
                    latest.outbox[idx].retryCount += 1
                    latest.outbox[idx].lastError = error.localizedDescription
                    self.saveSnapshot(latest)
                }
            }
        }
        Self.logger.info("Outbox flush finished, \(self.snapshot.outbox.count) item(s) still pending")
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
            return sortedEntries(pendingLocal + validRemote)
        }
        // 本地快照可能因分页重叠/历史遗留出现重复 id，必须容错而不是 trap
        var map = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for entry in incoming {
            if let deleted = entry.deletedAt, !deleted.isEmpty {
                map.removeValue(forKey: entry.id)
            } else {
                var syncedEntry = entry
                syncedEntry.syncStatus = "synced"
                map[entry.id] = syncedEntry
            }
        }
        return sortedEntries(Array(map.values))
    }

    /// 时间流统一排序（全量与增量共用）：北京时间倒序，同刻按服务端 id 倒序。
    /// 排序前一次性提取时间戳 (O(N))，避免比较器内部重复 DateFormatter 解析。
    nonisolated static func sortedEntries(_ entries: [LifeEntry]) -> [LifeEntry] {
        let itemsWithDate: [(entry: LifeEntry, date: Date)] = entries.map {
            ($0, FormatUtils.parseFlexDate($0.occurredAt) ?? .distantPast)
        }
        return itemsWithDate.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.entry.id > $1.entry.id
        }.map(\.entry)
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
            return sortedTransactions(pendingLocal + validRemote)
        }
        var map = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for tx in incoming {
            if let deleted = tx.deletedAt, !deleted.isEmpty {
                map.removeValue(forKey: tx.id)
            } else {
                var syncedTx = tx
                syncedTx.syncStatus = "synced"
                map[tx.id] = syncedTx
            }
        }
        return sortedTransactions(Array(map.values))
    }

    /// 账目统一排序：语义与 `sortedEntries` 一致。
    nonisolated static func sortedTransactions(_ transactions: [Transaction]) -> [Transaction] {
        let itemsWithDate: [(tx: Transaction, date: Date)] = transactions.map {
            ($0, FormatUtils.parseFlexDate($0.occurredAt) ?? .distantPast)
        }
        return itemsWithDate.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.tx.id > $1.tx.id
        }.map(\.tx)
    }
}

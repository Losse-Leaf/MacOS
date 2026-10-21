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

    /// 发件箱单条最大重试次数，超过即判定为死信并丢弃（避免无限重试与无界增长）
    public static let maxOutboxRetryCount = 5

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.looseleaf.archive.network.monitor")
    private let diskWriteQueue = DispatchQueue(label: "com.looseleaf.archive.snapshot.io", qos: .utility)

    public private(set) var isOnline: Bool = true
    public private(set) var isFlushingOutbox: Bool = false

    /// 快照更新回调（保证在主线程调用，UI 可零延迟响应）
    public var onSnapshotUpdated: (@MainActor (LocalArchiveSnapshot) -> Void)?
    public var onNetworkStatusChanged: (@MainActor (Bool) -> Void)?
    /// 本地快照加载失败时的用户可读告警（nil 表示正常）
    public var onLocalDataWarning: (@MainActor (String) -> Void)?

    private var snapshot: LocalArchiveSnapshot
    private var pendingWrite: DispatchWorkItem?
    /// 单调递增的快照版本号：只有更高版本的快照才允许落盘，杜绝「旧数据覆盖新数据」
    private var snapshotRevision: UInt64 = 0
    /// 批量更新模式：一次全量同步会触发多次保存，
    /// 若每次都立即回调 UI，会造成 5 次整页重绘。此模式下只在批次结束时回调一次。
    private var isBatching: Bool = false
    private var pendingBatchSnapshot: LocalArchiveSnapshot?
    /// 已落盘的最大版本号（跨线程访问，仅由 diskWriteQueue 读写）
    nonisolated(unsafe) private static var lastWrittenRevision: UInt64 = 0
    /// 最近一次网络状态（用于去重，避免同状态反复触发排空队列）
    private var lastKnownOnline: Bool?

    private init() {
        // 首屏 0 阻塞：先给空壳立即返回，快照在后台线程解码完成后再注水。
        self.snapshot = LocalArchiveSnapshot()
        startNetworkMonitor()
        hydrateFromDiskInBackground()
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

    /// 本地快照目录 (存储于 ~/Library/Application Support/LooseLeaf/ 保证沙箱环境下 100% 可靠读写)
    /// 目录 URL 只计算一次，避免每次写盘都做一次 createDirectory 系统调用。
    nonisolated public static let sharedStorageDirectory: URL = {
        // 诊断用：允许把整个存储目录（凭据 / 快照 / 媒体缓存）指到别处。
        // 关键：UI 测试与性能剖析必须有一份**完全隔离**的存储，
        // 否则测试会读写用户真实的中枢令牌与档案。
        if let override = ProcessInfo.processInfo.environment["LOOSELEAF_STORAGE_DIR"],
           !override.isEmpty {
            let dir = URL(fileURLWithPath: override, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            return dir
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("LooseLeaf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 目录权限收紧为 0700，且排除 Time Machine / iCloud 备份（令牌等敏感文件不可外传）
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDir = dir
        try? mutableDir.setResourceValues(resourceValues)
        return dir
    }()

    public nonisolated static var snapshotFileURL: URL {
        sharedStorageDirectory.appendingPathComponent("archive_snapshot_v1.json")
    }

    /// 最近一次本地快照加载失败的原因（供启动期提示，nil 表示加载正常或文件不存在）
    public private(set) var lastLoadFailureMessage: String?

    /// 磁盘读取 + JSON 解码（纯 IO，可在任意线程调用）
    nonisolated static func loadFromDisk() -> LocalArchiveSnapshot? {
        loadSnapshotFromDisk(at: snapshotFileURL).snapshot
    }

    /// 磁盘读取 + JSON 解码，返回快照与失败原因。
    /// 解码失败绝不静默重建：先把原文件隔离备份，否则随后任何一次 saveSnapshot
    /// 都会用空快照原子覆盖掉用户仅存的一份本地档案。
    nonisolated static func loadSnapshotFromDisk(at url: URL) -> (snapshot: LocalArchiveSnapshot?, failureMessage: String?) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return (nil, nil)
        }
        do {
            let decoded = try JSONDecoder().decode(LocalArchiveSnapshot.self, from: data)
            return (decoded.migrated(), nil)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backupURL = url.deletingLastPathComponent()
                .appendingPathComponent("archive_snapshot_v1.corrupt-\(stamp).json")
            let moved = (try? FileManager.default.moveItem(at: url, to: backupURL)) != nil
            let message = moved
                ? "本地快照无法解析，已隔离备份为 \(backupURL.lastPathComponent)，本次以空档案启动，请勿继续录入以免混淆。"
                : "本地快照无法解析且备份失败，请立即手动备份 \(url.path) 后再启动。"
            Self.logger.error("Snapshot decode failed: \(error.localizedDescription, privacy: .public); backup moved: \(moved)")
            return (nil, message)
        }
    }

    /// 后台解码本地快照并在主线程注水，避免冷启动首帧被主线程 IO 阻塞。
    private func hydrateFromDiskInBackground() {
        let fileURL = Self.snapshotFileURL
        Task.detached(priority: .userInitiated) {
            let result = ArchivePerformance.measure(.startup, "decodeSnapshot") {
                Self.loadSnapshotFromDisk(at: fileURL)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let message = result.failureMessage {
                    self.lastLoadFailureMessage = message
                    self.onLocalDataWarning?(message)
                    return
                }
                guard let loaded = result.snapshot else { return }

                // 关键：**不要**无条件用磁盘快照覆盖内存快照。
                //
                // 注水是后台异步解码（几千条 JSON 约 100~500ms）。在这段时间里
                // 用户可能已经：提交了一条记录（乐观写入）、或把服务端首页
                // 合并进了快照。此时若无条件 `self.snapshot = loaded`，
                // 那些刚写进去的数据会被**整体抹掉**，并且之后的每次
                // saveSnapshot 都以这个旧快照为基准 —— 磁盘上的新数据也被回滚覆盖。
                //
                // 正确做法：已经有本地写入时，注水只负责「填空」，
                // 条目一律走增量合并。
                if self.snapshotRevision > 0 {
                    // 本地已被改写 → 增量合并，不覆盖
                    var merged = self.snapshot
                    merged.entries = Self.mergedEntries(
                        current: self.snapshot.entries,
                        incoming: loaded.entries,
                        isDelta: true
                    )
                    // 发件箱以本地为准（本地可能有还没发出去的项）
                    if loaded.outbox.isEmpty {
                        merged.outbox = self.snapshot.outbox
                    }
                    if (merged.lastEntriesSyncCursor ?? "").isEmpty {
                        merged.lastEntriesSyncCursor = loaded.lastEntriesSyncCursor
                    }
                    // siteConfig / profile / stats 是**非可选**字段，
                    // 本地内存快照里已有值（来自启动引导或后续更新），
                    // 此时应以本地为准 —— 磁盘上的旧版本不应覆盖它。
                    // 若本地还是空壳（冷启动即注水），才用磁盘里的。
                    self.snapshot = merged
                    self.onSnapshotUpdated?(merged)
                } else {
                    self.snapshot = loaded
                    self.onSnapshotUpdated?(loaded)
                }
            }
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
        copy.schemaVersion = LocalArchiveSnapshot.currentSchemaVersion
        snapshotRevision += 1
        self.snapshot = copy
        if isBatching {
            // 批次内只记录最终状态，批次结束时统一回调一次
            pendingBatchSnapshot = copy
        } else {
            // 立即通知 UI 响应刷新，保证 0ms 上屏
            onSnapshotUpdated?(copy)
        }
        scheduleDiskWrite(copy, revision: snapshotRevision)
    }

    /// 开始批量更新（期间不逐次回调 UI）
    public func beginBatch() {
        isBatching = true
        pendingBatchSnapshot = nil
    }

    /// 结束批量更新（若有变更则回调一次）
    public func endBatch() {
        isBatching = false
        guard let snapshot = pendingBatchSnapshot else { return }
        pendingBatchSnapshot = nil
        onSnapshotUpdated?(snapshot)
    }

    /// 合并 0.35 秒内的连续保存：一次全量刷新会触发 5 次 save，没必要写 5 次盘。
    /// 写盘全部发生在 diskWriteQueue（串行），并用 revision 保证「后写的一定更新」。
    private func scheduleDiskWrite(_ copy: LocalArchiveSnapshot, revision: UInt64) {
        pendingWrite?.cancel()
        let fileURL = Self.snapshotFileURL
        let item = DispatchWorkItem { [weak self] in
            Self.writeSnapshot(copy, to: fileURL, revision: revision)
            _ = self
        }
        pendingWrite = item
        diskWriteQueue.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    /// 串行落盘：只有 revision ≥ 已落盘版本时才允许覆盖，杜绝旧数据回滚新数据。
    nonisolated static func writeSnapshot(_ snapshot: LocalArchiveSnapshot, to url: URL, revision: UInt64) {
        guard revision >= lastWrittenRevision else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            ArchivePerformance.metric(.disk, "snapshotBytes", data.count)
            try ArchivePerformance.measure(.disk, "writeSnapshot") {
                try data.write(to: url, options: .atomic)
            }
            lastWrittenRevision = revision
        } catch {
            Self.logger.error("Snapshot write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 退出前同步落盘，确保防抖窗口内的最后一次修改不丢失。
    /// 关键：在**同一串行队列**上同步等待，而不是在主线程另写一份，否则会与队列中的旧写入乱序。
    public func flushSnapshotToDiskIfNeeded() {
        pendingWrite?.cancel()
        pendingWrite = nil
        let copy = snapshot
        let revision = snapshotRevision
        let fileURL = Self.snapshotFileURL
        diskWriteQueue.sync {
            Self.writeSnapshot(copy, to: fileURL, revision: revision)
        }
    }

    // MARK: - 网络监听与自动补发 (NWPathMonitor)

    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            Task { @MainActor [weak self] in
                guard let self else { return }
                // 状态去重：相同状态不重复回调，避免反复触发排空队列
                if let last = self.lastKnownOnline, last == online { return }
                self.lastKnownOnline = online
                let wasOffline = !(self.isOnline)
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

    /// 提交新生活记录。
    ///
    /// **乐观更新**：先把记录写进本地快照并立即通知 UI（时间流立刻出现这条散页），
    /// 再在后台静默同步到服务端。同步失败时按错误性质分别处理：
    /// - 网络类错误 → 转入 Outbox 待重试，记录保持 `pending_create`
    /// - 4xx 永久错误 → 记录标记为 `failed` 并保留在本地，用户可重试
    public func submitEntry(_ req: CreateEntryRequest, attachments: [Attachment] = []) async throws -> (entry: LifeEntry, queuedOffline: Bool) {
        let optimistic = submitEntryOptimistically(req, attachments: attachments)
        return try await syncPendingEntry(req, tempId: optimistic.id, optimistic: optimistic)
    }

    /// **乐观写入**：立刻把记录写进本地快照并通知 UI（时间流立即可见），完全同步、无任何等待。
    /// - Returns: 本地乐观实体（临时负数 id，状态 `pending_create`）
    @discardableResult
    public func submitEntryOptimistically(_ req: CreateEntryRequest, attachments: [Attachment] = []) -> LifeEntry {
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
            syncStatus: "pending_create"
        )
        var current = snapshot
        // 乐观记录按发生时间归位，而不是无条件插到列表顶部
        current.entries = Self.sortedEntries(current.entries, inserting: optimistic)
        saveSnapshot(current)
        return optimistic
    }

    /// 后台同步一条已乐观写入的记录：
    /// 成功 → 用服务端正式实体替换；网络失败 → 转入 Outbox；4xx 永久失败 → 标记为 failed。
    private func syncPendingEntry(
        _ req: CreateEntryRequest,
        tempId: Int,
        optimistic: LifeEntry
    ) async throws -> (entry: LifeEntry, queuedOffline: Bool) {
        guard isOnline else {
            appendOutbox(.createEntry, localTempId: tempId, entryRequest: req)
            return (optimistic, true)
        }
        do {
            let created = try await APIClient.shared.createEntry(req)
            // 用服务端正式实体替换乐观记录（id 换成真实 id，状态转为已同步）
            var latest = snapshot
            latest.entries.removeAll { $0.id == tempId }
            latest.entries = Self.sortedEntries(latest.entries + [created])
            saveSnapshot(latest)
            return (created, false)
        } catch let apiErr as APIError {
            switch apiErr {
            case .unauthorized:
                // 永久错误：记录保留在时间流并标记为失败，用户可重试
                markEntryFailed(tempId: tempId, reason: apiErr.localizedDescription)
                throw apiErr
            case .serverError(let code, _) where (400..<500).contains(code):
                // 关键：**所有 4xx** 都是永久错误，不只是 400。
                // 原先只覆盖 400，于是 409 / 413 / 415 / 422 会落进下面的
                // 「网络类错误」分支进发件箱重试 5 次，最终成为死信 ——
                // 而本地条目始终是 `pending_create`，界面一直显示
                // 「待同步 / 将自动重试」，实际**永远不会成功**。
                markEntryFailed(tempId: tempId, reason: apiErr.localizedDescription)
                throw apiErr
            default:
                // 网络类错误：转入 Outbox，记录保持待同步
                appendOutbox(.createEntry, localTempId: tempId, entryRequest: req)
                return (optimistic, true)
            }
        } catch {
            // 网络中断：降级转入本地 Outbox
            appendOutbox(.createEntry, localTempId: tempId, entryRequest: req)
            return (optimistic, true)
        }
    }

    /// **非阻塞提交**：立刻乐观写入并返回，后台在独立任务里静默同步。
    /// 调用方（例如创作弹窗）可以马上关闭界面，用户不必等待网络往返。
    @discardableResult
    public func submitEntryInBackground(_ req: CreateEntryRequest, attachments: [Attachment] = []) -> LifeEntry {
        let optimistic = submitEntryOptimistically(req, attachments: attachments)
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.syncPendingEntry(req, tempId: optimistic.id, optimistic: optimistic)
        }
        return optimistic
    }

    /// 追加一条待同步动作到 Outbox
    private func appendOutbox(
        _ kind: OutboxActionKind,
        localTempId: Int,
        entryRequest: CreateEntryRequest? = nil,
        transactionRequest: CreateTransactionRequest? = nil,
        targetServerId: Int? = nil
    ) {
        var latest = snapshot
        // 关键：**同一个本地临时 id + 同一类动作，只保留一条待发项**。
        // 原先是无条件 append —— 于是「提交 → 离线入队 → 用户点重试 →
        // 又入队一条」会让发件箱里躺着两条同一个 tempId 的待发项，
        // 网络恢复后**服务端会收到两份**，本地也多出两条重复条目。
        // 后写覆盖先写：请求内容以最新一次为准。
        latest.outbox.removeAll { $0.kind == kind && $0.localTempId == localTempId }
        latest.outbox.append(OutboxItem(
            kind: kind,
            localTempId: localTempId,
            targetServerId: targetServerId,
            entryRequest: entryRequest,
            transactionRequest: transactionRequest
        ))
        saveSnapshot(latest)
    }

    /// 把一次「删除」排入发件箱（离线时网络恢复后自动补删）
    ///
    /// 关键：早先离线删除会**直接丢掉**删除请求 ——
    /// 界面上只剩一句「删除失败」，网络恢复后也不会补删，
    /// 而 `OutboxActionKind.deleteEntry` 这条链路形同虚设。
    public func enqueueDelete(kind: OutboxActionKind, localTempId: Int, targetServerId: Int) {
        appendOutbox(kind, localTempId: localTempId, targetServerId: targetServerId)
    }

    /// 移除一条**尚未同步**的乐观记录（连同它在发件箱里的待发项）
    ///
    /// 关键：乐观条目的本地 id 是负数，`guard entry.id > 0` 会直接 return ——
    /// 于是用户**无法删除**一条还没同步上去的记录，只能等它同步成功或永远留着。
    public func removeOptimisticEntry(localTempId: Int) {
        var latest = snapshot
        latest.entries.removeAll { $0.id == localTempId }
        latest.outbox.removeAll { $0.localTempId == localTempId }
        saveSnapshot(latest)
    }

    /// 移除一条尚未同步的乐观账目
    public func removeOptimisticTransaction(localTempId: Int) {
        var latest = snapshot
        // 关键：删除乐观账目时**回滚汇总**。
        // 原先只从数组里移除，汇总里的金额却留着 ——
        // 于是「离线记 ¥500 → 又删掉」之后，本月支出仍然多算 ¥500，
        // 直到下次同步才被服务端覆盖。
        if let removed = latest.transactions.first(where: { $0.id == localTempId }),
           Self.isInSummaryMonth(removed.occurredAt, summary: latest.transactionSummary) {
            Self.applySummaryDelta(
                &latest.transactionSummary,
                category: removed.category,
                type: removed.type,
                amount: -removed.amount
            )
        }
        latest.transactions.removeAll { $0.id == localTempId }
        latest.outbox.removeAll { $0.localTempId == localTempId }
        saveSnapshot(latest)
    }

    /// **重传一条已存在的乐观记录**（复用它原本的本地 id）
    ///
    /// 关键：早先的「重试 / 重传」是走 `submitEntryOptimistically` ——
    /// 它**无条件**生成一个新的临时 id 并插入列表。于是：
    ///   1. 列表里同时存在两条内容相同的条目（旧条 + 新条）
    ///   2. 同步成功时只移除**新**临时 id 那条 → **旧条永远留在时间流里**，
    ///      而且状态还是「待同步」，会一直被计入待同步条数
    ///   3. 批量重传时待同步集合 N → 2N，每点一次「全部重传」就翻一倍
    ///
    /// 现在改为**复用既有本地 id**：把原条目标回「待同步」，然后用同一个
    /// tempId 走同步流程 —— 成功时 `syncPendingEntry` 会用服务端实体替换它。
    public func resyncEntry(id: Int, req: CreateEntryRequest, attachments: [Attachment]) {
        guard let existing = snapshot.entries.first(where: { $0.id == id }) else { return }
        markEntryRetrying(id: id)
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.syncPendingEntry(req, tempId: id, optimistic: existing)
        }
    }

    /// **重传一条已存在的乐观账目**（复用它原本的本地 id）
    public func resyncTransaction(id: Int, req: CreateTransactionRequest) {
        guard let existing = snapshot.transactions.first(where: { $0.id == id }) else { return }
        markTransactionRetrying(id: id)
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.syncPendingTransaction(req, tempId: id, optimistic: existing)
        }
    }

    /// 把一条乐观记录标记为同步失败（保留在时间流，等待用户重试）
    private func markEntryFailed(tempId: Int, reason: String) {
        var latest = snapshot
        var touched = false
        for index in latest.entries.indices where latest.entries[index].id == tempId {
            latest.entries[index].syncStatus = "failed"
            touched = true
        }
        guard touched else { return }
        saveSnapshot(latest)
        Self.logger.error("Entry \(tempId) marked as failed: \(reason, privacy: .public)")
    }

    /// 提交新记账流水（在线直接落库，离线或网络阻断时写入本地 Outbox 乐观更新）
    public func submitTransaction(_ req: CreateTransactionRequest) async throws -> (transaction: Transaction, queuedOffline: Bool) {
        let optimistic = submitTransactionOptimistically(req)
        return try await syncPendingTransaction(req, tempId: optimistic.id, optimistic: optimistic)
    }

    /// **乐观写入**账目（同步完成，UI 立即可见）
    @discardableResult
    public func submitTransactionOptimistically(_ req: CreateTransactionRequest) -> Transaction {
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
        current.transactions = Self.sortedTransactions(current.transactions, inserting: optimistic)
        // 关键：只有当这笔账目**落在汇总所属的月份**时才调整汇总。
        // `transactionSummary` 恒为「当前自然月」的汇总，
        // 而用户完全可以补记上个月的账（occurredAt 是别的月份）——
        // 原先无条件 `totalExpense += amount`，
        // 于是补记一笔往月的账会立刻把**本月**支出加上去，直到下次同步才被覆盖。
        if Self.isInSummaryMonth(req.occurredAt, summary: current.transactionSummary) {
            Self.applySummaryDelta(&current.transactionSummary, category: req.category, type: req.type, amount: req.amount)
        }
        saveSnapshot(current)
        return optimistic
    }

    /// 账目是否落在汇总所属的年月
    nonisolated static func isInSummaryMonth(_ occurredAt: String, summary: TransactionSummary) -> Bool {
        guard let date = FormatUtils.parseFlexDate(occurredAt) else { return false }
        let (y, m) = FormatUtils.beijingCurrentYearMonth()
        let parts = FormatUtils.formatBeijingDate(date)
        return parts.year == String(y) && parts.month == String(format: "%02d", m)
    }

    /// 统一调整月度汇总（正数=增加，负数=扣减）
    ///
    /// 关键：所有会改变汇总的地方都必须走这里，
    /// 否则「乐观写入加了、删除时忘了减」就会让汇总长期失真。
    nonisolated static func applySummaryDelta(
        _ summary: inout TransactionSummary,
        category: String,
        type: String,
        amount: Int64
    ) {
        if type == "expense" {
            summary.totalExpense += amount
            if let existing = summary.categoryBreakdown[category] {
                summary.categoryBreakdown[category] = existing + amount
            } else if amount > 0 {
                summary.categoryBreakdown[category] = amount
            }
        } else {
            summary.totalIncome += amount
        }
        summary.balance = summary.totalIncome - summary.totalExpense
    }

    /// 后台同步一条已乐观写入的账目
    private func syncPendingTransaction(
        _ req: CreateTransactionRequest,
        tempId: Int,
        optimistic: Transaction
    ) async throws -> (transaction: Transaction, queuedOffline: Bool) {
        guard isOnline else {
            appendOutbox(.createTransaction, localTempId: tempId, transactionRequest: req)
            return (optimistic, true)
        }
        do {
            let created = try await APIClient.shared.createTransaction(req)
            var latest = snapshot
            latest.transactions.removeAll { $0.id == tempId }
            latest.transactions = Self.sortedTransactions(latest.transactions + [created])
            saveSnapshot(latest)
            return (created, false)
        } catch let apiErr as APIError {
            switch apiErr {
            case .unauthorized:
                markTransactionFailed(tempId: tempId, reason: apiErr.localizedDescription)
                throw apiErr
            case .serverError(let code, _) where (400..<500).contains(code):
                // 同上：所有 4xx 都是永久错误
                markTransactionFailed(tempId: tempId, reason: apiErr.localizedDescription)
                throw apiErr
            default:
                appendOutbox(.createTransaction, localTempId: tempId, transactionRequest: req)
                return (optimistic, true)
            }
        } catch {
            appendOutbox(.createTransaction, localTempId: tempId, transactionRequest: req)
            return (optimistic, true)
        }
    }

    /// **非阻塞提交**账目：立刻乐观写入并返回，后台静默同步。
    ///
    /// 关键：必须把结果**如实回传**给调用方。
    /// 早先这里是 `try? await` 一把梭 —— 离线暂存、永久失败全部被吞掉，
    /// 调用方的 `queuedOffline` 恒为 false，于是「已记入账本」的提示
    /// 在离线时也照弹，用户根本不知道这条账只是躺在发件箱里。
    @discardableResult
    public func submitTransactionInBackground(
        _ req: CreateTransactionRequest,
        completion: (@MainActor (Result<Bool, Error>) -> Void)? = nil
    ) -> Transaction {
        let optimistic = submitTransactionOptimistically(req)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let outcome = try await self.syncPendingTransaction(req, tempId: optimistic.id, optimistic: optimistic)
                completion?(.success(outcome.queuedOffline))
            } catch {
                completion?(.failure(error))
            }
        }
        return optimistic
    }

    /// 把一条失败的散页改回「待同步」（用户点击重试时）
    public func markEntryRetrying(id: Int) {
        var latest = snapshot
        var touched = false
        for index in latest.entries.indices where latest.entries[index].id == id {
            latest.entries[index].syncStatus = "pending_create"
            touched = true
        }
        guard touched else { return }
        saveSnapshot(latest)
    }

    /// 把一条失败的账目改回「待同步」
    public func markTransactionRetrying(id: Int) {
        var latest = snapshot
        var touched = false
        for index in latest.transactions.indices where latest.transactions[index].id == id {
            latest.transactions[index].syncStatus = "pending_create"
            touched = true
        }
        guard touched else { return }
        saveSnapshot(latest)
    }

    /// 把一条乐观账目标记为同步失败（保留在账本，等待用户重试）
    private func markTransactionFailed(tempId: Int, reason: String) {
        var latest = snapshot
        var touched = false
        for index in latest.transactions.indices where latest.transactions[index].id == tempId {
            // 关键：服务端返回永久错误（4xx）时，这笔账**根本没进服务端** ——
            // 汇总里的金额必须回滚，否则本地会一直显示一笔不存在的支出。
            let tx = latest.transactions[index]
            if Self.isInSummaryMonth(tx.occurredAt, summary: latest.transactionSummary) {
                Self.applySummaryDelta(
                    &latest.transactionSummary,
                    category: tx.category,
                    type: tx.type,
                    amount: -tx.amount
                )
            }
            latest.transactions[index].syncStatus = "failed"
            touched = true
        }
        guard touched else { return }
        saveSnapshot(latest)
        Self.logger.error("Transaction \(tempId) marked as failed: \(reason, privacy: .public)")
    }

    /// 用户主动同步（⌘R）时，把已暂停的死信重新放回队列。
    /// 自动同步不会调用，避免对永久 4xx 错误反复重试。
    public func resetPausedOutboxItems() {
        var latest = snapshot
        var changed = false
        for index in latest.outbox.indices where latest.outbox[index].retryCount >= Self.maxOutboxRetryCount {
            latest.outbox[index].retryCount = 0
            latest.outbox[index].lastError = nil
            changed = true
        }
        if changed {
            Self.logger.info("Re-queued paused outbox items for manual retry")
            saveSnapshot(latest)
        }
    }

    /// 排空并同步本地 Outbox 待发送队列
    public func flushOutbox() async {
        guard !isFlushingOutbox, !snapshot.outbox.isEmpty else { return }
        isFlushingOutbox = true
        defer {
            isFlushingOutbox = false
            // 关键：必须把「排空结束」这件事**通知到 UI**。
            // AppState 的 `isFlushingOutbox` 是在 `onSnapshotUpdated` 回调里镜像的，
            // 而排空结束时往往不会再有 `saveSnapshot` —— 于是 UI 拿到的永远是
            // 循环中那个 true，侧栏就**永久**卡在「同步中…」，
            // 直到下一次任意快照写入才恢复。
            onSnapshotUpdated?(snapshot)
        }

        Self.logger.info("Flushing outbox: \(self.snapshot.outbox.count) item(s) queued")

        let itemsToFlush = snapshot.outbox.filter { $0.retryCount < Self.maxOutboxRetryCount }

        for item in itemsToFlush {
            if Task.isCancelled { break }
            // 确保该项目尚未被外部清除
            guard self.snapshot.outbox.contains(where: { $0.id == item.id }) else { continue }
            do {
                switch item.kind {
                case .createEntry:
                    if let req = item.entryRequest {
                        let created = try await APIClient.shared.createEntry(req)
                        var latest = self.snapshot
                        latest.entries.removeAll { $0.id == item.localTempId }
                        // 同步成功的记录按发生时间归位，而非插到列表顶部
                        latest.entries = Self.sortedEntries(latest.entries + [created])
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
                        latest.transactions = Self.sortedTransactions(latest.transactions + [created])
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
            } catch let apiErr as APIError {
                self.handleOutboxFailure(item: item, error: apiErr)
            } catch {
                self.handleOutboxFailure(item: item, error: APIError.networkFailure(error.localizedDescription))
            }
        }
        let remaining = self.snapshot.outbox.count
        Self.logger.info("Outbox flush finished, \(remaining) item(s) still pending")

        // 同步完成后给一条系统通知（用户切到别的 App 时也能知道结果）
        if AppState.shared.notifiesOnSync {
            if remaining == 0, !itemsToFlush.isEmpty {
                AppDelegate.postNotification(
                    title: "活页集 · 同步完成",
                    body: "本地发件箱的 \(itemsToFlush.count) 条记录已同步至中枢。"
                )
            } else if remaining > 0 {
                AppDelegate.postNotification(
                    title: "活页集 · 仍有待同步记录",
                    body: "有 \(remaining) 条本地记录暂未同步成功，将自动重试。"
                )
            }
        }
    }

    /// 发件箱失败分类处理：
    /// - 401 未授权：暂停自动重试但**保留**记录，重新配对后可手动重试
    /// - 4xx 客户端错误：暂停自动重试但**保留**记录，避免静默丢数据
    /// - 其余（网络 / 5xx）：有限次重试，超过上限后暂停并保留，等待用户手动重试
    private func handleOutboxFailure(item: OutboxItem, error: APIError) {
        var latest = snapshot
        guard let idx = latest.outbox.firstIndex(where: { $0.id == item.id }) else { return }

        switch error {
        case .unauthorized:
            latest.outbox[idx].retryCount = Self.maxOutboxRetryCount
            latest.outbox[idx].lastError = error.localizedDescription
            Self.logger.error("Outbox item \(item.id.uuidString) paused: device unauthorized")
            onLocalDataWarning?("设备授权已失效，\(latest.outbox.count) 条本地记录已暂停同步；重新配对后点「同步」重试")
        case .serverError(let code, _) where (400..<500).contains(code):
            latest.outbox[idx].retryCount = Self.maxOutboxRetryCount
            latest.outbox[idx].lastError = error.localizedDescription
            Self.logger.error("Outbox item \(item.id.uuidString) paused: client error \(code)")
            onLocalDataWarning?("有条本地记录因参数错误无法同步，已暂停自动重试；内容仍保留在本机")
        default:
            let nextRetry = latest.outbox[idx].retryCount + 1
            if nextRetry >= Self.maxOutboxRetryCount {
                // 不再删除：死信保留在 outbox 中，用户仍能看到待同步计数，
                // 后续版本可提供「查看/重试/导出」入口。静默 removeAll 等于数据丢失。
                latest.outbox[idx].retryCount = Self.maxOutboxRetryCount
                latest.outbox[idx].lastError = error.localizedDescription
                Self.logger.error("Outbox item \(item.id.uuidString) paused after \(Self.maxOutboxRetryCount) attempts")
                onLocalDataWarning?("有条本地记录多次同步失败，已暂停自动重试；内容仍保留在本机，请检查网络或中枢状态")
            } else {
                latest.outbox[idx].retryCount = nextRetry
                latest.outbox[idx].lastError = error.localizedDescription
            }
        }
        saveSnapshot(latest)
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

    /// **只增不删**地合并一批远端散页（用于「首屏优先」投递）
    ///
    /// 关键：首屏回调**不能**用全量语义。
    /// `mergeEntries(_:isDelta: false)` 是「本地档案整体替换为远端列表」，
    /// 而首屏只带了**第 1 页（100 条）** —— 于是本地 5000 条会被瞬间截断成 100 条，
    /// 而且这个截断态还会被写进磁盘快照。
    /// 更糟的是游标也被推进到首屏的最大时间戳：后续增量同步只会拉
    /// 「比首屏更新的」，旧条目**永远回不来** —— 本地数据就此永久丢失。
    ///
    /// 所以首屏只做「只增不删」的合并，**且不推进游标**；
    /// 游标要等全部分页拉完、由 `mergeEntries(_:isDelta:)` 统一推进。
    public func mergeEntriesIncremental(_ incoming: [LifeEntry]) {
        var current = snapshot
        var map = Dictionary(current.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for entry in incoming {
            if let deleted = entry.deletedAt, !deleted.isEmpty {
                map.removeValue(forKey: entry.id)
            } else {
                var syncedEntry = entry
                syncedEntry.syncStatus = "synced"
                map[entry.id] = syncedEntry
            }
        }
        current.entries = Self.sortedEntries(Array(map.values))
        // 刻意**不**推进 lastEntriesSyncCursor（理由见上）
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
    /// - Parameter inserting: 需要一并插入的乐观记录（避免调用方先 `+ [extra]` 多复制一份数组）。
    nonisolated static func sortedEntries(_ entries: [LifeEntry], inserting extra: LifeEntry? = nil) -> [LifeEntry] {
        ArchivePerformance.metric(.sync, "sortEntryCount", entries.count)
        return ArchivePerformance.measure(.sync, "sortEntries") {
            var itemsWithDate: [(entry: LifeEntry, date: Date)] = entries.map {
                ($0, FormatUtils.parseFlexDate($0.occurredAt) ?? .distantPast)
            }
            if let extra {
                itemsWithDate.append((extra, FormatUtils.parseFlexDate(extra.occurredAt) ?? .distantPast))
            }
            itemsWithDate.sort {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.entry.id > $1.entry.id
            }
            return itemsWithDate.map(\.entry)
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
    nonisolated static func sortedTransactions(_ transactions: [Transaction], inserting extra: Transaction? = nil) -> [Transaction] {
        var itemsWithDate: [(tx: Transaction, date: Date)] = transactions.map {
            ($0, FormatUtils.parseFlexDate($0.occurredAt) ?? .distantPast)
        }
        if let extra {
            itemsWithDate.append((extra, FormatUtils.parseFlexDate(extra.occurredAt) ?? .distantPast))
        }
        itemsWithDate.sort {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.tx.id > $1.tx.id
        }
        return itemsWithDate.map(\.tx)
    }
}

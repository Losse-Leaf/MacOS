import Foundation
import Network
import os

/// 可同步记录协议（统一 `LifeEntry` 与 `Transaction` 的注水择优、全量/增量对账与时间流排序）
protocol SyncableRecord: Identifiable, Sendable where ID == Int {
    var occurredAt: String { get }
    var updatedAt: String? { get }
    var deletedAt: String? { get }
    var syncStatus: String? { get set }
}

extension LifeEntry: SyncableRecord {}
extension Transaction: SyncableRecord {}

/// 本地优先存储与离线发件箱同步调度引擎 (Local-First & Sync Outbox Engine)
/// 严格遵循 docs/macos.md §4 与 docs/ecosystem.md §7 规范
/// 注：OutboxItem / LocalArchiveSnapshot 已移至 Models/SnapshotModel.swift
@MainActor
public final class SyncManager {
    public static let shared = SyncManager()

    nonisolated private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "sync")

    /// 发件箱单条最大重试次数，超过即判定为死信并暂停自动重试（保留数据不静默丢弃）
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
    /// 发件箱排空结束后的回调（传入本次尝试发送的待发条数，与 `AppState` / `AppDelegate` 解耦）
    public var onOutboxFlushCompleted: (@MainActor @Sendable (Int) -> Void)?

    private var snapshot: LocalArchiveSnapshot
    private var pendingWrite: DispatchWorkItem?
    /// 关键写入（离线新记录/删除）的立即落盘任务（与防抖任务分槽管理）
    private var pendingCriticalWrite: DispatchWorkItem?
    /// 单调递增的快照版本号：只有更高版本的快照才允许落盘，杜绝「旧数据覆盖新数据」
    private var snapshotRevision: UInt64 = 0
    /// 磁盘快照是否已在主线程注水完成（注水前禁止落盘，防止启动期空壳覆盖磁盘档案）
    private var hasHydrated = false
    /// 是否已收到过服务端权威月度汇总
    private var hasAuthoritativeSummary = false
    /// 轻量指纹缓存（按 snapshotRevision 对应）
    private var cachedFingerprintRevision: UInt64 = 0
    private var cachedFingerprint: SnapshotFingerprint?
    /// 批量更新模式：批次结束时统一回调一次 UI
    private var isBatching: Bool = false
    private var pendingBatchSnapshot: LocalArchiveSnapshot?
    /// 已落盘的最大版本号（跨线程访问，仅由 diskWriteQueue 读写）
    nonisolated(unsafe) private static var lastWrittenRevision: UInt64 = 0
    /// 最近一次网络状态（用于去重，避免同状态反复触发排空队列）
    private var lastKnownOnline: Bool?

    private init() {
        self.snapshot = LocalArchiveSnapshot()
        startNetworkMonitor()
        hydrateFromDiskInBackground()
        NotificationCenter.default.addObserver(
            forName: .looseLeafHubDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                SyncManager.shared.discardOutboxAndPending()
            }
        }
    }

    /// 换中枢 / 解除配对时丢弃一切属于旧中枢的待同步状态。
    public func discardOutboxAndPending() {
        var latest = snapshot
        let pendingIDs = Set(latest.outbox.map { $0.localTempId })
        let removedTx = latest.transactions.filter { pendingIDs.contains($0.id) || $0.id < 0 }
        latest.outbox.removeAll()
        latest.entries.removeAll { pendingIDs.contains($0.id) || $0.id < 0 }
        latest.transactions.removeAll { pendingIDs.contains($0.id) || $0.id < 0 }
        for tx in removedTx {
            Self.rollbackSummaryIfNeeded(for: tx, in: &latest.transactionSummary)
        }
        latest.lastEntriesSyncCursor = nil
        latest.lastTransactionsSyncCursor = nil
        saveSnapshot(latest)
    }

    /// 彻底清除本地持久化档案快照、发件箱与草稿文件（用于解除设备配对与 401 远端吊销零残留擦除）
    public func purgeAllLocalData() {
        pendingWrite?.cancel()
        pendingWrite = nil
        pendingCriticalWrite?.cancel()
        pendingCriticalWrite = nil
        snapshotRevision += 1
        snapshot = LocalArchiveSnapshot()
        hasAuthoritativeSummary = false
        cachedFingerprint = nil
        cachedFingerprintRevision = snapshotRevision
        if isBatching {
            pendingBatchSnapshot = snapshot
        } else {
            onSnapshotUpdated?(snapshot)
        }
        UserDefaults.standard.removeObject(forKey: "looseleaf_entry_draft_v1")
        let snapURL = Self.snapshotFileURL
        let draftURL = Self.sharedStorageDirectory.appendingPathComponent("entry_draft_v1.json")
        let previewDir = Self.sharedStorageDirectory.appendingPathComponent("PreviewStaging", isDirectory: true)
        let dropDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("LooseLeafDarkroomDrop", isDirectory: true)
        try? FileManager.default.removeItem(at: snapURL)
        try? FileManager.default.removeItem(at: draftURL)
        diskWriteQueue.async {
            try? FileManager.default.removeItem(at: snapURL)
            try? FileManager.default.removeItem(at: draftURL)
            try? FileManager.default.removeItem(at: previewDir)
            try? FileManager.default.removeItem(at: dropDir)
        }
    }

    /// 重置增量同步游标，触发后续请求退化为安全的全量同步自愈。
    public func resetSyncCursors() {
        var latest = snapshot
        latest.lastEntriesSyncCursor = nil
        latest.lastTransactionsSyncCursor = nil
        saveSnapshot(latest)
    }

    /// 升级后首次注水完成时清空一次账目游标，强制下一次账目同步走全量补齐。
    public func resetLedgerCursorForPaginationFixIfNeeded(defaults: UserDefaults = .standard) {
        guard Self.consumeLedgerPaginationFixReset(defaults: defaults) else { return }
        guard !(snapshot.lastTransactionsSyncCursor ?? "").isEmpty else { return }
        var latest = snapshot
        latest.lastTransactionsSyncCursor = nil
        saveSnapshot(latest, critical: true)
    }

    nonisolated static func consumeLedgerPaginationFixReset(defaults: UserDefaults = .standard) -> Bool {
        let key = "looseleaf.sync.ledgerPaginationFixCursorReset.v1"
        guard !defaults.bool(forKey: key) else { return false }
        defaults.set(true, forKey: key)
        return true
    }

    // MARK: - 本地临时 ID 生成

    private nonisolated(unsafe) static var tempIdSequence: Int = 0
    private nonisolated static let tempIdLock = NSLock()

    /// 生成离线乐观记录的本地临时 ID（负值，与服务器正 ID 区分）。
    nonisolated static func makeLocalTempId() -> Int {
        tempIdLock.lock()
        let seq = tempIdSequence % 1000
        tempIdSequence += 1
        tempIdLock.unlock()
        return -(Int(Date().timeIntervalSince1970 * 1000) * 1000 + seq)
    }

    // MARK: - 本地磁盘缓存路径

    nonisolated public static let sharedStorageDirectory: URL = {
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
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDir = dir
        try? mutableDir.setResourceValues(resourceValues)
        return dir
    }()

    nonisolated(unsafe) private static var _snapshotFileURLOverride: URL?

    public nonisolated static var snapshotFileURLOverride: URL? {
        get { _snapshotFileURLOverride }
        set { _snapshotFileURLOverride = newValue }
    }

    public nonisolated static var snapshotFileURL: URL {
        snapshotFileURLOverride
            ?? sharedStorageDirectory.appendingPathComponent("archive_snapshot_v1.json")
    }

    /// 最近一次本地快照加载失败的原因（供启动期提示，nil 表示加载正常或文件不存在）
    public private(set) var lastLoadFailureMessage: String?

    /// 磁盘读取 + JSON 解码，返回快照与失败原因（解码失败或未来 schema 版本一律先隔离备份）。
    nonisolated static func loadSnapshotFromDisk(at url: URL) -> (snapshot: LocalArchiveSnapshot?, failureMessage: String?) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return (nil, nil)
        }
        do {
            let decoded = try JSONDecoder().decode(LocalArchiveSnapshot.self, from: data)
            guard let migrated = decoded.migrated() else {
                let stamp = ISO8601DateFormatter().string(from: Date())
                    .replacingOccurrences(of: ":", with: "-")
                let backupURL = url.deletingLastPathComponent()
                    .appendingPathComponent("archive_snapshot_v_newer.corrupt-\(stamp).json")
                let moved = (try? FileManager.default.moveItem(at: url, to: backupURL)) != nil
                let message = moved
                    ? "本地快照来自更新版本的应用（v\(decoded.schemaVersion) > 当前 v\(LocalArchiveSnapshot.currentSchemaVersion)），已隔离备份为 \(backupURL.lastPathComponent)，本次以空档案启动。请升级到最新版以恢复完整档案。"
                    : "本地快照来自更新版本的应用，且备份失败，请立即手动备份 \(url.path) 后再启动。"
                Self.logger.error("Snapshot from a newer schema version (\(decoded.schemaVersion)); backup moved: \(moved)")
                return (nil, message)
            }
            return (migrated, nil)
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
                    self.hasHydrated = true
                    self.lastLoadFailureMessage = message
                    self.onLocalDataWarning?(message)
                    self.resetLedgerCursorForPaginationFixIfNeeded()
                    return
                }
                guard let loaded = result.snapshot else {
                    self.hasHydrated = true
                    if self.snapshotRevision > 0 {
                        self.saveSnapshot(self.snapshot, critical: true)
                    }
                    self.resetLedgerCursorForPaginationFixIfNeeded()
                    return
                }

                if self.snapshotRevision > 0 {
                    let merged = Self.mergedHydratedSnapshot(
                        current: self.snapshot,
                        loaded: loaded,
                        hasAuthoritativeSummary: self.hasAuthoritativeSummary
                    )
                    self.hasHydrated = true
                    self.saveSnapshot(merged, critical: true)
                } else {
                    self.hasHydrated = true
                    self.snapshotRevision += 1
                    self.snapshot = loaded
                    if self.isBatching {
                        self.pendingBatchSnapshot = loaded
                    } else {
                        self.onSnapshotUpdated?(loaded)
                    }
                }
                self.resetLedgerCursorForPaginationFixIfNeeded()
            }

            await self.refreshExpiredMediaURLs()
        }
    }

    public func currentSnapshot() -> LocalArchiveSnapshot {
        snapshot
    }

    // MARK: - 媒体签名地址换签（快照里的 URL 会过期）

    private nonisolated static let r2DateFormatterLock = NSLock()
    nonisolated(unsafe) private static let r2DateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated static func isMediaURLExpired(_ urlString: String, within seconds: TimeInterval = 60) -> Bool {
        guard let components = URLComponents(string: urlString),
              let items = components.queryItems else {
            return false
        }
        let dict = Dictionary(items.map { ($0.name.lowercased(), $0.value ?? "") }, uniquingKeysWith: { first, _ in first })

        if let exp = dict["exp"], let ts = Double(exp) {
            return Date().timeIntervalSince1970 + seconds >= ts
        }
        if let iso = dict["x-amz-date"], let ttl = Double(dict["x-amz-expires"] ?? "") {
            r2DateFormatterLock.lock()
            let signedAt = r2DateFormatter.date(from: iso)
            r2DateFormatterLock.unlock()
            if let signedAt {
                return signedAt.timeIntervalSinceNow + ttl <= seconds
            }
        }
        return true
    }

    /// 把快照里已过期的媒体地址批量换签并回写
    public func refreshExpiredMediaURLs() async {
        let scan = snapshot
        var needRefresh: Set<String> = []
        func collect(_ attachments: [Attachment]) {
            for att in attachments {
                if att.objectKey.isEmpty { continue }
                if Self.isMediaURLExpired(att.url) || (att.thumbnailUrl.map { Self.isMediaURLExpired($0) } ?? false) {
                    needRefresh.insert(att.objectKey)
                }
            }
        }
        for entry in scan.entries { collect(entry.attachments) }

        guard !needRefresh.isEmpty else {
            var latest = snapshot
            if latest.mediaURLsRefreshedAt == nil {
                latest.mediaURLsRefreshedAt = FormatUtils.beijingISOString()
                saveSnapshot(latest)
            }
            return
        }

        let refreshed: [String: RefreshedMediaURLs]
        do {
            refreshed = try await APIClient.shared.refreshMediaURLs(objectKeys: Array(needRefresh))
        } catch {
            Self.logger.info("Media URL re-signing skipped: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !refreshed.isEmpty else { return }

        func patch(_ attachments: [Attachment]) -> [Attachment] {
            attachments.map { att in
                guard let new = refreshed[att.objectKey] else { return att }
                var copy = att
                if !new.url.isEmpty { copy.url = new.url }
                if let thumb = new.thumbnailUrl, !thumb.isEmpty { copy.thumbnailUrl = thumb }
                return copy
            }
        }
        var latest = snapshot
        latest.entries = latest.entries.map { e in var c = e; c.attachments = patch(e.attachments); return c }
        latest.mediaURLsRefreshedAt = FormatUtils.beijingISOString()
        saveSnapshot(latest)
    }

    /// 原子更新站点配置、主理人档案与统计
    public func updateConfigAndProfile(siteConfig: SiteConfig?, profile: CuratorProfile?, stats: GlobalStats?) {
        guard siteConfig != nil || profile != nil || stats != nil else { return }
        var latest = snapshot
        if let siteConfig { latest.siteConfig = siteConfig }
        if let profile { latest.profile = profile }
        if let stats { latest.stats = stats }
        saveSnapshot(latest)
    }

    /// 原子更新月度记账概览（重新叠加同月尚未上传的 `pending_create` 乐观账目）
    public func updateTransactionSummary(_ summary: TransactionSummary) {
        hasAuthoritativeSummary = true
        var latest = snapshot
        var adjusted = summary
        for tx in latest.transactions where (tx.syncStatus ?? "synced") == "pending_create" {
            guard Self.isInSummaryMonth(tx.occurredAt, summary: summary) else { continue }
            Self.applySummaryDelta(&adjusted, category: tx.category, type: tx.type, amount: tx.amount)
        }
        latest.transactionSummary = adjusted
        saveSnapshot(latest)
    }

    /// 单个集合的轻量指纹：条目数 + 最大 updatedAt + 顺序化状态哈希。
    public struct CollectionFingerprint: Equatable, Sendable {
        public var count: Int
        public var maxUpdatedAt: String
        public var stateHash: UInt64
    }

    public struct SnapshotFingerprint: Equatable, Sendable {
        public var entries: CollectionFingerprint
        public var transactions: CollectionFingerprint
    }

    nonisolated private static let fnvOffset: UInt64 = 14_695_981_039_346_656_037
    nonisolated private static let fnvPrime: UInt64 = 1_099_511_628_211

    @inline(__always)
    nonisolated private static func mix(_ value: UInt64, into hash: inout UInt64) {
        hash ^= value
        hash &*= fnvPrime
    }

    @inline(__always)
    nonisolated private static func mix(_ string: String, into hash: inout UInt64) {
        for byte in string.utf8 { mix(UInt64(byte), into: &hash) }
        mix(0xFF, into: &hash)
    }

    public static let fingerprintThreshold = 2_000

    nonisolated public static func entryFingerprint(_ entries: [LifeEntry]) -> CollectionFingerprint {
        var hash = fnvOffset
        var maxUpdatedAt = ""
        for entry in entries {
            mix(UInt64(bitPattern: Int64(entry.id)), into: &hash)
            mix(entry.syncStatus ?? "", into: &hash)
            mix(entry.title, into: &hash)
            mix(entry.type, into: &hash)
            mix(UInt64(entry.content.utf8.count), into: &hash)
            mix(entry.occurredAt, into: &hash)
            mix(entry.location ?? "", into: &hash)
            mix(entry.cityCode ?? "", into: &hash)
            mix(entry.cityName ?? "", into: &hash)
            mix(entry.gearId ?? "", into: &hash)
            mix(entry.deletedAt ?? "", into: &hash)
            mix(UInt64(entry.projectId ?? 0), into: &hash)
            mix(UInt64(entry.wishId ?? 0), into: &hash)
            mix(UInt64(bitPattern: Int64(entry.footprintId ?? 0)), into: &hash)
            mix(entry.isPrivate ? "1" : "0", into: &hash)
            for attachment in entry.attachments {
                mix(UInt64(attachment.id), into: &hash)
                mix(attachment.objectKey, into: &hash)
                mix(attachment.url, into: &hash)
                mix(attachment.thumbnailUrl ?? "", into: &hash)
            }
            let updated = entry.updatedAt ?? ""
            if !updated.isEmpty, updated > maxUpdatedAt { maxUpdatedAt = updated }
        }
        return CollectionFingerprint(count: entries.count, maxUpdatedAt: maxUpdatedAt, stateHash: hash)
    }

    nonisolated public static func transactionFingerprint(_ transactions: [Transaction]) -> CollectionFingerprint {
        var hash = fnvOffset
        var maxUpdatedAt = ""
        for tx in transactions {
            mix(UInt64(bitPattern: Int64(tx.id)), into: &hash)
            mix(tx.syncStatus ?? "", into: &hash)
            mix(tx.category, into: &hash)
            mix(tx.type, into: &hash)
            mix(UInt64(bitPattern: tx.amount), into: &hash)
            mix(tx.occurredAt, into: &hash)
            mix(tx.title, into: &hash)
            mix(tx.note ?? "", into: &hash)
            mix(tx.cityCode ?? "", into: &hash)
            mix(tx.paymentMethod ?? "", into: &hash)
            mix(tx.isInstallment == true ? "1" : "0", into: &hash)
            mix(tx.installmentChannelCode ?? "", into: &hash)
            mix(UInt64(bitPattern: tx.installmentTotalAmount ?? 0), into: &hash)
            mix(UInt64(tx.installmentMonths ?? 0), into: &hash)
            mix(UInt64(bitPattern: tx.installmentMonthlyPay ?? 0), into: &hash)
            mix(UInt64(tx.installmentRemainMonths ?? 0), into: &hash)
            mix(UInt64(tx.repaymentDay ?? 0), into: &hash)
            mix(UInt64(bitPattern: Int64(tx.wishId ?? 0)), into: &hash)
            mix(UInt64(bitPattern: Int64(tx.footprintId ?? 0)), into: &hash)
            mix(tx.deletedAt ?? "", into: &hash)
            let updated = tx.updatedAt ?? ""
            if !updated.isEmpty, updated > maxUpdatedAt { maxUpdatedAt = updated }
        }
        return CollectionFingerprint(count: transactions.count, maxUpdatedAt: maxUpdatedAt, stateHash: hash)
    }

    nonisolated public static func fingerprint(of snapshot: LocalArchiveSnapshot) -> SnapshotFingerprint {
        SnapshotFingerprint(
            entries: entryFingerprint(snapshot.entries),
            transactions: transactionFingerprint(snapshot.transactions)
        )
    }

    public func fingerprint(for snapshot: LocalArchiveSnapshot) -> SnapshotFingerprint {
        if cachedFingerprintRevision == snapshotRevision, let cachedFingerprint {
            return cachedFingerprint
        }
        return Self.fingerprint(of: snapshot)
    }

    /// 保存一份新快照
    public func saveSnapshot(_ updated: LocalArchiveSnapshot, critical: Bool = false) {
        var copy = updated
        copy.updatedAt = FormatUtils.beijingISOString()
        copy.schemaVersion = LocalArchiveSnapshot.currentSchemaVersion
        snapshotRevision += 1
        self.snapshot = copy
        if isBatching {
            pendingBatchSnapshot = copy
        } else {
            onSnapshotUpdated?(copy)
        }

        guard hasHydrated else { return }

        let needsFingerprint = copy.entries.count >= Self.fingerprintThreshold
            || copy.transactions.count >= Self.fingerprintThreshold
        if needsFingerprint {
            let fingerprintRevision = snapshotRevision
            let fingerprintSnapshot = copy
            diskWriteQueue.async { [weak self] in
                let fingerprint = Self.fingerprint(of: fingerprintSnapshot)
                Task { @MainActor in
                    guard let self, self.snapshotRevision == fingerprintRevision else { return }
                    self.cachedFingerprint = fingerprint
                    self.cachedFingerprintRevision = fingerprintRevision
                }
            }
        } else {
            cachedFingerprint = nil
            cachedFingerprintRevision = snapshotRevision
        }
        scheduleDiskWrite(copy, revision: snapshotRevision, critical: critical)
    }

    public func beginBatch() {
        isBatching = true
        pendingBatchSnapshot = nil
    }

    public func endBatch() {
        isBatching = false
        guard let snapshot = pendingBatchSnapshot else { return }
        pendingBatchSnapshot = nil
        onSnapshotUpdated?(snapshot)
    }

    public func flushBatchSnapshotNow() {
        guard isBatching, let snapshot = pendingBatchSnapshot else { return }
        pendingBatchSnapshot = nil
        onSnapshotUpdated?(snapshot)
    }

    private func scheduleDiskWrite(_ copy: LocalArchiveSnapshot, revision: UInt64, critical: Bool = false) {
        let fileURL = Self.snapshotFileURL
        if critical {
            pendingCriticalWrite?.cancel()
            let criticalItem = DispatchWorkItem {
                Self.writeSnapshot(copy, to: fileURL, revision: revision)
            }
            pendingCriticalWrite = criticalItem
            diskWriteQueue.async(execute: criticalItem)
            return
        }
        pendingWrite?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Self.writeSnapshot(copy, to: fileURL, revision: revision)
            _ = self
        }
        pendingWrite = item
        diskWriteQueue.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

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

    public func flushSnapshotToDiskIfNeededAsync() async {
        guard hasHydrated else { return }
        pendingWrite?.cancel()
        pendingWrite = nil
        pendingCriticalWrite?.cancel()
        pendingCriticalWrite = nil
        let copy = snapshot
        let revision = snapshotRevision
        let fileURL = Self.snapshotFileURL
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            diskWriteQueue.async {
                Self.writeSnapshot(copy, to: fileURL, revision: revision)
                continuation.resume()
            }
        }
    }

    public func flushSnapshotToDiskIfNeeded() {
        guard hasHydrated else { return }
        pendingWrite?.cancel()
        pendingWrite = nil
        pendingCriticalWrite?.cancel()
        pendingCriticalWrite = nil
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
                if let last = self.lastKnownOnline, last == online { return }
                self.lastKnownOnline = online
                let wasOffline = !(self.isOnline)
                self.isOnline = online
                Self.logger.info("Network status: \(online ? "online" : "offline", privacy: .public)")
                self.onNetworkStatusChanged?(online)
                if online && (wasOffline || !self.snapshot.outbox.isEmpty) {
                    await self.flushOutbox()
                }
                if online {
                    await self.refreshExpiredMediaURLs()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - 写入流：在线直发 + 断网自动转入 Outbox 队列

    private func stableEntryRequest(_ req: CreateEntryRequest) -> CreateEntryRequest {
        var copy = req
        if copy.clientRequestId?.isEmpty != false {
            copy.clientRequestId = UUID().uuidString
        }
        return copy
    }

    private func stableTransactionRequest(_ req: CreateTransactionRequest) -> CreateTransactionRequest {
        var copy = req
        if copy.clientRequestId?.isEmpty != false {
            copy.clientRequestId = UUID().uuidString
        }
        return copy
    }

    public func submitEntry(_ req: CreateEntryRequest, attachments: [Attachment] = []) async throws -> (entry: LifeEntry, queuedOffline: Bool) {
        let stableReq = stableEntryRequest(req)
        let optimistic = submitEntryOptimistically(stableReq, attachments: attachments)
        return try await syncPendingEntry(stableReq, tempId: optimistic.id, optimistic: optimistic)
    }

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
            isPrivate: req.isPrivate ?? false,
            attachments: attachments,
            syncStatus: "pending_create"
        )
        var current = snapshot
        current.entries = Self.sortedEntries(current.entries, inserting: optimistic)
        saveSnapshot(current)
        return optimistic
    }

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
            var latest = snapshot
            latest.entries.removeAll { $0.id == tempId || $0.id == created.id }
            latest.outbox.removeAll { $0.kind == .createEntry && $0.localTempId == tempId }
            latest.entries = Self.sortedEntries(latest.entries, inserting: created)
            saveSnapshot(latest)
            return (created, false)
        } catch let apiErr as APIError {
            switch apiErr {
            case .unauthorized:
                markEntryFailed(tempId: tempId, reason: apiErr.localizedDescription)
                throw apiErr
            case .serverError(410, _):
                discardGoneEntry(tempId: tempId)
                throw apiErr
            case .serverError(let code, _) where (400..<500).contains(code):
                markEntryFailed(tempId: tempId, reason: apiErr.localizedDescription)
                throw apiErr
            default:
                appendOutbox(.createEntry, localTempId: tempId, entryRequest: req)
                return (optimistic, true)
            }
        } catch {
            appendOutbox(.createEntry, localTempId: tempId, entryRequest: req)
            return (optimistic, true)
        }
    }

    /// 追加一条待同步动作到 Outbox（复用 `stableEntryRequest` / `stableTransactionRequest` 幂等键签名）
    private func appendOutbox(
        _ kind: OutboxActionKind,
        localTempId: Int,
        entryRequest: CreateEntryRequest? = nil,
        transactionRequest: CreateTransactionRequest? = nil,
        targetServerId: Int? = nil
    ) {
        var latest = snapshot
        latest.outbox.removeAll { $0.kind == kind && $0.localTempId == localTempId }
        let stampedEntryRequest = (kind == .createEntry) ? entryRequest.map(stableEntryRequest) : entryRequest
        let stampedTransactionRequest = (kind == .createTransaction) ? transactionRequest.map(stableTransactionRequest) : transactionRequest
        latest.outbox.append(OutboxItem(
            kind: kind,
            localTempId: localTempId,
            targetServerId: targetServerId,
            entryRequest: stampedEntryRequest,
            transactionRequest: stampedTransactionRequest
        ))
        saveSnapshot(latest, critical: true)
    }

    /// 把一次「删除」排入发件箱（离线时网络恢复后自动补删）
    public func enqueueDelete(kind: OutboxActionKind, localTempId: Int, targetServerId: Int) {
        var latest = snapshot
        switch kind {
        case .deleteEntry:
            latest.entries.removeAll { $0.id == targetServerId }
        case .deleteTransaction:
            if let removed = latest.transactions.first(where: { $0.id == targetServerId }) {
                Self.rollbackSummaryIfNeeded(for: removed, in: &latest.transactionSummary)
            }
            latest.transactions.removeAll { $0.id == targetServerId }
        default:
            break
        }
        snapshot = latest
        appendOutbox(kind, localTempId: localTempId, targetServerId: targetServerId)
    }

    public func removeOptimisticEntry(localTempId: Int) {
        var latest = snapshot
        latest.entries.removeAll { $0.id == localTempId }
        latest.outbox.removeAll { $0.localTempId == localTempId }
        saveSnapshot(latest)
    }

    public func removeOptimisticTransaction(localTempId: Int) {
        var latest = snapshot
        if let removed = latest.transactions.first(where: { $0.id == localTempId }) {
            Self.rollbackSummaryIfNeeded(for: removed, in: &latest.transactionSummary)
        }
        latest.transactions.removeAll { $0.id == localTempId }
        latest.outbox.removeAll { $0.localTempId == localTempId }
        saveSnapshot(latest)
    }

    public func resyncEntry(id: Int, req: CreateEntryRequest, attachments: [Attachment]) {
        guard let existing = snapshot.entries.first(where: { $0.id == id }) else { return }
        var stableReq = req
        if stableReq.clientRequestId?.isEmpty != false {
            stableReq.clientRequestId = snapshot.outbox
                .first(where: { $0.kind == .createEntry && $0.localTempId == id })?
                .entryRequest?.clientRequestId
        }
        stableReq = stableEntryRequest(stableReq)
        markEntryRetrying(id: id)
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.syncPendingEntry(stableReq, tempId: id, optimistic: existing)
        }
    }

    public func resyncTransaction(id: Int, req: CreateTransactionRequest) {
        guard let existing = snapshot.transactions.first(where: { $0.id == id }) else { return }
        var stableReq = req
        if stableReq.clientRequestId?.isEmpty != false {
            stableReq.clientRequestId = snapshot.outbox
                .first(where: { $0.kind == .createTransaction && $0.localTempId == id })?
                .transactionRequest?.clientRequestId
        }
        stableReq = stableTransactionRequest(stableReq)
        markTransactionRetrying(id: id)
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.syncPendingTransaction(stableReq, tempId: id, optimistic: existing)
        }
    }

    private func markEntryFailed(tempId: Int, reason: String) {
        var latest = snapshot
        var touched = false
        for index in latest.entries.indices where latest.entries[index].id == tempId {
            latest.entries[index].syncStatus = "failed"
            touched = true
        }
        let hadOutboxItem = latest.outbox.contains { $0.kind == .createEntry && $0.localTempId == tempId }
        latest.outbox.removeAll { $0.kind == .createEntry && $0.localTempId == tempId }
        guard touched || hadOutboxItem else { return }
        saveSnapshot(latest)
        Self.logger.error("Entry \(tempId) marked as failed: \(reason, privacy: .public)")
    }

    func discardGoneEntry(tempId: Int) {
        var latest = snapshot
        latest.entries.removeAll { $0.id == tempId }
        latest.outbox.removeAll { $0.localTempId == tempId }
        saveSnapshot(latest)
        Self.logger.info("Entry \(tempId) discarded: server reports 410 Gone")
    }

    public func submitTransaction(_ req: CreateTransactionRequest) async throws -> (transaction: Transaction, queuedOffline: Bool) {
        let stableReq = stableTransactionRequest(req)
        let optimistic = submitTransactionOptimistically(stableReq)
        return try await syncPendingTransaction(stableReq, tempId: optimistic.id, optimistic: optimistic)
    }

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
            isInstallment: req.isInstallment,
            installmentChannelCode: req.installmentChannelCode,
            installmentTotalAmount: req.installmentTotalAmount,
            installmentMonths: req.installmentMonths,
            installmentMonthlyPay: req.installmentMonthlyPay,
            installmentRemainMonths: req.installmentRemainMonths,
            repaymentDay: req.repaymentDay,
            syncStatus: "pending_create"
        )

        var current = snapshot
        current.transactions = Self.sortedRecords(current.transactions, inserting: optimistic)
        if Self.isInSummaryMonth(req.occurredAt, summary: current.transactionSummary) {
            Self.applySummaryDelta(&current.transactionSummary, category: req.category, type: req.type, amount: req.amount)
        }
        saveSnapshot(current)
        return optimistic
    }

    /// 账目是否落在汇总所属的年月
    nonisolated static func isInSummaryMonth(_ occurredAt: String, summary: TransactionSummary) -> Bool {
        guard let date = FormatUtils.parseFlexDate(occurredAt) else { return false }
        let parts = FormatUtils.formatBeijingDate(date)
        return parts.year == String(summary.year) && parts.month == String(format: "%02d", summary.month)
    }

    /// 统一调整月度汇总（正数=增加，负数=扣减）
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

    /// 当被移除/失败的账目落在汇总所属年月时，统一回滚乐观月度汇总
    nonisolated static func rollbackSummaryIfNeeded(
        for tx: Transaction,
        in summary: inout TransactionSummary
    ) {
        guard isInSummaryMonth(tx.occurredAt, summary: summary) else { return }
        applySummaryDelta(&summary, category: tx.category, type: tx.type, amount: -tx.amount)
    }

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
            latest.transactions.removeAll { $0.id == tempId || $0.id == created.id }
            latest.outbox.removeAll { $0.kind == .createTransaction && $0.localTempId == tempId }
            latest.transactions = Self.sortedRecords(latest.transactions, inserting: created)
            saveSnapshot(latest)
            return (created, false)
        } catch let apiErr as APIError {
            switch apiErr {
            case .unauthorized:
                markTransactionFailed(tempId: tempId, reason: apiErr.localizedDescription)
                throw apiErr
            case .serverError(410, _):
                discardGoneTransaction(tempId: tempId)
                throw apiErr
            case .serverError(let code, _) where (400..<500).contains(code):
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

    private func markTransactionFailed(tempId: Int, reason: String) {
        var latest = snapshot
        var touched = false
        for index in latest.transactions.indices where latest.transactions[index].id == tempId {
            Self.rollbackSummaryIfNeeded(for: latest.transactions[index], in: &latest.transactionSummary)
            latest.transactions[index].syncStatus = "failed"
            touched = true
        }
        let hadOutboxItem = latest.outbox.contains { $0.kind == .createTransaction && $0.localTempId == tempId }
        latest.outbox.removeAll { $0.kind == .createTransaction && $0.localTempId == tempId }
        guard touched || hadOutboxItem else { return }
        saveSnapshot(latest)
        Self.logger.error("Transaction \(tempId) marked as failed: \(reason, privacy: .public)")
    }

    func discardGoneTransaction(tempId: Int) {
        var latest = snapshot
        if let removed = latest.transactions.first(where: { $0.id == tempId }) {
            Self.rollbackSummaryIfNeeded(for: removed, in: &latest.transactionSummary)
        }
        latest.transactions.removeAll { $0.id == tempId }
        latest.outbox.removeAll { $0.localTempId == tempId }
        saveSnapshot(latest)
        Self.logger.info("Transaction \(tempId) discarded: server reports 410 Gone")
    }

    func discardGoneDelete(item: OutboxItem) {
        guard let targetId = item.targetServerId else { return }
        var latest = snapshot
        switch item.kind {
        case .deleteEntry:
            latest.entries.removeAll { $0.id == targetId }
        case .deleteTransaction:
            if let removed = latest.transactions.first(where: { $0.id == targetId }) {
                Self.rollbackSummaryIfNeeded(for: removed, in: &latest.transactionSummary)
            }
            latest.transactions.removeAll { $0.id == targetId }
        default:
            break
        }
        latest.outbox.removeAll { $0.id == item.id }
        saveSnapshot(latest)
        Self.logger.info("Outbox delete \(item.id.uuidString) finished: server reports 404 Not Found")
    }

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
            onSnapshotUpdated?(snapshot)
        }

        Self.logger.info("Flushing outbox: \(self.snapshot.outbox.count) item(s) queued")

        var normalized = snapshot
        var stamped = false
        for index in normalized.outbox.indices {
            switch normalized.outbox[index].kind {
            case .createEntry:
                if let req = normalized.outbox[index].entryRequest, req.clientRequestId?.isEmpty != false {
                    normalized.outbox[index].entryRequest = stableEntryRequest(req)
                    stamped = true
                }
            case .createTransaction:
                if let req = normalized.outbox[index].transactionRequest, req.clientRequestId?.isEmpty != false {
                    normalized.outbox[index].transactionRequest = stableTransactionRequest(req)
                    stamped = true
                }
            default:
                break
            }
        }
        if stamped {
            saveSnapshot(normalized, critical: true)
        }

        let itemsToFlush = snapshot.outbox.filter { $0.retryCount < Self.maxOutboxRetryCount }

        let wasBatching = isBatching
        if !wasBatching { beginBatch() }

        for item in itemsToFlush {
            if Task.isCancelled { break }
            guard self.snapshot.outbox.contains(where: { $0.id == item.id }) else { continue }
            do {
                switch item.kind {
                case .createEntry:
                    if let req = item.entryRequest {
                        let created = try await APIClient.shared.createEntry(req)
                        var latest = self.snapshot
                        latest.entries.removeAll { $0.id == item.localTempId || $0.id == created.id }
                        latest.entries = Self.sortedEntries(latest.entries, inserting: created)
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
                        latest.transactions.removeAll { $0.id == item.localTempId || $0.id == created.id }
                        latest.transactions = Self.sortedRecords(latest.transactions, inserting: created)
                        latest.outbox.removeAll { $0.id == item.id }
                        self.saveSnapshot(latest)
                    }
                case .deleteTransaction:
                    if let targetId = item.targetServerId {
                        try await APIClient.shared.deleteTransaction(id: targetId)
                        var latest = self.snapshot
                        if let removed = latest.transactions.first(where: { $0.id == targetId }) {
                            Self.rollbackSummaryIfNeeded(for: removed, in: &latest.transactionSummary)
                        }
                        latest.transactions.removeAll { $0.id == targetId }
                        latest.outbox.removeAll { $0.id == item.id }
                        self.saveSnapshot(latest)
                    }
                }
            } catch let apiErr as APIError {
                if case .serverError(410, _) = apiErr {
                    switch item.kind {
                    case .createEntry:
                        self.discardGoneEntry(tempId: item.localTempId)
                    case .createTransaction:
                        self.discardGoneTransaction(tempId: item.localTempId)
                    default:
                        self.handleOutboxFailure(item: item, error: apiErr)
                    }
                    continue
                }
                if case .serverError(404, _) = apiErr,
                   item.kind == .deleteEntry || item.kind == .deleteTransaction {
                    self.discardGoneDelete(item: item)
                    continue
                }
                self.handleOutboxFailure(item: item, error: apiErr)
            } catch {
                self.handleOutboxFailure(item: item, error: APIError.networkFailure(error.localizedDescription))
            }
        }

        if !wasBatching { endBatch() }

        let remaining = self.snapshot.outbox.count
        Self.logger.info("Outbox flush finished, \(remaining) item(s) still pending")
        onOutboxFlushCompleted?(itemsToFlush.count)
    }

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

    nonisolated static func normalizeCursor(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed.count >= 6 {
            let suffix = trimmed.suffix(6)
            if suffix.hasPrefix(" ") && suffix.contains(":") {
                let prefix = trimmed.dropLast(6)
                if prefix.contains(":") {
                    let offsetDigits = suffix.dropFirst()
                    return "\(prefix)+\(offsetDigits)"
                }
            }
        }
        return trimmed
    }

    nonisolated static func lookbackCursor(_ raw: String?, seconds: TimeInterval = 120) -> String? {
        guard let normalized = normalizeCursor(raw) else { return nil }
        guard seconds > 0, let date = FormatUtils.parseFlexDate(normalized) else {
            return normalized
        }
        return FormatUtils.beijingISOString(from: date.addingTimeInterval(-seconds))
    }

    nonisolated static func latestServerCursor(_ timestamps: [String?]) -> String? {
        timestamps.compactMap { normalizeCursor($0) }.filter { !$0.isEmpty }.max()
    }

    public func mergeEntries(_ incoming: [LifeEntry], isDelta: Bool) async {
        let cursor = Self.latestServerCursor(incoming.flatMap { [$0.updatedAt, $0.deletedAt] })

        for _ in 0..<12 {
            try? Task.checkCancellation()
            if Task.isCancelled { return }
            let revision = snapshotRevision
            let current = snapshot.entries
            let merged = await Task.detached(priority: .userInitiated) {
                Self.mergedEntries(current: current, incoming: incoming, isDelta: isDelta)
            }.value

            guard snapshotRevision == revision else { continue }
            var latest = snapshot
            latest.entries = merged
            if let cursor {
                latest.lastEntriesSyncCursor = cursor
            }
            saveSnapshot(latest)
            return
        }

        if Task.isCancelled { return }
        Self.logger.warning("mergeEntries fell back to synchronous merge after repeated revision churn")
        var latest = snapshot
        latest.entries = Self.mergedEntries(current: latest.entries, incoming: incoming, isDelta: isDelta)
        if let cursor {
            latest.lastEntriesSyncCursor = cursor
        }
        saveSnapshot(latest)
    }

    /// 注水合并：磁盘快照负责补全历史，内存里已发生的本地写入优先（不把 loaded 条目改写为 synced）。
    nonisolated static func mergedHydratedSnapshot(
        current: LocalArchiveSnapshot,
        loaded: LocalArchiveSnapshot,
        hasAuthoritativeSummary: Bool = false
    ) -> LocalArchiveSnapshot {
        var merged = current
        merged.entries = mergeHydratedRecords(local: current.entries, disk: loaded.entries)
        merged.transactions = mergeHydratedRecords(local: current.transactions, disk: loaded.transactions)

        var outboxByID = Dictionary(loaded.outbox.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in current.outbox { outboxByID[item.id] = item }
        merged.outbox = outboxByID.values.sorted { $0.createdAt < $1.createdAt }

        let pendingDeletedEntryIds = Set(merged.outbox.compactMap { $0.kind == .deleteEntry ? $0.targetServerId : nil })
        if !pendingDeletedEntryIds.isEmpty {
            merged.entries.removeAll { pendingDeletedEntryIds.contains($0.id) }
        }
        let pendingDeletedTxIds = Set(merged.outbox.compactMap { $0.kind == .deleteTransaction ? $0.targetServerId : nil })
        if !pendingDeletedTxIds.isEmpty {
            merged.transactions.removeAll { pendingDeletedTxIds.contains($0.id) }
        }

        if (merged.lastEntriesSyncCursor ?? "").isEmpty {
            merged.lastEntriesSyncCursor = loaded.lastEntriesSyncCursor
        }
        if (merged.lastTransactionsSyncCursor ?? "").isEmpty {
            merged.lastTransactionsSyncCursor = loaded.lastTransactionsSyncCursor
        }
        if (merged.mediaURLsRefreshedAt ?? "").isEmpty {
            merged.mediaURLsRefreshedAt = loaded.mediaURLsRefreshedAt
        }
        if current.siteConfig.siteName.isEmpty {
            merged.siteConfig = loaded.siteConfig
        }
        if current.profile.name.isEmpty {
            merged.profile = loaded.profile
        }
        let statsEmpty = current.stats.totalEntries == 0
            && current.stats.totalPhotos == 0
            && current.stats.totalProjects == 0
            && current.stats.monthExpense == 0
        if statsEmpty {
            merged.stats = loaded.stats
        }
        let summaryEmpty = current.transactionSummary.count == 0
            && current.transactionSummary.totalExpense == 0
            && current.transactionSummary.totalIncome == 0
        if !hasAuthoritativeSummary,
           summaryEmpty,
           loaded.transactionSummary.year == current.transactionSummary.year,
           loaded.transactionSummary.month == current.transactionSummary.month {
            merged.transactionSummary = loaded.transactionSummary
        }
        return merged
    }

    // MARK: - 泛型合并与排序内核 (SyncableRecord)

    nonisolated static func preferHydrated<R: SyncableRecord>(local: R, disk: R) -> R {
        let localPending = (local.syncStatus ?? "synced") != "synced"
        let diskPending = (disk.syncStatus ?? "synced") != "synced"
        if diskPending && !localPending { return disk }
        if localPending && !diskPending { return local }
        return (disk.updatedAt ?? "") > (local.updatedAt ?? "") ? disk : local
    }

    nonisolated static func mergeHydratedRecords<R: SyncableRecord>(local: [R], disk: [R]) -> [R] {
        var map = Dictionary(disk.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in local {
            if let diskItem = map[item.id] {
                map[item.id] = preferHydrated(local: item, disk: diskItem)
            } else {
                map[item.id] = item
            }
        }
        return sortedRecords(Array(map.values))
    }

    nonisolated static func mergedRecords<R: SyncableRecord>(current: [R], incoming: [R], isDelta: Bool) -> [R] {
        if !isDelta {
            let pendingLocal = current.filter { ($0.syncStatus ?? "synced") != "synced" }
            let validRemote = incoming.filter { ($0.deletedAt ?? "").isEmpty }
            return sortedRecords(pendingLocal + validRemote)
        }
        var map = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for record in incoming {
            if let deleted = record.deletedAt, !deleted.isEmpty {
                map.removeValue(forKey: record.id)
            } else {
                var synced = record
                synced.syncStatus = "synced"
                map[record.id] = synced
            }
        }
        return sortedRecords(Array(map.values))
    }

    nonisolated static func sortedRecords<R: SyncableRecord>(_ records: [R], inserting extra: R? = nil) -> [R] {
        var itemsWithDate: [(record: R, date: Date)] = records.map {
            ($0, FormatUtils.parseFlexDate($0.occurredAt) ?? .distantPast)
        }
        if let extra {
            itemsWithDate.append((extra, FormatUtils.parseFlexDate(extra.occurredAt) ?? .distantPast))
        }
        itemsWithDate.sort {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.record.id > $1.record.id
        }
        return itemsWithDate.map(\.record)
    }

    /// 只增不删地合并一批远端散页（用于首屏优先投递，不推进游标）
    public func mergeEntriesIncremental(_ incoming: [LifeEntry]) {
        var current = snapshot
        current.entries = Self.mergedRecords(current: current.entries, incoming: incoming, isDelta: true)
        saveSnapshot(current)
    }

    /// 时间流合并（纯函数，可单测）
    nonisolated static func mergedEntries(current: [LifeEntry], incoming: [LifeEntry], isDelta: Bool) -> [LifeEntry] {
        mergedRecords(current: current, incoming: incoming, isDelta: isDelta)
    }

    /// 时间流统一排序（保留性能遥测埋点）
    nonisolated static func sortedEntries(_ entries: [LifeEntry], inserting extra: LifeEntry? = nil) -> [LifeEntry] {
        ArchivePerformance.metric(.sync, "sortEntryCount", entries.count)
        return ArchivePerformance.measure(.sync, "sortEntries") {
            sortedRecords(entries, inserting: extra)
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

    /// 账目合并（纯函数，可单测）
    nonisolated static func mergedTransactions(current: [Transaction], incoming: [Transaction], isDelta: Bool) -> [Transaction] {
        mergedRecords(current: current, incoming: incoming, isDelta: isDelta)
    }
}

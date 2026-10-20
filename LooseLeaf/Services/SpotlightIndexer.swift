import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import os

/// Spotlight 系统搜索索引器：将散页记录写入系统级搜索（标题 / 正文 / 城市 / 标签）。
/// 采用「防抖 + 增量 diff」策略：只重建发生变化或消失的条目，避免每次保存都擦写整个索引域。
///
/// 并发模型：全部可变状态由单一 `stateLock` 保护；重建任务用「代号（generation）」判新旧，
/// 防止被取消但仍在运行的旧任务覆盖新结果（Swift 取消不会中断已开始的同步工作）。
enum SpotlightIndexer {
    private static let domainIdentifier = "com.looseleaf.archive.entries"
    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "spotlight")

    /// 单一状态锁：保护 indexedVersions / hasRebuiltDomain / debounceTask / generation
    private static let stateLock = NSLock()

    /// 防抖任务句柄
    private static var debounceTask: Task<Void, Never>?
    /// 重建代号：每次调度自增；执行时若代号已过期则直接放弃
    private static var generation: UInt64 = 0

    /// 已写入系统索引的条目指纹（id -> 内容版本），用于计算增量
    private static var indexedVersions: [Int: String] = [:]
    /// 首次运行需要清理历史遗留的孤儿索引项
    private static var hasRebuiltDomain = false
    /// 指纹是否已从磁盘恢复
    private static var didRestorePersistedState = false

    /// 单次提交给 CoreSpotlight 的最大条目数（避免一次性提交几千条导致系统侧内存峰值）
    private static let indexBatchSize = 200

    /// 指纹持久化文件：跨会话增量，避免每次冷启动全量清空重建系统索引
    private static var persistedStateURL: URL {
        SyncManager.sharedStorageDirectory.appendingPathComponent("spotlight_versions.json")
    }

    /// 指纹状态恢复（后台执行，绝不在主线程读盘 + 解码）
    private static func restorePersistedStateIfNeeded() {
        stateLock.lock()
        let alreadyRestored = didRestorePersistedState
        stateLock.unlock()
        guard !alreadyRestored else { return }

        let url = persistedStateURL
        Task.detached(priority: .utility) {
            let decoded = (try? Data(contentsOf: url, options: .mappedIfSafe))
                .flatMap { try? JSONDecoder().decode([Int: String].self, from: $0) }
            applyRestoredState(decoded)
        }
    }

    /// 同步应用恢复结果（独立函数：避免在异步上下文中直接操作 NSLock）
    private static func applyRestoredState(_ decoded: [Int: String]?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let decoded, !decoded.isEmpty {
            indexedVersions = decoded
            hasRebuiltDomain = true
        }
        didRestorePersistedState = true
    }

    /// 指纹状态持久化（串行队列，避免并发写导致旧数据覆盖新数据）
    private static let persistQueue = DispatchQueue(label: "com.looseleaf.spotlight.persist", qos: .utility)

    private static func persistState() {
        stateLock.lock()
        let snapshot = indexedVersions
        stateLock.unlock()
        let url = persistedStateURL
        persistQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// 全量/增量重建散页索引（防抖 1.5 秒，避免高频保存触发重复擦写系统索引库）
    static func reindex(entries: [LifeEntry], immediate: Bool = false) {
        restorePersistedStateIfNeeded()

        stateLock.lock()
        debounceTask?.cancel()
        generation &+= 1
        let currentGeneration = generation
        stateLock.unlock()

        if immediate {
            performReindex(entries: entries, generation: currentGeneration)
            return
        }

        let task = Task.detached(priority: .utility) {
            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                return   // 被取消（正常路径）
            }
            guard !Task.isCancelled else { return }
            SpotlightIndexer.performReindex(entries: entries, generation: currentGeneration)
        }
        stateLock.lock()
        debounceTask = task
        stateLock.unlock()
    }

    /// 立即提交一次索引（应用退出前调用，避免 1.5 秒防抖窗口内的变更丢失）
    @MainActor
    static func flushNow() {
        stateLock.lock()
        debounceTask?.cancel()
        debounceTask = nil
        generation &+= 1
        let currentGeneration = generation
        stateLock.unlock()
        // 立即执行一次重建（不等待防抖）
        performReindex(entries: AppState.shared.entries, generation: currentGeneration)
    }

    private static func fingerprint(_ entry: LifeEntry) -> String {
        // 只取会影响搜索结果的字段，避免为纯排序变化付出重建成本
        "\(entry.updatedAt ?? "")|\(entry.title)|\(entry.content.count)|\(entry.cityName ?? "")|\(entry.location ?? "")"
    }

    private static func makeItem(_ entry: LifeEntry) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = entry.title.isEmpty ? "散页手稿" : entry.title
        attrs.contentDescription = entry.content
        attrs.contentCreationDate = FormatUtils.parseFlexDate(entry.occurredAt)
        attrs.city = entry.cityName ?? entry.location
        return CSSearchableItem(
            uniqueIdentifier: "looseleaf-entry-\(entry.id)",
            domainIdentifier: domainIdentifier,
            attributeSet: attrs
        )
    }

    /// 执行一次增量重建。
    /// - Parameter generation: 调度时的代号；若已被更新的调度取代则直接放弃本次工作。
    private static func performReindex(entries: [LifeEntry], generation expectedGeneration: UInt64) {
        stateLock.lock()
        guard expectedGeneration == generation else {
            stateLock.unlock()
            return
        }
        let oldVersions = indexedVersions
        let needsDomainReset = !hasRebuiltDomain
        stateLock.unlock()

        let visible = entries.filter { ($0.deletedAt ?? "").isEmpty }

        var newVersions: [Int: String] = [:]
        newVersions.reserveCapacity(visible.count)
        for entry in visible {
            newVersions[entry.id] = fingerprint(entry)
        }

        let removedIdentifiers = oldVersions.keys
            .filter { newVersions[$0] == nil }
            .map { "looseleaf-entry-\($0)" }
        let changedEntries = visible.filter { newVersions[$0.id] != oldVersions[$0.id] }

        let index = CSSearchableIndex.default()

        /// 提交指纹状态：只有系统索引**写入成功**后才提交，
        /// 否则该条目的指纹会被记为「已索引」，导致它**永久无法被 Spotlight 搜到**。
        func commitState() {
            stateLock.lock()
            indexedVersions = newVersions
            hasRebuiltDomain = true
            stateLock.unlock()
            logger.info("Spotlight incremental reindex: +\(changedEntries.count) / -\(removedIdentifiers.count), total \(newVersions.count)")
            persistState()
        }

        func indexChanged() {
            guard !changedEntries.isEmpty else {
                commitState()
                return
            }
            // 分批提交，避免一次性提交数千条导致 CoreSpotlight 侧内存峰值
            let batches = stride(from: 0, to: changedEntries.count, by: indexBatchSize).map {
                Array(changedEntries[$0..<min($0 + indexBatchSize, changedEntries.count)])
            }
            func submit(_ remaining: [[LifeEntry]]) {
                guard let batch = remaining.first else {
                    commitState()
                    return
                }
                let items = batch.map(makeItem)
                index.indexSearchableItems(items) { error in
                    if let error {
                        // 写入失败：绝不提交指纹状态，下次 reindex 会自动重试该批条目
                        logger.error("Spotlight index failed: \(error.localizedDescription)")
                        return
                    }
                    submit(Array(remaining.dropFirst()))
                }
            }
            submit(batches)
        }

        if needsDomainReset {
            // 首次运行：清掉旧版本可能留下的孤儿条目，再写入当前全量
            index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in
                indexChanged()
            }
            return
        }

        guard !removedIdentifiers.isEmpty else {
            indexChanged()
            return
        }
        index.deleteSearchableItems(withIdentifiers: removedIdentifiers) { error in
            if let error {
                // 删除失败：同样不提交状态，下次会重试删除（避免系统索引残留「幽灵条目」）
                logger.error("Spotlight delete failed: \(error.localizedDescription)")
                return
            }
            indexChanged()
        }
    }
}

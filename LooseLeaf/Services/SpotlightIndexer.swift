import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import os

/// Spotlight 系统搜索索引器：将散页记录写入系统级搜索（标题 / 正文 / 城市 / 标签）。
/// 采用「防抖 + 增量 diff」策略：只重建发生变化或消失的条目，避免每次保存都擦写整个索引域。
enum SpotlightIndexer {
    private static let domainIdentifier = "com.looseleaf.archive.entries"
    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "spotlight")
    private static var debounceTask: Task<Void, Never>?
    private static let lock = NSLock()

    /// 已写入系统索引的条目指纹（id -> 内容版本），用于计算增量
    private static var indexedVersions: [Int: String] = [:]
    /// 首次运行需要清理历史遗留的孤儿索引项
    private static var hasRebuiltDomain = false
    /// 串行化多次重建，避免防抖任务与 immediate 调用互相覆盖状态
    private static let reindexLock = NSLock()

    /// 指纹持久化文件：跨会话增量，避免每次冷启动全量清空重建系统索引
    private static var persistedStateURL: URL {
        SyncManager.sharedStorageDirectory.appendingPathComponent("spotlight_versions.json")
    }

    /// 首次访问时从磁盘恢复指纹（static let 保证只执行一次）
    private static let restorePersistedState: Void = {
        guard let data = try? Data(contentsOf: persistedStateURL),
              let decoded = try? JSONDecoder().decode([Int: String].self, from: data), !decoded.isEmpty else {
            return
        }
        lock.lock()
        indexedVersions = decoded
        hasRebuiltDomain = true
        lock.unlock()
    }()

    private static func persistState() {
        lock.lock()
        let snapshot = indexedVersions
        lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: persistedStateURL, options: .atomic)
            }
        }
    }

    /// 全量/增量重建散页索引（防抖 1.5 秒，避免高频保存触发重复擦写系统索引库）
    static func reindex(entries: [LifeEntry], immediate: Bool = false) {
        _ = restorePersistedState
        lock.lock()
        debounceTask?.cancel()
        if immediate {
            lock.unlock()
            performReindex(entries: entries)
            return
        }

        debounceTask = Task.detached(priority: .utility) {
            do {
                try await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                performReindex(entries: entries)
            } catch {}
        }
        lock.unlock()
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

    private static func performReindex(entries: [LifeEntry]) {
        reindexLock.lock()
        defer { reindexLock.unlock() }

        let visible = entries.filter { ($0.deletedAt ?? "").isEmpty }

        lock.lock()
        let oldVersions = indexedVersions
        let needsDomainReset = !hasRebuiltDomain
        lock.unlock()

        var newVersions: [Int: String] = [:]
        newVersions.reserveCapacity(visible.count)
        for entry in visible {
            newVersions[entry.id] = fingerprint(entry)
        }

        let removedIdentifiers = oldVersions.keys
            .filter { newVersions[$0] == nil }
            .map { "looseleaf-entry-\($0)" }
        let changedItems = visible
            .filter { newVersions[$0.id] != oldVersions[$0.id] }
            .map(makeItem)

        let index = CSSearchableIndex.default()

        func commitState() {
            lock.lock()
            indexedVersions = newVersions
            hasRebuiltDomain = true
            lock.unlock()
            logger.info("Spotlight incremental reindex: +\(changedItems.count) / -\(removedIdentifiers.count), total \(newVersions.count)")
        persistState()
        }

        func indexChanged() {
            guard !changedItems.isEmpty else {
                commitState()
                return
            }
            index.indexSearchableItems(changedItems) { error in
                if let error {
                    logger.error("Spotlight index failed: \(error.localizedDescription)")
                }
                commitState()
            }
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
                logger.error("Spotlight delete failed: \(error.localizedDescription)")
            }
            indexChanged()
        }
    }
}

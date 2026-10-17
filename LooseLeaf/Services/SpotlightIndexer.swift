import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import os

/// Spotlight 系统搜索索引器：将散页记录写入系统级搜索（标题 / 正文 / 城市 / 标签）。
/// 数据量小，采用「防抖整体重建」策略，由快照刷新驱动。
enum SpotlightIndexer {
    private static let domainIdentifier = "com.looseleaf.archive.entries"
    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "spotlight")
    private static var debounceTask: Task<Void, Never>?
    private static let lock = NSLock()

    /// 全量重建散页索引（防抖 1.5 秒，避免高频保存触发重复全量擦写系统索引库）
    static func reindex(entries: [LifeEntry], immediate: Bool = false) {
        lock.lock()
        debounceTask?.cancel()
        if immediate {
            lock.unlock()
            performReindex(entries: entries)
            return
        }

        debounceTask = Task.detached(priority: .utility) {
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                performReindex(entries: entries)
            } catch {}
        }
        lock.unlock()
    }

    private static func performReindex(entries: [LifeEntry]) {
        let items = entries
            .filter { ($0.deletedAt ?? "").isEmpty }
            .map { entry -> CSSearchableItem in
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

        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in
            index.indexSearchableItems(items) { error in
                if let error {
                    logger.error("Spotlight reindex failed: \(error.localizedDescription)")
                } else {
                    logger.info("Spotlight reindexed \(items.count) item(s)")
                }
            }
        }
    }
}

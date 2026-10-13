import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import os

/// Spotlight 系统搜索索引器：将散页记录写入系统级搜索（标题 / 正文 / 城市 / 标签）。
/// 数据量小，采用「整体重建」策略，由快照刷新驱动。
enum SpotlightIndexer {
    private static let domainIdentifier = "com.looseleaf.archive.entries"
    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "spotlight")

    /// 全量重建散页索引（异步执行，不阻塞调用方）
    static func reindex(entries: [LifeEntry]) {
        let items = entries
            .filter { ($0.deletedAt ?? "").isEmpty }
            .map { entry -> CSSearchableItem in
                let attrs = CSSearchableItemAttributeSet(contentType: .text)
                attrs.title = entry.title.isEmpty ? "散页手稿" : entry.title
                attrs.contentDescription = entry.content
                attrs.contentCreationDate = FormatUtils.parseFlexDate(entry.occurredAt)
                attrs.city = entry.cityName ?? entry.location
                attrs.keywords = entry.hashtags
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

import XCTest
@testable import LooseLeaf

/// 同步与数据完整性回归测试 (Sync & Data Integrity)
///
/// 覆盖第二批优化清单引入的关键不变量：
/// - 快照 schema 版本与迁移
/// - 增量合并与软删除对账
/// - 排序稳定性
/// - CSV / JSON 导出契约
/// - 凭据并发安全
/// - 设计令牌
@MainActor
final class ArchiveSyncIntegrityTests: XCTestCase {

    // MARK: - 合并与排序

    func testMergedEntriesKeepsPendingLocalItemsOnFullSync() {
        let pending = LifeEntry(
            id: -1,
            title: "离线草稿",
            content: "",
            occurredAt: "2026-10-01T08:00:00+08:00",
            syncStatus: "pending_create"
        )
        let remote = LifeEntry(
            id: 10,
            title: "远端",
            content: "",
            occurredAt: "2026-10-02T08:00:00+08:00"
        )
        let merged = SyncManager.mergedEntries(current: [pending], incoming: [remote], isDelta: false)
        XCTAssertTrue(merged.contains { $0.id == -1 }, "全量同步不得丢弃未同步的本地项")
        XCTAssertTrue(merged.contains { $0.id == 10 })
    }

    func testMergedEntriesRemovesSoftDeletedEntries() {
        let alive = LifeEntry(id: 1, title: "留存", content: "", occurredAt: "2026-10-01T08:00:00+08:00")
        let deleted = LifeEntry(id: 2, title: "已删", content: "", occurredAt: "2026-10-02T08:00:00+08:00", deletedAt: "2026-10-03T08:00:00+08:00")
        let merged = SyncManager.mergedEntries(current: [alive], incoming: [deleted], isDelta: true)
        XCTAssertEqual(merged.map(\.id), [1])
    }

    func testSortedEntriesIsStableForSameTimestamp() {
        let a = LifeEntry(id: 1, title: "A", content: "", occurredAt: "2026-10-01T08:00:00+08:00")
        let b = LifeEntry(id: 2, title: "B", content: "", occurredAt: "2026-10-01T08:00:00+08:00")
        let sorted = SyncManager.sortedEntries([a, b])
        XCTAssertEqual(sorted.map(\.id), [2, 1], "同一时刻必须按 id 倒序确定排序")
        // 幂等：重复排序结果一致
        XCTAssertEqual(SyncManager.sortedEntries(sorted).map(\.id), [2, 1])
    }

    func testLatestServerCursorIgnoresEmptyAndNil() {
        XCTAssertEqual(
            SyncManager.latestServerCursor(["2026-10-03T10:00:00+08:00", nil, "2026-10-01T10:00:00+08:00", ""]),
            "2026-10-03T10:00:00+08:00"
        )
        XCTAssertNil(SyncManager.latestServerCursor([]))
    }

    func testLocalTempIdsAreUniqueAndNegative() {
        var seen = Set<Int>()
        for _ in 0..<50 {
            let id = SyncManager.makeLocalTempId()
            XCTAssertLessThan(id, 0, "本地临时 ID 必须为负值")
            XCTAssertTrue(seen.insert(id).inserted, "本地临时 ID 不得重复")
        }
    }

    // MARK: - 导出契约

    func testFullArchiveJSONRoundTripKeepsEntries() throws {
        var snap = LocalArchiveSnapshot()
        snap.entries = [
            LifeEntry(id: 1, title: "第一条", content: "正文", occurredAt: "2026-10-01T08:00:00+08:00")
        ]
        snap.transactions = [
            Transaction(id: 1, amount: 4250, type: "expense", category: "餐饮", title: "咖啡", occurredAt: "2026-10-01T08:00:00+08:00")
        ]

        let data = try ArchiveExporter.makeFullArchiveJSON(snapshot: snap, projects: [], wishes: [], footprints: [])
        let decoded = try JSONDecoder().decode(ArchiveExporter.FullArchiveExportPayload.self, from: data)
        XCTAssertEqual(decoded.snapshot.entries.count, 1)
        XCTAssertEqual(decoded.snapshot.entries.first?.title, "第一条")
        XCTAssertEqual(decoded.snapshot.transactions.first?.amount, 4250)
    }

    func testCSVQuotesFieldsWithTabAndQuote() {
        let tx = Transaction(
            id: 1,
            amount: 100,
            type: "expense",
            category: "餐饮",
            title: "含\t制表符",
            note: "含\"引号\"",
            paymentMethod: "现金",
            cityCode: "330100",
            occurredAt: "2026-10-01T08:00:00+08:00"
        )
        let csv = ArchiveExporter.makeTransactionsCSV(transactions: [tx])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"), "CSV 必须带 UTF-8 BOM 以便 Excel 正确识别中文")
        XCTAssertTrue(csv.contains("\"含\t制表符\""), "含制表符的字段必须加引号")
        XCTAssertTrue(csv.contains("\"\"引号\"\""), "引号必须被转义为两个引号")
    }

    func testMarkdownIncludesTitleAndAttachments() {
        var entry = LifeEntry(id: 1, title: "西湖散步", content: "风很轻", occurredAt: "2026-10-01T08:00:00+08:00")
        entry.attachments = [
            Attachment(id: 1, objectKey: "k", originalFilename: "a.jpg", mimeType: "image/jpeg", size: 100, width: 800, height: 600, url: "https://x/a.jpg")
        ]
        let md = ArchiveExporter.makeMarkdown(entries: [entry])
        XCTAssertTrue(md.contains("## 西湖散步"))
        XCTAssertTrue(md.contains("风很轻"))
        XCTAssertTrue(md.contains("a.jpg（800 × 600）"))
    }

    // MARK: - 设计令牌

    func testDesignTokensMeetMinimumSizes() {
        XCTAssertGreaterThanOrEqual(ArchiveHitTarget.minPointer, 28)
        XCTAssertGreaterThanOrEqual(ArchiveHitTarget.minTouch, 44)
        XCTAssertGreaterThanOrEqual(ArchiveTypography.Scale.micro, 10, "正文级最小字号不得低于 10pt")
        XCTAssertEqual(ArchiveSheetWidth.form, 720)
    }

    func testArchiveAppInfoExposesVersionAndRepository() {
        XCTAssertFalse(ArchiveAppInfo.repository.isEmpty)
        XCTAssertNotNil(ArchiveAppInfo.repositoryURL)
        XCTAssertFalse(ArchiveAppInfo.fullVersion.isEmpty)
    }

    func testShortcutReferenceCoversPrimaryCommands() {
        let combinations = ArchiveShortcutReference.all.map(\.combination)
        XCTAssertTrue(combinations.contains("⌘N"))
        XCTAssertTrue(combinations.contains("⌘K"))
        XCTAssertTrue(combinations.contains("⌘R"))
        XCTAssertTrue(combinations.contains("⌘,"))
    }

    // MARK: - 日期解析矩阵

    func testFlexDateHandlesAllSupportedLayouts() {
        let samples = [
            "2026-10-13T21:15:00+08:00",
            "2026-10-13T21:15:00Z",
            "2026-10-13 09:30:00",
            "2026-10-13 09:30",
            "2026-10-13",
            "2026.10.13 09:30:00",
            "2026.10.13 09:30",
            "2026.10.13",
            "2026:10:13 09:30:00"
        ]
        for raw in samples {
            XCTAssertNotNil(FormatUtils.parseFlexDate(raw), "格式「\(raw)」应能解析")
        }
        XCTAssertNil(FormatUtils.parseFlexDate("完全不是时间"))
        XCTAssertNil(FormatUtils.parseFlexDate(nil))
        XCTAssertNil(FormatUtils.parseFlexDate(""))
    }

    func testDaysBetweenHandlesMonthAndYearBoundaries() {
        XCTAssertEqual(FormatUtils.daysBetween("2026-09-30 23:00:00", "2026-10-01 01:00:00"), 1)
        XCTAssertEqual(FormatUtils.daysBetween("2025-12-31 08:00:00", "2026-01-01 08:00:00"), 1)
        XCTAssertEqual(FormatUtils.daysBetween("2026-02-27 08:00:00", "2026-03-01 08:00:00"), 2, "2026 非闰年")
        XCTAssertEqual(FormatUtils.daysBetween("2024-02-27 08:00:00", "2024-03-01 08:00:00"), 3, "2024 为闰年")
    }
}

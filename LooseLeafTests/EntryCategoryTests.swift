import XCTest
@testable import LooseLeaf

/// 散页原生分类（方式 A，与后端 commit 0fc123c / Android v2.2.1 / Vesper Space 四大展区 1:1 对齐）回归测试
final class EntryCategoryTests: XCTestCase {

    // MARK: - 1. EntryCategory 归一化解析与文案契约

    func testNormalizationCoversCanonicalAliasesAndFallbacks() {
        XCTAssertEqual(EntryCategory(normalized: nil), .daily)
        XCTAssertEqual(EntryCategory(normalized: ""), .daily)
        XCTAssertEqual(EntryCategory(normalized: "  "), .daily)
        XCTAssertEqual(EntryCategory(normalized: "daily"), .daily)
        XCTAssertEqual(EntryCategory(normalized: "日常"), .daily)
        XCTAssertEqual(EntryCategory(normalized: "日常随笔"), .daily)

        XCTAssertEqual(EntryCategory(normalized: "Photography"), .photography)
        XCTAssertEqual(EntryCategory(normalized: "photography"), .photography)
        XCTAssertEqual(EntryCategory(normalized: "摄影"), .photography)

        XCTAssertEqual(EntryCategory(normalized: "Travel"), .travel)
        XCTAssertEqual(EntryCategory(normalized: "旅途"), .travel)
        XCTAssertEqual(EntryCategory(normalized: "旅行"), .travel)

        XCTAssertEqual(EntryCategory(normalized: "Still Life"), .stillLife)
        XCTAssertEqual(EntryCategory(normalized: "still_life"), .stillLife)
        XCTAssertEqual(EntryCategory(normalized: "still-life"), .stillLife)
        XCTAssertEqual(EntryCategory(normalized: "静物"), .stillLife)
        XCTAssertEqual(EntryCategory(normalized: "器物"), .stillLife)

        XCTAssertEqual(EntryCategory(normalized: "Motion"), .motion)
        XCTAssertEqual(EntryCategory(normalized: "video"), .motion)
        XCTAssertEqual(EntryCategory(normalized: "影像"), .motion)

        XCTAssertEqual(EntryCategory(normalized: "UnknownCategory"), .daily)
    }

    func testEntryCategoryLabelsAndRawValues() {
        XCTAssertEqual(EntryCategory.daily.rawValue, "")
        XCTAssertEqual(EntryCategory.daily.label, "日常")
        XCTAssertEqual(EntryCategory.daily.badgeLabel, "日常随笔")

        XCTAssertEqual(EntryCategory.photography.rawValue, "Photography")
        XCTAssertEqual(EntryCategory.photography.label, "摄影")
        XCTAssertEqual(EntryCategory.photography.badgeLabel, "摄影")

        XCTAssertEqual(EntryCategory.travel.rawValue, "Travel")
        XCTAssertEqual(EntryCategory.travel.label, "旅途")
        XCTAssertEqual(EntryCategory.travel.badgeLabel, "旅途")

        XCTAssertEqual(EntryCategory.stillLife.rawValue, "Still Life")
        XCTAssertEqual(EntryCategory.stillLife.label, "静物")
        XCTAssertEqual(EntryCategory.stillLife.badgeLabel, "静物")

        XCTAssertEqual(EntryCategory.motion.rawValue, "Motion")
        XCTAssertEqual(EntryCategory.motion.label, "影像")
        XCTAssertEqual(EntryCategory.motion.badgeLabel, "影像")
    }

    // MARK: - 2. LifeEntry 解码兼容与 toCreateRequest 透传

    func testLifeEntryDecodingWithAndWithoutCategoryField() throws {
        let withCategory = """
        {
            "id": 201,
            "type": "life",
            "category": "Still Life",
            "title": "窗台茶盏",
            "content": "下午的光落在粗陶杯口",
            "occurred_at": "2026-11-23T15:00:00+08:00"
        }
        """.data(using: .utf8)!

        let decodedWithCategory = try JSONDecoder().decode(LifeEntry.self, from: withCategory)
        XCTAssertEqual(decodedWithCategory.category, "Still Life")
        XCTAssertEqual(decodedWithCategory.resolvedCategory, .stillLife)
        XCTAssertEqual(decodedWithCategory.displayBadgeLabel, "静物")
        XCTAssertEqual(decodedWithCategory.toCreateRequest().category, "Still Life")

        // 旧缓存/旧快照不含 category 字段时必须安全回落为空串（日常）
        let legacyJSON = """
        {
            "id": 202,
            "type": "life",
            "title": "旧版缓存散页",
            "content": "没有 category 键",
            "occurred_at": "2026-10-01T10:00:00+08:00"
        }
        """.data(using: .utf8)!

        let decodedLegacy = try JSONDecoder().decode(LifeEntry.self, from: legacyJSON)
        XCTAssertEqual(decodedLegacy.category, "")
        XCTAssertEqual(decodedLegacy.resolvedCategory, .daily)
        XCTAssertEqual(decodedLegacy.displayBadgeLabel, "日常随笔")
    }

    func testCreateEntryRequestLegacyOutboxDecodingCompatibility() throws {
        let legacyOutboxPayload = """
        {
            "type": "life",
            "title": "升级前离线草稿",
            "content": "没有 category 字段的旧发件箱载荷",
            "occurred_at": "2026-11-20T09:00:00+08:00",
            "attachment_ids": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CreateEntryRequest.self, from: legacyOutboxPayload)
        XCTAssertEqual(decoded.category, "")
        XCTAssertEqual(decoded.title, "升级前离线草稿")

        let fresh = CreateEntryRequest(category: EntryCategory.motion.rawValue, content: "街角慢镜头")
        let encoded = try JSONEncoder().encode(fresh)
        let dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(dict["category"] as? String, "Motion")
    }

    // MARK: - 3. UpdateEntryRequest 三态 category 编码契约

    func testUpdateEntryRequestCategoryTriStateEncoding() throws {
        // 1) nil：局部更新（例如仅切换私密态）不得携带 category 键，避免覆盖服务端原值
        let untouched = UpdateEntryRequest(isPrivate: true)
        let untouchedData = try JSONEncoder().encode(untouched)
        let untouchedJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: untouchedData) as? [String: Any])
        XCTAssertNil(untouchedJSON["category"], "未修改分类时不得写出 category 键")

        // 2) ""：把画廊分类改回「日常」时，必须显式写出 "category": ""
        let resetToDaily = UpdateEntryRequest(type: "life", category: "", content: "改回日常")
        let resetData = try JSONEncoder().encode(resetToDaily)
        let resetJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: resetData) as? [String: Any])
        XCTAssertEqual(resetJSON["category"] as? String, "", "改回日常时必须显式下发空字符串 category")

        // 3) 非空画廊分类：原样编码为后端标准枚举串
        let setGallery = UpdateEntryRequest(type: "life", category: EntryCategory.photography.rawValue, content: "胶片一卷")
        let setData = try JSONEncoder().encode(setGallery)
        let setJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: setData) as? [String: Any])
        XCTAssertEqual(setJSON["category"] as? String, "Photography")
    }

    // MARK: - 4. ArchiveCategory 过滤视角匹配

    func testArchiveCategoryFilteringMatchesNativeCategories() {
        let dailyEntry = LifeEntry(id: 1, type: "life", category: "", title: "日常", content: "正文", occurredAt: "2026-11-23T09:00:00+08:00")
        let photoEntry = LifeEntry(id: 2, type: "life", category: "Photography", title: "街头", content: "正文", occurredAt: "2026-11-23T10:00:00+08:00")
        let travelEntry = LifeEntry(id: 3, type: "life", category: "Travel", title: "山间", content: "正文", occurredAt: "2026-11-23T11:00:00+08:00")
        let stillLifeEntry = LifeEntry(id: 4, type: "life", category: "Still Life", title: "茶具", content: "正文", occurredAt: "2026-11-23T12:00:00+08:00")
        let motionEntry = LifeEntry(id: 5, type: "life", category: "Motion", title: "短片", content: "正文", occurredAt: "2026-11-23T13:00:00+08:00")
        let wishEntry = LifeEntry(id: 6, type: "wish", category: "Photography", title: "心愿", content: "正文", occurredAt: "2026-11-23T14:00:00+08:00")

        let all = [dailyEntry, photoEntry, travelEntry, stillLifeEntry, motionEntry, wishEntry]

        XCTAssertEqual(all.filter { $0.matches(category: .all) }.count, 6)
        // .daily 匹配全部 type == "life"（含日常与四大画廊分区）
        XCTAssertEqual(all.filter { $0.matches(category: .daily) }.map(\.id), [1, 2, 3, 4, 5])
        // 四大画廊分区仅匹配 type == "life" 且归一化 category 精确一致的散页（心愿不混入）
        XCTAssertEqual(all.filter { $0.matches(category: .photography) }.map(\.id), [2])
        XCTAssertEqual(all.filter { $0.matches(category: .travel) }.map(\.id), [3])
        XCTAssertEqual(all.filter { $0.matches(category: .stillLife) }.map(\.id), [4])
        XCTAssertEqual(all.filter { $0.matches(category: .motion) }.map(\.id), [5])
        XCTAssertEqual(all.filter { $0.matches(category: .wish) }.map(\.id), [6])

        XCTAssertEqual(wishEntry.displayBadgeLabel, "心愿印记")
    }

    // MARK: - 5. hasDistinctTitle 去重规则（对齐 Android v2.2.1）

    func testHasDistinctTitleFiltersPlaceholdersAndDerivedTitles() {
        func make(title: String, content: String) -> LifeEntry {
            LifeEntry(id: 1, title: title, content: content, occurredAt: "2026-11-23T10:00:00+08:00")
        }

        XCTAssertFalse(make(title: "", content: "正文").hasDistinctTitle)
        XCTAssertFalse(make(title: "   ", content: "正文").hasDistinctTitle)
        XCTAssertFalse(make(title: "无题随笔", content: "正文").hasDistinctTitle)
        XCTAssertFalse(make(title: "无题", content: "正文").hasDistinctTitle)
        XCTAssertFalse(make(title: "现场快门 · 2026.11.23", content: "拍了一张").hasDistinctTitle)
        XCTAssertFalse(make(title: "现场记录 · 杭州", content: "散步").hasDistinctTitle)
        XCTAssertFalse(make(title: "今天下午的光很好", content: "今天下午的光很好\n拍了一卷胶片").hasDistinctTitle)
        XCTAssertFalse(make(title: "今天下午的光很好…", content: "今天下午的光很好，顺手拍了一张").hasDistinctTitle)
        XCTAssertFalse(make(title: "今天下午的光很好...", content: "今天下午的光很好，顺手拍了一张").hasDistinctTitle)

        XCTAssertTrue(make(title: "秋日暗房", content: "第一卷 Portra 400 冲洗完成").hasDistinctTitle)
        XCTAssertTrue(make(title: "仅有标题", content: "").hasDistinctTitle)
    }

    // MARK: - 6. 状态层草稿重置与 SyncManager 指纹 / 乐观入队透传

    @MainActor
    func testQuickCaptureDraftCategoryResetAndOptimisticPassthrough() {
        let draft = QuickCaptureDraft()
        draft.category = .travel
        draft.titleText = "京都步行"
        draft.resetThought()
        XCTAssertEqual(draft.category, .daily, "resetThought 必须将分类复位为 .daily")

        let base = LifeEntry(id: 10, type: "life", category: "", title: "随笔", content: "正文", occurredAt: "2026-11-23T10:00:00+08:00")
        var categorized = base
        categorized.category = EntryCategory.photography.rawValue
        XCTAssertNotEqual(
            SyncManager.entryFingerprint([base]),
            SyncManager.entryFingerprint([categorized]),
            "仅修改散页分类也必须使快照指纹变化，避免大档案下 UI 跳过刷新"
        )

        let optimistic = SyncManager.shared.submitEntryOptimistically(
            CreateEntryRequest(category: EntryCategory.stillLife.rawValue, title: "桌面", content: "离线静物测试")
        )
        defer { SyncManager.shared.removeOptimisticEntry(localTempId: optimistic.id) }
        XCTAssertEqual(optimistic.category, "Still Life")
        XCTAssertEqual(optimistic.resolvedCategory, .stillLife)
    }
}

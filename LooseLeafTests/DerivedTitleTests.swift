import XCTest
@testable import LooseLeaf

/// 「朋友圈式发布」的标题派生规则
///
/// 关键：这条规则必须在 **后端 / mac / Web 三端一致**，
/// 否则同一条记录在不同端标题会不一样，搜索与索引也对不上。
/// 后端有 `TestDeriveTitleFromContent`，Web 有同名实现，这里是第三份。
@MainActor
final class DerivedTitleTests: XCTestCase {

    func test01_DerivesFirstLineOfContent() {
        XCTAssertEqual(FormatUtils.derivedTitle(from: "今天下午的光很好"), "今天下午的光很好")
        XCTAssertEqual(FormatUtils.derivedTitle(from: "第一行\n第二行\n第三行"), "第一行")
        XCTAssertEqual(FormatUtils.derivedTitle(from: "   \n第二行"), "")
        XCTAssertEqual(FormatUtils.derivedTitle(from: "  今天的随笔  "), "今天的随笔")
        XCTAssertEqual(FormatUtils.derivedTitle(from: ""), "")
    }

    func test02_TruncatesLongFirstLine() {
        let long = String(repeating: "甲", count: 45)
        let derived = FormatUtils.derivedTitle(from: long)
        XCTAssertEqual(derived.count, 41, "应截断到 40 字并加省略号")
        XCTAssertTrue(derived.hasSuffix("…"))
    }

    func test03_KeepsExactlyMaxLength() {
        let exact = String(repeating: "甲", count: 40)
        XCTAssertEqual(FormatUtils.derivedTitle(from: exact), exact)
    }

    /// 草稿的 effectiveTitle：显式标题优先，否则从正文派生
    func test04_DraftEffectiveTitle() {
        let draft = EntryDraft()
        draft.content = "搬进新居的第一天\n把书架靠到窗边。"
        XCTAssertEqual(draft.effectiveTitle, "搬进新居的第一天")

        draft.title = "  手写的标题  "
        XCTAssertEqual(draft.effectiveTitle, "手写的标题")
    }
}

import XCTest
@testable import LooseLeaf

/// Spotlight 索引范围的隐私回归（DEC-03 口径 C）
///
/// 背景：原文把**每条散页的正文全文**写进系统 Spotlight 索引。
/// 于是私人文字会被系统搜索与 Siri 命中；若用户开了「与 Siri 共享」
/// 或 iCloud 同步 Spotlight，内容还会**外流到云端** —— 而应用本身对此毫无提示。
///
/// 现在默认只索引「标题 + 前 60 字摘要」，完整索引交给用户在设置里显式开启。
/// 这里把这条口径钉死，防止日后有人「顺手」改回全文索引。
final class SpotlightPrivacyTests: XCTestCase {

    override func tearDown() {
        // 复位全局开关，避免污染其它用例
        SpotlightIndexer.indexesFullContent = false
        super.tearDown()
    }

    /// 默认必须**不**索引全文
    func testDefaultDoesNotIndexFullContent() {
        let fresh = SpotlightIndexer.indexesFullContent
        XCTAssertFalse(
            fresh,
            "默认不得索引正文全文 —— 私人文字会被系统搜索与 Siri 命中，开启 iCloud 同步时还会外流到云端"
        )
    }

    /// 摘要长度上限 60 字（超出的部分截断并加省略号）
    func testSummaryIsTruncatedToSixtyCharacters() {
        let long = String(repeating: "散", count: 200)
        let summary = SpotlightIndexer.summary(of: long)
        XCTAssertTrue(summary.hasSuffix("…"), "超长正文应当以省略号收尾，实际: \(summary)")
        // 60 个正文 + 1 个省略号
        XCTAssertEqual(summary.count, 61, "摘要应当是 60 字正文加一个省略号")
    }

    /// 短正文原样保留（不硬凑省略号）
    func testShortContentIsKeptVerbatim() {
        let short = "很短的一则随笔"
        XCTAssertEqual(SpotlightIndexer.summary(of: short), short)
    }

    /// 首尾空白先裁掉，避免摘要以空格开头（系统搜索里很难看）
    func testSummaryTrimsWhitespace() {
        XCTAssertEqual(SpotlightIndexer.summary(of: "   \n 正文  \n "), "正文")
    }

    /// 空正文得到空摘要（不能崩、也不能塞占位符）
    func testEmptyContentYieldsEmptySummary() {
        XCTAssertEqual(SpotlightIndexer.summary(of: ""), "")
        XCTAssertEqual(SpotlightIndexer.summary(of: "   \n  "), "")
    }

    /// 摘要里**不得**出现正文尾部的私密内容
    func testSummaryDoesNotLeakTailContent() {
        let secret = "这一段是私密内容不应该出现在索引里"
        let content = String(repeating: "公开的日常记录。", count: 20) + secret
        let summary = SpotlightIndexer.summary(of: content)
        XCTAssertFalse(
            summary.contains(secret),
            "摘要不得包含正文尾部的内容"
        )
    }
}

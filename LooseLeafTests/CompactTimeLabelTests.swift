import XCTest
@testable import LooseLeaf

/// 时间流的「朋友圈式」紧凑时间戳
///
/// 规则（参照朋友圈）：
///   - 与上一条**同一分钟** → 折叠，不显示
///   - 与上一条**同一天**   → "HH:mm"
///   - 跨天、同一年         → "9月1日"
///   - 跨年                 → "2025年9月1日"
///
/// 关键：早先每张卡都印着完整的 "YYYY.MM.DD HH:mm"，一行占掉大半行宽度；
/// 改成随跨度变化的短标签后，一屏能多看一倍的内容。
@MainActor
final class CompactTimeLabelTests: XCTestCase {

    /// 直接用 ISO 串构造一份 ParsedBeijingDate（走 Formatter 的正规解析路径）
    private func label(_ current: String, _ previous: String?) -> String {
        guard let curDate = FormatUtils.parseFlexDate(current) else { return "" }
        let cur = FormatUtils.formatBeijingDate(curDate)
        let prev = previous
            .flatMap { FormatUtils.parseFlexDate($0) }
            .map { FormatUtils.formatBeijingDate($0) }
        return AppState.compactTimeLabel(cur, previous: prev)
    }

    func test01_FirstRowShowsDate() {
        // 第一条没有参照 → 给日期，让人知道这是什么时候的记录
        let result = label("2026-09-01T10:00:00+08:00", nil)
        XCTAssertTrue(result.contains("9") && result.contains("1"), "首条应显示日期，实际 \(result)")
    }

    func test02_SameDayShowsClockTime() {
        let result = label("2026-09-01T10:00:00+08:00", "2026-09-01T08:00:00+08:00")
        XCTAssertEqual(result, "10:00")
    }

    func test03_SameMinuteIsCollapsed() {
        // 同一分钟的连续记录 → 不重复显示时间
        let result = label("2026-09-01T10:00:00+08:00", "2026-09-01T10:00:00+08:00")
        XCTAssertEqual(result, "", "同一分钟应折叠为空串")
    }

    func test04_CrossDayShowsMonthAndDay() {
        let result = label("2026-09-02T10:00:00+08:00", "2026-09-01T10:00:00+08:00")
        XCTAssertEqual(result, "9月2日")
    }

    func test05_CrossYearShowsFullDate() {
        let result = label("2027-01-05T10:00:00+08:00", "2026-12-31T10:00:00+08:00")
        XCTAssertTrue(result.contains("2027"), "跨年应显示年份，实际 \(result)")
    }

    /// 标签必须**短**：一整行里不能超过 10 个字符，否则又会像原先那样占满半行
    func test06_LabelStaysShort() {
        let cases: [(String, String?)] = [
            ("2026-09-01T10:00:00+08:00", nil),
            ("2026-09-02T10:00:00+08:00", "2026-09-01T10:00:00+08:00"),
            ("2027-01-05T10:00:00+08:00", "2026-12-31T10:00:00+08:00")
        ]
        for (cur, prev) in cases {
            let result = label(cur, prev)
            XCTAssertLessThanOrEqual(result.count, 10, "时间戳过长：\(result)")
        }
    }
}

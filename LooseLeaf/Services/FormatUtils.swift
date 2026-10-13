import Foundation

/// 散页全平台统一格式化与解析中枢
/// 严格遵循：
/// 1. 货币分级整型标准 (Cents Precision, Int64)，严禁使用浮点数存储或传输金额
/// 2. 中国北京时间基准 (UTC+8, RC-134)，无论系统处于何种时区，展示与切分一律锚定 UTC+8
public enum FormatUtils {
    /// 中国北京时间固定偏移 (UTC+8)，不依赖系统本地时区设置
    public static let beijingTimeZone = TimeZone(secondsFromGMT: 8 * 3600)!

    /// 北京时间日历（值类型缓存，线程安全）
    public static let beijingCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = beijingTimeZone
        cal.locale = Locale(identifier: "zh_CN")
        return cal
    }()

    // MARK: - 解析器缓存（高频调用，复用实例 + 加锁保证线程安全）

    private static let formatLock = NSLock()

    private static let isoFractionFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoStandardFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let flexDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = beijingTimeZone
        return df
    }()

    private static let beijingISOFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = beijingTimeZone
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'+08:00'"
        return df
    }()

    private static let flexLayouts = [
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
        "yyyy.MM.dd HH:mm:ss",
        "yyyy.MM.dd HH:mm",
        "yyyy.MM.dd",
        "yyyy:MM:dd HH:mm:ss" // EXIF DateTimeOriginal
    ]

    // MARK: - 货币分币转换与格式化 (Cents Standard)

    private static let yuanFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    /// 将以“分”为单位的 Int64 金额格式化为标准元字符串 (如 4250 -> "42.50" 或 "¥ 42.50")
    public static func formattedYuan(cents: Int64, includeSymbol: Bool = false) -> String {
        formatLock.lock()
        defer { formatLock.unlock() }
        let isNegative = cents < 0
        let absCents = abs(cents)
        let decimalYuan = Decimal(absCents) / Decimal(100)
        let number = NSDecimalNumber(decimal: decimalYuan)
        let formatted = yuanFormatter.string(from: number) ?? String(format: "%lld.%02lld", absCents / 100, absCents % 100)
        let sign = isNegative ? "-" : ""
        if includeSymbol {
            return "\(sign)¥ \(formatted)"
        }
        return "\(sign)\(formatted)"
    }

    /// 将用户输入的元字符串转换为精确的 Int64 分值 (如 "42.5" -> 4250)
    public static func parseYuanToCents(_ rawInput: String) -> Int64? {
        let cleaned = rawInput
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "元", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty,
              let decimalVal = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }

        var multiplied = decimalVal * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &multiplied, 0, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        let cents = number.int64Value
        return cents > 0 ? cents : nil
    }

    // MARK: - 快捷记账自然语义解析 (Quick Ledger Parser)

    public struct QuickLedgerParsed: Equatable, Sendable {
        public let amountCents: Int64
        public let type: String // "expense" | "income"
        public let category: String
        public let title: String

        public init(amountCents: Int64, type: String, category: String, title: String) {
            self.amountCents = amountCents
            self.type = type
            self.category = category
            self.title = title
        }
    }

    /// 解析如 "42.5 午餐咖啡"、"129 数码器材 无线鼠标"、"+5000 薪资" 等快捷记账指令
    /// - Parameter knownCategories: 后端动态下发的支出分类字典（为空时回退到内置基准分类集）
    public static func parseQuickLedgerInput(
        _ input: String,
        defaultCategory: String = "餐饮",
        knownCategories: [String] = []
    ) -> QuickLedgerParsed? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return nil }

        var detectedCents: Int64?
        var detectedType = "expense"
        var remainingTokens: [String] = []

        for token in tokens {
            if detectedCents == nil {
                var tokenClean = token
                if tokenClean.hasPrefix("+") {
                    detectedType = "income"
                    tokenClean.removeFirst()
                } else if tokenClean.hasPrefix("-") {
                    detectedType = "expense"
                    tokenClean.removeFirst()
                }
                if let cents = parseYuanToCents(tokenClean) {
                    detectedCents = cents
                    continue
                }
            }
            remainingTokens.append(token)
        }

        guard let amountCents = detectedCents, amountCents > 0 else {
            return nil
        }

        let effectiveCategories = knownCategories.isEmpty ? builtinCategories : knownCategories
        var category: String?
        var titleParts: [String] = []

        for part in remainingTokens {
            if category == nil && effectiveCategories.contains(part) {
                category = part
            } else {
                titleParts.append(part)
            }
        }

        let finalTitle = titleParts.joined(separator: " ")
        let inferredCategory = category ?? inferCategory(from: finalTitle, isIncome: detectedType == "income", fallback: defaultCategory)
        let displayTitle = finalTitle.isEmpty ? inferredCategory : finalTitle

        return QuickLedgerParsed(
            amountCents: amountCents,
            type: detectedType,
            category: inferredCategory,
            title: displayTitle
        )
    }

    /// 内置基准分类集（后端未下发或离线时的最小语义集）
    private static let builtinCategories = ["餐饮", "交通", "购物", "数码器材", "娱乐", "住房", "学习", "医疗", "二手回血", "其他"]

    private static func inferCategory(from text: String, isIncome: Bool, fallback: String) -> String {
        if isIncome {
            if text.contains("二手") || text.contains("出闲置") || text.contains("回血") {
                return "二手回血"
            }
            return "其他"
        }
        let rules: [(keywords: [String], category: String)] = [
            (["咖啡", "午餐", "午饭", "晚餐", "晚饭", "早餐", "早饭", "奶茶", "外卖", "面", "火锅", "聚餐", "茶", "面包", "甜点", "水果"], "餐饮"),
            (["地铁", "打车", "滴滴", "高铁", "火车", "机票", "公交", "加油", "停车", "单车", "出租"], "交通"),
            (["相机", "镜头", "胶卷", "鼠标", "键盘", "显示器", "耳机", "手机", "电脑", "充电", "硬盘", "内存"], "数码器材"),
            (["房租", "水电", "物业", "宽带", "燃气", "话费", "维修", "家居"], "住房"),
            (["书", "课程", "订阅", "会员", "专栏", "文具", "笔记本", "纸"], "学习"),
            (["电影", "演出", "展览", "游戏", "门票", "黑胶", "音乐"], "娱乐"),
            (["药", "医院", "体检", "牙", "诊所", "挂号"], "医疗"),
            (["衣服", "鞋", "包", "日用", "超市", "网购"], "购物")
        ]
        for rule in rules {
            if rule.keywords.contains(where: { text.contains($0) }) {
                return rule.category
            }
        }
        return fallback
    }

    // MARK: - 弹性时间解析与北京时间格式化 (FlexTime & UTC+8 Standard)

    public struct ParsedBeijingDate: Equatable, Sendable {
        public let year: String
        public let month: String
        public let day: String
        public let time: String
        public let dateKey: String   // "YYYY-MM-DD"
        public let dotDate: String   // "YYYY.MM.DD"
        public let dotDateTime: String // "YYYY.MM.DD HH:mm"
        public let date: Date
    }

    /// 弹性解析后端或本地输入的多种时间格式，无时区后缀一律按北京时间 (UTC+8) 解释
    public static func parseFlexDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        formatLock.lock()
        defer { formatLock.unlock() }

        // 1. 带时区偏移的标准 ISO8601 / RFC3339
        if let d = isoFractionFormatter.date(from: raw) {
            return d
        }
        if let d = isoStandardFormatter.date(from: raw) {
            return d
        }

        // 2. 不带时区后缀的弹性格式，统一按北京时间 UTC+8 解释
        for layout in flexLayouts {
            flexDateFormatter.dateFormat = layout
            if let d = flexDateFormatter.date(from: raw) {
                return d
            }
        }
        return nil
    }

    /// 统一解析 occurred_at 并返回北京时间各维度出版物格式
    public static func parseOccurredDate(_ raw: String?) -> ParsedBeijingDate {
        let date = parseFlexDate(raw) ?? Date()
        return formatBeijingDate(date)
    }

    public static func formatBeijingDate(_ date: Date) -> ParsedBeijingDate {
        let comps = beijingCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let y = String(format: "%04d", comps.year ?? 2026)
        let m = String(format: "%02d", comps.month ?? 1)
        let d = String(format: "%02d", comps.day ?? 1)
        let hh = String(format: "%02d", comps.hour ?? 0)
        let mm = String(format: "%02d", comps.minute ?? 0)

        let time = "\(hh):\(mm)"
        let dateKey = "\(y)-\(m)-\(d)"
        let dotDate = "\(y).\(m).\(d)"
        let dotDateTime = "\(dotDate) \(time)"

        return ParsedBeijingDate(
            year: y,
            month: m,
            day: d,
            time: time,
            dateKey: dateKey,
            dotDate: dotDate,
            dotDateTime: dotDateTime,
            date: date
        )
    }

    /// 生成带 +08:00 偏移的标准北京时间 ISO8601 字符串
    public static func beijingISOString(from date: Date = Date()) -> String {
        formatLock.lock()
        defer { formatLock.unlock() }
        return beijingISOFormatter.string(from: date)
    }

    /// 生成北京时间 YYYY-MM-DD 字符串
    public static func beijingDateString(from date: Date = Date()) -> String {
        formatBeijingDate(date).dateKey
    }

    /// 当前北京时间的年份与月份
    public static func beijingCurrentYearMonth(from date: Date = Date()) -> (year: Int, month: Int) {
        let comps = beijingCalendar.dateComponents([.year, .month], from: date)
        return (comps.year ?? 2026, comps.month ?? 10)
    }

    /// 计算两条记录在自然日维度上的间隔天数（用于 >= 14 天岁月留白刻度线）
    public static func daysBetween(_ firstRaw: String?, _ secondRaw: String?) -> Int {
        let d1 = parseFlexDate(firstRaw) ?? Date()
        let d2 = parseFlexDate(secondRaw) ?? Date()
        let cal = beijingCalendar
        let start1 = cal.startOfDay(for: min(d1, d2))
        let start2 = cal.startOfDay(for: max(d1, d2))
        return cal.dateComponents([.day], from: start1, to: start2).day ?? 0
    }

    // MARK: - 标签提取 (#标签)

    /// 从正文或输入中提取 #标签 列表
    public static func extractHashtags(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "#([\\p{L}\\p{N}_\\-]+)", options: []) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        var seen = Set<String>()
        var result: [String] = []
        for match in matches {
            if match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text) {
                let tag = String(text[range])
                if !seen.contains(tag) {
                    seen.insert(tag)
                    result.append(tag)
                }
            }
        }
        return result
    }

    // MARK: - 城市名称与行政区划代码智能解析 (CityCodeResolver)

    /// 自动从地点字符串中识别对应的 6 位城市代码（如 "杭州 · 西湖" -> "330100"）
    /// 词典为全国地级行政区全量标准表（`CityDictionary`，与 web `web/src/utils/cities.ts` 对表一致）
    public static func resolveCityCode(from locationText: String) -> String? {
        let cleaned = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // 如果用户本身就输入了 6 位数字代码，直接使用
        if cleaned.count == 6 && cleaned.allSatisfy({ $0.isNumber }) {
            return cleaned
        }

        return CityDictionary.code(forLocation: cleaned)
    }
}

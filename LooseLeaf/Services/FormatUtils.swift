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

    // MARK: - 解析器缓存（每线程一份，彻底消除全局锁串行化）

    /// DateFormatter / NumberFormatter 都不是线程安全的，但共享一把全局锁会让
    /// 列表滚动（主线程）与后台解码/排序互相排队。这里改为每线程缓存一份实例：
    /// 线程数很少（主线程 + URLSession/磁盘队列），内存代价可忽略，热路径零锁竞争。
    private final class FormatterBag {
        let isoFraction: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        let isoStandard: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        let flexDate: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = FormatUtils.beijingTimeZone
            return df
        }()

        let beijingISO: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = FormatUtils.beijingTimeZone
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'+08:00'"
            return df
        }()

        let yuan: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            formatter.groupingSeparator = ","
            formatter.usesGroupingSeparator = true
            return formatter
        }()
    }

    private static let formatterKey = "com.looseleaf.formatutils.formatters"

    private static var formatters: FormatterBag {
        let dictionary = Thread.current.threadDictionary
        if let existing = dictionary[formatterKey] as? FormatterBag {
            return existing
        }
        let bag = FormatterBag()
        dictionary[formatterKey] = bag
        return bag
    }

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

    /// 将以“分”为单位的 Int64 金额格式化为标准元字符串 (如 4250 -> "42.50" 或 "¥ 42.50")
    /// 从正文派生标题（朋友圈式发布：只填正文，标题自动取第一行）
    ///
    /// 关键：这条规则必须在**客户端、后端、Web 三端一致**，
    /// 否则同一条记录在不同端的标题会不一样，搜索与索引也会对不上。
    /// 规则：取正文的第一行（去掉首尾空白），超过 `maxLength` 则截断并加省略号。
    public static func derivedTitle(from content: String, maxLength: Int = 40) -> String {
        let firstLine = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }

    public static func formattedYuan(cents: Int64, includeSymbol: Bool = false) -> String {
        let isNegative = cents < 0
        // Int64.min 取绝对值会溢出 trap；这是极端值，钳到 Int64.max 只差 1 分，远好于崩溃
        let absCents = cents == Int64.min ? Int64.max : abs(cents)
        let decimalYuan = Decimal(absCents) / Decimal(100)
        let number = NSDecimalNumber(decimal: decimalYuan)
        let formatted = formatters.yuan.string(from: number) ?? String(format: "%lld.%02lld", absCents / 100, absCents % 100)
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
        // 四舍五入（原先用 .plain 截断，"0.999" 会变成 99 分而非 100 分）
        NSDecimalRound(&rounded, &multiplied, 0, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        let cents = number.int64Value
        return cents > 0 ? cents : nil
    }

    /// 金额解析的「可区分失败」版本：0 元返回 0，非法输入返回 nil
    public static func parseYuanToCentsAllowZero(_ rawInput: String) -> Int64? {
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
        return NSDecimalNumber(decimal: rounded).int64Value
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
            let rules: [(keywords: [String], category: String)] = [
                (["工资", "薪资", "奖金", "津贴", "月薪"], "工资收入"),
                (["二手", "出闲置", "回血", "卖掉"], "二手回血"),
                (["稿费", "稿酬", "稿筹", "设计费", "外包"], "稿酬设计"),
                (["利息", "理财", "分红", "基金", "股票"], "投资理财"),
                (["红包", "礼金", "压岁钱"], "礼金红包"),
                (["报销", "退款", "退货"], "退款报销")
            ]
            for rule in rules where rule.keywords.contains(where: { text.contains($0) }) {
                return rule.category
            }
            return "其他收入"
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
        /// 原始时间串是否可解析。false 时展示"时间未知"，且不参与热力图/间隔计算。
        public let isValid: Bool

        public static let unknown = ParsedBeijingDate(
            year: "----",
            month: "--",
            day: "--",
            time: "--:--",
            dateKey: "",
            dotDate: "未知日期",
            dotDateTime: "时间未知",
            date: .distantPast,
            isValid: false
        )
    }

    /// 弹性解析后端或本地输入的多种时间格式，无时区后缀一律按北京时间 (UTC+8) 解释
    ///
    /// 性能关键：这里曾是**全局最热函数**（列表滚动、排序、热力图、Spotlight 索引都会调用）。
    /// 原实现对每条时间串盲试 9 种 layout（外加 2 次 ISO 尝试，最多 11 次 DateFormatter 解析），
    /// 5,000 条记录渲染一次约 16.5 万次解析 → 主线程 0.3~0.8 秒卡顿。
    /// 现在先按「字符串形状」筛掉不可能命中的 layout，把尝试次数降到 1~4 次。
    public static func parseFlexDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        // 1. 带时区偏移的标准 ISO8601 / RFC3339（ISO8601DateFormatter 解析为线程安全）
        if let d = formatters.isoFraction.date(from: raw) {
            return d
        }
        if let d = formatters.isoStandard.date(from: raw) {
            return d
        }

        // 2. 不带时区后缀的弹性格式，统一按北京时间 UTC+8 解释
        let candidates = candidateLayouts(for: raw)
        guard !candidates.isEmpty else { return nil }
        let flex = formatters.flexDate
        for layout in candidates {
            flex.dateFormat = layout
            if let d = flex.date(from: raw) {
                return d
            }
        }
        return nil
    }

    /// 依据字符串形状筛出可能命中的时间格式（顺序与 `flexLayouts` 保持一致，语义不变）
    private static func candidateLayouts(for raw: String) -> [String] {
        let hasColon = raw.contains(":")
        let hasDot = raw.contains(".")
        let hasSpace = raw.contains(" ")
        // EXIF 拍摄时间形如 "2026:10:13 09:30:00"：日期部分的前 5 个字符内含冒号
        let looksLikeExif = raw.prefix(5).contains(":")

        var candidates: [String] = []
        if raw.contains("T") && hasColon {
            candidates.append("yyyy-MM-dd'T'HH:mm:ss")
            candidates.append("yyyy-MM-dd'T'HH:mm")
        }
        if hasSpace && hasColon && !raw.contains("T") {
            candidates.append("yyyy-MM-dd HH:mm:ss")
            candidates.append("yyyy-MM-dd HH:mm")
        }
        if !hasColon && raw.contains("-") {
            candidates.append("yyyy-MM-dd")
        }
        if hasDot && hasSpace && hasColon {
            candidates.append("yyyy.MM.dd HH:mm:ss")
            candidates.append("yyyy.MM.dd HH:mm")
        }
        if hasDot && !hasColon {
            candidates.append("yyyy.MM.dd")
        }
        if looksLikeExif {
            candidates.append("yyyy:MM:dd HH:mm:ss")
        }
        return candidates
    }

    /// 统一解析 occurred_at 并返回北京时间各维度出版物格式。
    /// 解析失败时返回 `unknown`（而不是伪装成"现在"），避免坏数据污染热力图与排序。
    public static func parseOccurredDate(_ raw: String?) -> ParsedBeijingDate {
        guard let date = parseFlexDate(raw) else {
            return .unknown
        }
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
            date: date,
            isValid: true
        )
    }

    /// 生成带 +08:00 偏移的标准北京时间 ISO8601 字符串
    public static func beijingISOString(from date: Date = Date()) -> String {
        formatters.beijingISO.string(from: date)
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

    /// 将日期字符串格式化为北京时间点状日期 (如 "2026.10.17")
    public static func formatDate(_ raw: String?) -> String {
        guard let raw = raw, !raw.isEmpty else { return "" }
        return parseOccurredDate(raw).dotDate
    }

    /// 将日期字符串格式化为北京时间点状时间 (如 "2026.10.17 14:30")
    public static func formatDateTime(_ raw: String?) -> String {
        guard let raw = raw, !raw.isEmpty else { return "" }
        return parseOccurredDate(raw).dotDateTime
    }

    /// 计算两条记录在自然日维度上的间隔天数（用于 >= 14 天岁月留白刻度线）
    /// 任一端时间不可解析时返回 0，调用方据此不渲染留白切线。
    public static func daysBetween(_ firstRaw: String?, _ secondRaw: String?) -> Int {
        guard let d1 = parseFlexDate(firstRaw), let d2 = parseFlexDate(secondRaw) else {
            return 0
        }
        return daysBetween(d1, d2)
    }

    /// 已是 Date 的间隔计算（避免对同一批条目反复解析时间串）
    public static func daysBetween(_ d1: Date, _ d2: Date) -> Int {
        let cal = beijingCalendar
        let start1 = cal.startOfDay(for: min(d1, d2))
        let start2 = cal.startOfDay(for: max(d1, d2))
        return cal.dateComponents([.day], from: start1, to: start2).day ?? 0
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

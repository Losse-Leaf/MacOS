import Foundation

/// 全量多格式档案导出中枢：支持 Markdown 长文、UTF-8 BOM CSV 账单流水与全量 JSON 结构化冷备
public enum ArchiveExporter {

    public enum ExportFormat: String, Sendable {
        case markdown
        case csv
        case json
    }

    /// 全量结构化备份载荷
    public struct FullArchiveExportPayload: Codable, Sendable {
        public let exportedAt: String
        public let snapshot: LocalArchiveSnapshot
        public let projects: [Project]
        public let wishes: [Wish]
        public let footprints: [Footprint]

        enum CodingKeys: String, CodingKey {
            case exportedAt = "exported_at"
            case snapshot
            case projects
            case wishes
            case footprints
        }

        public init(
            exportedAt: String = FormatUtils.beijingISOString(),
            snapshot: LocalArchiveSnapshot,
            projects: [Project],
            wishes: [Wish],
            footprints: [Footprint]
        ) {
            self.exportedAt = exportedAt
            self.snapshot = snapshot
            self.projects = projects
            self.wishes = wishes
            self.footprints = footprints
        }
    }

    /// 生成完整 Markdown 文本（保持传入顺序，调用方通常传入「当前筛选视图」或全量散页）
    public static func makeMarkdown(entries: [LifeEntry]) -> String {
        var lines: [String] = []
        let exportTime = FormatUtils.formatBeijingDate(Date()).dotDateTime
        lines.append("# 散页 · 生活档案导出")
        lines.append("")
        lines.append("> 导出时间：\(exportTime)（北京时间） · 共 \(entries.count) 篇")
        lines.append("")

        for entry in entries {
            lines.append("---")
            lines.append("")
            let title = entry.title.isEmpty ? entryTypeName(entry.type) : entry.title
            lines.append("## \(title)")
            lines.append("")

            var meta: [String] = ["`\(entry.parsedDate.dotDateTime)`"]
            if let loc = entry.location ?? entry.cityName, !loc.isEmpty {
                meta.append(loc)
            }
            lines.append(meta.joined(separator: " · "))
            lines.append("")

            if !entry.content.isEmpty {
                lines.append(entry.content)
                lines.append("")
            }

            if !entry.attachments.isEmpty {
                lines.append("附件 \(entry.attachments.count) 项：")
                for att in entry.attachments {
                    if let w = att.width, let h = att.height {
                        lines.append("- \(att.originalFilename)（\(w) × \(h)）")
                    } else {
                        lines.append("- \(att.originalFilename)")
                    }
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 生成带 UTF-8 BOM (\u{FEFF}) 的标准账目流水 CSV（Excel / Numbers 直接双击无乱码）
    /// 列顺序：日期时间,收支类型,分类,标题,金额(元),金额(分),支付方式,城市代码,分期,备注
    public static func makeTransactionsCSV(transactions: [Transaction]) -> String {
        var rows: [String] = []
        rows.append("日期时间,收支类型,分类,标题,金额(元),金额(分),支付方式,城市代码,分期,备注")

        for tx in transactions {
            let dateStr = escapeCSVField(tx.parsedDate.dotDateTime)
            let typeStr = tx.type == "income" ? "收入" : "支出"
            let categoryStr = escapeCSVField(tx.category)
            let titleStr = escapeCSVField(tx.title.isEmpty ? tx.category : tx.title)
            let absCents = abs(tx.amount)
            let sign = tx.amount < 0 ? "-" : ""
            let yuanPlain = "\(sign)\(String(format: "%lld.%02lld", absCents / 100, absCents % 100))"
            let centsStr = "\(tx.amount)"
            let paymentStr = escapeCSVField(tx.paymentMethod ?? "")
            let cityStr = escapeCSVField(tx.cityCode ?? "")
            let installmentStr: String
            if tx.isInstallment == true {
                let months = tx.installmentMonths ?? 0
                let channel = tx.installmentChannelCode ?? ""
                installmentStr = escapeCSVField(channel.isEmpty ? "是(\(months)期)" : "\(channel)(\(months)期)")
            } else {
                installmentStr = "否"
            }
            let noteStr = escapeCSVField(tx.note ?? "")

            let row = [
                dateStr,
                typeStr,
                categoryStr,
                titleStr,
                yuanPlain,
                centsStr,
                paymentStr,
                cityStr,
                installmentStr,
                noteStr
            ].joined(separator: ",")
            rows.append(row)
        }

        return "\u{FEFF}" + rows.joined(separator: "\n")
    }

    /// 生成全量档案 JSON 备份数据。
    /// - Throws: 编码失败时抛出错误（原先返回 nil，调用方无法区分「无内容」与「编码失败」，
    ///   用户点击导出只会得到一个空文件且没有任何提示）。
    public static func makeFullArchiveJSON(
        snapshot: LocalArchiveSnapshot,
        projects: [Project],
        wishes: [Wish],
        footprints: [Footprint]
    ) throws -> Data {
        let payload = FullArchiveExportPayload(
            exportedAt: FormatUtils.beijingISOString(),
            snapshot: snapshot,
            projects: projects,
            wishes: wishes,
            footprints: footprints
        )
        let encoder = JSONEncoder()
        // 不用 .prettyPrinted：会让体积膨胀 2~3 倍；.sortedKeys 每层字典 O(n log n)
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    private static func escapeCSVField(_ raw: String) -> String {
        var cleaned = raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        // 阻断 Excel / Numbers 公式注入。
        // 关键：必须先去掉**前导空格与制表符**再判定 —— Excel 会 trim 后再执行公式，
        // 原实现只看首字符，" =cmd|..." 这类以空格开头的载荷会被漏判。
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let startsDangerously = trimmed.hasPrefix("=")
            || trimmed.hasPrefix("+")
            || trimmed.hasPrefix("@")
            || trimmed.hasPrefix("\t")
        let minusWithoutNumber = trimmed.hasPrefix("-") && Double(trimmed) == nil
        if startsDangerously || minusWithoutNumber {
            cleaned = "'" + cleaned
        }

        // 含分隔符、引号、空格或制表符的字段必须加引号（原实现漏了 \t，会被 Excel 错切）
        if cleaned.contains(",")
            || cleaned.contains("\"")
            || cleaned.contains(" ")
            || cleaned.contains("\t")
            || cleaned.contains("\n") {
            let escaped = cleaned.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return cleaned
    }

    /// 把 Markdown / CSV 导出结果流式写入文件（避免在内存中再拼一份完整副本）
    public static func writeTextToFile(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// 把 JSON 导出结果写入文件
    public static func writeJSONToFile(
        snapshot: LocalArchiveSnapshot,
        projects: [Project],
        wishes: [Wish],
        footprints: [Footprint],
        to url: URL
    ) throws {
        let data = try makeFullArchiveJSON(
            snapshot: snapshot,
            projects: projects,
            wishes: wishes,
            footprints: footprints
        )
        try data.write(to: url, options: .atomic)
    }

    private static func entryTypeName(_ raw: String) -> String {
        switch raw {
        case "travel": return "山川游历"
        case "project": return "造物演进"
        case "wish": return "心愿印记"
        case "transaction": return "柴米油盐"
        default: return "日常随笔"
        }
    }
}

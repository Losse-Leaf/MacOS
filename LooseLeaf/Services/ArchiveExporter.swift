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

    /// 生成全量档案 Pretty-Printed JSON 备份数据
    public static func makeFullArchiveJSON(
        snapshot: LocalArchiveSnapshot,
        projects: [Project],
        wishes: [Wish],
        footprints: [Footprint]
    ) -> Data? {
        let payload = FullArchiveExportPayload(
            exportedAt: FormatUtils.beijingISOString(),
            snapshot: snapshot,
            projects: projects,
            wishes: wishes,
            footprints: footprints
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(payload)
    }

    /// 循环分页拉取远端全量数据（遵循后端单页上限 pageSize <= 100 约束）并导出指定格式
    public static func fetchAllRemoteAndExport(
        format: ExportFormat,
        fallbackSnapshot: LocalArchiveSnapshot,
        fallbackProjects: [Project] = [],
        fallbackWishes: [Wish] = [],
        fallbackFootprints: [Footprint] = []
    ) async -> Data? {
        var exportSnapshot = fallbackSnapshot
        var exportProjects = fallbackProjects
        var exportWishes = fallbackWishes
        var exportFootprints = fallbackFootprints

        // 1. 分页拉取全量散页记录 (严格单页 pageSize = 100，绝不超过 100)
        if format == .markdown || format == .json {
            let pageSize = 100
            var page = 1
            var allEntries: [LifeEntry] = []
            var fetchSucceeded = false
            while true {
                guard let resp = try? await APIClient.shared.fetchEntries(
                    page: page,
                    pageSize: pageSize,
                    useETag: false
                ) else {
                    break
                }
                fetchSucceeded = true
                allEntries.append(contentsOf: resp.entries)
                if resp.entries.count < pageSize || allEntries.count >= resp.total {
                    break
                }
                page += 1
            }
            if fetchSucceeded && !allEntries.isEmpty {
                exportSnapshot.entries = allEntries
            }
        }

        // 2. 分批拉取全量账目流水
        if format == .csv || format == .json {
            let batchLimit = 500
            var offset = 0
            var allTxs: [Transaction] = []
            var txSucceeded = false
            while true {
                guard let batch = try? await APIClient.shared.fetchTransactions(
                    limit: batchLimit,
                    offset: offset,
                    useETag: false
                ) else {
                    break
                }
                txSucceeded = true
                allTxs.append(contentsOf: batch)
                if batch.count < batchLimit {
                    break
                }
                offset += batch.count
            }
            if txSucceeded && !allTxs.isEmpty {
                exportSnapshot.transactions = allTxs
            }
        }

        // 3. 若为全量 JSON 备份，补齐造物、心愿单（分页 pageSize = 100）与行迹
        if format == .json {
            if let remoteProjects = try? await APIClient.shared.fetchProjects() {
                exportProjects = remoteProjects
            }
            var wishPage = 1
            let wishPageSize = 100
            var allWishes: [Wish] = []
            while true {
                guard let wishResp = try? await APIClient.shared.fetchWishes(page: wishPage, pageSize: wishPageSize) else {
                    break
                }
                allWishes.append(contentsOf: wishResp.wishes)
                if wishResp.wishes.count < wishPageSize || allWishes.count >= wishResp.total {
                    break
                }
                wishPage += 1
            }
            if !allWishes.isEmpty {
                exportWishes = allWishes
            }
            if let remoteFootprints = try? await APIClient.shared.fetchFootprints() {
                exportFootprints = remoteFootprints
            }
        }

        switch format {
        case .markdown:
            return makeMarkdown(entries: exportSnapshot.entries).data(using: .utf8)
        case .csv:
            return makeTransactionsCSV(transactions: exportSnapshot.transactions).data(using: .utf8)
        case .json:
            return makeFullArchiveJSON(
                snapshot: exportSnapshot,
                projects: exportProjects,
                wishes: exportWishes,
                footprints: exportFootprints
            )
        }
    }

    private static func escapeCSVField(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        if cleaned.contains(",") || cleaned.contains("\"") {
            let escaped = cleaned.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return cleaned
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

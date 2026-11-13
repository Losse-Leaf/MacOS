import Foundation

/// 散页长文 Markdown 导出中枢
public enum ArchiveExporter {

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

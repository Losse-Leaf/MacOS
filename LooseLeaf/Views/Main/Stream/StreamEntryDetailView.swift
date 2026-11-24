import SwiftUI
import AppKit

/// 轻量安全的内联/引用块富文本视图（消除 `Text(LocalizedStringKey(...))` 对用户输入执行 `%@`/`%d` 格式化解析的隐患）
public struct EditorialProseTextView: View {
    public let text: String
    public var font: Font
    public var color: Color
    public var lineSpacing: CGFloat = 5
    public var lineLimit: Int? = nil

    public init(
        _ text: String,
        font: Font = ArchiveTypography.bodySans(size: 14),
        color: Color = ArchivePalette.inkPrimary,
        lineSpacing: CGFloat = 5,
        lineLimit: Int? = nil
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.lineSpacing = lineSpacing
        self.lineLimit = lineLimit
    }

    public var body: some View {
        if let lineLimit {
            renderedInlineText(text)
                .font(font)
                .foregroundStyle(color)
                .lineSpacing(lineSpacing)
                .lineLimit(lineLimit)
        } else {
            let blocks = Self.parseBlocks(text)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .paragraph(let content):
                        renderedInlineText(content)
                            .font(font)
                            .foregroundStyle(color)
                            .lineSpacing(lineSpacing)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .quote(let content):
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(ArchivePalette.accentWarm.opacity(0.65))
                                .frame(width: 2.5)
                            renderedInlineText(content)
                                .font(ArchiveTypography.monoScale(size: 12))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    }
                }
            }
        }
    }

    private enum Block {
        case paragraph(String)
        case quote(String)
    }

    private static func parseBlocks(_ raw: String) -> [Block] {
        guard raw.contains("\n>") || raw.hasPrefix(">") else {
            return [.paragraph(raw)]
        }
        var result: [Block] = []
        var currentLines: [String] = []
        var currentIsQuote: Bool?

        func flush() {
            guard !currentLines.isEmpty, let isQuote = currentIsQuote else { return }
            let joined = currentLines.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(isQuote ? .quote(joined) : .paragraph(joined))
            }
            currentLines.removeAll()
        }

        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") {
                if currentIsQuote == false { flush() }
                currentIsQuote = true
                let stripped = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                currentLines.append(stripped)
            } else {
                if currentIsQuote == true { flush() }
                currentIsQuote = false
                currentLines.append(line)
            }
        }
        flush()
        return result.isEmpty ? [.paragraph(raw)] : result
    }

    private func renderedInlineText(_ content: String) -> Text {
        if let attr = try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr)
        }
        return Text(verbatim: content)
    }
}

/// 散页详情视图 (Entry Detail)
/// 既用于主窗口内的详情弹层，也用于「在新窗口打开」的独立详情窗口（支持多窗口并排对照、窗口内编辑/删除/灯箱闭环）。
struct StreamEntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: LifeEntry
    let appState: AppState
    /// 是否运行在独立详情窗口中（独立窗口自适应全窗宽高，Sheet 模式约束版心）
    var isStandaloneWindow: Bool = false
    var onClose: (() -> Void)? = nil
    var onEditEntry: (LifeEntry) -> Void = { _ in }
    var onEditTransaction: (Transaction) -> Void = { _ in }
    var onDeleteTransaction: (Transaction) -> Void = { _ in }
    var onDeleteEntryOverride: ((LifeEntry) -> Void)? = nil
    var onOpenAttachment: ((Attachment) -> Void)? = nil

    private func handleClose() {
        if !isStandaloneWindow {
            appState.highlightedEntry = nil
        }
        onClose?()
        dismiss()
    }

    var body: some View {
        let isTx = (entry.type == "transaction")
        let txId = Int(entry.associatedTransactionId ?? Int64(entry.id))
        let matchingTx = isTx ? appState.transactionById[txId] : nil
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    if entry.type == EntryType.life.rawValue {
                        Circle()
                            .fill(entry.displayAccentColor)
                            .frame(width: 5.5, height: 5.5)
                            .accessibilityHidden(true)
                    }
                    Text(Self.entryTypeBadge(entry))
                        .font(ArchiveTypography.monoScale(size: 11, weight: .medium))
                }
                .foregroundStyle(entry.displayAccentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(entry.displayAccentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                if entry.isPrivate {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9.5))
                        Text("仅自己可见")
                            .font(ArchiveTypography.monoScale(size: 10.5))
                    }
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ArchivePalette.accentWarm.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .accessibilityLabel("私密记录，仅自己可见")
                }

                Text(entry.parsedDate.dotDateTime)
                    .font(ArchiveTypography.monoScale(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                Spacer()
                if appState.isPaired && (entry.id > 0 || (isTx && matchingTx != nil)) {
                    if isTx {
                        if let tx = matchingTx {
                            Button("编辑账目") {
                                if !isStandaloneWindow { handleClose() }
                                onEditTransaction(tx)
                            }
                            .font(ArchiveTypography.bodySans(size: 12))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .buttonStyle(.plain)
                            .paperButtonFocusRing(cornerRadius: 4)

                            Button("删除账目") {
                                if let onDeleteTx = isStandaloneWindow ? onDeleteTransaction : nil {
                                    onDeleteTx(tx)
                                } else {
                                    appState.askConfirm(
                                        title: ArchiveSharedCopy.transactionDeleteTitle,
                                        message: ArchiveSharedCopy.transactionDeleteMessage,
                                        confirmText: ArchiveSharedCopy.transactionDeleteConfirmText,
                                        danger: true
                                    ) {
                                        handleClose()
                                        onDeleteTransaction(tx)
                                    }
                                }
                            }
                            .font(ArchiveTypography.bodySans(size: 12))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .buttonStyle(.plain)
                            .paperButtonFocusRing(cornerRadius: 4)
                        }
                    } else {
                        Button("编辑手稿") {
                            let target = entry
                            if !isStandaloneWindow { handleClose() }
                            onEditEntry(target)
                        }
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .buttonStyle(.plain)
                        .paperButtonFocusRing(cornerRadius: 4)

                        Button("删除记录") {
                            if let onDeleteEntryOverride {
                                onDeleteEntryOverride(entry)
                            } else {
                                appState.askConfirm(
                                    title: ArchiveSharedCopy.entryDeleteTitle,
                                    message: ArchiveSharedCopy.entryDeleteMessage,
                                    confirmText: ArchiveSharedCopy.entryDeleteConfirmText,
                                    danger: true
                                ) {
                                    handleClose()
                                    appState.deleteEntryAction(entry)
                                }
                            }
                        }
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .buttonStyle(.plain)
                        .paperButtonFocusRing(cornerRadius: 4)
                    }
                }
                Button("关闭") {
                    handleClose()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()
            }

            if let tx = matchingTx {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tx.title.isEmpty ? tx.category : tx.title)
                            .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Spacer()
                        Text("\(tx.type == "income" ? "+" : "-")\(FormatUtils.formattedYuan(cents: tx.amount, includeSymbol: true))")
                            .font(ArchiveTypography.monoScale(size: 22, weight: .bold))
                            .foregroundStyle(tx.type == "income" ? ArchivePalette.accentMoss : ArchivePalette.inkPrimary)
                    }

                    HStack(spacing: 8) {
                        Text(tx.category)
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        if let pay = tx.paymentMethod, !pay.isEmpty {
                            Text(pay)
                                .font(ArchiveTypography.bodySans(size: 11.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        if let badgeText = tx.installmentBadgeText {
                            Text(badgeText)
                                .font(ArchiveTypography.monoScale(size: 11))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(ArchivePalette.accentWarm, lineWidth: 0.5)
                                )
                        }
                    }

                    if let note = tx.note, !note.isEmpty {
                        EditorialProseTextView(
                            note,
                            font: ArchiveTypography.bodySans(size: 13.5),
                            color: ArchivePalette.inkPrimary.opacity(0.88)
                        )
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 6)
            } else {
                let trimmedLocation = entry.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !trimmedLocation.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: ArchiveIcon.location.systemName)
                            .font(.system(size: 10))
                        Text(trimmedLocation)
                            .font(ArchiveTypography.monoScale(size: 11))
                    }
                    .foregroundStyle(ArchivePalette.inkMuted)
                }

                if entry.hasDistinctTitle {
                    Text(entry.title)
                        .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        EditorialProseTextView(
                            entry.content,
                            font: ArchiveTypography.bodySans(size: 14),
                            color: ArchivePalette.inkPrimary,
                            lineSpacing: 5
                        )
                        .textSelection(.enabled)

                        if !entry.attachments.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(entry.attachments) { att in
                                        if let url = att.resolvedDisplayURL(preferThumbnail: true) {
                                            FilmFrameView(
                                                imageURL: url,
                                                originalURL: att.resolvedDisplayURL(preferThumbnail: false),
                                                preferredFilename: att.originalFilename,
                                                intrinsicSize: att.intrinsicSize,
                                                caption: entry.title.isEmpty ? att.originalFilename : entry.title,
                                                metaText: entry.parsedDate.dotDate,
                                                maxHeight: 220
                                            ) {
                                                if let onOpenAttachment {
                                                    onOpenAttachment(att)
                                                } else {
                                                    appState.lightboxAttachment = att
                                                }
                                            } onExportNotice: { message in
                                                appState.showTemporaryBanner(message)
                                            }
                                            .frame(width: 240)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: isStandaloneWindow ? .infinity : 460)
            }
        }
        .padding(24)
        .frame(maxWidth: isStandaloneWindow ? 760 : 560, maxHeight: isStandaloneWindow ? .infinity : nil, alignment: .topLeading)
        .frame(maxWidth: isStandaloneWindow ? .infinity : nil)
        .background(ArchivePalette.archivePaper)
    }

    static func entryTypeBadge(_ entry: LifeEntry) -> String {
        entry.displayBadgeLabel
    }
}

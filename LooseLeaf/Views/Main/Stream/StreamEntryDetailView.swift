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
/// 支持三种承载形式：主窗口右侧原生 `.inspector()` 检视器、独立对照窗口 (`WindowGroup`) 与模态弹窗。
struct StreamEntryDetailView: View {
    enum PresentationStyle: Sendable {
        case inspector
        case standaloneWindow
        case sheet
    }

    @Environment(\.dismiss) private var dismiss
    let entry: LifeEntry
    let appState: AppState
    /// 是否运行在独立详情窗口中（兼容既有调用方）
    var isStandaloneWindow: Bool = false
    var presentationStyle: PresentationStyle? = nil
    var onClose: (() -> Void)? = nil
    var onOpenInNewWindow: ((LifeEntry) -> Void)? = nil
    var onEditEntry: (LifeEntry) -> Void = { _ in }
    var onEditTransaction: (Transaction) -> Void = { _ in }
    var onDeleteTransaction: (Transaction) -> Void = { _ in }
    var onDeleteEntryOverride: ((LifeEntry) -> Void)? = nil
    var onOpenAttachment: ((Attachment) -> Void)? = nil

    @State private var hydratedEntry: LifeEntry?

    private var resolvedStyle: PresentationStyle {
        presentationStyle ?? (isStandaloneWindow ? .standaloneWindow : .sheet)
    }

    private var displayEntry: LifeEntry {
        if let hydratedEntry, hydratedEntry.id == entry.id {
            return hydratedEntry
        }
        return entry
    }

    private func handleClose() {
        if resolvedStyle != .standaloneWindow {
            appState.highlightedEntry = nil
        }
        onClose?()
        if resolvedStyle == .sheet {
            dismiss()
        }
    }

    var body: some View {
        let current = displayEntry
        let isTx = (current.type == "transaction")
        let txId = Int(current.associatedTransactionId ?? Int64(current.id))
        let matchingTx = isTx ? appState.transactionById[txId] : nil

        Group {
            if resolvedStyle == .inspector {
                inspectorBody(current: current, isTx: isTx, matchingTx: matchingTx)
            } else {
                modalOrWindowBody(current: current, isTx: isTx, matchingTx: matchingTx)
            }
        }
        .background(ArchivePalette.archivePaper)
        .task(id: entry.id) {
            hydratedEntry = nil
            guard resolvedStyle == .inspector,
                  entry.id > 0,
                  entry.type != "transaction",
                  !appState.entries.contains(where: { $0.id == entry.id }) else { return }
            if let remote = try? await APIClient.shared.fetchEntry(id: entry.id) {
                hydratedEntry = remote
            }
        }
    }

    // MARK: - 原生三栏 Inspector 布局（300–520pt 窄栏自适应，无 .cancelAction 冲突）

    private func inspectorBody(current: LifeEntry, isTx: Bool, matchingTx: Transaction?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    badgeTag(for: current)

                    if current.isPrivate {
                        privateTag
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 2) {
                        if appState.isPaired && (current.id > 0 || (isTx && matchingTx != nil)) {
                            if isTx {
                                if let tx = matchingTx {
                                    PaperIconButton(
                                        systemName: ArchiveIcon.edit.systemName,
                                        label: "编辑账目",
                                        size: 11,
                                        tint: ArchivePalette.inkSecondary
                                    ) {
                                        onEditTransaction(tx)
                                    }
                                    PaperIconButton(
                                        systemName: ArchiveIcon.delete.systemName,
                                        label: "删除账目",
                                        size: 11,
                                        tint: ArchivePalette.accentWarm
                                    ) {
                                        appState.askConfirm(
                                            title: ArchiveSharedCopy.transactionDeleteTitle,
                                            message: ArchiveSharedCopy.transactionDeleteMessage,
                                            confirmText: ArchiveSharedCopy.transactionDeleteConfirmText,
                                            danger: true
                                        ) {
                                            onDeleteTransaction(tx)
                                        }
                                    }
                                }
                            } else {
                                if current.id > 0 {
                                    PaperIconButton(
                                        systemName: ArchiveIcon.edit.systemName,
                                        label: "编辑手稿",
                                        size: 11,
                                        tint: ArchivePalette.inkSecondary
                                    ) {
                                        onEditEntry(current)
                                    }
                                    PaperIconButton(
                                        systemName: current.isPrivate ? "lock.open" : "lock.fill",
                                        label: current.isPrivate ? "设为公开可见" : "设为仅自己可见",
                                        size: 11,
                                        tint: current.isPrivate ? ArchivePalette.accentWarm : ArchivePalette.inkSecondary
                                    ) {
                                        appState.toggleEntryPrivacy(current)
                                    }
                                }
                                PaperIconButton(
                                    systemName: "macwindow.badge.plus",
                                    label: "在新窗口打开",
                                    size: 11,
                                    tint: ArchivePalette.inkSecondary
                                ) {
                                    if let onOpenInNewWindow {
                                        onOpenInNewWindow(current)
                                    } else {
                                        appState.detailWindowEntry = current
                                    }
                                }
                                PaperIconButton(
                                    systemName: ArchiveIcon.delete.systemName,
                                    label: "删除记录",
                                    size: 11,
                                    tint: ArchivePalette.accentWarm
                                ) {
                                    appState.askConfirm(
                                        title: ArchiveSharedCopy.entryDeleteTitle,
                                        message: ArchiveSharedCopy.entryDeleteMessage,
                                        confirmText: ArchiveSharedCopy.entryDeleteConfirmText,
                                        danger: true
                                    ) {
                                        appState.deleteEntryAction(current)
                                    }
                                }
                            }
                        }

                        PaperIconButton(
                            systemName: ArchiveIcon.close.systemName,
                            label: "收起检视器",
                            size: 11,
                            tint: ArchivePalette.inkMuted
                        ) {
                            handleClose()
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text(current.parsedDate.dotDateTime)
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)

                    let trimmedLocation = current.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !trimmedLocation.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: ArchiveIcon.location.systemName)
                                .font(.system(size: 9.5))
                            Text(trimmedLocation)
                                .font(ArchiveTypography.monoScale(size: 11))
                                .lineLimit(1)
                        }
                        .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }
            }

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.7))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let tx = matchingTx {
                        transactionDetailContent(tx)
                    } else {
                        if current.hasDistinctTitle {
                            Text(current.title)
                                .font(ArchiveTypography.editorialSerif(size: 18, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                                .textSelection(.enabled)
                        }

                        if !current.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            EditorialProseTextView(
                                current.content,
                                font: ArchiveTypography.bodySans(size: 13.5),
                                color: ArchivePalette.inkPrimary,
                                lineSpacing: 5
                            )
                            .textSelection(.enabled)
                        }

                        if !current.attachments.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(current.attachments) { att in
                                    if let url = att.resolvedDisplayURL(preferThumbnail: true) {
                                        FilmFrameView(
                                            imageURL: url,
                                            originalURL: att.resolvedDisplayURL(preferThumbnail: false),
                                            preferredFilename: att.originalFilename,
                                            intrinsicSize: att.intrinsicSize,
                                            caption: current.title.isEmpty ? att.originalFilename : current.title,
                                            metaText: current.parsedDate.dotDate,
                                            maxHeight: 240
                                        ) {
                                            if let onOpenAttachment {
                                                onOpenAttachment(att)
                                            } else {
                                                appState.lightboxAttachment = att
                                            }
                                        } onExportNotice: { message in
                                            appState.showTemporaryBanner(message)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - 独立窗口 / 弹窗布局

    private func modalOrWindowBody(current: LifeEntry, isTx: Bool, matchingTx: Transaction?) -> some View {
        let standalone = (resolvedStyle == .standaloneWindow)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                badgeTag(for: current)

                if current.isPrivate {
                    privateTag
                }

                Text(current.parsedDate.dotDateTime)
                    .font(ArchiveTypography.monoScale(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                Spacer()
                if appState.isPaired && (current.id > 0 || (isTx && matchingTx != nil)) {
                    if isTx {
                        if let tx = matchingTx {
                            Button("编辑账目") {
                                if !standalone { handleClose() }
                                onEditTransaction(tx)
                            }
                            .font(ArchiveTypography.bodySans(size: 12))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .buttonStyle(.plain)
                            .paperButtonFocusRing(cornerRadius: 4)

                            Button("删除账目") {
                                if standalone {
                                    onDeleteTransaction(tx)
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
                            let target = current
                            if !standalone { handleClose() }
                            onEditEntry(target)
                        }
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .buttonStyle(.plain)
                        .paperButtonFocusRing(cornerRadius: 4)

                        Button("删除记录") {
                            if let onDeleteEntryOverride {
                                onDeleteEntryOverride(current)
                            } else {
                                appState.askConfirm(
                                    title: ArchiveSharedCopy.entryDeleteTitle,
                                    message: ArchiveSharedCopy.entryDeleteMessage,
                                    confirmText: ArchiveSharedCopy.entryDeleteConfirmText,
                                    danger: true
                                ) {
                                    handleClose()
                                    appState.deleteEntryAction(current)
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
                transactionDetailContent(tx)
            } else {
                let trimmedLocation = current.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !trimmedLocation.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: ArchiveIcon.location.systemName)
                            .font(.system(size: 10))
                        Text(trimmedLocation)
                            .font(ArchiveTypography.monoScale(size: 11))
                    }
                    .foregroundStyle(ArchivePalette.inkMuted)
                }

                if current.hasDistinctTitle {
                    Text(current.title)
                        .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        EditorialProseTextView(
                            current.content,
                            font: ArchiveTypography.bodySans(size: 14),
                            color: ArchivePalette.inkPrimary,
                            lineSpacing: 5
                        )
                        .textSelection(.enabled)

                        if !current.attachments.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(current.attachments) { att in
                                        if let url = att.resolvedDisplayURL(preferThumbnail: true) {
                                            FilmFrameView(
                                                imageURL: url,
                                                originalURL: att.resolvedDisplayURL(preferThumbnail: false),
                                                preferredFilename: att.originalFilename,
                                                intrinsicSize: att.intrinsicSize,
                                                caption: current.title.isEmpty ? att.originalFilename : current.title,
                                                metaText: current.parsedDate.dotDate,
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
                .frame(minHeight: 160, maxHeight: standalone ? .infinity : 460)
            }
        }
        .padding(24)
        .frame(maxWidth: standalone ? 760 : 560, maxHeight: standalone ? .infinity : nil, alignment: .topLeading)
        .frame(maxWidth: standalone ? .infinity : nil)
    }

    private func badgeTag(for current: LifeEntry) -> some View {
        HStack(spacing: 4) {
            if current.type == EntryType.life.rawValue {
                Circle()
                    .fill(current.displayAccentColor)
                    .frame(width: 5.5, height: 5.5)
                    .accessibilityHidden(true)
            }
            Text(Self.entryTypeBadge(current))
                .font(ArchiveTypography.monoScale(size: 11, weight: .medium))
        }
        .foregroundStyle(current.displayAccentColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(current.displayAccentColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
    }

    private var privateTag: some View {
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

    private func transactionDetailContent(_ tx: Transaction) -> some View {
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
                .textSelection(.enabled)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
    }

    static func entryTypeBadge(_ entry: LifeEntry) -> String {
        entry.displayBadgeLabel
    }
}

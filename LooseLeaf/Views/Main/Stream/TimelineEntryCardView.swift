import SwiftUI
import AppKit

/// 卡片 body 求值计数器（诊断用）
enum TimelineRenderCounter {
    #if DEBUG
    nonisolated(unsafe) static var cardBodyEvaluations: Int = 0
    static func reset() { cardBodyEvaluations = 0 }
    static var value: Int { cardBodyEvaluations }
    #else
    static func reset() {}
    static var value: Int { 0 }
    #endif
}

private struct CountCardRender: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        TimelineRenderCounter.cardBodyEvaluations += 1
        #endif
        return content
    }
}

@MainActor
final class TimelineEntryActions {
    init(appState: AppState? = nil) {
        let state = appState ?? AppState.shared
        onEditEntry = { entry in state.editingEntry = entry }
        onEditTransaction = { tx in state.editingTransaction = tx }
        onOpenDetail = { entry in
            MainThreadWatchdog.shared.noteAction("点击卡片（打开详情）")
            state.highlightedEntry = entry
        }
        onOpenInNewWindow = { entry in
            state.detailWindowEntry = entry
        }
        onOpenLightbox = { attachment in state.lightboxAttachment = attachment }
        onToast = { message in state.showTemporaryBanner(message) }
        onRetrySync = { id in state.reuploadEntry(id: id) }
        onReuploadEntry = { entry in state.reuploadEntry(id: entry.id) }
        onTogglePrivacy = { entry in
            guard entry.id > 0 else { return }
            let nextPrivate = !entry.isPrivate
            Task { @MainActor in
                do {
                    _ = try await APIClient.shared.updateEntry(
                        id: entry.id,
                        UpdateEntryRequest(isPrivate: nextPrivate)
                    )
                    await state.loadEntries(forceFull: false)
                    state.showTemporaryBanner(nextPrivate ? "已设为仅自己可见（私密）" : "已恢复为随展厅公开展示")
                } catch {
                    state.showTemporaryBanner("切换私密状态失败：\(error.localizedDescription)")
                }
            }
        }
        onDeleteEntry = { entry in
            state.askConfirm(
                title: ArchiveSharedCopy.entryDeleteTitle,
                message: ArchiveSharedCopy.entryDeleteMessage,
                confirmText: ArchiveSharedCopy.entryDeleteConfirmText,
                danger: true
            ) {
                state.deleteEntryAction(entry)
            }
        }
        onDeleteTransaction = { tx in
            state.askConfirm(
                title: ArchiveSharedCopy.transactionDeleteTitle,
                message: ArchiveSharedCopy.transactionDeleteMessage,
                confirmText: ArchiveSharedCopy.transactionDeleteConfirmText,
                danger: true
            ) {
                state.deleteTransactionAction(tx)
            }
        }
    }

    var onEditEntry: (LifeEntry) -> Void = { _ in }
    var onDeleteEntry: (LifeEntry) -> Void = { _ in }
    var onEditTransaction: (Transaction) -> Void = { _ in }
    var onDeleteTransaction: (Transaction) -> Void = { _ in }
    var onOpenDetail: (LifeEntry) -> Void = { _ in }
    var onOpenInNewWindow: (LifeEntry) -> Void = { _ in }
    var onOpenLightbox: (Attachment) -> Void = { _ in }
    var onToast: (String) -> Void = { _ in }
    var onRetrySync: (Int) -> Void = { _ in }
    var onReuploadEntry: (LifeEntry) -> Void = { _ in }
    var onTogglePrivacy: (LifeEntry) -> Void = { _ in }
}

struct TimelineEntryCardView: View {
    let entry: LifeEntry
    var timeLabel: String = ""
    let transaction: Transaction?
    var isKeyboardFocused: Bool = false
    var actions: TimelineEntryActions = TimelineEntryActions()

    @State private var isHovering: Bool = false

    private var parsed: FormatUtils.ParsedBeijingDate {
        entry.parsedDate
    }

    private var typeAccentColor: Color {
        switch entry.type {
        case "travel": return ArchivePalette.accentWarm
        case "project": return ArchivePalette.spectrumStudy
        case "wish": return ArchivePalette.spectrumLeisure
        case "transaction": return ArchivePalette.spectrumDining
        default: return ArchivePalette.accentMoss
        }
    }

    private var entryTypeBadgeName: String {
        EntryType(rawValue: entry.type)?.badgeLabel ?? "日常随笔"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(ArchivePalette.borderSubtle.opacity(0.7))
                    .frame(width: 1.5)
                    .padding(.leading, 6)

                HStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(ArchivePalette.archivePaper)
                            .frame(width: 11, height: 11)
                        Circle()
                            .stroke(typeAccentColor, lineWidth: 1.5)
                            .frame(width: 11, height: 11)
                        Circle()
                            .fill(typeAccentColor)
                            .frame(width: 4.5, height: 4.5)
                    }
                    .frame(width: 13, height: 13)

                    Rectangle()
                        .fill(typeAccentColor.opacity(0.40))
                        .frame(width: 14, height: 1.5)
                }
                .padding(.top, 7)
            }
            .frame(width: 27)
            .padding(.trailing, 6)

            VStack(alignment: .leading, spacing: 9) {
                // 顶栏（双击顶栏空白处打开详情，避免与下方正文双击选词手势冲突）
                HStack(spacing: 7) {
                    Text(entryTypeBadgeName)
                        .font(ArchiveTypography.monoScale(size: 10, weight: .medium))
                        .foregroundStyle(typeAccentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(typeAccentColor.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                    if entry.isPrivate {
                        HStack(spacing: 2.5) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8.5))
                            Text("私密")
                                .font(ArchiveTypography.monoScale(size: 9.5, weight: .medium))
                        }
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(ArchivePalette.accentWarm.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                        .accessibilityLabel("仅自己可见")
                    }

                    if let loc = entry.location ?? entry.cityName, !loc.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: ArchiveIcon.location.systemName)
                                .font(.system(size: 9.5))
                            Text(loc)
                                .font(ArchiveTypography.bodySans(size: 11))
                        }
                        .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    if let tx = transaction, let badge = tx.installmentBadgeText {
                        Text(badge)
                            .font(ArchiveTypography.monoScale(size: 9.5))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(ArchivePalette.accentWarm.opacity(0.6), lineWidth: 0.5)
                            )
                    }

                    let syncState = entry.syncStatus ?? "synced"
                    if syncState == "pending_create" {
                        Text("待同步")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .accessibilityLabel("待同步到中枢")

                        Button {
                            actions.onReuploadEntry(entry)
                        } label: {
                            Text("重传")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .paperButtonFocusRing(cornerRadius: 3)
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .help("重新上传这条记录到中枢")
                        .accessibilityLabel("重新上传到中枢")
                    } else if syncState == "failed" {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                                .font(.system(size: 9.5))
                            Text("同步失败")
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                        }
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .accessibilityLabel("同步失败")

                        Button {
                            actions.onRetrySync(entry.id)
                        } label: {
                            Text("重试")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .paperButtonFocusRing(cornerRadius: 3)
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .help("重新同步到中枢")
                        .accessibilityLabel("重试同步")
                    }

                    if !timeLabel.isEmpty {
                        Text(timeLabel)
                            .font(ArchiveTypography.monoScale(size: 10.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .monospacedDigit()
                    }

                    Spacer()
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            actions.onOpenDetail(entry)
                        }

                    // 右侧操作按钮：常驻视图树保障全键盘与读屏可达，避免在高频滚动列表卡内挂载 @FocusState 造成 O(N²) 焦点图开销
                    HStack(spacing: 4) {
                        if entry.type == "transaction" {
                            if let tx = transaction {
                                cardCircleActionButton(
                                    icon: ArchiveIcon.edit.systemName,
                                    tint: ArchivePalette.inkSecondary,
                                    label: "编辑账目"
                                ) {
                                    actions.onEditTransaction(tx)
                                }

                                cardCircleActionButton(
                                    icon: ArchiveIcon.delete.systemName,
                                    tint: ArchivePalette.accentWarm,
                                    label: "删除账目"
                                ) {
                                    actions.onDeleteTransaction(tx)
                                }
                            }
                        } else {
                            if entry.id > 0 {
                                cardCircleActionButton(
                                    icon: ArchiveIcon.edit.systemName,
                                    tint: ArchivePalette.inkSecondary,
                                    label: "编辑手稿"
                                ) {
                                    actions.onEditEntry(entry)
                                }
                            }

                            cardCircleActionButton(
                                icon: ArchiveIcon.delete.systemName,
                                tint: ArchivePalette.accentWarm,
                                label: "删除手稿"
                            ) {
                                actions.onDeleteEntry(entry)
                            }
                        }

                        cardCircleActionButton(
                            icon: ArchiveIcon.detail.systemName,
                            tint: ArchivePalette.inkMuted,
                            label: "查看手稿完整详情"
                        ) {
                            actions.onOpenDetail(entry)
                        }
                    }
                    .opacity(isHovering || isKeyboardFocused ? 1 : 0.45)
                    .animation(nil, value: isHovering)
                }

                let derived = FormatUtils.derivedTitle(from: entry.content)
                if !entry.title.isEmpty && entry.title != derived {
                    Text(entry.title)
                        .font(ArchiveTypography.editorialSerif(size: 17, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .padding(.bottom, 1)
                        .onTapGesture(count: 2) {
                            actions.onOpenDetail(entry)
                        }
                }

                // 仅在聚焦/悬停卡片上挂载重型 AppKit textSelection 包装器，长列表滚动更轻盈且不抢双击选词
                if isHovering || isKeyboardFocused {
                    Text(entry.content)
                        .font(ArchiveTypography.bodySans(size: 13.5))
                        .foregroundStyle(ArchivePalette.inkPrimary.opacity(0.9))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                } else {
                    Text(entry.content)
                        .font(ArchiveTypography.bodySans(size: 13.5))
                        .foregroundStyle(ArchivePalette.inkPrimary.opacity(0.9))
                        .lineSpacing(5)
                }

                // 附件胶片相框画廊（显示走缩略图、导出走 4K 原图、占位锁定原始宽高比零跳动）
                if !entry.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(entry.attachments) { att in
                                if let url = att.resolvedDisplayURL(preferThumbnail: true) {
                                    FilmFrameView(
                                        imageURL: url,
                                        originalURL: att.resolvedDisplayURL(preferThumbnail: false),
                                        preferredFilename: att.originalFilename,
                                        intrinsicSize: att.intrinsicSize,
                                        caption: entry.title.isEmpty ? att.originalFilename : entry.title,
                                        metaText: parsed.dotDate,
                                        maxHeight: 220
                                    ) {
                                        actions.onOpenLightbox(att)
                                    } onExportNotice: { message in
                                        actions.onToast(message)
                                    }
                                    .frame(width: 260)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? typeAccentColor.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isKeyboardFocused ? ArchivePalette.accentWarm : (isHovering ? typeAccentColor.opacity(0.25) : Color.clear),
                    lineWidth: isKeyboardFocused ? 1.5 : 0.6
                )
        )
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .accessibilityAction(.default) {
            actions.onOpenDetail(entry)
        }
        .modifier(CountCardRender())
        .contextMenu {
            if entry.type == "transaction" {
                if let tx = transaction {
                    Button {
                        actions.onEditTransaction(tx)
                    } label: {
                        Label("编辑账目", systemImage: ArchiveIcon.edit.systemName)
                    }
                    Button(role: .destructive) {
                        actions.onDeleteTransaction(tx)
                    } label: {
                        Label("删除账目", systemImage: ArchiveIcon.delete.systemName)
                    }
                    Divider()
                    Button {
                        SecureClipboard.copy(FormatUtils.formattedYuan(cents: tx.amount))
                        actions.onToast("已拷贝金额至剪贴板")
                    } label: {
                        Label("拷贝金额", systemImage: "doc.on.doc")
                    }
                    Button {
                        SecureClipboard.copy(tx.title.isEmpty ? tx.category : tx.title)
                        actions.onToast("已拷贝账目摘要至剪贴板")
                    } label: {
                        Label("拷贝账目摘要", systemImage: "text.quote")
                    }
                }
            } else {
                Button {
                    actions.onOpenDetail(entry)
                } label: {
                    Label("查看手稿详情", systemImage: "book.pages")
                }
                Button {
                    actions.onOpenInNewWindow(entry)
                } label: {
                    Label("在新窗口打开", systemImage: "macwindow.badge.plus")
                }
                if entry.id > 0 {
                    Button {
                        actions.onEditEntry(entry)
                    } label: {
                        Label("编辑手稿", systemImage: ArchiveIcon.edit.systemName)
                    }
                    Button {
                        actions.onTogglePrivacy(entry)
                    } label: {
                        Label(
                            entry.isPrivate ? "设为公开可见" : "设为仅自己可见（私密）",
                            systemImage: entry.isPrivate ? "lock.open" : "lock.fill"
                        )
                    }
                }
                Button(role: .destructive) {
                    actions.onDeleteEntry(entry)
                } label: {
                    Label("删除手稿", systemImage: ArchiveIcon.delete.systemName)
                }
                Divider()
                Button {
                    SecureClipboard.copy(entry.content)
                    actions.onToast("已拷贝手稿正文至剪贴板")
                } label: {
                    Label("拷贝手稿正文", systemImage: "doc.on.doc")
                }
                Button {
                    let md = ArchiveExporter.makeMarkdown(entries: [entry])
                    SecureClipboard.copy(md)
                    actions.onToast("已拷贝 Markdown 格式至剪贴板")
                } label: {
                    Label("拷贝 Markdown 格式", systemImage: "text.alignleft")
                }
                Button {
                    SecureClipboard.copy(parsed.dotDateTime)
                    actions.onToast("已拷贝时间戳至剪贴板")
                } label: {
                    Label("拷贝时间戳", systemImage: "clock")
                }
            }
        }
    }

    private func cardCircleActionButton(
        icon: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: ArchiveHitTarget.minPointer, height: ArchiveHitTarget.minPointer)
                .background(ArchivePalette.archiveSubtle.opacity(0.85))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .paperButtonFocusRing(cornerRadius: 14)
        .help(label)
        .accessibilityLabel(label)
    }
}

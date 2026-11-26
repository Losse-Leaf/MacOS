import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// 菜单栏极速闪念与记账悬浮窗 (QuickCaptureView)
/// 严格遵循 docs/macos.md §3.1 规范：
/// 1. 宽 380px，高自适应（440~580pt；窄高度下内部滚动 + 固定操作条，展开日历不裁切）
/// 2. 顶部切换「极速记录」与「快速记账」，草稿状态统一由 `QuickCaptureDraft` 跨宿主托管
/// 3. 复用 `EntryMediaState` 作为唯一相纸装裱管线，支持单张进度、失败重试与聚焦文本框内 `⌘V` 直贴截图
/// 4. `ESC`、提交回执与展开主工作台同时兼容悬浮 `NSPanel` 与系统 `MenuBarExtra` 自动收起
@MainActor
public struct QuickCaptureView: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    var onClosePopover: (() -> Void)?

    public typealias CaptureTab = QuickCaptureTab

    @State private var isDragTargeted: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?
    @State private var successText: String?
    @State private var isExitRequested: Bool = false

    @FocusState private var isContentFocused: Bool
    @FocusState private var isTitleFocused: Bool

    public init(appState: AppState, onClosePopover: (() -> Void)? = nil) {
        self.appState = appState
        self.onClosePopover = onClosePopover
    }

    private func closePanel() {
        if let onClosePopover {
            onClosePopover()
        } else {
            dismiss()
        }
    }

    private var allUploadedAttachments: [Attachment] {
        appState.quickDraft.media.uploadedAttachments
    }

    private var effectiveCameraLine: String {
        appState.quickDraft.media.extractedCameraLine
    }

    public var body: some View {
        @Bindable var draft = appState.quickDraft
        return ZStack {
            NoiseBackground(useSubtleSurface: false, enableVibrancy: true)

            VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                // 1. 顶部栏（铺设专属拖拽热区，防止误拖下方表单胶囊）
                headerBar
                    .background(WindowDragHandleView())

                // 2. 全局提示（本面板已有就地回执时不再重复展示）
                if let banner = appState.statusBanner, successText == nil {
                    QuickFeedbackStrip(icon: "checkmark.circle.fill", text: banner, tint: ArchivePalette.accentMoss)
                }

                // 3. 主体内容区（切换 Tab 不丢失任何输入，均由 QuickCaptureDraft 托管）
                if draft.activeTab == .thought {
                    thoughtCaptureSection
                } else {
                    QuickLedgerView(appState: appState) {
                        closePanel()
                    }
                }

                Divider()
                    .overlay(ArchivePalette.borderSubtle)

                // 4. 底栏：状态印记与展开主工作台入口
                footerBar
            }
            .padding(ArchiveSpacing.m)
        }
        .frame(width: 380)
        .frame(minHeight: 440, maxHeight: 580)
        .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDragTargeted) { providers in
            guard appState.quickDraft.activeTab == .thought else { return false }
            return appState.quickDraft.media.handleDrop(providers: providers)
        }
        .onPasteImageShortcut {
            guard appState.quickDraft.activeTab == .thought else { return }
            appState.quickDraft.media.paste(providers: [])
            isTitleFocused = true
        }
        .onAppear {
            if appState.quickDraft.activeTab == .thought {
                isContentFocused = true
            }
            consumePendingCaptureText()
        }
        .onChange(of: appState.pendingCaptureText) { _, _ in
            consumePendingCaptureText()
        }
        .onExitCommand {
            handleExitCommand()
        }
    }

    // MARK: - 顶部切换栏

    private var headerBar: some View {
        HStack(spacing: ArchiveSpacing.s) {
            HStack(spacing: ArchiveSpacing.xs) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.accentMoss)
                    .accessibilityHidden(true)
                Text(appState.siteConfig.siteName.isEmpty ? "散页 · 伴随记录" : appState.siteConfig.siteName)
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.heading, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if !appState.outboxItems.isEmpty {
                Text("待同步 \(appState.outboxItems.count)")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .padding(.horizontal, ArchiveSpacing.xs)
                    .padding(.vertical, ArchiveSpacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                            .stroke(ArchivePalette.accentWarm, lineWidth: 0.5)
                    )
            }

            HStack(spacing: ArchiveSpacing.xs) {
                ForEach(CaptureTab.allCases, id: \.rawValue) { tab in
                    PaperPillButton(
                        title: tab.rawValue,
                        isSelected: appState.quickDraft.activeTab == tab
                    ) {
                        appState.quickDraft.activeTab = tab
                    }
                }
            }
        }
    }

    // MARK: - 极速闪念记录区域

    private var thoughtCaptureSection: some View {
        @Bindable var draft = appState.quickDraft
        return VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                    entryCategoryCapsules
                    titleField
                    contentEditor
                    exifStrip
                    miniDarkroomDropSlot
                }
                .padding(.bottom, ArchiveSpacing.xs)
            }
            .frame(minHeight: 190)

            thoughtActionBar

            if draft.showBackdatePicker {
                HStack(spacing: ArchiveSpacing.s) {
                    PaperDateTimePicker(selection: $draft.occurredAt, showQuickShortcuts: true)
                    Spacer(minLength: 0)
                }
            }

            feedbackBar
        }
        .frame(maxHeight: .infinity)
    }

    private var entryCategoryCapsules: some View {
        @Bindable var draft = appState.quickDraft
        return EntryCategoryPickerRow(selection: $draft.category, isCompact: true)
    }

    private var titleField: some View {
        @Bindable var draft = appState.quickDraft
        return TextField("标题", text: $draft.titleText)
            .textFieldStyle(.plain)
            .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.heading, weight: .medium))
            .foregroundStyle(ArchivePalette.inkPrimary)
            .focused($isTitleFocused)
            .padding(.horizontal, ArchiveSpacing.s)
            .padding(.vertical, ArchiveSpacing.xs)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
            )
            .accessibilityLabel("标题")
    }

    private var contentEditor: some View {
        @Bindable var draft = appState.quickDraft
        return TextField("写下此刻闪念，按 ⌘ + Return 即刻归档…", text: $draft.contentText, axis: .vertical)
            .accessibilityLabel("闪念正文")
            .textFieldStyle(.plain)
            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
            .foregroundStyle(ArchivePalette.inkPrimary)
            .lineLimit(5...12)
            .frame(minHeight: 84, alignment: .topLeading)
            .focused($isContentFocused)
            .padding(ArchiveSpacing.s)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
            )
            .onPasteCommand(of: [.png, .tiff, .jpeg, .fileURL, .image]) { providers in
                appState.quickDraft.media.paste(providers: providers)
                isTitleFocused = true
            }
    }

    private var exifStrip: some View {
        let cameraLine = effectiveCameraLine
        return Group {
            if !cameraLine.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ArchiveSpacing.xs) {
                        Text(cameraLine)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .padding(.horizontal, ArchiveSpacing.xs)
                            .padding(.vertical, ArchiveSpacing.xxs)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    }
                }
            }
        }
    }

    private var thoughtActionBar: some View {
        @Bindable var draft = appState.quickDraft
        let media = draft.media
        return HStack(spacing: ArchiveSpacing.s) {
            Button {
                draft.showBackdatePicker.toggle()
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(draft.showBackdatePicker ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                    .padding(ArchiveSpacing.xs)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
            .accessibilityLabel("补记历史时刻")
            .help("补记过去的时刻")

            Button {
                draft.isPrivate.toggle()
            } label: {
                Image(systemName: draft.isPrivate ? "lock.fill" : "lock.open")
                    .font(.system(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(draft.isPrivate ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                    .padding(ArchiveSpacing.xs)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
            .accessibilityLabel(draft.isPrivate ? "仅自己可见（私密）" : "公开可见（含图自动同步至 Vesper Space）")
            .accessibilityAddTraits(draft.isPrivate ? .isSelected : AccessibilityTraits())
            .help(draft.isPrivate ? "已设为仅自己可见（私密）" : "设为仅自己可见（私密）")

            Spacer(minLength: 0)

            Button {
                submitThought()
            } label: {
                HStack(spacing: ArchiveSpacing.xs) {
                    Image(systemName: "paperplane")
                        .font(.system(size: ArchiveTypography.Scale.caption))
                    Text(isSubmitting ? "归档中…" : "归档 ⌘↩")
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .paperButtonFocusRing()
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(draft.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && allUploadedAttachments.isEmpty || isSubmitting || media.isUploading)
            .accessibilityLabel("归档本条闪念")
        }
    }

    // MARK: - 迷你拖拽暗房槽位（统一委托 EntryMediaState）

    private var miniDarkroomDropSlot: some View {
        let media = appState.quickDraft.media
        return HStack(spacing: ArchiveSpacing.s) {
            Image(systemName: media.isUploading ? "arrow.triangle.2.circlepath.camera" : "photo.badge.plus")
                .font(.system(size: ArchiveTypography.Scale.heading))
                .foregroundStyle(isDragTargeted ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                .accessibilityHidden(true)

            if media.isUploading {
                Text("正在冲印上传 (\(Int(media.overallProgress * 100))%)…")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                Spacer(minLength: 0)
            } else if !media.items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ArchiveSpacing.xs) {
                        ForEach(media.items) { item in
                            HStack(spacing: ArchiveSpacing.xs) {
                                if let thumb = item.localThumbnail {
                                    Image(nsImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 18, height: 18)
                                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                } else if let att = item.attachment, let url = att.resolvedDisplayURL(preferThumbnail: true) {
                                    CachedFilmImageView(url: url, maxHeight: 18, intrinsicSize: att.intrinsicSize)
                                        .frame(width: 18, height: 18)
                                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                }
                                Text(item.displayName)
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                    .foregroundStyle(item.status == .failed ? ArchivePalette.accentWarm : ArchivePalette.inkPrimary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 80)

                                if item.status == .failed {
                                    Button {
                                        media.retry(item)
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: ArchiveTypography.Scale.micro, weight: .semibold))
                                            .foregroundStyle(ArchivePalette.accentWarm)
                                            .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("重试上传 \(item.displayName)")
                                }

                                Button {
                                    media.remove(item)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: ArchiveTypography.Scale.micro, weight: .bold))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                        .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("移除附件 \(item.displayName)")
                                .help("移除该附件")
                            }
                            .padding(.horizontal, ArchiveSpacing.xs)
                            .padding(.vertical, ArchiveSpacing.xxs)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(
                                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                    .stroke(item.status == .failed ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                        }
                    }
                }
                Spacer(minLength: ArchiveSpacing.xs)
                Button("清空") {
                    media.removeAll()
                }
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                .buttonStyle(.plain)
                .paperButtonFocusRing(cornerRadius: 3)
                .foregroundStyle(ArchivePalette.inkMuted)
                .accessibilityLabel("清空全部附件")
            } else {
                Text("拖拽或 ⌘V 粘贴照片自动装裱")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
                Spacer(minLength: ArchiveSpacing.xs)
                Button("粘贴图片") {
                    media.paste(providers: [])
                    isTitleFocused = true
                }
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro, weight: .medium))
                .buttonStyle(.plain)
                .paperButtonFocusRing(cornerRadius: 3)
                .foregroundStyle(ArchivePalette.accentWarm)
                .accessibilityLabel("粘贴剪贴板图片")
            }
        }
        .padding(.horizontal, ArchiveSpacing.s)
        .padding(.vertical, ArchiveSpacing.xs)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                .strokeBorder(
                    isDragTargeted ? ArchivePalette.accentWarm : ArchivePalette.borderDivider,
                    style: StrokeStyle(lineWidth: isDragTargeted ? 1.0 : 0.5, dash: [4, 3])
                )
        )
    }

    // MARK: - 底部工具栏

    private var footerBar: some View {
        let badge = appState.hubConnectionBadgeState
        return HStack(spacing: ArchiveSpacing.s) {
            HStack(spacing: ArchiveSpacing.xs) {
                if differentiateWithoutColor {
                    Image(systemName: badge.symbolName)
                        .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(badge.dotColor)
                        .accessibilityHidden(true)
                } else {
                    Circle()
                        .fill(badge.dotColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(badge.label)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                appState.activeSection = .stream
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                closePanel()
            } label: {
                HStack(spacing: ArchiveSpacing.xs) {
                    Image(systemName: "macwindow")
                        .font(.system(size: ArchiveTypography.Scale.caption))
                    Text("展开主工作台")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                }
                .foregroundStyle(ArchivePalette.inkSecondary)
                .frame(minHeight: ArchiveHitTarget.minPointer)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
            .accessibilityLabel("展开主工作台")

            PaperIconButton(
                systemName: "gearshape",
                label: "偏好设置",
                help: "打开偏好设置 (⌘,)",
                size: ArchiveTypography.Scale.body,
                tint: ArchivePalette.inkMuted
            ) {
                appState.navigation.settingsSelectedTab = .general
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
                closePanel()
            }
        }
    }

    // MARK: - 反馈条

    @ViewBuilder
    private var feedbackBar: some View {
        if let err = errorText ?? appState.quickDraft.media.errorMessage {
            QuickFeedbackStrip(icon: "exclamationmark.triangle.fill", text: err, tint: ArchivePalette.accentWarm)
        } else if let successText {
            QuickFeedbackStrip(icon: "checkmark.circle.fill", text: successText, tint: ArchivePalette.accentMoss)
        }
    }

    // MARK: - 提交与收起

    private func consumePendingCaptureText() {
        guard let pending = appState.pendingCaptureText, !pending.isEmpty else { return }
        if appState.quickDraft.contentText.isEmpty {
            appState.quickDraft.contentText = pending
        } else {
            appState.quickDraft.contentText += "\n\n" + pending
        }
        appState.quickDraft.activeTab = .thought
        appState.pendingCaptureText = nil
        isContentFocused = true
    }

    private func handleExitCommand() {
        guard !isExitRequested else { return }
        isExitRequested = true
        closePanel()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            isExitRequested = false
        }
    }

    private func submitThought() {
        let draft = appState.quickDraft
        let attachments = allUploadedAttachments
        let cameraLine = effectiveCameraLine
        var finalContent = draft.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalContent.isEmpty && !attachments.isEmpty {
            finalContent = cameraLine.isEmpty ? "相纸影像归档" : cameraLine
        }
        guard !finalContent.isEmpty, !isSubmitting else { return }

        if !cameraLine.isEmpty && !finalContent.contains(cameraLine) {
            finalContent += "\n\n> \(cameraLine)"
        }

        let contentToSubmit = finalContent
        isSubmitting = true
        errorText = nil
        successText = nil

        Task { @MainActor in
            do {
                let queuedOffline = try await appState.submitQuickCapture(
                    title: draft.titleText,
                    content: contentToSubmit,
                    type: .life,
                    category: draft.category,
                    attachmentIds: attachments.map(\.id),
                    attachments: attachments,
                    occurredAt: FormatUtils.beijingISOString(from: draft.occurredAt),
                    isPrivate: draft.isPrivate
                )
                draft.resetThought()
                isSubmitting = false
                presentSuccess(
                    queuedOffline
                        ? "已暂存至本地发件箱，网络恢复后自动同步"
                        : "已归入散页时间流"
                )
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private func presentSuccess(_ message: String) {
        successText = message
        errorText = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard successText == message else { return }
            successText = nil
            closePanel()
        }
    }
}

// MARK: - 共享就地反馈条 (QuickFeedbackStrip)

struct QuickFeedbackStrip: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: ArchiveSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: ArchiveTypography.Scale.caption))
                .foregroundStyle(tint)
            Text(text)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ArchiveSpacing.s)
        .padding(.vertical, ArchiveSpacing.xs)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 预览 (Preview)

#if DEBUG
@MainActor
private enum QuickCapturePreviewData {
    static func makeSample(tab: QuickCaptureTab) -> AppState {
        let state = AppState.shared
        state.expenseCategories = ["餐饮", "交通", "购物", "数码器材", "娱乐", "住房"]
        state.incomeCategories = ["工资收入", "二手回血", "稿酬设计", "投资理财"]
        state.paymentMethods = ["微信支付", "支付宝", "银行卡", "现金"]
        state.quickDraft.activeTab = tab
        state.quickDraft.titleText = "午后抄书"
        state.quickDraft.contentText = "午后的光落在旧书页上，忽然想把它抄进这本散页里。"
        return state
    }
}

#Preview("极速闪念面板") {
    QuickCaptureView(appState: QuickCapturePreviewData.makeSample(tab: .thought))
        .frame(width: 380, height: 460)
}

#Preview("快速记账面板") {
    QuickCaptureView(appState: QuickCapturePreviewData.makeSample(tab: .ledger))
        .frame(width: 380, height: 460)
}
#endif

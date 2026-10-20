import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// 菜单栏极速闪念与记账悬浮窗 (QuickCaptureView)
/// 严格遵循 docs/macos.md §3.1 规范：
/// 1. 宽 380px，高自适应（上限 460px；窄高度下内部滚动 + 固定操作条，绝不溢出）
/// 2. 顶部切换「极速记录」与「快速记账」
/// 3. 自动识别 #标签、支持拖拽相片自动提取 EXIF 直传 R2
/// 4. Cmd + Enter 即刻落库，提交结果在面板内就地反馈（菜单栏窗口看不到全局横幅）
/// 5. ESC 收起统一由视图层处理，避免与 AppKit `cancelOperation` 双重触发
/// 跨并发边界共享的进度计数器（避免可变局部变量被捕获进 @Sendable 闭包）
final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Double = 0
    var value: Double {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}

@MainActor
public struct QuickCaptureView: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow
    var onClosePopover: (() -> Void)?

    public typealias CaptureTab = QuickCaptureTab

    // 暗房相片拖拽与上传状态（临时会话态）
    @State private var isDragTargeted: Bool = false
    @State private var isUploadingPhoto: Bool = false
    @State private var uploadProgress: Double = 0.0
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?
    /// 提交成功后的面板内确认文案（就地反馈，不依赖全局横幅）
    @State private var successText: String?
    /// ESC 去重标记：一次按键只允许触发一次收起
    @State private var isExitRequested: Bool = false

    @FocusState private var isContentFocused: Bool
    /// 标题输入框焦点（粘贴图片成功后自动聚焦）
    @FocusState private var isTitleFocused: Bool

    public init(appState: AppState, onClosePopover: (() -> Void)? = nil) {
        self.appState = appState
        self.onClosePopover = onClosePopover
    }

    public var body: some View {
        @Bindable var draft = appState.quickDraft
        return ZStack {
            NoiseBackground(useSubtleSurface: false, enableVibrancy: true)

            VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                // 1. 顶部栏：品牌印记 + 模式切换 + 离线队列指示
                headerBar

                // 2. 全局提示（同步 / 配对等跨模块动作的即时回执）
                // 本面板已有就地成功回执时不再重复展示全局横幅，避免同一句话出现两次
                if let banner = appState.statusBanner, successText == nil {
                    feedbackStrip(icon: "checkmark.circle.fill", text: banner, tint: ArchivePalette.accentMoss)
                }

                // 3. 主体内容区（各 Tab 自行管理「可滚动区 + 固定操作条」）
                if draft.activeTab == .thought {
                    thoughtCaptureSection
                } else {
                    QuickLedgerView(appState: appState) {
                        onClosePopover?()
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
        .frame(maxHeight: 460)
        .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        .onAppear {
            isContentFocused = true
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
            // 1. 可滚动输入区（窄高度下由滚动承载，不撑破面板）
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                    entryTypeCapsules
                    titleField
                    contentEditor
                    exifStrip
                    miniDarkroomDropSlot
                }
                .padding(.bottom, ArchiveSpacing.xs)
            }
            .frame(minHeight: 190)

            // 2. 固定操作条：地点 / 补记 / 精选 / 归档（始终可见，不随滚动移出视野）
            thoughtActionBar

            // 3. 补记时刻弹层
            if draft.showBackdatePicker {
                HStack(spacing: ArchiveSpacing.s) {
                    PaperDateTimePicker(selection: $draft.occurredAt, showQuickShortcuts: true)
                    Spacer(minLength: 0)
                }
            }

            // 4. 就地反馈（错误 / 成功确认，紧贴提交按钮）
            feedbackBar
        }
        .frame(maxHeight: .infinity)
    }

    /// 形态选择胶囊（日常 / 游历 / 造物 / 心愿 / 账目）
    private var entryTypeCapsules: some View {
        @Bindable var draft = appState.quickDraft
        return HStack(spacing: ArchiveSpacing.xs) {
            ForEach(EntryType.allCases) { kind in
                PaperPillButton(
                    title: kind.label,
                    icon: kind.symbolName,
                    isSelected: draft.entryType == kind
                ) {
                    draft.entryType = kind
                }
            }
        }
    }

    /// 可选标题行（粘贴图片后自动聚焦此处）
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

    /// 正文 Markdown 输入框
    /// 采用垂直 TextField 彻底根治中文拼音预输入与占位文字重叠 BUG
    private var contentEditor: some View {
        @Bindable var draft = appState.quickDraft
        return TextField("写下此刻闪念，按 ⌘ + Return 即刻归档…", text: $draft.contentText, axis: .vertical)
            .textFieldStyle(.plain)
            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
            .foregroundStyle(ArchivePalette.inkPrimary)
            .lineLimit(4...7)
            .focused($isContentFocused)
            .padding(ArchiveSpacing.s)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
            )
            .accessibilityLabel("正文")
            .onPasteCommand(of: [.png, .tiff, .jpeg, .fileURL, .image]) { providers in
                handlePasteCommand(providers)
            }
    }

    /// EXIF 相机印记展示
    private var exifStrip: some View {
        Group {
            if !appState.quickDraft.extractedCameraLine.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ArchiveSpacing.xs) {
                        Text(appState.quickDraft.extractedCameraLine)
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

    /// 固定操作条（地点 / 补记 / 精选 / 归档）
    private var thoughtActionBar: some View {
        @Bindable var draft = appState.quickDraft
        return HStack(spacing: ArchiveSpacing.s) {
            PaperCityPicker(
                selectedCode: $draft.selectedCityCode,
                selectedName: $draft.selectedCityName,
                placeholder: appState.profile.displayCity.isEmpty ? "点选城市" : appState.profile.displayCity
            )

            // 补记历史时刻（命中区不小于 28pt）
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
            .accessibilityLabel("补记历史时刻")
            .help("补记过去的时刻")

            // 精选印记开关（命中区不小于 28pt）
            Button {
                draft.isFeatured.toggle()
            } label: {
                Image(systemName: draft.isFeatured ? "star.fill" : "star")
                    .font(.system(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(draft.isFeatured ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                    .padding(ArchiveSpacing.xs)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(draft.isFeatured ? "取消精选印记" : "标记为精选印记")
            .accessibilityValue(draft.isFeatured ? "已精选" : "未精选")
            .help("标记为精选印记")

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
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(draft.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.uploadedAttachments.isEmpty || isSubmitting || isUploadingPhoto)
            .accessibilityLabel("归档本条闪念")
        }
    }

    // MARK: - 迷你拖拽暗房槽位

    private var miniDarkroomDropSlot: some View {
        HStack(spacing: ArchiveSpacing.s) {
            Image(systemName: isUploadingPhoto ? "arrow.triangle.2.circlepath.camera" : "photo.badge.plus")
                .font(.system(size: ArchiveTypography.Scale.heading))
                .foregroundStyle(isDragTargeted ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                .accessibilityHidden(true)

            if isUploadingPhoto {
                Text("正在上传相片 (\(Int(uploadProgress * 100))%)…")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                Spacer(minLength: 0)
            } else if !appState.quickDraft.uploadedAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ArchiveSpacing.xs) {
                        ForEach(appState.quickDraft.uploadedAttachments) { att in
                            HStack(spacing: ArchiveSpacing.xs) {
                                if let url = APIClient.shared.resolveMediaURL(att.url) {
                                    CachedFilmImageView(url: url, maxHeight: 18)
                                        .frame(width: 18, height: 18)
                                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                }
                                Text(att.originalFilename)
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 80)
                                Button {
                                    appState.quickDraft.uploadedAttachments.removeAll { $0.id == att.id }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: ArchiveTypography.Scale.micro, weight: .bold))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                        .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("移除附件 \(att.originalFilename)")
                                .help("移除该附件")
                            }
                            .padding(.horizontal, ArchiveSpacing.xs)
                            .padding(.vertical, ArchiveSpacing.xxs)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(
                                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                        }
                    }
                }
                Spacer(minLength: ArchiveSpacing.xs)
                Button("清空") {
                    appState.quickDraft.uploadedAttachments.removeAll()
                    appState.quickDraft.extractedCameraLine = ""
                }
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                .buttonStyle(.plain)
                .foregroundStyle(ArchivePalette.inkMuted)
                .accessibilityLabel("清空全部附件")
            } else {
                Text("拖拽照片至此，自动装裱保存")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
                Spacer(minLength: ArchiveSpacing.xs)
                Button("粘贴剪贴板图片 (⌘V)") {
                    pasteImageFromPasteboard()
                }
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(ArchivePalette.accentWarm)
                .keyboardShortcut("v", modifiers: [.command])
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
        .onDrop(of: [.fileURL, .image], isTargeted: $isDragTargeted) { providers in
            handlePhotoDrop(providers: providers)
            return true
        }
    }

    // MARK: - 底部工具栏

    private var footerBar: some View {
        HStack(spacing: ArchiveSpacing.s) {
            HStack(spacing: ArchiveSpacing.xs) {
                Circle()
                    .fill(!appState.isOnline ? ArchivePalette.accentWarm : (appState.isPaired ? ArchivePalette.accentMoss : ArchivePalette.accentWarm))
                    .frame(width: 6, height: 6)
                Text(!appState.isOnline ? "离线暂存 (待同步 \(appState.outboxItems.count))" : (appState.isPaired ? "已接入数据中枢" : "待绑定中枢"))
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                appState.activeSection = .stream
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                onClosePopover?()
            } label: {
                HStack(spacing: ArchiveSpacing.xs) {
                    Image(systemName: "macwindow")
                        .font(.system(size: ArchiveTypography.Scale.caption))
                    Text("展开主工作台")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                }
                .foregroundStyle(ArchivePalette.inkSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("展开主工作台")

            PaperIconButton(
                systemName: "gearshape",
                label: "偏好设置",
                help: "偏好设置",
                size: ArchiveTypography.Scale.body,
                tint: ArchivePalette.inkMuted
            ) {
                appState.activeSection = .preferences
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                onClosePopover?()
            }
        }
    }

    // MARK: - 反馈条（错误与成功确认）

    /// 提交或上传的失败原因 / 成功回执，始终贴在操作条下方，用户无需滚动即可看到
    @ViewBuilder
    private var feedbackBar: some View {
        if let errorText {
            feedbackStrip(icon: "exclamationmark.triangle.fill", text: errorText, tint: ArchivePalette.accentWarm)
        } else if let successText {
            feedbackStrip(icon: "checkmark.circle.fill", text: successText, tint: ArchivePalette.accentMoss)
        }
    }

    /// 统一反馈条样式（错误暖色 / 成功苔绿）
    private func feedbackStrip(icon: String, text: String, tint: Color) -> some View {
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

    // MARK: - 提交与照片拖拽处理

    /// 消费系统「服务」菜单摘录的待归档文本（预填正文并聚焦）
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

    /// ESC 收起：视图层唯一处理入口
    /// 去重标记吸收 AppKit `cancelOperation` 可能带来的二次触发，保证一次按键只收起一次
    private func handleExitCommand() {
        guard !isExitRequested else { return }
        isExitRequested = true
        onClosePopover?()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            isExitRequested = false
        }
    }

    /// 提交闪念：落库成功后在面板内给出确认回执（菜单栏窗口看不到全局横幅）
    private func submitThought() {
        let draft = appState.quickDraft
        var finalContent = draft.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalContent.isEmpty && !draft.uploadedAttachments.isEmpty {
            finalContent = draft.extractedCameraLine.isEmpty ? "暗房胶片冲印归档" : draft.extractedCameraLine
        }
        guard !finalContent.isEmpty, !isSubmitting else { return }

        if !draft.extractedCameraLine.isEmpty && !finalContent.contains(draft.extractedCameraLine) {
            finalContent += "\n\n> \(draft.extractedCameraLine)"
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
                    type: draft.entryType,
                    location: draft.customLocation.isEmpty ? nil : draft.customLocation,
                    cityCode: draft.selectedCityCode.isEmpty ? nil : draft.selectedCityCode,
                    cityName: draft.selectedCityName.isEmpty ? nil : draft.selectedCityName,
                    attachmentIds: draft.uploadedAttachments.map(\.id),
                    featured: draft.isFeatured,
                    occurredAt: FormatUtils.beijingISOString(from: draft.occurredAt)
                )
                draft.reset()
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

    /// 提交成功回执：面板内停留片刻展示确认，随后自动收起
    private func presentSuccess(_ message: String) {
        successText = message
        errorText = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard successText == message else { return }
            successText = nil
            onClosePopover?()
        }
    }

    private func handlePhotoDrop(providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        // NSItemProvider 不是 Sendable：交由 DropLoader 内部的 @unchecked Sendable 盒子跨隔离域传递
        let box = DropLoader.makeProviderBox(providers)
        Task { @MainActor in
            let urls = await DropLoader.loadDroppablePhotoURLs(from: box)
            await processAndUploadFiles(urls)
        }
    }

    /// 串行压制并上传多张底片（批量拖拽），全部归入附件列表
    private func processAndUploadFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isUploadingPhoto = true
        uploadProgress = 0.05
        errorText = nil
        successText = nil
        let total = Double(urls.count)
        // 进度计数器放在引用盒中，避免可变局部变量被捕获进 @Sendable 闭包
        let counter = ProgressCounter()
        for url in urls {
            do {
                let processed = try await ImageProcessor.processImageFileInBackground(at: url)
                if appState.quickDraft.extractedCameraLine.isEmpty && !processed.exifMetadata.formattedCameraLine.isEmpty {
                    appState.quickDraft.extractedCameraLine = processed.exifMetadata.formattedCameraLine
                }
                let attachment = try await R2DirectUploader.shared.uploadProcessedPhoto(processed) { prog in
                    Task { @MainActor in
                        self.uploadProgress = (counter.value + prog) / total
                    }
                }
                appState.quickDraft.uploadedAttachments.append(attachment)
            } catch {
                errorText = "「\(url.lastPathComponent)」上传失败：\(error.localizedDescription)"
            }
            counter.value += 1
            uploadProgress = max(uploadProgress, counter.value / total)
        }
        isUploadingPhoto = false
    }

    /// 粘贴命令（⌘V）：优先读取系统剪贴板图像，其次回退到粘贴提供者
    private func handlePasteCommand(_ providers: [NSItemProvider]) {
        Task { @MainActor in
            errorText = nil
            successText = nil
            // 剪贴板读取（文件 IO + PNG 重编码）全部在后台线程执行，不阻塞主线程
            let boardData = await DropLoader.readImageFromPasteboardAsync()
            if let boardData {
                isUploadingPhoto = true
                uploadProgress = 0.08
                await uploadPasteboardImage(boardData)
            } else {
                await handlePastedImages(providers)
            }
        }
    }

    /// 从 NSPasteboard.general 读取剪贴板图像，经 ImageProcessor 压制后上传入列
    private func pasteImageFromPasteboard() {
        errorText = nil
        successText = nil
        Task { @MainActor in
            isUploadingPhoto = true
            uploadProgress = 0.08
            let rawData = await DropLoader.readImageFromPasteboardAsync()
            guard let rawData else {
                errorText = "剪贴板中未检测到可用的图片或截图"
                isUploadingPhoto = false
                return
            }
            await uploadPasteboardImage(rawData)
        }
    }

    /// 压制并上传剪贴板图像，成功后自动聚焦标题输入框
    private func uploadPasteboardImage(_ rawData: Data) async {
        do {
            let processed = try await ImageProcessor.processImageDataInBackground(
                rawData,
                originalFilename: "pasteboard-\(Int(Date().timeIntervalSince1970)).jpg"
            )
            if appState.quickDraft.extractedCameraLine.isEmpty && !processed.exifMetadata.formattedCameraLine.isEmpty {
                appState.quickDraft.extractedCameraLine = processed.exifMetadata.formattedCameraLine
            }
            let attachment = try await R2DirectUploader.shared.uploadProcessedPhoto(processed) { prog in
                Task { @MainActor in
                    self.uploadProgress = prog
                }
            }
            appState.quickDraft.uploadedAttachments.append(attachment)
            isUploadingPhoto = false
            // 粘贴成功后自动聚焦标题输入框，便于立即补写标题
            isTitleFocused = true
        } catch {
            errorText = "剪贴板图片处理失败：\(error.localizedDescription)"
            isUploadingPhoto = false
        }
    }

    /// 处理剪贴板粘贴的图像（⌘V 截图直贴管线）
    private func handlePastedImages(_ providers: [NSItemProvider]) async {
        guard !providers.isEmpty else { return }
        isUploadingPhoto = true
        uploadProgress = 0.05
        errorText = nil
        // NSItemProvider 不是 Sendable：用 @unchecked Sendable 盒子安全跨隔离域传递
        let box = DropLoader.makeProviderBox(providers)
        for (index, provider) in box.providers.enumerated() {
            guard let data = await DropLoader.loadImageData(from: provider) else { continue }
            do {
                let processed = try await ImageProcessor.processImageDataInBackground(
                    data,
                    originalFilename: "clipboard-\(Int(Date().timeIntervalSince1970))-\(index)"
                )
                if appState.quickDraft.extractedCameraLine.isEmpty && !processed.exifMetadata.formattedCameraLine.isEmpty {
                    appState.quickDraft.extractedCameraLine = processed.exifMetadata.formattedCameraLine
                }
                let attachment = try await R2DirectUploader.shared.uploadProcessedPhoto(processed) { prog in
                    Task { @MainActor in
                        self.uploadProgress = prog
                    }
                }
                appState.quickDraft.uploadedAttachments.append(attachment)
                // 粘贴成功后自动聚焦标题输入框
                isTitleFocused = true
            } catch {
                errorText = error.localizedDescription
            }
        }
        isUploadingPhoto = false
    }
}

// MARK: - 预览 (Preview)

/// 预览用 mock 数据（复用 AppState 单例，仅注入面板所需的展示数据）
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

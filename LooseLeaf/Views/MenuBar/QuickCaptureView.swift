import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// 菜单栏极速闪念与记账悬浮窗 (QuickCaptureView)
/// 严格遵循 docs/macos.md §3.1 规范：
/// 1. 宽 380px，高随内容自适应（最大 520px）
/// 2. 顶部切换「极速记录」与「快速记账」
/// 3. 自动识别 #标签、支持拖拽相片自动提取 EXIF 直传 R2
/// 4. Cmd + Enter 即刻落库并播放快门声与触控板微震动
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

    @FocusState private var isContentFocused: Bool

    public init(appState: AppState, onClosePopover: (() -> Void)? = nil) {
        self.appState = appState
        self.onClosePopover = onClosePopover
    }

    private var detectedTags: [String] {
        FormatUtils.extractHashtags(from: appState.quickDraft.contentText)
    }

    public var body: some View {
        @Bindable var draft = appState.quickDraft
        return ZStack {
            NoiseBackground(useSubtleSurface: false, enableVibrancy: true)

            VStack(alignment: .leading, spacing: 12) {
                // 1. 顶部栏：品牌印记 + 模式切换 + 离线队列指示
                headerBar

                if let banner = appState.statusBanner {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.accentMoss)
                        Text(banner)
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // 2. 主体内容区
                if draft.activeTab == .thought {
                    thoughtCaptureSection
                } else {
                    QuickLedgerView(appState: appState) {
                        onClosePopover?()
                    }
                }

                Divider()
                    .overlay(ArchivePalette.borderSubtle)

                // 3. 底栏：状态印记与展开主工作台入口
                footerBar
            }
            .padding(14)
        }
        .frame(width: 380)
        .frame(maxHeight: 520)
        .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        .onAppear {
            isContentFocused = true
            consumePendingCaptureText()
        }
        .onChange(of: appState.pendingCaptureText) { _, _ in
            consumePendingCaptureText()
        }
        .onExitCommand {
            onClosePopover?()
        }
    }

    // MARK: - 顶部切换栏

    private var headerBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(ArchivePalette.accentMoss)
                Text(appState.siteConfig.siteName.isEmpty ? "散页 · 伴随记录" : appState.siteConfig.siteName)
                    .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .lineLimit(1)
            }

            Spacer()

            if !appState.outboxItems.isEmpty {
                Text("待同步 \(appState.outboxItems.count)")
                    .font(ArchiveTypography.monoScale(size: 10))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(ArchivePalette.accentWarm, lineWidth: 0.5)
                    )
            }

            HStack(spacing: 4) {
                ForEach(CaptureTab.allCases, id: \.rawValue) { tab in
                    PaperPillButton(
                        title: tab.rawValue,
                        isSelected: appState.quickDraft.activeTab == tab
                    ) {
                        appState.quickDraft.activeTab = tab
                        AudioFeedback.shared.playPaperFlip()
                    }
                }
            }
        }
    }

    // MARK: - 极速闪念记录区域

    private var thoughtCaptureSection: some View {
        @Bindable var draft = appState.quickDraft
        return VStack(alignment: .leading, spacing: 10) {
            // 形态选择胶囊
            HStack(spacing: 5) {
                ForEach(EntryType.allCases) { kind in
                    PaperPillButton(
                        title: kind.label,
                        icon: kind.symbolName,
                        isSelected: draft.entryType == kind
                    ) {
                        draft.entryType = kind
                        AudioFeedback.shared.playTink()
                    }
                }
            }

            // 可选标题行
            TextField("标题（可选，留空则为极速闪念片羽）", text: $draft.titleText)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .medium))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )

            // 正文 Markdown 输入框 (支持 #标签 实时识别)
            ZStack(alignment: .topLeading) {
                if draft.contentText.isEmpty {
                    Text("写下此刻闪念，支持 Markdown 与 #标签，按 ⌘ + Return 即刻归档…")
                        .font(ArchiveTypography.bodySans(size: 12.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $draft.contentText)
                    .font(ArchiveTypography.bodySans(size: 12.5))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isContentFocused)
                    .padding(5)
                    .frame(minHeight: 88, maxHeight: 140)
            }
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
            )
            .onPasteCommand(of: [.png, .tiff, .jpeg, .fileURL, .image]) { providers in
                if DropLoader.readImageFromPasteboard() != nil {
                    pasteImageFromPasteboard()
                } else {
                    handlePastedImages(providers)
                }
            }

            // 自动识别出的 #标签 与 EXIF 相机印记展示
            if !detectedTags.isEmpty || !draft.extractedCameraLine.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(detectedTags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(ArchiveTypography.monoScale(size: 10.5))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        if !draft.extractedCameraLine.isEmpty {
                            Text(draft.extractedCameraLine)
                                .font(ArchiveTypography.monoScale(size: 10.5))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
            }

            // 拖拽暗房相纸槽位
            miniDarkroomDropSlot

            // 地点与提交按钮行
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "location")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    TextField(
                        appState.profile.displayCity.isEmpty ? "记录地点（可选）" : appState.profile.displayCity,
                        text: $draft.customLocation
                    )
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .frame(maxWidth: 130)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )

                Button {
                    draft.showBackdatePicker.toggle()
                    AudioFeedback.shared.playTink()
                } label: {
                    Image(systemName: "clock")
                        .font(.system(size: 11.5))
                        .foregroundStyle(draft.showBackdatePicker ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                        .padding(6)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("补记历史时刻")
                .help("补记过去的时刻")

                Button {
                    draft.isFeatured.toggle()
                    AudioFeedback.shared.playTink()
                } label: {
                    Image(systemName: draft.isFeatured ? "star.fill" : "star")
                        .font(.system(size: 11.5))
                        .foregroundStyle(draft.isFeatured ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                        .padding(6)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("标记为精选印记")

                Spacer()

                Button {
                    submitThought()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 11))
                        Text(isSubmitting ? "归档中…" : "归档 ⌘↩")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(draft.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.uploadedAttachments.isEmpty || isSubmitting || isUploadingPhoto)
            }

            if draft.showBackdatePicker {
                HStack(spacing: 6) {
                    PaperDateTimePicker(selection: $draft.occurredAt, showQuickShortcuts: true)
                    Spacer()
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }
        }
    }

    private func isSameMinute(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 60
    }

    // MARK: - 迷你拖拽暗房槽位

    private var miniDarkroomDropSlot: some View {
        HStack(spacing: 8) {
            Image(systemName: isUploadingPhoto ? "arrow.triangle.2.circlepath.camera" : "photo.badge.plus")
                .font(.system(size: 13))
                .foregroundStyle(isDragTargeted ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)

            if isUploadingPhoto {
                Text("正在上传相片 (\(Int(uploadProgress * 100))%)…")
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                Spacer(minLength: 0)
            } else if !appState.quickDraft.uploadedAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(appState.quickDraft.uploadedAttachments) { att in
                            HStack(spacing: 4) {
                                if let url = APIClient.shared.resolveMediaURL(att.url) {
                                    CachedFilmImageView(url: url, maxHeight: 18)
                                        .frame(width: 18, height: 18)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                }
                                Text(att.originalFilename)
                                    .font(ArchiveTypography.monoScale(size: 10))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 80)
                                Button {
                                    appState.quickDraft.uploadedAttachments.removeAll { $0.id == att.id }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2.5)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                        }
                    }
                }
                Spacer(minLength: 4)
                Button("清空") {
                    appState.quickDraft.uploadedAttachments.removeAll()
                    appState.quickDraft.extractedCameraLine = ""
                }
                .font(ArchiveTypography.bodySans(size: 10.5))
                .buttonStyle(.plain)
                .foregroundStyle(ArchivePalette.inkMuted)
            } else {
                Text("拖拽照片至此，自动装裱保存")
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !isContentFocused {
                    Button("粘贴剪贴板图片 (⌘V)") {
                        pasteImageFromPasteboard()
                    }
                    .font(ArchiveTypography.bodySans(size: 10.5, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .keyboardShortcut("v", modifiers: [.command])
                } else {
                    Button("粘贴剪贴板图片 (⌘V)") {
                        pasteImageFromPasteboard()
                    }
                    .font(ArchiveTypography.bodySans(size: 10.5, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(ArchivePalette.accentWarm)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
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
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle()
                    .fill(!appState.isOnline ? ArchivePalette.accentWarm : (appState.isPaired ? ArchivePalette.accentMoss : ArchivePalette.accentWarm))
                    .frame(width: 6, height: 6)
                Text(!appState.isOnline ? "离线暂存 (待同步 \(appState.outboxItems.count))" : (appState.isPaired ? "已接入数据中枢" : "待绑定中枢"))
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            Spacer()

            Button {
                appState.activeSection = .stream
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                onClosePopover?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11))
                    Text("展开主工作台")
                        .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                }
                .foregroundStyle(ArchivePalette.inkSecondary)
            }
            .buttonStyle(.plain)

            Button {
                appState.activeSection = .settings
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                onClosePopover?()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }
            .buttonStyle(.plain)
            .help("设备配对与偏好设置")
        }
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

        Task { @MainActor in
            do {
                _ = try await appState.submitQuickCapture(
                    title: draft.titleText,
                    content: contentToSubmit,
                    type: draft.entryType,
                    location: draft.customLocation.isEmpty ? nil : draft.customLocation,
                    attachmentIds: draft.uploadedAttachments.map(\.id),
                    featured: draft.isFeatured,
                    occurredAt: FormatUtils.beijingISOString(from: draft.occurredAt)
                )
                draft.reset()
                isSubmitting = false
                onClosePopover?()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private func handlePhotoDrop(providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        Task { @MainActor in
            let urls = await DropLoader.loadDroppablePhotoURLs(from: providers)
            await processAndUploadFiles(urls)
        }
    }

    /// 串行压制并上传多张底片（批量拖拽），全部归入附件列表
    private func processAndUploadFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isUploadingPhoto = true
        uploadProgress = 0.05
        errorText = nil
        let total = Double(urls.count)
        var finished = 0.0
        for url in urls {
            do {
                let processed = try await ImageProcessor.processImageFileInBackground(at: url)
                if appState.quickDraft.extractedCameraLine.isEmpty && !processed.exifMetadata.formattedCameraLine.isEmpty {
                    appState.quickDraft.extractedCameraLine = processed.exifMetadata.formattedCameraLine
                }
                let attachment = try await R2DirectUploader.shared.uploadProcessedPhoto(processed) { prog in
                    Task { @MainActor in
                        self.uploadProgress = (finished + prog) / total
                    }
                }
                appState.quickDraft.uploadedAttachments.append(attachment)
                AudioFeedback.shared.playShutter()
            } catch {
                errorText = "「\(url.lastPathComponent)」上传失败：\(error.localizedDescription)"
            }
            finished += 1
            uploadProgress = max(uploadProgress, finished / total)
        }
        isUploadingPhoto = false
    }

    /// 从 NSPasteboard.general 读取剪贴板图像，经 ImageProcessor 压制后上传入列
    private func pasteImageFromPasteboard() {
        guard let rawData = DropLoader.readImageFromPasteboard() else {
            errorText = "剪贴板中未检测到可用的图片或截图"
            return
        }
        Task { @MainActor in
            isUploadingPhoto = true
            uploadProgress = 0.08
            errorText = nil
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
                AudioFeedback.shared.playShutter()
            } catch {
                errorText = "剪贴板图片处理失败：\(error.localizedDescription)"
            }
            isUploadingPhoto = false
        }
    }

    /// 处理剪贴板粘贴的图像（⌘V 截图直贴管线）
    private func handlePastedImages(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        Task { @MainActor in
            isUploadingPhoto = true
            uploadProgress = 0.05
            errorText = nil
            for (index, provider) in providers.enumerated() {
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
                    AudioFeedback.shared.playShutter()
                } catch {
                    errorText = error.localizedDescription
                }
            }
            isUploadingPhoto = false
        }
    }
}

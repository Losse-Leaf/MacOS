import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// 菜单栏极速闪念与记账悬浮窗 (QuickCaptureView)
/// 严格遵循 docs/macos.md §3.1 规范：
/// 1. 宽 380px，高随内容自适应（最大 520px）
/// 2. 顶部切换「极速记录」与「快速记账」
/// 3. 自动识别 #标签、支持拖拽相片自动提取 EXIF 直传 R2
/// 4. Cmd + Enter 即刻落库并播放快门声与触控板微震动
public struct QuickCaptureView: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow
    var onClosePopover: (() -> Void)?

    public enum CaptureTab: String, CaseIterable {
        case thought = "极速记录"
        case ledger = "快速记账"
    }

    @State private var activeTab: CaptureTab = .thought
    @State private var entryType: EntryType = .life
    @State private var titleText: String = ""
    @State private var contentText: String = ""
    @State private var customLocation: String = ""
    @State private var isFeatured: Bool = false

    // 暗房相片拖拽与上传状态
    @State private var isDragTargeted: Bool = false
    @State private var isUploadingPhoto: Bool = false
    @State private var uploadProgress: Double = 0.0
    @State private var uploadedAttachments: [Attachment] = []
    @State private var extractedCameraLine: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    @FocusState private var isContentFocused: Bool

    public init(appState: AppState, onClosePopover: (() -> Void)? = nil) {
        self.appState = appState
        self.onClosePopover = onClosePopover
    }

    private var detectedTags: [String] {
        FormatUtils.extractHashtags(from: contentText)
    }

    public var body: some View {
        ZStack {
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
                if activeTab == .thought {
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
                        isSelected: activeTab == tab
                    ) {
                        activeTab = tab
                        AudioFeedback.shared.playPaperFlip()
                    }
                }
            }
        }
    }

    // MARK: - 极速闪念记录区域

    private var thoughtCaptureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 形态选择胶囊
            HStack(spacing: 5) {
                ForEach(EntryType.allCases) { kind in
                    PaperPillButton(
                        title: kind.label,
                        icon: kind.symbolName,
                        isSelected: entryType == kind
                    ) {
                        entryType = kind
                        AudioFeedback.shared.playTink()
                    }
                }
            }

            // 可选标题行
            TextField("标题（可选，留空则为极速闪念片羽）", text: $titleText)
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
                if contentText.isEmpty {
                    Text("写下此刻闪念，支持 Markdown 与 #标签，按 ⌘ + Return 即刻归档…")
                        .font(ArchiveTypography.bodySans(size: 12.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $contentText)
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

            // 自动识别出的 #标签 与 EXIF 相机印记展示
            if !detectedTags.isEmpty || !extractedCameraLine.isEmpty {
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
                        if !extractedCameraLine.isEmpty {
                            Text(extractedCameraLine)
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
                        text: $customLocation
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
                    isFeatured.toggle()
                    AudioFeedback.shared.playTink()
                } label: {
                    Image(systemName: isFeatured ? "star.fill" : "star")
                        .font(.system(size: 11.5))
                        .foregroundStyle(isFeatured ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
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
                .disabled(contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && uploadedAttachments.isEmpty || isSubmitting || isUploadingPhoto)
            }

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }
        }
    }

    // MARK: - 迷你拖拽暗房槽位

    private var miniDarkroomDropSlot: some View {
        HStack(spacing: 8) {
            Image(systemName: isUploadingPhoto ? "arrow.triangle.2.circlepath.camera" : "photo.badge.plus")
                .font(.system(size: 13))
                .foregroundStyle(isDragTargeted ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)

            if isUploadingPhoto {
                Text("正在压制 4K 相纸并上传 (\(Int(uploadProgress * 100))%)…")
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkSecondary)
            } else if !uploadedAttachments.isEmpty {
                Text("已装裱 \(uploadedAttachments.count) 张胶片底片")
                    .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                    .foregroundStyle(ArchivePalette.accentMoss)
                Spacer()
                Button("清除") {
                    uploadedAttachments.removeAll()
                    extractedCameraLine = ""
                }
                .font(ArchiveTypography.bodySans(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(ArchivePalette.inkMuted)
            } else {
                Text("从 Finder 拖拽照片至此，自动提取 EXIF 并压制直传")
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
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
                    .fill(appState.isPaired ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                    .frame(width: 6, height: 6)
                Text(appState.isPaired ? "已配对授信 · 主理人全权管理" : "待配对激活")
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            Spacer()

            Button {
                appState.activeSection = .stream
                openWindow(id: "main-workbench")
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
                openWindow(id: "main-workbench")
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

    private func submitThought() {
        var finalContent = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalContent.isEmpty && !uploadedAttachments.isEmpty {
            finalContent = extractedCameraLine.isEmpty ? "暗房胶片冲印归档" : extractedCameraLine
        }
        guard !finalContent.isEmpty, !isSubmitting else { return }

        if !extractedCameraLine.isEmpty && !finalContent.contains(extractedCameraLine) {
            finalContent += "\n\n> \(extractedCameraLine)"
        }

        isSubmitting = true
        errorText = nil

        Task {
            do {
                _ = try await appState.submitQuickCapture(
                    title: titleText,
                    content: finalContent,
                    type: entryType,
                    location: customLocation.isEmpty ? nil : customLocation,
                    attachmentIds: uploadedAttachments.map(\.id),
                    featured: isFeatured
                )
                titleText = ""
                contentText = ""
                uploadedAttachments.removeAll()
                extractedCameraLine = ""
                isFeatured = false
                isSubmitting = false
                onClosePopover?()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private func handlePhotoDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let fileURL: URL?
                if let url = item as? URL {
                    fileURL = url
                } else if let data = item as? Data {
                    fileURL = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    fileURL = nil
                }
                guard let validURL = fileURL else { return }
                Task { @MainActor in
                    await processAndUploadFile(at: validURL)
                }
            }
        }
    }

    private func processAndUploadFile(at url: URL) async {
        isUploadingPhoto = true
        uploadProgress = 0.05
        errorText = nil
        do {
            let processed = try ImageProcessor.processImageFile(at: url)
            if !processed.exifMetadata.formattedCameraLine.isEmpty {
                extractedCameraLine = processed.exifMetadata.formattedCameraLine
            }
            let attachment = try await R2DirectUploader.shared.uploadProcessedPhoto(processed) { prog in
                Task { @MainActor in
                    self.uploadProgress = prog
                }
            }
            uploadedAttachments.append(attachment)
            AudioFeedback.shared.playShutter()
        } catch {
            errorText = error.localizedDescription
        }
        isUploadingPhoto = false
    }
}

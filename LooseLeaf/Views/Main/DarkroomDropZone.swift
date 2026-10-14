import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// 拖拽暗房相纸冲印工作台组件 (DarkroomDropZone)
/// 严格遵循 docs/macos.md §3.3 规范：
/// 1. 支持从 Finder 直接拖拽 .jpg, .jpeg, .png, .heic, .webp, .cr2, .nef, .arw, .dng 等底片
/// 2. 端侧 ImageIO 提取 EXIF 相机型号、镜头焦段、光圈、快门与 ISO 参数
/// 3. 自动执行最长边 3840px (4K) 缩放与 85% 质量压制
/// 4. 预签名直传 R2 存储桶（展示拟物进度环）并伴生写入散页时间流
@MainActor
public struct DarkroomDropZone: View {
    @Bindable var appState: AppState

    @State private var isDragTargeted: Bool = false
    @State private var previewImage: NSImage?
    @State private var processedPhoto: ImageProcessor.ProcessedPhoto?
    @State private var uploadedAttachment: Attachment?
    @State private var pendingPhotoURLs: [URL] = []

    @State private var entryTitle: String = ""
    @State private var entryContent: String = ""
    @State private var entryLocation: String = ""
    @State private var entryType: EntryType = .life
    @State private var isFeatured: Bool = true

    @State private var isProcessing: Bool = false
    @State private var isUploading: Bool = false
    @State private var uploadProgress: Double = 0.0
    @State private var errorMessage: String?

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. 页眉说明
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("银盐暗房 · 拖拽相纸冲印与 EXIF 装裱")
                            .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("从 Finder 拖入单反原片或日常摄影，端侧自动提取机型镜头参数、压制 4K 画质并直传归档")
                            .font(ArchiveTypography.bodySans(size: 12.5))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                    }
                    Spacer()

                    if !pendingPhotoURLs.isEmpty {
                        Text("队列待冲印 \(pendingPhotoURLs.count) 张")
                            .font(ArchiveTypography.monoScale(size: 11))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }

                    Button {
                        selectPhotoFromFinder()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder.badge.plus")
                            Text("从访达选择底片…")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }

                // 2. 核心拖拽暗房框与相纸装裱预览
                HStack(alignment: .top, spacing: 20) {
                    dropCanvasArea
                        .frame(maxWidth: .infinity)

                    if let photo = processedPhoto {
                        exifAndPublishInspector(photo: photo)
                            .frame(width: 310)
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - 拖拽画布与相纸装裱框

    private var dropCanvasArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(ArchivePalette.archiveSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isDragTargeted ? ArchivePalette.accentWarm : ArchivePalette.borderDivider,
                            style: StrokeStyle(lineWidth: isDragTargeted ? 1.5 : 0.8, dash: [6, 4])
                        )
                )

            if let previewImage, let photo = processedPhoto {
                VStack(spacing: 14) {
                    FilmFrameView(
                        localImage: previewImage,
                        caption: entryTitle.isEmpty ? photo.filename : entryTitle,
                        metaText: photo.exifMetadata.formattedCameraLine.isEmpty
                            ? "\(photo.width) × \(photo.height)"
                            : photo.exifMetadata.formattedCameraLine,
                        maxHeight: 380
                    )

                    if isUploading {
                        HStack(spacing: 10) {
                            ProgressView(value: uploadProgress)
                                .progressViewStyle(.linear)
                                .tint(ArchivePalette.accentWarm)
                                .frame(width: 180)
                            Text("正在直传云端存储桶 \(Int(uploadProgress * 100))%")
                                .font(ArchiveTypography.monoScale(size: 11.5))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                        }
                    }
                }
                .padding(20)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: isProcessing ? "camera.metering.multispot" : "photo.on.rectangle.angled")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(isDragTargeted ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)

                    Text(isProcessing ? "正在解析 EXIF 与压制 4K 相纸…" : "将照片拖拽至此处装裱显影")
                        .font(ArchiveTypography.editorialSerif(size: 16, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Text("支持 JPEG · PNG · HEIC · WebP · CR2 · NEF · ARW · DNG（可多张拖入，单张上限 50MB）")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .padding(48)
            }
        }
        .frame(minHeight: 380)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDragTargeted) { providers in
            handleImageDrop(providers: providers)
            return true
        }
    }

    // MARK: - 右侧 EXIF 检视器与归档表单

    private func exifAndPublishInspector(photo: ImageProcessor.ProcessedPhoto) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("底片参数与装裱手记")
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            // EXIF 参数卡片
            VStack(alignment: .leading, spacing: 7) {
                exifRow(label: "机型铭牌", value: photo.exifMetadata.formattedCameraLine.isEmpty ? "未检出器材 EXIF" : photo.exifMetadata.formattedCameraLine)
                exifRow(label: "画幅尺寸", value: "\(photo.width) × \(photo.height) px")
                exifRow(
                    label: "端侧压制",
                    value: "\(formatBytes(photo.originalSize)) → \(formatBytes(photo.compressedSize))"
                )
                if let captured = photo.exifMetadata.capturedAt {
                    exifRow(label: "拍摄时刻", value: FormatUtils.parseOccurredDate(captured).dotDateTime)
                }
            }
            .padding(10)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
            )

            // 归档形态
            HStack(spacing: 6) {
                PaperPillButton(title: "日常光影", icon: "leaf", isSelected: entryType == .life) {
                    entryType = .life
                }
                PaperPillButton(title: "山川行旅", icon: "safari", isSelected: entryType == .travel) {
                    entryType = .travel
                }
            }

            // 标题与手记输入
            TextField("相片标题（可选）", text: $entryTitle)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.editorialSerif(size: 13.5))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .padding(8)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )

            TextField(
                appState.profile.displayCity.isEmpty ? "拍摄地点（如：杭州 · 满觉陇）" : appState.profile.displayCity,
                text: $entryLocation
            )
            .textFieldStyle(.plain)
            .font(ArchiveTypography.bodySans(size: 12))
            .foregroundStyle(ArchivePalette.inkPrimary)
            .padding(8)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
            )

            ZStack(alignment: .topLeading) {
                if entryContent.isEmpty {
                    Text("写下按下快门时的心境与手记…")
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $entryContent)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(height: 90)
            }
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack(spacing: 8) {
                Button("重置底片") {
                    resetDarkroom()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                Spacer()

                Button {
                    uploadAndPublishPhoto(photo)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                        Text(isUploading ? "显影归档中…" : "显影并归入散页")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(isUploading)
            }
        }
        .padding(16)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
        )
    }

    private func exifRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(ArchiveTypography.bodySans(size: 11))
                .foregroundStyle(ArchivePalette.inkMuted)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(ArchiveTypography.monoScale(size: 11))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 拖拽与文件处理逻辑

    private func selectPhotoFromFinder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .rawImage]
        if panel.runModal() == .OK, let url = panel.url {
            loadPhoto(from: url)
        }
    }

    private func handleImageDrop(providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        Task { @MainActor in
            let urls = await DropLoader.loadFileURLs(from: providers)
            guard let first = urls.first else { return }
            pendingPhotoURLs.append(contentsOf: urls.dropFirst())
            loadPhoto(from: first)
        }
    }

    private func loadPhoto(from url: URL) {
        isProcessing = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let result = try await ImageProcessor.processImageFileInBackground(at: url)
                self.processedPhoto = result
                self.previewImage = NSImage(data: result.compressedData)
                if entryTitle.isEmpty {
                    entryTitle = (url.lastPathComponent as NSString).deletingPathExtension
                }
                if entryContent.isEmpty && !result.exifMetadata.formattedCameraLine.isEmpty {
                    entryContent = result.exifMetadata.formattedCameraLine
                }
                AudioFeedback.shared.playPaperFlip()
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isProcessing = false
        }
    }

    private func uploadAndPublishPhoto(_ photo: ImageProcessor.ProcessedPhoto) {
        isUploading = true
        uploadProgress = 0.05
        errorMessage = nil

        Task { @MainActor in
            do {
                let att = try await R2DirectUploader.shared.uploadProcessedPhoto(photo) { prog in
                    Task { @MainActor in
                        self.uploadProgress = prog
                    }
                }
                self.uploadedAttachment = att

                let bodyText = entryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? (photo.exifMetadata.formattedCameraLine.isEmpty ? "暗房相纸显影归档" : photo.exifMetadata.formattedCameraLine)
                    : entryContent

                _ = try await appState.submitQuickCapture(
                    title: entryTitle,
                    content: bodyText,
                    type: entryType,
                    location: entryLocation.isEmpty ? nil : entryLocation,
                    attachmentIds: [att.id],
                    featured: isFeatured
                )

                let remainingCount = pendingPhotoURLs.count
                resetDarkroom()
                if remainingCount == 0 {
                    appState.activeSection = .stream
                } else {
                    appState.showTemporaryBanner("已归档当前底片，已载入队列下一张（待冲印 \(remainingCount) 张）")
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isUploading = false
        }
    }

    private func resetDarkroom() {
        previewImage = nil
        processedPhoto = nil
        uploadedAttachment = nil
        entryTitle = ""
        entryContent = ""
        uploadProgress = 0.0
        errorMessage = nil
        // 队列流转：若还有待冲印底片，自动载入下一张
        if !pendingPhotoURLs.isEmpty {
            let next = pendingPhotoURLs.removeFirst()
            loadPhoto(from: next)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024.0 {
            return String(format: "%.0f KB", kb)
        }
        return String(format: "%.2f MB", kb / 1024.0)
    }
}

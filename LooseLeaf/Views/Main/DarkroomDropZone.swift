import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// 拖拽暗房相纸冲印工作台组件 (DarkroomDropZone)
/// 严格遵循 docs/macos.md §3.3 规范：
/// 1. 支持从 Finder 直接拖拽 .jpg, .jpeg, .png, .heic, .webp, .cr2, .nef, .arw, .dng 等底片
/// 2. 支持多底片集合装裱 (Darkroom Film Strip) 与多相纸合并为单篇生活手记
/// 3. 端侧 ImageIO 提取 EXIF 相机型号、镜头焦段、光圈、快门与 ISO 参数
/// 4. 自动执行最长边 3840px (4K) 缩放与 85% 质量压制
/// 5. 预签名直传 R2 存储桶并伴生写入散页时间流
@MainActor
public struct DarkroomDropZone: View {
    @Bindable var appState: AppState

    public struct DarkroomPhotoItem: Identifiable, Equatable {
        public let id = UUID()
        public var photo: ImageProcessor.ProcessedPhoto
        public var preview: NSImage
        public var originalURL: URL?

        public static func == (lhs: DarkroomPhotoItem, rhs: DarkroomPhotoItem) -> Bool {
            lhs.id == rhs.id
        }
    }

    @State private var items: [DarkroomPhotoItem] = []
    @State private var selectedIndex: Int = 0
    @State private var batchIntoSingleEntry: Bool = true
    @State private var isDragTargeted: Bool = false

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

    private var currentItem: DarkroomPhotoItem? {
        guard !items.isEmpty else { return nil }
        let idx = min(max(selectedIndex, 0), items.count - 1)
        return items[idx]
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. 页眉说明
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("银盐暗房 · 胶片冲印与相纸装裱")
                            .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("拖入摄影原片或日常照片，自动识别器材参数，支持底片卷多张合并或单张装裱入册")
                            .font(ArchiveTypography.bodySans(size: 12.5))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                    }
                    Spacer()

                    if !items.isEmpty {
                        Text("底片卷 \(items.count) 张")
                            .font(ArchiveTypography.monoScale(size: 11, weight: .semibold))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(ArchivePalette.accentWarm.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    Button {
                        pastePhotoFromClipboard()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.on.clipboard")
                            Text("粘贴剪贴板图片 (⌘V)")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .keyboardShortcut("v", modifiers: [.command])

                    Button {
                        selectPhotoFromFinder()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "photo.badge.plus")
                            Text("选择相片…")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }

                // 2. 核心拖拽暗房框与相纸装裱预览
                HStack(alignment: .top, spacing: 20) {
                    dropCanvasArea
                        .frame(maxWidth: .infinity)

                    if let current = currentItem {
                        exifAndPublishInspector(current: current)
                            .frame(width: 320)
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - 拖拽画布与相纸装裱框

    private var dropCanvasArea: some View {
        VStack(spacing: 12) {
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

                if let current = currentItem {
                    VStack(spacing: 14) {
                        FilmFrameView(
                            localImage: current.preview,
                            caption: entryTitle.isEmpty ? current.photo.filename : entryTitle,
                            metaText: current.photo.exifMetadata.formattedCameraLine.isEmpty
                                ? "\(current.photo.width) × \(current.photo.height)"
                                : current.photo.exifMetadata.formattedCameraLine,
                            maxHeight: 380
                        )

                        if isUploading {
                            HStack(spacing: 10) {
                                ProgressView(value: uploadProgress)
                                    .progressViewStyle(.linear)
                                    .tint(ArchivePalette.accentWarm)
                                    .frame(width: 180)
                                Text("正在冲印上传 \(Int(uploadProgress * 100))%…")
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

                        Text(isProcessing ? "正在装裱底片…" : "将照片拖拽至此处装裱显影")
                            .font(ArchiveTypography.editorialSerif(size: 16, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)

                        Text("支持常见图片与单反原片，支持一次拖入多张照片生成底片卷，或按 ⌘V 粘贴截图")
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
            .onPasteCommand(of: [.png, .tiff, .jpeg, .fileURL, .image]) { _ in
                pastePhotoFromClipboard()
            }

            // 3. 底片胶卷卷栏 (Film Strip / Darkroom Contact Sheet)
            if items.count > 1 {
                filmStripBar
            }
        }
    }

    private var filmStripBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("底片胶卷盒 (\(items.count) 张)")
                    .font(ArchiveTypography.editorialSerif(size: 12, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                Spacer()
                Text("点击底片切换预览 · 点击角标移除")
                    .font(ArchiveTypography.monoScale(size: 10))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        VStack(spacing: 3) {
                            ZStack(alignment: .topTrailing) {
                                Image(nsImage: item.preview)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(
                                                selectedIndex == index ? ArchivePalette.accentWarm : ArchivePalette.borderDivider,
                                                lineWidth: selectedIndex == index ? 2.0 : 0.5
                                            )
                                    )

                                Button {
                                    removePhoto(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(ArchivePalette.accentWarm)
                                        .background(Circle().fill(Color.white))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 3, y: -3)
                            }

                            Text("\(index + 1)")
                                .font(ArchiveTypography.monoScale(size: 10, weight: selectedIndex == index ? .bold : .regular))
                                .foregroundStyle(selectedIndex == index ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedIndex = index
                            AudioFeedback.shared.playTink()
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
        .padding(10)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 右侧检视器与归档表单

    private func exifAndPublishInspector(current: DarkroomPhotoItem) -> some View {
        let photo = current.photo
        return VStack(alignment: .leading, spacing: 14) {
            Text("拍摄参数与相纸手记")
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            // 参数卡片
            VStack(alignment: .leading, spacing: 7) {
                exifRow(label: "器材参数", value: photo.exifMetadata.formattedCameraLine.isEmpty ? "无拍摄参数记录" : photo.exifMetadata.formattedCameraLine)
                exifRow(label: "画幅尺寸", value: "\(photo.width) × \(photo.height) px")
                exifRow(
                    label: "相纸大小",
                    value: "\(formatBytes(photo.compressedSize)) (原图 \(formatBytes(photo.originalSize)))"
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

            // 多图合并选项
            if items.count > 1 {
                Toggle("将全部 \(items.count) 张底片合并归档入同一篇散页手记", isOn: $batchIntoSingleEntry)
                    .toggleStyle(.checkbox)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkPrimary)
            }

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
                Button("清空重选") {
                    resetDarkroom()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .disabled(isUploading)

                Spacer()

                Button {
                    uploadAndPublishPhotos()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                        Text(isUploading ? "冲印上传中…" : (batchIntoSingleEntry && items.count > 1 ? "全部合并装裱入册" : "装裱并保存"))
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

    private func pastePhotoFromClipboard() {
        guard let rawData = DropLoader.readImageFromPasteboard() else {
            errorMessage = "剪贴板中未检测到图片或截图数据"
            return
        }
        isProcessing = true
        errorMessage = nil
        let name = "pasteboard-\(Int(Date().timeIntervalSince1970)).jpg"
        Task { @MainActor in
            do {
                let result = try await ImageProcessor.processImageDataInBackground(rawData, originalFilename: name)
                if let img = NSImage(data: result.compressedData) {
                    let item = DarkroomPhotoItem(photo: result, preview: img)
                    items.append(item)
                    selectedIndex = items.count - 1
                    if entryTitle.isEmpty {
                        entryTitle = "剪贴板相片 · \(FormatUtils.beijingDateString())"
                    }
                    if entryContent.isEmpty && !result.exifMetadata.formattedCameraLine.isEmpty {
                        entryContent = result.exifMetadata.formattedCameraLine
                    }
                    AudioFeedback.shared.playPaperFlip()
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isProcessing = false
        }
    }

    private func selectPhotoFromFinder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .rawImage]
        if panel.runModal() == .OK {
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            Task { @MainActor in
                await loadPhotos(from: urls)
            }
        }
    }

    private func handleImageDrop(providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        Task { @MainActor in
            let urls = await DropLoader.loadDroppablePhotoURLs(from: providers)
            guard !urls.isEmpty else { return }
            await loadPhotos(from: urls)
        }
    }

    private func loadPhotos(from urls: [URL]) async {
        isProcessing = true
        errorMessage = nil
        for url in urls {
            do {
                let result = try await ImageProcessor.processImageFileInBackground(at: url)
                if let img = NSImage(data: result.compressedData) {
                    let item = DarkroomPhotoItem(photo: result, preview: img, originalURL: url)
                    items.append(item)
                    if entryTitle.isEmpty {
                        entryTitle = (url.lastPathComponent as NSString).deletingPathExtension
                    }
                    if entryContent.isEmpty && !result.exifMetadata.formattedCameraLine.isEmpty {
                        entryContent = result.exifMetadata.formattedCameraLine
                    }
                }
            } catch {
                self.errorMessage = "载入「\(url.lastPathComponent)」失败：\(error.localizedDescription)"
            }
        }
        selectedIndex = max(0, items.count - 1)
        AudioFeedback.shared.playPaperFlip()
        isProcessing = false
    }

    private func removePhoto(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        if items.isEmpty {
            resetDarkroom()
        } else {
            selectedIndex = min(selectedIndex, items.count - 1)
        }
        AudioFeedback.shared.playTink()
    }

    private func uploadAndPublishPhotos() {
        guard !items.isEmpty, !isUploading else { return }
        isUploading = true
        uploadProgress = 0.05
        errorMessage = nil

        Task { @MainActor in
            do {
                if batchIntoSingleEntry && items.count > 1 {
                    // 全部底片合并装裱入同一篇生活手记
                    var attachmentIds: [Int] = []
                    let total = Double(items.count)
                    var finished = 0.0

                    for item in items {
                        let att = try await R2DirectUploader.shared.uploadProcessedPhoto(item.photo) { prog in
                            Task { @MainActor in
                                self.uploadProgress = (finished + prog) / total
                            }
                        }
                        attachmentIds.append(att.id)
                        finished += 1
                        self.uploadProgress = finished / total
                    }

                    var bodyText = entryContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    let allExifLines = Array(Set(items.map { $0.photo.exifMetadata.formattedCameraLine }.filter { !$0.isEmpty }))
                    if !allExifLines.isEmpty {
                        let exifSuffix = allExifLines.map { "> \($0)" }.joined(separator: "\n")
                        if bodyText.isEmpty {
                            bodyText = exifSuffix
                        } else if !bodyText.contains(allExifLines.first!) {
                            bodyText += "\n\n" + exifSuffix
                        }
                    }
                    if bodyText.isEmpty {
                        bodyText = "银盐暗房 · 胶片相纸显影归档"
                    }

                    _ = try await appState.submitQuickCapture(
                        title: entryTitle,
                        content: bodyText,
                        type: entryType,
                        location: entryLocation.isEmpty ? nil : entryLocation,
                        attachmentIds: attachmentIds,
                        featured: isFeatured
                    )

                    resetDarkroom()
                    appState.showTemporaryBanner("已装裱并归档 \(attachmentIds.count) 张相纸至散页手记")
                    appState.activeSection = .stream
                } else {
                    // 单张装裱当前选中的底片
                    let item = items[selectedIndex]
                    let att = try await R2DirectUploader.shared.uploadProcessedPhoto(item.photo) { prog in
                        Task { @MainActor in
                            self.uploadProgress = prog
                        }
                    }

                    var bodyText = entryContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !item.photo.exifMetadata.formattedCameraLine.isEmpty && !bodyText.contains(item.photo.exifMetadata.formattedCameraLine) {
                        bodyText += (bodyText.isEmpty ? "" : "\n\n") + "> \(item.photo.exifMetadata.formattedCameraLine)"
                    }
                    if bodyText.isEmpty {
                        bodyText = "银盐暗房 · 胶片相纸显影归档"
                    }

                    _ = try await appState.submitQuickCapture(
                        title: entryTitle,
                        content: bodyText,
                        type: entryType,
                        location: entryLocation.isEmpty ? nil : entryLocation,
                        attachmentIds: [att.id],
                        featured: isFeatured
                    )

                    items.remove(at: selectedIndex)
                    if items.isEmpty {
                        resetDarkroom()
                        appState.activeSection = .stream
                    } else {
                        selectedIndex = min(selectedIndex, items.count - 1)
                        entryTitle = items[selectedIndex].photo.filename
                        appState.showTemporaryBanner("已归档底片，底片卷中还有 \(items.count) 张待装裱")
                    }
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isUploading = false
        }
    }

    private func resetDarkroom() {
        items.removeAll()
        selectedIndex = 0
        entryTitle = ""
        entryContent = ""
        entryLocation = ""
        uploadProgress = 0.0
        errorMessage = nil
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024.0 {
            return String(format: "%.0f KB", kb)
        }
        return String(format: "%.2f MB", kb / 1024.0)
    }
}

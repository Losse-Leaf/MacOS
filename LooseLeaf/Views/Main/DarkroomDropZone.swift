import SwiftUI

/// 暗房回廊底片条目（全端通用：随AppState记忆化缓存）
public struct GalleryPhotoItem: Identifiable, Equatable {
    public let id: String
    public let attachment: Attachment
    public let parentEntry: LifeEntry

    public static func == (lhs: GalleryPhotoItem, rhs: GalleryPhotoItem) -> Bool {
        lhs.id == rhs.id
    }
}

import UniformTypeIdentifiers
import AppKit

/// 银盐底片回廊与相纸冲印装裱工作台 (DarkroomDropZone)
/// 严格遵循 docs/macos.md §3.3 与体验重构规范：
/// 1. 彻底解决“图文割裂与荒漠感”：上方为相纸冲印显影台，下方为“银盐底片回廊（画廊）”，全量展现时光手账装裱底片与大图灯箱
/// 2. 支持从 Finder 拖拽常见相片与单反 RAW 原片，或按 ⌘V 粘贴截图冲印
/// 3. 支持底片卷多张合并归档或单张装裱入册
/// 4. 端侧 ImageIO 提取 EXIF 相机型号、焦段、光圈、快门与 ISO 参数
/// 5. 自动执行 4K 缩放与 85% 质量压制，预签名直传 R2 伴生写入生活时间流
@MainActor
public struct DarkroomDropZone: View {
    @Bindable var appState: AppState

    /// 跨并发边界共享的上传进度计数器（避免可变局部变量被捕获进 @Sendable 闭包）
final class UploadProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Double = 0
    var value: Double {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}

/// 底片条目。
    /// Sendable 说明：photo 为值类型快照；preview (NSImage) 在创建后不再被修改，
    /// AppKit 文档保证 NSImage 的读取是线程安全的，因此可在并发任务间传递。
    public struct DarkroomPhotoItem: Identifiable, Equatable, @unchecked Sendable {
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
    @State private var entryCityCode: String = ""
    @State private var entryCityName: String = ""
    @State private var entryOccurredAt: Date = Date()
    @State private var entryType: EntryType = .life
    @State private var isFeatured: Bool = true

    @State private var isProcessing: Bool = false
    /// 批量装裱进度（0~1）
    @State private var processingProgress: Double = 0
    @State private var isUploading: Bool = false
    @State private var uploadProgress: Double = 0.0
    @State private var errorMessage: String?

    @State private var galleryCategoryFilter: ArchiveCategory = .all
    @State private var selectedLightboxPhoto: GalleryPhotoItem? = nil

    public init(appState: AppState) {
        self.appState = appState
    }

    private var currentItem: DarkroomPhotoItem? {
        guard !items.isEmpty else { return nil }
        let idx = min(max(selectedIndex, 0), items.count - 1)
        return items[idx]
    }

    private var filteredGalleryPhotos: [GalleryPhotoItem] {
        let all = appState.allGalleryPhotos
        if galleryCategoryFilter == .all {
            return all
        }
        return all.filter { item in
            switch galleryCategoryFilter {
            case .daily: return item.parentEntry.type == "life"
            case .travel: return item.parentEntry.type == "travel"
            case .project: return item.parentEntry.type == "project"
            case .wish: return item.parentEntry.type == "wish"
            default: return true
            }
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // 1. 页眉说明与快速操作
                headerBar

                // 2. 冲印装裱显影区
                if items.isEmpty {
                    compactDropBanner
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        dropCanvasArea
                            .frame(maxWidth: .infinity)

                        if let current = currentItem {
                            exifAndPublishInspector(current: current)
                                .frame(width: 320)
                        }
                    }
                }

                Divider().overlay(ArchivePalette.borderSubtle.opacity(0.6))

                // 3. 银盐底片回廊与相册 (Film Negatives Gallery)
                filmGallerySection
            }
            .padding(24)
            .onChange(of: selectedIndex) { _, newIndex in
                if items.indices.contains(newIndex),
                   let capAt = items[newIndex].photo.exifMetadata.capturedAt,
                   let date = FormatUtils.parseFlexDate(capAt) {
                    entryOccurredAt = date
                }
            }
        }
        .sheet(item: $selectedLightboxPhoto) { item in
            FilmLightboxModal(item: item) {
                selectedLightboxPhoto = nil
            } onJumpToEntry: { entry in
                selectedLightboxPhoto = nil
                appState.highlightedEntry = entry
                appState.activeSection = .stream
            }
        }
    }

    // MARK: - 刊头栏

    private var headerBar: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("银盐暗房 · 胶片回廊与相纸装裱")
                    .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text("拖入摄影原片或日常相纸，自动识别器材曝光参数并装裱入册")
                    .font(ArchiveTypography.bodySans(size: 12.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
            }
            Spacer()

            if !items.isEmpty {
                Text("待装裱 \(items.count) 张")
                    .font(ArchiveTypography.monoScale(size: 11, weight: .semibold))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(ArchivePalette.accentWarm.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    // MARK: - 吸顶紧凑拖拽装裱条 (当无待冲印图片时展示，消除大荒漠)

    private var compactDropBanner: some View {
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

            HStack(spacing: 16) {
                Image(systemName: isProcessing ? "camera.metering.multispot" : "photo.badge.plus")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(isDragTargeted ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isProcessing ? "正在装裱底片…" : "将照片拖拽至此处显影，或按 ⌘V 粘贴")
                        .font(ArchiveTypography.editorialSerif(size: 14.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("自动提取相机型号、镜头焦段与曝光 EXIF")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)

                    // 批量装裱进度（原先只有一个布尔量，用户不知道还要等多久）
                    if isProcessing {
                        ProgressView(value: processingProgress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 220)
                            .padding(.top, 4)
                            .accessibilityLabel("正在装裱底片")
                            .accessibilityValue("\(Int(processingProgress * 100))%")
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        pastePhotoFromClipboard()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                            Text("粘贴剪贴板 (⌘V)")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                    Button {
                        selectPhotoFromFinder()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("选择相片…")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                }
            }
            .padding(16)
        }
        .frame(minHeight: 76)
        .onDrop(of: [.fileURL, .image, .rawImage], isTargeted: $isDragTargeted) { providers in
            handleImageDrop(providers: providers)
            return true
        }
        .onPasteCommand(of: [.png, .tiff, .jpeg, .fileURL, .image]) { _ in
            pastePhotoFromClipboard()
        }
    }

    // MARK: - 待冲印画布与底片胶卷盒

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
                }
            }
            .frame(minHeight: 380)
            .onDrop(of: [.fileURL, .image, .rawImage], isTargeted: $isDragTargeted) { providers in
                handleImageDrop(providers: providers)
                return true
            }
            .onPasteCommand(of: [.png, .tiff, .jpeg, .fileURL, .image]) { _ in
                pastePhotoFromClipboard()
            }

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
                                        .background(Circle().fill(ArchivePalette.archivePaper))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("移除这张底片")
                                .offset(x: 3, y: -3)
                            }

                            Text("\(index + 1)")
                                .font(ArchiveTypography.monoScale(size: 10, weight: selectedIndex == index ? .bold : .regular))
                                .foregroundStyle(selectedIndex == index ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedIndex = index
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
                    .toggleStyle(.paperCheckbox)
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
            TextField("相片标题", text: $entryTitle)
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

            PaperDateTimePicker(selection: $entryOccurredAt, label: "记录时间", showQuickShortcuts: true)

            PaperCityPicker(
                selectedCode: $entryCityCode,
                selectedName: $entryCityName,
                placeholder: appState.profile.displayCity.isEmpty ? "点选拍摄城市…" : appState.profile.displayCity,
                label: "拍摄城市",
                isFullWidth: true
            )

            TextField("写下按下快门时的心境与手记…", text: $entryContent, axis: .vertical)
                .font(ArchiveTypography.bodySans(size: 12))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(2...4)
                .padding(10)
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

    // MARK: - 银盐底片回廊 (Film Negatives Gallery)

    private var filmGallerySection: some View {
        // 只遍历一次 entries × attachments：此前在标题/空态/网格里各算一遍
        let photos = filteredGalleryPhotos
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("银盐底片回廊")
                            .font(ArchiveTypography.editorialSerif(size: 17, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("(\(photos.count) 张)")
                            .font(ArchiveTypography.monoScale(size: 11.5, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    Text("收录生活时间流中所有装裱相纸底片，点击可放大检视或溯源手稿")
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(ArchiveCategory.allCases.filter { $0 != .transaction }) { cat in
                        PaperPillButton(
                            title: cat.label,
                            isSelected: galleryCategoryFilter == cat
                        ) {
                            galleryCategoryFilter = cat
                        }
                    }
                }
            }

            if photos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Text("尚无底片相纸记录")
                        .font(ArchiveTypography.editorialSerif(size: 14.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    Text("在上方拖入照片冲印，或在撰写散页时添加相片，底片将自动珍藏于此回廊中。")
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .padding(40)
                .frame(maxWidth: .infinity)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)], spacing: 16) {
                    ForEach(photos) { item in
                        GalleryPhotoCard(item: item) {
                            selectedLightboxPhoto = item
                        } onJumpToEntry: {
                            appState.highlightedEntry = item.parentEntry
                            appState.activeSection = .stream
                        }
                    }
                }
            }
        }
    }

    // MARK: - 单张底片卡片 (GalleryPhotoCard)

    private struct GalleryPhotoCard: View {
        let item: GalleryPhotoItem
        var onTap: () -> Void
        var onJumpToEntry: () -> Void

        @State private var isHovering: Bool = false

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    if let url = APIClient.shared.resolveMediaURL(item.attachment.url) {
                        CachedFilmImageView(url: url, maxHeight: 180)
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Rectangle()
                            .fill(ArchivePalette.archiveSubtle)
                            .frame(height: 180)
                    }

                    if isHovering {
                        Button {
                            onJumpToEntry()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right.square")
                                Text("溯源手稿")
                            }
                            .font(ArchiveTypography.monoScale(size: 10, weight: .medium))
                            .foregroundStyle(ArchivePalette.archivePaper)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(ArchivePalette.inkPrimary.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .transition(.opacity)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.parentEntry.title.isEmpty ? item.attachment.originalFilename : item.parentEntry.title)
                        .font(ArchiveTypography.editorialSerif(size: 13, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(FormatUtils.parseOccurredDate(item.parentEntry.occurredAt).dotDate)
                            .font(ArchiveTypography.monoScale(size: 10.5))
                            .foregroundStyle(ArchivePalette.inkMuted)

                        if let city = item.parentEntry.cityName ?? item.parentEntry.location, !city.isEmpty {
                            Text("·")
                                .font(ArchiveTypography.monoScale(size: 10))
                                .foregroundStyle(ArchivePalette.inkMuted)
                            Text(city)
                                .font(ArchiveTypography.bodySans(size: 10.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        if let w = item.attachment.width, let h = item.attachment.height {
                            Text("\(w)×\(h)")
                                .font(ArchiveTypography.monoScale(size: 10))
                                .foregroundStyle(ArchivePalette.inkMuted.opacity(0.8))
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(10)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isHovering ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: isHovering ? 1.0 : 0.5)
            )
            .shadow(color: ArchivePalette.inkPrimary.opacity(isHovering ? 0.08 : 0.02), radius: isHovering ? 8 : 2, x: 0, y: isHovering ? 4 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            .onHover { h in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = h
                }
            }
        }
    }

    // MARK: - 大图底片灯箱弹窗 (FilmLightboxModal)

    private struct FilmLightboxModal: View {
        let item: GalleryPhotoItem
        var onDismiss: () -> Void
        var onJumpToEntry: (LifeEntry) -> Void

        var body: some View {
            VStack(spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.parentEntry.title.isEmpty ? item.attachment.originalFilename : item.parentEntry.title)
                            .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        HStack(spacing: 8) {
                            Text(FormatUtils.parseOccurredDate(item.parentEntry.occurredAt).dotDateTime)
                                .font(ArchiveTypography.monoScale(size: 11))
                                .foregroundStyle(ArchivePalette.inkMuted)
                            if let loc = item.parentEntry.location ?? item.parentEntry.cityName, !loc.isEmpty {
                                Text("·")
                                    .font(ArchiveTypography.monoScale(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Text(loc)
                                    .font(ArchiveTypography.bodySans(size: 11))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        onJumpToEntry(item.parentEntry)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.right.circle")
                            Text("跳转至手稿手账")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 26, height: 26)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if let url = APIClient.shared.resolveMediaURL(item.attachment.url) {
                    FilmFrameView(
                        imageURL: url,
                        caption: item.parentEntry.title.isEmpty ? nil : item.parentEntry.title,
                        metaText: "\(item.attachment.originalFilename) · \(item.attachment.width ?? 0)×\(item.attachment.height ?? 0)px",
                        maxHeight: 520
                    )
                }

                HStack {
                    Text("文件大小: \(formatBytes(item.attachment.size))")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)

                    Spacer()

                    if let url = APIClient.shared.resolveMediaURL(item.attachment.url) {
                        Button {
                            openInPreview(url: url)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "macwindow.on.rectangle")
                                Text("在系统「预览」中查看")
                            }
                            .font(ArchiveTypography.bodySans(size: 11.5))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    }
                }
            }
            .padding(20)
            .frame(minWidth: 540, maxWidth: 780)
            .background(ArchivePalette.archivePaper)
        }

        private func formatBytes(_ bytes: Int64) -> String {
            let kb = Double(bytes) / 1024.0
            if kb < 1024.0 { return String(format: "%.0f KB", kb) }
            return String(format: "%.2f MB", kb / 1024.0)
        }

        private func openInPreview(url: URL) {
            Task { @MainActor in
                if let (data, _) = try? await URLSession.shared.data(from: url) {
                    let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                    try? data.write(to: tempPath, options: .atomic)
                    NSWorkspace.shared.open(tempPath)
                }
            }
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
        // NSItemProvider 不是 Sendable：用 @unchecked Sendable 盒子安全跨隔离域传递
        let box = DropLoader.makeProviderBox(providers)
        Task { @MainActor in
            let urls = await DropLoader.loadDroppablePhotoURLs(from: box)
            guard !urls.isEmpty else { return }
            await loadPhotos(from: urls)
        }
    }

    /// 批量装裱底片。
    /// 关键：原先逐张串行处理（每张 EXIF 解析 + 4K 解码 + JPEG 编码约 0.5~2 秒），
    /// 拖入 20 张需要 10~40 秒且毫无进度反馈。
    /// 现在改为**受限并发**（最多 3 张同时处理，避免 CPU 争抢）并展示整体进度。
    private func loadPhotos(from urls: [URL]) async {
        isProcessing = true
        errorMessage = nil
        let total = urls.count
        var finished = 0

        // 并发度上限：图片压制是 CPU 密集型，过高并发只会互相抢核
        let maxConcurrent = 3
        var index = 0

        while index < urls.count {
            let batch = urls[index..<min(index + maxConcurrent, urls.count)]
            index += maxConcurrent

            let results = await withTaskGroup(of: (URL, Result<DarkroomPhotoItem, Error>).self) { group -> [(URL, Result<DarkroomPhotoItem, Error>)] in
                for url in batch {
                    group.addTask {
                        do {
                            let result = try await ImageProcessor.processImageFileInBackground(at: url)
                            // autoreleasepool：批量处理时及时释放每张图的中间产物，
                            // 避免峰值内存 = N 张图之和
                            let preview: NSImage? = autoreleasepool {
                                NSImage(data: result.compressedData)
                            }
                            if let preview {
                                let item = DarkroomPhotoItem(photo: result, preview: preview, originalURL: url)
                                return (url, .success(item))
                            }
                            return (url, .failure(APIError.decodingFailure("无法解码图像预览")))
                        } catch {
                            return (url, .failure(error))
                        }
                    }
                }
                var collected: [(URL, Result<DarkroomPhotoItem, Error>)] = []
                for await outcome in group {
                    collected.append(outcome)
                }
                return collected
            }

            // 保持拖拽顺序
            for (_, outcome) in results.sorted(by: { a, b in
                let ia = urls.firstIndex(of: a.0) ?? 0
                let ib = urls.firstIndex(of: b.0) ?? 0
                return ia < ib
            }) {
                switch outcome {
                case .success(let item):
                    items.append(item)
                    if entryTitle.isEmpty {
                        if let originalURL = item.originalURL {
                            entryTitle = (originalURL.lastPathComponent as NSString).deletingPathExtension
                        }
                    }
                    if entryContent.isEmpty && !item.photo.exifMetadata.formattedCameraLine.isEmpty {
                        entryContent = item.photo.exifMetadata.formattedCameraLine
                    }
                    if let capAt = item.photo.exifMetadata.capturedAt, let date = FormatUtils.parseFlexDate(capAt) {
                        entryOccurredAt = date
                    }
                case .failure(let error):
                    self.errorMessage = "载入失败：\(error.localizedDescription)"
                }
                finished += 1
                processingProgress = total > 0 ? Double(finished) / Double(total) : 1
            }
        }

        selectedIndex = max(0, items.count - 1)
        isProcessing = false
        processingProgress = 0
    }

    private func removePhoto(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        if items.isEmpty {
            resetDarkroom()
        } else {
            selectedIndex = min(selectedIndex, items.count - 1)
        }
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
                    // 进度计数器放在引用盒中，避免可变局部变量被捕获进 @Sendable 闭包
                    let counter = UploadProgressCounter()

                    for item in items {
                        let att = try await R2DirectUploader.shared.uploadProcessedPhoto(item.photo) { prog in
                            Task { @MainActor in
                                self.uploadProgress = (counter.value + prog) / total
                            }
                        }
                        attachmentIds.append(att.id)
                        counter.value += 1
                        self.uploadProgress = counter.value / total
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
                        location: entryCityName.isEmpty ? nil : entryCityName,
                        cityCode: entryCityCode.isEmpty ? nil : entryCityCode,
                        cityName: entryCityName.isEmpty ? nil : entryCityName,
                        attachmentIds: attachmentIds,
                        featured: isFeatured,
                        occurredAt: FormatUtils.beijingISOString(from: entryOccurredAt)
                    )

                    resetDarkroom()
                    appState.showTemporaryBanner("已装裱并归档 \(attachmentIds.count) 张相纸至散页手记")
                    appState.activeSection = .stream
                } else {
                    // 单张装裱当前选中的底片（索引可能在上传期间被外部删除，必须校验）
                    guard items.indices.contains(selectedIndex) else {
                        self.isUploading = false
                        return
                    }
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
                        location: entryCityName.isEmpty ? nil : entryCityName,
                        cityCode: entryCityCode.isEmpty ? nil : entryCityCode,
                        cityName: entryCityName.isEmpty ? nil : entryCityName,
                        attachmentIds: [att.id],
                        featured: isFeatured,
                        occurredAt: FormatUtils.beijingISOString(from: entryOccurredAt)
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
        DropLoader.cleanupStaleDropFiles(olderThan: 0)
        items.removeAll()
        selectedIndex = 0
        entryTitle = ""
        entryContent = ""
        entryCityCode = ""
        entryCityName = ""
        entryOccurredAt = Date()
        isUploading = false
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

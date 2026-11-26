import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 胶片暗房装裱边框组件 (.film-frame)
/// 严格遵循 docs/ecosystem.md §4.1.2 规范：
/// 四周预留哑光衬纸留白，底部以等宽字体标注底片元数据与拍摄时间，带有相纸贴在日记本上的物理微隆起阴影
public struct FilmFrameView: View {
    public var imageURL: URL?
    /// 4K 原图地址（画面显示优先走缩略图 `imageURL`，右键拷贝/预览/导出/拖出一律优先走原图）
    public var originalURL: URL?
    /// 原始文件名（用于导出/预览补全真实扩展名，解决 `/files/thumbnail` 无后缀问题）
    public var preferredFilename: String?
    /// 原始像素宽高（用于在异步显影前精确锁定占位框比例，彻底消除 +80pt 列表跳动）
    public var intrinsicSize: CGSize?
    public var localImage: NSImage?
    public var caption: String?
    public var metaText: String?
    public var maxHeight: CGFloat
    public var onTap: (() -> Void)?
    /// 缩略图目标像素（nil = 按显示高度 × 2 自动计算）。
    /// 灯箱等多倍缩放场景可显式传更大的值，仍保持「缩略图」而非原图。
    public var thumbnailMaxPixel: Int?
    /// 导出/拷贝结果反馈（成功或失败）—— 由调用方接到横幅上
    public var onExportNotice: ((String) -> Void)?

    public init(
        imageURL: URL? = nil,
        originalURL: URL? = nil,
        preferredFilename: String? = nil,
        intrinsicSize: CGSize? = nil,
        localImage: NSImage? = nil,
        caption: String? = nil,
        metaText: String? = nil,
        maxHeight: CGFloat = 280,
        thumbnailMaxPixel: Int? = nil,
        onTap: (() -> Void)? = nil,
        onExportNotice: ((String) -> Void)? = nil
    ) {
        self.imageURL = imageURL
        self.originalURL = originalURL
        self.preferredFilename = preferredFilename
        self.intrinsicSize = intrinsicSize
        self.localImage = localImage
        self.caption = caption
        self.metaText = metaText
        self.maxHeight = maxHeight
        self.thumbnailMaxPixel = thumbnailMaxPixel
        self.onTap = onTap
        self.onExportNotice = onExportNotice
    }

    private var exportTargetURL: URL? {
        originalURL ?? imageURL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                ArchivePalette.archivePaper

                if let localImage {
                    let displayMaxH = min(maxHeight, max(64, localImage.size.height))
                    Image(nsImage: localImage)
                        .interpolation(.high)
                        .antialiased(true)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: displayMaxH)
                        .clipped()
                        .accessibilityLabel(caption ?? "相纸影像")
                } else if let imageURL {
                    CachedFilmImageView(
                        url: imageURL,
                        maxHeight: maxHeight,
                        maxPixelOverride: thumbnailMaxPixel,
                        intrinsicSize: intrinsicSize
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
            )

            if hasFooter {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.body))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let metaText, !metaText.isEmpty {
                        Text(metaText)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.label))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(10)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
        )
        // 原先这里有一层 radius 10 的模糊阴影（实测相纸框 61.5ms），
        // 而相纸框本身已有 0.5pt 描边；图片多的散页里，相纸框会成倍出现，
        // 去掉阴影可显著降低时间流滚动开销。
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        // 可点击的相纸需显式声明为按钮语义
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onTap != nil ? .isButton : AccessibilityTraits())
        .accessibilityLabel(caption ?? "相纸")
        .onDrag {
            makeDragItemProvider()
        }
        .contextMenu {
            Button {
                copyFilmImage()
            } label: {
                Label("拷贝相纸", systemImage: "doc.on.doc")
            }

            if let url = exportTargetURL {
                Button {
                    openInPreview(url: url)
                } label: {
                    Label("在系统「预览」中查看", systemImage: "macwindow.on.rectangle")
                }

                Button {
                    saveFilmImage(url: url)
                } label: {
                    Label("导出存储相纸…", systemImage: "square.and.arrow.down")
                }
            }
        }
    }

    /// 构造支持拖出至访达/桌面保存原图的 NSItemProvider
    private func makeDragItemProvider() -> NSItemProvider {
        if let localImage {
            return NSItemProvider(object: localImage)
        }
        guard let url = exportTargetURL else {
            return NSItemProvider()
        }
        let provider = NSItemProvider()
        let filenameHint = preferredFilename ?? caption
        provider.suggestedName = (PaperImageExport.normalizedFilename(filenameHint, fallbackURL: url) as NSString).deletingPathExtension
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.image.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            Task { @MainActor in
                do {
                    let data = try await PaperImageExport.data(for: url)
                    let safeName = PaperImageExport.normalizedFilename(filenameHint, fallbackURL: url, data: data)
                        .replacingOccurrences(of: "/", with: "-")
                    let dropDir = SyncManager.sharedStorageDirectory.appendingPathComponent("PreviewStaging", isDirectory: true)
                    try? FileManager.default.createDirectory(at: dropDir, withIntermediateDirectories: true)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dropDir.path)
                    let fileURL = dropDir.appendingPathComponent("drag-\(UUID().uuidString.prefix(8))-\(safeName)")
                    try data.write(to: fileURL, options: .atomic)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
                    completion(fileURL, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    /// 拷贝相纸（统一走 `PaperImageExport` + `SecureClipboard` 60s 清理，优先取原图）
    private func copyFilmImage() {
        if let localImage {
            SecureClipboard.copy(image: localImage)
            onExportNotice?("已拷贝相纸至剪贴板")
            return
        }
        guard let targetURL = exportTargetURL else { return }
        Task { @MainActor in
            switch await PaperImageExport.copyToClipboard(url: targetURL) {
            case .success(let message), .failure(let message):
                onExportNotice?(message)
            }
        }
    }

    /// 在系统「预览」中打开（统一走 `PaperImageExport`，优先取原图并补全后缀）
    private func openInPreview(url: URL) {
        let filenameHint = preferredFilename ?? caption
        Task { @MainActor in
            switch await PaperImageExport.openInSystemPreview(url: url, preferredFilename: filenameHint) {
            case .success(let message), .failure(let message):
                onExportNotice?(message)
            }
        }
    }

    /// 导出落盘（统一走 `PaperImageExport.presentSavePanel`，优先导出原图）
    private func saveFilmImage(url: URL) {
        let filenameHint = preferredFilename ?? caption
        Task { @MainActor in
            guard let result = await PaperImageExport.presentSavePanel(url: url, preferredFilename: filenameHint) else {
                return
            }
            switch result {
            case .success(let message), .failure(let message):
                onExportNotice?(message)
            }
        }
    }

    private var hasFooter: Bool {
        !(caption ?? "").isEmpty || !(metaText ?? "").isEmpty
    }
}

/// 相纸加载状态机（纯值类型，便于单测）。
///
/// 关键：用**代号**而不是布尔闸门。
///
/// `.task(id: url)` 在 url 变化时会取消旧任务并启动新任务，
/// 而取消是**异步投递**的：新任务启动时旧任务的清理还没执行。
/// 若用 `isLoading` 布尔量，新任务会被「已经在加载」的闸门直接挡掉
/// → 这一张图**永远不会被加载**；同时旧任务的 catch 会把
/// hasFailed 置 true → 界面显示「相纸载入失败」，即使 URL 完全正常。
///
/// 代号方案：每次加载领一个号，只有**最新那个**号的结果才被采纳。
/// url 变化时同时清空上一张的 `image` / `hasFailed`，
/// 避免灯箱切换附件后继续显示上一张相纸。
struct FilmImageLoadState {
    private(set) var url: URL?
    private(set) var generation: UInt64 = 0
    private(set) var image: NSImage?
    private(set) var hasFailed = false
    /// 当前 url 是否还欠一次加载（init 命中内存缓存时为 false）
    private(set) var needsReload = false

    init(url: URL?, cachedImage: NSImage? = nil) {
        self.url = url
        self.image = cachedImage
        self.needsReload = cachedImage == nil
    }

    /// url 变化：丢弃上一张的显示态并领取新代号。
    /// 同一 url 返回 nil —— 不重复触发加载。
    @discardableResult
    mutating func resetIfNeeded(to newURL: URL?) -> UInt64? {
        guard newURL != url else { return nil }
        url = newURL
        image = nil
        hasFailed = false
        needsReload = true
        generation &+= 1
        return generation
    }

    /// 领取本次加载的代号；旧代号的异步结果将全部失效。
    mutating func beginLoad() -> UInt64 {
        generation &+= 1
        needsReload = false
        return generation
    }

    /// 任务被取消（不是失败）：重新标记待加载，允许 task 重启后重试。
    /// 旧代号的取消不得污染新 url 的状态。
    mutating func markInterrupted(generation: UInt64) {
        guard isCurrent(generation) else { return }
        needsReload = true
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        generation == self.generation
    }

    /// 只有最新代号的结果才允许回写。
    @discardableResult
    mutating func accept(image newImage: NSImage, generation: UInt64) -> Bool {
        guard isCurrent(generation) else { return false }
        image = newImage
        hasFailed = false
        return true
    }

    @discardableResult
    mutating func acceptFailure(generation: UInt64) -> Bool {
        guard isCurrent(generation) else { return false }
        hasFailed = true
        return true
    }
}

/// 支持内存首帧命中与平滑解码展示的相纸图像视图（消除长列表翻阅时的白屏闪烁与纵向高度抖动）
public struct CachedFilmImageView: View {
    public let url: URL
    public let maxHeight: CGFloat
    /// 显式缩略图目标像素（nil = maxHeight × 2）
    public let maxPixelOverride: Int?
    /// 已知原始像素宽高（用于占位框等比锁定与小尺寸图片防放大模糊）
    public let intrinsicSize: CGSize?

    @State private var loadState: FilmImageLoadState

    /// 缩略图目标像素：显示高度的 2 倍（Retina），下限 160
    private static func thumbPixel(for displayHeight: CGFloat) -> Int {
        max(160, Int(displayHeight * 2))
    }

    private var targetPixel: Int {
        maxPixelOverride ?? Self.thumbPixel(for: maxHeight)
    }

    /// 结合原始像素宽高计算展示最大高度，防止小尺寸贴纸/图标在 Retina 下被拉伸 2 倍变糊
    private var effectiveMaxHeight: CGFloat {
        if let s = intrinsicSize, s.width > 0, s.height > 0 {
            let logicalHeight = max(64, s.height / 2.0)
            return min(maxHeight, logicalHeight)
        }
        return maxHeight
    }

    public init(
        url: URL,
        maxHeight: CGFloat,
        maxPixelOverride: Int? = nil,
        intrinsicSize: CGSize? = nil
    ) {
        self.url = url
        self.maxHeight = maxHeight
        self.maxPixelOverride = maxPixelOverride
        self.intrinsicSize = intrinsicSize
        // 只做缩略图内存命中（零 I/O）；磁盘降采样解码交给 .task 在后台完成
        _loadState = State(initialValue: FilmImageLoadState(
            url: url,
            cachedImage: PaperImageCache.memoryImage(
                for: url,
                maxPixel: maxPixelOverride ?? Self.thumbPixel(for: maxHeight)
            )
        ))
    }

    @ViewBuilder
    private func placeholderContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let s = intrinsicSize, s.width > 0, s.height > 0 {
            Color.clear
                .aspectRatio(s, contentMode: .fit)
                .frame(maxHeight: effectiveMaxHeight)
                .frame(maxWidth: .infinity)
                .overlay { content() }
        } else {
            content()
                .frame(maxWidth: .infinity, minHeight: min(140, maxHeight))
        }
    }

    public var body: some View {
        ZStack {
            if loadState.url == url, let image = loadState.image {
                let displayMaxH = maxPixelOverride == nil
                    ? min(effectiveMaxHeight, max(64, image.size.height / 2.0))
                    : maxHeight
                Image(nsImage: image)
                    .interpolation(.high)
                    .antialiased(true)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: displayMaxH)
                    .clipped()
            } else if loadState.url == url, loadState.hasFailed {
                placeholderContainer {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.artframe")
                            .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.sectionTitle))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .accessibilityHidden(true)
                        Text("相纸载入暂缓")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("相纸载入失败")
            } else {
                placeholderContainer {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("相纸显影中…")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("相纸载入中")
            }
        }
        .task(id: url) {
            await loadImage()
        }
        // 新 url 到达时先同步清掉旧图与失败标记，
        // 避免在 task 启动前的那一帧仍闪现上一张相纸。
        .onChange(of: url) { _, newURL in
            loadState.resetIfNeeded(to: newURL)
        }
    }

    private func loadImage() async {
        // 双保险：即使 onChange 尚未投递，task 自己也能发现 url 已变并重置。
        loadState.resetIfNeeded(to: url)

        // init 已命中内存缓存、或同一 url 已加载完成时不再重复解码/下载，
        // 避免 SwiftUI 分支切换引发加载风暴。
        guard loadState.needsReload else { return }

        let gen = loadState.beginLoad()

        let pixel = targetPixel
        if let cached = PaperImageCache.memoryImage(for: url, maxPixel: pixel) {
            loadState.accept(image: cached, generation: gen)
            return
        }
        // 磁盘降采样解码在后台队列完成，不再阻塞首帧
        if let diskHit = await PaperImageCache.loadImage(for: url, maxPixel: pixel) {
            guard loadState.isCurrent(gen) else { return }
            loadState.accept(image: diskHit, generation: gen)
            return
        }

        do {
            // 单飞：卡片与灯箱同时打开时共享同一次下载（稳定 URL 去重）。
            let data = try await ImageRequestCoalescer.shared.data(
                for: url,
                session: APIClient.mediaSession
            )
            guard loadState.isCurrent(gen) else { return }
            // 解码在专用 decodeQueue 上执行；返回后再校验一次代号，
            // 防止解码期间用户已切到下一张。
            let thumb = await PaperImageCache.storeDownloaded(rawData: data, for: url, maxPixel: pixel)
            guard loadState.isCurrent(gen) else { return }
            if let thumb {
                loadState.accept(image: thumb, generation: gen)
            } else {
                loadState.acceptFailure(generation: gen)
            }
        } catch is CancellationError {
            // 取消不是失败 —— 旧任务被新任务取代时不该留下「载入失败」；
            // 但同一代号的取消要重新标记待加载，避免重新出现时一直转圈。
            loadState.markInterrupted(generation: gen)
            return
        } catch {
            loadState.acceptFailure(generation: gen)
        }
    }
}

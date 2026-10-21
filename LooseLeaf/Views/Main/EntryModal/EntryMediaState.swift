// EntryMediaState.swift
// 创作模态相纸装裱状态容器 (@Observable)
// 职责：逐张相纸的压制 / 上传队列、进度、失败重试与附件汇总。

import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - 单张相纸的装裱任务

/// 相纸装裱任务状态
enum EntryUploadStatus: String {
    case pending    // 等待中
    case uploading  // 上传中
    case succeeded  // 成功
    case failed     // 失败

    /// 状态中文名（展示在任务卡片上）
    var label: String {
        switch self {
        case .pending: return "等待中"
        case .uploading: return "上传中"
        case .succeeded: return "成功"
        case .failed: return "失败"
        }
    }

    /// 状态图标
    var icon: String {
        switch self {
        case .pending: return "clock"
        case .uploading: return "arrow.up.circle"
        case .succeeded: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

/// 单张相纸的装裱任务（缩略图 + 进度 + 状态 + 重试素材）
@Observable
@MainActor
final class EntryUploadItem: Identifiable {
    let id = UUID()
    /// 展示名（文件名或「剪贴板相纸」）
    var displayName: String
    /// 当前状态
    var status: EntryUploadStatus = .pending
    /// 上传进度（0 ~ 1）
    var progress: Double = 0
    /// 失败原因
    var errorMessage: String?
    /// 本地缩略图（上传前就能看到，失败重试时依旧可见）
    var localThumbnail: NSImage?
    /// 上传成功后由服务端分配的附件
    var attachment: Attachment?
    /// 重试素材：本地文件 URL（沙箱外文件需安全作用域授权）或内存图片数据
    var sourceURL: URL?
    var sourceData: Data?

    init(displayName: String, sourceURL: URL? = nil, sourceData: Data? = nil) {
        self.displayName = displayName
        self.sourceURL = sourceURL
        self.sourceData = sourceData
    }
}

// MARK: - 相纸装裱状态容器

/// 相纸装裱状态容器 (@Observable)
///
/// 父 View 与各表单子 View 共享同一个实例：
/// - 表单子 View 只负责渲染与派发「选图 / 拖拽 / 粘贴 / 重试 / 移除」；
/// - 上传队列、逐张进度与失败汇总全部收敛在这里，父 View 提交时直接取 `uploadedAttachments`。
@Observable
@MainActor
final class EntryMediaState {

    /// 装裱任务队列（按入队顺序排列）
    var items: [EntryUploadItem] = []
    /// 相机底款信息（EXIF 摘要，来自最近一张成功解析的相纸）
    var extractedCameraLine: String = ""
    /// 失败汇总提示（与原「相纸上传失败：xxx」文案保持一致）
    var errorMessage: String?

    /// 是否仍有相纸排队或上传中（上传期间禁止提交）
    var isUploading: Bool {
        items.contains { $0.status == .pending || $0.status == .uploading }
    }

    /// 已成功装裱的附件（提交时取其 id）
    var uploadedAttachments: [Attachment] {
        items.compactMap(\.attachment)
    }

    /// 已装裱成功的张数
    var succeededCount: Int {
        items.filter { $0.status == .succeeded }.count
    }

    /// 整体进度（各任务平均，仅用于展示）
    var overallProgress: Double {
        guard !items.isEmpty else { return 0 }
        return items.map(\.progress).reduce(0, +) / Double(items.count)
    }

    /// 队列处理器是否已在运行（避免重复起跑）
    private var isRunnerActive: Bool = false

    // MARK: - 入队

    /// 入队一批本地文件（来自「选择相纸照片」/ 拖拽 / 剪贴板文件 URL）
    func enqueueFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls {
            items.append(EntryUploadItem(displayName: url.lastPathComponent, sourceURL: url))
        }
        startRunner()
    }

    /// 入队一张内存图片（⌘V 粘贴的截图）
    func enqueueImageData(_ data: Data, displayName: String) {
        items.append(EntryUploadItem(displayName: displayName, sourceData: data))
        startRunner()
    }

    /// 失败任务重试：素材仍在本地，直接重新排队
    func retry(_ item: EntryUploadItem) {
        item.status = .pending
        item.progress = 0
        item.errorMessage = nil
        startRunner()
    }

    /// 移除任务（成功任务移除时其附件一并从提交列表中消失，语义与原「移除附件」一致）
    func remove(_ item: EntryUploadItem) {
        items.removeAll { $0.id == item.id }
        refreshErrorSummary()
    }

    /// 清空全部相纸（提交成功后的收尾）
    func removeAll() {
        items.removeAll()
        errorMessage = nil
    }

    // MARK: - 选图 / 拖拽

    /// 从「照片」App / 访达选择相纸文件
    func pickAndUploadFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .jpeg, .png, .heic, .rawImage]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            enqueueFiles(panel.urls)
        }
    }

    /// 拖拽装裱：支持多文件同时拖入
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        // NSItemProvider 不是 Sendable：用 @unchecked Sendable 盒子安全跨隔离域传递
        let box = DropLoader.makeProviderBox(providers)
        Task { @MainActor [weak self] in
            let urls = await DropLoader.loadDroppablePhotoURLs(from: box)
            self?.enqueueFiles(urls)
        }
        return true
    }

    /// 粘贴装裱（⌘V / 「粘贴相纸」按钮）
    ///
    /// 优先读取系统剪贴板中的图片文件 URL（保留文件名与 EXIF），
    /// 其次读取图片二进制数据（系统截图），最后回退到 SwiftUI 提供的 provider 管线。
    func paste(providers: [NSItemProvider]) {
        Task { @MainActor [weak self] in
            let payload = await EntryPasteboard.readPayload()
            guard let self else { return }
            if !payload.fileURLs.isEmpty {
                self.enqueueFiles(payload.fileURLs)
                return
            }
            if let data = payload.imageData {
                let stamp = Int(Date().timeIntervalSince1970)
                self.enqueueImageData(data, displayName: "剪贴板相纸-\(stamp).jpg")
                return
            }
            guard !providers.isEmpty else { return }
            // NSItemProvider 不是 Sendable：用 @unchecked Sendable 盒子安全跨隔离域传递
            let box = DropLoader.makeProviderBox(providers)
            let urls = await DropLoader.loadDroppablePhotoURLs(from: box)
            self.enqueueFiles(urls)
        }
    }

    // MARK: - 上传队列

    /// 启动队列处理器（已有处理器在跑时直接返回，新入队任务会被同一条队列接走）
    private func startRunner() {
        guard !isRunnerActive else { return }
        isRunnerActive = true
        Task { @MainActor [weak self] in
            await self?.drainQueue()
            self?.isRunnerActive = false
        }
    }

    /// 逐张压制并上传：单张失败不打断其余任务
    private func drainQueue() async {
        while let item = items.first(where: { $0.status == .pending }) {
            await process(item)
            // 每处理完一张就刷新失败汇总，失败提示不必等到整批结束才出现
            refreshErrorSummary()
        }
        refreshErrorSummary()
    }

    /// 单张相纸的完整流水线：缩略图 → 端侧压制 → 直传对象存储
    private func process(_ item: EntryUploadItem) async {
        item.status = .uploading
        item.progress = 0.03
        item.errorMessage = nil
        do {
            // 1. 本地缩略图（离开主线程，避免大图解码卡住界面）
            item.localThumbnail = await makeThumbnail(for: item)

            // 2. 端侧 4K 压制
            let processed: ImageProcessor.ProcessedPhoto
            if let url = item.sourceURL {
                // 沙箱：NSOpenPanel 选中的文件位于沙箱容器之外，
                // 必须取得安全作用域授权才能读取，否则读取会静默失败。
                processed = try await SandboxFileAccess.withAccess(to: url) { scopedURL in
                    try await ImageProcessor.processImageFileInBackground(at: scopedURL)
                }
            } else if let data = item.sourceData {
                processed = try await ImageProcessor.processImageDataInBackground(
                    data,
                    originalFilename: item.displayName
                )
            } else {
                throw NSError(
                    domain: "LooseLeaf",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "缺少相纸来源，无法上传"]
                )
            }

            // 3. 相机底款信息（原先只写不读，用户看不到 EXIF 相机信息）
            let camera = processed.exifMetadata.formattedCameraLine
            if !camera.isEmpty {
                extractedCameraLine = camera
            }

            // 4. 直传对象存储（带逐张进度回调）
            let bridge = EntryProgressBridge { value in
                item.progress = value
            }
            let attachment = try await R2DirectUploader.shared.uploadProcessedPhoto(processed) { progress in
                bridge.emit(progress)
            }

            // 任务可能在上传途中被移除：此时不再挂载附件
            guard items.contains(where: { $0.id == item.id }) else { return }
            item.attachment = attachment
            item.progress = 1
            item.status = .succeeded
        } catch {
            item.status = .failed
            item.progress = 0
            item.errorMessage = error.localizedDescription
        }
    }

    /// 生成本地缩略图：解码在后台线程完成，只把 Data（Sendable）带回来
    private func makeThumbnail(for item: EntryUploadItem) async -> NSImage? {
        let url = item.sourceURL
        let sourceData = item.sourceData
        let thumbnailData: Data? = await Task.detached(priority: .userInitiated) { () -> Data? in
            if let url {
                return SandboxFileAccess.withAccess(to: url) { scopedURL in
                    EntryThumbnailMaker.thumbnailData(from: scopedURL)
                }
            }
            if let sourceData {
                return EntryThumbnailMaker.thumbnailData(from: sourceData)
            }
            return nil
        }.value
        guard let thumbnailData else { return nil }
        return NSImage(data: thumbnailData)
    }

    /// 汇总失败任务提示
    private func refreshErrorSummary() {
        let failures = items.filter { $0.status == .failed }
        guard !failures.isEmpty else {
            errorMessage = nil
            return
        }
        let details = failures.map { "\($0.displayName)：\($0.errorMessage ?? "未知错误")" }
        errorMessage = details.count == 1
            ? "相纸上传失败：\(details[0])"
            : "\(details.count) 张相纸上传失败：\(details.prefix(3).joined(separator: "；"))"
    }
}

// MARK: - 上传进度桥（跨隔离域安全投递）

/// 上传进度桥：把后台回调的进度值安全地投递到主线程的任务对象上。
///
/// 关键：R2DirectUploader 的进度回调是 `@Sendable (Double) -> Void`，
/// 而 `EntryUploadItem` 是 `@MainActor` 隔离的类型 —— 直接在回调里捕获它会跨隔离域访问状态。
/// 这里用 `@unchecked Sendable` 盒子把「主线程闭包」包起来，回调只碰盒子，不碰任务对象。
private final class EntryProgressBridge: @unchecked Sendable {
    private let onProgress: @MainActor (Double) -> Void

    init(onProgress: @escaping @MainActor (Double) -> Void) {
        self.onProgress = onProgress
    }

    func emit(_ value: Double) {
        Task { @MainActor in
            self.onProgress(value)
        }
    }
}

// MARK: - 相纸缩略图生成器

/// 相纸缩略图生成器
///
/// 只返回 `Data`（Sendable）而不是位图对象：位图对象跨隔离域传递会触发并发检查告警，
/// 而 JPEG 数据可以在后台线程生成、在主线程按需构造 `NSImage`。
enum EntryThumbnailMaker {
    /// 缩略图最长边像素
    private static let maxPixelSize = 240

    /// 从本地文件生成缩略图数据
    static func thumbnailData(from url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return encode(source)
    }

    /// 从内存图片数据生成缩略图数据
    static func thumbnailData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return encode(source)
    }

    private static func encode(_ source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }
}

// MARK: - 剪贴板相纸读取器

/// 剪贴板相纸载荷（`Data` 与 `URL` 均为 Sendable，可安全跨隔离域传递）
struct EntryPasteboardPayload: Sendable {
    /// 剪贴板中的图片二进制数据（截图）
    var imageData: Data?
    /// 剪贴板中的图片文件 URL（访达拷贝的文件，保留文件名与 EXIF）
    var fileURLs: [URL]

    var isEmpty: Bool {
        (imageData == nil) && fileURLs.isEmpty
    }
}

/// 剪贴板相纸读取器
///
/// 读取 `NSPasteboard.general`：优先取图片文件 URL（保留原始文件名与 EXIF），
/// 其次取 PNG / JPEG / TIFF 二进制数据，最后用 `NSImage` 兜底转 PNG。
enum EntryPasteboard {

    /// 异步读取剪贴板相纸载荷（文件 IO 与 PNG 重编码都在后台线程，不阻塞主线程）
    static func readPayload() async -> EntryPasteboardPayload {
        await Task.detached(priority: .userInitiated) {
            readPayloadSync()
        }.value
    }

    private static func readPayloadSync() -> EntryPasteboardPayload {
        let board = NSPasteboard.general

        // 1. 图片文件 URL（访达拷贝 / 截图工具写出的文件）
        if let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let imageURLs = urls.filter { url in
                guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
                return type.conforms(to: .image)
            }
            if !imageURLs.isEmpty {
                return EntryPasteboardPayload(imageData: nil, fileURLs: imageURLs)
            }
        }

        // 2. 图片二进制数据（系统截图 / 图片 App 拷贝）
        let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        for pasteType in [NSPasteboard.PasteboardType.png, jpegType, NSPasteboard.PasteboardType.tiff] {
            if let data = board.data(forType: pasteType), !data.isEmpty {
                return EntryPasteboardPayload(imageData: data, fileURLs: [])
            }
        }

        // 3. 兜底：NSImage 兜底转 PNG
        if let image = NSImage(pasteboard: board),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]),
           !pngData.isEmpty {
            return EntryPasteboardPayload(imageData: pngData, fileURLs: [])
        }

        return EntryPasteboardPayload(imageData: nil, fileURLs: [])
    }
}

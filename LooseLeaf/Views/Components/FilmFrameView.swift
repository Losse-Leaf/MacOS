import SwiftUI
import AppKit
import CryptoKit
import ImageIO

/// 胶片暗房装裱边框组件 (.film-frame)
/// 严格遵循 docs/ecosystem.md §4.1.2 规范：
/// 四周预留哑光衬纸留白，底部以等宽字体标注底片元数据与拍摄时间，带有相纸贴在日记本上的物理微隆起阴影
public struct FilmFrameView: View {
    public var imageURL: URL?
    public var localImage: NSImage?
    public var caption: String?
    public var metaText: String?
    public var maxHeight: CGFloat
    public var onTap: (() -> Void)?

    public init(
        imageURL: URL? = nil,
        localImage: NSImage? = nil,
        caption: String? = nil,
        metaText: String? = nil,
        maxHeight: CGFloat = 280,
        onTap: (() -> Void)? = nil
    ) {
        self.imageURL = imageURL
        self.localImage = localImage
        self.caption = caption
        self.metaText = metaText
        self.maxHeight = maxHeight
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                ArchivePalette.archivePaper

                if let localImage {
                    Image(nsImage: localImage)
                        .interpolation(.high)
                        .antialiased(true)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: maxHeight)
                        .clipped()
                } else if let imageURL {
                    CachedFilmImageView(url: imageURL, maxHeight: maxHeight)
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
                            .font(ArchiveTypography.editorialSerif(size: 12))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let metaText, !metaText.isEmpty {
                        Text(metaText)
                            .font(ArchiveTypography.monoScale(size: 10.5))
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
        .shadow(color: ArchivePalette.inkPrimary.opacity(0.08), radius: 10, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
            Button {
                copyFilmImage()
            } label: {
                Label("拷贝相纸", systemImage: "doc.on.doc")
            }

            if let url = imageURL {
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

    private func copyFilmImage() {
        if let localImage {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([localImage])
            return
        }
        if let imageURL {
            if let cached = PaperImageCache.image(for: imageURL) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([cached])
                return
            }
            Task { @MainActor in
                if let (data, _) = try? await URLSession.shared.data(from: imageURL),
                   let img = NSImage(data: data) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([img])
                }
            }
        }
    }

    private func openInPreview(url: URL) {
        Task { @MainActor in
            if let cached = PaperImageCache.image(for: url),
               let tiffData = cached.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? pngData.write(to: tempPath, options: .atomic)
                NSWorkspace.shared.open(tempPath)
                return
            }
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? data.write(to: tempPath, options: .atomic)
                NSWorkspace.shared.open(tempPath)
            }
        }
    }

    private func saveFilmImage(url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (caption?.isEmpty == false) ? "\(caption!).jpg" : url.lastPathComponent
        if panel.runModal() == .OK, let targetURL = panel.url {
            Task { @MainActor in
                if let (data, _) = try? await URLSession.shared.data(from: url) {
                    try? data.write(to: targetURL, options: .atomic)
                }
            }
        }
    }

    private var hasFooter: Bool {
        !(caption ?? "").isEmpty || !(metaText ?? "").isEmpty
    }
}

/// 相纸画廊专用双级缓存池 (Memory NSCache + Disk MediaCache)
/// 遵循 Local-First 架构：已查看相纸自动落盘，支持离线即刻本地显影
public enum PaperImageCache {
    private static let memoryCache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.totalCostLimit = 100 * 1024 * 1024 // 100 MB 内存解码池
        c.countLimit = 150
        return c
    }()

    private static let diskQueue = DispatchQueue(label: "com.looseleaf.media.diskcache", qos: .utility)

    /// 磁盘缓存硬上限；超出后按最后访问时间淘汰最旧文件
    private static let maxDiskBytes: Int64 = 300 * 1024 * 1024
    private static let diskLimitLock = NSLock()
    nonisolated(unsafe) private static var lastPruneAt: Date = .distantPast

    /// 测试注入点：覆盖磁盘缓存目录，避免测试写入用户真实 MediaCache
    nonisolated(unsafe) static var overrideDirectory: URL?

    public static var diskCacheDirectory: URL {
        let dir: URL
        if let overrideDirectory {
            dir = overrideDirectory
        } else {
            dir = SyncManager.sharedStorageDirectory.appendingPathComponent("MediaCache", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 稳定缓存键：SHA256(URL) 截断。
    /// 不能用 Swift `Hasher`——它每进程随机加盐，重启后 key 全变，磁盘缓存永不命中且旧文件永久堆积。
    private static func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        return "cache_\(hex.prefix(32)).\(ext)"
    }

    private static func diskFileURL(for url: URL) -> URL {
        diskCacheDirectory.appendingPathComponent(cacheKey(for: url))
    }

    /// 仅查内存（可在 View init 中安全调用，不触发磁盘 I/O）
    public static func memoryImage(for url: URL) -> NSImage? {
        memoryCache.object(forKey: url as NSURL)
    }

    /// 缩略图内存键：与原图内存缓存共存（磁盘始终只存原图）
    private static func thumbKey(_ url: URL, maxPixel: Int) -> NSURL {
        NSURL(string: "\(url.absoluteString)#thumb-\(maxPixel)") ?? url as NSURL
    }

    /// 仅查降采样缩略图内存（列表/网格 init 专用，零 I/O）
    public static func memoryImage(for url: URL, maxPixel: Int) -> NSImage? {
        memoryCache.object(forKey: thumbKey(url, maxPixel: maxPixel))
    }

    /// 按显示尺寸降采样的异步两级命中：单张 4K 原图解码约 39MB，缩略图仅约 0.5MB
    public static func loadImage(for url: URL, maxPixel: Int) async -> NSImage? {
        if let hit = memoryImage(for: url, maxPixel: maxPixel) {
            return hit
        }
        return await withCheckedContinuation { continuation in
            diskQueue.async {
                let image = decodeThumbnailFromDisk(url, maxPixel: maxPixel)
                if let image {
                    memoryCache.setObject(image, forKey: thumbKey(url, maxPixel: maxPixel), cost: maxPixel * maxPixel * 4)
                }
                continuation.resume(returning: image)
            }
        }
    }

    private static func decodeThumbnailFromDisk(_ url: URL, maxPixel: Int) -> NSImage? {
        guard let data = try? Data(contentsOf: diskFileURL(for: url)) else { return nil }
        return decodeThumbnail(from: data, maxPixel: maxPixel)
    }

    private static func decodeThumbnail(from data: Data, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// 下载完成后：原图落盘（异步）+ 指定尺寸缩略图进内存，不在主线程做全尺寸解码
    public static func storeDownloaded(rawData: Data, for url: URL, maxPixel: Int) -> NSImage? {
        let thumbnail = decodeThumbnail(from: rawData, maxPixel: maxPixel)
        if let thumbnail {
            memoryCache.setObject(thumbnail, forKey: thumbKey(url, maxPixel: maxPixel), cost: maxPixel * maxPixel * 4)
        }
        let diskURL = diskFileURL(for: url)
        diskQueue.async {
            try? rawData.write(to: diskURL, options: .atomic)
            pruneDiskCacheIfNeeded()
        }
        return thumbnail
    }

    /// 同步两级命中：仅供详情灯箱、导出、复制等允许阻塞的路径使用
    public static func image(for url: URL) -> NSImage? {
        if let memoryHit = memoryImage(for: url) {
            return memoryHit
        }
        return loadFromDisk(url)
    }

    /// 异步两级命中：列表卡片路径专用，磁盘读取与解码全部离开主线程
    public static func loadImage(for url: URL) async -> NSImage? {
        if let memoryHit = memoryImage(for: url) {
            return memoryHit
        }
        return await withCheckedContinuation { continuation in
            diskQueue.async {
                continuation.resume(returning: loadFromDisk(url))
            }
        }
    }

    private static func loadFromDisk(_ url: URL) -> NSImage? {
        let diskPath = diskFileURL(for: url)
        guard let diskData = try? Data(contentsOf: diskPath),
              let diskImage = NSImage(data: diskData) else {
            return nil
        }
        normalizePixelSize(diskImage)
        memoryCache.setObject(diskImage, forKey: url as NSURL, cost: diskData.count)
        return diskImage
    }

    private static func normalizePixelSize(_ image: NSImage) {
        if let rep = image.representations.first as? NSBitmapImageRep {
            image.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
    }

    public static func setImage(_ image: NSImage, rawData: Data? = nil, for url: URL, cost: Int = 0) {
        normalizePixelSize(image)
        memoryCache.setObject(image, forKey: url as NSURL, cost: cost)

        // 异步写入磁盘缓存，避免主线程 I/O 阻塞
        let diskURL = diskFileURL(for: url)
        diskQueue.async {
            if let rawData {
                try? rawData.write(to: diskURL, options: .atomic)
            } else if let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let jpeg = rep.representation(using: .jpeg, properties: [:]) {
                try? jpeg.write(to: diskURL, options: .atomic)
            }
            pruneDiskCacheIfNeeded()
        }
    }

    /// 超限淘汰：按修改时间从旧到新删除，直到回落至上限的 80%。最多每分钟执行一次。
    private static func pruneDiskCacheIfNeeded() {
        diskLimitLock.lock()
        let now = Date()
        if now.timeIntervalSince(lastPruneAt) < 60 {
            diskLimitLock.unlock()
            return
        }
        lastPruneAt = now
        diskLimitLock.unlock()

        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskCacheDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries: [(url: URL, size: Int64, modified: Date)] = []
        var total: Int64 = 0
        for file in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize else { continue }
            let modified = values.contentModificationDate ?? .distantPast
            total += Int64(size)
            entries.append((file, Int64(size), modified))
        }
        guard total > maxDiskBytes else { return }

        let target = Int64(Double(maxDiskBytes) * 0.8)
        for entry in entries.sorted(by: { $0.modified < $1.modified }) {
            guard total > target else { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

/// 支持内存首帧命中与平滑解码展示的相纸图像视图（消除长列表翻阅时的白屏闪烁）
public struct CachedFilmImageView: View {
    public let url: URL
    public let maxHeight: CGFloat

    @State private var loadedImage: NSImage?
    @State private var isLoading: Bool = false
    @State private var hasFailed: Bool = false

    /// 缩略图目标像素：显示高度的 2 倍（Retina），下限 160
    private static func thumbPixel(for displayHeight: CGFloat) -> Int {
        max(160, Int(displayHeight * 2))
    }

    public init(url: URL, maxHeight: CGFloat) {
        self.url = url
        self.maxHeight = maxHeight
        // 只做缩略图内存命中（零 I/O）；磁盘降采样解码交给 .task 在后台完成
        _loadedImage = State(initialValue: PaperImageCache.memoryImage(for: url, maxPixel: Self.thumbPixel(for: maxHeight)))
    }

    public var body: some View {
        Group {
            if let image = loadedImage {
                Image(nsImage: image)
                    .interpolation(.high)
                    .antialiased(true)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
                    .clipped()
            } else if hasFailed {
                VStack(spacing: 6) {
                    Image(systemName: "photo.artframe")
                        .font(.system(size: 22))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Text("相纸载入暂缓")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("暗房显影中…")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .task(id: url) {
                    await loadImage()
                }
            }
        }
    }

    private func loadImage() async {
        let pixel = Self.thumbPixel(for: maxHeight)
        if let cached = PaperImageCache.memoryImage(for: url, maxPixel: pixel) {
            self.loadedImage = cached
            return
        }
        // 磁盘降采样解码在后台队列完成，不再阻塞首帧
        if let diskHit = await PaperImageCache.loadImage(for: url, maxPixel: pixel) {
            self.loadedImage = diskHit
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let thumb = PaperImageCache.storeDownloaded(rawData: data, for: url, maxPixel: pixel) {
                self.loadedImage = thumb
            } else {
                self.hasFailed = true
            }
        } catch {
            self.hasFailed = true
        }
    }
}

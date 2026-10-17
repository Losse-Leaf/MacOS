import SwiftUI
import AppKit

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
            AudioFeedback.shared.playTink()
            return
        }
        if let imageURL {
            if let cached = PaperImageCache.image(for: imageURL) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([cached])
                AudioFeedback.shared.playTink()
                return
            }
            Task { @MainActor in
                if let (data, _) = try? await URLSession.shared.data(from: imageURL),
                   let img = NSImage(data: data) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([img])
                    AudioFeedback.shared.playTink()
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
                    AudioFeedback.shared.playShutter()
                }
            }
        }
    }

    private var hasFooter: Bool {
        !(caption ?? "").isEmpty || !(metaText ?? "").isEmpty
    }
}

/// 相纸画廊专用双级缓存池 (Memory NSCache + Disk MediaCache)
/// 遵循 Local-First 架构：已查看相纸自动落盘，支持离线 0ms 本地显影
public enum PaperImageCache {
    private static let memoryCache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.totalCostLimit = 100 * 1024 * 1024 // 100 MB 内存解码池
        c.countLimit = 150
        return c
    }()

    private static let diskQueue = DispatchQueue(label: "com.looseleaf.media.diskcache", qos: .utility)

    public static var diskCacheDirectory: URL {
        let dir = SyncManager.sharedStorageDirectory.appendingPathComponent("MediaCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cacheKey(for url: URL) -> String {
        let raw = url.absoluteString
        var hasher = Hasher()
        hasher.combine(raw)
        let hash = abs(hasher.finalize())
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        return "cache_\(hash).\(ext)"
    }

    private static func diskFileURL(for url: URL) -> URL {
        diskCacheDirectory.appendingPathComponent(cacheKey(for: url))
    }

    public static func image(for url: URL) -> NSImage? {
        // 1. 内存一级命中
        if let memoryHit = memoryCache.object(forKey: url as NSURL) {
            return memoryHit
        }

        // 2. 磁盘二级命中 (0ms 离线即刻读盘)
        let diskPath = diskFileURL(for: url)
        if FileManager.default.fileExists(atPath: diskPath.path),
           let diskData = try? Data(contentsOf: diskPath),
           let diskImage = NSImage(data: diskData) {
            if let rep = diskImage.representations.first as? NSBitmapImageRep {
                diskImage.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            }
            memoryCache.setObject(diskImage, forKey: url as NSURL, cost: diskData.count)
            return diskImage
        }

        return nil
    }

    public static func setImage(_ image: NSImage, rawData: Data? = nil, for url: URL, cost: Int = 0) {
        if let rep = image.representations.first as? NSBitmapImageRep {
            image.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
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

    public init(url: URL, maxHeight: CGFloat) {
        self.url = url
        self.maxHeight = maxHeight
        _loadedImage = State(initialValue: PaperImageCache.image(for: url))
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
        if let cached = PaperImageCache.image(for: url) {
            self.loadedImage = cached
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = NSImage(data: data) {
                PaperImageCache.setImage(image, rawData: data, for: url, cost: data.count)
                self.loadedImage = image
            } else {
                self.hasFailed = true
            }
        } catch {
            if let diskHit = PaperImageCache.image(for: url) {
                self.loadedImage = diskHit
            } else {
                self.hasFailed = true
            }
        }
    }
}

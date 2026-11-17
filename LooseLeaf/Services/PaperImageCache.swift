import AppKit
import CryptoKit
import Foundation
import ImageIO

/// 相纸画廊专用双级缓存池 (Memory NSCache + Disk MediaCache)
/// 遵循 Local-First 架构：已查看相纸自动落盘原图字节，显示层按 `maxPixel` 降采样进内存缓存
public enum PaperImageCache {
    // NSCache 本身是线程安全的（Apple 明确保证），因此作为不可变常量共享是安全的。
    nonisolated(unsafe) private static let memoryCache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.totalCostLimit = 60 * 1024 * 1024 // 60 MB 缩略图解码池
        c.countLimit = 300
        return c
    }()

    /// 计算 NSImage 真实占用的位图内存（字节数），用于 NSCache cost。
    /// 兼容 `NSBitmapImageRep` 与 `NSImage(cgImage:size:)` 生成的 `NSCGImageSnapshotRep`（避免恒返回 1 字节导致 60MB 上限失效）。
    static func bitmapByteCost(of image: NSImage) -> Int {
        var total = 0
        for rep in image.representations {
            if let bitmap = rep as? NSBitmapImageRep {
                total += bitmap.bytesPerRow * bitmap.pixelsHigh
            } else if let cg = rep.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                total += cg.bytesPerRow * cg.height
            } else if rep.pixelsWide > 0, rep.pixelsHigh > 0 {
                total += rep.pixelsWide * rep.pixelsHigh * 4
            }
        }
        if total == 0, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            total = cg.bytesPerRow * cg.height
        }
        return max(total, 1)
    }

    /// 主动清空内存图片缓存（主窗口关闭退驻菜单栏或收到内存告警时释放位图池）
    public static func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    /// 彻底清空内存与磁盘媒体缓存（解除设备配对或 401 吊销时零残留清理）
    public static func clearAllCaches() {
        clearMemoryCache()
        touchLock.lock()
        lastTouchedAt.removeAll()
        touchLock.unlock()
        let dir = diskCacheDirectory
        writeQueue.async {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// 磁盘读取：并发受控（4 路），只做 `Data(contentsOf:)`，不做解码。
    private static let diskIOQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.looseleaf.media.diskio"
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// 图片解码：独立并发池（3 路），与磁盘 I/O 解耦。
    private static let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.looseleaf.media.decode"
        queue.maxConcurrentOperationCount = 3
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// 磁盘写入：串行（避免同一文件并发写），utility 优先级。
    private static let writeQueue = DispatchQueue(label: "com.looseleaf.media.write", qos: .utility)

    /// 缓存淘汰：独立低优先级，绝不和前台读图抢线程。
    private static let maintenanceQueue = DispatchQueue(
        label: "com.looseleaf.media.maintenance",
        qos: .background
    )

    /// per-key 单飞：同一张图 + 同一尺寸只解码一次。
    private final class DecodeTaskBox: @unchecked Sendable {
        let task: Task<NSImage?, Never>
        init(_ task: Task<NSImage?, Never>) { self.task = task }
    }
    private static let decodeFlightLock = NSLock()
    nonisolated(unsafe) private static var inFlightDecodes: [String: DecodeTaskBox] = [:]

    /// per-key 写入去重：卡片与灯箱同时下载到同一份字节时只落盘一次。
    private static let writeFlightLock = NSLock()
    nonisolated(unsafe) private static var pendingDiskWrites: Set<String> = []

    /// 在指定 OperationQueue 上执行同步工作，并用 continuation 回到调用方。
    private static func runOnQueue<T>(_ queue: OperationQueue, _ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.addOperation {
                continuation.resume(returning: work())
            }
        }
    }

    /// 读取文件字节（并发 4 路，不阻塞主线程）
    private static func readData(at url: URL) async -> Data? {
        await runOnQueue(diskIOQueue) {
            try? Data(contentsOf: url)
        }
    }

    /// 磁盘缓存硬上限；超出后按最后访问时间淘汰最旧文件
    private static let maxDiskBytes: Int64 = 300 * 1024 * 1024
    private static let diskLimitLock = NSLock()
    nonisolated(unsafe) private static var lastPruneAt: Date = .distantPast

    /// 测试注入点：覆盖磁盘缓存目录，避免测试写入用户真实 MediaCache
    nonisolated(unsafe) static var overrideDirectory: URL?

    private static let defaultDiskCacheDirectory: URL = {
        let dir = SyncManager.sharedStorageDirectory.appendingPathComponent("MediaCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let touchLock = NSLock()
    nonisolated(unsafe) private static var lastTouchedAt: [String: Date] = [:]

    public static var diskCacheDirectory: URL {
        if let overrideDirectory {
            try? FileManager.default.createDirectory(at: overrideDirectory, withIntermediateDirectories: true)
            return overrideDirectory
        }
        return defaultDiskCacheDirectory
    }

    /// 稳定身份标识：剥掉预签名参数后的 URL。
    public static func stableKeyURL(for url: URL) -> URL {
        MediaURLIdentity.stableURL(for: url)
    }

    /// 稳定缓存键：SHA256(剥掉签名参数后的 URL) 截断。
    private static func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(stableKeyURL(for: url).absoluteString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        return "cache_\(hex.prefix(32)).\(ext)"
    }

    private static func diskFileURL(for url: URL) -> URL {
        diskCacheDirectory.appendingPathComponent(cacheKey(for: url))
    }

    /// 仅供测试/诊断：磁盘缓存文件位置
    public static func diskCacheFileURL(for url: URL) -> URL {
        diskFileURL(for: url)
    }

    /// 缩略图内存键（一律基于剥掉签名参数后的稳定身份）
    private static func thumbKey(_ url: URL, maxPixel: Int) -> NSURL {
        let stable = stableKeyURL(for: url).absoluteString
        return NSURL(string: "\(stable)#thumb-\(maxPixel)") ?? stableKeyURL(for: url) as NSURL
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
        return await decodeThumbnailSingleFlight(url: url, maxPixel: maxPixel)
    }

    /// 仅供测试：观察「真正开始一次解码」的次数（用于验证 per-key 单飞）
    nonisolated(unsafe) static var decodeObserverForTesting: (@Sendable (URL, Int) -> Void)?

    /// 同一 (稳定 URL, maxPixel) 的并发解码只执行一次。
    private static func decodeThumbnailSingleFlight(url: URL, maxPixel: Int) async -> NSImage? {
        let key = thumbCacheKeyString(url, maxPixel: maxPixel)

        let box: DecodeTaskBox = withDecodeFlightLock {
            if let existing = inFlightDecodes[key] { return existing }
            let task = Task<NSImage?, Never> {
                decodeObserverForTesting?(url, maxPixel)
                return await decodeThumbnailFromDisk(url, maxPixel: maxPixel)
            }
            let created = DecodeTaskBox(task)
            inFlightDecodes[key] = created
            return created
        }

        let image = await box.task.value

        withDecodeFlightLock {
            if inFlightDecodes[key] === box {
                inFlightDecodes[key] = nil
            }
        }
        return image
    }

    private static func thumbCacheKeyString(_ url: URL, maxPixel: Int) -> String {
        thumbKey(url, maxPixel: maxPixel).absoluteString
            ?? stableKeyURL(for: url).absoluteString
    }

    private static func withDecodeFlightLock<T>(_ body: () -> T) -> T {
        decodeFlightLock.lock()
        defer { decodeFlightLock.unlock() }
        return body()
    }

    private static func decodeThumbnailFromDisk(_ url: URL, maxPixel: Int) async -> NSImage? {
        let diskPath = diskFileURL(for: url)
        guard FileManager.default.fileExists(atPath: diskPath.path) else { return nil }
        let decoded = await runOnQueue(decodeQueue) {
            decodeThumbnail(at: diskPath, maxPixel: maxPixel)
        }
        if let (image, byteCost) = decoded {
            memoryCache.setObject(
                image,
                forKey: thumbKey(url, maxPixel: maxPixel),
                cost: byteCost
            )
            touchDiskFile(at: diskPath)
            return image
        }
        return nil
    }

    private static func decodeThumbnail(at fileURL: URL, maxPixel: Int) -> (NSImage, Int)? {
        let srcOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, srcOpts as CFDictionary) else { return nil }
        return createThumbnail(from: source, maxPixel: maxPixel)
    }

    private static func decodeThumbnail(from data: Data, maxPixel: Int) -> (NSImage, Int)? {
        let srcOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, srcOpts as CFDictionary) else { return nil }
        return createThumbnail(from: source, maxPixel: maxPixel)
    }

    private static func createThumbnail(from source: CGImageSource, maxPixel: Int) -> (NSImage, Int)? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let cost = bitmapByteCost(of: image)
        return (image, cost)
    }

    /// 下载完成后：指定尺寸缩略图在专用解码队列生成（await 回调用方），原始字节在写队列落盘一次。
    public static func storeDownloaded(rawData: Data, for url: URL, maxPixel: Int) async -> NSImage? {
        let decoded = await runOnQueue(decodeQueue) {
            decodeThumbnail(from: rawData, maxPixel: maxPixel)
        }
        let thumbnail = decoded?.0
        if let (image, byteCost) = decoded {
            memoryCache.setObject(
                image,
                forKey: thumbKey(url, maxPixel: maxPixel),
                cost: byteCost
            )
        }
        enqueueDiskWrite(rawData, for: url)
        return thumbnail
    }

    /// 原始字节落盘（per-key 去重 + 串行写）
    private static func enqueueDiskWrite(_ data: Data, for url: URL) {
        let key = stableKeyURL(for: url).absoluteString
        writeFlightLock.lock()
        let inserted = pendingDiskWrites.insert(key).inserted
        writeFlightLock.unlock()
        guard inserted else { return }

        let diskURL = diskFileURL(for: url)
        writeQueue.async {
            try? data.write(to: diskURL, options: .atomic)
            writeFlightLock.lock()
            pendingDiskWrites.remove(key)
            writeFlightLock.unlock()
            maintenanceQueue.async {
                pruneDiskCacheIfNeeded()
            }
        }
    }

    /// 异步读取磁盘缓存的原始字节（导出/拷贝路径专用，不做解码）
    public static func loadRawData(for url: URL) async -> Data? {
        await readData(at: diskFileURL(for: url))
    }

    /// 触达磁盘缓存文件：更新修改时间，使其成为「最近使用」（1 小时内节流免重复写 inode）
    private static func touchDiskFile(at url: URL) {
        let path = url.path
        let now = Date()
        touchLock.lock()
        if let last = lastTouchedAt[path], now.timeIntervalSince(last) < 3600 {
            touchLock.unlock()
            return
        }
        lastTouchedAt[path] = now
        touchLock.unlock()
        maintenanceQueue.async {
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: path)
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

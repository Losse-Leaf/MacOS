import Foundation
import AppKit
import UniformTypeIdentifiers

/// 拖拽 / 粘贴载荷统一加载工具：
/// 将 NSItemProvider 的异步回调与 NSPasteboard 剪贴板读取封装供捕捉面板与暗房共用（拒绝重复实现）。
public enum DropLoader {

    /// 主线程安全提取剪贴板原始载荷（避免在后台线程直接读写非线程安全的 NSPasteboard.general）
    private enum RawPasteboardSnapshot: Sendable {
        case directData(Data)
        case fileURLs([URL])
        case tiffData(Data)
        case empty
    }

    @MainActor
    private static func capturePasteboardSnapshotOnMain() -> RawPasteboardSnapshot {
        let pb = NSPasteboard.general
        let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        for pasteType in [NSPasteboard.PasteboardType.png, jpegType, NSPasteboard.PasteboardType.tiff] {
            if let data = pb.data(forType: pasteType), !data.isEmpty {
                return .directData(data)
            }
        }
        var urls: [URL] = []
        if let urlData = pb.data(forType: .fileURL),
           let fileURL = URL(dataRepresentation: urlData, relativeTo: nil) {
            urls.append(fileURL)
        }
        if let readURLs = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            urls.append(contentsOf: readURLs.filter(\.isFileURL))
        }
        if !urls.isEmpty {
            return .fileURLs(urls)
        }
        if let image = NSImage(pasteboard: pb),
           let tiffData = image.tiffRepresentation,
           !tiffData.isEmpty {
            return .tiffData(tiffData)
        }
        return .empty
    }

    /// 异步读取系统通用剪贴板中的图像二进制数据：
    /// 主线程仅做 <1ms 的 NSPasteboard 内存快照捕获，文件读取与 PNG 重编码全部在后台线程完成。
    public static func readImageFromPasteboardAsync() async -> Data? {
        let snapshot = await MainActor.run { capturePasteboardSnapshotOnMain() }
        return await Task.detached(priority: .userInitiated) {
            switch snapshot {
            case .directData(let data):
                return data
            case .fileURLs(let urls):
                for url in urls {
                    if let fileData = try? Data(contentsOf: url), !fileData.isEmpty {
                        return fileData
                    }
                }
                return nil
            case .tiffData(let tiffData):
                if let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]),
                   !pngData.isEmpty {
                    return pngData
                }
                return tiffData
            case .empty:
                return nil
            }
        }.value
    }

    /// 清理暗房拖拽历史遗留的临时文件（应用启动与暗房重置时调用；olderThan <= 0 表示全清）
    public static func cleanupStaleDropFiles(olderThan interval: TimeInterval = 3600) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LooseLeafDarkroomDrop", isDirectory: true)
        DispatchQueue.global(qos: .utility).async {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return }
            let cutoff = Date().addingTimeInterval(-interval)
            for file in files {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if modified < cutoff {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    /// 从单个 provider 提取文件 URL（Finder 拖拽场景）
    /// 读取用户拖入 / 选中的图片文件（沙箱下需取得安全作用域授权）
    public static func loadImageData(fromAccessibleFile url: URL) async -> Data? {
        // 同步闭包不需要 await（withAccess 的同步重载）
        SandboxFileAccess.withAccess(to: url) { scopedURL in
            try? Data(contentsOf: scopedURL, options: .mappedIfSafe)
        }
    }

    static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        // 关键：加超时兜底。少数第三方 NSItemProvider 会静默不回调，
        // 原实现会让 continuation 永不 resume → 拖拽界面永远转圈。
        // NSItemProvider 不是 Sendable：用 @unchecked Sendable 盒子安全跨隔离域传递。
        let box = ProviderBox([provider])
        return await withTimeout(seconds: 10) {
            await withCheckedContinuation { continuation in
                box.providers[0].loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let u = item as? URL {
                        url = u
                    } else if let d = item as? Data {
                        url = URL(dataRepresentation: d, relativeTo: nil)
                    } else {
                        url = nil
                    }
                    continuation.resume(returning: url)
                }
            }
        }
    }

    /// 带超时兜底的 await：超时后返回 nil，避免 continuation 永不恢复导致的挂起。
    /// `operation` 返回 `T?`；`nil` 既表示「超时」，也表示「本身就没有结果」。
    ///
    /// 注意：不能用 `withTaskGroup` 做这件事。TaskGroup 在退出作用域时会等待**所有**
    /// 子任务结束；如果 `operation` 卡在一个永不回调的 `NSItemProvider` continuation 上，
    /// 即使超时分支已经返回，group 仍会永久等待，界面照样卡死。
    /// 这里改为「一次性 continuation + 两个独立 Task 竞争」，谁先到谁恢复，另一个结果丢弃。
    static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let once = TimeoutContinuation(continuation)
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                once.resume(nil)
            }
            Task {
                let value = await operation()
                timeoutTask.cancel()
                once.resume(value)
            }
        }
    }

    /// 保证 CheckedContinuation 只恢复一次：超时与真实结果竞争时，后到者被忽略。
    private final class TimeoutContinuation<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T?, Never>?

        init(_ continuation: CheckedContinuation<T?, Never>) {
            self.continuation = continuation
        }

        func resume(_ value: T?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }

    /// 从单个 provider 提取可处理的图片 URL（优先 Finder 本地文件；若从 Apple Photos / 网页浏览器拖入，自动提取图像流写入临时暗房沙箱）
    static func loadDroppablePhotoURL(from provider: NSItemProvider) async -> URL? {
        if let directURL = await loadFileURL(from: provider) {
            return directURL
        }
        // 降级：若从系统照片.app 或浏览器拖拽，未能提供直接 fileURL 时，提取图像流并暂存
        if let data = await loadImageData(from: provider) {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LooseLeafDarkroomDrop", isDirectory: true)
            // 扩展名按实际数据类型推断（硬编码 .jpg 会让 PNG/HEIC/TIFF 文件名误导）
            let ext = ImageFormatSniffer.fileExtension(for: data)
            let tempFile = tempDir.appendingPathComponent("drop-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).\(ext)")
            // 写盘必须离开主线程（continuation 恢复到调用方的 @MainActor 上下文）
            return await Task.detached(priority: .userInitiated) { () -> URL? in
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                do {
                    try data.write(to: tempFile, options: .atomic)
                    return tempFile
                } catch {
                    return nil
                }
            }.value
        }
        return nil
    }

    /// 批量提取可处理的图片 URL（支持 Finder、系统照片.app 与浏览器混合多选拖拽）
    /// 关键：并发提取而非逐个 await。原先串行处理 20 张图需要 10~40 秒。
    static func loadDroppablePhotoURLs(from box: ProviderBox) async -> [URL] {
        guard !box.providers.isEmpty else { return [] }
        // 只捕获 box（@unchecked Sendable），不捕获非 Sendable 的数组本身
        return await withTaskGroup(of: (Int, URL?).self) { group -> [URL] in
            for (index, provider) in box.providers.enumerated() {
                // 逐个装箱传递，避免在 @Sendable 子任务闭包中捕获非 Sendable 的数组
                let single = ProviderBox([provider])
                group.addTask { (index, await loadDroppablePhotoURL(from: single.providers[0])) }
            }
            var collected: [(Int, URL)] = []
            for await (index, url) in group {
                if let url { collected.append((index, url)) }
            }
            // 保持拖拽提供的原始顺序
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// 便捷入口：直接传入 provider 数组
    static func loadDroppablePhotoURLs(from providers: [NSItemProvider]) async -> [URL] {
        await loadDroppablePhotoURLs(from: ProviderBox(providers))
    }

    /// NSItemProvider 数组的 Sendable 包装（AppKit 未标注 Sendable，
    /// 但 NSItemProvider 的读取接口是线程安全的，因此在并发任务间传递是安全的）
    public final class ProviderBox: @unchecked Sendable {
        public let providers: [NSItemProvider]
        init(_ providers: [NSItemProvider]) { self.providers = providers }
    }

    /// 创建可跨隔离域传递的 provider 包装
    public static func makeProviderBox(_ providers: [NSItemProvider]) -> ProviderBox {
        ProviderBox(providers)
    }

    /// 从单个 provider 提取图像二进制数据（支持 JPEG、PNG、HEIC、TIFF、通用图像）
    static func loadImageData(from provider: NSItemProvider) async -> Data? {
        let candidates = [
            UTType.jpeg.identifier,
            UTType.png.identifier,
            UTType.heic.identifier,
            UTType.tiff.identifier,
            UTType.image.identifier
        ]
        for identifier in candidates where provider.hasItemConformingToTypeIdentifier(identifier) {
            // NSItemProvider 不是 Sendable：用 @unchecked Sendable 盒子安全跨隔离域传递
            let box = ProviderBox([provider])
            let data = await withTimeout(seconds: 15) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                    box.providers[0].loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                        continuation.resume(returning: data)
                    }
                }
            }
            if let data, !data.isEmpty {
                return data
            }
        }
        return nil
    }
}

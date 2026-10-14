import Foundation
import UniformTypeIdentifiers

/// 拖拽 / 粘贴载荷统一加载工具：
/// 将 NSItemProvider 的异步回调封装为 async/await，供捕捉面板与暗房共用（拒绝重复实现）。
enum DropLoader {

    /// 从单个 provider 提取文件 URL（Finder 拖拽场景）
    static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
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

    /// 批量提取文件 URL（多张拖拽场景，保持顺序）
    static func loadFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadFileURL(from: provider) {
                urls.append(url)
            }
        }
        return urls
    }

    /// 从单个 provider 提取可处理的图片 URL（优先 Finder 本地文件；若从 Apple Photos / 网页浏览器拖入，自动提取图像流写入临时暗房沙箱）
    static func loadDroppablePhotoURL(from provider: NSItemProvider) async -> URL? {
        if let directURL = await loadFileURL(from: provider) {
            return directURL
        }
        // 降级：若从系统照片.app 或浏览器拖拽，未能提供直接 fileURL 时，提取图像流并暂存
        if let data = await loadImageData(from: provider) {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LooseLeafDarkroomDrop", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempFile = tempDir.appendingPathComponent("drop-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).jpg")
            do {
                try data.write(to: tempFile, options: .atomic)
                return tempFile
            } catch {
                return nil
            }
        }
        return nil
    }

    /// 批量提取可处理的图片 URL（支持 Finder、系统照片.app 与浏览器混合多选拖拽）
    static func loadDroppablePhotoURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadDroppablePhotoURL(from: provider) {
                urls.append(url)
            }
        }
        return urls
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
            let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            if let data, !data.isEmpty {
                return data
            }
        }
        return nil
    }
}

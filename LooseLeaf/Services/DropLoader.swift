import Foundation
import AppKit
import UniformTypeIdentifiers

/// 拖拽 / 粘贴载荷统一加载工具：
/// 将 NSItemProvider 的异步回调与 NSPasteboard 剪贴板读取封装供捕捉面板与暗房共用（拒绝重复实现）。
public enum DropLoader {

    /// 从系统通用剪贴板 (NSPasteboard.general) 读取图像二进制数据
    /// 依次尝试：PNG、JPEG、TIFF、本地图片文件 URL (.fileURL)、NSImage 实例转换
    public static func readImageFromPasteboard() -> Data? {
        let pb = NSPasteboard.general

        // 1. 直接读取 PNG / JPEG / TIFF 原始图像字节流
        let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        for pasteType in [NSPasteboard.PasteboardType.png, jpegType, NSPasteboard.PasteboardType.tiff] {
            if let data = pb.data(forType: pasteType), !data.isEmpty {
                return data
            }
        }

        // 2. Finder 复制的图片文件 URL (.fileURL)
        if let urlData = pb.data(forType: .fileURL),
           let fileURL = URL(dataRepresentation: urlData, relativeTo: nil),
           let fileData = try? Data(contentsOf: fileURL),
           !fileData.isEmpty {
            return fileData
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls where url.isFileURL {
                if let fileData = try? Data(contentsOf: url), !fileData.isEmpty {
                    return fileData
                }
            }
        }

        // 3. 兜底通过 NSImage 读取并序列化为 PNG / TIFF
        if let image = NSImage(pasteboard: pb),
           let tiffData = image.tiffRepresentation,
           !tiffData.isEmpty {
            if let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]),
               !pngData.isEmpty {
                return pngData
            }
            return tiffData
        }

        return nil
    }

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

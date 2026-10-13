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

    /// 从单个 provider 提取图像二进制数据（剪贴板粘贴场景，按 PNG → TIFF → JPEG 依次尝试）
    static func loadImageData(from provider: NSItemProvider) async -> Data? {
        let candidates = [UTType.png.identifier, UTType.tiff.identifier, UTType.jpeg.identifier]
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

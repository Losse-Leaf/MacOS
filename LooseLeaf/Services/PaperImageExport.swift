// PaperImageExport.swift
// 相纸的「拷贝 / 预览 / 导出」统一出口
//
// 背景：这三件事此前在**两处**各写了一遍（灯箱 `EditorialLightboxView`
// 与相纸框 `FilmFrameView`），逻辑几乎逐字重复，而且：
//   - 网络失败时**零反馈** —— 按钮点了毫无反应，用户以为坏了
//   - 成功文案**永不重置** —— 一次成功就常驻在界面上
//   - 导出时直接下载**原图**（1.5MB），既慢又没必要
//
// 现在收敛到一处，失败一律回抛，让调用方能给出明确提示。

import AppKit
import Foundation

/// 相纸导出结果
public enum PaperImageExportResult: Equatable, Sendable {
    /// 成功（附一句给用户看的提示）
    case success(message: String)
    /// 失败（附一句给用户看的提示）
    case failure(message: String)
}

@MainActor
public enum PaperImageExport {

    /// 取回相纸的字节：先查缓存（内存 → 磁盘），再下载
    ///
    /// 关键：下载失败必须**抛出来**，不能静默返回 nil ——
    /// 否则调用方无从判断「没取到」是「失败」还是「本来就没有」。
    public static func data(for url: URL) async throws -> Data {
        // 先读磁盘原始字节：不做全尺寸解码、不占主线程，也不必重新编码。
        if let raw = await PaperImageCache.loadRawData(for: url) {
            return raw
        }
        do {
            // 与卡片共用同一套会话与在途合并：卡片正在下载同一张图时直接等结果。
            return try await ImageRequestCoalescer.shared.data(
                for: url,
                session: APIClient.mediaSession
            )
        } catch {
            throw NSError(
                domain: "PaperImageExport",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "相纸读取失败：\(error.localizedDescription)"]
            )
        }
    }

    /// 拷贝到剪贴板
    public static func copyToClipboard(url: URL) async -> PaperImageExportResult {
        do {
            let data = try await data(for: url)
            guard let image = NSImage(data: data) else {
                return .failure(message: "相纸格式无法识别")
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            return .success(message: "已拷贝相纸至剪贴板")
        } catch {
            return .failure(message: error.localizedDescription)
        }
    }

    /// 在系统「预览」中打开
    public static func openInSystemPreview(url: URL) async -> PaperImageExportResult {
        do {
            let data = try await data(for: url)
            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("looseleaf-preview-\(UUID().uuidString)-\(url.lastPathComponent)")
            try data.write(to: tempPath, options: .atomic)
            NSWorkspace.shared.open(tempPath)
            // 关键：**用完即删**。
            // 原先每次预览一张 1.5MB 原图就在临时目录留一份，**从不删除** ——
            // 只能靠系统临时目录的清理策略兜底。
            // macOS 打开的文件句柄在文件被 unlink 后仍可读，所以这里可以安全删除。
            scheduleCleanup(of: tempPath)
            return .success(message: "已在「预览」中打开相纸")
        } catch {
            return .failure(message: error.localizedDescription)
        }
    }

    /// 延迟删除临时文件（给「预览」app 一点时间打开它）
    private static func scheduleCleanup(of url: URL) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 导出到磁盘
    public static func exportToDisk(url: URL, to targetURL: URL) async -> PaperImageExportResult {
        do {
            let data = try await data(for: url)
            try data.write(to: targetURL, options: .atomic)
            return .success(message: "相纸已导出落盘")
        } catch {
            return .failure(message: error.localizedDescription)
        }
    }
}

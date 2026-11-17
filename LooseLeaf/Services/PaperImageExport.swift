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

/// 图像字节魔数嗅探器（供拖拽暂存与相纸导出共用）
public enum ImageFormatSniffer {
    /// 根据文件字节头魔数推断真实图片扩展名（解决缩略图接口 `/files/thumbnail` 无后缀与剪贴板/拖拽无扩展名问题）
    public static func fileExtension(for data: Data, fallbackURL: URL? = nil) -> String {
        if data.count >= 12 {
            let bytes = [UInt8](data.prefix(12))
            if bytes[0] == 0xFF, bytes[1] == 0xD8 { return "jpg" }
            if bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 { return "png" }
            if bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 { return "gif" }
            if bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
               bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 { return "webp" }
            if bytes[0] == 0x42, bytes[1] == 0x4D { return "tif" }
            if bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 { return "heic" }
        }
        if let ext = fallbackURL?.pathExtension, !ext.isEmpty {
            return ext.lowercased()
        }
        return "jpg"
    }
}

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

    /// 根据文件字节头魔数推断真实图片扩展名（委托至 `ImageFormatSniffer`）
    public nonisolated static func inferredExtension(for data: Data, fallbackURL: URL? = nil) -> String {
        ImageFormatSniffer.fileExtension(for: data, fallbackURL: fallbackURL)
    }

    /// 规范化导出默认文件名（确保携带有效图片扩展名）
    public nonisolated static func normalizedFilename(_ raw: String?, fallbackURL: URL, data: Data? = nil) -> String {
        let base = (raw?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? (fallbackURL.lastPathComponent.isEmpty || fallbackURL.lastPathComponent == "thumbnail"
                ? "looseleaf-photo"
                : fallbackURL.lastPathComponent)
        let existingExt = (base as NSString).pathExtension
        if !existingExt.isEmpty {
            return base
        }
        let ext = data.map { inferredExtension(for: $0, fallbackURL: fallbackURL) }
            ?? (fallbackURL.pathExtension.isEmpty ? "jpg" : fallbackURL.pathExtension.lowercased())
        return "\(base).\(ext)"
    }

    /// 拷贝到剪贴板（接入 SecureClipboard 60 秒延时清除）
    public static func copyToClipboard(url: URL) async -> PaperImageExportResult {
        do {
            let data = try await data(for: url)
            guard let image = NSImage(data: data) else {
                return .failure(message: "相纸格式无法识别")
            }
            SecureClipboard.copy(image: image)
            return .success(message: "已拷贝相纸至剪贴板")
        } catch {
            return .failure(message: error.localizedDescription)
        }
    }

    /// 在系统「预览」中打开（0600 权限隔离临时文件 + 自动补全图片后缀 + 延迟清理）
    public static func openInSystemPreview(url: URL, preferredFilename: String? = nil) async -> PaperImageExportResult {
        do {
            let data = try await data(for: url)
            let safeName = normalizedFilename(preferredFilename, fallbackURL: url, data: data)
                .replacingOccurrences(of: "/", with: "-")
            let previewDir = SyncManager.sharedStorageDirectory.appendingPathComponent("PreviewStaging", isDirectory: true)
            try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: previewDir.path)
            let tempPath = previewDir.appendingPathComponent("preview-\(UUID().uuidString.prefix(8))-\(safeName)")
            try data.write(to: tempPath, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempPath.path)
            NSWorkspace.shared.open(tempPath)
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

    /// 弹出系统保存面板并导出相纸（用户取消返回 `nil`）
    public static func presentSavePanel(url: URL, preferredFilename: String? = nil) async -> PaperImageExportResult? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = normalizedFilename(preferredFilename, fallbackURL: url)
        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = await panel.begin()
        }
        guard response == .OK, let targetURL = panel.url else { return nil }
        return await exportToDisk(url: url, to: targetURL)
    }
}

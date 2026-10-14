import Foundation
import AppKit
import Observation
import os

/// 桌面端原生 GitHub Releases 自动检测与一键热更引擎
/// 1. 启动时静默检查云端最新 Release
/// 2. 发现新版时呈现原生纸墨风升级卡片与更新日志
/// 3. 点击「立即更新」通过 URLSession 进程内下载（完全绕过浏览器，零 com.apple.quarantine 隔离标记）
/// 4. 解压替换 /Applications/LooseLeaf.app 并自动平滑重启接管
@Observable
@MainActor
public final class UpdateChecker {
    public static let shared = UpdateChecker()
    public static let repo = "Losse-Leaf/MacOS"

    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "updater")

    public var isChecking: Bool = false
    public var isUpdating: Bool = false
    public var updateProgress: Double = 0.0
    public var availableUpdate: ReleaseInfo?
    public var updateError: String?

    public struct ReleaseInfo: Equatable, Sendable {
        public let tagName: String
        public let versionName: String
        public let body: String
        public let downloadURL: URL
        public let publishedAt: String
    }

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    public func checkForUpdates(isUserInitiated: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        updateError = nil
        defer { isChecking = false }

        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                if isUserInitiated {
                    updateError = "无法连接至 GitHub Releases 服务"
                }
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]] else {
                return
            }

            let cleanRemoteTag = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let cleanLocalTag = currentVersion.hasPrefix("v") ? String(currentVersion.dropFirst()) : currentVersion

            if Self.isVersion(cleanRemoteTag, greaterThan: cleanLocalTag) {
                // 查找 arm64.zip
                if let asset = assets.first(where: {
                    let name = ($0["name"] as? String)?.lowercased() ?? ""
                    return name.hasSuffix(".zip") && (name.contains("arm64") || name.contains("looseleaf"))
                }), let downloadURLStr = asset["browser_download_url"] as? String,
                   let downloadURL = URL(string: downloadURLStr) {
                    self.availableUpdate = ReleaseInfo(
                        tagName: tagName,
                        versionName: cleanRemoteTag,
                        body: (json["body"] as? String) ?? "",
                        downloadURL: downloadURL,
                        publishedAt: (json["published_at"] as? String) ?? ""
                    )
                    Self.logger.info("Found newer version: \(cleanRemoteTag, privacy: .public)")
                }
            } else if isUserInitiated {
                AppState.shared.showTemporaryBanner("当前已是最新版本 (v\(currentVersion))")
            }
        } catch {
            if isUserInitiated {
                updateError = "检查更新失败: \(error.localizedDescription)"
            }
        }
    }

    /// 执行一键无感下载、替换并重启
    public func performInAppUpdate() async {
        guard let update = availableUpdate, !isUpdating else { return }
        isUpdating = true
        updateProgress = 0.05
        updateError = nil

        do {
            // 1. 通过 URLSession 下载（不经过浏览器，系统不会打上 quarantine 属性）
            let (tempZipURL, _) = try await URLSession.shared.download(from: update.downloadURL)
            updateProgress = 0.55

            // 2. 解压到沙箱临时目录
            let tempExtractDir = FileManager.default.temporaryDirectory.appendingPathComponent("LooseLeafExtract-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)

            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-q", "-o", tempZipURL.path, "-d", tempExtractDir.path]
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            updateProgress = 0.85

            // 查找解压出的 LooseLeaf.app
            let items = (try? FileManager.default.contentsOfDirectory(atPath: tempExtractDir.path)) ?? []
            guard let appBundleName = items.first(where: { $0.hasSuffix(".app") }) else {
                throw NSError(domain: "UpdateError", code: 1, userInfo: [NSLocalizedDescriptionKey: "解压包中未包含 LooseLeaf.app"])
            }
            let extractedApp = tempExtractDir.appendingPathComponent(appBundleName)

            // 3. 剥离可能存在的扩展隔离属性
            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-cr", extractedApp.path]
            try? xattrProcess.run()
            xattrProcess.waitUntilExit()

            // 4. 定位目标应用安装路径（优先 Bundle 本身所在路径，若在只读区则回退到 /Applications）
            var targetAppURL = Bundle.main.bundleURL
            if !targetAppURL.path.hasSuffix(".app") {
                targetAppURL = URL(fileURLWithPath: "/Applications/LooseLeaf.app")
            }

            // 5. 调用外部 shell 进行平滑交换并重新拉起
            let swapScript = """
            sleep 0.8
            rm -rf "\(targetAppURL.path)"
            cp -R "\(extractedApp.path)" "\(targetAppURL.path)"
            xattr -cr "\(targetAppURL.path)" 2>/dev/null || true
            open "\(targetAppURL.path)"
            """

            let swapProcess = Process()
            swapProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            swapProcess.arguments = ["-c", swapScript]
            try swapProcess.run()

            updateProgress = 1.0

            // 退出当前旧进程，让新版本无缝接管
            NSApp.terminate(nil)
        } catch {
            updateError = "自动更新失败：\(error.localizedDescription)"
            isUpdating = false
        }
    }

    /// 语义化版本号比较器（v1.2.1 > v1.2.0）
    public nonisolated static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let p1 = v1.split(separator: ".").compactMap { Int($0) }
        let p2 = v2.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(p1.count, p2.count)
        for i in 0..<maxCount {
            let n1 = i < p1.count ? p1[i] : 0
            let n2 = i < p2.count ? p2[i] : 0
            if n1 > n2 { return true }
            if n1 < n2 { return false }
        }
        return false
    }
}

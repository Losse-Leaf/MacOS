import Foundation
import AppKit
import Observation
import CryptoKit
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

    nonisolated private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "updater")

    public var isChecking: Bool = false
    public var hasChecked: Bool = false
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
        /// GitHub Release 提供的 "sha256:..." 资产摘要；缺失时为 nil
        public let expectedDigest: String?
    }

    nonisolated private static let ignoredVersionKey = "ignoredUpdateVersion"
    /// 上次检查时间：GitHub 未认证 API 限额 60 次/小时/IP，24 小时内不重复检查
    nonisolated private static let lastCheckAtKey = "looseleaf_update_last_check_at"
    nonisolated private static let checkInterval: TimeInterval = 24 * 60 * 60

    /// 当前版本号（一次性读取，避免每次 body 求值都拷贝 Bundle 字典）
    public let currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    /// 用户选择忽略当前检测到的新版本（避免反复弹窗干扰）
    public func ignoreCurrentUpdate() {
        if let update = availableUpdate {
            UserDefaults.standard.set(update.tagName, forKey: Self.ignoredVersionKey)
        }
        availableUpdate = nil
    }

    public func checkForUpdates(isUserInitiated: Bool = false) async {
        // 后台检查进行中时，用户手动点击「检查新版本…」不能静默无响应：
        // 直接提示正在检查中即可（不排队，避免并发请求）。
        guard !isChecking else {
            if isUserInitiated {
                updateError = "正在检查新版本，请稍候…"
            }
            return
        }

        // 非用户主动触发时，24 小时内最多检查一次，避免撞上 GitHub 匿名 API 限额
        if !isUserInitiated, !Self.shouldCheckNow() {
            hasChecked = true
            return
        }

        isChecking = true
        updateError = nil
        defer {
            isChecking = false
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckAtKey)
        }

        if isUserInitiated {
            UserDefaults.standard.removeObject(forKey: Self.ignoredVersionKey)
        }

        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                if isUserInitiated { updateError = "无法连接至 GitHub Releases 服务" }
                return
            }

            // GitHub 匿名 API 限流（403 + X-RateLimit-Remaining = 0）需要明确提示，
            // 否则用户只会看到「无法连接」，无从判断真实原因。
            if http.statusCode == 403,
               http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init)
                let resetHint = reset.map { Date(timeIntervalSince1970: $0).formatted(date: .omitted, time: .shortened) } ?? "稍后"
                if isUserInitiated {
                    updateError = "GitHub 版本查询频率受限，请于 \(resetHint) 后重试"
                }
                return
            }

            guard http.statusCode == 200 else {
                if isUserInitiated {
                    updateError = "无法连接至 GitHub Releases 服务 (HTTP \(http.statusCode))"
                }
                return
            }

            // 解析放后台线程（JSONSerialization → [String: Any] 是最慢的解析方式）
            let release: GitHubRelease
            do {
                release = try await Task.detached(priority: .userInitiated) {
                    try JSONDecoder().decode(GitHubRelease.self, from: data)
                }.value
            } catch {
                if isUserInitiated {
                    updateError = "更新信息解析失败（GitHub 返回格式异常），请稍后重试或直接访问发布页"
                }
                return
            }

            let cleanRemoteTag = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            let cleanLocalTag = currentVersion.hasPrefix("v") ? String(currentVersion.dropFirst()) : currentVersion

            if Self.isVersion(cleanRemoteTag, greaterThan: cleanLocalTag) {
                let ignored = UserDefaults.standard.string(forKey: Self.ignoredVersionKey)
                if !isUserInitiated && ignored == release.tagName {
                    // 该版本已被用户手动忽略，且非用户手动点击检测，静默跳过横幅提示
                    self.hasChecked = true
                    return
                }

                // 查找 arm64.zip
                if let asset = release.assets.first(where: {
                    let name = $0.name.lowercased()
                    return name.hasSuffix(".zip") && (name.contains("arm64") || name.contains("looseleaf"))
                }), let downloadURL = URL(string: asset.browserDownloadURL) {
                    self.availableUpdate = ReleaseInfo(
                        tagName: release.tagName,
                        versionName: cleanRemoteTag,
                        body: release.body ?? "",
                        downloadURL: downloadURL,
                        publishedAt: release.publishedAt ?? "",
                        expectedDigest: asset.digest
                    )
                } else if isUserInitiated {
                    updateError = "已发现新版本 v\(cleanRemoteTag)，但未找到可下载的 macOS 安装包"
                }
                self.hasChecked = true
            } else {
                self.availableUpdate = nil
                self.hasChecked = true
                if isUserInitiated {
                    AppState.shared.showTemporaryBanner("当前已是最新版本 (v\(currentVersion))")
                }
            }
        } catch {
            if isUserInitiated {
                updateError = "检查更新失败: \(error.localizedDescription)"
            }
        }
    }

    /// GitHub Release 响应模型（Codable 解析比 JSONSerialization 快且无类型擦除）
    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String
            let digest: String?

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case digest
            }
        }
        let tagName: String
        let body: String?
        let publishedAt: String?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case publishedAt = "published_at"
            case assets
        }
    }

    /// 24 小时节流判定
    private nonisolated static func shouldCheckNow() -> Bool {
        let last = UserDefaults.standard.double(forKey: lastCheckAtKey)
        guard last > 0 else { return true }
        return Date().timeIntervalSince1970 - last >= checkInterval
    }

    /// 在默认浏览器中打开对应版本的 GitHub Release 下载页面
    public func openDownloadInBrowser() {
        if let url = availableUpdate?.downloadURL {
            NSWorkspace.shared.open(url)
        } else {
            guard let releaseURL = URL(string: "https://github.com/\(Self.repo)/releases/latest") else { return }
            NSWorkspace.shared.open(releaseURL)
        }
    }

    /// 终端一键安装/更新命令（唯一事实源，同时供按钮复制与测试断言使用）
    public static let installCommand = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Losse-Leaf/MacOS/main/install.sh)""#

    /// 复制终端全自动一键安装更新命令至剪贴板（全自动安装并放行 Gatekeeper，免终端输入配置）
    public func copyInstallCommandToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.installCommand, forType: .string)
        AppState.shared.showTemporaryBanner("已复制终端安装命令，打开 Mac「终端」粘贴回车即可一键全自动升级")
    }

    /// 执行一键无感下载、脱离主进程守护替换并重启
    public func performInAppUpdate() async {
        guard let update = availableUpdate, !isUpdating else { return }
        isUpdating = true
        updateProgress = 0.05
        updateError = nil

        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        if isSandboxed {
            updateError = "系统沙箱 (App Sandbox) 安全机制拦截了应用内直接覆盖写入。推荐使用下方「浏览器下载安装」或「复制终端一键更新」完成升级。"
            isUpdating = false
            return
        }

        do {
            // 1. 通过 URLSession 下载（带真实进度回调）
            updateProgress = 0.15
            let progressDelegate = DownloadProgressDelegate { [weak self] fraction in
                Task { @MainActor in
                    // 下载阶段占据 0.15 ~ 0.50
                    self?.updateProgress = 0.15 + fraction * 0.35
                }
            }
            let session = URLSession(configuration: .default, delegate: progressDelegate, delegateQueue: nil)
            let (tempDownloadedURL, _) = try await session.download(from: update.downloadURL)
            progressDelegate.invalidate()
            updateProgress = 0.50

            // 2. 立即将下载的产物转移至独立临时目录，防止被系统或 URLSession 句柄早退清理
            let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("LooseLeafUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            let zipPath = workDir.appendingPathComponent("update.zip")
            // 跨卷时 moveItem 会退化为拷贝（100MB+），必须放在后台线程
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.moveItem(at: tempDownloadedURL, to: zipPath)
            }.value

            // 2.1 校验下载包完整性（GitHub Release 资产自带 sha256 digest）
            // 关键：SHA256 对 100MB 包需 0.3~1 秒，必须离开主线程，否则窗口全程无响应
            try await Task.detached(priority: .userInitiated) {
                try Self.verifyDigest(of: zipPath, expected: update.expectedDigest)
            }.value

            // 3. 解压产物（unzip 需数秒，同样不能在主线程 waitUntilExit）
            updateProgress = 0.70
            let extractDir = workDir.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let unzipStatus = try await Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-q", "-o", zipPath.path, "-d", extractDir.path]
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            }.value

            guard unzipStatus == 0 else {
                throw NSError(domain: "UpdateError", code: 2, userInfo: [NSLocalizedDescriptionKey: "更新包解压失败"])
            }

            updateProgress = 0.85

            // 4. 定位解压出的 LooseLeaf.app
            let items = (try? FileManager.default.contentsOfDirectory(atPath: extractDir.path)) ?? []
            guard let appBundleName = items.first(where: { $0.hasSuffix(".app") }) else {
                throw NSError(domain: "UpdateError", code: 3, userInfo: [NSLocalizedDescriptionKey: "解压包中未包含 LooseLeaf.app"])
            }
            let extractedApp = extractDir.appendingPathComponent(appBundleName)

            // 5. 预先剥离解压产物的隔离属性（后台线程执行，递归遍历可能耗时数秒）
            await Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                process.arguments = ["-cr", extractedApp.path]
                try? process.run()
                process.waitUntilExit()
            }.value

            // 6. 确定目标应用安装路径（若当前运行于开发/DerivedData 目录，自动定位至 /Applications/LooseLeaf.app）
            var targetAppURL = Bundle.main.bundleURL
            if !targetAppURL.path.hasSuffix(".app") || targetAppURL.path.contains("/build/") || targetAppURL.path.contains("/DerivedData/") {
                targetAppURL = URL(fileURLWithPath: "/Applications/LooseLeaf.app")
            }
            let installDirectory = targetAppURL.deletingLastPathComponent()
            guard FileManager.default.isWritableFile(atPath: installDirectory.path) else {
                throw NSError(
                    domain: "UpdateError",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "对 \(installDirectory.path) 没有写入权限，请使用「复制终端一键更新」完成升级"]
                )
            }

            // 7. 生成独立于当前主进程生命周期的守护替换脚本 (脱离会话组，安全等待主进程 PID 退出)
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let scriptURL = workDir.appendingPathComponent("swap_updater.sh")
            let scriptContent = """
            #!/bin/bash
            TARGET="\(targetAppURL.path)"
            SOURCE="\(extractedApp.path)"
            OLD_PID="\(currentPID)"
            WORK_DIR="\(workDir.path)"

            # 1. 严格轮询等待旧进程彻底安全退出（至多轮询 15 秒）
            COUNT=0
            while kill -0 "$OLD_PID" 2>/dev/null; do
                sleep 0.2
                COUNT=$((COUNT + 1))
                if [ $COUNT -ge 75 ]; then
                    kill -9 "$OLD_PID" 2>/dev/null || true
                    break
                fi
            done

            # 稍等 0.3 秒确保系统文件句柄释放
            sleep 0.3

            # 2. 覆盖替换安装
            rm -rf "$TARGET"
            cp -R "$SOURCE" "$TARGET"

            # 3. 再次确保隔离属性清除
            xattr -cr "$TARGET" 2>/dev/null || true

            # 4. 重新拉起应用
            open "$TARGET"

            # 5. 清理临时解压工作目录
            rm -rf "$WORK_DIR"
            """

            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            updateProgress = 1.0

            // 8. 使用 nohup 启动独立替换脚本，彻底脱离父进程会话组，重定向 stdio 确保父进程退出不会阻断
            let detachProcess = Process()
            detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            detachProcess.arguments = ["/bin/bash", scriptURL.path]
            detachProcess.standardInput = FileHandle.nullDevice
            detachProcess.standardOutput = FileHandle.nullDevice
            detachProcess.standardError = FileHandle.nullDevice
            try detachProcess.run()

            // 给操作系统调度 150 毫秒确保子进程已独立驻留运行
            try? await Task.sleep(nanoseconds: 150_000_000)

            // 退出当前旧应用进程，由后台 swap_updater.sh 完成交接与唤起
            NSApp.terminate(nil)
        } catch {
            updateError = "自动更新失败：\(error.localizedDescription)"
            isUpdating = false
        }
    }

    /// 语义化版本号比较器（v1.2.1 > v1.2.0；预发布版本优先级低于同核心版本号）
    public nonisolated static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let parsed1 = parseSemVer(v1)
        let parsed2 = parseSemVer(v2)
        let maxCount = max(parsed1.core.count, parsed2.core.count)
        for i in 0..<maxCount {
            let n1 = i < parsed1.core.count ? parsed1.core[i] : 0
            let n2 = i < parsed2.core.count ? parsed2.core[i] : 0
            if n1 > n2 { return true }
            if n1 < n2 { return false }
        }
        // 核心版本号相同时：带预发布标记的版本优先级更低（1.5.7-beta.1 < 1.5.7）
        if parsed1.isPrerelease != parsed2.isPrerelease {
            return parsed2.isPrerelease
        }
        return false
    }

    private struct SemVer {
        let core: [Int]
        let isPrerelease: Bool
    }

    /// "v1.5.7-beta.1" → core [1,5,7] + isPrerelease = true
    private nonisolated static func parseSemVer(_ raw: String) -> SemVer {
        var core = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if core.hasPrefix("v") || core.hasPrefix("V") {
            core.removeFirst()
        }
        var isPrerelease = false
        if let dash = core.firstIndex(of: "-") {
            isPrerelease = true
            core = String(core[..<dash])
        }
        if let plus = core.firstIndex(of: "+") {
            core = String(core[..<plus])
        }
        let parts = core.split(separator: ".").map { component -> Int in
            let digits = component.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
        return SemVer(core: parts, isPrerelease: isPrerelease)
    }

    /// 用 GitHub Release 提供的 sha256 摘要校验下载包；未提供摘要时只记录日志（兼容旧发布）。
    nonisolated static func verifyDigest(of fileURL: URL, expected: String?) throws {
        guard let expected, expected.lowercased().hasPrefix("sha256:") else {
            logger.notice("Release asset has no sha256 digest; skipping integrity check")
            return
        }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let wanted = String(expected.dropFirst("sha256:".count)).lowercased()
        guard actual == wanted else {
            throw NSError(
                domain: "UpdateError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "更新包校验失败（SHA256 不匹配），已中止安装"]
            )
        }
    }
}

/// 下载进度代理：把 URLSession 的字节进度转换为 0~1 比例（节流后回调，避免刷屏）
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Double) -> Void
    private var lastReportedFraction: Double = 0
    private var lastReportTime: Date = .distantPast
    private let lock = NSLock()

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        lock.lock()
        let now = Date()
        // 节流：进度变化 < 1% 或间隔 < 100ms 则不回调
        guard fraction - lastReportedFraction > 0.01, now.timeIntervalSince(lastReportTime) > 0.1 else {
            lock.unlock()
            return
        }
        lastReportedFraction = fraction
        lastReportTime = now
        lock.unlock()
        onProgress(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // 下载完成；由 URLSession.download(for:) 返回临时文件路径，无需在此搬运
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let fraction = lastReportedFraction
        lock.unlock()
        if fraction < 1.0 { onProgress(1.0) }
    }

    func invalidate() {
        // 让 session 释放 delegate 引用
    }
}

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

    private static let ignoredVersionKey = "ignoredUpdateVersion"

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// 用户选择忽略当前检测到的新版本（避免反复弹窗干扰）
    public func ignoreCurrentUpdate() {
        if let update = availableUpdate {
            UserDefaults.standard.set(update.tagName, forKey: Self.ignoredVersionKey)
        }
        availableUpdate = nil
    }

    public func checkForUpdates(isUserInitiated: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        updateError = nil
        defer { isChecking = false }

        if isUserInitiated {
            UserDefaults.standard.removeObject(forKey: Self.ignoredVersionKey)
        }

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
                let ignored = UserDefaults.standard.string(forKey: Self.ignoredVersionKey)
                if !isUserInitiated && ignored == tagName {
                    // 该版本已被用户手动忽略，且非用户手动点击检测，静默跳过横幅提示
                    self.hasChecked = true
                    return
                }

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
                        publishedAt: (json["published_at"] as? String) ?? "",
                        expectedDigest: asset["digest"] as? String
                    )
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
        AudioFeedback.shared.playTink()
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
            // 1. 通过 URLSession 下载
            updateProgress = 0.15
            let (tempDownloadedURL, _) = try await URLSession.shared.download(from: update.downloadURL)
            updateProgress = 0.50

            // 2. 立即将下载的产物转移至独立临时目录，防止被系统或 URLSession 句柄早退清理
            let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("LooseLeafUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            let zipPath = workDir.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: tempDownloadedURL, to: zipPath)

            // 2.1 校验下载包完整性（GitHub Release 资产自带 sha256 digest）
            try Self.verifyDigest(of: zipPath, expected: update.expectedDigest)

            // 3. 解压产物
            updateProgress = 0.70
            let extractDir = workDir.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-q", "-o", zipPath.path, "-d", extractDir.path]
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            guard unzipProcess.terminationStatus == 0 else {
                throw NSError(domain: "UpdateError", code: 2, userInfo: [NSLocalizedDescriptionKey: "更新包解压失败"])
            }

            updateProgress = 0.85

            // 4. 定位解压出的 LooseLeaf.app
            let items = (try? FileManager.default.contentsOfDirectory(atPath: extractDir.path)) ?? []
            guard let appBundleName = items.first(where: { $0.hasSuffix(".app") }) else {
                throw NSError(domain: "UpdateError", code: 3, userInfo: [NSLocalizedDescriptionKey: "解压包中未包含 LooseLeaf.app"])
            }
            let extractedApp = extractDir.appendingPathComponent(appBundleName)

            // 5. 预先剥离解压产物的隔离属性
            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-cr", extractedApp.path]
            try? xattrProcess.run()
            xattrProcess.waitUntilExit()

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

    /// 语义化版本号比较器（v1.2.1 > v1.2.0，容忍 1.5.7-beta.1 这类预发布标签）
    public nonisolated static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let p1 = numericParts(v1)
        let p2 = numericParts(v2)
        let maxCount = max(p1.count, p2.count)
        for i in 0..<maxCount {
            let n1 = i < p1.count ? p1[i] : 0
            let n2 = i < p2.count ? p2[i] : 0
            if n1 > n2 { return true }
            if n1 < n2 { return false }
        }
        return false
    }

    /// "v1.5.7-beta.1" -> [1, 5, 7]；先剥离 v 前缀与预发布/构建元数据，再逐段取数字。
    private nonisolated static func numericParts(_ raw: String) -> [Int] {
        var core = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if core.hasPrefix("v") || core.hasPrefix("V") {
            core.removeFirst()
        }
        // SemVer：1.5.7-beta.1 的优先级低于 1.5.7，比较时只取核心版本号
        if let dash = core.firstIndex(of: "-") {
            core = String(core[..<dash])
        }
        if let plus = core.firstIndex(of: "+") {
            core = String(core[..<plus])
        }
        return core.split(separator: ".").map { component in
            let digits = component.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }

    /// 用 GitHub Release 提供的 sha256 摘要校验下载包；未提供摘要时只记录日志（兼容旧发布）。
    private nonisolated static func verifyDigest(of fileURL: URL, expected: String?) throws {
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

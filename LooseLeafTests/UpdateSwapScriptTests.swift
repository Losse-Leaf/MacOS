import XCTest
import Foundation
@testable import LooseLeaf

/// 应用内更新的「守护替换脚本」回归测试
///
/// 背景：旧版脚本是 `rm -rf "$TARGET"` → `cp -R "$SOURCE" "$TARGET"`。
/// 一旦 `cp` 中途失败（磁盘满 / 权限变动 / 目标被占用），
/// **用户的 App 就此消失**，而且没有任何东西可以回滚 —— 只能重新下载安装。
///
/// 现在脚本改为「拷到同卷暂存 → 旧版移作备份 → 原子 rename → 失败回滚」。
/// 本测试**真的把脚本跑起来**，在临时目录里搭出「旧 App」与「新 App」，
/// 分别验证成功路径与失败路径的磁盘最终状态。
@MainActor
final class UpdateSwapScriptTests: XCTestCase {

    private var workRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        workRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("looseleaf-swap-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workRoot)
        try await super.tearDown()
    }

    /// 造一个假的 .app 包
    private func makeFakeApp(at url: URL, marker: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try marker.write(to: contents.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
    }

    private func marker(at url: URL) -> String? {
        try? String(contentsOf: url.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
    }

    /// 把脚本写到磁盘并执行，返回退出码
    @discardableResult
    private func runScript(target: URL, source: URL, workDir: URL) throws -> Int32 {
        let script = UpdateChecker.swapScript(
            target: target.path,
            source: source.path,
            oldPID: 999_999,            // 必然不存在的正数 PID → kill -0 立即失败 → 跳过等待
            workDir: workDir.path
        )
        let scriptURL = workRoot.appendingPathComponent("swap.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        // 脚本末尾会 `open "$TARGET"` 重新拉起应用。测试里绝不能真的启动它，
        // 于是在 PATH 前置一个假的 `open`（脚本按名字调用，可被 PATH 劫持）。
        let fakeBin = workRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        let fakeOpen = fakeBin.appendingPathComponent("open")
        try "#!/bin/bash\nexit 0\n".write(to: fakeOpen, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeOpen.path)

        process.environment = [
            "PATH": "\(fakeBin.path):/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": workRoot.path
        ]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    // MARK: - 1. 成功路径：新版本就位，旧版本与备份都清干净

    func test01_SwapReplacesAppAndLeavesNoResidue() throws {
        let installDir = workRoot.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let target = installDir.appendingPathComponent("LooseLeaf.app")
        let source = workRoot.appendingPathComponent("extracted/LooseLeaf.app", isDirectory: true)
        let workDir = workRoot.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        try makeFakeApp(at: target, marker: "OLD")
        try makeFakeApp(at: source, marker: "NEW")

        let code = try runScript(target: target, source: source, workDir: workDir)
        XCTAssertEqual(code, 0, "替换脚本应成功退出")

        XCTAssertEqual(marker(at: target), "NEW", "目标位置应是新版本")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: installDir.appendingPathComponent(".LooseLeaf.backup.\(ProcessInfo.processInfo.processIdentifier).x").path),
            "不应残留任何备份目录"
        )

        // 目录里不应留下 .installing / .backup 之类的临时项
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: installDir.path)
            .filter { $0.hasPrefix(".LooseLeaf.") }
        XCTAssertTrue(leftovers.isEmpty, "安装目录残留了临时项: \(leftovers)")

        // workDir 脚本自己会清
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: workDir.path),
            "临时工作目录应被脚本清理"
        )
    }

    // MARK: - 2. 失败路径：新版本不可用时，旧版本必须原封不动

    func test02_SwapFailureKeepsOldAppIntact() throws {
        let installDir = workRoot.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let target = installDir.appendingPathComponent("LooseLeaf.app")
        // 故意让 source 不存在 → cp 必然失败
        let source = workRoot.appendingPathComponent("extracted/Missing.app", isDirectory: true)
        let workDir = workRoot.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        try makeFakeApp(at: target, marker: "OLD")

        let code = try runScript(target: target, source: source, workDir: workDir)
        XCTAssertNotEqual(code, 0, "拷贝失败时脚本应返回非零")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: target.path),
            "替换失败后旧 App 绝不能消失"
        )
        XCTAssertEqual(marker(at: target), "OLD", "替换失败后旧 App 内容必须原封不动")

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: installDir.path)
            .filter { $0.hasPrefix(".LooseLeaf.") }
        XCTAssertTrue(leftovers.isEmpty, "失败路径也不应残留临时项: \(leftovers)")
    }

    // MARK: - 3. 脚本本身必须是合法 shell

    func test03_SwapScriptIsValidShell() throws {
        let script = UpdateChecker.swapScript(
            target: "/Applications/LooseLeaf.app",
            source: "/tmp/src/LooseLeaf.app",
            oldPID: 12345,
            workDir: "/tmp/work"
        )
        let scriptURL = workRoot.appendingPathComponent("syntax_check.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-n", scriptURL.path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        XCTAssertEqual(
            process.terminationStatus, 0,
            "脚本存在 shell 语法错误: \(String(data: data, encoding: .utf8) ?? "")"
        )
    }

    // MARK: - 4. 关键：脚本里不允许出现「先删目标再拷贝」

    func test04_SwapScriptNeverDeletesTargetBeforeCopying() throws {
        let script = UpdateChecker.swapScript(
            target: "/Applications/LooseLeaf.app",
            source: "/tmp/src/LooseLeaf.app",
            oldPID: 1,
            workDir: "/tmp/work"
        )

        // 目标只允许被 `mv` 走（移作备份），不允许被 `rm -rf` 直接删除。
        // 跳过注释行：脚本注释里本来就会引用被禁止的写法作为反例。
        let destructiveLines = script
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.hasPrefix("#") && line.contains("rm -rf") && line.contains("\"$TARGET\"")
            }
        XCTAssertTrue(
            destructiveLines.isEmpty,
            "脚本不得直接 rm -rf 目标（会丢失回滚能力）: \(destructiveLines)"
        )

        // 必须存在备份与回滚路径
        XCTAssertTrue(script.contains("BACKUP_PATH"), "脚本缺少备份路径")
        XCTAssertTrue(script.contains("STAGING_PATH"), "脚本缺少暂存路径")
        XCTAssertTrue(script.contains("mv \"$BACKUP_PATH\" \"$TARGET\""), "脚本缺少回滚语句")
    }
}

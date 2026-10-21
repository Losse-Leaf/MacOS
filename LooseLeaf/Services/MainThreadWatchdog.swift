// MainThreadWatchdog.swift
// 主线程卡顿看门狗 (Main-thread Stall Watchdog)
//
// 目的：把「点一下卡十几秒」这种**偶发、难以复现**的主线程阻塞，
// 变成一份可事后分析的确凿证据。
//
// 原理：
//   1. 后台线程每 200ms 给主队列发一个「心跳」任务
//   2. 心跳任务在主线程真正执行时，记录实际延迟
//   3. 延迟超过阈值即判定为**主线程阻塞**，记录持续时长
//   4. 阻塞期间如果开启了取证模式，自动调用 `/usr/bin/sample` 抓自己，
//      把主线程调用栈写到日志目录 —— 这份栈能直接指出卡在哪个函数
//
// 关键：不依赖任何 UI 事件，也不会影响正常性能（后台线程只发心跳）。

import Foundation
import os

/// `@unchecked Sendable`：本类的可变状态只有 `_lastUserAction` 与 `expectedAt`，
/// 两者都由 `stateLock` / `expectedLock` 保护；心跳定时器与主线程之间只通过
/// 值传递（时间戳、字符串），不共享引用。
final class MainThreadWatchdog: @unchecked Sendable {

    static let shared = MainThreadWatchdog()

    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "watchdog")

    /// 心跳间隔
    private let heartbeatInterval: TimeInterval = 0.2
    /// 判定为阻塞的阈值
    private let stallThreshold: TimeInterval = 0.6

    private var timer: DispatchSourceTimer?
    /// 下一次心跳的**预期**执行时刻（由锁保护）
    private var expectedAt: Date = Date()
    private let expectedLock = NSLock()
    private var running = false

    /// 最近一次用户动作（用于给卡顿归因）
    ///
    /// 关键：这个类**不是** `@MainActor`。
    /// 它的心跳定时器挂在后台队列上，若类标了 `@MainActor`，
    /// 隔离承诺就是假的（Swift 5 语言模式下不报错，Swift 6 下直接编译失败），
    /// 而且 `MainActor.assumeIsolated` 在非主线程调用会 trap。
    /// 这里改用一把锁保护共享状态，心跳结果一律回主线程处理。
    private let stateLock = NSLock()
    private var _lastUserAction: String = "（尚无）"

    var lastUserAction: String {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastUserAction
    }

    /// 记录一条用户动作，卡顿发生时就能知道当时用户在干什么
    func noteAction(_ action: String) {
        stateLock.lock()
        _lastUserAction = action
        stateLock.unlock()
    }

    /// 日志目录（放在应用存储目录下，用户可自行取走）
    private var logDirectory: URL {
        let base = SyncManager.sharedStorageDirectory.appendingPathComponent("PerfLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// 是否开启取证（抓 sample 栈）
    ///
    /// 默认开启：一次卡顿的证据比几 MB 日志值钱得多。
    /// 只在检测到阻塞时才调用 sample，平时零开销。
    private let captureStacks: Bool

    private init(captureStacks: Bool = ProcessInfo.processInfo.environment["LOOSELEAF_NO_STACK_CAPTURE"] == nil) {
        self.captureStacks = captureStacks
    }

    /// 启动看门狗
    func start() {
        guard !running else { return }
        running = true

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: heartbeatInterval)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        running = false
    }

    /// 一次心跳（运行在后台队列）
    private func tick() {
        expectedLock.lock()
        let scheduled = expectedAt
        expectedAt = scheduled.addingTimeInterval(heartbeatInterval)
        expectedLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let delay = Date().timeIntervalSince(scheduled)
            if delay >= self.stallThreshold {
                self.reportStall(delay: delay)
            }
        }
    }

    /// 报告一次阻塞
    private func reportStall(delay: TimeInterval) {
        let action = self.lastUserAction
        let stamp = Date().timeIntervalSince1970
        let message = String(format: "主线程阻塞 %.2fs（最近动作：%@）", delay, action)
        Self.logger.error("\(message, privacy: .public)")
        print("⟦WATCHDOG⟧ \(message)")

        // 落一份文本日志
        let logURL = logDirectory.appendingPathComponent("stalls.log")
        let line = String(format: "%.3f  delay=%.3fs  action=%@\n", stamp, delay, action)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: logURL)
        }

        guard captureStacks else { return }
        captureStack(delay: delay, action: action, stamp: stamp)
    }

    /// 只保留最近 N 份栈快照
    private static func pruneStacks(in directory: URL, keeping maxCount: Int) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let stacks = files
            .filter { $0.lastPathComponent.hasPrefix("stall-") && $0.pathExtension == "txt" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l > r
            }
        for stale in stacks.dropFirst(maxCount) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    /// 抓一份主线程调用栈
    private func captureStack(delay: TimeInterval, action: String, stamp: TimeInterval) {
        let outURL = logDirectory.appendingPathComponent(String(format: "stall-%.3f.txt", stamp))
        let pid = ProcessInfo.processInfo.processIdentifier
        DispatchQueue.global(qos: .background).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            process.arguments = [String(pid), "2", "-file", outURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            // 关键：**限制份数**。每次卡顿都会落一份数 MB 的栈快照，
            // 而 PerfLogs 目录只增不减 —— 一次卡顿风暴就能堆出几百 MB。
            Self.pruneStacks(in: self.logDirectory, keeping: 8)
            // 补一行说明，方便对照
            if let handle = try? FileHandle(forWritingTo: outURL) {
                handle.seekToEndOfFile()
                handle.write(Data(String(format: "\\n// delay=%.3fs action=%@\\n", delay, action).utf8))
                try? handle.close()
            }
            print("⟦WATCHDOG⟧ 已抓取主线程栈: \(outURL.path)")
        }
    }
}

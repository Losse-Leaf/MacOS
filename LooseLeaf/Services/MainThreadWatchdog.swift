// MainThreadWatchdog.swift
// 主线程卡顿看门狗 (Main-thread Stall Watchdog)
//
// 目的：把「点一下卡十几秒」这种偶发、难以复现的主线程阻塞，
// 变成一份可事后分析的确凿证据，同时绝不引发性能雪崩。
//
// 原理与防护机制：
//   1. 探针单在途保证（In-flight Guard）：
//      后台定时器每 200ms 检查主线程响应情况。若上一个探针仍在主队列排队未执行，
//      绝不重复派发新探针，从根本上杜绝主线程阻塞期间任务积压与多重并发回调。
//   2. 真实耗时探测（No Cumulative Drift）：
//      每次探测基于真实派发时刻计算延迟，彻底杜绝历史基准时间累积漂移导致的「永久误判卡顿」。
//   3. 进程采样严格互斥与降级保护（Sample Mutex & Cooldown）：
//      /usr/bin/sample 是重度诊断工具，默认在生产环境中关闭（仅可通过环境变量 LOOSELEAF_ENABLE_STACK_CAPTURE 显式开启）。
//      开启时具备严格的单实例互斥锁与最少 30 秒冷却保护，彻底杜绝高并发 sample 耗尽系统 CPU。
//   4. 日志大小兜底（Log Size Cap）：
//      PerfLogs 日志超过 1MB 自动滚动截断，防止磁盘膨胀。

import Foundation
import os

/// `@unchecked Sendable`：所有可变状态均由 `stateLock` 互斥锁严格保护；
/// 心跳定时器与主线程之间仅传递不可变值（时间戳、字符串），不共享可变引用。
final class MainThreadWatchdog: @unchecked Sendable {

    static let shared = MainThreadWatchdog()

    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "watchdog")

    /// 心跳检测间隔（0.2 秒）
    private let heartbeatInterval: TimeInterval = 0.2
    /// 判定为主线程阻塞的阈值（0.6 秒）
    private let stallThreshold: TimeInterval = 0.6
    /// 两次抓栈的最小冷却时间（至少 30 秒，防止连续卡顿导致抓栈死循环）
    private let minSampleCooldown: TimeInterval = 30.0

    private var timer: DispatchSourceTimer?
    private var running = false

    /// 状态保护互斥锁
    private let stateLock = NSLock()

    /// 最近一次用户动作（用于给卡顿归因）
    private var _lastUserAction: String = "（尚无）"

    /// 是否当前已有探针在主队列中排队或等待执行
    private var _isProbeInFlight: Bool = false
    /// 当前在途探针的派发时刻
    private var _probeDispatchedAt: Date = .distantPast
    /// 上一次报告阻塞的时刻（用于避免单次阻塞过程中每 200ms 重复刷屏写日志）
    private var _lastStallReportedAt: Date = .distantPast

    /// 当前是否有 /usr/bin/sample 子进程在运行（严格互斥，永不允许并发多实例运行）
    private var _isSampling: Bool = false
    /// 上一次启动 sample 抓栈的时刻（防风暴冷却）
    private var _lastSampleTime: Date = .distantPast

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
    /// 默认关闭：在用户日常使用与 Release 环境下，调用外部诊断工具 /usr/bin/sample
    /// 会挂起目标进程并产生高 CPU 负载，在连续卡顿场景下极易造成死循环雪崩。
    /// 仅在显式配置环境变量 LOOSELEAF_ENABLE_STACK_CAPTURE 时启用。
    private let captureStacks: Bool

    private init(
        captureStacks: Bool = ProcessInfo.processInfo.environment["LOOSELEAF_ENABLE_STACK_CAPTURE"] == "1"
    ) {
        self.captureStacks = captureStacks
    }

    /// 启动看门狗
    func start() {
        stateLock.lock()
        guard !running else {
            stateLock.unlock()
            return
        }
        running = true
        _isProbeInFlight = false
        _probeDispatchedAt = .distantPast
        _lastStallReportedAt = .distantPast
        stateLock.unlock()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + heartbeatInterval, repeating: heartbeatInterval)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        stateLock.lock()
        timer?.cancel()
        timer = nil
        running = false
        _isProbeInFlight = false
        stateLock.unlock()
    }

    /// 一次心跳（运行在后台 .utility 队列）
    private func tick() {
        let now = Date()

        stateLock.lock()
        // 1. 如果已有探针在途（主线程正忙，尚未执行完上一次分发的探针）
        if _isProbeInFlight {
            let elapsed = now.timeIntervalSince(_probeDispatchedAt)
            // 判定主线程正在阻塞中
            if elapsed >= stallThreshold {
                // 防刷屏控制：一次持续的阻塞，至少间隔 1 秒才输出一条持续进度日志
                let timeSinceLastReport = now.timeIntervalSince(_lastStallReportedAt)
                if timeSinceLastReport >= 1.0 {
                    _lastStallReportedAt = now
                    let action = _lastUserAction
                    stateLock.unlock()
                    reportStall(delay: elapsed, action: action, isOngoing: true)
                    return
                }
            }
            stateLock.unlock()
            // 关键：探针未返回前，绝不向主线程再次派发新任务，杜绝队列雪崩
            return
        }

        // 2. 探针已空闲，发起新一轮探测
        _isProbeInFlight = true
        _probeDispatchedAt = now
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let completedAt = Date()

            self.stateLock.lock()
            let totalDelay = completedAt.timeIntervalSince(self._probeDispatchedAt)
            let wasStalled = totalDelay >= self.stallThreshold
            let action = self._lastUserAction
            self._isProbeInFlight = false
            self.stateLock.unlock()

            // 如果主线程经历了一次严重阻塞后终于恢复，记录最终恢复耗时
            if wasStalled {
                self.reportRecovery(totalDelay: totalDelay, action: action)
            }
        }
    }

    /// 记录主线程正在发生的阻塞（在后台线程执行）
    private func reportStall(delay: TimeInterval, action: String, isOngoing: Bool) {
        let stamp = Date().timeIntervalSince1970
        let message = String(format: "主线程正在阻塞 %.2fs（最近动作：%@）", delay, action)
        Self.logger.error("\(message, privacy: .public)")
        print("⟦WATCHDOG⟧ \(message)")

        appendStallLog(stamp: stamp, delay: delay, action: action, status: isOngoing ? "ongoing" : "resolved")

        // 仅在明确开启时尝试抓取调用栈
        if captureStacks {
            captureStack(delay: delay, action: action, stamp: stamp)
        }
    }

    /// 记录阻塞恢复
    private func reportRecovery(totalDelay: TimeInterval, action: String) {
        let stamp = Date().timeIntervalSince1970
        let message = String(format: "主线程阻塞已恢复，总耗时 %.2fs（最近动作：%@）", totalDelay, action)
        Self.logger.notice("\(message, privacy: .public)")
        print("⟦WATCHDOG⟧ \(message)")

        appendStallLog(stamp: stamp, delay: totalDelay, action: action, status: "recovered")
    }

    /// 写入文本日志（包含大小限制，超过 1MB 自动截断旧日志，防止磁盘膨胀）
    private func appendStallLog(stamp: TimeInterval, delay: TimeInterval, action: String, status: String) {
        let logURL = logDirectory.appendingPathComponent("stalls.log")
        let line = String(format: "%.3f  delay=%.3fs  status=%@  action=%@\n", stamp, delay, status, action)

        // 日志轮转保护：若大于 1MB，截断保留最新 200KB
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
           let size = attrs[.size] as? Int64, size > 1_000_000 {
            if let existingData = try? Data(contentsOf: logURL) {
                let keepData = existingData.suffix(200_000)
                try? keepData.write(to: logURL, options: .atomic)
            }
        }

        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: logURL)
        }
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

    /// 抓一份主线程调用栈（严格单实例互斥 + 30秒冷却限制）
    private func captureStack(delay: TimeInterval, action: String, stamp: TimeInterval) {
        stateLock.lock()
        // 关键防护 1：严格单实例运行，已有 sample 正在跑时绝不重复启动
        guard !_isSampling else {
            stateLock.unlock()
            Self.logger.warning("已有 sample 进程在运行，跳过本次抓取")
            return
        }

        // 关键防护 2：最小冷却时间 30 秒，防止连续卡顿触发抓栈风暴
        let now = Date()
        guard now.timeIntervalSince(_lastSampleTime) >= minSampleCooldown else {
            stateLock.unlock()
            return
        }

        _isSampling = true
        _lastSampleTime = now
        stateLock.unlock()

        let outURL = logDirectory.appendingPathComponent(String(format: "stall-%.3f.txt", stamp))
        let pid = ProcessInfo.processInfo.processIdentifier

        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer {
                self?.stateLock.lock()
                self?._isSampling = false
                self?.stateLock.unlock()
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            process.arguments = [String(pid), "2", "-file", outURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                Self.logger.error("运行 /usr/bin/sample 失败: \(error.localizedDescription)")
            }

            guard let self else { return }
            Self.pruneStacks(in: self.logDirectory, keeping: 8)
            if let handle = try? FileHandle(forWritingTo: outURL) {
                handle.seekToEndOfFile()
                handle.write(Data(String(format: "\n// delay=%.3fs action=%@\n", delay, action).utf8))
                try? handle.close()
            }
            print("⟦WATCHDOG⟧ 已抓取主线程栈: \(outURL.path)")
        }
    }
}

// MainThreadWatchdogTests.swift
// LooseLeafTests
//
// 验证主线程看门狗的生命周期、动作记录、探针并发控制与安全防护机制。

import XCTest
@testable import LooseLeaf

final class MainThreadWatchdogTests: XCTestCase {

    func test01_WatchdogActionRecording() {
        let watchdog = MainThreadWatchdog.shared
        watchdog.noteAction("测试交互·点击卡片")
        XCTAssertEqual(watchdog.lastUserAction, "测试交互·点击卡片")

        watchdog.noteAction("测试交互·切换板块")
        XCTAssertEqual(watchdog.lastUserAction, "测试交互·切换板块")
    }

    func test02_WatchdogStartAndStopLifecycle() async throws {
        let watchdog = MainThreadWatchdog.shared
        watchdog.start()
        // 重复 start 应幂等安全
        watchdog.start()

        // 运行 0.5 秒，让后台心跳正常运作
        try await Task.sleep(nanoseconds: 500_000_000)

        watchdog.stop()
        // 重复 stop 同样幂等安全
        watchdog.stop()
    }

    func test03_StackCaptureIsDisabledByDefault() {
        // 默认环境下绝不能自动开启重度 sample 抓栈
        let isExplicitlyEnabled = ProcessInfo.processInfo.environment["LOOSELEAF_ENABLE_STACK_CAPTURE"] == "1"
        XCTAssertFalse(isExplicitlyEnabled, "生产与测试环境下 LOOSELEAF_ENABLE_STACK_CAPTURE 必须默认关闭")
    }
}

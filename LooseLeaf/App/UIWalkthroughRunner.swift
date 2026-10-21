import SwiftUI
import AppKit
import os

/// **脚本化 UI 走查**（诊断用，不参与日常运行）
///
/// 目的：把「用户点一下会卡」这种主观感受，变成**可采样、可归因**的主线程时间线。
/// 做法：以 `-UIWalkthrough` 启动参数运行真实 App，按脚本依次触发
/// 「打开弹窗 / 切页 / 开详情 / 切形态」等真实交互，每步之间留出采样窗口；
/// 外部用 `sample <pid>` 抓主线程栈，即可定位到具体热点函数。
///
/// 用法：
/// ```
/// .build/release/LooseLeaf -UIWalkthrough
/// sample <pid> 5 -file /tmp/lo.maintime.txt
/// ```
///
/// 每个步骤都会打印 `⟦WALK⟧ <步骤名> 开始/结束`，便于与采样结果对齐。
@MainActor
enum UIWalkthroughRunner {

    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "walkthrough")

    /// 走查日志
    ///
    /// 关键：必须走 **stderr**（无缓冲）。`print` 在 stdout 被重定向到文件时
    /// 是全缓冲的，进程不退出就一行都看不到 —— 曾因此误判「走查脚本没跑」。
    private static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// 是否处于脚本化走查模式
    static var isEnabled: Bool {
        CommandLine.arguments.contains("-UIWalkthrough")
    }

    /// 走查的每一步
    private struct Step {
        let name: String
        let hold: TimeInterval
        let action: @MainActor (AppState) -> Void
    }

    /// 启动走查（App 启动完成后调用）
    static func startIfEnabled() {
        guard isEnabled else { return }
        Task { @MainActor in
            // 等主窗口与首屏数据就位
            try? await Task.sleep(for: .seconds(3))
            await run()
        }
    }

    private static func run() async {
        let appState = AppState.shared

        let steps: [Step] = [
            Step(name: "打开创作弹窗", hold: 2.0) { s in
                s.showNewEntrySheet = true
            },
            Step(name: "关闭创作弹窗", hold: 1.0) { s in
                s.showNewEntrySheet = false
            },
            Step(name: "切到账目页", hold: 1.5) { s in
                s.activeSection = .ledger
            },
            Step(name: "切到心愿页", hold: 1.5) { s in
                s.activeSection = .wishes
            },
            Step(name: "切到足迹页", hold: 1.5) { s in
                s.activeSection = .atlas
            },
            Step(name: "切到造物页", hold: 1.5) { s in
                s.activeSection = .projects
            },
            Step(name: "切到主理人页", hold: 2.0) { s in
                s.activeSection = .dossier
            },
            Step(name: "切回时间流", hold: 1.5) { s in
                s.activeSection = .stream
            },
            Step(name: "打开全局检索", hold: 2.0) { s in
                s.showSearchModal = true
            },
            Step(name: "关闭全局检索", hold: 1.0) { s in
                s.showSearchModal = false
            },
            Step(name: "点击卡片（打开详情）", hold: 2.0) { s in
                s.highlightedEntry = s.entries.first
            },
            Step(name: "关闭详情", hold: 1.0) { s in
                s.highlightedEntry = nil
            },
            Step(name: "打开独立详情窗口", hold: 2.0) { s in
                s.detailWindowEntry = s.entries.first
            },
            Step(name: "关闭独立详情窗口", hold: 1.0) { s in
                s.detailWindowEntry = nil
            },
            Step(name: "触发一次全量刷新", hold: 2.0) { s in
                s.isOnline = true
            }
        ]

        log("⟦WALK⟧ ===== 开始脚本化走查（\\(steps.count) 步）=====")
        for (index, step) in steps.enumerated() {
            log("⟦WALK⟧ [\(index + 1)/\(steps.count)] \(step.name) — 开始")
            let start = Date()
            step.action(appState)
            // 让 runloop 真正把这一帧渲染出去（否则采样抓不到）
            try? await Task.sleep(for: .seconds(step.hold))
            let elapsed = Date().timeIntervalSince(start)
            log("⟦WALK⟧ [\(index + 1)/\(steps.count)] \(step.name) — 结束 (\(String(format: "%.3f", elapsed))s)")
        }
        log("⟦WALK⟧ ===== 走查结束 =====")
    }
}

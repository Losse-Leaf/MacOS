import SwiftUI
import AppKit

/// Loose-Leaf (活页集 · 散页) macOS 原生客户端入口 (`SwiftUI + AppKit`).
@main
public struct LooseLeafApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared

    public init() {}

    public var body: some Scene {
        // 1. 桌面主工作台窗口 (单例窗口；未配对展示主理人门禁，配对后直接进入全权管理工作台)
        Window("Loose-Leaf · 活页集", id: "main") {
            Group {
                if !appState.isPaired {
                    PairingGateView(appState: appState)
                        .frame(minWidth: 720, minHeight: 560)
                } else {
                    StreamView(appState: appState)
                        .frame(minWidth: 980, minHeight: 640)
                        .task {
                            await appState.refreshAll()
                            await UpdateChecker.shared.checkForUpdates(isUserInitiated: false)
                        }
                        .onOpenURL { url in
                            appState.handleIncomingURL(url)
                        }
                }
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查新版本…") {
                    Task { @MainActor in
                        await UpdateChecker.shared.checkForUpdates(isUserInitiated: true)
                    }
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("呼出极速闪念与记账悬浮窗") {
                    appDelegate.toggleQuickCapturePanel()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            CommandMenu("活页工作台") {
                ForEach(Array(WorkbenchSection.allCases.enumerated()), id: \.element.id) { index, section in
                    Button(section.title) {
                        var transaction = SwiftUI.Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            appState.activeSection = section
                        }
                        AudioFeedback.shared.playPaperFlip()
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                }

                Divider()

                Button("立即同步全量档案") {
                    Task { @MainActor in
                        await appState.refreshAll(forceFull: true)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("上一条散页") {
                    appState.moveSelection(by: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])

                Button("下一条散页") {
                    appState.moveSelection(by: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

                Button("打开选中的散页") {
                    appState.openKeyboardFocusedEntry()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }

        // 2. 常驻菜单栏动态活页夹 (MenuBarExtra)
        MenuBarExtra {
            Group {
                if !appState.isPaired {
                    PairingGateView(appState: appState)
                        .frame(width: 380, height: 460)
                } else {
                    QuickCaptureView(appState: appState)
                }
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        } label: {
            HStack(spacing: 4) {
                // 菜单栏模板图标：SF Symbol 随系统深浅色自适应；加载时呈现动态效果 (macOS 14+ pulse / macOS 15+ rotate)
                if #available(macOS 15.0, *) {
                    Image(systemName: appState.isLoading ? "arrow.triangle.2.circlepath" : "leaf.fill")
                        .symbolEffect(.rotate, isActive: appState.isLoading)
                } else {
                    Image(systemName: appState.isLoading ? "arrow.triangle.2.circlepath" : "leaf.fill")
                        .symbolEffect(.pulse, isActive: appState.isLoading)
                }
                if !appState.outboxItems.isEmpty {
                    Text("\(appState.outboxItems.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)

        // 3. 系统偏好设置窗口 (⌘,)
        Settings {
            SettingsView(appState: appState)
                .frame(minWidth: 680, minHeight: 540)
                .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
    }
}

import SwiftUI
import AppKit
import CoreSpotlight

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
                        .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                            if let uniqueId = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                                if uniqueId.hasPrefix("looseleaf-entry-"),
                                   let idStr = uniqueId.split(separator: "-").last,
                                   let entryId = Int(idStr) {
                                    appState.navigateToEntry(id: entryId)
                                }
                            }
                        }
                }
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("偏好设置…") {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        appState.activeSection = .preferences
                    }
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandGroup(after: .appInfo) {
                Button("检查新版本…") {
                    Task { @MainActor in
                        await UpdateChecker.shared.checkForUpdates(isUserInitiated: true)
                    }
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("记一笔…") {
                    appState.showNewEntrySheet = true
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("全局搜索档案…") {
                    appState.showSearchModal = true
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("呼出极速闪念与记账悬浮窗") {
                    appDelegate.toggleQuickCapturePanel()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            CommandMenu("活页工作台") {
                // ⌘1–⌘6 只绑六大内容板块；配置类条目不占用数字键
                ForEach(Array(WorkbenchSection.contentSections.enumerated()), id: \.element.id) { index, section in
                    Button(section.title) {
                        guard appState.activeSection != section else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            appState.activeSection = section
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                }

                Divider()

                ForEach(WorkbenchSection.configurationSections) { section in
                    Button(section.title) {
                        guard appState.activeSection != section else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            appState.activeSection = section
                        }
                    }
                }

                Divider()

                Button("生活刻度统计…") {
                    appState.showStatsSheet = true
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

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
                .keyboardShortcut(.upArrow, modifiers: [.command])

                Button("下一条散页") {
                    appState.moveSelection(by: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command])

                Button("打开选中的散页") {
                    appState.openKeyboardFocusedEntry()
                }
                .keyboardShortcut(.return, modifiers: [.command])
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
    }
}

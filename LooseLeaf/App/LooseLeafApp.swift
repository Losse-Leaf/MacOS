import SwiftUI
import AppKit
import CoreSpotlight

/// Loose-Leaf (活页集 · 散页) macOS 原生客户端入口 (`SwiftUI + AppKit`).
@main
public struct LooseLeafApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared

    public init() {}

    /// 关闭最上层的自定义弹层（⌘W）。
    /// 自绘 ZStack 弹层不是系统 sheet，拿不到系统级的 ⌘W 行为，必须自行实现。
    private func closeTopmostOverlay() {
        if appState.activeConfirmDialog != nil {
            appState.dismissConfirm()
        } else if appState.showSearchModal {
            appState.showSearchModal = false
        } else if appState.showStatsSheet {
            appState.showStatsSheet = false
        } else if appState.showNewEntrySheet {
            appState.showNewEntrySheet = false
        } else if appState.lightboxAttachment != nil {
            appState.lightboxAttachment = nil
        }
    }

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
            // 原生窗口工具栏：把「记一笔 / 同步 / 全局检索」提升到 macOS 标准位置。
            // 此前这些操作散落在侧栏、画布内工具条与右下角悬浮按钮三处，
            // 既不符合 HIG，也会随窗口尺寸漂移并遮挡内容。
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        appState.showSearchModal = true
                    } label: {
                        Label("全局档案检索", systemImage: ArchiveIcon.search.systemName)
                    }
                    .help("全局档案检索 (⌘K)")

                    Button {
                        Task { @MainActor in
                            await appState.refreshAll(forceFull: true)
                        }
                    } label: {
                        Label("同步档案", systemImage: ArchiveIcon.sync.systemName)
                    }
                    .help("全量同步中枢档案 (⌘R)")

                    Button {
                        appState.showNewEntrySheet = true
                    } label: {
                        Label("记一笔", systemImage: ArchiveIcon.add.systemName)
                    }
                    .help("记一笔 (⌘N)")
                }
            }
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
                Button("关闭当前弹层") {
                    closeTopmostOverlay()
                }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(!appState.hasOpenOverlay)

                Button("搜索散页…") {
                    appState.requestStreamSearchFocus()
                }
                .keyboardShortcut("f", modifiers: [.command])


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
                // ⌘1–⌘6 绑定六大内容板块；⌘7–⌘0 绑定五个配置板块与辅助工具
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

                ForEach(Array(WorkbenchSection.configurationSections.enumerated()), id: \.element.id) { index, section in
                    Button(section.title) {
                        guard appState.activeSection != section else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            appState.activeSection = section
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 7)")), modifiers: [.command])
                }

                Button("银盐暗房") {
                    guard appState.activeSection != .darkroom else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        appState.activeSection = .darkroom
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character("0")), modifiers: [.command])

                Divider()

                Button("键盘快捷键速查…") {
                    appState.activeSection = .preferences
                }
                .keyboardShortcut(KeyEquivalent(Character("/")), modifiers: [.command])

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

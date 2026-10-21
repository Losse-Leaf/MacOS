import SwiftUI
import AppKit
import CoreSpotlight

/// Loose-Leaf (活页集 · 散页) macOS 原生客户端入口 (`SwiftUI + AppKit`).
@main
public struct LooseLeafApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared

    public init() {}

    /// 板块快捷键：显式数组，禁止再用 `Character("\(index + 7)")`。
    /// 数字 ≥10 时 Character(String) 会触发「more than one extended grapheme cluster」运行时崩溃，
    /// 且配置板块有 5 项，⌘7–⌘0 只有 4 个键位，必然越界。
    private static let contentShortcuts: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6"]
    private static let configurationShortcuts: [KeyEquivalent] = ["1", "2", "3", "4", "5"]

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
        } else if appState.editingEntry != nil {
            // 关键：详情 / 编辑这三个 sheet 也要能被 ⌘W 关掉。
            // 上一轮把它们加进了 `hasOpenOverlay`（⌘W 菜单项变成可用了），
            // 却没有在这里加对应处理 —— 于是菜单项可点却**毫无反应**。
            // 这是我自己引入的回归。
            appState.editingEntry = nil
        } else if appState.editingTransaction != nil {
            appState.editingTransaction = nil
        } else if appState.highlightedEntry != nil {
            appState.highlightedEntry = nil
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

            CommandGroup(replacing: .undoRedo) {
                Button(appState.undoActionLabel.map { "撤销 \($0)" } ?? "撤销") {
                    Task { @MainActor in
                        await appState.performUndo()
                    }
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!appState.canUndo)
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
                // ⌘1–⌘6 绑定六大内容板块；⌥⌘1–⌥⌘5 绑定配置板块。
                // prefix 防御：将来新增板块但忘记补快捷键时，只是没有快捷键，不会数组越界。
                let contentSections = Array(WorkbenchSection.contentSections.prefix(Self.contentShortcuts.count))
                ForEach(Array(contentSections.enumerated()), id: \.element.id) { index, section in
                    Button(section.title) {
                        guard appState.activeSection != section else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            appState.activeSection = section
                        }
                    }
                    .keyboardShortcut(Self.contentShortcuts[index], modifiers: [.command])
                }

                Divider()

                let configurationSections = Array(WorkbenchSection.configurationSections.prefix(Self.configurationShortcuts.count))
                ForEach(Array(configurationSections.enumerated()), id: \.element.id) { index, section in
                    Button(section.title) {
                        guard appState.activeSection != section else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            appState.activeSection = section
                        }
                    }
                    .keyboardShortcut(Self.configurationShortcuts[index], modifiers: [.command, .option])
                }

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

        // 2. 独立散页详情窗口（深链 looseleaf://entry/<id> 与「在新窗口打开」使用）
        Window("散页详情", id: "detail") {
            Group {
                if let entry = appState.detailWindowEntry {
                    StreamEntryDetailView(entry: entry, appState: appState)
                        .frame(minWidth: 520, minHeight: 380)
                        .background(ArchivePalette.archivePaper)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        Text("未选定散页")
                            .font(ArchiveTypography.editorialSerif(size: 15, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("从时间流中打开一条手稿，或用 looseleaf://entry/<id> 深链直达")
                            .font(ArchiveTypography.bodySans(size: 12))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    .frame(minWidth: 520, minHeight: 380)
                    .background(ArchivePalette.archivePaper)
                }
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .defaultSize(width: 620, height: 560)
        .windowResizability(.contentMinSize)

        // 3. 常驻菜单栏动态活页夹 (MenuBarExtra)
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

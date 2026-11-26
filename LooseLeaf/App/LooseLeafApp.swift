import SwiftUI
import AppKit
import CoreSpotlight

/// 独立散页详情窗口宿主视图（支持 `WindowGroup(for: Int.self)` 多窗口并排对照，窗口内自持编辑、删除确认与看图灯箱）
@MainActor
private struct StandaloneEntryDetailWindow: View {
    let entryId: Int?
    @Bindable var appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var localEditingEntry: LifeEntry?
    @State private var localEditingTx: Transaction?
    @State private var localLightbox: Attachment?
    @State private var localConfirm: ConfirmDialogRequest?

    private var resolvedEntry: LifeEntry? {
        if let id = entryId {
            if let live = appState.entries.first(where: { $0.id == id }) {
                return live
            }
            if appState.detailWindowEntry?.id == id {
                return appState.detailWindowEntry
            }
        }
        return appState.detailWindowEntry
    }

    var body: some View {
        ZStack {
            if let entry = resolvedEntry {
                StreamEntryDetailView(
                    entry: entry,
                    appState: appState,
                    isStandaloneWindow: true,
                    onClose: {
                        if appState.detailWindowEntry?.id == entry.id {
                            appState.detailWindowEntry = nil
                        }
                        NSApp.keyWindow?.performClose(nil)
                    },
                    onEditEntry: { target in
                        localEditingEntry = target
                    },
                    onEditTransaction: { tx in
                        localEditingTx = tx
                    },
                    onDeleteTransaction: { tx in
                        localConfirm = ConfirmDialogRequest(
                            title: ArchiveSharedCopy.transactionDeleteTitle,
                            message: ArchiveSharedCopy.transactionDeleteMessage,
                            confirmText: ArchiveSharedCopy.transactionDeleteConfirmText,
                            danger: true
                        ) {
                            appState.deleteTransactionAction(tx)
                            NSApp.keyWindow?.performClose(nil)
                        }
                    },
                    onDeleteEntryOverride: { target in
                        localConfirm = ConfirmDialogRequest(
                            title: ArchiveSharedCopy.entryDeleteTitle,
                            message: ArchiveSharedCopy.entryDeleteMessage,
                            confirmText: ArchiveSharedCopy.entryDeleteConfirmText,
                            danger: true
                        ) {
                            appState.deleteEntryAction(target)
                            NSApp.keyWindow?.performClose(nil)
                        }
                    },
                    onOpenAttachment: { att in
                        localLightbox = att
                    }
                )
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
                    Text("从时间流中右键选择「在新窗口打开」，或用 looseleaf://entry/<id> 深链直达")
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minWidth: 520, minHeight: 380)
                .background(ArchivePalette.archivePaper)
            }

            if let att = localLightbox {
                EditorialLightboxView(
                    attachment: att,
                    allAttachments: resolvedEntry?.attachments ?? [att]
                ) {
                    localLightbox = nil
                }
                .zIndex(100)
            }
        }
        .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        .alert(
            localConfirm?.title ?? "请确认",
            isPresented: Binding(
                get: { localConfirm != nil },
                set: { if !$0 { localConfirm = nil } }
            ),
            presenting: localConfirm
        ) { req in
            Button(req.confirmText, role: req.danger ? .destructive : nil) {
                let action = req.onConfirm
                localConfirm = nil
                action()
            }
            Button(req.cancelText, role: .cancel) {
                let onCancel = req.onCancel
                localConfirm = nil
                onCancel?()
            }
        } message: { req in
            Text(req.message)
        }
        .sheet(item: $localEditingEntry) { target in
            EditEntrySheetView(entry: target) { updated in
                _ = try await APIClient.shared.updateEntry(id: target.id, updated)
                await appState.loadEntries(forceFull: false)
                await appState.loadConfigAndProfile()
                localEditingEntry = nil
            } onCancel: {
                localEditingEntry = nil
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .sheet(item: $localEditingTx) { tx in
            EditTransactionSheet(appState: appState, transaction: tx) {
                localEditingTx = nil
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .onDisappear {
            if let id = entryId, appState.detailWindowEntry?.id == id {
                appState.detailWindowEntry = nil
            } else if entryId == nil {
                appState.detailWindowEntry = nil
            }
        }
    }
}

/// Loose-Leaf (活页集 · 散页) macOS 原生客户端入口 (`SwiftUI + AppKit`).
@main
public struct LooseLeafApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared

    public init() {}

    private static let contentShortcuts: [KeyEquivalent] = ["1", "2"]
    private static let configurationShortcuts: [KeyEquivalent] = ["1", "2", "3"]

    /// 关闭主窗口最上层的自定义弹层（无弹层时走原生 `NSWindow.performClose`）
    private func closeTopmostOverlayOrWindow() {
        let isMainWindowKey = NSApp.keyWindow?.identifier?.rawValue == "main"
            || (NSApp.keyWindow != nil && NSApp.keyWindow === NSApp.mainWindow && appState.hasOpenOverlay)
        if isMainWindowKey && appState.hasOpenOverlay {
            if appState.activeConfirmDialog != nil {
                appState.dismissConfirm()
            } else if appState.showSearchModal {
                appState.showSearchModal = false
            } else if appState.lightboxAttachment != nil {
                appState.lightboxAttachment = nil
            } else if appState.showNewEntrySheet {
                appState.showNewEntrySheet = false
            } else if appState.editingEntry != nil {
                appState.editingEntry = nil
            } else if appState.editingTransaction != nil {
                appState.editingTransaction = nil
            } else if appState.highlightedEntry != nil {
                appState.highlightedEntry = nil
            }
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    public var body: some Scene {
        // 1. 桌面主工作台窗口（最小尺寸适配 13"/14" MacBook Split View 分屏）
        Window("Loose-Leaf · 活页集", id: "main") {
            Group {
                if !appState.isPaired {
                    PairingGateView(appState: appState)
                        .frame(minWidth: 680, minHeight: 500)
                } else {
                    StreamView(appState: appState)
                        .frame(minWidth: 800, minHeight: 520)
                }
            }
            .onOpenURL { url in
                appState.handleIncomingURL(url)
            }
            .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                SpotlightIndexer.handleContinuationActivity(userActivity, appState: appState)
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        appState.showSearchModal = true
                    } label: {
                        Label("全局档案检索", systemImage: ArchiveIcon.search.systemName)
                    }
                    .help("全局档案检索 (⌘K)")
                    .disabled(!appState.isPaired || appState.hasOpenOverlay)

                    Button {
                        Task { @MainActor in
                            await appState.refreshAll(forceFull: true)
                        }
                    } label: {
                        Label("同步档案", systemImage: ArchiveIcon.sync.systemName)
                    }
                    .help("全量同步中枢档案 (⌘R)")
                    .disabled(appState.hasOpenOverlay || !appState.isPaired || appState.isLoading || appState.isFlushingOutbox)

                    Button {
                        appState.showNewEntrySheet = true
                    } label: {
                        Label("记一笔", systemImage: ArchiveIcon.add.systemName)
                    }
                    .help("记一笔 (⌘N)")
                    .disabled(!appState.isPaired || appState.hasOpenOverlay)
                }
            }
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

            CommandGroup(replacing: .undoRedo) {
                Button(appState.undoActionLabel.map { "撤销 \($0)" } ?? "撤销") {
                    // 关键护栏：若当前焦点位于文本输入框（AppKit NSTextView），优先转发原生文本撤销，
                    // 绝不能抢走用户的打字撤销甚至误恢复后台刚删除的手稿！
                    if NSApp.keyWindow?.firstResponder is NSTextView {
                        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                    } else {
                        Task { @MainActor in
                            await appState.performUndo()
                        }
                    }
                }
                .keyboardShortcut("z", modifiers: [.command])

                Button("重做") {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .newItem) {
                Button(appState.hasOpenOverlay ? "关闭当前弹层" : "关闭窗口") {
                    closeTopmostOverlayOrWindow()
                }
                .keyboardShortcut("w", modifiers: [.command])

                Button("搜索散页…") {
                    appState.requestStreamSearchFocus()
                }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(!appState.isPaired)

                Button("记一笔…") {
                    appState.showNewEntrySheet = true
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(!appState.isPaired)

                Button("全局搜索档案…") {
                    appState.showSearchModal = true
                }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(!appState.isPaired)

                Button("呼出极速闪念与记账悬浮窗 (\(AppDelegate.hotKeyDisplayName))") {
                    appDelegate.toggleQuickCapturePanel()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            CommandMenu("活页工作台") {
                let contentSections = Array(WorkbenchSection.contentSections.prefix(Self.contentShortcuts.count))
                ForEach(Array(contentSections.enumerated()), id: \.element.id) { index, section in
                    Button(section.title) {
                        guard appState.activeSection != section else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            appState.activeSection = section
                        }
                    }
                    .keyboardShortcut(Self.contentShortcuts[index], modifiers: [.command])
                    .disabled(!appState.isPaired)
                }

                Divider()

                ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element.id) { index, tab in
                    Button("\(tab.rawValue)…") {
                        appState.openSettings(tab: tab)
                    }
                    .keyboardShortcut(Self.configurationShortcuts[index], modifiers: [.command, .option])
                }

                Divider()

                Button("键盘快捷键速查…") {
                    appState.openSettings(tab: .general)
                }
                .keyboardShortcut(KeyEquivalent(Character("/")), modifiers: [.command])

                Divider()

                Button("立即同步全量档案") {
                    Task { @MainActor in
                        await appState.refreshAll(forceFull: true)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!appState.isPaired || appState.isLoading)

                Divider()

                Button("上一条散页") {
                    appState.moveSelection(by: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])
                .disabled(!appState.isPaired)

                Button("下一条散页") {
                    appState.moveSelection(by: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command])
                .disabled(!appState.isPaired)

                Button("打开选中的散页") {
                    appState.openKeyboardFocusedEntry()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!appState.isPaired)
            }
        }

        // 2. 原生 macOS 独立设置窗口 (⌘,)
        Settings {
            SettingsView(appState: appState)
                .frame(minWidth: 680, idealWidth: 760, minHeight: 520, idealHeight: 640)
                .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }

        // 3. 独立散页详情窗口组（支持多篇并排对照阅读及深链直达）
        WindowGroup("散页详情", id: "detail", for: Int.self) { $entryId in
            StandaloneEntryDetailWindow(entryId: entryId, appState: appState)
        }
        .defaultSize(width: 640, height: 580)
        .windowResizability(.contentMinSize)

        // 4. 常驻菜单栏动态活页夹 (MenuBarExtra)
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

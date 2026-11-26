import SwiftUI
import AppKit

/// 独立观察 `AppBanners` 的顶部提示浮层
private struct StreamBannerOverlay: View {
    @Bindable var banners: AppBanners

    var body: some View {
        VStack(spacing: 4) {
            if let err = banners.error {
                noticeStrip(text: err, isError: true) {
                    banners.error = nil
                }
            }
            if let warning = banners.localWarning {
                noticeStrip(text: warning, isError: true) {
                    banners.localWarning = nil
                }
            }
            if let status = banners.status {
                noticeStrip(text: status, isError: false) {
                    banners.status = nil
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .allowsHitTesting(true)
    }

    private func noticeStrip(text: String, isError: Bool, onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                .foregroundStyle(isError ? ArchivePalette.accentWarm : ArchivePalette.accentMoss)
            Text(text)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkPrimary)
            Spacer()
            Button("关闭") {
                onDismiss()
            }
            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
            .buttonStyle(.plain)
            .paperButtonFocusRing(cornerRadius: 3)
            .foregroundStyle(ArchivePalette.inkMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
        )
    }
}

/// 桌面主窗口工作台 (Bear / Day One 风格三栏阅读架构)
/// 1. 左侧：完整导航树（散页 / 画廊 / 财务与心愿）
/// 2. 散页态：中栏按月分组目录 + 右栏纯净阅读/原地编辑（无噪点、无相纸白框、无时间轴圆点）
/// 3. 财务与心愿态：自动展开为两栏宽工作区（流水表格 / 无边框心愿网格）
@MainActor
public struct StreamView: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var localSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?

    public init(appState: AppState) {
        self.appState = appState
    }

    private var currentWindowTitle: String {
        appState.navigation.sidebarDestination.title
    }

    private var currentWindowSubtitle: String {
        switch appState.navigation.sidebarDestination {
        case .ledger:
            return "收支明细与月度类目光谱"
        case .wishlist:
            return "好物 · 旅程 · 里程碑"
        default:
            return "\(appState.displayedStreamEntries.count) 篇散页"
        }
    }

    private var currentSearchPrompt: String {
        switch appState.navigation.sidebarDestination {
        case .ledger:
            return "筛选账目流水…"
        case .wishlist:
            return "筛选心愿清单…"
        default:
            return "搜索散页或远端归档…"
        }
    }

    public var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                WorkbenchSidebar(appState: appState) { _ in }
                    .navigationSplitViewColumnWidth(min: 195, ideal: 215, max: 255)
            } detail: {
                ZStack {
                    ArchivePalette.archivePaper
                        .ignoresSafeArea()

                    switch appState.navigation.sidebarDestination {
                    case .ledger:
                        LedgerAssetsView(appState: appState)
                    case .wishlist:
                        WishlistView(appState: appState, embedded: false)
                    case .allEntries, .daily, .privateEntries, .onThisDay, .category:
                        HSplitView {
                            StreamEntryListView(appState: appState)
                                .frame(minWidth: 265, idealWidth: 315, maxWidth: 400)

                            StreamEntryReaderView(appState: appState)
                                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    StreamBannerOverlay(banners: appState.banners)
                }
                .navigationTitle(currentWindowTitle)
                .navigationSubtitle(currentWindowSubtitle)
            }
            .searchable(text: $localSearchText, placement: .toolbar, prompt: currentSearchPrompt)
            .accessibilityHidden(appState.hasOpenOverlay)

            // 暗房全屏看图灯箱
            if let att = appState.lightboxAttachment {
                EditorialLightboxView(
                    attachment: att,
                    allAttachments: appState.entries.first(where: { $0.attachments.contains(where: { $0.id == att.id }) })?.attachments ?? [att]
                ) {
                    appState.lightboxAttachment = nil
                }
            }

            // 全局聚光灯档案检索 (⌘K Spotlight)
            if appState.showSearchModal {
                PaperModalOverlay(onDismiss: {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                        appState.showSearchModal = false
                    }
                }) {
                    GlobalSearchModalView(
                        appState: appState,
                        onDismiss: {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                                appState.showSearchModal = false
                            }
                        },
                        onSelectEntry: { entry in
                            if !appState.navigation.sidebarDestination.isStreamDestination {
                                appState.navigation.selectDestination(.allEntries)
                            }
                            appState.keyboardFocusedEntryId = entry.id
                            appState.highlightedEntry = entry
                        },
                        onSelectWish: { wish in
                            appState.navigation.highlightedWishId = wish.id
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                                appState.navigation.selectDestination(.wishlist)
                            }
                        }
                    )
                }
                .zIndex(120)
            }
        }
        .background(
            HostingWindowCloseObserver {
                // 主窗口关闭退驻后台/菜单栏时主动释放 ~120MB 位图解码缓存池
                PaperImageCache.clearMemoryCache()
            }
        )
        .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        .sheet(isPresented: $appState.showNewEntrySheet) {
            NewEntryModal(appState: appState) {
                appState.showNewEntrySheet = false
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .sheet(item: $appState.editingEntry) { entry in
            EditEntrySheetView(entry: entry) { updated in
                _ = try await APIClient.shared.updateEntry(id: entry.id, updated)
                await appState.loadEntries(forceFull: false)
                await appState.loadConfigAndProfile()
                appState.editingEntry = nil
            } onCancel: {
                appState.editingEntry = nil
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .sheet(item: $appState.editingTransaction) { tx in
            EditTransactionSheet(appState: appState, transaction: tx) {
                appState.editingTransaction = nil
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .alert(
            appState.activeConfirmDialog?.title ?? "请确认",
            isPresented: Binding(
                get: { appState.activeConfirmDialog != nil },
                set: { if !$0 { appState.activeConfirmDialog = nil } }
            ),
            presenting: appState.activeConfirmDialog
        ) { req in
            Button(req.confirmText, role: req.danger ? .destructive : nil) {
                if appState.enablesHapticFeedback { ArchiveFeedback.light() }
                let action = req.onConfirm
                appState.activeConfirmDialog = nil
                action()
            }
            Button(req.cancelText, role: .cancel) {
                appState.dismissConfirm()
            }
        } message: { req in
            Text(req.message)
        }
        .onAppear {
            localSearchText = appState.searchQuery
            appState.navigation.syncDestinationFromLegacyState()
            ensureInitialEntrySelection()
        }
        .onChange(of: localSearchText) { _, newVal in
            searchDebounceTask?.cancel()
            let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                appState.searchQuery = ""
                appState.clearGlobalSearchResult()
            } else {
                searchDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard !Task.isCancelled else { return }
                    appState.searchQuery = newVal
                    if appState.navigation.sidebarDestination.isStreamDestination && appState.isPaired {
                        await appState.performGlobalSearch(query: trimmed)
                    }
                }
            }
        }
        .onChange(of: appState.searchQuery) { _, newVal in
            if localSearchText != newVal {
                localSearchText = newVal
            }
        }
        .onChange(of: appState.searchFocusRequest) { _, _ in
            ToolbarSearchFocus.activate()
        }
        .onChange(of: appState.detailWindowEntry?.id) { _, newValue in
            guard let id = newValue else { return }
            openWindow(id: "detail", value: id)
        }
        .onChange(of: appState.navigation.sidebarDestination) { _, newDest in
            if newDest.isStreamDestination {
                ensureSelectionMatchesDisplayedList()
            }
        }
        .onChange(of: appState.entries) { _, newEntries in
            if let current = appState.highlightedEntry, current.type != "transaction" {
                if let updated = newEntries.first(where: { $0.id == current.id }) {
                    if updated != current {
                        appState.highlightedEntry = updated
                    }
                } else if current.id > 0 {
                    appState.highlightedEntry = appState.displayedStreamEntries.first
                }
            } else if appState.highlightedEntry == nil && appState.navigation.sidebarDestination.isStreamDestination {
                ensureInitialEntrySelection()
            }
        }
        .onChange(of: appState.activeSection) { _, newSec in
            if WorkbenchSection.configurationSections.contains(newSec) {
                let tab: SettingsTab = switch newSec {
                case .hub: .devices
                case .about: .about
                default: .general
                }
                appState.activeSection = .stream
                appState.navigation.settingsSelectedTab = tab
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            appState.navigation.syncDestinationFromLegacyState()
        }
        .onChange(of: appState.navigation.ledgerSubTab) { _, _ in
            if appState.activeSection == .ledger {
                appState.navigation.syncDestinationFromLegacyState()
            }
        }
        .onChange(of: appState.navigation.settingsOpenToken) { _, _ in
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .onExitCommand {
            if appState.showSearchModal {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { appState.showSearchModal = false }
            } else if appState.lightboxAttachment != nil {
                appState.lightboxAttachment = nil
            }
        }
    }

    private func ensureInitialEntrySelection() {
        guard appState.navigation.sidebarDestination.isStreamDestination,
              appState.highlightedEntry == nil,
              let first = appState.displayedStreamEntries.first else { return }
        appState.highlightedEntry = first
        appState.keyboardFocusedEntryId = first.id
    }

    private func ensureSelectionMatchesDisplayedList() {
        let list = appState.displayedStreamEntries
        if let current = appState.highlightedEntry, list.contains(where: { $0.id == current.id }) {
            return
        }
        if let first = list.first {
            appState.highlightedEntry = first
            appState.keyboardFocusedEntryId = first.id
        } else {
            appState.highlightedEntry = nil
        }
    }
}

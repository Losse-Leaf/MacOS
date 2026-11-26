import SwiftUI
import AppKit

/// 工作台左侧导航栏 (Workbench Sidebar)
/// 1. 使用原生 `List(selection:)` + 可选类型 `.tag(dest as SidebarDestination?)` 修复 macOS 选中与点击响应
/// 2. 完整承载「散页 / 画廊分类 / 财务与心愿」三组导航树，让系统侧栏磨砂通透与内容区分明
/// 3. 显式注入暖纸朱砂与矿物语义色图标，消除系统默认蓝；底栏收口为极简单行状态条与设置入口
struct WorkbenchSidebar: View {
    @Bindable var appState: AppState
    var onSelect: (WorkbenchSection) -> Void = { _ in }

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var badgeState: HubConnectionBadgeState {
        appState.hubConnectionBadgeState
    }

    private var destinationSelectionBinding: Binding<SidebarDestination?> {
        Binding(
            get: { appState.navigation.sidebarDestination },
            set: { newValue in
                guard let dest = newValue else { return }
                let prevSection = appState.activeSection
                appState.navigation.selectDestination(dest)
                if appState.activeSection != prevSection {
                    onSelect(appState.activeSection)
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: destinationSelectionBinding) {
                Section("散页") {
                    sidebarRow(
                        SidebarDestination.allEntries.title,
                        systemImage: "book.pages",
                        tint: ArchivePalette.accentWarm,
                        badge: appState.entries.count
                    )
                    .tag(SidebarDestination.allEntries)

                    sidebarRow(
                        SidebarDestination.daily.title,
                        systemImage: "doc.text",
                        tint: ArchivePalette.accentMoss,
                        badge: appState.dailyEntriesCount
                    )
                    .tag(SidebarDestination.daily)

                    sidebarRow(
                        SidebarDestination.privateEntries.title,
                        systemImage: "lock",
                        tint: ArchivePalette.accentWarm,
                        badge: appState.privateEntriesCount
                    )
                    .tag(SidebarDestination.privateEntries)

                    if !appState.onThisDayEntries.isEmpty {
                        sidebarRow(
                            SidebarDestination.onThisDay.title,
                            systemImage: "clock.arrow.circlepath",
                            tint: ArchivePalette.accentWarm,
                            badge: appState.onThisDayEntries.count
                        )
                        .tag(SidebarDestination.onThisDay)
                    }
                }

                Section("画廊") {
                    ForEach(EntryCategory.galleryCases) { category in
                        let dest = SidebarDestination.category(category)
                        sidebarRow(
                            category.label,
                            systemImage: category.symbolName,
                            tint: category.accentColor,
                            badge: appState.entryCount(for: category)
                        )
                        .tag(dest)
                    }
                }

                Section("财务与心愿") {
                    sidebarRow(
                        SidebarDestination.ledger.title,
                        systemImage: "creditcard",
                        tint: ArchivePalette.spectrumDining,
                        badge: appState.transactionsNeedingUpload
                    )
                    .tag(SidebarDestination.ledger)

                    sidebarRow(
                        SidebarDestination.wishlist.title,
                        systemImage: "sparkles",
                        tint: ArchivePalette.spectrumLeisure,
                        badge: appState.wantingWishesCount
                    )
                    .tag(SidebarDestination.wishlist)
                }
            }
            .listStyle(.sidebar)
            .tint(ArchivePalette.accentWarm)

            bottomUtilityBar
        }
        .background {
            if reduceTransparency {
                ArchivePalette.archiveSubtle
            }
        }
    }

    private func sidebarRow(
        _ title: String,
        systemImage: String,
        tint: Color,
        badge: Int
    ) -> some View {
        Label {
            Text(title)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading))
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .imageScale(.medium)
        }
        .badge(badge)
    }

    private var bottomUtilityBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.6))

            HStack(spacing: 6) {
                if differentiateWithoutColor {
                    Image(systemName: badgeState.symbolName)
                        .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.micro, weight: .medium))
                        .foregroundStyle(badgeState.dotColor)
                        .accessibilityHidden(true)
                } else {
                    Circle()
                        .fill(badgeState.dotColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }

                Text(badgeState.label)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if appState.entriesNeedingUpload + appState.transactionsNeedingUpload > 0 {
                    Button("重传") {
                        appState.reuploadAllPending()
                    }
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro, weight: .semibold))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .buttonStyle(.plain)
                    .paperButtonFocusRing(cornerRadius: 3)
                    .help("重新上传全部待同步内容")
                    .accessibilityLabel("重新上传全部待同步内容")
                }

                Spacer(minLength: 4)

                Button {
                    (NSApp.delegate as? AppDelegate)?.toggleQuickCapturePanel()
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                .help("极速闪念 (\(AppDelegate.hotKeyDisplayName))")
                .accessibilityLabel("呼出极速闪念面板")

                Button {
                    appState.navigation.settingsSelectedTab = .general
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape")
                        .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.body))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                .help("偏好与设置 (⌘,)")
                .accessibilityLabel("打开偏好与设置")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

import SwiftUI
import AppKit

/// 工作台左侧导航栏 (Workbench Sidebar)
/// 严格遵循 macOS HIG 与 macos-native-ui 规范：
/// 1. 适配原生 `NavigationSplitView` 列宽调解与 `⌃⌘S` 侧栏折叠，去除硬编码 42pt 顶部空白
/// 2. 「偏好与设置」唤起 macOS 标准独立 `Settings` 窗口 (`⌘,`)，不再霸占主画布
/// 3. 完整适配「减少透明度」与「不靠颜色区分」系统级辅助偏好，底栏双行防挤压换行
struct WorkbenchSidebar: View {
    @Bindable var appState: AppState
    var onSelect: (WorkbenchSection) -> Void

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var badgeState: HubConnectionBadgeState {
        appState.hubConnectionBadgeState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 刊头印记 (100% 动态读取后端配置与主理人档案)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 13, weight: .medium))
                        .imageScale(.medium)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ArchivePalette.accentMoss)
                        .accessibilityHidden(true)

                    Text(appState.siteConfig.siteName.isEmpty ? "散页 · 时光手账" : appState.siteConfig.siteName)
                        .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)
                }

                if !appState.profile.name.isEmpty || !appState.profile.displayCity.isEmpty {
                    Text(
                        [appState.profile.name, appState.profile.displayCity]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                    )
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 导航菜单项：6 大生活内容板块 + 原生独立设置窗口入口
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("生活卷宗")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(.horizontal, 12)
                        .padding(.top, 2)
                        .padding(.bottom, 3)

                    ForEach(WorkbenchSection.contentSections) { section in
                        WorkbenchNavRow(
                            section: section,
                            selected: appState.activeSection == section,
                            reduceMotion: reduceMotion
                        ) {
                            guard appState.activeSection != section else { return }
                            onSelect(section)
                        }
                    }

                    Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))
                        .padding(.vertical, 6)

                    // 唤起原生 macOS 独立设置窗口 (⌘,)
                    WorkbenchNavRow(
                        section: .preferences,
                        selected: false,
                        customTitle: "偏好与设置…",
                        customIcon: "gearshape",
                        reduceMotion: reduceMotion
                    ) {
                        appState.navigation.settingsSelectedTab = .general
                        openSettings()
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 8)

            // 底部系统状态与极速捕捉热键徽标（紧凑双层防窄栏挤压竖排）
            VStack(alignment: .leading, spacing: 6) {
                Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))

                HStack(spacing: 5) {
                    if differentiateWithoutColor {
                        Image(systemName: badgeState.symbolName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(badgeState.dotColor)
                            .accessibilityHidden(true)
                    } else {
                        Circle()
                            .fill(badgeState.dotColor)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }

                    Text(badgeState.label)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    if appState.entriesNeedingUpload + appState.transactionsNeedingUpload > 0 {
                        Button {
                            appState.reuploadAllPending()
                        } label: {
                            Text("全部重传")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro, weight: .semibold))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .underline()
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .paperButtonFocusRing(cornerRadius: 3)
                        .help("把所有待同步 / 同步失败的内容重新上传到中枢")
                        .accessibilityLabel("重新上传全部待同步内容")
                    }
                }

                Button {
                    (NSApp.delegate as? AppDelegate)?.toggleQuickCapturePanel()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .accessibilityHidden(true)
                        Text("极速闪念")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(AppDelegate.hotKeyDisplayName)
                            .font(ArchiveTypography.monoScale(size: 9.5, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(ArchivePalette.archivePaper.opacity(reduceTransparency ? 1.0 : 0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .paperButtonFocusRing(cornerRadius: 3)
                .help("呼出极速闪念与记账悬浮面板 (\(AppDelegate.hotKeyDisplayName))")
                .accessibilityLabel("呼出极速闪念与记账悬浮面板，快捷键 \(AppDelegate.hotKeyDisplayName)")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background {
            if reduceTransparency {
                ArchivePalette.archiveSubtle
            } else {
                ZStack {
                    WindowVibrancyView(material: .sidebar, blendingMode: .behindWindow)
                    ArchivePalette.archivePaper.opacity(0.78)
                }
            }
        }
    }

    /// 侧边导航行：符合 macOS HIG 规范，支持层级 SF Symbols、微胶囊背景与左侧朱砂指示线
    struct WorkbenchNavRow: View {
        let section: WorkbenchSection
        let selected: Bool
        var customTitle: String? = nil
        var customIcon: String? = nil
        var reduceMotion: Bool = false
        let action: () -> Void

        @State private var isHovering: Bool = false

        private var effectiveTitle: String {
            customTitle ?? section.title
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: customIcon ?? section.icon)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .imageScale(.medium)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(selected ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                        .frame(width: 18)

                    Text(effectiveTitle)
                        .font(ArchiveTypography.bodySans(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? ArchivePalette.inkPrimary : ArchivePalette.inkSecondary)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.leading, 10)
                .padding(.trailing, 10)
                .padding(.vertical, 6.5)
                .background(
                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                        .fill(rowFill)
                )
                .overlay(alignment: .leading) {
                    if selected {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(ArchivePalette.accentWarm)
                            .frame(width: 2.5, height: 14)
                            .padding(.leading, 2)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                        .stroke(selected ? ArchivePalette.borderDivider.opacity(0.6) : Color.clear, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .paperButtonFocusRing(cornerRadius: ArchiveRadius.sm)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: selected)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isHovering)
            .onHover { isHovering = $0 }
            .accessibilityLabel(effectiveTitle)
            .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
        }

        private var rowFill: Color {
            if selected { return ArchivePalette.archiveSubtle }
            return isHovering ? ArchivePalette.archiveSubtle.opacity(0.55) : .clear
        }
    }
}

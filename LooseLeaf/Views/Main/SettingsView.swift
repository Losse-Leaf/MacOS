import SwiftUI

/// 配置中心分类标签枚举
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general = "偏好设置"
    case devices = "中枢与设备"
    case about = "关于活页"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .general: return ArchiveIcon.preferences.systemName
        case .devices: return ArchiveIcon.hub.systemName
        case .about: return ArchiveIcon.about.systemName
        }
    }
}

/// 活页集原生设置窗口外壳 (SettingsView · `⌘,`)
/// 遵循 macOS HIG 标准独立 `Settings` Scene 规范：
/// 1. 双向绑定 `appState.navigation.settingsSelectedTab`，支持 `⌥⌘1–3` 与更新提示跨窗口精准切页
/// 2. 本文件是唯一持有 `ScrollView` 与外层留白的容器，各子面板输出纯粹的 `VStack`
@MainActor
public struct SettingsView: View {
    @Bindable var appState: AppState
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    public init(appState: AppState) {
        self.appState = appState
    }

    private var selectedTab: SettingsTab {
        appState.navigation.settingsSelectedTab
    }

    public var body: some View {
        VStack(spacing: 0) {
            pinnedSectionHeader
            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.6))

            ScrollView {
                VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
                    Group {
                        switch selectedTab {
                        case .general:
                            PreferencesSettingsView(appState: appState)
                        case .devices:
                            HubDevicesSettingsView(appState: appState)
                        case .about:
                            AboutSettingsView(appState: appState)
                        }
                    }
                    .id(selectedTab)
                    .transition(.opacity)
                }
                .padding(.horizontal, SettingsLayout.horizontalGutter)
                .padding(.vertical, ArchiveSpacing.xl)
                .frame(maxWidth: ArchiveSheetWidth.form)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(ArchivePalette.archivePaper)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArchivePalette.archivePaper)
    }

    // MARK: - 统一设置中心顶栏与分段切换器
    private var pinnedSectionHeader: some View {
        HStack(spacing: ArchiveSpacing.m) {
            HStack(spacing: 4) {
                ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element.id) { index, tab in
                    PaperPillButton(
                        title: tab.rawValue,
                        icon: tab.iconName,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            appState.navigation.settingsSelectedTab = tab
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
                }
            }

            Spacer()

            let badge = appState.hubConnectionBadgeState
            HStack(spacing: ArchiveSpacing.s) {
                if differentiateWithoutColor {
                    Image(systemName: badge.symbolName)
                        .font(.system(size: 10))
                        .foregroundStyle(badge.dotColor)
                        .accessibilityHidden(true)
                } else {
                    Circle()
                        .fill(badge.dotColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(badge.label)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .lineLimit(1)
                Text("v\(UpdateChecker.shared.currentVersion)")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(badge.label)，版本 v\(UpdateChecker.shared.currentVersion)")
            .help(appState.isPaired ? "数据中枢节点: \(appState.hubURLString) (\(badge.label))" : "尚未配对生活数据中枢")
        }
        .padding(.horizontal, ArchiveSpacing.l)
        .frame(height: 52)
        .background(ArchivePalette.archivePaper)
    }
}

/// 配置中心外层布局常量（唯一留白来源）
public enum SettingsLayout {
    /// 设置面板左右留白：比 ArchiveSpacing.xl 更宽，形成杂志版心
    public static let horizontalGutter: CGFloat = 32
}

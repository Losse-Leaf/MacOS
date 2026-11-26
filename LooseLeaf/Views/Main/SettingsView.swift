import SwiftUI

/// 配置中心分类标签枚举
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general = "偏好设置"
    case devices = "账号与连接"
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
/// 2. 采用原生 `TabView` 由系统渲染标准 macOS 设置页签栏
/// 3. 本文件是唯一持有 `ScrollView` 与外层留白的容器，各子面板输出纯粹的 `VStack`
@MainActor
public struct SettingsView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        @Bindable var navigation = appState.navigation

        TabView(selection: $navigation.settingsSelectedTab) {
            settingsTabContainer {
                PreferencesSettingsView(appState: appState)
            }
            .tabItem {
                Label(SettingsTab.general.rawValue, systemImage: SettingsTab.general.iconName)
            }
            .tag(SettingsTab.general)

            settingsTabContainer {
                HubDevicesSettingsView(appState: appState)
            }
            .tabItem {
                Label(SettingsTab.devices.rawValue, systemImage: SettingsTab.devices.iconName)
            }
            .tag(SettingsTab.devices)

            settingsTabContainer {
                AboutSettingsView(appState: appState)
            }
            .tabItem {
                Label(SettingsTab.about.rawValue, systemImage: SettingsTab.about.iconName)
            }
            .tag(SettingsTab.about)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArchivePalette.archivePaper)
    }

    private func settingsTabContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
                content()
            }
            .padding(.horizontal, SettingsLayout.horizontalGutter)
            .padding(.vertical, ArchiveSpacing.xl)
            .frame(maxWidth: ArchiveSheetWidth.form)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArchivePalette.archivePaper)
    }
}

/// 配置中心外层布局常量（唯一留白来源）
public enum SettingsLayout {
    /// 设置面板左右留白：比 ArchiveSpacing.xl 更宽，形成杂志版心
    public static let horizontalGutter: CGFloat = 32
}

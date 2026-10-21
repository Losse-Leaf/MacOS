import SwiftUI

/// 配置中心分类标签枚举
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general = "偏好设置"
    case devices = "中枢与设备"
    case backup = "存储与备份"
    case categories = "分类字典"
    case about = "关于活页"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .general: return ArchiveIcon.preferences.systemName
        case .devices: return ArchiveIcon.hub.systemName
        case .backup: return ArchiveIcon.storage.systemName
        case .categories: return ArchiveIcon.categories.systemName
        case .about: return ArchiveIcon.about.systemName
        }
    }

    public var subtitle: String {
        switch self {
        case .general: return "纸墨外观与全局热键"
        case .devices: return "节点地址、受信任设备"
        case .backup: return "R2 云存与中枢快照"
        case .categories: return "收支类别与造物字典"
        case .about: return "版本状态与更新日志"
        }
    }
}

/// 活页集配置类导航外壳 (SettingsView)
/// 扁平化后 5 个配置条目已直接进入左侧菜单栏；本文件只负责页眉与 tab 分发，
/// 各 tab 的完整实现拆分在 `Views/Main/Settings/` 下：
/// PreferencesSettingsView / HubDevicesSettingsView / StorageBackupSettingsView /
/// CategoriesSettingsView / AboutSettingsView
///
/// 结构约定（避免多层嵌套滚动）：
/// 本文件是**唯一**持有 `ScrollView` 与外层留白的一层；
/// 各子视图只输出纯粹的 `VStack(alignment:.leading, spacing: ArchiveSpacing.l)`。
@MainActor
public struct SettingsView: View {
    @Bindable var appState: AppState

    /// 扁平化后由侧栏直接进入时锁定的 tab；nil 时退化为「偏好设置」
    /// 启动时钉住的标签页（仅用于初始化选中项，存下来后不再读取）

    @State private var selectedTab: SettingsTab = .general

    public init(appState: AppState, pinnedTab: SettingsTab? = nil) {
        self.appState = appState
        _selectedTab = State(initialValue: pinnedTab ?? .general)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 扁平化后：每个 tab 都是独立的侧栏目的地，只保留精简页眉
            pinnedSectionHeader
            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.6))

            // 居中黄金比例设置面板 (maxWidth 720pt centered, standard macOS HIG)
            ScrollView {
                VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
                    Group {
                        switch selectedTab {
                        case .general:
                            PreferencesSettingsView(appState: appState)
                        case .devices:
                            HubDevicesSettingsView(appState: appState)
                        case .backup:
                            StorageBackupSettingsView(appState: appState)
                        case .categories:
                            CategoriesSettingsView(appState: appState)
                        case .about:
                            AboutSettingsView(appState: appState)
                        }
                    }
                    .id(selectedTab)
                    .transition(.opacity)
                }
                // 外层留白统一在此处施加，子视图不再重复内边距
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

    // MARK: - 扁平化后的精简页眉（tab 已由侧栏承担，这里只做身份标识）
    private var pinnedSectionHeader: some View {
        HStack(spacing: ArchiveSpacing.s) {
            Image(systemName: selectedTab.iconName)
                .font(.system(size: ArchiveTypography.Scale.heading))
                .foregroundStyle(ArchivePalette.accentWarm)
                .accessibilityHidden(true)
            Text(selectedTab.rawValue)
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Spacer()

            HStack(spacing: ArchiveSpacing.s) {
                Circle()
                    .fill(appState.isPaired ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(appState.isPaired ? "中枢在线" : "未配对")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                Text("v\(UpdateChecker.shared.currentVersion)")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(appState.isPaired ? "中枢在线" : "未配对")
            .help(appState.isPaired ? "数据中枢已连接: \(appState.hubURLString)" : "尚未配对生活数据中枢")
        }
        .padding(.horizontal, ArchiveSpacing.l)
        .frame(height: 46)
        .background(ArchivePalette.archivePaper)
    }
}

/// 配置中心外层布局常量（唯一留白来源）
public enum SettingsLayout {
    /// 设置面板左右留白：比 ArchiveSpacing.xl 更宽，形成杂志版心
    public static let horizontalGutter: CGFloat = 32
}

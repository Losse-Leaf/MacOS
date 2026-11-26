import SwiftUI
import Observation

/// 瞬时提示状态 (Transient Banners)
///
/// **为什么要拆出来**：`AppState` 原本有 50+ 个可观察属性，其中「顶部提示条」
/// 这类**瞬时、高频写入**的属性与「档案数据」混在一起。
/// 每次写提示条都会唤醒所有观察 `AppState` 的视图 —— 包括侧栏与长列表。
/// 拆成独立对象后，只有真正读取 `banners` 的视图会被唤醒。
@Observable
@MainActor
public final class AppBanners {
    /// 操作成功 / 中性提示（如「已归入散页时间流」）
    public var status: String?
    /// 错误提示（优先级最高）
    public var error: String?
    /// 本地数据完整性告警（快照损坏等，需要用户手动关闭）
    public var localWarning: String?

    public init() {}

    /// 清空全部提示
    public func clearAll() {
        status = nil
        error = nil
        localWarning = nil
    }
}

/// 时间流私密筛选维度
public enum StreamPrivacyFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case privateOnly = "private_only"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "全部"
        case .privateOnly: return "仅私密"
        }
    }
}

/// 导航与检索状态 (Navigation & Search)
///
/// 与档案数据分离：切换板块、输入搜索词这类交互不会再让数据视图无谓重算。
@Observable
@MainActor
public final class AppNavigation {
    /// 侧栏完整导航树当前选中的目标节点
    public var sidebarDestination: SidebarDestination = .allEntries
    /// 当前侧栏板块
    public var activeSection: WorkbenchSection = .stream
    /// 记账板块内当前子页签（流水 | 心愿单）
    public var ledgerSubTab: LedgerSubTab = .ledger
    /// 当前分类视角
    public var selectedCategory: ArchiveCategory = .all
    /// 时间流私密态筛选
    public var streamPrivacyFilter: StreamPrivacyFilter = .all
    /// 时间流本地搜索词
    public var searchQuery: String = ""
    /// 时间流离屏切换时保存的滚动锚点条目 ID
    public var streamScrollEntryId: Int? = nil
    /// ⌘F 请求聚焦工具栏搜索框（自增 token 驱动 onChange）
    public var searchFocusRequest: Int = 0
    /// ⌘N / 工具栏「+」在收支流水下的新建请求令牌
    public var newTransactionRequestToken: Int = 0
    /// ⌘N / 工具栏「+」在心愿清单下的新建请求令牌
    public var newWishRequestToken: Int = 0
    /// ⌘E 请求切换右侧散页进入原地编辑态
    public var editCurrentEntryRequestToken: Int = 0
    /// 独立设置窗口当前激活标签页（支持 ⌘, 与 ⌥⌘1–3 联动）
    public var settingsSelectedTab: SettingsTab = .general
    /// 编程式唤起独立设置窗口的自增请求计数
    public var settingsOpenToken: Int = 0
    /// 全局检索 (⌘K) 精准跳转定位目标
    public var highlightedWishId: Int?

    public init() {}

    /// 请求聚焦工具栏搜索框（适用于当前所在板块）
    public func requestStreamSearchFocus() {
        searchFocusRequest += 1
    }

    /// 切换侧栏导航目标并同步派生状态
    public func selectDestination(_ destination: SidebarDestination) {
        sidebarDestination = destination
        switch destination {
        case .allEntries:
            activeSection = .stream
            selectedCategory = .all
            streamPrivacyFilter = .all
        case .daily:
            activeSection = .stream
            selectedCategory = .daily
            streamPrivacyFilter = .all
        case .privateEntries:
            activeSection = .stream
            selectedCategory = .all
            streamPrivacyFilter = .privateOnly
        case .onThisDay:
            activeSection = .stream
            selectedCategory = .all
            streamPrivacyFilter = .all
        case .category(let cat):
            activeSection = .stream
            selectedCategory = ArchiveCategory(rawValue: cat.rawValue) ?? .all
            streamPrivacyFilter = .all
        case .ledger:
            activeSection = .ledger
            ledgerSubTab = .ledger
        case .wishlist:
            activeSection = .ledger
            ledgerSubTab = .wishlist
        }
    }

    /// 从旧式 `activeSection` / `ledgerSubTab` 变更反向同步 `sidebarDestination`
    public func syncDestinationFromLegacyState() {
        switch activeSection {
        case .ledger:
            let target: SidebarDestination = (ledgerSubTab == .wishlist) ? .wishlist : .ledger
            if sidebarDestination != target {
                sidebarDestination = target
            }
        case .stream, .preferences, .hub, .about:
            if !sidebarDestination.isStreamDestination {
                sidebarDestination = .allEntries
            }
        }
    }
}

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

/// 导航与检索状态 (Navigation & Search)
///
/// 与档案数据分离：切换板块、输入搜索词这类交互不会再让数据视图无谓重算。
@Observable
@MainActor
public final class AppNavigation {
    /// 当前侧栏板块
    public var activeSection: WorkbenchSection = .stream
    /// 当前分类视角
    public var selectedCategory: ArchiveCategory = .all
    /// 时间流本地搜索词
    public var searchQuery: String = ""
    /// ⌘F 请求聚焦搜索框（自增 token 驱动 onChange）
    public var searchFocusRequest: Int = 0
    /// 新建散页时的初始形态（如从「造物」入口打开）
    public var newEntryInitialKind: String?
    public var newEntryInitialProjectId: Int?
    public var newEntryInitialCityCode: String?
    public var newEntryInitialCityName: String?

    public init() {}

    /// 请求时间流搜索框聚焦
    public func requestStreamSearchFocus() {
        activeSection = .stream
        searchFocusRequest += 1
    }
}

// EntryDraft.swift
// 创作模态表单草稿容器 (@Observable)
// 职责：承载「记一笔」模态的全部表单字段，供父 View 与五个表单子 View 共享同一份数据源。

import Foundation
import Observation

/// 创作模态草稿容器 (@Observable)
///
/// **为什么不再用 40+ 个平铺的 @State**：
/// 原先 `NewEntryModal` 一个 struct 里平铺了 40+ 个 `@State`，任何一处输入变化
/// （标题、正文、金额……）都会让**整个 body 重新求值**；而 body 里又挂着五个表单分支，
/// 每个分支还带着重量级的 `PaperDatePicker` / `PaperCityPicker` / `PaperSelect`，
/// 于是「敲一个字」就要重算整棵视图树 —— 这正是「点击修改卡片或者创建内容很卡」的根因。
///
/// 改为「父持有草稿对象 + 各表单子 View 只订阅自己读到的字段」之后：
/// - 输入标题只会重绘真正读取了 `title` 的那个子 View，父 body 与其它分支完全不受影响；
/// - 五个分支各自是独立子 View，只有当前选中的分支存在于视图树中；
/// - 父子之间共享的是**同一个对象引用**，不需要任何回调收集，也不存在状态同步 BUG。
@Observable
@MainActor
final class EntryDraft {

    // MARK: - 通用字段

    var title: String = ""

    /// 实际落库的标题
    ///
    /// 朋友圈式发布：日常/随笔**不再单列标题输入框**，只写正文；
    /// 标题由正文第一行自动派生（`FormatUtils.derivedTitle`）。
    /// 显式填了标题就以标题为准（游历/心愿等形态仍用得到）。
    var effectiveTitle: String {
        let explicit = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        return FormatUtils.derivedTitle(from: content)
    }
    var content: String = ""
    var occurredAt: Date = Date()
    var cityCode: String = ""
    var cityName: String = ""
    var isFeatured: Bool = false

    // MARK: - 游历专有

    var selectedFootprintId: Int?
    var departedAt: Date = Date()

    // MARK: - 造物专有

    var projectMode: String = "entry" // "new" 或 "entry"
    var selectedProjectId: Int?
    var newProjectTitle: String = ""
    var newProjectSubtitle: String = ""
    var newProjectCategory: String = "开源项目"
    var newProjectStatus: String = "Active"
    var newProjectGithub: String = ""
    var newProjectDesc: String = ""
    var newProjectStory: String = ""

    // MARK: - 心愿专有

    var wishKind: String = "item" // item, travel, milestone
    var wishBudgetYuan: String = ""
    var wishSpec: String = ""
    var wishCityCode: String = ""
    var wishCityName: String = ""
    var wishTargetDate: Date = Date()

    // MARK: - 账目专有

    var txType: String = "expense" // expense, income
    var txAmountYuan: String = ""
    var txCategory: String = "餐饮"
    var txPaymentMethod: String = "微信支付"
    var selectedWishId: Int?
    var isInstallment: Bool = false
    var installmentChannel: String = "huabei"
    var installmentMonths: Int = 12
    var customRepaymentDay: Int = 10
    var syncToGear: Bool = false
    var gearCategory: String = "数码器材"
    var gearSpec: String = ""
}

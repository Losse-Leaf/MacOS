// EntryDraft.swift
// 创作模态表单草稿容器 (@Observable)
// 职责：承载「记一笔」模态的散页表单字段，供父 View 与表单子 View 共享同一份数据源。

import Foundation
import Observation

/// 创作模态草稿容器 (@Observable)
///
/// 独立持有草稿对象，让输入变化只触发读取对应字段的表单子视图重绘，
/// 避免每次敲击键盘引起整个创作模态外壳重算。
@Observable
@MainActor
final class EntryDraft {

    // MARK: - 通用字段

    var category: EntryCategory = .daily
    var title: String = ""

    /// 实际落库的标题
    ///
    /// 朋友圈式发布：日常散页不再单列标题输入框，只写正文；
    /// 标题由正文第一行自动派生（`FormatUtils.derivedTitle`）。
    /// 若显式填了标题则以显式标题为准。
    var effectiveTitle: String {
        let explicit = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        return FormatUtils.derivedTitle(from: content)
    }
    var content: String = ""
    var occurredAt: Date = Date()
    var location: String = ""
    var userEditedTime: Bool = false
    var userEditedLocation: Bool = false
    var isPrivate: Bool = false
}

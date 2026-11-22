import Foundation

/// 键盘快捷键速查表（唯一事实源：偏好设置页与帮助面板共用）
public struct ArchiveShortcutItem: Identifiable, Sendable {
    public let title: String
    public let combination: String

    public var id: String { combination + title }

    public init(title: String, combination: String) {
        self.title = title
        self.combination = combination
    }
}

public enum ArchiveShortcutReference {
    /// 全应用常用快捷键
    @MainActor
    public static var all: [ArchiveShortcutItem] {
        [
            ArchiveShortcutItem(title: "记一笔（新建散页）", combination: "⌘N"),
            ArchiveShortcutItem(title: "全局档案检索", combination: "⌘K"),
            ArchiveShortcutItem(title: "时间流搜索框聚焦", combination: "⌘F"),
            ArchiveShortcutItem(title: "全量同步中枢档案", combination: "⌘R"),
            ArchiveShortcutItem(title: "撤销最近一次删除操作", combination: "⌘Z"),
            ArchiveShortcutItem(title: "呼出极速手账悬浮窗", combination: AppDelegate.hotKeyDisplayName),
            ArchiveShortcutItem(title: "切换散页与记账板块", combination: "⌘1 – ⌘2"),
            ArchiveShortcutItem(title: "切换设置窗口分页", combination: "⌥⌘1 – ⌥⌘3"),
            ArchiveShortcutItem(title: "键盘流上下浏览", combination: "⌘↑ / ⌘↓"),
            ArchiveShortcutItem(title: "打开选中的散页", combination: "⌘↩"),
            ArchiveShortcutItem(title: "关闭当前弹层或窗口", combination: "⌘W"),
            ArchiveShortcutItem(title: "打开偏好设置窗口", combination: "⌘,"),
            ArchiveShortcutItem(title: "查看快捷键速查", combination: "⌘/")
        ]
    }
}

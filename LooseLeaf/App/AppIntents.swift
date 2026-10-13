import AppIntents
import Foundation

/// 快捷指令 / Siri 集成：「记一条闪念」「极速记一笔」。
/// Intent 在主应用进程内执行，复用本机设备凭据与离线发件箱逻辑，无需额外扩展目标。
struct AddQuickNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "记一条闪念"
    static var description = IntentDescription("把一句话极速归档到《散页》时间流。")

    @Parameter(title: "内容")
    var text: String

    @Parameter(title: "地点")
    var location: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let req = CreateEntryRequest(
            content: text,
            location: (trimmedLocation?.isEmpty == true) ? nil : trimmedLocation
        )
        _ = try await SyncManager.shared.submitEntry(req)
        return .result(dialog: "已归入《散页》时间流。")
    }
}

/// 「42.5 午餐咖啡」自然语言极速记账
struct QuickLedgerIntent: AppIntent {
    static var title: LocalizedStringResource = "极速记一笔"
    static var description = IntentDescription("用一句话记账，例如：42.5 午餐咖啡。")

    @Parameter(title: "记账指令")
    var phrase: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let parsed = FormatUtils.parseQuickLedgerInput(phrase) else {
            return .result(dialog: "未能识别金额，请例如说：42.5 午餐咖啡。")
        }
        let appState = await AppState.shared
        _ = try await appState.submitQuickLedger(
            amountCents: parsed.amountCents,
            type: parsed.type,
            category: parsed.category,
            title: parsed.title
        )
        return .result(dialog: "已记入账本：\(FormatUtils.formattedYuan(cents: parsed.amountCents, includeSymbol: true)) · \(parsed.category)")
    }
}

/// 系统快捷指令与 Siri 短语注册
struct LooseLeafAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddQuickNoteIntent(),
            phrases: [
                "用 \(.applicationName) 记一条闪念",
                "用 \(.applicationName) 记一条手稿"
            ],
            shortTitle: "记闪念",
            systemImageName: "book.pages"
        )
        AppShortcut(
            intent: QuickLedgerIntent(),
            phrases: [
                "用 \(.applicationName) 记一笔",
                "用 \(.applicationName) 极速记账"
            ],
            shortTitle: "极速记账",
            systemImageName: "chart.bar.doc.horizontal"
        )
    }
}

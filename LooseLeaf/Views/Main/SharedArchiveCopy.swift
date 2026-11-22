import SwiftUI

// MARK: - 共享文案常量 (Shared Copy)

/// 全应用复用的确认文案与选项常量。
/// 保证同一语义在任何入口都给出完全一致的措辞。
enum ArchiveSharedCopy {
    // 删除生活手稿
    static let entryDeleteTitle = "确认删除该条生活手稿？"
    static let entryDeleteMessage = "删除后记录将从时间流中移除，关联的附件将一并清理。"
    static let entryDeleteConfirmText = "删除手稿"

    // 删除流水账目
    static let transactionDeleteTitle = "确认删除该笔流水账目？"
    static let transactionDeleteMessage = "删除后将从本地账本与中枢中移除，月度收支将即刻重新核算。"
    static let transactionDeleteConfirmText = "删除账目"
}

/// 分期付款期数选项（全应用唯一真源，避免各处散落的魔法数组）
enum ArchiveInstallmentOptions {
    /// 可选分期期数（月）
    static let installmentOptions = [3, 6, 12, 24]
}

// MARK: - 横向滚动渐隐遮罩 (Horizontal Fade Mask)

public extension View {
    /// 横向滚动容器首尾渐隐遮罩。
    /// 横向 `ScrollView` 隐藏指示器后，用户无法感知右侧仍有内容，
    /// 此处以渐变遮罩暗示「可继续横向滚动」。
    /// - Parameters:
    ///   - edgeFade: 首尾渐隐所占比例（0.01 ~ 0.1）
    func horizontalFadeMask(edgeFade: CGFloat = 0.03) -> some View {
        mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: edgeFade),
                    .init(color: .black, location: 1 - edgeFade),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

// MARK: - 预览假数据 (Preview Fixtures)

#if DEBUG
/// SwiftUI 预览用的假数据装配器。
/// 仅在 `#Preview` 中调用：为 AppState 注入结构完整的示例数据，
/// 便于离线检视各主视图的排版、空态与加载态。
@MainActor
enum ArchivePreviewFixtures {
    /// 心愿假数据
    static func wishes() -> [Wish] {
        [
            Wish(
                id: 9101,
                title: "徕卡 M6 旁轴机身",
                kind: "item",
                note: "胶片时代的取景器手感，值得为它留一台。",
                spec: "旁轴 · 35mm 定焦",
                budget: 1680000,
                actualCost: 0,
                status: "wanting",
                attachments: []
            ),
            Wish(
                id: 9102,
                title: "骑行环青海湖",
                kind: "travel",
                note: "四天三夜，晒黑也值得。",
                spec: "环湖东路 · 约 360 公里",
                budget: 480000,
                actualCost: 0,
                status: "wanting",
                attachments: []
            ),
            Wish(
                id: 9103,
                title: "完成第一台胶片相机 DIY",
                kind: "milestone",
                note: "从零件到成片，完整走通一次。",
                spec: "拆机 · 改快门 · 自制外壳",
                budget: 120000,
                actualCost: 98000,
                status: "fulfilled",
                attachments: []
            )
        ]
    }

    /// 账目流水假数据
    static func transactions() -> [Transaction] {
        let month = FormatUtils.beijingCurrentYearMonth()
        let prefix = String(format: "%04d-%02d", month.year, month.month)
        return [
            Transaction(
                id: 9301,
                amount: 4250,
                type: "expense",
                category: "餐饮",
                title: "手冲咖啡豆",
                note: "耶加雪菲",
                paymentMethod: "微信支付",
                wishId: nil,
                occurredAt: "\(prefix)-12T08:12:00Z",
                isInstallment: nil,
                installmentChannelCode: nil,
                installmentTotalAmount: nil,
                installmentMonths: nil,
                installmentMonthlyPay: nil,
                installmentRemainMonths: nil,
                repaymentDay: nil,
                deletedAt: nil,
                createdAt: nil,
                updatedAt: nil,
                syncStatus: "synced"
            ),
            Transaction(
                id: 9302,
                amount: 128900,
                type: "expense",
                category: "数码器材",
                title: "胶片卷与药水",
                note: "显影套装",
                paymentMethod: "支付宝",
                wishId: nil,
                occurredAt: "\(prefix)-06T19:40:00Z",
                isInstallment: true,
                installmentChannelCode: "huabei",
                installmentTotalAmount: 128900,
                installmentMonths: 6,
                installmentMonthlyPay: 21483,
                installmentRemainMonths: 4,
                repaymentDay: 10,
                deletedAt: nil,
                createdAt: nil,
                updatedAt: nil,
                syncStatus: "synced"
            ),
            Transaction(
                id: 9303,
                amount: 1680000,
                type: "income",
                category: "工资收入",
                title: "月度薪酬",
                note: nil,
                paymentMethod: "银行卡",
                wishId: nil,
                occurredAt: "\(prefix)-01T10:00:00Z",
                isInstallment: nil,
                installmentChannelCode: nil,
                installmentTotalAmount: nil,
                installmentMonths: nil,
                installmentMonthlyPay: nil,
                installmentRemainMonths: nil,
                repaymentDay: nil,
                deletedAt: nil,
                createdAt: nil,
                updatedAt: nil,
                syncStatus: "synced"
            )
        ]
    }

    /// 手记假数据
    static func entries() -> [LifeEntry] {
        [
            LifeEntry(
                id: 9401,
                type: "life",
                title: "雨天的旧书店",
                content: "在巷子尽头翻到一本 1998 年的诗集，扉页上有人写：「愿你始终有处可回」。",
                occurredAt: "2025-04-06T20:15:00Z",
                location: "杭州",
                wishId: nil,
                wish: nil,
                attachments: [],
                deletedAt: nil,
                createdAt: nil,
                updatedAt: nil,
                syncStatus: "synced"
            ),
            LifeEntry(
                id: 9402,
                type: "life",
                title: "胡同口的槐树",
                content: "五月里槐花落满肩头，房东说这棵树比院子还老。",
                occurredAt: "2025-03-22T17:05:00Z",
                location: "北京",
                wishId: nil,
                wish: nil,
                attachments: [],
                deletedAt: nil,
                createdAt: nil,
                updatedAt: nil,
                syncStatus: "synced"
            )
        ]
    }

    /// 装配一份带假数据的 AppState（供 #Preview 使用）
    static func makeAppState() -> AppState {
        let state = AppState.shared
        state.wishes = wishes()
        state.transactions = transactions()
        state.entries = entries()
        state.transactionSummary = TransactionSummary(
            year: FormatUtils.beijingCurrentYearMonth().year,
            month: FormatUtils.beijingCurrentYearMonth().month,
            totalExpense: 133150,
            totalIncome: 1680000,
            balance: 1546850,
            categoryBreakdown: ["餐饮": 4250, "数码器材": 128900]
        )
        var profile = CuratorProfile()
        profile.name = "沈砚"
        profile.title = "主理人 · 记录爱好者"
        profile.bio = "在代码与胶片之间往返，记录生活片段与日常开销。"
        profile.location = "杭州"
        profile.currentCity = "杭州"
        profile.motto = "把日子过成可检索的档案。"
        profile.manifesto = "每一笔花销都有归处，每一页片段都值得留存。"
        state.profile = profile
        return state
    }
}
#endif

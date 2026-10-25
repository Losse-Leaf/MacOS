import SwiftUI

// MARK: - 共享文案常量 (Shared Copy)

/// 全应用复用的确认文案与选项常量。
/// 消除 LedgerAssetsView 与 CuratorDossierView 之间逐字重复的删除确认文案，
/// 保证同一语义在任何入口都给出完全一致的措辞。
enum ArchiveSharedCopy {
    // 删除随身器材资产
    static let gearDeleteTitle = "确认删除该件随身器材资产？"
    static let gearDeleteMessage = "删除后该项设备将从固资货架中移除。"
    static let gearDeleteConfirmText = "删除器材"

    // 删除生活手稿
    //
    // 关键：这里曾是**唯一真源**，而时间流卡片与详情页各自硬编码了一份 ——
    // 文案一旦要改就会漏改一处，用户在两个界面看到不同的说法。
    static let entryDeleteTitle = "确认删除该条生活手稿？"
    static let entryDeleteMessage = "删除后记录将从时间流中移除，关联的附件与下渗足迹将一并清理。"
    static let entryDeleteConfirmText = "删除手稿"

    // 删除流水账目
    static let transactionDeleteTitle = "确认删除该笔流水账目？"
    static let transactionDeleteMessage = "删除后将从本地账本与中枢中移除，月度收支与资产大盘将即刻重新核算。"
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

/// SwiftUI 预览用的假数据装配器。
/// 仅在 `#Preview` 中调用：为 AppState 注入结构完整的示例数据，
/// 便于离线检视各主视图的排版、空态与加载态。
@MainActor
enum ArchivePreviewFixtures {
    /// 造物项目假数据
    static func projects() -> [Project] {
        [
            Project(
                id: 9001,
                title: "活页 · 桌面端重构",
                subtitle: "SwiftUI 多端一致性改造",
                description: "以统一的设计令牌重写桌面端六大主视图，梳理懒加载与无障碍细节。",
                story: nil,
                category: "开源项目",
                githubUrl: "https://github.com/example/looseleaf",
                status: ProjectStatus.inProgress.rawValue,
                order: 1,
                createdAt: nil,
                updatedAt: nil
            ),
            Project(
                id: 9002,
                title: "手冲咖啡工坊",
                subtitle: "周末器具与参数笔记",
                description: "记录从磨豆到注水的完整参数曲线与器具迭代。",
                story: nil,
                category: "设计作品",
                githubUrl: nil,
                status: ProjectStatus.maintaining.rawValue,
                order: 2,
                createdAt: nil,
                updatedAt: nil
            ),
            Project(
                id: 9003,
                title: "旧版个人主页",
                subtitle: "已归档的静态站点",
                description: "2019 年建成的静态博客，已停止维护并归档。",
                story: nil,
                category: "写作出版",
                githubUrl: nil,
                status: ProjectStatus.shelved.rawValue,
                order: 3,
                createdAt: nil,
                updatedAt: nil
            )
        ]
    }

    /// 心愿假数据
    static func wishes() -> [Wish] {
        [
            Wish(
                id: 9101,
                title: "徕卡 M6 旁轴机身",
                kind: "item",
                note: "胶片时代的取景器手感，值得为它留一台。",
                spec: "旁轴 · 35mm 定焦",
                cityCode: nil,
                cityName: nil,
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
                cityCode: "630100",
                cityName: "西宁市",
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
                cityCode: nil,
                cityName: nil,
                budget: 120000,
                actualCost: 98000,
                status: "fulfilled",
                attachments: []
            )
        ]
    }

    /// 行迹票根假数据
    static func footprints() -> [Footprint] {
        [
            Footprint(
                id: 9201,
                cityCode: "330100",
                cityName: "杭州市",
                title: "西湖边的雨",
                visitedAt: "2025-04-06T09:00:00Z",
                departedAt: nil,
                note: "断桥的雨丝落在青石板上，像一场没有预约的演奏。",
                lifeEntryId: nil,
                wishId: nil,
                attachments: [],
                entriesCount: 3,
                totalSpent: 42600,
                transactionCount: 5,
                createdAt: nil,
                updatedAt: nil
            ),
            Footprint(
                id: 9202,
                cityCode: "110100",
                cityName: "北京市",
                title: "胡同与槐树",
                visitedAt: "2025-03-22T14:30:00Z",
                departedAt: nil,
                note: "槐花落了一地，没人扫。",
                lifeEntryId: nil,
                wishId: nil,
                attachments: [],
                entriesCount: 2,
                totalSpent: 18800,
                transactionCount: 2,
                createdAt: nil,
                updatedAt: nil
            ),
            Footprint(
                id: 9203,
                cityCode: "320100",
                cityName: "南京市",
                title: "城墙上的黄昏",
                visitedAt: "2024-11-18T16:00:00Z",
                departedAt: nil,
                note: "砖缝里长出的草，比城墙更古老。",
                lifeEntryId: nil,
                wishId: nil,
                attachments: [],
                entriesCount: 1,
                totalSpent: 9600,
                transactionCount: 1,
                createdAt: nil,
                updatedAt: nil
            )
        ]
    }

    /// 随身器物假数据
    static func gear() -> [GearItem] {
        [
            GearItem(
                id: "gear-preview-1",
                name: "理光 GR1v",
                spec: "28mm f/2.8 · 银色",
                category: "影像与暗房",
                status: "active",
                priceCents: 468000,
                purchaseDate: "2025-01-12",
                soldPriceCents: nil,
                soldDate: nil,
                note: "口袋里的城市观察器"
            ),
            GearItem(
                id: "gear-preview-2",
                name: "小蜜蜂手冲壶",
                spec: "600ml · 细口",
                category: "手冲咖啡工坊",
                status: "active",
                priceCents: 32800,
                purchaseDate: "2024-12-02",
                soldPriceCents: nil,
                soldDate: nil,
                note: nil
            ),
            GearItem(
                id: "gear-preview-3",
                name: "ThinkPad X1 Carbon",
                spec: "i7 · 32G · 1T",
                category: "工作台与算力",
                status: "sold",
                priceCents: 899900,
                purchaseDate: "2022-08-20",
                soldPriceCents: 420000,
                soldDate: "2024-05-18",
                note: "已转售回血"
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
                footprintId: nil,
                cityCode: "330100",
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
                footprintId: nil,
                cityCode: nil,
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
                footprintId: nil,
                cityCode: nil,
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
                cityCode: "330100",
                cityName: "杭州市",
                projectId: 9001,
                project: nil,
                wishId: nil,
                wish: nil,
                footprintId: 9201,
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
                cityCode: "110100",
                cityName: "北京市",
                projectId: 9002,
                project: nil,
                wishId: nil,
                wish: nil,
                footprintId: 9202,
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
        state.projects = projects()
        state.wishes = wishes()
        state.footprints = footprints()
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
        state.assetsOverview = AssetsOverview(
            netWorth: 2476800,
            liquidBalance: 1546850,
            initialLiquidBalance: 1200000,
            fixedAssets: 468000,
            totalLiabilities: 85966,
            monthlyLiabilities: 21483,
            gearSummary: GearSummary(
                totalCount: 3,
                activeCount: 2,
                activeValue: 500800,
                soldCount: 1,
                soldRecoveredValue: 420000,
                items: gear()
            ),
            channelLiabilities: nil
        )
        var profile = CuratorProfile()
        profile.name = "沈砚"
        profile.title = "主理人 · 器物与记录爱好者"
        profile.bio = "在代码与胶片之间往返，记录造物、行旅与日常开销。"
        profile.location = "杭州"
        profile.currentCity = "杭州"
        profile.motto = "把日子过成可检索的档案。"
        profile.manifesto = "每一笔花销都有归处，每一次远行都留有票根。"
        profile.edcGear = gear()
        state.profile = profile
        return state
    }
}

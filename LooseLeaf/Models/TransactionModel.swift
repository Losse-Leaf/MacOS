import Foundation

/// 独立记账记录 (Transaction)
/// 核心铁律：所有金额字段一律采用 Int64 (单位：分)，严禁使用浮点数
public struct Transaction: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var amount: Int64 // 单位：分 (如 4250 表示 42.50 元)
    public var type: String  // "expense" | "income"
    public var category: String
    public var title: String
    public var note: String?
    public var paymentMethod: String?
    public var wishId: Int?
    public var footprintId: Int?
    public var cityCode: String?
    public var occurredAt: String

    // 分期付款核心字段 (RC-53)
    public var isInstallment: Bool?
    public var installmentChannelCode: String?
    public var installmentTotalAmount: Int64?
    public var installmentMonths: Int?
    public var installmentMonthlyPay: Int64?
    public var installmentRemainMonths: Int?
    public var repaymentDay: Int?

    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    /// 客户端本地同步状态标记 ("synced", "pending_create", "pending_delete")
    public var syncStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case amount
        case type
        case category
        case title
        case note
        case paymentMethod = "payment_method"
        case wishId = "wish_id"
        case footprintId = "footprint_id"
        case cityCode = "city_code"
        case occurredAt = "occurred_at"
        case isInstallment = "is_installment"
        case installmentChannelCode = "installment_channel_code"
        case installmentTotalAmount = "installment_total_amount"
        case installmentMonths = "installment_months"
        case installmentMonthlyPay = "installment_monthly_pay"
        case installmentRemainMonths = "installment_remain_months"
        case repaymentDay = "repayment_day"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncStatus = "sync_status"
    }

    public init(
        id: Int,
        amount: Int64,
        type: String = "expense",
        category: String,
        title: String,
        note: String? = nil,
        paymentMethod: String? = nil,
        wishId: Int? = nil,
        footprintId: Int? = nil,
        cityCode: String? = nil,
        occurredAt: String = FormatUtils.beijingISOString(),
        isInstallment: Bool? = false,
        installmentChannelCode: String? = nil,
        installmentTotalAmount: Int64? = nil,
        installmentMonths: Int? = nil,
        installmentMonthlyPay: Int64? = nil,
        installmentRemainMonths: Int? = nil,
        repaymentDay: Int? = nil,
        deletedAt: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        syncStatus: String? = "synced"
    ) {
        self.id = id
        self.amount = amount
        self.type = type
        self.category = category
        self.title = title
        self.note = note
        self.paymentMethod = paymentMethod
        self.wishId = wishId
        self.footprintId = footprintId
        self.cityCode = cityCode
        self.occurredAt = occurredAt
        self.isInstallment = isInstallment
        self.installmentChannelCode = installmentChannelCode
        self.installmentTotalAmount = installmentTotalAmount
        self.installmentMonths = installmentMonths
        self.installmentMonthlyPay = installmentMonthlyPay
        self.installmentRemainMonths = installmentRemainMonths
        self.repaymentDay = repaymentDay
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStatus = syncStatus
    }

    /// 容错解码：单条脏数据不应让整个账目列表解码失败（与 LifeEntry 策略一致）
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        amount = (try? c.decode(Int64.self, forKey: .amount)) ?? 0
        type = (try? c.decode(String.self, forKey: .type)) ?? "expense"
        category = (try? c.decode(String.self, forKey: .category)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        paymentMethod = try? c.decodeIfPresent(String.self, forKey: .paymentMethod)
        wishId = try? c.decodeIfPresent(Int.self, forKey: .wishId)
        footprintId = try? c.decodeIfPresent(Int.self, forKey: .footprintId)
        cityCode = try? c.decodeIfPresent(String.self, forKey: .cityCode)
        occurredAt = (try? c.decode(String.self, forKey: .occurredAt)) ?? ""
        isInstallment = try? c.decodeIfPresent(Bool.self, forKey: .isInstallment)
        installmentChannelCode = try? c.decodeIfPresent(String.self, forKey: .installmentChannelCode)
        installmentTotalAmount = try? c.decodeIfPresent(Int64.self, forKey: .installmentTotalAmount)
        installmentMonths = try? c.decodeIfPresent(Int.self, forKey: .installmentMonths)
        installmentMonthlyPay = try? c.decodeIfPresent(Int64.self, forKey: .installmentMonthlyPay)
        installmentRemainMonths = try? c.decodeIfPresent(Int.self, forKey: .installmentRemainMonths)
        repaymentDay = try? c.decodeIfPresent(Int.self, forKey: .repaymentDay)
        deletedAt = try? c.decodeIfPresent(String.self, forKey: .deletedAt)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
        syncStatus = (try? c.decodeIfPresent(String.self, forKey: .syncStatus)) ?? "synced"
    }

    /// 格式化展示金额 (元)
    public var formattedAmount: String {
        FormatUtils.formattedYuan(cents: amount, includeSymbol: true)
    }

    /// 北京时间派生日期结构
    public var parsedDate: FormatUtils.ParsedBeijingDate {
        FormatUtils.parseOccurredDate(occurredAt)
    }

    /// 转换为时间流伴生视图条目 (与 Web 端 txToEntry 逻辑一致)
    public func toLifeEntry() -> LifeEntry {
        let sign = type == "income" ? "+" : "-"
        let summaryText = "\(sign)\(FormatUtils.formattedYuan(cents: amount, includeSymbol: true)) · \(category)" +
            ((paymentMethod?.isEmpty == false) ? " · \(paymentMethod!)" : "") +
            ((note?.isEmpty == false) ? "\n\(note!)" : "")
        return LifeEntry(
            id: -abs(id) - 1_000_000,
            type: "transaction",
            title: title.isEmpty ? category : title,
            content: summaryText,
            occurredAt: occurredAt,
            location: nil,
            cityCode: cityCode,
            syncStatus: syncStatus
        )
    }
}

/// 月度记账统计与支出类目光谱 (GET /api/v1/transactions/summary)
public struct TransactionSummary: Codable, Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var totalExpense: Int64
    public var totalIncome: Int64
    public var balance: Int64
    public var categoryBreakdown: [String: Int64]
    public var count: Int

    enum CodingKeys: String, CodingKey {
        case year
        case month
        case totalExpense = "total_expense"
        case totalIncome = "total_income"
        case balance
        case categoryBreakdown = "category_breakdown"
        case count
    }

    public init(
        year: Int = FormatUtils.beijingCurrentYearMonth().year,
        month: Int = FormatUtils.beijingCurrentYearMonth().month,
        totalExpense: Int64 = 0,
        totalIncome: Int64 = 0,
        balance: Int64 = 0,
        categoryBreakdown: [String: Int64] = [:],
        count: Int = 0
    ) {
        self.year = year
        self.month = month
        self.totalExpense = totalExpense
        self.totalIncome = totalIncome
        self.balance = balance
        self.categoryBreakdown = categoryBreakdown
        self.count = count
    }

    /// 按支出金额降序排列的类目光谱项
    public var sortedSpectrum: [(category: String, cents: Int64, ratio: Double)] {
        guard totalExpense > 0 else { return [] }
        return categoryBreakdown
            .sorted { $0.value > $1.value }
            .map { (key, val) in
                (category: key, cents: val, ratio: Double(val) / Double(totalExpense))
            }
    }
}

/// 创建或更新记账请求载荷 (POST / PUT /api/v1/transactions)
public struct CreateTransactionRequest: Codable, Equatable, Sendable {
    public var amount: Int64
    public var type: String
    public var category: String
    public var title: String
    public var note: String?
    public var paymentMethod: String?
    public var wishId: Int?
    public var footprintId: Int?
    public var cityCode: String?
    public var occurredAt: String
    /// 是否为分期账目
    ///
    /// 关键：必须是**可选**。
    /// 非可选 `Bool` 会被 JSONEncoder 必定写进请求体（`"is_installment": false`），
    /// 而后端的新契约是「nil = 本次未携带 → 保持原值」——
    /// 非可选让这个契约在 mac 侧**根本无法表达**，
    /// 于是「撤销删除 / 重传 / 重试」重建账目时都会丢分期信息。
    public var isInstallment: Bool?
    public var installmentChannelCode: String?
    public var installmentTotalAmount: Int64?
    public var installmentMonths: Int?
    public var installmentMonthlyPay: Int64?
    public var installmentRemainMonths: Int?
    public var repaymentDay: Int?
    public var linkGearAsset: Bool
    public var gearCategory: String?
    public var gearSpec: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case type
        case category
        case title
        case note
        case paymentMethod = "payment_method"
        case wishId = "wish_id"
        case footprintId = "footprint_id"
        case cityCode = "city_code"
        case occurredAt = "occurred_at"
        case isInstallment = "is_installment"
        case installmentChannelCode = "installment_channel_code"
        case installmentTotalAmount = "installment_total_amount"
        case installmentMonths = "installment_months"
        case installmentMonthlyPay = "installment_monthly_pay"
        case installmentRemainMonths = "installment_remain_months"
        case repaymentDay = "repayment_day"
        case linkGearAsset = "link_gear_asset"
        case gearCategory = "gear_category"
        case gearSpec = "gear_spec"
    }

    public init(
        amount: Int64,
        type: String = "expense",
        category: String,
        title: String,
        note: String? = nil,
        paymentMethod: String? = nil,
        wishId: Int? = nil,
        footprintId: Int? = nil,
        cityCode: String? = nil,
        occurredAt: String = FormatUtils.beijingISOString(),
        isInstallment: Bool? = nil,
        installmentChannelCode: String? = nil,
        installmentTotalAmount: Int64? = nil,
        installmentMonths: Int? = nil,
        installmentMonthlyPay: Int64? = nil,
        installmentRemainMonths: Int? = nil,
        repaymentDay: Int? = nil,
        linkGearAsset: Bool = false,
        gearCategory: String? = nil,
        gearSpec: String? = nil
    ) {
        self.amount = amount
        self.type = type
        self.category = category
        self.title = title
        self.note = note
        self.paymentMethod = paymentMethod
        self.wishId = wishId
        self.footprintId = footprintId
        self.cityCode = cityCode
        self.occurredAt = occurredAt
        self.isInstallment = isInstallment
        self.installmentChannelCode = installmentChannelCode
        self.installmentTotalAmount = installmentTotalAmount
        self.installmentMonths = installmentMonths
        self.installmentMonthlyPay = installmentMonthlyPay
        self.installmentRemainMonths = installmentRemainMonths
        self.repaymentDay = repaymentDay
        self.linkGearAsset = linkGearAsset
        self.gearCategory = gearCategory
        self.gearSpec = gearSpec
    }
}

/// 随身装备与固定资产单品 (GearItem RC-53)
public struct GearItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var spec: String?
    public var category: String
    public var status: String? // "active" | "sold"
    public var priceCents: Int64?
    public var purchaseDate: String?
    public var soldPriceCents: Int64?
    public var soldDate: String?
    public var note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case spec
        case category
        case status
        case priceCents = "price_cents"
        case purchaseDate = "purchase_date"
        case soldPriceCents = "sold_price_cents"
        case soldDate = "sold_date"
        case note
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        spec: String? = nil,
        category: String,
        status: String? = "active",
        priceCents: Int64? = nil,
        purchaseDate: String? = nil,
        soldPriceCents: Int64? = nil,
        soldDate: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.spec = spec
        self.category = category
        self.status = status
        self.priceCents = priceCents
        self.purchaseDate = purchaseDate
        self.soldPriceCents = soldPriceCents
        self.soldDate = soldDate
        self.note = note
    }
}

/// 新增固定资产设备请求载荷 (POST /api/v1/assets/gear)
/// 严格遵循 RC-132 契约：同步记账字段为 create_transaction
public struct AddGearAssetRequest: Codable, Sendable {
    public var name: String
    public var spec: String?
    public var category: String
    public var priceCents: Int64
    public var purchaseDate: String
    public var note: String?
    public var createTransaction: Bool
    public var paymentMethod: String?
    /// 是否按分期购入（与账目分期同一套协议）
    public var isInstallment: Bool
    public var installmentChannelCode: String?
    public var installmentTotalAmount: Int64?
    public var installmentMonths: Int?
    public var repaymentDay: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case spec
        case category
        case priceCents = "price_cents"
        case purchaseDate = "purchase_date"
        case note
        case createTransaction = "create_transaction"
        case paymentMethod = "payment_method"
        case isInstallment = "is_installment"
        case installmentChannelCode = "installment_channel_code"
        case installmentTotalAmount = "installment_total_amount"
        case installmentMonths = "installment_months"
        case repaymentDay = "repayment_day"
    }

    public init(
        name: String,
        spec: String? = nil,
        category: String,
        priceCents: Int64,
        purchaseDate: String = FormatUtils.beijingDateString(),
        note: String? = nil,
        createTransaction: Bool = true,
        paymentMethod: String? = nil,
        isInstallment: Bool = false,
        installmentChannelCode: String? = nil,
        installmentTotalAmount: Int64? = nil,
        installmentMonths: Int? = nil,
        repaymentDay: Int? = nil
    ) {
        self.name = name
        self.spec = spec
        self.category = category
        self.priceCents = priceCents
        self.purchaseDate = purchaseDate
        self.note = note
        self.createTransaction = createTransaction
        self.paymentMethod = paymentMethod
        self.isInstallment = isInstallment
        self.installmentChannelCode = installmentChannelCode
        self.installmentTotalAmount = installmentTotalAmount
        self.installmentMonths = installmentMonths
        self.repaymentDay = repaymentDay
    }
}

/// 资产大盘看板聚合响应 (GET /api/v1/assets/overview)
public struct AssetsOverview: Codable, Equatable, Sendable {
    public var netWorth: Int64
    public var liquidBalance: Int64
    public var initialLiquidBalance: Int64
    public var fixedAssets: Int64
    public var totalLiabilities: Int64
    public var monthlyLiabilities: Int64
    public var gearSummary: GearSummary?
    public var channelLiabilities: [ChannelLiability]?

    enum CodingKeys: String, CodingKey {
        case netWorth = "net_worth"
        case liquidBalance = "liquid_balance"
        case initialLiquidBalance = "initial_liquid_balance"
        case fixedAssets = "fixed_assets"
        case totalLiabilities = "total_liabilities"
        case monthlyLiabilities = "monthly_liabilities"
        case gearSummary = "gear_summary"
        case channelLiabilities = "channel_liabilities"
    }
}

public struct GearSummary: Codable, Equatable, Sendable {
    public var totalCount: Int
    public var activeCount: Int
    public var activeValue: Int64
    public var soldCount: Int
    public var soldRecoveredValue: Int64
    public var items: [GearItem]?

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case activeCount = "active_count"
        case activeValue = "active_value"
        case soldCount = "sold_count"
        case soldRecoveredValue = "sold_recovered_value"
        case items
    }
}

public struct ChannelLiability: Codable, Identifiable, Equatable, Sendable {
    public var id: String { channelCode }
    public var channelCode: String
    public var channelName: String
    public var repaymentDay: Int
    public var color: String?
    public var totalDebt: Int64
    public var monthlyPay: Int64
    public var daysUntilRepayment: Int
    public var activeCount: Int

    enum CodingKeys: String, CodingKey {
        case channelCode = "channel_code"
        case channelName = "channel_name"
        case repaymentDay = "repayment_day"
        case color
        case totalDebt = "total_debt"
        case monthlyPay = "monthly_pay"
        case daysUntilRepayment = "days_until_repayment"
        case activeCount = "active_count"
    }
}

/// 信贷与分期渠道配置 (GET /api/v1/credit-channels)
public struct CreditChannel: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var code: String
    public var name: String
    public var repaymentDay: Int
    public var isBuiltin: Bool
    public var color: String?

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case name
        case repaymentDay = "repayment_day"
        case isBuiltin = "is_builtin"
        case color
    }

    public init(
        id: Int,
        code: String,
        name: String,
        repaymentDay: Int = 10,
        isBuiltin: Bool = false,
        color: String? = nil
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.repaymentDay = repaymentDay
        self.isBuiltin = isBuiltin
        self.color = color
    }
}

/// 新建或修改信贷分期渠道请求载荷 (POST / PUT /api/v1/credit-channels)
public struct CreateCreditChannelRequest: Codable, Equatable, Sendable {
    public var code: String?
    public var name: String
    public var repaymentDay: Int
    public var color: String?

    enum CodingKeys: String, CodingKey {
        case code
        case name
        case repaymentDay = "repayment_day"
        case color
    }

    public init(
        code: String? = nil,
        name: String,
        repaymentDay: Int = 10,
        color: String? = nil
    ) {
        self.code = code
        self.name = name
        self.repaymentDay = repaymentDay
        self.color = color
    }
}

/// 自定义分类字典项 (GET /api/v1/categories)
public struct CategoryOption: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var scope: String // "expense", "income", "gear", "payment", "project"
    public var name: String
    public var sortOrder: Int
    public var isBuiltin: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case scope
        case name
        case sortOrder = "sort_order"
        case isBuiltin = "is_builtin"
    }
}

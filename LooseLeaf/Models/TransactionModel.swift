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
        // 可逆编码：合成条目 id = txId - 1_000_000（恒为负，不与真实散页正 id /
        // 待同步散页的小负 id 撞号）。反向解析见 LifeEntry.associatedTransactionId。
        // 旧方案 `-abs(id) - 1_000_000` 不可逆——待同步账目（负 id）反解回正数，
        // 而 transactionById 的键是负 id ⇒ 永远查不到，账目视角的编辑/删除全部失联。
        return LifeEntry(
            id: id - 1_000_000,
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

/// 编辑一笔已有账目时，分期相关字段应当怎么取值
///
/// 关键（2026-10-22 修复）：**金额改了，分期总额必须跟着改**。
///
/// 原先桌面端编辑分期账目时传的是**旧**的 `installmentTotalAmount`，
/// 而月供却按**新**金额重算 —— 于是库里
/// `amount = ¥6,000`、`installment_total_amount = ¥12,000`、`monthly_pay = ¥500`，
/// 资产大盘仍按 ¥12,000 计负债（实算 ¥11,500）。
/// 用户明明把金额改小了，**负债却纹丝不动**，
/// 展厅与桌面端显示的「分期总额」也对不上。
///
/// 口径与 Web / Android 一致：**分期总额 == 账目金额**。
/// 金额没改时沿用原值（总额可能本就与金额不同，例如「首付 + 分期」）。
public struct InstallmentEditFields: Equatable, Sendable {
    /// 本次要发出的 is_installment（nil = 不携带）
    public var isInstallment: Bool?
    /// 本次是否**显式声明**取消分期
    public var clearInstallment: Bool
    public var totalAmount: Int64?
    public var monthlyPay: Int64?
    public var months: Int?
    public var remainMonths: Int?
    public var repaymentDay: Int?
    public var channelCode: String?
}

public enum InstallmentEditing {
    /// 本次编辑对分期的**意图**（三态）
    public enum Intent: Equatable, Sendable {
        /// 本次与分期无关 —— 服务端保持原值
        case untouched
        /// 明确是分期
        case apply
        /// 明确取消分期 —— 服务端会清空全部账期字段
        case cancel
    }

    /// 按意图 + 新金额推算编辑后的分期字段
    ///
    /// - Parameters:
    ///   - transaction: 被编辑的原始账目
    ///   - newAmountCents: 编辑后的新金额（分）
    ///   - intent: 本次对分期的意图
    ///   - channelCode: 用户选定的信贷渠道（nil = 沿用原值）
    ///   - months: 用户选定的期数（nil = 沿用原值）
    ///   - repaymentDay: 用户选定的每月还款日（nil = 沿用原值）
    public static func fields(
        for transaction: Transaction,
        newAmountCents: Int64,
        intent: Intent,
        channelCode: String? = nil,
        months: Int? = nil,
        repaymentDay: Int? = nil
    ) -> InstallmentEditFields {
        switch intent {
        case .untouched:
            // 本次不涉及分期。
            //
            // 关键：原账目**是**分期时，仍然要把账期字段带出去 ——
            // 因为后端一旦收到 `is_installment: true` 就会进入「写分期」的分支，
            // 若此时不携带 `installment_total_amount`，总额会保持旧值，
            // 于是「金额改了、负债没改」又回来了（MC-13 的老问题）。
            //
            // 原账目**不是**分期时则什么都不带（服务端保持原值）。
            //
            // isInstallment 透传**原始的可选值**：
            // nil = 省略（服务端保持原值）；false = 显式「不是分期」但**不带** clear_installment
            // （后端契约：单传 false 仍保持原值，这是为了保护老客户端）。
            guard transaction.isInstallment == true else {
                return InstallmentEditFields(
                    isInstallment: transaction.isInstallment,
                    clearInstallment: false,
                    totalAmount: nil,
                    monthlyPay: nil,
                    months: nil,
                    remainMonths: nil,
                    repaymentDay: nil,
                    channelCode: nil
                )
            }
            return applyFields(
                transaction: transaction,
                newAmountCents: newAmountCents,
                channelCode: channelCode,
                months: months,
                repaymentDay: repaymentDay
            )

        case .cancel:
            // 显式取消分期 —— 必须同时带上 is_installment=false 与 clear_installment=true，
            // 否则后端会「保持原值」，分期根本取消不掉（Android / Web 上踩过的同一个坑）。
            return InstallmentEditFields(
                isInstallment: false,
                clearInstallment: true,
                totalAmount: nil,
                monthlyPay: nil,
                months: nil,
                remainMonths: nil,
                repaymentDay: nil,
                channelCode: nil
            )

        case .apply:
            // 明确是分期 —— 总额与月供**由同一组数推出**，保证自洽。
            return applyFields(
                transaction: transaction,
                newAmountCents: newAmountCents,
                channelCode: channelCode,
                months: months,
                repaymentDay: repaymentDay
            )
        }
    }

    /// 「是分期」时账期字段的推算 —— 总额与月供由**同一组数**推出，保证自洽：
    ///   月供 = 总额 / 期数（整数除法，与后端 `total / months` 完全同口径）
    /// 关键：金额改了总额必须跟着改，否则「金额改了、负债没改」。
    private static func applyFields(
        transaction: Transaction,
        newAmountCents: Int64,
        channelCode: String?,
        months: Int?,
        repaymentDay: Int?
    ) -> InstallmentEditFields {
        let amountChanged = newAmountCents != transaction.amount
        let effectiveMonths = months ?? transaction.installmentMonths ?? 12
        let total: Int64
        if amountChanged {
            total = newAmountCents
        } else {
            total = transaction.installmentTotalAmount ?? newAmountCents
        }
        let monthly: Int64? = effectiveMonths > 0 ? total / Int64(effectiveMonths) : nil
        // 关键（2026-10-25 修复）：原账目**不是**分期（remainMonths 为 nil）时，
        // 必须显式发「满期数」而不是省略 —— 后端 UpdateTransaction 的
        // `InstallmentRemainMonths` 是普通 int，省略 = 0，而 `0 >= 0 && 0 <= autoRemain`
        // 恒命中 ⇒ 「支出改成分期」后剩余期数直接落 0，资产大盘按已还清计，
        // **负债当场清零**。与 Web 端同口径：新开分期发满期数。
        let remain = transaction.installmentRemainMonths ?? effectiveMonths
        return InstallmentEditFields(
            isInstallment: true,
            clearInstallment: false,
            totalAmount: total,
            monthlyPay: monthly,
            months: effectiveMonths,
            remainMonths: remain,
            repaymentDay: repaymentDay ?? transaction.repaymentDay,
            channelCode: channelCode ?? transaction.installmentChannelCode
        )
    }

    /// 由「用户是否显式动过分期开关」推出本次意图
    ///
    /// - Parameters:
    ///   - wantsInstallment: 分期开关当前状态
    ///   - touched: 用户是否**显式**动过这个开关
    ///   - isExpense: 当前收支类型是否为支出（收入没有分期）
    ///   - transaction: 被编辑的原始账目
    ///
    /// 关键（2026-10-22）：**没动过就不许改**。
    /// 若只看「开关当前值 vs 原值」，那么「支出 → 收入 → 支出」这种来回切换
    /// 会被误判成「用户取消了分期」，于是一次无心的类型切换就把分期静默抹掉。
    public static func intent(
        wantsInstallment: Bool,
        touched: Bool,
        isExpense: Bool,
        transaction: Transaction
    ) -> Intent {
        let wasInstallment = (transaction.isInstallment == true)
        if isExpense {
            // 支出态：只有用户**显式**动过开关，才算表达了意图。
            // 没动过就沿用原值 —— 否则「支出 → 收入 → 支出」这种来回切换
            // 会被误判成「用户取消了分期」，一次无心的类型切换就把分期静默抹掉。
            guard touched else { return .untouched }
            if wantsInstallment { return .apply }
            return wasInstallment ? .cancel : .untouched
        }
        // 收入没有分期 —— 原账目是分期时**在保存这一刻**取消它。
        //
        // 注意这与「来回切换」不冲突：判定用的是**保存时的最终类型**，
        // 用户「支出 → 收入 → 支出」最终停在支出，走上面那条 untouched 分支，
        // 分期原样保留。
        // （与 Web 端同口径：`wantInstallment` 也按保存时的最终类型算。）
        return wasInstallment ? .cancel : .untouched
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
    /// 显式声明「本次要取消分期」
    ///
    /// 关键：单发 `is_installment: false` **不足以**表达「取消分期」。
    /// 后端的新契约是「不带 clear_installment 就保持原值」——
    /// 因为已发布的老客户端（`Bool` 不可选，必定发 false）压根不知道可以不传。
    /// 若把 false 直接当成「取消分期」，老用户编辑一次账目就会毁掉分期负债。
    public var clearInstallment: Bool
    public var installmentChannelCode: String?
    public var installmentTotalAmount: Int64?
    public var installmentMonths: Int?
    public var installmentMonthlyPay: Int64?
    public var installmentRemainMonths: Int?
    public var repaymentDay: Int?
    /// 显式清空属地城市（契约 A，仅修订路径使用）：true 时服务端清空 city_code，
    /// 优先于 city_code 字段。创建路径恒为 nil（不下发）。
    public var clearCity: Bool?
    /// 幂等创建键（契约 C）：首次在线直发前生成，发件箱持久化后重试复用同一个 ——
    /// 服务端按它查重，杜绝同一笔账被重复上传成两份。
    /// nil 仅代表升级前的旧载荷，发送前会补签。
    public var clientRequestId: String?
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
        case clearInstallment = "clear_installment"
        case installmentChannelCode = "installment_channel_code"
        case installmentTotalAmount = "installment_total_amount"
        case installmentMonths = "installment_months"
        case installmentMonthlyPay = "installment_monthly_pay"
        case installmentRemainMonths = "installment_remain_months"
        case repaymentDay = "repayment_day"
        case clearCity = "clear_city"
        case clientRequestId = "client_request_id"
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
        clearInstallment: Bool = false,
        installmentChannelCode: String? = nil,
        installmentTotalAmount: Int64? = nil,
        installmentMonths: Int? = nil,
        installmentMonthlyPay: Int64? = nil,
        installmentRemainMonths: Int? = nil,
        repaymentDay: Int? = nil,
        clearCity: Bool? = nil,
        clientRequestId: String? = nil,
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
        self.clearInstallment = clearInstallment
        self.installmentChannelCode = installmentChannelCode
        self.installmentTotalAmount = installmentTotalAmount
        self.installmentMonths = installmentMonths
        self.installmentMonthlyPay = installmentMonthlyPay
        self.installmentRemainMonths = installmentRemainMonths
        self.repaymentDay = repaymentDay
        self.clearCity = clearCity
        self.clientRequestId = clientRequestId
        self.linkGearAsset = linkGearAsset
        self.gearCategory = gearCategory
        self.gearSpec = gearSpec
    }
}

/// 随身装备与固定资产单品 (GearItem RC-53)
/// 恢复随身设备的响应
public struct RestoreGearAssetResponse: Codable, Sendable {
    public var id: String
    public var restored: Bool
}

/// 恢复随身设备请求载荷（⌘Z 撤销用）
public struct RestoreGearAssetRequest: Codable, Sendable {
    public var id: String
    public var name: String
    public var spec: String?
    public var category: String
    public var status: String?
    public var priceCents: Int64?
    public var purchaseDate: String?
    public var soldPriceCents: Int64?
    public var soldDate: String?
    public var note: String?
    /// 原先在档案数组中的位置（-1 = 追加到末尾）
    public var index: Int

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
        case index
    }

    public init(
        id: String,
        name: String,
        spec: String? = nil,
        category: String = "数码器材",
        status: String? = nil,
        priceCents: Int64? = nil,
        purchaseDate: String? = nil,
        soldPriceCents: Int64? = nil,
        soldDate: String? = nil,
        note: String? = nil,
        index: Int = -1
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
        self.index = index
    }
}

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

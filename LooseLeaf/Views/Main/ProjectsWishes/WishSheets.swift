import SwiftUI

/// 心愿典藏相关弹窗集合 (NewWishSheet / EditWishSheet / ResolveWishSheet)
/// 从 ProjectsWishesView 中拆出的独立 Sheet 组件：
/// 1. NewWishSheet —— 许下新心愿（类型 / 预算 / 目的地城市 / 手记）
/// 2. EditWishSheet —— 修订既有心愿
/// 3. ResolveWishSheet —— 圆满归册心愿，并可联动生成流水 / 固资 / 足迹票根 / 时间流手稿
/// 仅做文件拆分，逻辑、数值与视觉表现与拆分前完全一致。

// MARK: - 新建心愿单弹窗 (NewWishSheet)

@MainActor
public struct NewWishSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var title: String = ""
    @State private var kind: String = "item"
    @State private var budgetYuan: String = ""
    @State private var spec: String = ""
    @State private var note: String = ""
    @State private var cityCode: String = ""
    @State private var cityName: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?
    /// 补档：许下日期可选过去任意一天（默认今天）
    @State private var plantedAt: Date = Date()

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            Text("许下新心愿")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack(spacing: 6) {
                PaperPillButton(title: "心仪好物", isSelected: kind == "item") { kind = "item" }
                PaperPillButton(title: "远方旅程", isSelected: kind == "travel") { kind = "travel" }
                PaperPillButton(title: "阶段里程碑", isSelected: kind == "milestone") { kind = "milestone" }
            }

            TextField("心愿名称", text: $title)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            if kind == "travel" {
                PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName, placeholder: "点选目的地城市…")
            }

            TextField("规格参数或目的地补充", text: $spec)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("预期预算金额（元）", text: $budgetYuan)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading))
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            HStack(spacing: ArchiveSpacing.s) {
                PaperDatePicker(selection: $plantedAt, enableTime: false, label: "许下日期")
                Text("（可选择过去的日期补录旧心愿）")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            TextField("写下心愿初衷与手记…", text: $note, axis: .vertical)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(3...5)
                .padding(10)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("存入心愿单") {
                    submitWish()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(
            minWidth: ArchiveSheetWidth.compact,
            idealWidth: ArchiveSheetWidth.compact,
            maxWidth: ArchiveSheetWidth.compact
        )
        .background(ArchivePalette.archivePaper)
    }

    private func submitWish() {
        let cents = FormatUtils.parseYuanToCents(budgetYuan) ?? 0
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateWishRequest(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: kind,
                    note: note.isEmpty ? nil : note,
                    spec: spec.isEmpty ? nil : spec,
                    cityCode: cityCode.isEmpty ? nil : cityCode,
                    cityName: cityName.isEmpty ? nil : cityName,
                    budget: cents,
                    plantedAt: FormatUtils.beijingDateString(from: plantedAt)
                )
                _ = try await APIClient.shared.createWish(req)
                // 关键：心愿在服务端会落一条伴生散页（时间流的一级数据），
                // 必须连带刷新时间流，否则「创建心愿后时间流没反应」。
                await appState.refreshAfterSecondaryWrite()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 修订心愿弹窗 (EditWishSheet)

@MainActor
public struct EditWishSheet: View {
    @Bindable var appState: AppState
    let wish: Wish
    var onDismiss: () -> Void

    @State private var title: String
    @State private var kind: String
    @State private var budgetYuan: String
    @State private var spec: String
    @State private var note: String
    @State private var cityCode: String
    @State private var cityName: String
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public init(appState: AppState, wish: Wish, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.wish = wish
        self.onDismiss = onDismiss
        _title = State(initialValue: wish.title)
        _kind = State(initialValue: wish.kind)
        _budgetYuan = State(initialValue: FormatUtils.formattedYuan(cents: wish.budget))
        _spec = State(initialValue: wish.spec ?? "")
        _note = State(initialValue: wish.note ?? "")
        _cityCode = State(initialValue: wish.cityCode ?? "")
        _cityName = State(initialValue: wish.cityName ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            Text("修订心愿")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack(spacing: 6) {
                PaperPillButton(title: "心仪好物", isSelected: kind == "item") { kind = "item" }
                PaperPillButton(title: "远方旅程", isSelected: kind == "travel") { kind = "travel" }
                PaperPillButton(title: "阶段里程碑", isSelected: kind == "milestone") { kind = "milestone" }
            }

            TextField("心愿名称", text: $title)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            if kind == "travel" {
                PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName, placeholder: "点选目的地城市…")
            }

            TextField("规格参数或目的地补充", text: $spec)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("意向预算金额（元）", text: $budgetYuan)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading))
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("写下心愿初衷与手记…", text: $note, axis: .vertical)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(3...5)
                .padding(10)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存修改") {
                    updateWish()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(
            minWidth: ArchiveSheetWidth.compact,
            idealWidth: ArchiveSheetWidth.compact,
            maxWidth: ArchiveSheetWidth.compact
        )
        .background(ArchivePalette.archivePaper)
    }

    private func updateWish() {
        let cents = FormatUtils.parseYuanToCents(budgetYuan) ?? 0
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateWishRequest(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: kind,
                    note: note.isEmpty ? nil : note,
                    spec: spec.isEmpty ? nil : spec,
                    cityCode: cityCode.isEmpty ? nil : cityCode,
                    cityName: cityName.isEmpty ? nil : cityName,
                    budget: cents
                )
                _ = try await APIClient.shared.updateWish(id: wish.id, req)
                // 编辑心愿同样会改动伴生散页，需连带刷新时间流
                await appState.refreshAfterSecondaryWrite()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 圆满心愿弹窗 (ResolveWishSheet)

@MainActor
public struct ResolveWishSheet: View {
    @Bindable var appState: AppState
    let wish: Wish
    var onDismiss: () -> Void

    @State private var actualCostYuan: String
    @State private var resolutionType: String = "exact" // exact | altered | relinquished
    @State private var createTransaction: Bool = true
    @State private var createGearAsset: Bool
    @State private var createLifeEntry: Bool = true
    @State private var createFootprint: Bool
    @State private var entryContent: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public init(appState: AppState, wish: Wish, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.wish = wish
        self.onDismiss = onDismiss
        _actualCostYuan = State(initialValue: FormatUtils.formattedYuan(cents: wish.budget))
        _createGearAsset = State(initialValue: wish.kind == "item")
        _createFootprint = State(initialValue: wish.kind == "travel")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveCardMetrics.padding) {
            Text("圆满心愿 · 载入典藏")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text("达成目标：\(wish.title)")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .medium))
                .foregroundStyle(ArchivePalette.inkSecondary)

            // 达成方式单选
            HStack(spacing: 6) {
                PaperPillButton(title: "如愿拿下", isSelected: resolutionType == "exact") { resolutionType = "exact" }
                PaperPillButton(title: "替代拿下", isSelected: resolutionType == "altered") { resolutionType = "altered" }
                PaperPillButton(title: "理性拔草", isSelected: resolutionType == "relinquished") { resolutionType = "relinquished" }
            }

            // 实付金额
            HStack(spacing: ArchiveSpacing.xs) {
                Text("实付金额 ¥")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .foregroundStyle(ArchivePalette.inkMuted)
                TextField("0.00", text: $actualCostYuan)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: 14, weight: .semibold))
                    .padding(6)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            // 联动联动伴生复选
            VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                Toggle("联动生成一笔记账支出流水", isOn: $createTransaction)
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))

                if wish.kind == "item" {
                    Toggle("联动建入随身固资设备库 (EDC Gear)", isOn: $createGearAsset)
                        .toggleStyle(.paperCheckbox)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                }

                if wish.kind == "travel" {
                    Toggle("同步点亮目的地城市足迹票根", isOn: $createFootprint)
                        .toggleStyle(.paperCheckbox)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                }

                Toggle("伴生发布一篇时间流手稿日记", isOn: $createLifeEntry)
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
            }

            if createLifeEntry {
                TextField("圆梦感言手记", text: $entryContent)
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
            }

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("确认圆满归册") {
                    submitResolve()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(isSubmitting)
            }
        }
        .padding(20)
        .frame(
            minWidth: ArchiveSheetWidth.standard,
            idealWidth: ArchiveSheetWidth.standard,
            maxWidth: ArchiveSheetWidth.standard
        )
        .background(ArchivePalette.archivePaper)
    }

    private func submitResolve() {
        let isRelinquished = (resolutionType == "relinquished")
        let cents = isRelinquished ? 0 : (FormatUtils.parseYuanToCents(actualCostYuan) ?? 0)
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = ResolveWishRequest(
                    fulfilledAt: FormatUtils.beijingISOString(),
                    actualCost: cents,
                    resolutionType: resolutionType,
                    actualTitle: wish.title,
                    createTransaction: isRelinquished ? false : createTransaction,
                    createGearAsset: isRelinquished ? false : createGearAsset,
                    createLifeEntry: createLifeEntry,
                    createFootprint: isRelinquished ? false : createFootprint,
                    entryContent: entryContent.isEmpty ? nil : entryContent
                )
                _ = try await APIClient.shared.resolveWish(id: wish.id, req)
                // 心愿圆满会在时间流落一条新散页：这里用增量刷新即可，
                // 不必再全量重拉（原先 forceFull: true 是「点一下卡好几秒」的元凶之一）。
                await appState.loadProjectsWishesFootprints()
                await appState.loadEntries(forceFull: false)
                await appState.loadTransactionsAndAssets(forceFull: false)
                await appState.loadConfigAndProfile()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

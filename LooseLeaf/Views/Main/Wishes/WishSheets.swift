import SwiftUI

/// 心愿典藏相关弹窗集合 (WishEditorSheet / ResolveWishSheet)
/// 1. WishEditorSheet —— 统一新建与修订心愿（修订时全类型保留 spec，省略 attachment_ids 杜绝清空跨端照片）
/// 2. ResolveWishSheet —— 圆满归册心愿，并可联动生成记账支出流水与时间流手稿

// MARK: - 统一心愿新建与修订弹窗 (WishEditorSheet)

@MainActor
public struct WishEditorSheet: View {
    @Bindable var appState: AppState
    let wish: Wish?
    var onDismiss: () -> Void

    @State private var title: String
    @State private var kind: String
    @State private var budgetYuan: String
    @State private var spec: String
    @State private var note: String
    @State private var isPrivate: Bool
    @State private var plantedAt: Date
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?
    @FocusState private var isTitleFocused: Bool

    public init(appState: AppState, wish: Wish? = nil, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.wish = wish
        self.onDismiss = onDismiss
        if let wish {
            _title = State(initialValue: wish.title)
            _kind = State(initialValue: wish.kind)
            _budgetYuan = State(initialValue: FormatUtils.formattedYuan(cents: wish.budget))
            _spec = State(initialValue: wish.spec ?? "")
            _note = State(initialValue: wish.note ?? "")
            _isPrivate = State(initialValue: wish.isPrivate ?? false)
            _plantedAt = State(initialValue: FormatUtils.parseFlexDate(wish.plantedAt) ?? Date())
        } else {
            _title = State(initialValue: "")
            _kind = State(initialValue: "item")
            _budgetYuan = State(initialValue: "")
            _spec = State(initialValue: "")
            _note = State(initialValue: "")
            _isPrivate = State(initialValue: false)
            _plantedAt = State(initialValue: Date())
        }
    }

    private var isEditing: Bool { wish != nil }

    public var body: some View {
        PaperSheetScaffold(
            title: isEditing ? "修订心愿" : "许下新心愿",
            subtitle: isEditing ? nil : "好物 · 旅程 · 里程碑",
            width: ArchiveSheetWidth.compact,
            isSubmitting: isSubmitting,
            isSubmitDisabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            submitTitle: isEditing ? "保存修改 ⌘↩" : "存入心愿单 ⌘↩",
            onCancel: onDismiss,
            onSubmit: submit
        ) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                HStack(spacing: 6) {
                    PaperPillButton(title: "心仪好物", isSelected: kind == "item") { kind = "item" }
                    PaperPillButton(title: "远方旅程", isSelected: kind == "travel") { kind = "travel" }
                    PaperPillButton(title: "阶段里程碑", isSelected: kind == "milestone") { kind = "milestone" }
                }

                TextField("心愿名称", text: $title)
                    .accessibilityLabel("心愿名称")
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                TextField("规格参数或补充说明", text: $spec)
                    .accessibilityLabel("规格参数或补充说明")
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                TextField("预期预算金额（元）", text: $budgetYuan)
                    .accessibilityLabel("预期预算金额")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading))
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                if !isEditing {
                    HStack(spacing: ArchiveSpacing.s) {
                        PaperDatePicker(selection: $plantedAt, enableTime: false, label: "许下日期")
                        Text("（可选择过去的日期补录旧心愿）")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }

                TextField("写下心愿初衷与手记…", text: $note, axis: .vertical)
                    .accessibilityLabel("心愿初衷与手记")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .lineLimit(3...8)
                    .padding(10)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                HStack {
                    Label("私密心愿（仅配对主理人设备可见）", systemImage: ArchiveIcon.lock.systemName)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    Spacer()
                    Toggle("私密心愿", isOn: $isPrivate)
                        .labelsHidden()
                        .toggleStyle(.paperSwitch)
                        .accessibilityLabel("设为私密心愿")
                }

                if let errorText {
                    Text(errorText)
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }
            }
        }
        .onAppear {
            isTitleFocused = true
        }
    }

    private func submit() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !isSubmitting else { return }
        let cents = FormatUtils.parseYuanToCents(budgetYuan) ?? 0
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                if let wish {
                    let req = CreateWishRequest(
                        title: cleanTitle,
                        kind: kind,
                        // 空串是显式清空；nil 会被后端当作保持原值；attachmentIds 默认 nil 不覆盖跨端附件。
                        note: note,
                        spec: spec,
                        budget: cents,
                        isPrivate: isPrivate
                    )
                    _ = try await APIClient.shared.updateWish(id: wish.id, req)
                } else {
                    let req = CreateWishRequest(
                        title: cleanTitle,
                        kind: kind,
                        note: note.isEmpty ? nil : note,
                        spec: spec.isEmpty ? nil : spec,
                        budget: cents,
                        plantedAt: FormatUtils.beijingDateString(from: plantedAt),
                        isPrivate: isPrivate
                    )
                    _ = try await APIClient.shared.createWish(req)
                }
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
    @State private var createLifeEntry: Bool = true
    @State private var entryContent: String = ""
    @State private var alteredTitle: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?
    @FocusState private var isCostFocused: Bool

    public init(appState: AppState, wish: Wish, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.wish = wish
        self.onDismiss = onDismiss
        _actualCostYuan = State(initialValue: FormatUtils.formattedYuan(cents: wish.budget))
    }

    public var body: some View {
        PaperSheetScaffold(
            title: "圆满心愿 · 载入典藏",
            subtitle: "达成目标：\(wish.title)",
            width: ArchiveSheetWidth.standard,
            isSubmitting: isSubmitting,
            submitTitle: "确认圆满归册 ⌘↩",
            onCancel: onDismiss,
            onSubmit: submitResolve
        ) {
            VStack(alignment: .leading, spacing: ArchiveCardMetrics.padding) {
                HStack(spacing: 6) {
                    PaperPillButton(title: "如愿拿下", isSelected: resolutionType == "exact") { resolutionType = "exact" }
                    PaperPillButton(title: "替代拿下", isSelected: resolutionType == "altered") { resolutionType = "altered" }
                    PaperPillButton(title: "理性拔草", isSelected: resolutionType == "relinquished") { resolutionType = "relinquished" }
                }

                if resolutionType == "altered" {
                    EntryPaperField(
                        placeholder: "实际购入的物品名（例：同价位的中性笔）",
                        text: $alteredTitle,
                        font: ArchiveTypography.bodySans(size: 12)
                    )
                }

                if resolutionType != "relinquished" {
                    HStack(spacing: ArchiveSpacing.xs) {
                        Text("实付金额 ¥")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        TextField("0.00", text: $actualCostYuan)
                            .accessibilityLabel("实付金额")
                            .textFieldStyle(.plain)
                            .focused($isCostFocused)
                            .font(ArchiveTypography.monoScale(size: 14, weight: .semibold))
                            .padding(6)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    }
                }

                Divider().overlay(ArchivePalette.borderSubtle)

                if resolutionType != "relinquished" {
                    Toggle("联动生成一笔记账支出流水", isOn: $createTransaction)
                        .toggleStyle(.paperCheckbox)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                }

                Toggle("伴生发布一篇时间流手稿日记", isOn: $createLifeEntry)
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))

                if createLifeEntry {
                    TextField("圆梦感言手记", text: $entryContent, axis: .vertical)
                        .accessibilityLabel("圆梦感言手记")
                        .textFieldStyle(.plain)
                        .lineLimit(2...6)
                        .padding(ArchiveSpacing.s)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }

                if let errorText {
                    Text(errorText)
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }
            }
        }
        .onAppear {
            isCostFocused = true
        }
    }

    private func submitResolve() {
        guard !isSubmitting else { return }
        let isRelinquished = (resolutionType == "relinquished")
        let cleanAlteredTitle = alteredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolutionType == "altered" && cleanAlteredTitle.isEmpty {
            errorText = "「替代拿下」请填写实际购入的物品名"
            return
        }
        let cents = isRelinquished ? 0 : (FormatUtils.parseYuanToCents(actualCostYuan) ?? 0)
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = ResolveWishRequest(
                    fulfilledAt: FormatUtils.beijingISOString(),
                    actualCost: cents,
                    resolutionType: resolutionType,
                    actualTitle: resolutionType == "altered" ? cleanAlteredTitle : nil,
                    createTransaction: isRelinquished ? false : createTransaction,
                    createLifeEntry: createLifeEntry,
                    entryContent: entryContent.isEmpty ? nil : entryContent
                )
                _ = try await APIClient.shared.resolveWish(id: wish.id, req)
                await appState.loadWishes()
                await appState.loadEntries(forceFull: false)
                await appState.loadTransactions(forceFull: false)
                await appState.loadConfigAndProfile()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

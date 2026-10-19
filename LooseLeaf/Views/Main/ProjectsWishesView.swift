import SwiftUI

// 原「造物 / 心愿 / 行迹」聚合主视图已拆分为 WishlistView / ProjectsView / TravelAtlasView，
// 本文件只保留多端共用的卡片、编辑 Sheet 与城市/省份回忆抽屉。

/// 城市 / 省份回忆抽屉的选择载荷（TravelAtlasView 与抽屉 Sheet 共用）
struct DrawerCitySelection: Identifiable, Equatable {
    var id: String { code }
    let code: String
    let name: String
}

struct DrawerProvinceSelection: Identifiable, Equatable {
    var id: String { adcode }
    let adcode: String
    let name: String
}

/// 统一样式与等高对齐的心愿典藏卡片 (WishCardView)
struct WishCardView: View {
    let wish: Wish
    let onResolve: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 顶栏：分类标签徽章 + 状态微胶囊
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    Image(systemName: kindIcon)
                        .font(.system(size: 9.5))
                    Text(kindTitle)
                        .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                }
                .foregroundStyle(kindColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(kindColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 5.5, height: 5.5)
                    Text(statusTitle)
                        .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                        .foregroundStyle(statusTextColor)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(statusBgColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.bottom, 10)

            // 2. 标题
            Text(wish.title)
                .font(ArchiveTypography.editorialSerif(size: 16.5, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(1)

            // 3. 规格
            if let spec = wish.spec, !spec.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.2")
                        .font(.system(size: 9))
                    Text(spec)
                        .font(ArchiveTypography.monoScale(size: 11, weight: .medium))
                }
                .foregroundStyle(ArchivePalette.inkSecondary)
                .padding(.top, 3)
                .lineLimit(1)
            }

            // 4. 手记备注
            if let note = wish.note, !note.isEmpty {
                Text(LocalizedStringKey(note))
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkSecondary.opacity(0.88))
                    .lineLimit(2)
                    .lineSpacing(2)
                    .padding(.top, 4)
            }

            // 弹性占位：将底部预算与操作栏统一牢牢推向卡片底端，确保各卡片严格等高对齐
            Spacer(minLength: 12)

            // 5. 分割线
            Rectangle()
                .fill(ArchivePalette.borderDivider)
                .frame(height: 0.5)
                .padding(.vertical, 9)

            // 6. 底部：预算 / 实付金额 + 操作按钮栏
            HStack(alignment: .center) {
                if wish.status == "fulfilled" && wish.actualCost > 0 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("圆满实付")
                            .font(ArchiveTypography.bodySans(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        Text(FormatUtils.formattedYuan(cents: wish.actualCost, includeSymbol: true))
                            .font(ArchiveTypography.monoScale(size: 13, weight: .bold))
                            .foregroundStyle(ArchivePalette.accentMoss)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("意向预算")
                            .font(ArchiveTypography.bodySans(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        Text(FormatUtils.formattedYuan(cents: wish.budget, includeSymbol: true))
                            .font(ArchiveTypography.monoScale(size: 12.5, weight: .semibold))
                            .foregroundStyle(wish.budget > 0 ? ArchivePalette.inkPrimary : ArchivePalette.inkMuted)
                    }
                }

                Spacer()

                // 主理人操作区
                HStack(spacing: 6) {
                    if wish.status != "fulfilled" {
                        Button(action: onResolve) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("圆满心愿")
                                    .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(ArchivePalette.accentMoss)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(ArchivePalette.accentMoss.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.accentMoss.opacity(0.3), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                            Text("已归册")
                                .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                        }
                        .foregroundStyle(ArchivePalette.accentMoss)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(ArchivePalette.accentMoss.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(6)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("修订心愿")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(6)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("删除心愿")
                }
            }
        }
        .padding(14)
        .frame(minHeight: 195)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.6)
        )
        .shadow(color: ArchivePalette.inkPrimary.opacity(0.04), radius: 6, x: 0, y: 2)
        .paperHover()
    }

    private var kindIcon: String {
        switch wish.kind {
        case "travel": return "airplane"
        case "milestone": return "flag.fill"
        default: return "bag.fill"
        }
    }

    private var kindTitle: String {
        switch wish.kind {
        case "travel": return "远方旅程"
        case "milestone": return "阶段里程碑"
        default: return "心仪好物"
        }
    }

    private var kindColor: Color {
        switch wish.kind {
        case "travel": return ArchivePalette.categoryColor(for: "交通")
        case "milestone": return ArchivePalette.accentMoss
        default: return ArchivePalette.accentWarm
        }
    }

    private var statusTitle: String {
        switch wish.status {
        case "fulfilled": return "已圆满归册"
        case "relinquished": return "已理性拔草"
        case "shelved": return "暂且搁置"
        default: return "静候圆梦"
        }
    }

    private var statusDotColor: Color {
        switch wish.status {
        case "fulfilled": return ArchivePalette.accentMoss
        case "relinquished": return ArchivePalette.inkMuted
        case "shelved": return Color.orange.opacity(0.8)
        default: return ArchivePalette.accentWarm
        }
    }

    private var statusTextColor: Color {
        switch wish.status {
        case "fulfilled": return ArchivePalette.accentMoss
        case "relinquished": return ArchivePalette.inkMuted
        default: return ArchivePalette.inkSecondary
        }
    }

    private var statusBgColor: Color {
        switch wish.status {
        case "fulfilled": return ArchivePalette.accentMoss.opacity(0.10)
        case "relinquished": return ArchivePalette.borderSubtle
        default: return ArchivePalette.archivePaper
        }
    }
}

/// 统一样式与等高对齐的造物项目卡片 (ProjectCardView)
struct ProjectCardView: View {
    let proj: Project
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶栏：分类标签 + 状态标签
            HStack {
                if let cat = proj.category, !cat.isEmpty {
                    Text(cat)
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ArchivePalette.accentWarm.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                if let status = proj.status, !status.isEmpty {
                    Text(status)
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.accentMoss)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ArchivePalette.accentMoss.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.bottom, 8)

            Text(proj.title)
                .font(ArchiveTypography.editorialSerif(size: 16.5, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(1)

            if let sub = proj.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .padding(.top, 3)
                    .lineLimit(1)
            }

            if !proj.description.isEmpty {
                Text(LocalizedStringKey(proj.description))
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .lineLimit(3)
                    .lineSpacing(2)
                    .padding(.top, 4)
            }

            Spacer(minLength: 12)

            Rectangle()
                .fill(ArchivePalette.borderDivider)
                .frame(height: 0.5)
                .padding(.vertical, 9)

            HStack {
                if let gh = proj.githubUrl, !gh.isEmpty, let url = URL(string: gh) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("源码仓库")
                        }
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    }
                } else {
                    Spacer(minLength: 0)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(6)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("修订项目")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(6)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("删除项目")
                }
            }
        }
        .padding(14)
        .frame(minHeight: 195)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.6)
        )
        .shadow(color: ArchivePalette.inkPrimary.opacity(0.04), radius: 6, x: 0, y: 2)
        .paperHover()
    }
}

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

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("许下新心愿")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack(spacing: 6) {
                PaperPillButton(title: "心仪好物", isSelected: kind == "item") { kind = "item" }
                PaperPillButton(title: "远方旅程", isSelected: kind == "travel") { kind = "travel" }
                PaperPillButton(title: "阶段里程碑", isSelected: kind == "milestone") { kind = "milestone" }
            }

            TextField("心愿名称", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if kind == "travel" {
                PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName, placeholder: "点选目的地城市…")
            }

            TextField("规格参数或目的地补充", text: $spec)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("预期预算金额（元）", text: $budgetYuan)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 13))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("写下心愿初衷与手记…")
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $note)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .padding(4)
                    .frame(minHeight: 64, maxHeight: 90)
            }
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 4))

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
        .frame(width: 400)
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
                    budget: cents
                )
                _ = try await APIClient.shared.createWish(req)
                await appState.loadProjectsWishesFootprints()
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
        VStack(alignment: .leading, spacing: 12) {
            Text("修订心愿")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack(spacing: 6) {
                PaperPillButton(title: "心仪好物", isSelected: kind == "item") { kind = "item" }
                PaperPillButton(title: "远方旅程", isSelected: kind == "travel") { kind = "travel" }
                PaperPillButton(title: "阶段里程碑", isSelected: kind == "milestone") { kind = "milestone" }
            }

            TextField("心愿名称", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if kind == "travel" {
                PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName, placeholder: "点选目的地城市…")
            }

            TextField("规格参数或目的地补充", text: $spec)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("意向预算金额（元）", text: $budgetYuan)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 13))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("写下心愿初衷与手记…")
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $note)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .padding(4)
                    .frame(minHeight: 64, maxHeight: 90)
            }
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 4))

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
        .frame(width: 400)
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
                await appState.loadProjectsWishesFootprints()
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
        VStack(alignment: .leading, spacing: 14) {
            Text("圆满心愿 · 载入典藏")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text("达成目标：\(wish.title)")
                .font(ArchiveTypography.bodySans(size: 13, weight: .medium))
                .foregroundStyle(ArchivePalette.inkSecondary)

            // 达成方式单选
            HStack(spacing: 6) {
                PaperPillButton(title: "如愿拿下", isSelected: resolutionType == "exact") { resolutionType = "exact" }
                PaperPillButton(title: "替代拿下", isSelected: resolutionType == "altered") { resolutionType = "altered" }
                PaperPillButton(title: "理性拔草", isSelected: resolutionType == "relinquished") { resolutionType = "relinquished" }
            }

            // 实付金额
            HStack(spacing: 4) {
                Text("实付金额 ¥")
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkMuted)
                TextField("0.00", text: $actualCostYuan)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: 14, weight: .semibold))
                    .padding(6)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            // 联动联动伴生复选
            VStack(alignment: .leading, spacing: 8) {
                Toggle("联动生成一笔记账支出流水", isOn: $createTransaction)
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: 12))

                if wish.kind == "item" {
                    Toggle("联动建入随身固资设备库 (EDC Gear)", isOn: $createGearAsset)
                        .toggleStyle(.paperCheckbox)
                        .font(ArchiveTypography.bodySans(size: 12))
                }

                if wish.kind == "travel" {
                    Toggle("同步点亮目的地城市足迹票根", isOn: $createFootprint)
                        .toggleStyle(.paperCheckbox)
                        .font(ArchiveTypography.bodySans(size: 12))
                }

                Toggle("伴生发布一篇时间流手稿日记", isOn: $createLifeEntry)
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: 12))
            }

            if createLifeEntry {
                TextField("圆梦感言手记", text: $entryContent)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
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
        .frame(width: 420)
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
                await appState.loadProjectsWishesFootprints()
                await appState.loadEntries(forceFull: true)
                await appState.loadTransactionsAndAssets(forceFull: true)
                await appState.loadConfigAndProfile()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 点亮城市足迹弹窗 (NewFootprintSheet)

@MainActor
public struct NewFootprintSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var cityCode: String = ""
    @State private var cityName: String = ""
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var visitedDate: Date = Date()
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("点亮城市行迹票根")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName, placeholder: "选择行政区划城市…")

            PaperDateTimePicker(selection: $visitedDate, label: "到访时间", showQuickShortcuts: true)

            TextField("旅程标题", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("行迹随笔手记", text: $note)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("镌刻票根并伴生入流") {
                    submitFootprint()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(ArchivePalette.archivePaper)
    }

    private func submitFootprint() {
        let cleanCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCity.isEmpty else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateFootprintRequest(
                    cityCode: cityCode.isEmpty ? (FormatUtils.resolveCityCode(from: cleanCity) ?? "330100") : cityCode,
                    cityName: cleanCity,
                    title: title.isEmpty ? nil : title,
                    visitedAt: FormatUtils.beijingISOString(from: visitedDate),
                    note: note.isEmpty ? nil : note
                )
                _ = try await APIClient.shared.createFootprint(req)
                await appState.loadProjectsWishesFootprints()
                await appState.loadEntries(forceFull: true)
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 修订足迹票根弹窗 (EditFootprintSheet)

@MainActor
public struct EditFootprintSheet: View {
    @Bindable var appState: AppState
    let footprint: Footprint
    var onDismiss: () -> Void

    @State private var cityCode: String
    @State private var cityName: String
    @State private var title: String
    @State private var note: String
    @State private var visitedDate: Date
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public init(appState: AppState, footprint: Footprint, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.footprint = footprint
        self.onDismiss = onDismiss
        _cityCode = State(initialValue: footprint.cityCode)
        _cityName = State(initialValue: footprint.cityName)
        _title = State(initialValue: footprint.title ?? "")
        _note = State(initialValue: footprint.note ?? "")
        _visitedDate = State(initialValue: FormatUtils.parseFlexDate(footprint.visitedAt) ?? Date())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("修订行迹票根")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName)

            PaperDateTimePicker(selection: $visitedDate, label: "到访时间", showQuickShortcuts: true)

            TextField("旅程标题", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("随笔手记", text: $note)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存票根修改") {
                    updateFootprint()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(ArchivePalette.archivePaper)
    }

    private func updateFootprint() {
        let cleanCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCity.isEmpty else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateFootprintRequest(
                    cityCode: cityCode.isEmpty ? (FormatUtils.resolveCityCode(from: cleanCity) ?? footprint.cityCode) : cityCode,
                    cityName: cleanCity,
                    title: title.isEmpty ? nil : title,
                    visitedAt: FormatUtils.beijingISOString(from: visitedDate),
                    note: note.isEmpty ? nil : note
                )
                _ = try await APIClient.shared.updateFootprint(id: footprint.id, req)
                await appState.loadProjectsWishesFootprints()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 新建造物项目弹窗 (NewProjectSheet)

@MainActor
public struct NewProjectSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var description: String = ""
    @State private var category: String = "开源造物"
    @State private var status: String = "持续维护"
    @State private var githubUrl: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建造物与项目")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("项目名称", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("副标题或一句话定义", text: $subtitle)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 8) {
                TextField("分类", text: $category)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                TextField("状态", text: $status)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            TextField("项目详细背景与设计手记", text: $description)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("GitHub 源码仓库链接", text: $githubUrl)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 12))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("创建造物项目") {
                    submitProject()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(ArchivePalette.archivePaper)
    }

    private func submitProject() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateProjectRequest(
                    title: cleanTitle,
                    subtitle: subtitle.isEmpty ? nil : subtitle,
                    description: description,
                    category: category.isEmpty ? nil : category,
                    status: status.isEmpty ? nil : status,
                    githubUrl: githubUrl.isEmpty ? nil : githubUrl
                )
                _ = try await APIClient.shared.createProject(req)
                await appState.loadProjectsWishesFootprints()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 修订造物项目弹窗 (EditProjectSheet)

@MainActor
public struct EditProjectSheet: View {
    @Bindable var appState: AppState
    let project: Project
    var onDismiss: () -> Void

    @State private var title: String
    @State private var subtitle: String
    @State private var description: String
    @State private var category: String
    @State private var status: String
    @State private var githubUrl: String
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public init(appState: AppState, project: Project, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.project = project
        self.onDismiss = onDismiss
        _title = State(initialValue: project.title)
        _subtitle = State(initialValue: project.subtitle ?? "")
        _description = State(initialValue: project.description)
        _category = State(initialValue: project.category ?? "开源造物")
        _status = State(initialValue: project.status ?? "持续维护")
        _githubUrl = State(initialValue: project.githubUrl ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("修订造物与项目")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("项目名称", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("副标题或一句话定义", text: $subtitle)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 8) {
                TextField("分类", text: $category)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                TextField("状态", text: $status)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            TextField("项目详细背景手记", text: $description)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("GitHub 源码仓库链接", text: $githubUrl)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 12))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存项目修改") {
                    updateProject()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(ArchivePalette.archivePaper)
    }

    private func updateProject() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateProjectRequest(
                    title: cleanTitle,
                    subtitle: subtitle.isEmpty ? nil : subtitle,
                    description: description,
                    category: category.isEmpty ? nil : category,
                    status: status.isEmpty ? nil : status,
                    githubUrl: githubUrl.isEmpty ? nil : githubUrl
                )
                _ = try await APIClient.shared.updateProject(id: project.id, req)
                await appState.loadProjectsWishesFootprints()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 山川经纬星野图谱 (CelestialAtlasCanvasView - RC-98)

@MainActor
public struct CelestialAtlasCanvasView: View {
    let footprints: [Footprint]
    var onSelectCity: (String, String) -> Void

    private struct CityCluster: Identifiable {
        var id: String { code }
        let code: String
        let name: String
        let count: Int
        let x: Double
        let y: Double
    }

    private var clusters: [CityCluster] {
        var map: [String: (name: String, count: Int)] = [:]
        for fp in footprints {
            let cur = map[fp.cityCode] ?? (name: fp.cityName, count: 0)
            map[fp.cityCode] = (name: fp.cityName, count: cur.count + 1)
        }
        return map.map { (code, info) in
            let pt = CityDictionary.coordinate(forCode: code, cityName: info.name)
            return CityCluster(code: code, name: info.name, count: info.count, x: pt.x, y: pt.y)
        }
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Canvas { context, size in
                    let cols = 8
                    let rows = 5
                    for i in 1..<cols {
                        let x = size.width * CGFloat(i) / CGFloat(cols)
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(p, with: .color(ArchivePalette.borderDivider.opacity(0.6)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    }
                    for j in 1..<rows {
                        let y = size.height * CGFloat(j) / CGFloat(rows)
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p, with: .color(ArchivePalette.borderDivider.opacity(0.6)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    }
                }

                ForEach(clusters) { item in
                    let normX = CGFloat(min(max((item.x - 60.0) / 530.0, 0.05), 0.95))
                    let normY = CGFloat(min(max((item.y - 45.0) / 485.0, 0.08), 0.92))
                    let nodeColor = item.count >= 3 ? ArchivePalette.accentWarm : (item.count == 2 ? ArchivePalette.accentMoss : ArchivePalette.inkPrimary)

                    Button {
                        onSelectCity(item.code, item.name)
                    } label: {
                        VStack(spacing: 2) {
                            ZStack {
                                Circle()
                                    .fill(nodeColor.opacity(0.18))
                                    .frame(width: 18, height: 18)
                                Circle()
                                    .fill(nodeColor)
                                    .frame(width: 7, height: 7)
                            }
                            Text(item.name)
                                .font(ArchiveTypography.editorialSerif(size: 11, weight: .medium))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(ArchivePalette.archivePaper.opacity(0.88))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: w * normX, y: h * normY)
                }

                // 右下角古典罗盘玫瑰 (Compass Rose) 与四角星野裁切标
                VStack(spacing: 1) {
                    Text("N")
                        .font(ArchiveTypography.editorialSerif(size: 10, weight: .semibold))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    Image(systemName: "safari")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(ArchivePalette.inkSecondary.opacity(0.65))
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CELESTIAL VOYAGE TOPOLOGY · 85°E — 125°E / 18°N — 50°N")
                        .font(ArchiveTypography.monoScale(size: 9.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Text("已点亮 \(clusters.count) 座城市")
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(height: 360)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.7)
        )
    }
}

// MARK: - 城市回忆抽屉弹窗 (CityMemoryDrawerSheet)

@MainActor
public struct CityMemoryDrawerSheet: View {
    let cityCode: String
    let cityName: String
    var onDismiss: () -> Void

    @State private var drawer: CityMemoryDrawerResponse?
    @State private var isLoading: Bool = true
    @State private var errorText: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(cityName) · 城市回忆抽屉")
                        .font(ArchiveTypography.editorialSerif(size: 18, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("行政代码 \(cityCode)")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                Spacer()
                Button("关闭") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            if isLoading {
                ProgressView("正在翻找属地散页与相纸…")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.accentWarm)
            } else if let d = drawer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("到访次数")
                                    .font(ArchiveTypography.bodySans(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Text("\(d.visitStats.totalVisits) 次")
                                    .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                            }
                            if !d.visitStats.firstVisitedAt.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("首访日期")
                                        .font(ArchiveTypography.bodySans(size: 11))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                    Text(d.visitStats.firstVisitedAt)
                                        .font(ArchiveTypography.monoScale(size: 13))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                }
                            }
                            if d.ledgerSummary.totalSpent > 0 {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("属地开销")
                                        .font(ArchiveTypography.bodySans(size: 11))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                    Text(FormatUtils.formattedYuan(cents: d.ledgerSummary.totalSpent, includeSymbol: true))
                                        .font(ArchiveTypography.monoScale(size: 14, weight: .semibold))
                                        .foregroundStyle(ArchivePalette.accentMoss)
                                }
                            }
                        }

                        if !d.entries.isEmpty {
                            Text("属地散页随笔 (\(d.entries.count))")
                                .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                            ForEach(d.entries) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(entry.title.isEmpty ? "散页手记" : entry.title)
                                            .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .medium))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                        Spacer()
                                        Text(entry.parsedDate.dotDate)
                                            .font(ArchiveTypography.monoScale(size: 10.5))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                    }
                                    Text(entry.content)
                                        .font(ArchiveTypography.bodySans(size: 12))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                        .lineLimit(3)
                                }
                                .padding(10)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(ArchivePalette.archivePaper)
        .task {
            do {
                drawer = try await APIClient.shared.fetchCityMemoryDrawer(cityCode: cityCode)
                isLoading = false
            } catch {
                errorText = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - 省级山河回忆抽屉弹窗 (ProvinceMemoryDrawerSheet)

@MainActor
public struct ProvinceMemoryDrawerSheet: View {
    let adcode: String
    let provinceName: String
    var onDismiss: () -> Void

    @State private var drawer: ProvinceMemoryDrawerResponse?
    @State private var isLoading: Bool = true
    @State private var errorText: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(provinceName) · 省级山河回忆抽屉")
                        .font(ArchiveTypography.editorialSerif(size: 18, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("行政代码前缀 \(adcode)")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                Spacer()
                Button("关闭") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            if isLoading {
                ProgressView("正在聚合全省行迹票根与属地手记…")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.accentWarm)
            } else if let d = drawer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("点亮城邑")
                                    .font(ArchiveTypography.bodySans(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Text("\(d.visitedCities.count) 座城")
                                    .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("总履迹篇幅")
                                    .font(ArchiveTypography.bodySans(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Text("\(d.footprints.count) 次")
                                    .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                            }
                            if d.ledgerSummary.totalSpent > 0 {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("省内花销")
                                        .font(ArchiveTypography.bodySans(size: 11))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                    Text(FormatUtils.formattedYuan(cents: d.ledgerSummary.totalSpent, includeSymbol: true))
                                        .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                                        .foregroundStyle(ArchivePalette.accentMoss)
                                }
                            }
                        }
                        .padding(12)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        if !d.visitedCities.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("到访城市分布")
                                    .font(ArchiveTypography.editorialSerif(size: 13, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                HStack(spacing: 6) {
                                    ForEach(d.visitedCities) { city in
                                        Text("\(city.cityName) (\(city.visitCount))")
                                            .font(ArchiveTypography.monoScale(size: 11))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(ArchivePalette.archiveSubtle)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                        }

                        if !d.entries.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("属地散页手记 (\(d.entries.count))")
                                    .font(ArchiveTypography.editorialSerif(size: 13, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)

                                ForEach(d.entries) { entry in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(entry.title.isEmpty ? "散页随笔" : entry.title)
                                                .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
                                                .foregroundStyle(ArchivePalette.inkPrimary)
                                            Spacer()
                                            Text(entry.parsedDate.dotDate)
                                                .font(ArchiveTypography.monoScale(size: 10.5))
                                                .foregroundStyle(ArchivePalette.inkMuted)
                                        }
                                        Text(entry.content)
                                            .font(ArchiveTypography.bodySans(size: 12))
                                            .foregroundStyle(ArchivePalette.inkSecondary)
                                            .lineLimit(3)
                                    }
                                    .padding(10)
                                    .background(ArchivePalette.archiveSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(ArchivePalette.archivePaper)
        .task {
            do {
                drawer = try await APIClient.shared.fetchProvinceMemoryDrawer(adcode: adcode)
                isLoading = false
            } catch {
                errorText = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - 年度生活年鉴五幕画卷弹窗 (AnnualAlmanacSheet)

@MainActor
public struct AnnualAlmanacSheet: View {
    var onDismiss: () -> Void

    @State private var selectedYear: Int = FormatUtils.beijingCurrentYearMonth().year
    @State private var almanac: AnnualAlmanacResponse?
    @State private var isLoading: Bool = true
    @State private var errorText: String?

    private var availableYears: [Int] {
        let currentYear = FormatUtils.beijingCurrentYearMonth().year
        let entryYears = AppState.shared.entries.compactMap { entry -> Int? in
            guard entry.occurredAt.count >= 4 else { return nil }
            return Int(entry.occurredAt.prefix(4))
        }
        let earliest = min(entryYears.min() ?? currentYear, currentYear)
        return Array((earliest...currentYear).reversed())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("《散页 · \(selectedYear) 年度生活年鉴》")
                        .font(ArchiveTypography.editorialSerif(size: 18, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("岁月卷首 · 山川行迹 · 心愿圆满 · 浮光掠影 · 柴米油盐")
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(availableYears, id: \.self) { yr in
                        PaperPillButton(title: "\(yr) 年", isSelected: selectedYear == yr) {
                            selectedYear = yr
                            Task { await loadAlmanac() }
                        }
                    }
                    Button("关闭") { onDismiss() }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            if isLoading {
                ProgressView("正在装订年度年鉴画卷…")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.accentWarm)
            } else if let a = almanac {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 第一幕：岁月卷首
                        HStack(spacing: 20) {
                            almanacStat("散页篇幅", "\(a.prologue.totalEntries) 篇")
                            almanacStat("点亮城市", "\(a.prologue.citiesVisited) 城")
                            almanacStat("圆满心愿", "\(a.prologue.wishesFulfilled) 愿")
                            almanacStat("记账笔数", "\(a.prologue.txCount) 笔")
                        }
                        .padding(12)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        // 第二幕：山川行迹
                        if !a.atlas.cities.isEmpty {
                            Text("第二幕 · 山川行迹 (\(a.atlas.totalCities) 城)")
                                .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                            Text(a.atlas.cities.map(\.cityName).joined(separator: " · "))
                                .font(ArchiveTypography.bodySans(size: 12.5))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                        }

                        // 第三幕：心愿圆满
                        Text("第三幕 · 心愿圆满 (已达成 \(a.wishes.fulfilledCount) / 在愿 \(a.wishes.wantingCount))")
                            .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))

                        // 第四幕：浮光掠影 · 四季流转
                        VStack(alignment: .leading, spacing: 6) {
                            Text("第四幕 · 浮光掠影 · 四季流转")
                                .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                seasonCard(title: "春生 · 春季篇", entry: a.highlights.spring, tint: ArchivePalette.accentMoss)
                                seasonCard(title: "夏长 · 夏季篇", entry: a.highlights.summer, tint: ArchivePalette.accentWarm)
                                seasonCard(title: "秋收 · 秋季篇", entry: a.highlights.autumn, tint: Color(red: 0.83, green: 0.53, blue: 0.02))
                                seasonCard(title: "冬藏 · 冬季篇", entry: a.highlights.winter, tint: ArchivePalette.inkSecondary)
                            }
                        }

                        // 第五幕：柴米油盐
                        if a.finances.totalExpense > 0 || a.finances.totalIncome > 0 {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("第五幕 · 柴米油盐")
                                    .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                                HStack(spacing: 18) {
                                    Text("总支出 \(FormatUtils.formattedYuan(cents: a.finances.totalExpense, includeSymbol: true))")
                                        .font(ArchiveTypography.monoScale(size: 12))
                                        .foregroundStyle(ArchivePalette.accentWarm)
                                    Text("总收入 \(FormatUtils.formattedYuan(cents: a.finances.totalIncome, includeSymbol: true))")
                                        .font(ArchiveTypography.monoScale(size: 12))
                                        .foregroundStyle(ArchivePalette.accentMoss)
                                    Text(String(format: "取悦自己占比 %.1f%%", a.finances.wishSpendingRatio))
                                        .font(ArchiveTypography.monoScale(size: 12))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(ArchivePalette.archivePaper)
        .task {
            await loadAlmanac()
        }
    }

    private func seasonCard(title: String, entry: LifeEntry?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(ArchiveTypography.monoScale(size: 10))
                .foregroundStyle(tint)
            if let entry {
                Text(entry.title.isEmpty ? "无题随笔" : entry.title)
                    .font(ArchiveTypography.editorialSerif(size: 12, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .lineLimit(1)
                if !entry.content.isEmpty {
                    Text(entry.content)
                        .font(ArchiveTypography.bodySans(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .lineLimit(2)
                }
            } else {
                Text("暂无季候留痕")
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func almanacStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(ArchiveTypography.bodySans(size: 11))
                .foregroundStyle(ArchivePalette.inkMuted)
            Text(value)
                .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
        }
    }

    private func loadAlmanac() async {
        isLoading = true
        errorText = nil
        do {
            almanac = try await APIClient.shared.fetchAnnualAlmanac(year: selectedYear)
            isLoading = false
        } catch {
            errorText = error.localizedDescription
            isLoading = false
        }
    }
}

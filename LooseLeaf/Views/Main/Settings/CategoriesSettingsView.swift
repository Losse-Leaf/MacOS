import SwiftUI

/// 分类字典（左侧菜单「分类字典」入口）：收支类别、随身装备、支付方式与造物分类管理
@MainActor
struct CategoriesSettingsView: View {
    @Bindable var appState: AppState

    // 分类字典管理状态
    @State private var authError: String?
    @State private var selectedCategoryScope: String = "expense"
    @State private var isAddingCategoryInline: Bool = false
    @State private var inlineCategoryName: String = ""
    @State private var allCategoriesList: [CategoryOption] = []

    private var currentDisplayCategories: [CategoryOption] {
        let matched = allCategoriesList.filter { $0.scope == selectedCategoryScope }
        if !matched.isEmpty { return matched }
        // 兜底保障：即使离线或初次加载也呈现默认分类，绝不留白
        let defaults: [String] = {
            switch selectedCategoryScope {
            case "expense": return appState.expenseCategories
            case "income": return appState.incomeCategories
            case "gear": return appState.gearCategories
            case "payment": return appState.paymentMethods
            case "project": return appState.projectCategories
            default: return []
            }
        }()
        return defaults.enumerated().map { index, name in
            CategoryOption(id: -(index + 1), scope: selectedCategoryScope, name: name, sortOrder: index, isBuiltin: true)
        }
    }
    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
            settingsFeedbackBanner(feedback: nil, error: authError)
            // 类目分类范围切换
            HStack(spacing: ArchiveSpacing.s) {
                ForEach([
                    ("expense", "支出类目"),
                    ("income", "收入类目"),
                    ("gear", "随身装备"),
                    ("payment", "支付方式"),
                    ("project", "造物分类")
                ], id: \.0) { scope, label in
                    PaperPillButton(
                        title: label,
                        isSelected: selectedCategoryScope == scope
                    ) {
                        selectedCategoryScope = scope
                    }
                }

                Spacer()
            }

            settingsCardSection(title: "字典词条管理", caption: "共 \(currentDisplayCategories.count) 个词条") {
                VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                    // 纸墨流式标签云
                    FlowTagLayout(spacing: ArchiveSpacing.s) {
                        ForEach(currentDisplayCategories) { cat in
                            HStack(spacing: ArchiveSpacing.xs) {
                                Text(cat.name)
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                                    .foregroundStyle(ArchivePalette.inkPrimary)

                                if cat.id > 0 {
                                    // 删除图标按钮：命中区不小于 ArchiveHitTarget.minPointer
                                    PaperIconButton(
                                        systemName: "xmark",
                                        label: "删除分类「\(cat.name)」",
                                        help: "删除分类「\(cat.name)」",
                                        size: 9,
                                        tint: ArchivePalette.inkMuted
                                    ) {
                                        deleteCategoryAction(cat)
                                    }
                                }
                            }
                            .padding(.horizontal, ArchiveSpacing.s)
                            .frame(minHeight: ArchiveHitTarget.minPointer, alignment: .leading)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(
                                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                        }

                        // 行内即时添加新分类
                        if isAddingCategoryInline {
                            HStack(spacing: ArchiveSpacing.xs) {
                                TextField("新分类…", text: $inlineCategoryName)
                                    .textFieldStyle(.plain)
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                                    .frame(width: 80)
                                    .accessibilityLabel("新分类名称")
                                    .onSubmit { submitInlineNewCategory() }

                                // 确认图标按钮：命中区不小于 ArchiveHitTarget.minPointer
                                PaperIconButton(
                                    systemName: "checkmark",
                                    label: "确认添加新分类",
                                    help: "确认添加新分类",
                                    size: 9,
                                    tint: ArchivePalette.accentWarm
                                ) {
                                    submitInlineNewCategory()
                                }

                                // 取消图标按钮：命中区不小于 ArchiveHitTarget.minPointer
                                PaperIconButton(
                                    systemName: "xmark",
                                    label: "取消添加新分类",
                                    help: "取消添加新分类",
                                    size: 9,
                                    tint: ArchivePalette.inkMuted
                                ) {
                                    isAddingCategoryInline = false
                                    inlineCategoryName = ""
                                }
                            }
                            .padding(.horizontal, ArchiveSpacing.xs)
                            .frame(minHeight: ArchiveHitTarget.minPointer)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(RoundedRectangle(cornerRadius: ArchiveRadius.xs).stroke(ArchivePalette.accentWarm, lineWidth: 0.8))
                        } else {
                            Button {
                                isAddingCategoryInline = true
                                inlineCategoryName = ""
                            } label: {
                                HStack(spacing: ArchiveSpacing.xs) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9, weight: .medium))
                                        .accessibilityHidden(true)
                                    Text("添加分类")
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                }
                                .padding(.horizontal, ArchiveSpacing.s)
                                .padding(.vertical, ArchiveSpacing.xs)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                .overlay(RoundedRectangle(cornerRadius: ArchiveRadius.xs).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("添加分类")
                        }
                    }
                }
                .padding(ArchiveCardMetrics.padding)
            }
        }
        .task {
            if appState.isPaired {
                allCategoriesList = (try? await APIClient.shared.fetchCategories()) ?? []
            }
        }
    }
    private func submitInlineNewCategory() {
        let name = inlineCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            isAddingCategoryInline = false
            return
        }
        Task { @MainActor in
            do {
                _ = try await APIClient.shared.addCategoryOption(scope: selectedCategoryScope, name: name)
                inlineCategoryName = ""
                isAddingCategoryInline = false
                await appState.loadConfigAndProfile()
                // 关键：必须刷新 AppState 的分类数组。
                // `loadConfigAndProfile` 只拉站点配置与档案，不碰分类；
                // 而 `loadCategories` 才写 `expenseCategories / incomeCategories …`，
                // 且它原先只在 `refreshAll` 里被调用 ——
                // 于是新增一个「咖啡」后，账本页的类目胶囊仍是旧列表，
                // 必须按 ⌘R 才生效。
                await appState.loadCategories()
                allCategoriesList = (try? await APIClient.shared.fetchCategories()) ?? []
            } catch {
                authError = "添加分类失败: \(error.localizedDescription)"
            }
        }
    }

    private func deleteCategoryAction(_ cat: CategoryOption) {
        // 关键（2026-10-25 修复）：删除词条接二次确认 —— 与删渠道/删设备/删快照同款守护，
        // 原先一点即删，正被账目/器物引用的词条误触即失。
        appState.askConfirm(
            title: "确认删除分类「\(cat.name)」？",
            message: "删除后，该类目将从字典移除；已使用该类目的既有记录不受影响，但新记录将无法再选择它。",
            confirmText: "删除分类",
            danger: true
        ) {
            Task { @MainActor in
                do {
                    try await APIClient.shared.deleteCategoryOption(id: cat.id)
                    await appState.loadConfigAndProfile()
                    // 同上：删掉分类后也要刷新 AppState 的分类数组
                    await appState.loadCategories()
                    allCategoriesList = (try? await APIClient.shared.fetchCategories()) ?? []
                } catch {
                    authError = "删除分类失败: \(error.localizedDescription)"
                }
            }
        }
    }

// MARK: - 流式自适应换行布局 (FlowTagLayout)

public struct FlowTagLayout: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        height = currentY + lineHeight
        return CGSize(width: width, height: max(height, 28))
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
}

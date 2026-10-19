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
        VStack(alignment: .leading, spacing: 18) {
            settingsFeedbackBanner(feedback: nil, error: authError)
            // 类目分类范围切换
            HStack(spacing: 6) {
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
                VStack(alignment: .leading, spacing: 12) {
                    // 纸墨流式标签云
                    FlowTagLayout(spacing: 8) {
                        ForEach(currentDisplayCategories) { cat in
                            HStack(spacing: 5) {
                                Text(cat.name)
                                    .font(ArchiveTypography.bodySans(size: 11.5))
                                    .foregroundStyle(ArchivePalette.inkPrimary)

                                if cat.id > 0 {
                                    Button {
                                        deleteCategoryAction(cat)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                        }

                        // 行内即时添加新分类
                        if isAddingCategoryInline {
                            HStack(spacing: 4) {
                                TextField("新分类…", text: $inlineCategoryName)
                                    .textFieldStyle(.plain)
                                    .font(ArchiveTypography.bodySans(size: 11.5))
                                    .frame(width: 80)
                                    .onSubmit { submitInlineNewCategory() }

                                Button { submitInlineNewCategory() } label: {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(ArchivePalette.accentWarm)
                                }
                                .buttonStyle(.plain)

                                Button { isAddingCategoryInline = false } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(ArchivePalette.accentWarm, lineWidth: 0.8))
                        } else {
                            Button {
                                isAddingCategoryInline = true
                                inlineCategoryName = ""
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 8, weight: .medium))
                                    Text("添加分类")
                                        .font(ArchiveTypography.bodySans(size: 11))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
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
                allCategoriesList = (try? await APIClient.shared.fetchCategories()) ?? []
            } catch {
                authError = "添加分类失败: \(error.localizedDescription)"
            }
        }
    }

    private func deleteCategoryAction(_ cat: CategoryOption) {
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteCategoryOption(id: cat.id)
                await appState.loadConfigAndProfile()
                allCategoriesList = (try? await APIClient.shared.fetchCategories()) ?? []
            } catch {
                authError = "删除分类失败: \(error.localizedDescription)"
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

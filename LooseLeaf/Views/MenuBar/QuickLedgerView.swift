import SwiftUI

/// 菜单栏极速记账界面 (QuickLedgerView)
/// 遵循 docs/macos.md §1 & §3.1 规范：
/// 支持“42.5 午餐咖啡”一句话语义快记（自动转为 4250 分整型）与大数字金额 + 大地色类目胶囊勾选
public struct QuickLedgerView: View {
    @Bindable var appState: AppState
    var onSubmitted: (() -> Void)?

    @State private var smartInput: String = ""
    @State private var amountString: String = ""
    @State private var titleString: String = ""
    @State private var selectedType: String = "expense"
    @State private var selectedCategory: String = "餐饮"
    @State private var selectedPayment: String = "微信支付"
    @State private var isSubmitting: Bool = false
    @State private var localError: String?

    @FocusState private var isSmartFieldFocused: Bool

    public init(appState: AppState, onSubmitted: (() -> Void)? = nil) {
        self.appState = appState
        self.onSubmitted = onSubmitted
    }

    private var resolvedQuickParsed: FormatUtils.QuickLedgerParsed? {
        if !smartInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return FormatUtils.parseQuickLedgerInput(smartInput, defaultCategory: selectedCategory)
        }
        guard let cents = FormatUtils.parseYuanToCents(amountString), cents > 0 else {
            return nil
        }
        let cleanTitle = titleString.trimmingCharacters(in: .whitespacesAndNewlines)
        return FormatUtils.QuickLedgerParsed(
            amountCents: cents,
            type: selectedType,
            category: selectedCategory,
            title: cleanTitle.isEmpty ? selectedCategory : cleanTitle
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. 一句话极速语义记账框
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("极速指令输入")
                        .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Spacer()
                    if let parsed = resolvedQuickParsed {
                        Text("\(parsed.type == "income" ? "+" : "-")\(FormatUtils.formattedYuan(cents: parsed.amountCents, includeSymbol: true)) · \(parsed.category)")
                            .font(ArchiveTypography.monoScale(size: 11, weight: .semibold))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }
                }

                TextField("输入如：42.5 午餐咖啡（自动识别金额与类目）", text: $smartInput)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: 13.5))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .focused($isSmartFieldFocused)
                    .padding(9)
                    .background(ArchivePalette.archivePaper)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                    )
                    .onSubmit {
                        submitLedger()
                    }
            }

            // 2. 分项精细录入与收支切换
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    PaperPillButton(title: "支出", isSelected: selectedType == "expense") {
                        selectedType = "expense"
                        AudioFeedback.shared.playTink()
                    }
                    PaperPillButton(title: "收入", isSelected: selectedType == "income") {
                        selectedType = "income"
                        AudioFeedback.shared.playTink()
                    }
                }

                HStack(spacing: 4) {
                    Text("¥")
                        .font(ArchiveTypography.monoScale(size: 13, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    TextField("0.00", text: $amountString)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.monoScale(size: 14, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .frame(width: 72)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )

                TextField("摘要说明（可选）", text: $titleString)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(ArchivePalette.archivePaper)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                    )
            }

            // 3. 常用类目胶囊网格
            VStack(alignment: .leading, spacing: 6) {
                Text("支出类目")
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(appState.expenseCategories, id: \.self) { category in
                        PaperPillButton(
                            title: category,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                            AudioFeedback.shared.playTink()
                        }
                    }
                }
            }

            // 4. 支付方式与提交栏
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(appState.paymentMethods, id: \.self) { method in
                            Button {
                                selectedPayment = method
                                AudioFeedback.shared.playTink()
                            } label: {
                                Text(method)
                                    .font(ArchiveTypography.bodySans(size: 11))
                                    .foregroundStyle(selectedPayment == method ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(selectedPayment == method ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                Button {
                    submitLedger()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 11))
                        Text(isSubmitting ? "入账中…" : "记入账本 ⌘↩")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(resolvedQuickParsed == nil || isSubmitting)
            }

            if let localError {
                Text(localError)
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            Divider()
                .overlay(ArchivePalette.borderSubtle)

            // 5. 本月收支微光谱概览
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(appState.transactionSummary.month) 月累计支出")
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Spacer()
                    Text(FormatUtils.formattedYuan(cents: appState.transactionSummary.totalExpense, includeSymbol: true))
                        .font(ArchiveTypography.monoScale(size: 12, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                }
                ExpenseSpectrumBar(summary: appState.transactionSummary, showLegend: false)
            }
        }
        .onAppear {
            isSmartFieldFocused = true
            if let firstPay = appState.paymentMethods.first {
                selectedPayment = firstPay
            }
        }
    }

    private func submitLedger() {
        guard let parsed = resolvedQuickParsed, !isSubmitting else { return }
        isSubmitting = true
        localError = nil

        Task {
            do {
                _ = try await appState.submitQuickLedger(
                    amountCents: parsed.amountCents,
                    type: parsed.type,
                    category: parsed.category,
                    title: parsed.title,
                    paymentMethod: selectedPayment
                )
                smartInput = ""
                amountString = ""
                titleString = ""
                isSubmitting = false
                onSubmitted?()
            } catch {
                localError = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

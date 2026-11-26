import SwiftUI

/// 顶部吸顶的单行自然语言快速记账条（隔离输入态；完整可视化表单与分期配置经由 Sheet 弹出）
@MainActor
struct LedgerComposerCard: View {
    @Bindable var appState: AppState
    @Binding var errorNotice: String?
    var onOpenDetailedForm: () -> Void

    @State private var quickLine: String = ""
    @State private var isSubmittingTx: Bool = false

    private var quickParsed: FormatUtils.QuickLedgerParsed? {
        let isIncome = quickLine.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+")
        return FormatUtils.parseQuickLedgerInput(
            quickLine,
            knownCategories: isIncome ? appState.incomeCategories : appState.expenseCategories
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.viewfinder")
                .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.subheadline))
                .foregroundStyle(ArchivePalette.accentWarm)
                .accessibilityHidden(true)

            TextField("快速记账（如：42.5 咖啡）…", text: $quickLine)
                .accessibilityLabel("快速记账输入")
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .onSubmit {
                    submitQuickLine()
                }

            Text(quickParsed.map { "\($0.category) · \(FormatUtils.formattedYuan(cents: $0.amountCents, includeSymbol: true))" } ?? "输入金额与摘要自动识别")
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.footnote, weight: .medium))
                .foregroundStyle(quickParsed != nil ? ArchivePalette.accentWarm : ArchivePalette.inkMuted.opacity(0.65))
                .lineLimit(1)
                .frame(width: 152, alignment: .trailing)

            Button {
                submitQuickLine()
            } label: {
                if isSubmittingTx {
                    ProgressView().controlSize(.small)
                } else {
                    Text("记入账本")
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .paperButtonFocusRing()
            .disabled(isSubmittingTx || quickParsed == nil)

            Button {
                onOpenDetailedForm()
            } label: {
                HStack(spacing: ArchiveSpacing.xs) {
                    Image(systemName: "slider.horizontal.below.rectangle")
                    Text("详细表单…")
                }
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.footnote))
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            .paperButtonFocusRing()
        }
        .padding(.horizontal, ArchiveCardMetrics.padding)
        .padding(.vertical, 10)
        .background(ArchivePalette.archiveSubtle.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.md)
                .stroke(ArchivePalette.borderSubtle.opacity(0.65), lineWidth: 0.5)
        )
    }

    private func submitQuickLine() {
        guard let parsed = quickParsed, !isSubmittingTx else { return }
        isSubmittingTx = true
        errorNotice = nil
        Task { @MainActor in
            defer { isSubmittingTx = false }
            do {
                _ = try await appState.submitQuickLedger(
                    amountCents: parsed.amountCents,
                    type: parsed.type,
                    category: parsed.category,
                    title: parsed.title
                )
                quickLine = ""
            } catch {
                errorNotice = error.localizedDescription
            }
        }
    }
}

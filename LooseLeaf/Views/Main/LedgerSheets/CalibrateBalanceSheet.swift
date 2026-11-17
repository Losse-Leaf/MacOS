import SwiftUI

/// 校准初始流动资金底数弹窗 (CalibrateBalanceSheet)
/// 隔离自身输入状态与焦点，并使用 `FormatUtils.parseYuanToCents(..., allowZero: true)` 杜绝浮点误差或非法输入误归零。
@MainActor
struct CalibrateBalanceSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var initialBalanceYuanInput: String
    @State private var isCalibratingBalance: Bool = false
    @State private var errorNotice: String?
    @FocusState private var isCalibrateFieldFocused: Bool

    init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
        let currentCents = appState.assetsOverview?.initialLiquidBalance ?? 0
        _initialBalanceYuanInput = State(initialValue: FormatUtils.formattedYuan(cents: currentCents))
    }

    var body: some View {
        PaperSheetScaffold(
            title: "校准初始流动资金底数",
            subtitle: "设定记账前的储蓄基准底数（元），系统将以此实时核算当前可用流动资金。",
            width: ArchiveSheetWidth.compact,
            isSubmitting: isCalibratingBalance,
            submitTitle: "保存基准 ⌘↩",
            onCancel: onDismiss,
            onSubmit: submitCalibrateBalance
        ) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                TextField("0.00", text: $initialBalanceYuanInput)
                    .accessibilityLabel("初始流动资金底数")
                    .textFieldStyle(.plain)
                    .focused($isCalibrateFieldFocused)
                    .font(ArchiveTypography.monoScale(size: 14))
                    .padding(9)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                            .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                    )

                if let errorNotice {
                    HStack(spacing: ArchiveSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text(errorNotice)
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }
                }
            }
        }
        .onAppear {
            isCalibrateFieldFocused = true
        }
    }

    private func submitCalibrateBalance() {
        guard !isCalibratingBalance else { return }
        let trimmed = initialBalanceYuanInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cents = trimmed.isEmpty ? 0 : FormatUtils.parseYuanToCents(trimmed, allowZero: true) else {
            errorNotice = "请输入有效的非负金额数字（支持最多两位小数）"
            return
        }
        isCalibratingBalance = true
        errorNotice = nil
        Task { @MainActor in
            defer { isCalibratingBalance = false }
            do {
                try await APIClient.shared.updateInitialLiquidBalance(cents: cents)
                await appState.loadTransactionsAndAssets(forceFull: false)
                onDismiss()
            } catch {
                errorNotice = error.localizedDescription
            }
        }
    }
}

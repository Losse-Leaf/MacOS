import SwiftUI

/// 添置随身设备弹窗 (AddGearSheet)
/// 从 LedgerAssetsView 中拆出的独立 Sheet 组件：
/// 负责登记随身器物与在役固资，并可伴生记录一笔支出流水。
/// 仅做文件拆分，逻辑、数值与视觉表现与拆分前完全一致。

// MARK: - 独立弹窗组件：添置随身设备 (AddGearSheet)

@MainActor
public struct AddGearSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var name: String = ""
    @State private var spec: String = ""
    @State private var category: String = "数码器材"
    @State private var priceYuan: String = ""
    @State private var note: String = ""
    @State private var createTransaction: Bool = true
    @State private var paymentMethod: String = "微信支付"
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
        // 支付方式默认取用户已配置的首选项，未配置时回落微信支付
        _paymentMethod = State(initialValue: appState.paymentMethods.first ?? "微信支付")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveCardMetrics.padding) {
            Text("添置随身器物与在役固资")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("设备名称", text: $name)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("规格参数", text: $spec)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            HStack(spacing: ArchiveSpacing.s) {
                PaperSelect(
                    selection: $category,
                    options: appState.gearCategories.map { PaperSelectOption(value: $0, label: $0) },
                    label: "器物分类："
                )

                HStack(spacing: ArchiveSpacing.xs) {
                    Text("¥")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption, weight: .bold))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    TextField("购入金额", text: $priceYuan)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading))
                }
                .padding(.horizontal, ArchiveSpacing.s)
                .frame(height: 32)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
            }

            Toggle("伴生记录一笔支出流水", isOn: $createTransaction)
                .toggleStyle(.paperCheckbox)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))

            TextField("手记", text: $note)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
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
                Button("添置并纳入大盘") {
                    submitAddGear()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
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

    private func submitAddGear() {
        let cents = FormatUtils.parseYuanToCents(priceYuan) ?? 0
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = AddGearAssetRequest(
                    name: name,
                    spec: spec.isEmpty ? nil : spec,
                    category: category,
                    priceCents: cents,
                    purchaseDate: FormatUtils.beijingDateString(),
                    note: note.isEmpty ? nil : note,
                    createTransaction: createTransaction,
                    paymentMethod: paymentMethod
                )
                _ = try await APIClient.shared.addGearAsset(req)
                // 器物在服务端会落一条伴生散页（时间流的一级数据），需连带刷新
                await appState.loadConfigAndProfile()
                await appState.loadTransactionsAndAssets(forceFull: false)
                await appState.loadEntries(forceFull: false)
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

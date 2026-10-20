import SwiftUI

/// 器材转让回血弹窗 (SellGearSheet)
/// 从 LedgerAssetsView 中拆出的独立 Sheet 组件：
/// 负责将随身设备转售归档并登记回血金额与流转手记。
/// 仅做文件拆分，逻辑、数值与视觉表现与拆分前完全一致。

// MARK: - 独立弹窗组件：转让回血 (SellGearSheet)

@MainActor
public struct SellGearSheet: View {
    let gear: GearItem
    var onDismiss: () -> Void
    var onSold: () -> Void

    @State private var soldPriceYuan: String = ""
    @State private var note: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveCardMetrics.padding) {
            Text("出闲置 · 转售器材回血")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text("转让设备：\(gear.name) (\(gear.spec ?? gear.category))")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .medium))
                .foregroundStyle(ArchivePalette.inkSecondary)

            if let boughtPrice = gear.priceCents, boughtPrice > 0 {
                Text("原购入成本：\(FormatUtils.formattedYuan(cents: boughtPrice, includeSymbol: true))")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            TextField("转售金额", text: $soldPriceYuan)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 14))
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("流转手记", text: $note)
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
                Button("确认转售归档") {
                    submitSell()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(isSubmitting || (FormatUtils.parseYuanToCents(soldPriceYuan) ?? 0) <= 0)
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

    private func submitSell() {
        guard let cents = FormatUtils.parseYuanToCents(soldPriceYuan), cents > 0 else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = SellGearRequest(
                    soldPriceCents: cents,
                    soldDate: FormatUtils.beijingDateString(),
                    note: note.isEmpty ? nil : note
                )
                _ = try await APIClient.shared.sellGearAsset(id: gear.id, req)
                onSold()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

import SwiftUI

/// 信贷分期渠道与期数共享配置区
/// 供 `LedgerComposerCard`、`AddGearSheet`、`EditTransactionSheet` 三处统一复用。
@MainActor
struct CreditChannelInstallmentSection: View {
    let channels: [CreditChannel]
    let hubURLString: String
    @Binding var isInstallment: Bool
    @Binding var channelCode: String
    @Binding var months: Int
    var amountCents: Int64? = nil
    var showToggle: Bool = true
    var toggleTitle: String = "分期付款"
    var isToggleDisabled: Bool = false
    var showEmptyHint: Bool = true
    var showCardChrome: Bool = false
    var onToggleChanged: ((Bool) -> Void)? = nil

    private var selectedChannel: CreditChannel? {
        channels.first { $0.code == channelCode }
    }

    private func normalizeChannelSelection() {
        guard let first = channels.first else { return }
        if !channels.contains(where: { $0.code == channelCode }) {
            channelCode = first.code
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            if showToggle {
                Toggle(toggleTitle, isOn: $isInstallment)
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .disabled(isToggleDisabled || channels.isEmpty)
                    .help(channels.isEmpty ? "请前往 Web 展厅后台「资产 → 渠道管理」配置分期渠道" : "")
                    .onChange(of: isInstallment) { _, isOn in
                        onToggleChanged?(isOn)
                        if isOn { normalizeChannelSelection() }
                    }
                    .onChange(of: channels) { _, _ in
                        if isInstallment { normalizeChannelSelection() }
                    }
            }

            if showEmptyHint && channels.isEmpty {
                HStack(spacing: 8) {
                    Text("请前往 Web 展厅后台「资产 → 渠道管理」配置分期渠道与每月还款日。")
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    if let hubURL = URL(string: hubURLString) {
                        Link("打开 Web 后台 ↗", destination: hubURL)
                            .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }
                }
            }

            if isInstallment && !channels.isEmpty {
                detailContent
            }
        }
        .onAppear {
            if isInstallment { normalizeChannelSelection() }
        }
        .onChange(of: channels) { _, _ in
            if isInstallment && !showToggle { normalizeChannelSelection() }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        let content = VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            HStack(spacing: ArchiveSpacing.s) {
                PaperSelect(
                    selection: $channelCode,
                    options: channels.map {
                        PaperSelectOption(value: $0.code, label: "\($0.name) (每月\($0.repaymentDay)日)")
                    },
                    label: "分期渠道："
                )

                PaperSelect(
                    selection: $months,
                    options: ArchiveInstallmentOptions.installmentOptions.map {
                        PaperSelectOption(value: $0, label: "\($0) 期")
                    },
                    label: "期数："
                )
            }

            HStack(spacing: ArchiveSpacing.m) {
                if let channel = selectedChannel {
                    Text("还款日跟随渠道：每月 \(channel.repaymentDay) 日")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                if let cents = amountCents {
                    let safeMonths = max(1, months)
                    let validInstallment = cents > 0 && months > 0
                    Text(
                        validInstallment
                            ? "每期 ¥\(FormatUtils.formattedYuan(cents: cents / Int64(safeMonths))) · 总额 ¥\(FormatUtils.formattedYuan(cents: cents))"
                            : "输入有效金额后自动核算每期应还"
                    )
                    .font(ArchiveTypography.monoScale(size: 11, weight: validInstallment ? .semibold : .regular))
                    .foregroundStyle(validInstallment ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                    .lineLimit(1)
                }
            }
        }

        if showCardChrome {
            content
                .padding(10)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
        } else {
            content
        }
    }
}

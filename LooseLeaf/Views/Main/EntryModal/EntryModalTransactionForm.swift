// EntryModalTransactionForm.swift
// 创作模态 · 账目形态表单
// 职责：独立子 View，只订阅草稿中与「账目」相关的字段，未选中时根本不会挂载。

import SwiftUI

/// 账目形态表单（支出 / 收入、信贷分期与固定资产同步）
struct EntryModalTransactionForm: View {
    @Bindable var draft: EntryDraft
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PaperSegmentedControl(
                    selection: $draft.txType,
                    items: [
                        PaperSegmentItem("expense", title: "支出", icon: "arrow.down.forward"),
                        PaperSegmentItem("income", title: "收入", icon: "arrow.up.forward")
                    ]
                )
                .frame(width: 160)

                HStack(spacing: 4) {
                    Text("金额：¥")
                        .font(ArchiveTypography.monoScale(size: 13, weight: .semibold))
                        .foregroundStyle(draft.txType == "income" ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                    TextField("0.00", text: $draft.txAmountYuan)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                }
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 12) {
                let cats = draft.txType == "income" ? appState.incomeCategories : appState.expenseCategories
                let catOptions = cats.map { PaperSelectOption(value: $0, label: $0) }
                PaperSelect(selection: $draft.txCategory, options: catOptions, label: "分类")

                let payOptions = appState.paymentMethods.map { PaperSelectOption(value: $0, label: $0) }
                PaperSelect(selection: $draft.txPaymentMethod, options: payOptions, label: "支付方式")

                PaperDatePicker(selection: $draft.occurredAt, enableTime: true, label: "发生时间")
            }

            // 关联心愿或足迹票根 (选填)
            HStack(spacing: 12) {
                if !appState.wishes.isEmpty {
                    let wishOptions: [PaperSelectOption<Int?>] = [PaperSelectOption(value: nil, label: "不关联心愿")] + appState.wishes.map { w in
                        PaperSelectOption(value: w.id as Int?, label: w.title, badge: w.status == "fulfilled" ? "已圆满" : nil)
                    }
                    PaperSelect(selection: $draft.selectedWishId, options: wishOptions, label: "圆满心愿")
                }

                if !appState.footprints.isEmpty {
                    let fpOptions: [PaperSelectOption<Int?>] = [PaperSelectOption(value: nil, label: "不关联足迹")] + appState.footprints.map { f in
                        PaperSelectOption(value: f.id as Int?, label: "\(f.cityName) · \(f.title ?? "行旅")")
                    }
                    PaperSelect(selection: $draft.selectedFootprintId, options: fpOptions, label: "旅途花销")
                }
            }

            EntryPaperField(
                placeholder: "备注（例：工作日咖啡与烘焙）",
                text: $draft.content,
                font: ArchiveTypography.bodySans(size: 13)
            )

            // 扩展选项：信贷分期与同步固定资产
            HStack(spacing: 16) {
                Toggle("信贷分期", isOn: $draft.isInstallment)
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: 12))

                Toggle("同步为随身/桌面固资", isOn: $draft.syncToGear)
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: 12))
            }

            if draft.isInstallment {
                HStack(spacing: 12) {
                    let channelOptions = appState.creditChannels.map { PaperSelectOption(value: $0.code, label: $0.name) }
                    PaperSelect(selection: $draft.installmentChannel, options: channelOptions, label: "渠道")

                    let monthOptions = [3, 6, 12, 24].map { PaperSelectOption(value: $0, label: "\($0) 期") }
                    PaperSelect(selection: $draft.installmentMonths, options: monthOptions, label: "期数")
                }
                .padding(8)
                .background(ArchivePalette.archiveSubtle.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if draft.syncToGear {
                HStack(spacing: 12) {
                    let gearCatOptions = appState.gearCategories.map { PaperSelectOption(value: $0, label: $0) }
                    PaperSelect(selection: $draft.gearCategory, options: gearCatOptions, label: "固资分类")

                    EntryPaperField(
                        placeholder: "规格参数（例：M3 Max / 64G）",
                        text: $draft.gearSpec,
                        font: ArchiveTypography.monoScale(size: 11.5),
                        padding: 6,
                        background: ArchivePalette.archivePaper,
                        cornerRadius: 4
                    )
                }
                .padding(8)
                .background(ArchivePalette.archiveSubtle.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

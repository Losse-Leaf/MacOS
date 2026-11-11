// GearAssetCardView.swift
// 随身器物与固定资产卡片组件 (GearAssetCardView)
// 职责：统一主理人档案与资产大盘两处的固资设备卡片展示与转让/删除操作

import SwiftUI

public struct GearAssetCardView: View {
    public let gear: GearItem
    public var onSell: ((GearItem) -> Void)?
    public var onDelete: ((GearItem) -> Void)?

    public init(
        gear: GearItem,
        onSell: ((GearItem) -> Void)? = nil,
        onDelete: ((GearItem) -> Void)? = nil
    ) {
        self.gear = gear
        self.onSell = onSell
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(gear.category)
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(ArchivePalette.archivePaper)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Spacer()

                Text(gear.status == "sold" ? "已转让回血" : "服役中")
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(gear.status == "sold" ? ArchivePalette.inkMuted : ArchivePalette.accentMoss)
            }

            Text(gear.name)
                .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(1)

            if let spec = gear.spec, !spec.isEmpty {
                Text(spec)
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .lineLimit(1)
            }

            HStack {
                if let price = gear.priceCents, price > 0 {
                    Text("购入 \(FormatUtils.formattedYuan(cents: price, includeSymbol: true))")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                if let sold = gear.soldPriceCents, sold > 0 {
                    Text("回血 \(FormatUtils.formattedYuan(cents: sold, includeSymbol: true))")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.accentMoss)
                }

                Spacer()

                if gear.status != "sold", let onSell {
                    Button("转让回血") {
                        onSell(gear)
                    }
                    .font(ArchiveTypography.bodySans(size: 10.5))
                    .buttonStyle(.plain)
                    .foregroundStyle(ArchivePalette.accentWarm)
                }

                if let onDelete {
                    PaperIconButton(
                        systemName: ArchiveIcon.delete.systemName,
                        label: "删除设备",
                        help: "删除设备",
                        size: 10.5,
                        tint: ArchivePalette.inkMuted
                    ) {
                        onDelete(gear)
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(ArchiveSpacing.m)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
        .paperHover()
        .contextMenu {
            if gear.status != "sold", let onSell {
                Button {
                    onSell(gear)
                } label: {
                    Label("转让回血", systemImage: "dollarsign.circle")
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete(gear)
                } label: {
                    Label("删除设备", systemImage: ArchiveIcon.delete.systemName)
                }
            }
            Divider()
            Button {
                NSPasteboard.general.clearContents()
                SecureClipboard.copy(gear.name)
            } label: {
                Label("拷贝设备名称", systemImage: "doc.on.doc")
            }
            if let spec = gear.spec, !spec.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    SecureClipboard.copy(spec)
                } label: {
                    Label("拷贝规格参数", systemImage: "doc.on.clipboard")
                }
            }
        }
    }
}

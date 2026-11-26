import SwiftUI

/// 支出类目光谱条 (Expense Spectrum Bar)
/// 注：本组件为「主应用与 Widget 扩展」共享组件。
public struct ExpenseSpectrumBar: View {
    public let summary: TransactionSummary
    public var showLegend: Bool

    public init(summary: TransactionSummary, showLegend: Bool = true) {
        self.summary = summary
        self.showLegend = showLegend
    }

    private static func normalizedWidths(ratios: [Double], availableWidth: CGFloat, minWidth: CGFloat = 2.0) -> [CGFloat] {
        guard !ratios.isEmpty, availableWidth > 0 else { return [] }
        let count = CGFloat(ratios.count)
        if availableWidth <= count * minWidth {
            let equal = availableWidth / count
            return Array(repeating: equal, count: ratios.count)
        }
        var widths = ratios.map { availableWidth * CGFloat(max(0, $0)) }
        var deficit: CGFloat = 0
        var shrinkableSum: CGFloat = 0
        for i in widths.indices {
            if widths[i] < minWidth {
                deficit += (minWidth - widths[i])
                widths[i] = minWidth
            } else {
                shrinkableSum += (widths[i] - minWidth)
            }
        }
        if deficit > 0, shrinkableSum > 0 {
            let scale = max(0, (shrinkableSum - deficit) / shrinkableSum)
            for i in widths.indices where widths[i] > minWidth {
                widths[i] = minWidth + (widths[i] - minWidth) * scale
            }
        }
        return widths
    }

    public var body: some View {
        let items = summary.sortedSpectrum
        let voiceSummary = items
            .map { "\($0.category) \(FormatUtils.formattedYuan(cents: $0.cents, includeSymbol: true))（\(Int(($0.ratio * 100).rounded()))%）" }
            .joined(separator: "，")

        return VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            if items.isEmpty {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ArchivePalette.borderSubtle)
                    .frame(height: 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("支出类目占比")
                    .accessibilityValue("本月暂无支出记录")
            } else {
                Canvas { context, size in
                    let spacing: CGFloat = 1.5
                    let totalSpacing = CGFloat(max(0, items.count - 1)) * spacing
                    let availableWidth = max(0, size.width - totalSpacing)
                    let widths = Self.normalizedWidths(
                        ratios: items.map(\.ratio),
                        availableWidth: availableWidth
                    )
                    var x: CGFloat = 0
                    for (index, item) in items.enumerated() where index < widths.count {
                        let width = widths[index]
                        let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                        context.fill(
                            Path(rect),
                            with: .color(ArchivePalette.categoryColor(for: item.category))
                        )
                        x += width + spacing
                    }
                }
                .frame(height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .help(voiceSummary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("支出类目占比")
                .accessibilityValue(voiceSummary)
            }

            if showLegend && !items.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 8)], alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.category) { item in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(ArchivePalette.categoryColor(for: item.category))
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                            Text(item.category)
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(FormatUtils.formattedYuan(cents: item.cents))
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.label))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

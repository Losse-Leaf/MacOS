import SwiftUI

/// 支出类目光谱条 (Expense Spectrum Bar)
/// 遵循 docs/macos.md §3.2.2 与 docs/web.md §2.3 大地色盘类目映射
/// 注：本组件为「主应用与 Widget 扩展」共享的纯展示组件（无 @State 等宏依赖）。
public struct ExpenseSpectrumBar: View {
    public let summary: TransactionSummary
    public var showLegend: Bool

    public init(summary: TransactionSummary, showLegend: Bool = true) {
        self.summary = summary
        self.showLegend = showLegend
    }

    public var body: some View {
        let items = summary.sortedSpectrum
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                if items.isEmpty {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ArchivePalette.borderSubtle)
                        .frame(height: 6)
                } else {
                    let totalSpacing = CGFloat(max(0, items.count - 1)) * 1.5
                    let availableWidth = max(0, geo.size.width - totalSpacing)
                    HStack(spacing: 1.5) {
                        ForEach(items, id: \.category) { item in
                            Rectangle()
                                .fill(ArchivePalette.categoryColor(for: item.category))
                                .frame(width: max(2, availableWidth * item.ratio), height: 6)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            .frame(height: 6)

            if showLegend && !items.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 8)], alignment: .leading, spacing: 6) {
                    ForEach(items.prefix(6), id: \.category) { item in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(ArchivePalette.categoryColor(for: item.category))
                                .frame(width: 6, height: 6)
                            Text(item.category)
                                .font(ArchiveTypography.bodySans(size: 11))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(FormatUtils.formattedYuan(cents: item.cents))
                                .font(ArchiveTypography.monoScale(size: 10.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }
                    }
                }
            }
        }
    }
}

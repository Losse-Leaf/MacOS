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
        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            if items.isEmpty {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ArchivePalette.borderSubtle)
                    .frame(height: 6)
            } else {
                // 比例布局：改用 Canvas 直接按 ratio 分配宽度，
                // 避免 GeometryReader 在 LazyVGrid 父容器中多触发一遍布局测量
                Canvas { context, size in
                    let spacing: CGFloat = 1.5
                    let totalSpacing = CGFloat(max(0, items.count - 1)) * spacing
                    let availableWidth = max(0, size.width - totalSpacing)
                    var x: CGFloat = 0
                    for item in items {
                        let width = max(2, availableWidth * item.ratio)
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
            }

            if showLegend && !items.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 8)], alignment: .leading, spacing: 6) {
                    ForEach(items.prefix(6), id: \.category) { item in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(ArchivePalette.categoryColor(for: item.category))
                                .frame(width: 6, height: 6)
                            Text(item.category)
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
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

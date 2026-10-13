import WidgetKit
import SwiftUI

public struct ExpenseWidgetEntry: TimelineEntry {
    public let date: Date
    public let summary: TransactionSummary
}

public struct ExpenseWidgetProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> ExpenseWidgetEntry {
        ExpenseWidgetEntry(
            date: Date(),
            summary: TransactionSummary(
                totalExpense: 248500,
                totalIncome: 500000,
                balance: 251500,
                categoryBreakdown: ["餐饮": 98000, "购物": 76000, "交通": 32500, "娱乐": 42000],
                count: 18
            )
        )
    }

    public func getSnapshot(in context: Context, completion: @escaping (ExpenseWidgetEntry) -> Void) {
        completion(buildEntry())
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<ExpenseWidgetEntry>) -> Void) {
        let entry = buildEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func buildEntry() -> ExpenseWidgetEntry {
        guard let snapshot = WidgetArchiveReader.loadSnapshot() else {
            return ExpenseWidgetEntry(date: Date(), summary: TransactionSummary())
        }
        return ExpenseWidgetEntry(
            date: Date(),
            summary: snapshot.transactionSummary
        )
    }
}

public struct ExpenseWidgetView: View {
    public let entry: ExpenseWidgetEntry

    public init(entry: ExpenseWidgetEntry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EXPENSE SPECTRUM")
                    .font(ArchiveTypography.monoScale(size: 9, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkMuted)
                Spacer()
                Text(String(format: "%04d.%02d", entry.summary.year, entry.summary.month))
                    .font(ArchiveTypography.monoScale(size: 10))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            Text(FormatUtils.formattedYuan(cents: entry.summary.totalExpense, includeSymbol: true))
                .font(ArchiveTypography.editorialSerif(size: 20, weight: .bold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            ExpenseSpectrumBar(summary: entry.summary, showLegend: false)

            Spacer(minLength: 0)

            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
                Text("快速记账 (⌘⇧L)")
                    .font(ArchiveTypography.monoScale(size: 10))
                    .foregroundStyle(ArchivePalette.inkSecondary)
            }
        }
        .padding(14)
        .widgetURL(URL(string: "looseleaf://ledger"))
        .containerBackground(for: .widget) {
            ArchivePalette.archivePaper
        }
    }
}

public struct ExpenseWidget: Widget {
    public let kind: String = "com.looseleaf.widget.expense"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExpenseWidgetProvider()) { entry in
            ExpenseWidgetView(entry: entry)
        }
        .configurationDisplayName("柴米油盐光谱")
        .description("实时呈现当月开支总额与分类大地色光谱。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

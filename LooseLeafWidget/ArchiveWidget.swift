import WidgetKit
import SwiftUI

public struct ArchiveWidgetEntry: TimelineEntry {
    public let date: Date
    public let curatorStatus: String
    public let latestTitle: String
    public let latestBody: String
    public let latestDateText: String
    public let totalEntries: Int
}

public struct ArchiveWidgetProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> ArchiveWidgetEntry {
        defaultEntry()
    }

    public func getSnapshot(in context: Context, completion: @escaping (ArchiveWidgetEntry) -> Void) {
        completion(buildEntry())
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<ArchiveWidgetEntry>) -> Void) {
        let entry = buildEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func buildEntry() -> ArchiveWidgetEntry {
        guard let snapshot = WidgetArchiveReader.loadSnapshot() else {
            return defaultEntry()
        }
        let latest = snapshot.entries.first(where: { $0.deletedAt == nil })
        let title = latest?.title.isEmpty == false ? latest!.title : "散页手稿"
        let body = latest?.content ?? "点击呼出活页集，记录今日的第一笔手稿。"
        let status = !snapshot.profile.motto.isEmpty
            ? snapshot.profile.motto
            : (!snapshot.profile.currentCity.isEmpty ? snapshot.profile.currentCity : "归档在线")
        let dateText = latest.map { $0.parsedDate.dotDate } ?? FormatUtils.formatBeijingDate(Date()).dotDate
        return ArchiveWidgetEntry(
            date: Date(),
            curatorStatus: status,
            latestTitle: title,
            latestBody: body,
            latestDateText: dateText,
            totalEntries: snapshot.stats.totalEntries
        )
    }

    private func defaultEntry() -> ArchiveWidgetEntry {
        ArchiveWidgetEntry(
            date: Date(),
            curatorStatus: "活页归档",
            latestTitle: "Loose-Leaf · 活页集",
            latestBody: "点击记录今日灵感、影像或日常开支。",
            latestDateText: FormatUtils.formatBeijingDate(Date()).dotDate,
            totalEntries: 0
        )
    }
}

public struct ArchiveWidgetView: View {
    public let entry: ArchiveWidgetEntry

    public init(entry: ArchiveWidgetEntry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LIVING ARCHIVE")
                    .font(ArchiveTypography.monoScale(size: 9, weight: .semibold))
                    .foregroundStyle(ArchivePalette.accentWarm)
                Spacer()
                Text(entry.latestDateText)
                    .font(ArchiveTypography.monoScale(size: 9))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            Text(entry.latestTitle)
                .font(ArchiveTypography.editorialSerif(size: 14, weight: .bold))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(1)

            Text(entry.latestBody)
                .font(ArchiveTypography.bodySans(size: 12))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .lineLimit(3)

            Spacer(minLength: 0)

            HStack {
                Circle()
                    .fill(ArchivePalette.accentMoss)
                    .frame(width: 6, height: 6)
                Text(entry.curatorStatus)
                    .font(ArchiveTypography.monoScale(size: 10))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
                Spacer()
                Text("\(entry.totalEntries) 篇")
                    .font(ArchiveTypography.monoScale(size: 10))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }
        }
        .padding(14)
        .widgetURL(URL(string: "looseleaf://entry"))
        .containerBackground(for: .widget) {
            ArchivePalette.archivePaper
        }
    }
}

public struct ArchiveWidget: Widget {
    public let kind: String = "com.looseleaf.widget.archive"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ArchiveWidgetProvider()) { entry in
            ArchiveWidgetView(entry: entry)
        }
        .configurationDisplayName("散页今日脉搏")
        .description("展示今日手稿摘录与主理人实时状态。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

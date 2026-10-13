import WidgetKit
import SwiftUI

public struct MemoryWidgetEntry: TimelineEntry {
    public let date: Date
    public let entryId: Int
    public let title: String
    public let caption: String
    public let locationText: String
    public let dateText: String
}

public struct MemoryWidgetProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> MemoryWidgetEntry {
        defaultEntry()
    }

    public func getSnapshot(in context: Context, completion: @escaping (MemoryWidgetEntry) -> Void) {
        completion(buildEntry())
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<MemoryWidgetEntry>) -> Void) {
        let entry = buildEntry()
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func buildEntry() -> MemoryWidgetEntry {
        guard let snapshot = WidgetArchiveReader.loadSnapshot() else {
            return defaultEntry()
        }
        let photoEntries = snapshot.entries.filter { $0.deletedAt == nil && !$0.attachments.isEmpty }
        guard let chosen = photoEntries.first ?? snapshot.entries.first(where: { $0.deletedAt == nil }) else {
            return defaultEntry()
        }
        return MemoryWidgetEntry(
            date: Date(),
            entryId: chosen.id,
            title: chosen.title.isEmpty ? "暗房影像手稿" : chosen.title,
            caption: chosen.content,
            locationText: chosen.location ?? chosen.cityName ?? "DARKROOM ARCHIVE",
            dateText: chosen.parsedDate.dotDate
        )
    }

    private func defaultEntry() -> MemoryWidgetEntry {
        MemoryWidgetEntry(
            date: Date(),
            entryId: 0,
            title: "暗房冲印记忆",
            caption: "将照片拖入 Loose-Leaf 暗房工作台，自动提取 EXIF 并装裱入册。",
            locationText: "35MM FILM FRAME",
            dateText: FormatUtils.formatBeijingDate(Date()).dotDate
        )
    }
}

public struct MemoryWidgetView: View {
    public let entry: MemoryWidgetEntry

    public init(entry: MemoryWidgetEntry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
                Text("DARKROOM MEMORY")
                    .font(ArchiveTypography.monoScale(size: 9, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkMuted)
                Spacer()
                Text(entry.dateText)
                    .font(ArchiveTypography.monoScale(size: 9))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .bold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .lineLimit(1)

                Text(entry.caption)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .lineLimit(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(ArchivePalette.archiveSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(ArchivePalette.borderSubtle, lineWidth: 1)
            )

            Spacer(minLength: 0)

            HStack {
                Text(entry.locationText)
                    .font(ArchiveTypography.monoScale(size: 9))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(14)
        .widgetURL(URL(string: "looseleaf://entry/\(entry.entryId)"))
        .containerBackground(for: .widget) {
            ArchivePalette.archivePaper
        }
    }
}

public struct MemoryWidget: Widget {
    public let kind: String = "com.looseleaf.widget.memory"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemoryWidgetProvider()) { entry in
            MemoryWidgetView(entry: entry)
        }
        .configurationDisplayName("暗房记忆画框")
        .description("以装裱相纸形式轮播往期精选影像手稿。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

import SwiftUI

/// 城市回忆抽屉弹窗 (CityMemoryDrawerSheet)
/// 聚合展示该行政城市的：到访统计、属地开销光谱、历次驻足票根、属地相纸底片及散页随笔。

@MainActor
public struct CityMemoryDrawerSheet: View {
    let cityCode: String
    let cityName: String
    var onSelectEntry: ((LifeEntry) -> Void)?
    var onDismiss: () -> Void

    @State private var drawer: CityMemoryDrawerResponse?
    @State private var isLoading: Bool = true
    @State private var errorText: String?

    public init(
        cityCode: String,
        cityName: String,
        onSelectEntry: ((LifeEntry) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.cityCode = cityCode
        self.cityName = cityName
        self.onSelectEntry = onSelectEntry
        self.onDismiss = onDismiss
    }

    private func collectedAttachments(from d: CityMemoryDrawerResponse) -> [Attachment] {
        var seen = Set<Int>()
        var result: [Attachment] = []
        for fp in d.footprints {
            for att in fp.attachments where seen.insert(att.id).inserted {
                result.append(att)
            }
        }
        for entry in d.entries {
            for att in entry.attachments where seen.insert(att.id).inserted {
                result.append(att)
            }
        }
        return result
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveCardMetrics.padding) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(cityName) · 城市回忆抽屉")
                        .font(ArchiveTypography.editorialSerif(size: 18, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("行政代码 \(cityCode)")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                Spacer()
                Button("关闭") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
                    .keyboardShortcut(.cancelAction)
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            if isLoading {
                ProgressView("正在翻找属地散页与相纸…")
                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 420)
            } else if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .lineLimit(8)
                    .clipped()
                    .frame(minHeight: 220, maxHeight: 420, alignment: .topLeading)
            } else if let d = drawer {
                let photos = collectedAttachments(from: d)
                ScrollView {
                    VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
                        // 1. 城市大盘概览
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                Text("到访次数")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Text("\(d.visitStats.totalVisits) 次")
                                    .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                            }
                            if !d.visitStats.firstVisitedAt.isEmpty {
                                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                    Text("首访日期")
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                    Text(d.visitStats.firstVisitedAt)
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                }
                            }
                            if !d.visitStats.latestVisitedAt.isEmpty,
                               d.visitStats.latestVisitedAt != d.visitStats.firstVisitedAt {
                                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                    Text("最近驻足")
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                    Text(d.visitStats.latestVisitedAt)
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                }
                            }
                            if d.ledgerSummary.totalSpent > 0 {
                                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                    Text("属地开销 (\(d.ledgerSummary.transactionCount) 笔)")
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                    Text(FormatUtils.formattedYuan(cents: d.ledgerSummary.totalSpent, includeSymbol: true))
                                        .font(ArchiveTypography.monoScale(size: 14, weight: .semibold))
                                        .foregroundStyle(ArchivePalette.accentMoss)
                                }
                            }
                        }

                        if !d.ledgerSummary.categories.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(d.ledgerSummary.categories) { cat in
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(ArchivePalette.categoryColor(for: cat.name))
                                                .frame(width: 6, height: 6)
                                            Text("\(cat.name) \(FormatUtils.formattedYuan(cents: cat.amount, includeSymbol: true))")
                                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                                .foregroundStyle(ArchivePalette.inkSecondary)
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(ArchivePalette.archiveSubtle)
                                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                    }
                                }
                            }
                        }

                        // 2. 属地影像底片长廊
                        if !photos.isEmpty {
                            VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                                Text("属地影像相纸 (\(photos.count))")
                                    .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: ArchiveSpacing.s) {
                                        ForEach(photos) { att in
                                            let intrinsic: CGSize? = {
                                                if let w = att.width, let h = att.height, w > 0, h > 0 {
                                                    return CGSize(width: w, height: h)
                                                }
                                                return nil
                                            }()
                                            FilmFrameView(
                                                imageURL: URL(string: att.thumbnailUrl ?? att.url),
                                                originalURL: URL(string: att.url),
                                                preferredFilename: att.originalFilename,
                                                intrinsicSize: intrinsic,
                                                maxHeight: 110
                                            )
                                            .frame(maxWidth: 180)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }

                        // 3. 历次驻足票根
                        if !d.footprints.isEmpty {
                            VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                                Text("历次驻足票根 (\(d.footprints.count))")
                                    .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)

                                ForEach(d.footprints) { fp in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text((fp.title?.isEmpty == false) ? fp.title! : "\(fp.cityName) · 驻足印记")
                                                .font(ArchiveTypography.editorialSerif(size: 13, weight: .medium))
                                                .foregroundStyle(ArchivePalette.inkPrimary)
                                            if fp.isPrivate == true {
                                                Image(systemName: "lock.fill")
                                                    .font(.system(size: 9.5))
                                                    .foregroundStyle(ArchivePalette.inkMuted)
                                                    .accessibilityLabel("私密行迹")
                                            }
                                            Spacer()
                                            let visitedDot = FormatUtils.parseOccurredDate(fp.visitedAt).dotDate
                                            let dateLabel: String = {
                                                if let dep = fp.departedAt, !dep.isEmpty {
                                                    return "\(visitedDot) — \(FormatUtils.parseOccurredDate(dep).dotDate)"
                                                }
                                                return visitedDot
                                            }()
                                            Text(dateLabel)
                                                .font(ArchiveTypography.monoScale(size: 10.5))
                                                .foregroundStyle(ArchivePalette.inkMuted)
                                        }
                                        if let note = fp.note, !note.isEmpty {
                                            EditorialProseTextView(
                                                note,
                                                font: ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body),
                                                color: ArchivePalette.inkSecondary,
                                                lineSpacing: 2,
                                                lineLimit: 2
                                            )
                                        }
                                    }
                                    .padding(9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(ArchivePalette.archiveSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                                    )
                                }
                            }
                        }

                        // 4. 属地散页随笔
                        if !d.entries.isEmpty {
                            VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                                Text("属地散页随笔 (\(d.entries.count))")
                                    .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)

                                ForEach(d.entries) { entry in
                                    Button {
                                        onSelectEntry?(entry)
                                    } label: {
                                        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                                            HStack(spacing: 6) {
                                                Text(entry.title.isEmpty ? "散页手记" : entry.title)
                                                    .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .medium))
                                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                                if entry.isPrivate {
                                                    Image(systemName: "lock.fill")
                                                        .font(.system(size: 9.5))
                                                        .foregroundStyle(ArchivePalette.inkMuted)
                                                        .accessibilityLabel("私密散页")
                                                }
                                                Spacer()
                                                Text(entry.parsedDate.dotDate)
                                                    .font(ArchiveTypography.monoScale(size: 10.5))
                                                    .foregroundStyle(ArchivePalette.inkMuted)
                                            }
                                            EditorialProseTextView(
                                                entry.content,
                                                font: ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body),
                                                color: ArchivePalette.inkSecondary,
                                                lineSpacing: 3,
                                                lineLimit: 3
                                            )
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(ArchivePalette.archiveSubtle)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .paperHover()
                                    .paperButtonFocusRing()
                                }
                            }
                        } else if d.footprints.isEmpty {
                            ArchiveEmptyState(
                                systemName: ArchiveIcon.detail.systemName,
                                title: "尚未沉淀属地散页",
                                message: "可在时间流中补记一段带有该城市定位的漫游手记。"
                            )
                            .frame(minHeight: 120)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(minHeight: 220, maxHeight: 440)
            } else {
                ArchiveEmptyState(
                    systemName: ArchiveIcon.detail.systemName,
                    title: "暂无该城市的回忆抽屉",
                    message: "这座城市尚未沉淀公开或私密散页，可在时间流中补记一段漫游手记。"
                )
                .frame(minHeight: 220, maxHeight: 420)
            }
        }
        .padding(22)
        .frame(
            minWidth: ArchiveSheetWidth.wide,
            idealWidth: ArchiveSheetWidth.wide,
            maxWidth: ArchiveSheetWidth.wide
        )
        .background(ArchivePalette.archivePaper)
        .task {
            do {
                drawer = try await APIClient.shared.fetchCityMemoryDrawer(cityCode: cityCode)
                isLoading = false
            } catch {
                errorText = error.localizedDescription
                isLoading = false
            }
        }
    }
}

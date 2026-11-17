import SwiftUI

/// 山川印谱独立主视图 (TravelAtlasView)
/// 1. 标头：“山川印谱 · 典藏行迹票根”，动态统计点亮城市与足迹总数
/// 2. 典藏票根架与城市回忆抽屉 (CityMemoryDrawerSheet)，支持 ⌘K 精准拉起抽屉与 ⌘Z 撤销删除
@MainActor
public struct TravelAtlasView: View {
    @Bindable var appState: AppState

    @State private var showNewFootprintSheet: Bool = false
    @State private var editingFootprint: Footprint?
    @State private var selectedDrawerCity: DrawerCitySelection?
    @State private var errorMessage: String?

    public init(appState: AppState) {
        self.appState = appState
    }

    private var litCityCodes: Set<String> {
        Set(appState.footprints.map { $0.cityCode })
    }

    private var litCitiesCount: Int {
        litCityCodes.count
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ArchiveSpacing.xl) {
                headerSection

                if let err = errorMessage {
                    Text(err)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }

                ticketsSection
            }
            .padding(ArchiveSpacing.xl)
        }
        .onAppear {
            consumeHighlightedCityIfNeeded()
        }
        .onChange(of: appState.navigation.highlightedFootprintCity) { _, _ in
            consumeHighlightedCityIfNeeded()
        }
        .sheet(isPresented: $showNewFootprintSheet) {
            FootprintEditorSheet(appState: appState) {
                showNewFootprintSheet = false
            }
        }
        .sheet(item: $editingFootprint) { fp in
            FootprintEditorSheet(appState: appState, footprint: fp) {
                editingFootprint = nil
            }
        }
        .sheet(item: $selectedDrawerCity) { sel in
            CityMemoryDrawerSheet(
                cityCode: sel.code,
                cityName: sel.name,
                onSelectEntry: { entry in
                    selectedDrawerCity = nil
                    appState.highlightedEntry = entry
                }
            ) {
                selectedDrawerCity = nil
            }
        }
    }

    private func consumeHighlightedCityIfNeeded() {
        guard let target = appState.navigation.highlightedFootprintCity else { return }
        selectedDrawerCity = DrawerCitySelection(code: target.code, name: target.name)
        appState.navigation.highlightedFootprintCity = nil
    }

    // MARK: - 1. 标头
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: ArchiveSpacing.s) {
                    Text("山川印谱")
                        .font(ArchiveTypography.editorialSerif(size: 24, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("典藏行迹票根")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                Text("累计点亮 \(litCitiesCount) 座城市 · 沉淀 \(appState.footprints.count) 程漫游足迹")
                    .font(ArchiveTypography.editorialSerif(size: 12.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
            }

            Spacer()

            Button {
                showNewFootprintSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "location.fill.viewfinder")
                        .font(.system(size: 11, weight: .medium))
                    Text("点亮城市足迹")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .paperButtonFocusRing()
        }
    }

    // MARK: - 2. 典藏票根架
    private var ticketsSection: some View {
        VStack(alignment: .leading, spacing: ArchiveCardMetrics.padding) {
            if appState.isLoading && appState.footprints.isEmpty {
                ProgressView("正在打捞行迹票根…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if appState.footprints.isEmpty {
                emptyPlaceholder
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: ArchiveCardMetrics.padding), GridItem(.flexible(), spacing: ArchiveCardMetrics.padding)], spacing: ArchiveCardMetrics.padding) {
                    ForEach(appState.footprints) { fp in
                        let visitedDot = FormatUtils.parseOccurredDate(fp.visitedAt).dotDate
                        let dateRangeText: String = {
                            if let dep = fp.departedAt, !dep.isEmpty {
                                let depDot = FormatUtils.parseOccurredDate(dep).dotDate
                                if depDot != visitedDot {
                                    return "\(visitedDot)\n— \(depDot)"
                                }
                            }
                            return visitedDot
                        }()
                        let countValue = fp.entriesCount ?? 0

                        ZStack(alignment: .topTrailing) {
                            Button {
                                selectedDrawerCity = DrawerCitySelection(code: fp.cityCode, name: fp.cityName)
                            } label: {
                                HStack(spacing: 0) {
                                    // 左联：目的地存根
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 4) {
                                            Text(fp.cityName)
                                                .font(ArchiveTypography.editorialSerif(size: 17, weight: .semibold))
                                                .foregroundStyle(ArchivePalette.inkPrimary)
                                                .lineLimit(1)
                                            if fp.isPrivate == true {
                                                Image(systemName: "lock.fill")
                                                    .font(.system(size: 9.5))
                                                    .foregroundStyle(ArchivePalette.inkMuted)
                                                    .accessibilityLabel("私密行迹")
                                            }
                                        }
                                        Text(dateRangeText)
                                            .font(ArchiveTypography.monoScale(size: 10.5))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                            .lineLimit(2)
                                        Spacer(minLength: 4)
                                        Text(countValue > 0 ? "散页 \(countValue) 篇" : "尚未关联散页")
                                            .font(ArchiveTypography.monoScale(size: 10.5))
                                            .foregroundStyle(countValue > 0 ? ArchivePalette.accentMoss : ArchivePalette.inkMuted)
                                    }
                                    .frame(width: 112, alignment: .leading)
                                    .padding(ArchiveSpacing.m)

                                    // 齿孔虚线
                                    Path { p in
                                        p.move(to: CGPoint(x: 0.5, y: 0))
                                        p.addLine(to: CGPoint(x: 0.5, y: 1000))
                                    }
                                    .stroke(ArchivePalette.borderDivider, style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                                    .frame(width: 1)
                                    .clipped()
                                    .padding(.vertical, ArchiveSpacing.s)

                                    // 右联：游记正券
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text((fp.title?.isEmpty == false) ? fp.title! : "\(fp.cityName) · 行旅手记")
                                                .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .medium))
                                                .foregroundStyle(ArchivePalette.inkPrimary)
                                                .lineLimit(1)
                                                .padding(.trailing, 60)
                                            Spacer()
                                        }

                                        EditorialProseTextView(
                                            (fp.note?.isEmpty == false) ? fp.note! : "行至此处，留下一纸驻足印记。",
                                            font: ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body),
                                            color: ArchivePalette.inkSecondary,
                                            lineSpacing: 2,
                                            lineLimit: 2
                                        )

                                        Spacer(minLength: 4)

                                        HStack {
                                            if let spent = fp.totalSpent, spent > 0 {
                                                Text("旅途花销 \(FormatUtils.formattedYuan(cents: spent, includeSymbol: true))")
                                                    .font(ArchiveTypography.monoScale(size: 10.5))
                                                    .foregroundStyle(ArchivePalette.accentWarm)
                                            }
                                            Spacer()
                                            Text("城市抽屉 →")
                                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                                .foregroundStyle(ArchivePalette.inkMuted)
                                        }
                                    }
                                    .padding(ArchiveSpacing.m)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(minHeight: 115)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                                .overlay(
                                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                                        .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .paperButtonFocusRing(cornerRadius: ArchiveRadius.sm)
                            .accessibilityLabel("\(fp.cityName) 票根，\(fp.title ?? "行旅手记")")
                            .accessibilityHint("打开该城市的回忆抽屉")
                            .paperHover()
                            .contextMenu {
                                Button {
                                    selectedDrawerCity = DrawerCitySelection(code: fp.cityCode, name: fp.cityName)
                                } label: {
                                    Label("打开城市回忆抽屉", systemImage: "folder")
                                }
                                Button {
                                    editingFootprint = fp
                                } label: {
                                    Label("修订足迹票根", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    appState.askConfirm(
                                        title: "确认删除该座城市足迹票根？",
                                        message: "删除后将移除该次漫游记录，关联游记散页不受影响，可按 ⌘Z 撤销。",
                                        confirmText: "删除足迹票根",
                                        danger: true
                                    ) {
                                        deleteFootprint(fp)
                                    }
                                } label: {
                                    Label("删除足迹票根", systemImage: ArchiveIcon.delete.systemName)
                                }
                                Divider()
                                Button {
                                    SecureClipboard.copy(fp.cityName)
                                    appState.showTemporaryBanner("已拷贝城市名称至剪贴板")
                                } label: {
                                    Label("拷贝城市名称", systemImage: "doc.on.doc")
                                }
                                if let note = fp.note, !note.isEmpty {
                                    Button {
                                        SecureClipboard.copy(note)
                                        appState.showTemporaryBanner("已拷贝行旅手记至剪贴板")
                                    } label: {
                                        Label("拷贝行旅手记", systemImage: "text.quote")
                                    }
                                }
                            }

                            HStack(spacing: ArchiveSpacing.xs) {
                                PaperIconButton(
                                    systemName: "pencil",
                                    label: "修订该座城市足迹票根",
                                    help: "修订票根",
                                    size: 10.5,
                                    tint: ArchivePalette.inkMuted
                                ) {
                                    editingFootprint = fp
                                }

                                PaperIconButton(
                                    systemName: ArchiveIcon.delete.systemName,
                                    label: "删除该座城市足迹票根",
                                    help: "删除票根",
                                    size: 10.5,
                                    tint: ArchivePalette.inkMuted
                                ) {
                                    appState.askConfirm(
                                        title: "确认删除该座城市足迹票根？",
                                        message: "删除后将移除该次漫游记录，关联游记散页不受影响，可按 ⌘Z 撤销。",
                                        confirmText: "删除足迹票根",
                                        danger: true
                                    ) {
                                        deleteFootprint(fp)
                                    }
                                }
                            }
                            .padding(.top, 6)
                            .padding(.trailing, 8)
                        }
                    }
                }
            }
        }
    }

    private var emptyPlaceholder: some View {
        ArchiveEmptyState(
            systemName: ArchiveIcon.atlas.systemName,
            title: "行迹票根架尚待启程",
            message: "在时间流记录带城市的游记或点击上方「点亮城市足迹」，均会自动沉淀特种纸票根。",
            primaryTitle: "点亮城市足迹",
            primaryAction: { showNewFootprintSheet = true }
        )
        .frame(minHeight: 180)
    }

    private func deleteFootprint(_ fp: Footprint) {
        errorMessage = nil
        Task { @MainActor in
            do {
                try await appState.deleteFootprintAction(fp)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#if DEBUG
#Preview("山川印谱") {
    TravelAtlasView(appState: ArchivePreviewFixtures.makeAppState())
        .frame(width: 1100, height: 760)
}
#endif

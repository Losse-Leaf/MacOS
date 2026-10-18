import SwiftUI

/// 山川印谱独立主视图 (TravelAtlasView)
/// 严格 1:1 对标 Web 端 `web/src/components/TravelAtlasView.vue`：
/// 1. 标头：“山川印谱 · 行迹百宝格与典藏票根”，动态统计点亮城市与足迹总数
/// 2. 34 省印谱矩阵百宝格：按七大区（华北/东北/华东/中南/西南/西北/港澳台）钤印陈列
/// 3. 双模式切换：百宝格印谱 vs 典藏票根 vs 经纬星野
/// 4. 城市回忆抽屉 (CityMemoryDrawerSheet) 与省级回忆抽屉
@MainActor
public struct TravelAtlasView: View {
    @Bindable var appState: AppState

    @State private var viewMode: Int = 0 // 0: 百宝格印谱, 1: 典藏票根, 2: 经纬星野
    @State private var selectedRegion: String = "all" // all, 华北, 东北, 华东, 中南, 西南, 西北, 港澳台
    @State private var sealFilter: String = "all" // all: 全谱, lit: 仅已钤印

    @State private var showNewFootprintSheet: Bool = false
    @State private var editingFootprint: Footprint?
    @State private var selectedDrawerCity: ProjectsWishesView.DrawerCitySelection?
    @State private var selectedDrawerProvince: ProjectsWishesView.DrawerProvinceSelection?
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

    public static let regions: [(name: String, provinces: [(name: String, short: String, adcode: String)])] = [
        ("华东", [
            ("上海市", "沪", "310000"),
            ("江苏省", "苏", "320000"),
            ("浙江省", "浙", "330000"),
            ("安徽省", "皖", "340000"),
            ("福建省", "闽", "350000"),
            ("江西省", "赣", "360000"),
            ("山东省", "鲁", "370000")
        ]),
        ("华北", [
            ("北京市", "京", "110000"),
            ("天津市", "津", "120000"),
            ("河北省", "冀", "130000"),
            ("山西省", "晋", "140000"),
            ("内蒙古自治区", "蒙", "150000")
        ]),
        ("中南", [
            ("河南省", "豫", "410000"),
            ("湖北省", "鄂", "420000"),
            ("湖南省", "湘", "430000"),
            ("广东省", "粤", "440000"),
            ("广西壮族自治区", "桂", "450000"),
            ("海南省", "琼", "460000")
        ]),
        ("西南", [
            ("重庆市", "渝", "500000"),
            ("四川省", "川", "510000"),
            ("贵州省", "黔", "520000"),
            ("云南省", "滇", "530000"),
            ("西藏自治区", "藏", "540000")
        ]),
        ("西北", [
            ("陕西省", "陕", "610000"),
            ("甘肃省", "甘", "620000"),
            ("青海省", "青", "630000"),
            ("宁夏回族自治区", "宁", "640000"),
            ("新疆维吾尔自治区", "新", "650000")
        ]),
        ("东北", [
            ("辽宁省", "辽", "210000"),
            ("吉林省", "吉", "220000"),
            ("黑龙江省", "黑", "230000")
        ]),
        ("港澳台", [
            ("香港特别行政区", "港", "810000"),
            ("澳门特别行政区", "澳", "820000"),
            ("台湾省", "台", "710000")
        ])
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                viewModePillsSection

                if let err = errorMessage {
                    Text(err)
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }

                Group {
                    switch viewMode {
                    case 0:
                        stampsMatrixSection
                    case 1:
                        ticketsSection
                    default:
                        celestialSection
                    }
                }
                .id(viewMode)
                .transition(.opacity)
            }
            .padding(24)
        }
        .sheet(isPresented: $showNewFootprintSheet) {
            NewFootprintSheet(appState: appState) {
                showNewFootprintSheet = false
            }
        }
        .sheet(item: $editingFootprint) { fp in
            EditFootprintSheet(appState: appState, footprint: fp) {
                editingFootprint = nil
            }
        }
        .sheet(item: $selectedDrawerCity) { sel in
            CityMemoryDrawerSheet(cityCode: sel.code, cityName: sel.name) {
                selectedDrawerCity = nil
            }
        }
        .sheet(item: $selectedDrawerProvince) { sel in
            ProvinceMemoryDrawerSheet(adcode: sel.adcode, provinceName: sel.name) {
                selectedDrawerProvince = nil
            }
        }
    }

    // MARK: - 1. 标头
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("山川印谱")
                        .font(ArchiveTypography.editorialSerif(size: 24, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("行迹百宝格与典藏票根")
                        .font(ArchiveTypography.monoScale(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                Text("累计点亮 \(litCitiesCount) 座城市 · 沉淀 \(appState.footprints.count) 程漫游足迹")
                    .font(ArchiveTypography.editorialSerif(size: 12.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
            }

            Spacer()

            Button {
                showNewFootprintSheet = true
                AudioFeedback.shared.playTink()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "location.fill.viewfinder")
                        .font(.system(size: 11, weight: .medium))
                    Text("点亮城市足迹")
                        .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
        }
    }

    // MARK: - 2. 模式切换
    private var viewModePillsSection: some View {
        HStack(spacing: 8) {
            PaperPillButton(title: "百宝格印谱", isSelected: viewMode == 0) {
                guard viewMode != 0 else { return }
                viewMode = 0
                AudioFeedback.shared.playTink()
            }
            PaperPillButton(title: "典藏票根 (\(appState.footprints.count))", isSelected: viewMode == 1) {
                guard viewMode != 1 else { return }
                viewMode = 1
                AudioFeedback.shared.playTink()
            }
            PaperPillButton(title: "经纬星野", isSelected: viewMode == 2) {
                guard viewMode != 2 else { return }
                viewMode = 2
                AudioFeedback.shared.playTink()
            }

            Spacer()

            if viewMode == 0 {
                // 仅看已点亮切换
                HStack(spacing: 4) {
                    PaperPillButton(title: "全谱 34 省", isSelected: sealFilter == "all") {
                        sealFilter = "all"
                    }
                    PaperPillButton(title: "仅已钤印", isSelected: sealFilter == "lit") {
                        sealFilter = "lit"
                    }
                }
            }
        }
    }

    // MARK: - 3. 百宝格印谱矩阵
    private var stampsMatrixSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 大区筛选 Tab
            HStack(spacing: 6) {
                PaperPillButton(title: "全境", isSelected: selectedRegion == "all") {
                    guard selectedRegion != "all" else { return }
                    selectedRegion = "all"
                    AudioFeedback.shared.playTink()
                }
                ForEach(Self.regions, id: \.name) { reg in
                    PaperPillButton(title: reg.name, isSelected: selectedRegion == reg.name) {
                        guard selectedRegion != reg.name else { return }
                        selectedRegion = reg.name
                        AudioFeedback.shared.playTink()
                    }
                }
            }

            let displayRegions = selectedRegion == "all" ? Self.regions : Self.regions.filter { $0.name == selectedRegion }

            ForEach(displayRegions, id: \.name) { reg in
                VStack(alignment: .leading, spacing: 10) {
                    Text(reg.name)
                        .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                        .foregroundStyle(ArchivePalette.accentWarm)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(reg.provinces, id: \.adcode) { prov in
                            let isLit = appState.footprints.contains { $0.cityCode.hasPrefix(String(prov.adcode.prefix(2))) }
                            if sealFilter == "all" || isLit {
                                provinceStampCell(prov: prov, isLit: isLit)
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func provinceStampCell(prov: (name: String, short: String, adcode: String), isLit: Bool) -> some View {
        let provFps = appState.footprints.filter { $0.cityCode.hasPrefix(String(prov.adcode.prefix(2))) }
        return HStack(spacing: 10) {
            // 朱砂方印
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(isLit ? ArchivePalette.accentWarm.opacity(0.12) : ArchivePalette.archiveSubtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(isLit ? ArchivePalette.accentWarm : ArchivePalette.borderDivider, lineWidth: 1)
                    )
                Text(prov.short)
                    .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                    .foregroundStyle(isLit ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(prov.name)
                    .font(ArchiveTypography.editorialSerif(size: 13, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text(isLit ? "已钤印 \(provFps.count) 程" : "待踏访")
                    .font(ArchiveTypography.monoScale(size: 10))
                    .foregroundStyle(isLit ? ArchivePalette.accentMoss : ArchivePalette.inkMuted)
            }

            Spacer()

            if isLit {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }
        }
        .padding(10)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isLit {
                AudioFeedback.shared.playPaperFlip()
                selectedDrawerProvince = ProjectsWishesView.DrawerProvinceSelection(adcode: prov.adcode, name: prov.name)
            }
        }
        .paperHover()
    }

    // MARK: - 4. 典藏票根架
    private var ticketsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if appState.footprints.isEmpty {
                emptyPlaceholder
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(appState.footprints) { fp in
                        HStack(spacing: 0) {
                            // 左联：目的地存根
                            VStack(alignment: .leading, spacing: 6) {
                                Text(fp.cityName)
                                    .font(ArchiveTypography.editorialSerif(size: 17, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                Text(FormatUtils.parseOccurredDate(fp.visitedAt).dotDate)
                                    .font(ArchiveTypography.monoScale(size: 10.5))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Spacer(minLength: 4)
                                Text("散页 \(max(1, fp.entriesCount ?? 1)) 篇")
                                    .font(ArchiveTypography.monoScale(size: 10.5))
                                    .foregroundStyle(ArchivePalette.accentMoss)
                            }
                            .frame(width: 105, alignment: .leading)
                            .padding(12)

                            // 齿孔虚线
                            Rectangle()
                                .fill(ArchivePalette.borderDivider)
                                .frame(width: 0.5)
                                .padding(.vertical, 8)

                            // 右联：游记正券
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text((fp.title?.isEmpty == false) ? fp.title! : "\(fp.cityName) · 行旅手记")
                                        .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .medium))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        editingFootprint = fp
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        appState.askConfirm(
                                            title: "确认删除该座城市足迹票根？",
                                            message: "删除后将移除该次漫游记录，关联游记散页不受影响。",
                                            confirmText: "删除足迹票根",
                                            danger: true
                                        ) {
                                            deleteFootprint(fp)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Text((fp.note?.isEmpty == false) ? fp.note! : "行至此处，留下一纸驻足印记。")
                                    .font(ArchiveTypography.bodySans(size: 12))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                    .lineLimit(2)

                                Spacer(minLength: 4)

                                HStack {
                                    if let spent = fp.totalSpent, spent > 0 {
                                        Text("旅途花销 \(FormatUtils.formattedYuan(cents: spent, includeSymbol: true))")
                                            .font(ArchiveTypography.monoScale(size: 10.5))
                                            .foregroundStyle(ArchivePalette.accentWarm)
                                    }
                                    Spacer()
                                    Text("城市抽屉 →")
                                        .font(ArchiveTypography.monoScale(size: 10))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 115)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            AudioFeedback.shared.playPaperFlip()
                            selectedDrawerCity = ProjectsWishesView.DrawerCitySelection(code: fp.cityCode, name: fp.cityName)
                        }
                        .paperHover()
                    }
                }
            }
        }
    }

    // MARK: - 5. 经纬星野
    private var celestialSection: some View {
        CelestialAtlasCanvasView(footprints: appState.footprints) { code, name in
            AudioFeedback.shared.playPaperFlip()
            selectedDrawerCity = ProjectsWishesView.DrawerCitySelection(code: code, name: name)
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Text("行迹票根架尚待启程")
                .font(ArchiveTypography.editorialSerif(size: 14, weight: .medium))
                .foregroundStyle(ArchivePalette.inkSecondary)
            Text("在时间流记录带城市的游记或点击上方「点亮城市足迹」，均会自动沉淀特种纸票根")
                .font(ArchiveTypography.bodySans(size: 11.5))
                .foregroundStyle(ArchivePalette.inkMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func deleteFootprint(_ fp: Footprint) {
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteFootprint(id: fp.id)
                AudioFeedback.shared.playTink()
                await appState.loadProjectsWishesFootprints()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

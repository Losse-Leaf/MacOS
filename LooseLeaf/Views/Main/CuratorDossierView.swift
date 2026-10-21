import SwiftUI

/// 主理人生活手记与器物图鉴视图 (CuratorDossierView)
/// 严格遵守：100% 由 GET /api/v1/profile 动态驱动，严禁硬编码姓名或城市
@MainActor
public struct CuratorDossierView: View {
    @Bindable var appState: AppState

    @State private var showEditProfileSheet: Bool = false
    @State private var showAddGearSheet: Bool = false
    @State private var sellingGear: GearItem?
    @State private var dossierError: String?
    @State private var editName: String = ""
    @State private var editTitle: String = ""
    @State private var editCity: String = ""
    @State private var editCityCode: String = ""
    @State private var editLocation: String = ""
    @State private var editLocationCode: String = ""
    @State private var editMotto: String = ""
    @State private var editBio: String = ""
    @State private var editManifesto: String = ""
    @State private var newAvatarKey: String?
    @State private var isUploadingAvatar: Bool = false
    @State private var avatarPreviewImage: NSImage?
    @State private var selectedGearCategory: String = "all"
    @State private var selectedHeatmapDate: String? = nil

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        let prof = appState.profile
        // 一次性绑定固资筛选结果，避免 body 内重复全量过滤
        let gearCategories = Array(Set(prof.edcGear.map { $0.category })).sorted()
        let displayedGear = selectedGearCategory == "all"
            ? prof.edcGear
            : prof.edcGear.filter { $0.category == selectedGearCategory }

        ScrollView {
            // LazyVStack 作为 ScrollView 直接子视图，长列表才具备懒加载能力
            LazyVStack(alignment: .leading, spacing: ArchiveSpacing.xl) {
                if let dossierError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text(dossierError)
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Spacer()
                    }
                }

                // 1. 主理人名片与暗房肖像
                HStack(alignment: .top, spacing: 20) {
                    if !prof.avatarUrl.isEmpty, let url = APIClient.shared.resolveMediaURL(prof.avatarUrl) {
                        FilmFrameView(
                            imageURL: url,
                            caption: "银盐肖像",
                            metaText: prof.displayCity.isEmpty ? nil : prof.displayCity,
                            maxHeight: 180
                        )
                        .frame(width: 180)
                    }

                    VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                        HStack {
                            Text(prof.name.isEmpty ? "主理人档案待填写" : prof.name)
                                .font(ArchiveTypography.editorialSerif(size: 22, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)

                            if !prof.title.isEmpty {
                                Text(prof.title)
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                    .padding(.horizontal, ArchiveSpacing.s)
                                    .padding(.vertical, 3)
                                    .background(ArchivePalette.archiveSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            }

                            Spacer()

                            Button {
                                appState.showStatsSheet = true
                            } label: {
                                HStack(spacing: ArchiveSpacing.xs) {
                                    Image(systemName: "chart.bar")
                                        .font(.system(size: 11))
                                    Text("生活统计")
                                }
                            }
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                            .help("查看生活统计卡片 (⌘⌥S)")

                            Button("修订档案") {
                                editName = prof.name
                                editTitle = prof.title
                                editCity = prof.currentCity
                                editCityCode = CityDictionary.code(forLocation: prof.currentCity) ?? ""
                                editLocation = prof.location
                                editLocationCode = CityDictionary.code(forLocation: prof.location) ?? ""
                                editMotto = prof.motto
                                editBio = prof.bio
                                editManifesto = prof.manifesto
                                showEditProfileSheet = true
                            }
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        }

                        if !prof.displayCity.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "location")
                                    .font(.system(size: 11))
                                let coordText: String = {
                                    if !prof.location.isEmpty && !prof.currentCity.isEmpty && prof.location != prof.currentCity {
                                        return "常居：\(prof.location) · 当下：\(prof.currentCity)"
                                    } else if !prof.currentCity.isEmpty {
                                        return "当下坐标：\(prof.currentCity)"
                                    } else {
                                        return "常居坐标：\(prof.location)"
                                    }
                                }()
                                Text(coordText)
                                    .font(ArchiveTypography.monoScale(size: 11.5))
                            }
                            .foregroundStyle(ArchivePalette.inkMuted)
                        }

                        if !prof.motto.isEmpty {
                            Text("“\(prof.motto)”")
                                .font(ArchiveTypography.editorialSerif(size: 15))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .padding(.top, 2)
                        }

                        if !prof.bio.isEmpty {
                            Text(prof.bio)
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                        }

                        if !prof.manifesto.isEmpty {
                            Text(prof.manifesto)
                                .font(ArchiveTypography.bodySans(size: 12.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(18)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )

                // 2. 生活刻度 · 编年时间热力图与年度卷宗
                VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                    HStack {
                        HStack(spacing: ArchiveSpacing.s) {
                            Text("生活刻度 · 时间热力图")
                                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                            Text("（累计在册 \(appState.entries.count) 篇记录）")
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }

                        Spacer()

                        Button {
                            appState.showAlmanacSheet = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "book.closed")
                                    .font(.system(size: 11))
                                Text("年度生活年鉴画卷")
                                    .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                            }
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    }

                    LifeActivityHeatmapView(
                        entryCounts: appState.entryCountsByDate,
                        totalCount: appState.entries.count,
                        weeksCount: 52,
                        selectedDate: $selectedHeatmapDate
                    )

                    // 点击具体日期后展开当日手记速览抽屉 (严格 1:1 对标 Web 端 AboutView.vue)
                    if let dateKey = selectedHeatmapDate {
                        // 走记忆化的按日索引，不再每次 body 求值都全量解析一遍日期
                        let selectedDateEntries = appState.entriesByDateKey[dateKey] ?? []

                        LazyVStack(alignment: .leading, spacing: 10) {
                            Divider().overlay(ArchivePalette.borderSubtle)

                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 11))
                                        .foregroundStyle(ArchivePalette.accentWarm)
                                    Text("\(dateKey) 当日记录 (\(selectedDateEntries.count) 条)")
                                        .font(ArchiveTypography.monoScale(size: 11.5, weight: .medium))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                }

                                Spacer()

                                Button {
                                    selectedHeatmapDate = nil
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: ArchiveIcon.close.systemName)
                                            .font(.system(size: 10, weight: .bold))
                                        Text("关闭速览")
                                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                    }
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                }
                                .buttonStyle(.plain)
                            }

                            if selectedDateEntries.isEmpty {
                                Text("该日未留下公开或私密手记。")
                                    .font(ArchiveTypography.editorialSerif(size: 11.5))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .padding(.vertical, 6)
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: ArchiveSpacing.s) {
                                    ForEach(selectedDateEntries) { item in
                                        Button {
                                            appState.highlightedEntry = item
                                        } label: {
                                            VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                                                HStack {
                                                    Text(item.title.isEmpty ? "无题散页" : item.title)
                                                        .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                                        .lineLimit(1)
                                                    Spacer()
                                                    Text(FormatUtils.parseOccurredDate(item.occurredAt).time)
                                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                                        .foregroundStyle(ArchivePalette.inkMuted)
                                                }

                                                if !item.content.isEmpty {
                                                    Text(item.content)
                                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            .padding(10)
                                            .background(ArchivePalette.archivePaper)
                                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(18)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )

                // 3. 随身器物图鉴 (EDC Gear) — 标题与分类筛选
                gearHeaderSection(gearCategories: gearCategories)

                // 3b. 随身器物图鉴 — 空态或货架网格（作为 ScrollView 子级渲染，保留懒加载能力）
                if displayedGear.isEmpty {
                    gearEmptyState
                } else {
                    gearGrid(displayedGear)
                }
            }
            .padding(ArchiveSpacing.xl)
        }
        .sheet(isPresented: $showEditProfileSheet) {
            editProfileSheetView
        }
        .sheet(item: $sellingGear) { gear in
            SellGearSheet(gear: gear) {
                sellingGear = nil
            } onSold: {
                Task { @MainActor in
                    await appState.loadConfigAndProfile()
                    await appState.loadTransactionsAndAssets(forceFull: false)
                }
            }
        }
        .sheet(isPresented: $showAddGearSheet) {
            AddGearSheet(appState: appState) {
                showAddGearSheet = false
            }
        }
        .sheet(isPresented: $appState.showAlmanacSheet) {
            AnnualAlmanacSheet {
                appState.showAlmanacSheet = false
            }
        }
    }

    // MARK: - 随身器物图鉴分区

    /// 图鉴标题与分类筛选胶囊
    private func gearHeaderSection(gearCategories: [String]) -> some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            HStack(alignment: .center) {
                Text("随身器物与桌面装备图鉴 (\(appState.profile.edcGear.count))")
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                Spacer()

                Button {
                    showAddGearSheet = true
                } label: {
                    HStack(spacing: ArchiveSpacing.xs) {
                        Image(systemName: ArchiveIcon.add.systemName)
                            .font(.system(size: 11, weight: .semibold))
                        Text("添置随身设备")
                            .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            }

            // 分类筛选胶囊（首尾渐隐提示可横向滚动）
            if gearCategories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        PaperPillButton(title: "全部 (\(appState.profile.edcGear.count))", isSelected: selectedGearCategory == "all") {
                            selectedGearCategory = "all"
                        }
                        ForEach(gearCategories, id: \.self) { cat in
                            let count = appState.profile.edcGear.filter { $0.category == cat }.count
                            PaperPillButton(title: "\(cat) (\(count))", isSelected: selectedGearCategory == cat) {
                                selectedGearCategory = cat
                            }
                        }
                    }
                }
                .horizontalFadeMask()
            }
        }
    }

    /// 器物空态：提供明确的行动召唤（添置随身设备）
    private var gearEmptyState: some View {
        ArchiveEmptyState(
            systemName: ArchiveIcon.gear.systemName,
            title: "尚无该分类随身器物记录",
            message: "点击「添置随身设备」录入您的相机、镜头或 EDC 装备，服役中的固资将实时计入净资产大盘。",
            primaryTitle: "添置随身设备",
            primaryAction: { showAddGearSheet = true }
        )
    }

    /// 器物货架网格（作为 ScrollView 子级渲染，保留懒加载能力）
    private func gearGrid(_ displayedGear: [GearItem]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: ArchiveSpacing.m) {
            ForEach(displayedGear) { gear in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(gear.category)
                            .font(ArchiveTypography.monoScale(size: 10.5))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Spacer()
                        Text(gear.status == "sold" ? "已转让回血" : "服役中")
                            .font(ArchiveTypography.monoScale(size: 10.5))
                            .foregroundStyle(gear.status == "sold" ? ArchivePalette.inkMuted : ArchivePalette.accentMoss)
                    }

                    Text(gear.name)
                        .font(ArchiveTypography.editorialSerif(size: 14.5, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    if let spec = gear.spec, !spec.isEmpty {
                        Text(spec)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.inkSecondary)
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

                        if gear.status != "sold" {
                            Button("转让回血") {
                                sellingGear = gear
                            }
                            .font(ArchiveTypography.bodySans(size: 10.5))
                            .buttonStyle(.plain)
                            .foregroundStyle(ArchivePalette.accentWarm)
                        }

                        PaperIconButton(
                            systemName: ArchiveIcon.delete.systemName,
                            label: "删除设备",
                            help: "删除设备",
                            size: 10.5,
                            tint: ArchivePalette.inkMuted
                        ) {
                            appState.askConfirm(
                                title: ArchiveSharedCopy.gearDeleteTitle,
                                message: ArchiveSharedCopy.gearDeleteMessage,
                                confirmText: ArchiveSharedCopy.gearDeleteConfirmText,
                                danger: true
                            ) {
                                deleteGear(gear)
                            }
                        }
                    }
                }
                .padding(ArchiveCardMetrics.padding)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
                .paperHover()
            }
        }
    }

    private func deleteGear(_ gear: GearItem) {
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteGearAsset(id: gear.id)
                await appState.loadConfigAndProfile()
                await appState.loadTransactionsAndAssets(forceFull: false)
            } catch {
                dossierError = "删除器物失败：\(error.localizedDescription)"
            }
        }
    }

    private var editProfileSheetView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("修订主理人档案")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack(spacing: ArchiveSpacing.m) {
                if let avatarPreviewImage {
                    Image(nsImage: avatarPreviewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ArchivePalette.borderSubtle, lineWidth: 1))
                }
                Button {
                    selectAndUploadAvatar()
                } label: {
                    HStack(spacing: ArchiveSpacing.xs) {
                        Image(systemName: "photo")
                        Text(isUploadingAvatar ? "正在上传肖像…" : "更换肖像照片…")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .disabled(isUploadingAvatar)

                if newAvatarKey != nil {
                    Text("新肖像已就绪")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.accentMoss)
                }
            }
            .padding(.vertical, ArchiveSpacing.xxs)

            TextField("主理人称谓", text: $editName)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("主理人身份", text: $editTitle)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            HStack(spacing: ArchiveSpacing.s) {
                PaperCityPicker(
                    selectedCode: $editCityCode,
                    selectedName: $editCity,
                    placeholder: "点选当前城市…",
                    label: "当前城市",
                    isFullWidth: true
                )

                PaperCityPicker(
                    selectedCode: $editLocationCode,
                    selectedName: $editLocation,
                    placeholder: "点选常居城市…",
                    label: "常居城市",
                    isFullWidth: true
                )
            }

            TextField("近况题记", text: $editMotto)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("副标题", text: $editBio)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            if let dossierError {
                Text(dossierError)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { showEditProfileSheet = false }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存档案") {
                    Task { @MainActor in
                        let trimmedCity = editCity.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedLoc = editLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                        let req = UpdateProfileRequest(
                            name: editName,
                            title: editTitle,
                            bio: editBio,
                            location: trimmedLoc,
                            currentCity: trimmedCity,
                            avatarKey: newAvatarKey ?? appState.profile.avatarKey,
                            motto: editMotto,
                            manifesto: editManifesto
                        )
                        do {
                            _ = try await APIClient.shared.updateCuratorProfile(req)
                            await appState.loadConfigAndProfile()
                            dossierError = nil
                            showEditProfileSheet = false
                        } catch {
                            dossierError = "档案保存失败：\(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(
            minWidth: ArchiveSheetWidth.standard,
            idealWidth: ArchiveSheetWidth.standard,
            maxWidth: ArchiveSheetWidth.standard
        )
        .background(ArchivePalette.archivePaper)
    }

    private func selectAndUploadAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                isUploadingAvatar = true
                do {
                    // 沙箱：NSOpenPanel 选中的文件位于沙箱容器之外，
                    // 必须取得安全作用域授权才能读取，否则读取会静默失败。
                    let processed = try await SandboxFileAccess.withAccess(to: url) { scopedURL in
                        try await ImageProcessor.processImageFileInBackground(
                            at: scopedURL,
                            maxPixelSize: 1024,
                            quality: 0.85
                        )
                    }
                    avatarPreviewImage = NSImage(data: processed.compressedData)
                    let att = try await APIClient.shared.uploadUnifiedMultipart(
                        fileData: processed.compressedData,
                        filename: "avatar-\(Int(Date().timeIntervalSince1970)).jpg",
                        mimeType: "image/jpeg",
                        folder: "avatar"
                    )
                    newAvatarKey = att.objectKey
                } catch {
                    dossierError = "肖像上传失败：\(error.localizedDescription)"
                }
                isUploadingAvatar = false
            }
        }
    }
}

// MARK: - 预览 (Preview)

#Preview("主理人档案") {
    CuratorDossierView(appState: ArchivePreviewFixtures.makeAppState())
        .frame(width: 1100, height: 760)
}

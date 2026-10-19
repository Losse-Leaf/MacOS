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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let dossierError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text(dossierError)
                            .font(ArchiveTypography.bodySans(size: 12))
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

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(prof.name.isEmpty ? "主理人档案待填写" : prof.name)
                                .font(ArchiveTypography.editorialSerif(size: 22, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)

                            if !prof.title.isEmpty {
                                Text(prof.title)
                                    .font(ArchiveTypography.bodySans(size: 12))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(ArchivePalette.archiveSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }

                            Spacer()

                            Button {
                                appState.showStatsSheet = true
                            } label: {
                                HStack(spacing: 4) {
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
                                .font(ArchiveTypography.bodySans(size: 13))
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
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 8) {
                            Text("生活刻度 · 时间热力图")
                                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                            Text("（累计在册 \(appState.entries.count) 篇记录）")
                                .font(ArchiveTypography.monoScale(size: 11))
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
                        let selectedDateEntries = appState.entries.filter {
                            FormatUtils.parseOccurredDate($0.occurredAt).dateKey == dateKey
                        }

                        VStack(alignment: .leading, spacing: 10) {
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
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                        Text("关闭速览")
                                            .font(ArchiveTypography.bodySans(size: 11))
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
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(selectedDateEntries) { item in
                                        Button {
                                            appState.highlightedEntry = item
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack {
                                                    Text(item.title.isEmpty ? "无题散页" : item.title)
                                                        .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                                        .lineLimit(1)
                                                    Spacer()
                                                    Text(FormatUtils.parseOccurredDate(item.occurredAt).time)
                                                        .font(ArchiveTypography.monoScale(size: 10))
                                                        .foregroundStyle(ArchivePalette.inkMuted)
                                                }

                                                if !item.content.isEmpty {
                                                    Text(item.content)
                                                        .font(ArchiveTypography.bodySans(size: 11))
                                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            .padding(10)
                                            .background(ArchivePalette.archivePaper)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
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

                // 3. 随身器物图鉴 (EDC Gear)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        Text("随身器物与桌面装备图鉴 (\(prof.edcGear.count))")
                            .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)

                        Spacer()

                        Button {
                            showAddGearSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("添置随身设备")
                                    .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                            }
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    }

                    // 分类筛选胶囊
                    let gearCats = Set(prof.edcGear.map { $0.category })
                    if gearCats.count > 1 {
                        HStack(spacing: 6) {
                            PaperPillButton(title: "全部 (\(prof.edcGear.count))", isSelected: selectedGearCategory == "all") {
                                selectedGearCategory = "all"
                            }
                            ForEach(Array(gearCats).sorted(), id: \.self) { cat in
                                let count = prof.edcGear.filter { $0.category == cat }.count
                                PaperPillButton(title: "\(cat) (\(count))", isSelected: selectedGearCategory == cat) {
                                    selectedGearCategory = cat
                                }
                            }
                        }
                    }

                    let displayedGear = selectedGearCategory == "all" ? prof.edcGear : prof.edcGear.filter { $0.category == selectedGearCategory }

                    if displayedGear.isEmpty {
                        VStack(spacing: 8) {
                            Text("尚无该分类随身器物记录，点击上方「添置随身设备」录入您的相机、镜头或 EDC 装备。")
                                .font(ArchiveTypography.bodySans(size: 12.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
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
                                            .font(ArchiveTypography.monoScale(size: 11))
                                            .foregroundStyle(ArchivePalette.inkSecondary)
                                    }

                                    HStack {
                                        if let price = gear.priceCents, price > 0 {
                                            Text("购入 \(FormatUtils.formattedYuan(cents: price, includeSymbol: true))")
                                                .font(ArchiveTypography.monoScale(size: 11))
                                                .foregroundStyle(ArchivePalette.inkMuted)
                                        }

                                        if let sold = gear.soldPriceCents, sold > 0 {
                                            Text("回血 \(FormatUtils.formattedYuan(cents: sold, includeSymbol: true))")
                                                .font(ArchiveTypography.monoScale(size: 11))
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

                                        Button {
                                            appState.askConfirm(
                                                title: "确认删除该件随身器材资产？",
                                                message: "删除后该项设备将从固资货架中移除。",
                                                confirmText: "删除器材",
                                                danger: true
                                            ) {
                                                deleteGear(gear)
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(ArchivePalette.inkMuted)
                                        }
                                        .buttonStyle(.plain)
                                        .help("删除设备")
                                    }
                                }
                                .padding(14)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                                )
                            }
                        }
                    }
                }
            }
            .padding(24)
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
                    await appState.loadTransactionsAndAssets(forceFull: true)
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

    private func deleteGear(_ gear: GearItem) {
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteGearAsset(id: gear.id)
                await appState.loadConfigAndProfile()
                await appState.loadTransactionsAndAssets(forceFull: true)
            } catch {
                dossierError = "删除器物失败：\(error.localizedDescription)"
            }
        }
    }

    private var editProfileSheetView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("修订主理人档案")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack(spacing: 12) {
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
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                        Text(isUploadingAvatar ? "正在上传肖像…" : "更换肖像照片…")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .disabled(isUploadingAvatar)

                if newAvatarKey != nil {
                    Text("新肖像已就绪")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.accentMoss)
                }
            }
            .padding(.vertical, 2)

            TextField("主理人称谓", text: $editName)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("主理人身份", text: $editTitle)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 8) {
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
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("副标题", text: $editBio)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

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
        .frame(width: 420)
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
                    let processed = try await ImageProcessor.processImageFileInBackground(
                        at: url,
                        maxPixelSize: 1024,
                        quality: 0.85
                    )
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

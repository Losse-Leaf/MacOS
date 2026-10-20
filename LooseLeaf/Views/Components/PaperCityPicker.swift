// PaperCityPicker.swift
// 纸本省市点选器组件 (PaperCityPicker)
// 职责：只选到省市两级行政区的拟物点选器，支持搜索、定位秒选与省市联动面板。
// 来源：由 Views/Components/PaperComponents.swift 按职责拆分而来，代码逻辑保持原样。

import SwiftUI
import AppKit

/// 纸质拟物省市行政区划点选器 (PaperCityPicker)
/// 严格遵循要求：地点只选省市、拒绝复杂打字、杜绝 Emoji、支持 macOS 原生定位一键秒选
public struct PaperCityPicker: View {
    @Binding public var selectedCode: String
    @Binding public var selectedName: String
    public var placeholder: String
    public var label: String?
    public var isFullWidth: Bool

    @State private var isPickerPresented: Bool = false
    @State private var searchKeyword: String = ""
    @State private var activeProvince: String = "北京"

    public init(
        selectedCode: Binding<String>,
        selectedName: Binding<String>,
        placeholder: String = "选择省市…",
        label: String? = nil,
        isFullWidth: Bool = false
    ) {
        self._selectedCode = selectedCode
        self._selectedName = selectedName
        self.placeholder = placeholder
        self.label = label
        self.isFullWidth = isFullWidth
    }

    private var displayText: String {
        if !selectedName.isEmpty {
            if !selectedCode.isEmpty {
                let prefix = String(selectedCode.prefix(2))
                let prov = CityDictionary.provincePrefixMap[prefix] ?? ""
                let provText = prov.isEmpty || selectedName.contains(prov) ? "" : "\(prov) · "
                return "\(provText)\(selectedName)"
            }
            return selectedName
        }
        return placeholder
    }

    private var isSelected: Bool {
        !selectedName.isEmpty || !selectedCode.isEmpty
    }

    /// 省名列表只计算一次（此前每次 body 求值都重建 Set + 排序）
    private static let allProvincesCache: [String] = Array(Set(CityDictionary.provincePrefixMap.values)).sorted()

    private var allProvinces: [String] {
        Self.allProvincesCache
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
            if let label {
                Text(label)
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            // 外层不再用 Button 包裹：内部「清除」若嵌在 Button 里会同时触发打开弹层（双动作）
            HStack(spacing: 5) {
                Image(systemName: "map")
                    .font(.system(size: 10.5))
                    .foregroundStyle(isSelected ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)

                Text(displayText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(isSelected ? ArchivePalette.inkPrimary : ArchivePalette.inkMuted)
                    .lineLimit(1)

                if isFullWidth {
                    Spacer(minLength: 4)
                }

                if isSelected {
                    // 统一图标按钮：命中区不小于指针可点下限
                    PaperIconButton(
                        systemName: "xmark.circle.fill",
                        label: "清除已选城市",
                        size: 10,
                        tint: ArchivePalette.inkMuted
                    ) {
                        selectedCode = ""
                        selectedName = ""
                    }
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                searchKeyword = ""
                if let firstProv = allProvinces.first, activeProvince.isEmpty {
                    activeProvince = firstProv
                }
                // 已授权时静默刷新定位；未授权不在打开弹层的瞬间突然弹权限框
                if LocationManager.shared.isAuthorized {
                    LocationManager.shared.fetchCurrentLocation()
                }
                isPickerPresented = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("选择省市，当前为 \(displayText)")
            .padding(.horizontal, ArchiveSpacing.s)
            .padding(.vertical, isFullWidth ? 7 : 4.5)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                    .stroke(isSelected ? ArchivePalette.accentWarm.opacity(0.4) : ArchivePalette.borderDivider, lineWidth: 0.5)
            )
            .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
                cityPopoverContent
            }
        }
    }

    private var cityPopoverContent: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            // 1. 顶部当前定位秒选卡片
            let locMgr = LocationManager.shared
            if !locMgr.currentCity.isEmpty {
                Button {
                    let resolvedName = locMgr.currentCity
                    if let code = CityDictionary.code(forLocation: resolvedName) {
                        selectedCode = code
                        selectedName = resolvedName
                    } else {
                        selectedName = resolvedName
                    }
                    isPickerPresented = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text("当前定位：\(locMgr.lastResolvedLocationName)")
                            .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .lineLimit(1)
                        Spacer()
                        Text("点击选用")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    .padding(.horizontal, ArchiveSpacing.s)
                    .padding(.vertical, 5)
                    .background(ArchivePalette.accentWarm.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }
                .buttonStyle(.plain)
            } else {
                // 未定位成功时才提供显式入口：把权限申请收敛到用户主动点击，避免开弹层即弹系统框
                Button {
                    let status = locMgr.authorizationStatus
                    if status == .denied || status == .restricted {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                            NSWorkspace.shared.open(url)
                        }
                    } else {
                        locMgr.requestAuthorizationAndFetch()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location")
                            .font(.system(size: 10))
                        Text(locMgr.authorizationStatus == .denied || locMgr.authorizationStatus == .restricted
                             ? "定位权限已关闭 · 去系统设置开启"
                             : "使用当前定位")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                        Spacer()
                    }
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .padding(.horizontal, ArchiveSpacing.s)
                    .padding(.vertical, 5)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }
                .buttonStyle(.plain)
            }

            // 2. 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(ArchivePalette.inkMuted)
                TextField("检索省份或地级市…", text: $searchKeyword)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: 11.5))
            }
            .padding(6)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            Divider().overlay(ArchivePalette.borderSubtle)

            // 3. 内容展示：搜索模式 vs 两级省市点选模式
            if !searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let filtered = CityDictionary.searchCities(searchKeyword)
                if filtered.isEmpty {
                    Text("未检索到匹配的省市")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: ArchiveSpacing.xxs) {
                            ForEach(filtered) { city in
                                Button {
                                    selectedCode = city.code
                                    selectedName = city.name
                                    isPickerPresented = false
                                } label: {
                                    HStack {
                                        Text("\(city.province) · \(city.name)")
                                            .font(ArchiveTypography.bodySans(size: 11.5))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, ArchiveSpacing.s)
                                    .padding(.vertical, ArchiveSpacing.xs)
                                    .background(ArchivePalette.archivePaper)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 200)
                }
            } else {
                // 两级联动省市选择面板 (免键盘纯点选)
                HStack(spacing: 0) {
                    // 左侧省份列表
                    ScrollView {
                        LazyVStack(spacing: ArchiveSpacing.xxs) {
                            ForEach(allProvinces, id: \.self) { prov in
                                let isProvActive = prov == activeProvince
                                Button {
                                    activeProvince = prov
                                } label: {
                                    HStack {
                                        Text(prov)
                                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: isProvActive ? .semibold : .regular))
                                            .foregroundStyle(isProvActive ? ArchivePalette.accentWarm : ArchivePalette.inkPrimary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, ArchiveSpacing.s)
                                    .padding(.vertical, ArchiveSpacing.xs)
                                    .background(isProvActive ? ArchivePalette.accentWarm.opacity(0.12) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(prov)
                                .accessibilityValue(isProvActive ? "已选中" : "未选中")
                                .accessibilityAddTraits(isProvActive ? .isSelected : AccessibilityTraits())
                            }
                        }
                    }
                    .frame(width: 85, height: 210)

                    Rectangle()
                        .fill(ArchivePalette.borderSubtle)
                        .frame(width: 0.5)
                        .padding(.vertical, ArchiveSpacing.xxs)

                    // 右侧地级市列表
                    let citiesInProv = CityDictionary.standardCities.filter { $0.province == activeProvince }
                    ScrollView {
                        LazyVStack(spacing: ArchiveSpacing.xxs) {
                            ForEach(citiesInProv) { city in
                                Button {
                                    selectedCode = city.code
                                    selectedName = city.name
                                    isPickerPresented = false
                                } label: {
                                    HStack {
                                        Text(city.name)
                                            .font(ArchiveTypography.bodySans(size: 11.5))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8))
                                            .foregroundStyle(selectedCode == city.code ? ArchivePalette.accentWarm : Color.clear)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(ArchivePalette.archivePaper)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(city.name)
                                .accessibilityValue(selectedCode == city.code ? "已选中" : "未选中")
                                .accessibilityAddTraits(selectedCode == city.code ? .isSelected : AccessibilityTraits())
                            }
                        }
                    }
                    .frame(width: 140, height: 210)
                }
            }
        }
        .padding(10)
        .frame(minWidth: 260, idealWidth: 280)
        .background(ArchivePalette.archivePaper)
    }
}

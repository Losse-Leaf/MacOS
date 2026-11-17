// PaperCityPicker.swift
// 纸本省市点选器组件 (PaperCityPicker)

import SwiftUI
import AppKit

/// 纸质拟物省市行政区划点选器 (PaperCityPicker)
public struct PaperCityPicker: View {
    @Binding public var selectedCode: String
    @Binding public var selectedName: String
    public var placeholder: String
    public var label: String?
    public var isFullWidth: Bool

    @State private var isPickerPresented: Bool = false
    @State private var searchKeyword: String = ""
    @State private var activeProvince: String = ""
    @State private var hoveredCityCode: String? = nil
    @State private var hoveredProvince: String? = nil
    @FocusState private var isTriggerFocused: Bool
    @FocusState private var isSearchFocused: Bool

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

    private func openPicker() {
        searchKeyword = ""
        hoveredCityCode = selectedCode.isEmpty ? nil : selectedCode
        if selectedCode.count >= 2,
           let matchedProv = CityDictionary.provincePrefixMap[String(selectedCode.prefix(2))] {
            activeProvince = matchedProv
        } else if !selectedName.isEmpty,
                  let matchedCity = CityDictionary.standardCities.first(where: { $0.name == selectedName }) {
            activeProvince = matchedCity.province
        } else if activeProvince.isEmpty, let firstProv = allProvinces.first {
            activeProvince = firstProv
        }
        if LocationManager.shared.isAuthorized {
            LocationManager.shared.fetchCurrentLocation()
        }
        isPickerPresented = true
    }

    private var displayText: String {
        if !selectedName.isEmpty {
            return selectedName
        }
        if !selectedCode.isEmpty {
            let prefix = String(selectedCode.prefix(2))
            let prov = CityDictionary.provincePrefixMap[prefix] ?? ""
            return prov.isEmpty ? selectedCode : "\(prov) · \(selectedCode)"
        }
        return placeholder
    }

    private var isSelected: Bool {
        !selectedName.isEmpty || !selectedCode.isEmpty
    }

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

            HStack(spacing: 0) {
                Button {
                    openPicker()
                } label: {
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

                        Image(systemName: "chevron.down")
                            .font(.system(size: 7))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, ArchiveSpacing.s)
                    .padding(.vertical, isFullWidth ? 7 : 4.5)
                    .paperFocusRing(isFocused: isTriggerFocused, cornerRadius: ArchiveRadius.xs)
                }
                .buttonStyle(.plain)
                .focused($isTriggerFocused)
                .accessibilityLabel("选择省市，当前为 \(displayText)")

                if isSelected {
                    PaperIconButton(
                        systemName: "xmark.circle.fill",
                        label: "清除已选城市",
                        size: 10,
                        tint: ArchivePalette.inkMuted
                    ) {
                        selectedCode = ""
                        selectedName = ""
                    }
                    .padding(.trailing, 2)
                }
            }
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .frame(height: isFullWidth ? 32 : 28)
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

    private func moveSearchHighlight(in list: [CityDictionary.StandardCity], delta: Int) {
        guard !list.isEmpty else { return }
        if let currentCode = hoveredCityCode,
           let idx = list.firstIndex(where: { $0.code == currentCode }) {
            let nextIdx = min(max(idx + delta, 0), list.count - 1)
            hoveredCityCode = list[nextIdx].code
        } else {
            hoveredCityCode = list.first?.code
        }
    }

    private func commitSearchSelection(in list: [CityDictionary.StandardCity]) {
        guard let chosen = list.first(where: { $0.code == hoveredCityCode }) ?? list.first else { return }
        selectedCode = chosen.code
        selectedName = chosen.name
        isPickerPresented = false
    }

    private var cityPopoverContent: some View {
        let trimmedQuery = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmedQuery.isEmpty ? [] : CityDictionary.searchCities(trimmedQuery)
        return VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
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
                .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
            } else {
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
                .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(ArchivePalette.inkMuted)
                TextField("检索省份或地级市（回车快选）…", text: $searchKeyword)
                    .accessibilityLabel("检索省市")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .focused($isSearchFocused)
                    .onChange(of: searchKeyword) { _, newVal in
                        let hits = CityDictionary.searchCities(newVal.trimmingCharacters(in: .whitespacesAndNewlines))
                        hoveredCityCode = hits.first?.code
                    }
                    .onSubmit {
                        commitSearchSelection(in: filtered)
                    }
            }
            .padding(6)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            Divider().overlay(ArchivePalette.borderSubtle)

            if !trimmedQuery.isEmpty {
                Group {
                    if filtered.isEmpty {
                        Text("未检索到匹配的省市")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: ArchiveSpacing.xxs) {
                                    ForEach(filtered) { city in
                                        let isHovered = hoveredCityCode == city.code
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
                                            .contentShape(Rectangle())
                                            .padding(.horizontal, ArchiveSpacing.s)
                                            .padding(.vertical, ArchiveSpacing.xs)
                                            .background(isHovered ? ArchivePalette.accentWarm.opacity(0.12) : ArchivePalette.archivePaper)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                        .id(city.code)
                                        .buttonStyle(.plain)
                                        .onHover { h in
                                            if h { hoveredCityCode = city.code }
                                            else if hoveredCityCode == city.code { hoveredCityCode = nil }
                                        }
                                    }
                                }
                            }
                            .onChange(of: hoveredCityCode) { _, code in
                                if let code { proxy.scrollTo(code, anchor: .center) }
                            }
                        }
                    }
                }
                .frame(width: 225.5, height: 210)
            } else {
                HStack(spacing: 0) {
                    ScrollViewReader { provProxy in
                        ScrollView {
                            LazyVStack(spacing: ArchiveSpacing.xxs) {
                                ForEach(allProvinces, id: \.self) { prov in
                                    let isProvActive = prov == activeProvince
                                    let isHovered = hoveredProvince == prov
                                    Button {
                                        activeProvince = prov
                                    } label: {
                                        HStack {
                                            Text(prov)
                                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: isProvActive ? .semibold : .regular))
                                                .foregroundStyle(isProvActive ? ArchivePalette.accentWarm : ArchivePalette.inkPrimary)
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                        .padding(.horizontal, ArchiveSpacing.s)
                                        .padding(.vertical, ArchiveSpacing.xs)
                                        .background(isProvActive ? ArchivePalette.accentWarm.opacity(0.12) : (isHovered ? ArchivePalette.archiveSubtle.opacity(0.6) : Color.clear))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                    .id(prov)
                                    .buttonStyle(.plain)
                                    .onHover { h in
                                        if h { hoveredProvince = prov }
                                        else if hoveredProvince == prov { hoveredProvince = nil }
                                    }
                                    .accessibilityLabel(prov)
                                    .accessibilityAddTraits(isProvActive ? .isSelected : AccessibilityTraits())
                                }
                            }
                        }
                        .frame(width: 85, height: 210)
                        .onAppear {
                            if !activeProvince.isEmpty {
                                provProxy.scrollTo(activeProvince, anchor: .center)
                            }
                        }
                    }

                    Rectangle()
                        .fill(ArchivePalette.borderSubtle)
                        .frame(width: 0.5)
                        .padding(.vertical, ArchiveSpacing.xxs)

                    let citiesInProv = CityDictionary.standardCities.filter { $0.province == activeProvince }
                    ScrollView {
                        LazyVStack(spacing: ArchiveSpacing.xxs) {
                            ForEach(citiesInProv) { city in
                                let isSelectedCity = selectedCode == city.code
                                let isHovered = hoveredCityCode == city.code
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
                                            .foregroundStyle(isSelectedCity ? ArchivePalette.accentWarm : Color.clear)
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isSelectedCity ? ArchivePalette.accentWarm.opacity(0.08) : (isHovered ? ArchivePalette.archiveSubtle : ArchivePalette.archivePaper))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                                .onHover { h in
                                    if h { hoveredCityCode = city.code }
                                    else if hoveredCityCode == city.code { hoveredCityCode = nil }
                                }
                                .accessibilityLabel(city.name)
                                .accessibilityAddTraits(isSelectedCity ? .isSelected : AccessibilityTraits())
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
        .onAppear {
            isSearchFocused = true
        }
        .onKeyPress(.upArrow) {
            guard !trimmedQuery.isEmpty else { return .ignored }
            moveSearchHighlight(in: filtered, delta: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !trimmedQuery.isEmpty else { return .ignored }
            moveSearchHighlight(in: filtered, delta: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            isPickerPresented = false
            return .handled
        }
    }
}

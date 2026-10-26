// EventTreeDiagramView.swift
// 时间流 · 事件树谱全景图 (Event Tree Diagram View)
// 职责：将时间流条目按生活形态与时间分支映射为可视化层级树图。
// 严格遵循 diagram-design 技能 type-tree.md 规范：
// 1. 直角拐角连接线 (Orthogonal elbow-style connectors，严禁对角斜线)
// 2. 节点规格 rx=6，12px 600 加粗主名称 + 9px 等宽辅助标签
// 3. 单一焦点色强调 (Editorial coral/accent)，深浅色自适应

import SwiftUI
import AppKit

/// 树图呈现引擎
public enum TreeEngineMode: String, CaseIterable, Identifiable {
    case nativeTree = "原生矢量树谱"
    case echartsTree = "ECharts 交互树图"

    public var id: String { rawValue }
}

/// 事件树谱全景视图
public struct EventTreeDiagramView: View {
    public let entries: [LifeEntry]
    public var onSelectEntry: (LifeEntry) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var engineMode: TreeEngineMode = .nativeTree
    @State private var selectedCategoryId: String = "all"
    @State private var hoveredEntryId: Int? = nil

    public init(
        entries: [LifeEntry],
        onSelectEntry: @escaping (LifeEntry) -> Void
    ) {
        self.entries = entries
        self.onSelectEntry = onSelectEntry
    }

    private struct CategoryBranch: Identifiable {
        let id: String
        let label: String
        let icon: String
        let tint: Color
        let entries: [LifeEntry]
    }

    private var branches: [CategoryBranch] {
        let lifeEntries = entries.filter { $0.type == "life" }
        let travelEntries = entries.filter { $0.type == "travel" }
        let projectEntries = entries.filter { $0.type == "project" }
        let wishEntries = entries.filter { $0.type == "wish" }
        let txEntries = entries.filter { $0.type == "transaction" }

        return [
            CategoryBranch(id: "life", label: "日常随笔", icon: "pencil.line", tint: ArchivePalette.accentMoss, entries: lifeEntries),
            CategoryBranch(id: "travel", label: "山川行迹", icon: "airplane", tint: ArchivePalette.accentWarm, entries: travelEntries),
            CategoryBranch(id: "project", label: "造物沉淀", icon: "hammer", tint: Color("SpectrumStudy", bundle: ArchiveResourceBundle.bundle), entries: projectEntries),
            CategoryBranch(id: "wish", label: "心愿清单", icon: "sparkles", tint: Color("SpectrumLeisure", bundle: ArchiveResourceBundle.bundle), entries: wishEntries),
            CategoryBranch(id: "transaction", label: "柴米油盐", icon: "yensign.circle", tint: Color("SpectrumDining", bundle: ArchiveResourceBundle.bundle), entries: txEntries)
        ]
    }

    private var activeBranches: [CategoryBranch] {
        if selectedCategoryId == "all" {
            return branches.filter { !$0.entries.isEmpty }
        }
        return branches.filter { $0.id == selectedCategoryId && !$0.entries.isEmpty }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            // 控制栏：标题、分支筛选与引擎切换
            treeToolbar

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 主画布
            if engineMode == .nativeTree {
                nativeTreeView
            } else {
                echartsTreeView
            }
        }
        .padding(ArchiveSpacing.l)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
        .paperElevation(1)
    }

    // MARK: - 顶栏工具条

    private var treeToolbar: some View {
        HStack(spacing: ArchiveSpacing.m) {
            HStack(spacing: ArchiveSpacing.s) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13))
                    .foregroundStyle(ArchivePalette.accentWarm)

                VStack(alignment: .leading, spacing: 2) {
                    Text("时间流 · 事件树谱图")
                        .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("以形态分支与直角树谱梳理 \(entries.count) 篇在册生活事件")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
            }

            Spacer()

            // 分类筛选胶囊
            HStack(spacing: 4) {
                PaperPillButton(title: "全部形态", isSelected: selectedCategoryId == "all") {
                    selectedCategoryId = "all"
                }
                ForEach(branches) { b in
                    if !b.entries.isEmpty {
                        PaperPillButton(
                            title: "\(b.label) (\(b.entries.count))",
                            isSelected: selectedCategoryId == b.id
                        ) {
                            selectedCategoryId = b.id
                        }
                    }
                }
            }

            // 引擎切换
            HStack(spacing: 4) {
                ForEach(TreeEngineMode.allCases) { mode in
                    PaperPillButton(
                        title: mode.rawValue,
                        isSelected: engineMode == mode
                    ) {
                        engineMode = mode
                    }
                }
            }
        }
    }

    // MARK: - 原生矢量树谱 (Native SVG/Canvas Tree)

    private var nativeTreeView: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 24) {
                // 1. 根节点 (Root Node) 居中呈现
                HStack {
                    Spacer()
                    rootNodeView
                    Spacer()
                }

                // 2. 根部到一级分支的主母线 (Orthogonal Trunk to Bus)
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(ArchivePalette.borderSubtle)
                        .frame(width: 1.5, height: 20)
                    Spacer()
                }

                // 3. 各大形态分支横向并排展开 (Level 1 Branches & Event Leaves)
                HStack(alignment: .top, spacing: 20) {
                    ForEach(activeBranches) { branch in
                        branchColumnView(branch)
                    }
                }
                .padding(.horizontal, 10)
            }
            .padding(.vertical, 16)
            .frame(minWidth: 840)
        }
        .frame(minHeight: 380)
    }

    /// 根节点：生活卷宗
    private var rootNodeView: some View {
        HStack(spacing: 8) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 12))
                .foregroundStyle(ArchivePalette.accentWarm)
            VStack(alignment: .leading, spacing: 2) {
                Text("《散页》生活档案馆")
                    .font(ArchiveTypography.editorialSerif(size: 13, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text("ROOT · \(entries.count) EVENTS")
                    .font(ArchiveTypography.monoScale(size: 9))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.accentWarm.opacity(0.8), lineWidth: 1.2)
        )
    }

    /// 单个形态分支列 (包含分支父节点 + 直角分支线 + 叶子节点事件卡片)
    private func branchColumnView(_ branch: CategoryBranch) -> some View {
        VStack(alignment: .center, spacing: 0) {
            // 一级分支头节点 (Category Node)
            HStack(spacing: 6) {
                Image(systemName: branch.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(branch.tint)
                Text(branch.label)
                    .font(ArchiveTypography.editorialSerif(size: 12, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text("(\(branch.entries.count))")
                    .font(ArchiveTypography.monoScale(size: 9))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(branch.tint.opacity(0.6), lineWidth: 1)
            )

            // 直角延伸主干引线 (Orthogonal Branch Spine)
            Rectangle()
                .fill(branch.tint.opacity(0.3))
                .frame(width: 1.5, height: 16)

            // 叶子节点列表 (最多展示最近 10 条事件)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(branch.entries.prefix(8)) { entry in
                    leafNodeItemView(entry, tint: branch.tint)
                }

                if branch.entries.count > 8 {
                    Text("… 还有 \(branch.entries.count - 8) 条手稿沉淀")
                        .font(ArchiveTypography.monoScale(size: 10))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(.top, 4)
                        .padding(.leading, 18)
                }
            }
        }
        .frame(minWidth: 155, maxWidth: 190)
    }

    /// 单个事件叶子节点 (Leaf Node)
    private func leafNodeItemView(_ entry: LifeEntry, tint: Color) -> some View {
        let isHovered = hoveredEntryId == entry.id

        return HStack(alignment: .top, spacing: 0) {
            // 直角树枝分支引线 (Orthogonal Elbow Connector)
            HStack(spacing: 0) {
                Rectangle()
                    .fill(tint.opacity(0.4))
                    .frame(width: 1.5, height: 18)
                Rectangle()
                    .fill(tint.opacity(0.4))
                    .frame(width: 10, height: 1.5)
            }
            .padding(.top, 10)

            // 叶子节点小矩形 (rx=6，12px 名称 + 9px 等宽日期)
            Button {
                onSelectEntry(entry)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.title.isEmpty ? "无题散页" : entry.title)
                            .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                            .lineLimit(1)
                        Spacer()
                    }

                    HStack(spacing: 4) {
                        Text(FormatUtils.parseOccurredDate(entry.occurredAt).dateKey)
                            .font(ArchiveTypography.monoScale(size: 9))
                            .foregroundStyle(ArchivePalette.inkMuted)

                        if let loc = entry.cityName ?? entry.location, !loc.isEmpty {
                            Text("· \(loc)")
                                .font(ArchiveTypography.bodySans(size: 9))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isHovered ? tint.opacity(0.08) : ArchivePalette.archiveSubtle.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isHovered ? tint : ArchivePalette.borderSubtle.opacity(0.7), lineWidth: isHovered ? 1.2 : 0.6)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                hoveredEntryId = isHovered ? entry.id : nil
            }
            .help("点击打开详情")
        }
    }

    // MARK: - ECharts 交互树图 (ECharts Tree View)

    private var echartsTreeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ECharts 树图引擎 · 直角折线拓扑 (Polyline Tree)")
                .font(ArchiveTypography.monoScale(size: 11))
                .foregroundStyle(ArchivePalette.inkMuted)

            let catData: [String: [(id: Int, title: String, date: String, type: String)]] = branches.reduce(into: [:]) { dict, b in
                dict[b.label] = b.entries.map {
                    (id: $0.id, title: $0.title.isEmpty ? "无题散页" : $0.title, date: FormatUtils.parseOccurredDate($0.occurredAt).dateKey, type: $0.type)
                }
            }

            DiagramWebView(
                htmlContent: DiagramHTMLBuilder.buildEventTreeChartHTML(
                    categories: catData,
                    isDark: colorScheme == .dark
                ),
                onSelectEntry: { id in
                    if let target = entries.first(where: { $0.id == id }) {
                        onSelectEntry(target)
                    }
                }
            )
            .frame(height: 440)
            .background(ArchivePalette.archiveSubtle.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        }
    }
}

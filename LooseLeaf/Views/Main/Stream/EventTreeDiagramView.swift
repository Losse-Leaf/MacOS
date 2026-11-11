// EventTreeDiagramView.swift
// 时间流 · 事件树谱全景图 (Event Tree Diagram View)
// 职责：将时间流条目按生活形态与时间分支映射为可视化层级树图。
// 严格遵循 diagram-design 技能 type-tree.md 规范：
// 1. 直角拐角连接线 (Orthogonal elbow-style connectors，严禁对角斜线)
// 2. 节点规格 rx=6，12px 600 加粗主名称 + 9px 等宽辅助标签
// 3. 单一焦点色强调 (Editorial coral/accent)，深浅色自适应

import SwiftUI
import AppKit

/// 事件树谱全景视图
public struct EventTreeDiagramView: View {
    public let entries: [LifeEntry]
    public var onSelectEntry: (LifeEntry) -> Void

    @Environment(\.colorScheme) private var colorScheme
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
        let gearEntries = entries.filter { $0.type == "gear" }
        let otherEntries = entries.filter { !["life", "travel", "project", "wish", "transaction", "gear"].contains($0.type) }

        var list = [
            CategoryBranch(id: "life", label: "日常随笔", icon: "pencil.line", tint: ArchivePalette.accentMoss, entries: lifeEntries),
            CategoryBranch(id: "travel", label: "山川行迹", icon: "airplane", tint: ArchivePalette.accentWarm, entries: travelEntries),
            CategoryBranch(id: "project", label: "造物沉淀", icon: "hammer", tint: Color("SpectrumStudy", bundle: ArchiveResourceBundle.bundle), entries: projectEntries),
            CategoryBranch(id: "wish", label: "心愿清单", icon: "sparkles", tint: Color("SpectrumLeisure", bundle: ArchiveResourceBundle.bundle), entries: wishEntries),
            CategoryBranch(id: "transaction", label: "柴米油盐", icon: "yensign.circle", tint: Color("SpectrumDining", bundle: ArchiveResourceBundle.bundle), entries: txEntries),
            CategoryBranch(id: "gear", label: "行囊装备", icon: "cube.box", tint: Color("SpectrumShopping", bundle: ArchiveResourceBundle.bundle), entries: gearEntries)
        ]
        if !otherEntries.isEmpty {
            list.append(CategoryBranch(id: "other", label: "其它漫录", icon: "ellipsis.circle", tint: ArchivePalette.inkSecondary, entries: otherEntries))
        }
        return list
    }

    private var activeBranches: [CategoryBranch] {
        if selectedCategoryId == "all" {
            return branches.filter { !$0.entries.isEmpty }
        }
        return branches.filter { $0.id == selectedCategoryId && !$0.entries.isEmpty }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            // 控制栏：标题与分支筛选
            treeToolbar

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 主画布：纯原生直角折线树谱
            nativeTreeView
        }
        .padding(ArchiveSpacing.l)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
        .paperElevation(1)
    }

    // MARK: - 顶栏工具条

    private var treeToolbar: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            HStack(alignment: .center, spacing: ArchiveSpacing.m) {
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
            }

            // 分类筛选胶囊（横向平滑滚动，根治窄屏下溢出与文字挤压）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
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
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 原生矢量树谱 (Native SVG/Canvas Tree)

    private var nativeTreeView: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .center, spacing: 0) {
                // 1. 根节点 (Root Node) 居中呈现
                rootNodeView

                // 2. 根部到一级分支的主母线与横向总线 (Orthogonal Trunk to Bus)
                Rectangle()
                    .fill(ArchivePalette.accentWarm.opacity(0.45))
                    .frame(width: 1.5, height: 16)

                if activeBranches.count > 1 {
                    // 横向正交总线 (Bus Bar)
                    GeometryReader { geo in
                        Path { path in
                            let midY = geo.size.height / 2
                            path.move(to: CGPoint(x: 80, y: midY))
                            path.addLine(to: CGPoint(x: max(geo.size.width - 80, 80), y: midY))
                        }
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 1.5)
                    }
                    .frame(height: 10)
                }

                // 3. 各大形态分支横向并排展开 (Level 1 Branches & Event Leaves)
                HStack(alignment: .top, spacing: 20) {
                    ForEach(activeBranches) { branch in
                        branchColumnView(branch)
                    }
                }
                .padding(.horizontal, 16)
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
                Text("散页总卷 · \(entries.count) 篇在册留痕")
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

    /// 单个形态分支列 (包含分支父节点 + 垂直连续骨干引线 + 树枝连接叶子节点)
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

            // 直角延伸主干引线 (Orthogonal Branch Spine Top)
            Rectangle()
                .fill(branch.tint.opacity(0.35))
                .frame(width: 1.5, height: 16)

            // 叶子节点列表 (连续垂直树干 + ├── 与 └── 分支引线)
            let shownEntries = Array(branch.entries.prefix(8))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shownEntries.enumerated()), id: \.element.id) { index, entry in
                    let isLast = index == shownEntries.count - 1 && branch.entries.count <= 8
                    leafNodeItemView(entry, tint: branch.tint, isLast: isLast)
                }

                if branch.entries.count > 8 {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(branch.tint.opacity(0.35))
                            .frame(width: 1.5, height: 24)
                            .padding(.leading, 10)
                        Text("… 还有 \(branch.entries.count - 8) 条在册手稿")
                            .font(ArchiveTypography.monoScale(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(.leading, 8)
                    }
                }
            }
        }
        .frame(minWidth: 160, maxWidth: 195)
    }

    /// 单个事件叶子节点 (Leaf Node 带连续直角折线连接)
    private func leafNodeItemView(_ entry: LifeEntry, tint: Color, isLast: Bool) -> some View {
        let isHovered = hoveredEntryId == entry.id

        return HStack(alignment: .top, spacing: 0) {
            // 直角连接折线 (├── 或 └──)
            ZStack(alignment: .topLeading) {
                // 垂直主干 (若为末节点则折角处终止，否则贯穿到底)
                Rectangle()
                    .fill(tint.opacity(0.35))
                    .frame(width: 1.5)
                    .frame(maxHeight: isLast ? 22 : .infinity)
                    .padding(.leading, 10)

                // 水平折角引线 (向右伸向卡片)
                Rectangle()
                    .fill(tint.opacity(0.35))
                    .frame(width: 8, height: 1.5)
                    .padding(.leading, 10)
                    .padding(.top, 22)
            }
            .frame(width: 20)

            // 叶子节点卡片
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
            .padding(.vertical, 3)
            .onHover { isHovered in
                hoveredEntryId = isHovered ? entry.id : nil
            }
            .help("点击打开详情")
        }
    }

    // MARK: - ECharts 交互树图 (ECharts Tree View)


}

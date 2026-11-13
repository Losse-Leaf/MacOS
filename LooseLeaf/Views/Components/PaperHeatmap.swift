// PaperHeatmap.swift
// 时光刻度组件 (Temporal Gap Separator)
// 职责：归档时间轴上的「岁月留白」刻度切线，
//       属于时间维度的可视化呈现，不涉及表单控件与通用按钮样式。
// 来源：由 Views/Components/PaperComponents.swift 按职责拆分而来，代码逻辑保持原样。

import SwiftUI

/// 岁月留白刻度切线 (Temporal Gap Separator)
/// 遵循 docs/ecosystem.md §4.1.3：当相邻记录跨度 >= 14 天时自动插入留白标注
/// 融合树状时间轴树干母线与年轮休眠节点 (Tree Ring Dormant Node)
public struct TemporalGapDivider: View {
    public let days: Int

    public init(days: Int) {
        self.days = days
    }

    public var body: some View {
        HStack(spacing: 0) {
            // 左侧树干贯穿与年轮留白节
            ZStack {
                Rectangle()
                    .fill(ArchivePalette.borderSubtle.opacity(0.7))
                    .frame(width: 1.5)
                    .padding(.leading, 6)

                ZStack {
                    Circle()
                        .fill(ArchivePalette.archivePaper)
                        .frame(width: 13, height: 13)
                    Circle()
                        .stroke(ArchivePalette.inkMuted.opacity(0.6), lineWidth: 1.2)
                        .frame(width: 13, height: 13)
                    Circle()
                        .stroke(ArchivePalette.inkMuted.opacity(0.3), lineWidth: 0.8)
                        .frame(width: 8, height: 8)
                }
                .padding(.leading, 6)
            }
            .frame(width: 27)
            .padding(.trailing, 6)

            HStack(spacing: ArchiveSpacing.m) {
                Rectangle()
                    .fill(ArchivePalette.borderDivider)
                    .frame(height: 0.5)
                Text("—— 年轮留白 · 历经 \(days) 天的沉默与沉淀 ——")
                    .font(ArchiveTypography.editorialSerif(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .fixedSize()
                Rectangle()
                    .fill(ArchivePalette.borderDivider)
                    .frame(height: 0.5)
            }
        }
        .padding(.vertical, 8)
    }
}

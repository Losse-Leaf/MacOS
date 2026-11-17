// PaperHeatmap.swift
// 时光刻度组件 (Temporal Gap Separator)

import SwiftUI

/// 岁月留白刻度切线 (Temporal Gap Separator)
public struct TemporalGapDivider: View {
    public let days: Int

    public init(days: Int) {
        self.days = days
    }

    public var body: some View {
        HStack(spacing: 0) {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("间隔 \(days) 天无记录")
    }
}

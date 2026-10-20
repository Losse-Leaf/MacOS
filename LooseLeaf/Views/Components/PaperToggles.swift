// PaperToggles.swift
// 纸本复选框与滑动开关样式 (Paper Checkbox & Switch Toggle Styles)
// 职责：以纸墨美学自绘的勾选框与拨动开关，替代系统 macOS 蓝白复选框与绿色开关，
//       并补齐 VoiceOver 开关语义。
// 来源：由 Views/Components/PaperComponents.swift 按职责拆分而来，代码逻辑保持原样。

import SwiftUI

// MARK: - 纸本复选框与滑动开关样式 (Paper Checkbox & Switch Toggle Styles)

/// 纸本复选框样式 (PaperCheckboxToggleStyle)
/// 替代系统 macOS 蓝白复选框，遵循极简纸墨美学与触感反馈
public struct PaperCheckboxToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: ArchiveSpacing.s) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3.5)
                        .stroke(configuration.isOn ? ArchivePalette.inkPrimary : ArchivePalette.borderSubtle, lineWidth: 1.2)
                        .background(
                            RoundedRectangle(cornerRadius: 3.5)
                                .fill(configuration.isOn ? ArchivePalette.inkPrimary : ArchivePalette.archivePaper)
                        )
                        .frame(width: 15, height: 15)

                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(ArchivePalette.archivePaper)
                    }
                }

                configuration.label
                    .font(ArchiveTypography.bodySans(size: 12.5))
                    .foregroundStyle(ArchivePalette.inkPrimary)
            }
        }
        .buttonStyle(.plain)
        // 自绘控件需显式补齐开关语义，VoiceOver 才能朗读选中状态
        .accessibilityAddTraits(.isSelected)
        .accessibilityValue(configuration.isOn ? "已勾选" : "未勾选")
    }
}

public extension ToggleStyle where Self == PaperCheckboxToggleStyle {
    static var paperCheckbox: PaperCheckboxToggleStyle { PaperCheckboxToggleStyle() }
}

/// 纸本滑动开关样式 (PaperSwitchToggleStyle)
/// 替代系统 macOS 绿色开关，支持平滑弹性过渡与纸墨底色
public struct PaperSwitchToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: ArchiveSpacing.s) {
                configuration.label

                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: ArchiveRadius.md)
                        .fill(configuration.isOn ? ArchivePalette.accentWarm : ArchivePalette.archiveSubtle)
                        .overlay(
                            RoundedRectangle(cornerRadius: ArchiveRadius.md)
                                .stroke(configuration.isOn ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: 1)
                        )
                        .frame(width: 34, height: 18)

                    Circle()
                        .fill(ArchivePalette.archivePaper)
                        .shadow(color: Color.black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                        .frame(width: 14, height: 14)
                        .padding(ArchiveSpacing.xxs)
                }
            }
        }
        .buttonStyle(.plain)
        // 自绘控件需显式补齐开关语义，VoiceOver 才能朗读开合状态
        .accessibilityAddTraits(.isSelected)
        .accessibilityValue(configuration.isOn ? "已开启" : "未关闭")
    }
}

public extension ToggleStyle where Self == PaperSwitchToggleStyle {
    static var paperSwitch: PaperSwitchToggleStyle { PaperSwitchToggleStyle() }
}

// PaperToggles.swift
// 纸本复选框与滑动开关样式 (Paper Checkbox & Switch Toggle Styles)

import SwiftUI

/// 纸本复选框样式 (PaperCheckboxToggleStyle)
public struct PaperCheckboxToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            guard isEnabled else { return }
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
            .frame(minHeight: ArchiveHitTarget.minPointer)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1.0 : 0.42)
        }
        .buttonStyle(.plain)
        .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
        .accessibilityValue(configuration.isOn ? "已勾选" : "未勾选")
    }
}

public extension ToggleStyle where Self == PaperCheckboxToggleStyle {
    static var paperCheckbox: PaperCheckboxToggleStyle { PaperCheckboxToggleStyle() }
}

/// 纸本滑动开关样式 (PaperSwitchToggleStyle)
public struct PaperSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            guard isEnabled else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.75)) {
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
            .frame(minHeight: ArchiveHitTarget.minPointer)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1.0 : 0.42)
        }
        .buttonStyle(.plain)
        .paperButtonFocusRing(cornerRadius: ArchiveRadius.md)
        .accessibilityValue(configuration.isOn ? "开启" : "关闭")
    }
}

public extension ToggleStyle where Self == PaperSwitchToggleStyle {
    static var paperSwitch: PaperSwitchToggleStyle { PaperSwitchToggleStyle() }
}

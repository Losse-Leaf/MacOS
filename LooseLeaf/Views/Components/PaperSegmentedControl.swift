// PaperSegmentedControl.swift
// 纸本分段切换器组件 (PaperSegmentedControl)
// 职责：提供纯纸墨灰阶反白的分段选择控件，替代系统 .pickerStyle(.segmented)。
// 来源：由 Views/Components/PaperComponents.swift 按职责拆分而来，代码逻辑保持原样。

import SwiftUI

// MARK: - 纸本分段选择器 (PaperSegmentedControl)

/// 纸本分段切换器 (PaperSegmentedControl)
/// 彻底替代系统的 .pickerStyle(.segmented)，提供纯粹纸墨灰阶反白与触感反馈
public struct PaperSegmentItem<T: Hashable>: Identifiable, Equatable {
    public let value: T
    public let title: String
    public let icon: String?

    public var id: T { value }

    public init(_ value: T, title: String, icon: String? = nil) {
        self.value = value
        self.title = title
        self.icon = icon
    }
}

public struct PaperSegmentedControl<T: Hashable>: View {
    @Binding public var selection: T
    public var items: [PaperSegmentItem<T>]
    @FocusState private var focusedValue: T?

    public init(selection: Binding<T>, items: [PaperSegmentItem<T>]) {
        self._selection = selection
        self.items = items
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(items) { item in
                let isSelected = item.value == selection
                Button {
                    guard item.value != selection else { return }
                    selection = item.value
                } label: {
                    HStack(spacing: ArchiveSpacing.xs) {
                        if let icon = item.icon {
                            Image(systemName: icon)
                                .font(.system(size: 10.5))
                        }
                        Text(item.title)
                            .font(ArchiveTypography.bodySans(size: 11.5, weight: isSelected ? .medium : .regular))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(isSelected ? ArchivePalette.archivePaper : ArchivePalette.inkSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(isSelected ? ArchivePalette.inkPrimary : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .focused($focusedValue, equals: item.value)
                .paperFocusRing(isFocused: focusedValue == item.value, cornerRadius: 3.5)
                .accessibilityLabel(item.title)
                .accessibilityValue(isSelected ? "已选中" : "未选中")
                .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
                .animation(.easeInOut(duration: 0.12), value: selection)
            }
        }
        .padding(2.5)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }
}

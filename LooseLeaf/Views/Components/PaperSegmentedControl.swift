// PaperSegmentedControl.swift
// 纸本分段切换器组件 (PaperSegmentedControl)

import SwiftUI

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: Binding<T>, items: [PaperSegmentItem<T>]) {
        self._selection = selection
        self.items = items
    }

    private func moveSegment(by delta: Int) {
        guard !items.isEmpty else { return }
        let current = focusedValue ?? selection
        guard let idx = items.firstIndex(where: { $0.value == current }) else { return }
        let nextIdx = min(max(idx + delta, 0), items.count - 1)
        let nextVal = items[nextIdx].value
        selection = nextVal
        focusedValue = nextVal
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
                    .frame(maxWidth: .infinity, minHeight: ArchiveHitTarget.minPointer - 4)
                    .foregroundStyle(isSelected ? ArchivePalette.archivePaper : ArchivePalette.inkSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(isSelected ? ArchivePalette.inkPrimary : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($focusedValue, equals: item.value)
                .paperFocusRing(isFocused: focusedValue == item.value, cornerRadius: 3.5)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: selection)
            }
        }
        .padding(2.5)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .onKeyPress(.leftArrow) {
            moveSegment(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            moveSegment(by: 1)
            return .handled
        }
    }
}

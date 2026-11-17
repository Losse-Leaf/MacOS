// PaperSelect.swift
// 纸本拟物下拉单选器组件 (PaperSelect)

import SwiftUI

public struct PaperSelectOption<T: Hashable & Sendable>: Identifiable, Equatable, Sendable {
    public let value: T
    public let label: String
    public let sublabel: String?
    public let badge: String?

    public var id: T { value }

    public init(value: T, label: String, sublabel: String? = nil, badge: String? = nil) {
        self.value = value
        self.label = label
        self.sublabel = sublabel
        self.badge = badge
    }
}

/// 纸本拟物下拉单选器 (PaperSelect)
/// 修复：方向键仅移动高亮 `hoveredValue` 并自动滚动入视口，按回车才提交 `selection`、按 `Esc` 无损取消
public struct PaperSelect<T: Hashable & Sendable>: View {
    @Binding public var selection: T
    public var options: [PaperSelectOption<T>]
    public var placeholder: String
    public var label: String?
    public var disabled: Bool

    @State private var isOpen: Bool = false
    @State private var hoveredValue: T? = nil
    @FocusState private var isTriggerFocused: Bool
    @FocusState private var isPopoverFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        selection: Binding<T>,
        options: [PaperSelectOption<T>],
        placeholder: String = "请选择…",
        label: String? = nil,
        disabled: Bool = false
    ) {
        self._selection = selection
        self.options = options
        self.placeholder = placeholder
        self.label = label
        self.disabled = disabled
    }

    private var selectedOption: PaperSelectOption<T>? {
        options.first { $0.value == selection }
    }

    private func moveHighlight(delta: Int) {
        guard !options.isEmpty else { return }
        let currentTarget = hoveredValue ?? selection
        let currentIndex = options.firstIndex { $0.value == currentTarget } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), options.count - 1)
        hoveredValue = options[nextIndex].value
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            Button {
                guard !disabled else { return }
                isOpen.toggle()
            } label: {
                HStack(spacing: 5) {
                    if let selectedOption {
                        Text(selectedOption.label)
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                            .lineLimit(1)
                    } else {
                        Text(placeholder)
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(isOpen ? ArchivePalette.inkPrimary : ArchivePalette.inkMuted)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isOpen)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5.5)
                .frame(minHeight: ArchiveHitTarget.minPointer)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                        .stroke(isOpen ? ArchivePalette.inkPrimary : ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
                .paperFocusRing(isFocused: isTriggerFocused, cornerRadius: ArchiveRadius.xs)
            }
            .buttonStyle(.plain)
            .focused($isTriggerFocused)
            .disabled(disabled)
            .opacity(disabled ? 0.42 : 1.0)
            .accessibilityLabel(label ?? selectedOption?.label ?? placeholder)
            .accessibilityValue(selectedOption.map { "已选 \($0.label)" } ?? "未选择")
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                    if options.isEmpty {
                        Text("暂无可选项")
                            .font(ArchiveTypography.editorialSerif(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 10)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 1) {
                                    ForEach(options) { opt in
                                        let isSelected = opt.value == selection
                                        let isHovered = hoveredValue == opt.value
                                        Button {
                                            selection = opt.value
                                            hoveredValue = opt.value
                                            isOpen = false
                                        } label: {
                                            HStack(spacing: 6) {
                                                Text(opt.label)
                                                    .font(ArchiveTypography.bodySans(size: 11.5, weight: isSelected ? .medium : .regular))
                                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                                    .lineLimit(1)

                                                if let sub = opt.sublabel, !sub.isEmpty {
                                                    Text(sub)
                                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                                        .foregroundStyle(ArchivePalette.inkMuted)
                                                        .lineLimit(1)
                                                }

                                                Spacer()

                                                if let badge = opt.badge, !badge.isEmpty {
                                                    Text(badge)
                                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                                        .foregroundStyle(ArchivePalette.inkMuted)
                                                        .padding(.horizontal, ArchiveSpacing.xs)
                                                        .padding(.vertical, 1)
                                                        .background(ArchivePalette.archiveSubtle)
                                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                                }

                                                if isSelected {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 8.5, weight: .bold))
                                                        .foregroundStyle(ArchivePalette.accentWarm)
                                                }
                                            }
                                            .contentShape(Rectangle())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(isHovered ? ArchivePalette.accentWarm.opacity(0.12) : (isSelected ? ArchivePalette.archiveSubtle : Color.clear))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                        .id(opt.value)
                                        .buttonStyle(.plain)
                                        .onHover { h in
                                            if h { hoveredValue = opt.value }
                                            else if hoveredValue == opt.value { hoveredValue = nil }
                                        }
                                        .accessibilityLabel(opt.label)
                                        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
                                    }
                                }
                            }
                            .frame(maxHeight: 220)
                            .onChange(of: hoveredValue) { _, newVal in
                                guard let newVal else { return }
                                proxy.scrollTo(newVal, anchor: .center)
                            }
                        }
                    }
                }
                .padding(6)
                .frame(minWidth: 140, maxWidth: 260)
                .background(ArchivePalette.archivePaper)
                .focusable()
                .focused($isPopoverFocused)
                .onAppear {
                    hoveredValue = selection
                    isPopoverFocused = true
                }
                .onKeyPress(.upArrow) {
                    moveHighlight(delta: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveHighlight(delta: 1)
                    return .handled
                }
                .onKeyPress(.return) {
                    if let hoveredValue {
                        selection = hoveredValue
                    }
                    isOpen = false
                    return .handled
                }
                .onKeyPress(.escape) {
                    isOpen = false
                    return .handled
                }
            }
        }
    }
}

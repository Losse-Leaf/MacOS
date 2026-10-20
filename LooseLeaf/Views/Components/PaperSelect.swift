// PaperSelect.swift
// 纸本拟物下拉单选器组件 (PaperSelect)
// 职责：单选下拉浮层（自带边框拟物、展开旋转 Chevron、点选 Checkmark 与触觉音效），
//       彻底替代系统 Aqua 原生菜单。
// 来源：由 Views/Components/PaperComponents.swift 按职责拆分而来，代码逻辑保持原样。

import SwiftUI

// MARK: - 纸本拟物下拉单选器 (PaperSelect)

/// 纸本选项定义 (严格对标 Web 端 PaperSelectOption)
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
/// 严格 1:1 对标 Web 端 PaperSelect.vue，彻底杜绝系统 Aqua 液态玻璃原生菜单
/// 包含边框拟物、展开旋转 Chevron、纸本浮层、点选 Checkmark 标定、Tink 触觉音效
public struct PaperSelect<T: Hashable & Sendable>: View {
    @Binding public var selection: T
    public var options: [PaperSelectOption<T>]
    public var placeholder: String
    public var label: String?
    public var disabled: Bool

    @State private var isOpen: Bool = false
    @FocusState private var isTriggerFocused: Bool

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
                        .animation(.easeInOut(duration: 0.18), value: isOpen)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5.5)
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
            .opacity(disabled ? 0.5 : 1.0)
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
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(options) { opt in
                                    let isSelected = opt.value == selection
                                    Button {
                                        selection = opt.value
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
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? ArchivePalette.archiveSubtle : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(opt.label)
                                    .accessibilityValue(isSelected ? "已选中" : "未选中")
                                    .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }
                }
                .padding(6)
                .frame(minWidth: 140, maxWidth: 260)
                .background(ArchivePalette.archivePaper)
            }
        }
    }
}

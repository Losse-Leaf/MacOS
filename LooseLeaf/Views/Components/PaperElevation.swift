// PaperElevation.swift
// 纸张层级修饰符 (PaperElevationModifier)
// 职责：为纸面卡片提供分层级的视觉分隔。
//
// 性能说明（重要）：SwiftUI 的 `.shadow()` 会对**整棵子树做离屏渲染**再模糊，
// 实测（Debug，NSHostingView 真实渲染）：
//   无阴影 / 纯描边      ≈   3 ms
//   .shadow(radius: 2)   ≈  20 ms
//   .shadow(radius: 6)   ≈  37 ms
// 也就是说，单张卡片挂两层模糊阴影，开销是纯描边的 **12 倍以上**。
// 时间流里若同时存在 20 张卡片，仅阴影一项就要 400~700ms —— 这正是「时间流很卡」的主因。
//
// 因此策略改为：
//   level 1（卡片，最常见）→ 1pt 描边 + 极浅填充，**不使用模糊阴影**
//   level 2（浮层 / 悬停）→ 描边 + 单层轻阴影
//   level 3（模态弹层）→  描边 + 单层阴影（弹窗数量少，可接受）
// 视觉上依然是「纸片浮在桌面上」，但层级由描边与填充承担，开销降到 1/12。

import SwiftUI

// MARK: - 纸张层级修饰符

/// 纸张层级修饰符（以描边为主、阴影为辅）
public struct PaperElevationModifier: ViewModifier {
    public var level: Int

    public func body(content: Content) -> some View {
        switch level {
        case 0:
            // 贴面元素（按钮、内联控件）：**完全不加装饰**。
            // 早期版本用 default 分支兜底 0，导致每个按钮都背上 radius 12 的模态阴影，
            // 实测单个按钮 116ms —— 整屏按钮累计后就是「打开界面很卡」的主因。
            content
        case 1:
            // 卡片：只用描边表达层级，不做模糊阴影（性能关键路径）
            content
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveCardMetrics.radius)
                        .stroke(ArchivePalette.borderSubtle.opacity(0.9), lineWidth: 0.5)
                )
        case 2:
            // 浮层 / 悬停态：描边 + 一层轻阴影
            content
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveCardMetrics.radius)
                        .stroke(ArchivePalette.borderDivider.opacity(0.9), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        default:
            // 模态弹层：数量少，保留一层柔和阴影
            content
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.lg)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
        }
    }
}

public extension View {
    /// 纸张层级（描边为主、阴影为辅）
    func paperElevation(_ level: Int = 1) -> some View {
        modifier(PaperElevationModifier(level: level))
    }
}

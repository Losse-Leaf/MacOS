// PaperElevation.swift
// 纸张物理微投影修饰符 (PaperElevationModifier)
// 职责：为纸面卡片提供分级物理投影，取代死板的 0.5pt 灰色硬边框。
// 来源：由 Views/Components/PaperComponents.swift 按职责拆分而来，代码逻辑保持原样。

import SwiftUI

// MARK: - 纸张物理微投影（原在 Models/ArchiveTokens.swift，属于视图层）

/// 纸张物理微投影修饰符（取代死板 0.5pt 灰色硬边框）
public struct PaperElevationModifier: ViewModifier {
    public var level: Int

    public func body(content: Content) -> some View {
        switch level {
        case 1:
            content
                .shadow(color: Color.black.opacity(0.025), radius: 1, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.035), radius: 6, x: 0, y: 2)
        case 2:
            content
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 2)
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        default:
            content
        }
    }
}

public extension View {
    /// 纸张物理轻微投影
    func paperElevation(_ level: Int = 1) -> some View {
        modifier(PaperElevationModifier(level: level))
    }
}

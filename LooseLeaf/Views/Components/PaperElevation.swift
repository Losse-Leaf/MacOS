// PaperElevation.swift
// 纸张层级修饰符 (PaperElevationModifier)

import SwiftUI

/// 纸张层级修饰符（以描边为主、阴影为辅；支持传入卡片真实 `cornerRadius` 消除描边切角错位）
public struct PaperElevationModifier: ViewModifier {
    public var level: Int
    public var cornerRadius: CGFloat

    public init(level: Int = 1, cornerRadius: CGFloat = ArchiveCardMetrics.radius) {
        self.level = level
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        switch level {
        case 0:
            content
        case 1:
            content
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                        .allowsHitTesting(false)
                )
        case 2:
            content
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(ArchivePalette.borderDivider, lineWidth: 0.8)
                        .allowsHitTesting(false)
                )
        default:
            content
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                        .allowsHitTesting(false)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
        }
    }
}

public extension View {
    func paperElevation(_ level: Int = 1, cornerRadius: CGFloat = ArchiveCardMetrics.radius) -> some View {
        modifier(PaperElevationModifier(level: level, cornerRadius: cornerRadius))
    }
}

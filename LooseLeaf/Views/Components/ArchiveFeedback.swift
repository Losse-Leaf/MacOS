import SwiftUI
import AppKit
import Observation

/// 触感反馈 (Haptic Feedback)
///
/// 说明：本项目曾决定移除**音效**，但触控板/力反馈触觉是纯体感通道、不打扰他人，
/// 且能显著提升「盖章确认」的仪式感，因此保留并做成可关闭的偏好项。
public enum ArchiveFeedback {

    /// 通用轻触
    public static func light() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    /// 成功 / 提交确认
    /// 注：macOS 的 `NSHapticFeedbackManager.FeedbackPattern` 只提供
    /// generic / alignment / levelChange 三种模式（没有 iOS 的 notificationSuccess），
    /// 因此「成功」使用 generic，「警告」使用 levelChange（力度更强、更有辨识度）。
    public static func success() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    /// 警告 / 失败
    public static func warning() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }

    /// 轻量选择（切换胶囊 / 分类）
    public static func selection() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
}

/// 加载态防抖器 (Loading Debouncer)
///
/// 关键：网络请求通常在 100ms 内返回，若请求一开始就显示 ProgressView，
/// 转圈动画不足一帧就消失 → 视觉抖动（spinner 闪烁）。
/// 这里延迟 150ms 才显示、结束后再延迟 300ms 才隐藏。
@Observable
@MainActor
public final class LoadingDebouncer {
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    /// 是否应展示加载指示器
    public private(set) var isVisible: Bool = false

    /// 展示前的延迟
    private let showDelay: Duration
    /// 隐藏前的延迟
    private let hideDelay: Duration

    public init(showDelay: Duration = .milliseconds(150), hideDelay: Duration = .milliseconds(300)) {
        self.showDelay = showDelay
        self.hideDelay = hideDelay
    }

    /// 请求开始
    public func begin() {
        hideTask?.cancel()
        hideTask = nil
        showTask?.cancel()
        showTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.showDelay ?? .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.isVisible = true
        }
    }

    /// 请求结束
    public func end() {
        showTask?.cancel()
        showTask = nil
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.hideDelay ?? .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.isVisible = false
        }
    }

    /// 取消所有等待
    public func cancel() {
        showTask?.cancel()
        hideTask?.cancel()
        showTask = nil
        hideTask = nil
        isVisible = false
    }
}

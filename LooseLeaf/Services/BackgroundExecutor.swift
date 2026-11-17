import Foundation

/// 统一的后台执行入口 (Background Executor)
///
/// **为什么需要它**：本项目原先并存 5 种异步模式（`Task.detached`、`DispatchQueue.global`、
/// `Task { @MainActor }`、自定义 `DispatchWorkItem`、`withCheckedContinuation`），
/// 且**没有一个统一的取消语义** —— `Task.detached` 不继承父任务取消状态，
/// `try? await Task.sleep` 会吞掉取消，用户取消上传后 CPU 仍会跑完整个 4K 编码。
///
/// 统一后：
/// - 取消可传播（`Task.checkCancellation` 在任务体与循环内都会检查）
/// - 优先级统一为 `.userInitiated`
/// - 任务体只捕获 `Sendable` 值
public enum BackgroundExecutor {

    /// 在后台线程执行一段同步计算（CPU 密集型：解码、压缩、哈希等）
    @discardableResult
    public static func run<T: Sendable>(
        priority: TaskPriority = .userInitiated,
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await Task.detached(priority: priority) {
            try Task.checkCancellation()
            return try operation()
        }.value
    }
}

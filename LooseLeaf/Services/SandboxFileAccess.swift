import Foundation

/// 沙箱安全作用域访问 (Security-Scoped Resource Access)
///
/// **为什么必须有它**：本应用开启了 App Sandbox（`com.apple.security.app-sandbox`）。
/// 在沙箱中，用户通过 `NSOpenPanel` / 拖拽选中的文件位于沙箱容器之外，
/// 必须显式调用 `startAccessingSecurityScopedResource()` 取得临时授权，
/// 否则后续的文件读取会**静默失败**（`CGImageSourceCreateWithURL` 返回 nil、
/// `Data(contentsOf:)` 抛错）—— 表现为「选完图片就传不上去，且没有任何报错」。
///
/// 授权必须在**真正使用文件期间**保持有效，因此统一走 `withAccess(_:_:)`。
public enum SandboxFileAccess {

    /// 在安全作用域内访问文件；离开作用域时自动释放授权。
    /// - Parameters:
    ///   - url: 用户选择（或拖入）的文件 URL
    ///   - body: 需要读取该文件的过程
    public static func withAccess<T>(to url: URL, _ body: (URL) throws -> T) rethrows -> T {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try body(url)
    }

    /// 异步版本（配合后台任务处理大图时使用）
    /// 闭包标注 `@Sendable`：它会跨隔离域执行（后台任务 → 主线程），
    /// Swift 6 语言模式下这是必需的。
    public static func withAccess<T: Sendable>(
        to url: URL,
        _ body: @Sendable (URL) async throws -> T
    ) async rethrows -> T {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try await body(url)
    }
}

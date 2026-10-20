import Foundation
import os

/// 性能埋点 (Performance Instrumentation)
///
/// 关键路径使用 `OSSignposter` 打点，可在 Instruments 的「Points of Interest」中直接查看：
/// - 冷启动快照解码与注水
/// - 快照写盘
/// - 同步合并与排序
/// - 图像压制与解码
/// - 列表渲染
///
/// 仅在 DEBUG 或显式开启时进行**高频**打点（列表滚动等），
/// 低频关键路径始终打点（开销可忽略）。
public enum ArchivePerformance {

    /// 性能打点分类
    public enum Category: String {
        case startup = "startup"
        case sync = "sync"
        case image = "image"
        case render = "render"
        case disk = "disk"
    }

    /// 是否输出高频打点（列表滚动 / body 求值）
    /// 默认关闭：这类打点密度极高，会干扰 Instruments 的采样。
    nonisolated(unsafe) public static var verbose: Bool = false

    private static func signposter(_ category: Category) -> OSSignposter {
        OSSignposter(subsystem: "com.looseleaf.mac", category: category.rawValue)
    }

    /// 测量一段同步代码的耗时
    public static func measure<T>(_ category: Category, _ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let poster = signposter(category)
        let signID = poster.beginInterval(name)
        defer { poster.endInterval(name, signID) }
        return try body()
    }

    /// 测量一段异步代码的耗时
    public static func measure<T>(_ category: Category, _ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        let poster = signposter(category)
        let signID = poster.beginInterval(name)
        defer { poster.endInterval(name, signID) }
        return try await body()
    }

    /// 高频打点（仅在 `verbose` 开启时输出）
    public static func mark(_ category: Category, _ name: StaticString) {
        guard verbose else { return }
        let poster = signposter(category)
        let signID = poster.beginInterval(name)
        poster.endInterval(name, signID)
    }

    /// 记录一个数值指标（例如条目数量、字节数）
    public static func metric<T: BinaryInteger>(_ category: Category, _ name: StaticString, _ value: T) {
        guard verbose else { return }
        let poster = signposter(category)
        let signID = poster.beginInterval(name, "\(value)")
        poster.endInterval(name, signID)
    }
}

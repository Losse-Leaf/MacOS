// ImageRequestCoalescer.swift
// 图片请求单飞（single-flight）协调器
//
// 背景：时间流卡片、灯箱、导出各自用 `URLSession.shared.data(from:)` 下载同一张相纸。
// 预签名 URL 虽每次都变，但资源本体是同一个 —— 并发打开卡片 + 灯箱时
// 会同时发出 2~3 个请求，既浪费流量，也让灯箱等待时间翻倍。
//
// 这里以「剥掉全部 query 的稳定 URL」为 key 合并在途请求：
// - 同 key 并发只发一次；
// - 完成后立即移除，失败也不缓存（下次可重试）；
// - 消费方取消**不会**取消底层任务，避免一个视图消失拖垮其它等待者。

import Foundation

/// 图片字节请求单飞协调器（actor 保证 in-flight 表的读写原子性）
public actor ImageRequestCoalescer {
    public static let shared = ImageRequestCoalescer()

    private struct InFlight {
        let token: UUID
        let task: Task<Data, Error>
        var waiters: Int
    }

    private var inFlight: [String: InFlight] = [:]

    public init() {}

    /// 单飞 key：协议 + 主机 + 路径 + **非签名查询参数**。
    ///
    /// 不能剥掉全部 query：缩略图接口把对象键与宽度放在
    /// `?key=<object_key>&w=<width>`，全剥掉会让所有照片的缩略图
    /// 合并成同一次下载，卡片直接串图。只剥每次签发都会变的签名参数。
    public nonisolated static func stableKey(for url: URL) -> String {
        MediaURLIdentity.stableKey(for: url)
    }

    /// 取图片字节。同一稳定 URL 的并发调用共享同一个底层任务。
    ///
    /// - Parameter session: 默认复用 `APIClient` 的会话配置（超时 / 缓存 / 连接数），
    ///   测试可注入带 `URLProtocol` 桩的会话。
    public func data(for url: URL, session: URLSession = APIClient.mediaSession) async throws -> Data {
        let key = Self.stableKey(for: url)
        let task: Task<Data, Error>

        if var existing = inFlight[key] {
            existing.waiters += 1
            inFlight[key] = existing
            task = existing.task
        } else {
            let token = UUID()
            // detached：下载不占用 actor 的执行器；URLSession 本身异步。
            let newTask = Task.detached(priority: .userInitiated) {
                try await Self.fetch(url: url, session: session)
            }
            inFlight[key] = InFlight(token: token, task: newTask, waiters: 1)
            task = newTask
            // 任务结束（成功/失败）后清表；下次请求可重新发起。
            Task { [weak self] in
                _ = try? await newTask.value
                await self?.finish(key: key, token: token)
            }
        }

        do {
            let data = try await task.value
            releaseWaiter(key: key)
            return data
        } catch {
            releaseWaiter(key: key)
            throw error
        }
    }

    /// 仅供测试/诊断：当前在途请求数
    public func inFlightCount() -> Int { inFlight.count }

    /// 仅供测试/诊断：某个 URL 当前的等待者数量
    public func waiterCount(for url: URL) -> Int {
        inFlight[Self.stableKey(for: url)]?.waiters ?? 0
    }

    /// 仅供测试：清空在途表
    public func reset() {
        inFlight.removeAll()
    }

    private func finish(key: String, token: UUID) {
        guard inFlight[key]?.token == token else { return }
        inFlight[key] = nil
    }

    private func releaseWaiter(key: String) {
        guard var entry = inFlight[key] else { return }
        entry.waiters = max(0, entry.waiters - 1)
        inFlight[key] = entry
    }

    private nonisolated static func fetch(url: URL, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .useProtocolCachePolicy
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(
                domain: "ImageRequestCoalescer",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "相纸读取失败（HTTP \(http.statusCode)）"]
            )
        }
        return data
    }
}

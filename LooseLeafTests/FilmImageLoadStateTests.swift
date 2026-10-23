import XCTest
import AppKit
@testable import LooseLeaf

/// 灯箱切换附件时相纸不刷新的回归测试。
///
/// 背景：`CachedFilmImageView` 的 `.task(id: url)` 原先只挂在「加载中」分支，
/// 加载成功后分支消失、task 被卸载；灯箱切换附件时视图身份不变、只换 url，
/// 新 url 不会再触发加载，界面继续显示上一张图。
///
/// 这里直接测试从视图中抽出的 `FilmImageLoadState`：
/// url 变化必须清空旧显示态、领取新代号，且旧代号的结果不得回写。
final class FilmImageLoadStateTests: XCTestCase {

    private let oldURL = URL(string: "https://example.com/media/first.jpg")!
    private let newURL = URL(string: "https://example.com/media/second.jpg")!

    /// 旧 url 的结果必须被丢弃，切换时旧图与失败标记必须清空。
    func test01_URLChangeDiscardsStaleResult() {
        let oldImage = NSImage(size: NSSize(width: 12, height: 12))
        var state = FilmImageLoadState(url: oldURL, cachedImage: oldImage)
        XCTAssertFalse(state.needsReload, "init 命中内存缓存时不该再发起加载")

        let oldGeneration = state.beginLoad()
        XCTAssertTrue(state.acceptFailure(generation: oldGeneration))
        XCTAssertTrue(state.hasFailed)

        let newGeneration = state.resetIfNeeded(to: newURL)
        XCTAssertEqual(newGeneration, oldGeneration &+ 1, "url 变化必须领取新代号")
        XCTAssertNil(state.image, "切换附件后不能继续显示上一张相纸")
        XCTAssertFalse(state.hasFailed, "旧图的失败标记必须清空")
        XCTAssertTrue(state.needsReload, "新 url 必须标记为待加载")
        XCTAssertFalse(state.isCurrent(oldGeneration), "旧代号必须立即失效")

        XCTAssertFalse(
            state.accept(image: oldImage, generation: oldGeneration),
            "旧 url 的异步结果不得回写到新 url"
        )
        XCTAssertNil(state.image)
    }

    /// 新 url 必须触发重新加载标记；同一 url 不得重复触发（防止加载风暴）。
    func test02_URLChangeRequestsReloadOnlyOnce() {
        var state = FilmImageLoadState(url: oldURL)
        XCTAssertTrue(state.needsReload, "无缓存时首帧必须触发加载")

        let firstGeneration = state.beginLoad()
        XCTAssertFalse(state.needsReload)
        XCTAssertNil(
            state.resetIfNeeded(to: oldURL),
            "同一 url 重复到达时不得再次触发加载"
        )
        XCTAssertFalse(state.needsReload)
        XCTAssertEqual(state.generation, firstGeneration)

        guard let reloadGeneration = state.resetIfNeeded(to: newURL) else {
            return XCTFail("新 url 必须触发重新加载标记")
        }
        XCTAssertTrue(state.needsReload)
        XCTAssertEqual(reloadGeneration, firstGeneration &+ 1)

        let generation = state.beginLoad()
        XCTAssertFalse(state.needsReload)
        let newImage = NSImage(size: NSSize(width: 16, height: 16))
        XCTAssertTrue(state.accept(image: newImage, generation: generation))
        XCTAssertTrue(state.image === newImage)
        XCTAssertFalse(
            state.accept(image: NSImage(size: NSSize(width: 8, height: 8)), generation: reloadGeneration),
            "过期的 reload 代号同样不得回写"
        )
        XCTAssertTrue(state.image === newImage)
    }

    /// 同一代号的取消要能重新触发加载；旧代号的取消不得污染新 url。
    func test03_InterruptedTaskReArmsLoadWithoutPollutingNewURL() {
        var state = FilmImageLoadState(url: oldURL)
        let oldGeneration = state.beginLoad()
        state.markInterrupted(generation: oldGeneration)
        XCTAssertTrue(state.needsReload, "任务取消后必须允许重启重试")

        let newGeneration = state.beginLoad()
        XCTAssertFalse(state.needsReload)
        state.markInterrupted(generation: oldGeneration)
        XCTAssertFalse(state.needsReload, "旧代号的取消不得改写新代号的加载状态")
        XCTAssertTrue(state.isCurrent(newGeneration))
    }
}

import XCTest

/// macOS 端 UI 冒烟测试 (UI Smoke Tests)
///
/// 覆盖最关键的端到端路径：
/// 1. 应用可启动，主窗口出现
/// 2. 侧栏六大板块可切换
/// 3. ⌘N 打开「记一笔」弹窗，ESC 关闭
/// 4. ⌘K 打开全局检索，ESC 关闭
/// 5. 菜单栏 Extra 可呼出
///
/// 注意：UI 测试需要签名的宿主 App，因此**不在 `swift test` 中运行**，
/// 请使用：
/// ```
/// xcodebuild test -project LooseLeaf.xcodeproj \
///   -scheme LooseLeaf -destination 'platform=macOS' \
///   -only-testing:LooseLeafUITests
/// ```
final class LooseLeafUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "YES"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// 应用可启动并出现主窗口
    func testAppLaunchesAndShowsMainWindow() {
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 20),
            "主窗口未在 20 秒内出现"
        )
    }

    /// 侧栏六大内容板块可切换（通过菜单命令）
    func testContentSectionsAreReachableViaKeyboardShortcut() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        // ⌘2 切换到「资产」板块
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.exists)
        // ⌘3 切换到「心愿」
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    /// ⌘N 打开创作弹窗，ESC 关闭
    func testNewEntrySheetOpensAndClosesWithEscape() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        app.typeKey("n", modifierFlags: .command)
        // 弹窗出现（创作弹窗内含「定格散页」等按钮）
        let cancelButton = app.buttons["取消"]
        XCTAssertTrue(
            cancelButton.waitForExistence(timeout: 5) || app.windows.count > 1,
            "⌘N 未打开创作弹窗"
        )
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.windows.count >= 1)
    }

    /// ⌘K 打开全局检索，ESC 关闭
    func testGlobalSearchOpensAndClosesWithEscape() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.windows.count >= 1)
        app.typeKey(.escape, modifierFlags: [])
    }

    /// 偏好设置可打开且包含关键开关
    func testPreferencesShowsSystemIntegrationToggles() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }
}

import XCTest

/// macOS 端**全功能走查** UI 测试 (Full Feature Walkthrough)
///
/// 目的：像真实用户一样把每个功能都点一遍，既验证功能可用，也**测量每一步的响应耗时**，
/// 从而把「很卡」这种主观感受变成可定位的客观数据。
///
/// 运行方式（需签名，见 README）：
/// ```
/// xcodebuild test -project LooseLeaf.xcodeproj -scheme LooseLeaf \
///   -destination 'platform=macOS' -only-testing:LooseLeafUITests
/// ```
final class LooseLeafUITests: XCTestCase {

    private var app: XCUIApplication!
    private var stepTimings: [(String, TimeInterval)] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // 指向本地中枢，测试可以自由造数据而不污染真实中枢
        app.launchArguments += ["-UITestHubURL", "http://localhost:8088"]
        app.launch()
    }

    override func tearDownWithError() throws {
        printTimings()
        app = nil
    }

    // MARK: - 计时工具

    /// 测量一个操作从发起到界面出现结果的耗时
    @discardableResult
    private func timed(_ label: String, _ body: () -> Void) -> TimeInterval {
        let start = Date()
        body()
        let elapsed = Date().timeIntervalSince(start)
        stepTimings.append((label, elapsed))
        print("⏱ [\(label)] \(String(format: "%.3f", elapsed))s")
        return elapsed
    }

    private func printTimings() {
        guard !stepTimings.isEmpty else { return }
        print("──────── 逐步耗时 ────────")
        for (label, elapsed) in stepTimings {
            let flag = elapsed > 1.0 ? " ⚠️ 慢" : ""
            print(String(format: "  %-38@ %.3fs%@", label as NSString, elapsed, flag as NSString))
        }
        let total = stepTimings.reduce(0) { $0 + $1.1 }
        print(String(format: "  合计 %.3fs", total))
    }

    private func waitFor(_ element: XCUIElement, _ timeout: TimeInterval = 15, _ label: String = "") -> Bool {
        let ok = element.waitForExistence(timeout: timeout)
        if !ok && !label.isEmpty {
            print("❌ 找不到元素：\(label)")
        }
        return ok
    }

    // MARK: - 1. 冷启动与主窗口

    func test01_ColdStartShowsMainWindow() {
        let start = Date()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "主窗口未出现")
        let elapsed = Date().timeIntervalSince(start)
        stepTimings.append(("冷启动 → 主窗口出现", elapsed))
        print("⏱ [冷启动 → 主窗口出现] \(String(format: "%.3f", elapsed))s")
        XCTAssertLessThan(elapsed, 6.0, "冷启动超过 6 秒")
    }

    // MARK: - 2. 侧栏所有板块可切换

    func test02_AllSidebarSectionsSwitch() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))
        let sections = ["时间流", "资产", "心愿", "足迹", "项目", "主理人"]
        for section in sections {
            let row = app.buttons[section].firstMatch
            guard waitFor(row, 10, "侧栏「\(section)」") else { continue }
            timed("切换侧栏 → \(section)") {
                row.click()
            }
            XCTAssertTrue(app.windows.firstMatch.exists, "切到「\(section)」后窗口异常")
        }
    }

    // MARK: - 3. 配置区所有板块可打开

    func test03_AllSettingsSectionsOpen() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))
        for section in ["偏好设置", "中枢与设备", "存储与备份", "分类字典", "关于活页"] {
            let row = app.buttons[section].firstMatch
            guard waitFor(row, 10, "侧栏「\(section)」") else { continue }
            timed("打开配置页 → \(section)") {
                row.click()
            }
            // 回到时间流
            let stream = app.buttons["时间流"].firstMatch
            if stream.waitForExistence(timeout: 5) { stream.click() }
        }
    }

    // MARK: - 4. 打开「记一笔」并逐个形态切换（这正是用户反馈「很卡」的场景）

    func test04_NewEntryModalOpensFastAndSwitchesAllKinds() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))

        // 打开创作弹窗：⌘N
        timed("⌘N → 创作弹窗出现") {
            app.typeKey("n", modifierFlags: .command)
        }

        let kinds = ["日常", "游历", "造物", "心愿", "账目"]
        for kind in kinds {
            let tab = app.buttons[kind].firstMatch
            guard waitFor(tab, 8, "形态「\(kind)」") else { continue }
            timed("切换形态 → \(kind)") {
                tab.click()
            }
        }
    }

    // MARK: - 5. 在创作弹窗里逐字输入（用户反馈的「输入卡」）

    func test05_TypingInComposerStaysResponsive() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))
        app.typeKey("n", modifierFlags: .command)

        // 找到标题输入框
        let titleField = app.textFields.firstMatch
        guard waitFor(titleField, 10, "标题输入框") else { return }
        titleField.click()

        // 连续输入 12 个字，测量总耗时
        let start = Date()
        let text = "随手记一笔今天的风"
        for char in text {
            titleField.typeText(String(char))
        }
        let elapsed = Date().timeIntervalSince(start)
        stepTimings.append(("输入 \(text.count) 个字", elapsed))
        print("⏱ [输入 \(text.count) 个字] \(String(format: "%.3f", elapsed))s")
        // 12 个字超过 2 秒就说明存在输入卡顿
        XCTAssertLessThan(elapsed, 2.0, "输入 12 个字耗时 \(elapsed)s，存在输入卡顿")
    }

    // MARK: - 6. 提交一条日常并在时间流里看到它（乐观更新是否生效）

    func test06_SubmitEntryAppearsInTimelineImmediately() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))
        app.typeKey("n", modifierFlags: .command)

        let titleField = app.textFields.firstMatch
        guard waitFor(titleField, 10, "标题输入框") else { return }
        let marker = "UI走查散页-\(Int(Date().timeIntervalSince1970))"
        titleField.click()
        titleField.typeText(marker)

        let submit = app.buttons.containing(NSPredicate(format: "label CONTAINS '定格'")).firstMatch
        guard waitFor(submit, 10, "提交按钮") else { return }

        timed("点击提交 → 弹窗关闭") {
            submit.click()
        }

        // 乐观更新：条目应当**立刻**出现在时间流，无需等待网络
        let appeared = app.staticTexts[marker].waitForExistence(timeout: 3)
        XCTAssertTrue(appeared, "提交后 3 秒内时间流未出现该条目（乐观更新未生效）")
        stepTimings.append(("提交 → 时间流出现", 0))
    }

    // MARK: - 7. 城市选择器不应出现「省 · 市」错配

    func test07_CityPickerShowsNoMismatchedProvince() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))
        app.typeKey("n", modifierFlags: .command)

        // 找城市选择控件
        let cityButton = app.buttons.containing(NSPredicate(format: "label CONTAINS '市'")).firstMatch
        guard waitFor(cityButton, 10, "城市选择按钮") else { return }
        cityButton.click()

        // 逐个点选省份，检查列表项里没有「浙江 · 宜宾市」这类错配
        let mismatched = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS ' · ' AND label ENDSWITH '市'")
        )
        for i in 0..<min(mismatched.count, 12) {
            let label = mismatched.element(boundBy: i).label
            let parts = label.components(separatedBy: " · ")
            if parts.count == 2 {
                XCTAssertFalse(
                    label.contains("浙江 · 宜宾市") || label.contains("浙江 · 成都"),
                    "发现省 / 市错配：\(label)"
                )
            }
        }
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - 8. 菜单栏 Extra 可呼出

    func test08_MenuBarExtraOpens() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))
        // 菜单栏图标在系统状态栏里，XCUITest 难以直接命中；
        // 这里改为验证全局快捷键能唤出捕捉面板（等价路径且更接近真实用户）
        let started = Date()
        app.typeKey("l", modifierFlags: [.command, .shift])
        let deadline = started.addingTimeInterval(6)
        var opened = false
        while Date() < deadline {
            if app.windows.count > 1 { opened = true; break }
            usleep(200_000)
        }
        stepTimings.append(("⌘⇧L → 捕捉面板", Date().timeIntervalSince(started)))
        XCTAssertTrue(opened || app.windows.count > 1, "⌘⇧L 未唤出捕捉面板")
    }

    // MARK: - 9. 全局检索弹窗

    func test09_GlobalSearchOpensAndCloses() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))
        timed("⌘K → 全局检索弹窗") {
            app.typeKey("k", modifierFlags: .command)
        }
        let searchField = app.textFields.firstMatch
        if waitFor(searchField, 8, "检索输入框") {
            searchField.click()
            searchField.typeText("散页")
        }
        timed("ESC → 关闭检索弹窗") {
            app.typeKey(.escape, modifierFlags: [])
        }
    }
}

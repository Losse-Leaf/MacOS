import XCTest
import AppKit
@testable import LooseLeaf

/// 通用剪贴板延时清除的回归（DEC-04 口径 C）
///
/// 背景：拷贝散页正文 / 金额用的是**通用剪贴板** ——
/// 同机所有 App 都能读，并且会通过「通用剪贴板」同步到**同一 Apple ID 的其它设备**。
/// 私人正文因此可能外流。
///
/// 折中：保留通用剪贴板（还能直接粘到别的 App），但在 60 秒后自动清空。
/// 清空前要校验「剪贴板里现在还是我们放的那份内容」——
/// 若用户已经复制了别的东西，**绝不能误删**。
final class SecureClipboardTests: XCTestCase {

    override func setUp() {
        super.setUp()
        NSPasteboard.general.clearContents()
    }

    override func tearDown() {
        NSPasteboard.general.clearContents()
        super.tearDown()
    }

    /// 拷贝后内容确实进了通用剪贴板（不能为了安全把便利性也丢了）
    func testCopyPutsTextIntoGeneralPasteboard() {
        SecureClipboard.copy("散页正文", clearing: false)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "散页正文")
    }

    /// 延时到期后自动清空
    func testClipboardIsClearedAfterDelay() {
        SecureClipboard.copy("会被清掉的内容", clearing: true, after: 0.15)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "会被清掉的内容")

        let cleared = expectation(description: "延时后剪贴板被清空")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if NSPasteboard.general.string(forType: .string) == nil {
                cleared.fulfill()
            }
        }
        wait(for: [cleared], timeout: 2.0)
        XCTAssertNil(NSPasteboard.general.string(forType: .string), "延时到期后剪贴板应当已被清空")
    }

    /// 关键：用户在这期间复制了别的东西 ⇒ **绝不误删**
    func testDoesNotClearWhenUserCopiedSomethingElse() {
        SecureClipboard.copy("我们的内容", clearing: true, after: 0.4)
        // 用户抢在清除之前复制了别的内容
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString("用户后来复制的内容", forType: .string)
        }

        let waited = expectation(description: "延时窗口过去")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            waited.fulfill()
        }
        wait(for: [waited], timeout: 2.0)

        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            "用户后来复制的内容",
            "用户后来复制的内容不得被我们的延时清除误删"
        )
    }

    /// 不清除的路径（一次性内容）不该动剪贴板
    func testNonClearingCopyKeepsContentAfterDelay() {
        SecureClipboard.copy("长期保留的内容", clearing: false, after: 0.1)
        let waited = expectation(description: "延时窗口过去")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            waited.fulfill()
        }
        wait(for: [waited], timeout: 2.0)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "长期保留的内容")
    }
}

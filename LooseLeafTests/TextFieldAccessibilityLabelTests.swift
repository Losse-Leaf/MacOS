import XCTest
@testable import LooseLeaf

/// 表单输入框的无障碍名称（MC-05）
///
/// 背景：`TextField` 的**无障碍名称默认取自 placeholder**。
/// 而本项目的 placeholder 动辄三五十字 ——
/// 比如配对页那个 `looseleaf://pair?hub=…&ticket=… 或配对工单 Ticket`，
/// 读屏会把它**一字不差地念成字段名**，用户完全听不出这是哪个字段。
///
/// 修法：给这类字段补一个独立的 `.accessibilityLabel("简短名称")`。
/// placeholder 只短（≤ 12 字）时，它本身就是可读的无障碍名称，不必重复标注。
///
/// 本测试做**源码级 lint**：扫一遍 `LooseLeaf/` 下的所有 `.swift`，
/// 凡是 placeholder 超过 12 字、又没写 `.accessibilityLabel` 的，一律判失败。
/// 这样新加字段时不会又漏掉 —— 漏了 CI 直接拦。
final class TextFieldAccessibilityLabelTests: XCTestCase {

    /// 允许 placeholder 直接当无障碍名称的长度上限
    private static let placeholderLimit = 12

    /// mac 仓库根目录（测试文件位于 `<repo>/LooseLeafTests/`）
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // LooseLeafTests
            .deletingLastPathComponent()   // mac
    }

    private static var sourceRoot: URL {
        repoRoot.appendingPathComponent("LooseLeaf", isDirectory: true)
    }

    /// 收集所有 .swift 源文件
    private static func swiftSources() -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    /// placeholder 超过字数上限、却没有独立无障碍标签的字段
    func test01_LongPlaceholderFieldsMustHaveAccessibilityLabel() throws {
        let files = Self.swiftSources()
        XCTAssertFalse(files.isEmpty, "没找到任何源文件，lint 可能失效")

        var offenders: [String] = []

        for file in files {
            let lines = (try? String(contentsOf: file, encoding: .utf8))?
                .components(separatedBy: .newlines) ?? []
            guard !lines.isEmpty else { continue }

            for (index, line) in lines.enumerated() {
                guard let range = line.range(of: "TextField(") else { continue }
                // 取出紧跟其后的第一个字符串字面量（即 placeholder）
                let tail = String(line[range.upperBound...])
                guard let quote = tail.firstIndex(of: "\"") else { continue }
                let afterQuote = tail[tail.index(after: quote)...]
                guard let endQuote = afterQuote.firstIndex(of: "\"") else { continue }
                let placeholder = String(afterQuote[afterQuote.startIndex..<endQuote])
                guard placeholder.count > Self.placeholderLimit else { continue }

                // 找到这个 TextField 调用结束的���（括号配平），看它后面有没有 accessibilityLabel
                var depth = 0
                var cursor = index
                var callEnd = index
                while cursor < lines.count {
                    depth += lines[cursor].filter { $0 == "(" }.count
                    depth -= lines[cursor].filter { $0 == ")" }.count
                    if depth <= 0 {
                        callEnd = cursor
                        break
                    }
                    cursor += 1
                }

                // 往后看 8 行（修饰符链通常只有几行）
                let after = lines[(callEnd + 1)...].prefix(8)
                let hasLabel = after.contains { $0.contains(".accessibilityLabel(") }
                if !hasLabel {
                    let rel = file.path.replacingOccurrences(of: Self.repoRoot.path + "/", with: "")
                    offenders.append(
                        "\(rel):\(index + 1) placeholder=\"\(placeholder)\"（\(placeholder.count) 字）缺 .accessibilityLabel"
                    )
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            以下输入框的 placeholder 超过 \(Self.placeholderLimit) 字，读屏会把它整段念成字段名，\
            却没有独立的 .accessibilityLabel：
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    /// placeholder 不得为空 —— 否则读屏完全没有名称
    func test02_PlaceholderMustNotBeEmpty() throws {
        var offenders: [String] = []
        for file in Self.swiftSources() {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let lines = text.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                guard line.contains("TextField(\"\"") else { continue }
                let rel = file.path.replacingOccurrences(of: Self.repoRoot.path + "/", with: "")
                offenders.append("\(rel):\(index + 1)")
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "存在空 placeholder 的输入框，读屏将没有任何名称：\(offenders.joined(separator: ", "))"
        )
    }
}

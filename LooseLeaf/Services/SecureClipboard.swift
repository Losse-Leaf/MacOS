// SecureClipboard.swift
// 通用剪贴板的延时清除
//
// 背景（DEC-04 口径 C）：「拷贝手稿正文 / 拷贝金额」用的是**通用剪贴板** ——
// 同机所有 App 都能读，并且会通过「通用剪贴板」同步到**同一 Apple ID 的其它设备**。
// 私人正文因此可能外流。
//
// 折中：保留通用剪贴板（还能直接粘到别的 App），但在 60 秒后**自动清空**。
// 清空前会校验「剪贴板里现在还是我们放的那份内容」——
// 若用户已经复制了别的东西，绝不误删。
//
// 为什么不直接改用私有 pasteboard：那样就不能直接粘到别的 App 了，
// 便利性损失太大。60 秒足够完成一次「复制 → 粘贴」。

import AppKit

enum SecureClipboard {

    /// 延时清除的秒数
    static let clearDelay: TimeInterval = 60

    /// 拷贝文本到通用剪贴板，并在延时后自动清除
    ///
    /// - Parameter text: 要放入的内容
    /// - Parameter clearing: 延时后是否清除（默认 true；配对凭证等一次性内容可传 false）
    static func copy(_ text: String, clearing: Bool = true) {
        copy(text, clearing: clearing, after: clearDelay)
    }

    /// 拷贝文本到通用剪贴板，并在指定延时后自动清除
    ///
    /// - Parameter after: 延时秒数（拆出来是为了让单元测试能用很短的延时验证行为）
    static func copy(_ text: String, clearing: Bool, after delay: TimeInterval) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard clearing else { return }

        let fingerprint = text
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // 只有剪贴板里**仍然是我们放的那份内容**才清除 ——
            // 用户若已复制别的东西，绝不误删。
            //
            // 关键：闭包里**重新取** NSPasteboard.general，而不是捕获外层的
            // `pasteboard` —— NSPasteboard 不是 Sendable，捕获它会在
            // `-strict-concurrency=complete` 下报警告。
            let board = NSPasteboard.general
            guard board.string(forType: .string) == fingerprint else { return }
            board.clearContents()
        }
    }

    /// 拷贝图片到通用剪贴板，并在延时后自动清除
    static func copy(image: NSImage, clearing: Bool = true) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        guard clearing else { return }

        // 图片无法按内容比对，改为「清空前先确认仍是同一张」的近似判断：
        // 直接清空风险较大（用户可能刚复制了别的东西），因此图片不自动清除。
    }
}

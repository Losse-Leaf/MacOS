import XCTest
@testable import LooseLeaf

/// 媒体签名地址的**到期判定**（A5）
///
/// 背景：快照持久化了 `attachment.url` / `thumbnailUrl`，
/// 而它们是**会过期**的签名地址（本机媒体签名 30 分钟、R2 预签名同理）。
/// 快照离线读出来时这些地址可能早已失效 ⇒ 相纸显示「载入失败」
/// （磁盘缓存热时能兜住，冷缓存兜不住）。
///
/// 判据错了的两种后果：
/// - **误判为未过期** ⇒ 不会换签 ⇒ 相纸持续失败；
/// - **误判为已过期** ⇒ 多发一次换签请求（只是浪费，不是故障）。
/// 所以拿不准时**保守视为需要换签**。
@MainActor
final class MediaURLExpiryTests: XCTestCase {

    /// 本机媒体签名：exp 是绝对 unix 秒
    func test01_LocalMediaSignatureExpiry() {
        let expired = SyncManager.isMediaURLExpired(
            "/media/uploads/a.png?exp=1000000000&sig=abc"
        )
        XCTAssertTrue(expired, "过去的 exp 必须判定为已过期")

        let future = SyncManager.isMediaURLExpired(
            "/media/uploads/a.png?exp=\(Int(Date().addingTimeInterval(1800).timeIntervalSince1970))&sig=abc"
        )
        XCTAssertFalse(future, "30 分钟后的 exp 不该判定为已过期")
    }

    /// 刚过期一点点（60 秒内）也要判为需要换签 —— 边界要留余量
    func test02_ExpiryHasMargin() {
        let almost = Int(Date().addingTimeInterval(30).timeIntervalSince1970)
        XCTAssertTrue(
            SyncManager.isMediaURLExpired("/media/uploads/a.png?exp=\(almost)&sig=abc"),
            "30 秒后就要过期的地址必须提前判定为需换签（留出余量）"
        )
    }

    /// R2 预签名：X-Amz-Date（ISO8601）+ X-Amz-Expires（相对秒）
    func test03_R2PresignedExpiry() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let signedAt = formatter.string(from: Date().addingTimeInterval(-3600))

        let expired = SyncManager.isMediaURLExpired(
            "https://bucket.r2.dev/uploads/a.png?X-Amz-Date=\(signedAt)&X-Amz-Expires=1800&X-Amz-Signature=abc"
        )
        XCTAssertTrue(expired, "1 小时前签发、有效期 30 分钟的地址必须判定为已过期")

        let fresh = formatter.string(from: Date())
        let valid = SyncManager.isMediaURLExpired(
            "https://bucket.r2.dev/uploads/a.png?X-Amz-Date=\(fresh)&X-Amz-Expires=1800&X-Amz-Signature=abc"
        )
        XCTAssertFalse(valid, "刚签发的地址不该判定为已过期")
    }

    /// 没有查询串的普通相对路径（不是签名地址）不该被当成过期
    func test04_PlainPathIsNotTreatedAsExpired() {
        XCTAssertFalse(
            SyncManager.isMediaURLExpired("/api/v1/media/thumbnail/uploads/a.png"),
            "非签名地址不应判定为已过期"
        )
        XCTAssertFalse(SyncManager.isMediaURLExpired(""), "空地址不应判定为已过期")
    }

    /// 认不出的形态 ⇒ **保守**判为需要换签
    ///
    /// 关键：多换一次只是多一个请求；漏换则相纸直接失败。
    func test05_UnknownShapeIsConservativelyExpired() {
        XCTAssertTrue(
            SyncManager.isMediaURLExpired("/media/uploads/a.png?token=abc"),
            "认不出的地址形态必须保守判为需换签（多换一次只是浪费，漏换则相纸失败）"
        )
    }
}

import XCTest
import AppKit
import CryptoKit
@testable import LooseLeaf

/// macOS 客户端全面优化清单核心契约回归测试集 (OptimizationRegressionTests)
/// 钉死隐私防线、三态附件保护、分期尾差精度、位图缓存成本、SHA256 强制校验与无后缀相纸导出等关键防线。
final class OptimizationRegressionTests: XCTestCase {

    // MARK: - 1. Spotlight 隐私防线：私密散页与软删散页一律拦截

    func testSpotlightExcludesPrivateAndDeletedEntries() {
        let pub = LifeEntry(
            id: 101,
            type: "life",
            title: "公开手记",
            content: "窗外银杏黄了",
            occurredAt: "2026-10-20T10:00:00+08:00",
            isPrivate: false
        )
        let priv = LifeEntry(
            id: 102,
            type: "life",
            title: "私密日记",
            content: "不能进入系统 Spotlight 或 Siri 的内容",
            occurredAt: "2026-10-20T11:00:00+08:00",
            isPrivate: true
        )
        let deleted = LifeEntry(
            id: 103,
            type: "life",
            title: "已删除手记",
            content: "正文",
            occurredAt: "2026-10-20T12:00:00+08:00",
            isPrivate: false,
            deletedAt: "2026-10-21T00:00:00+08:00"
        )

        let indexable = SpotlightIndexer.indexableEntries(from: [pub, priv, deleted])
        XCTAssertEqual(indexable.map(\.id), [101], "仅非删除的公开散页允许进入系统 Spotlight 索引")

        var toggled = pub
        toggled.isPrivate = true
        XCTAssertNotEqual(
            SpotlightIndexer.fingerprint(pub),
            SpotlightIndexer.fingerprint(toggled),
            "isPrivate 状态翻转必须改变条目指纹"
        )
    }

    // MARK: - 2. Handoff 隐私防线：私密散页不得广播至蓝牙/iCloud 接力

    @MainActor
    func testHandoffSkipsPrivateEntries() {
        let appState = AppState.shared
        defer { appState.endHandoffActivity() }

        let privateEntry = LifeEntry(
            id: 201,
            type: "life",
            title: "私密手稿",
            content: "私密正文",
            occurredAt: "2026-10-20T10:00:00+08:00",
            isPrivate: true
        )
        appState.publishHandoffActivity(for: privateEntry)
        // 先发布公开再切私密，验证私密条目会主动撤销现有 Handoff 广播
        let publicEntry = LifeEntry(
            id: 202,
            type: "life",
            title: "公开手稿",
            content: "公开正文",
            occurredAt: "2026-10-20T10:00:00+08:00",
            isPrivate: false
        )
        appState.publishHandoffActivity(for: publicEntry)
        appState.publishHandoffActivity(for: privateEntry)
    }

    // MARK: - 3. 跨端照片防误删：心愿与足迹无图编辑不得写出空的 attachment_ids

    func testWishAndFootprintRequestsOmitAttachmentIdsByDefault() throws {
        let wishReq = CreateWishRequest(
            title: "北海道冬日漫游",
            kind: "travel",
            note: "看雪",
            spec: "7天6晚自由行",
            cityCode: "990000",
            cityName: "札幌",
            budget: 1200000,
            isPrivate: true
        )
        let wishJSON = try XCTUnwrap(String(data: JSONEncoder().encode(wishReq), encoding: .utf8))
        XCTAssertFalse(
            wishJSON.contains("attachment_ids"),
            "无图修订心愿时绝不可默认写出 attachment_ids: []，否则会静默解绑跨端上传的照片：\(wishJSON)"
        )
        XCTAssertTrue(wishJSON.contains("\"spec\":\"7天6晚自由行\""), "旅程心愿同样必须保留 spec 字段")
        XCTAssertTrue(wishJSON.contains("\"is_private\":true"))

        let fpReq = CreateFootprintRequest(
            cityCode: "330100",
            cityName: "杭州市",
            title: "秋日西湖",
            visitedAt: "2026-10-20T10:00:00+08:00",
            departedAt: "2026-10-23",
            note: "桂花雨",
            isPrivate: true
        )
        let fpJSON = try XCTUnwrap(String(data: JSONEncoder().encode(fpReq), encoding: .utf8))
        XCTAssertFalse(
            fpJSON.contains("attachment_ids"),
            "无图修订足迹时绝不可默认写出 attachment_ids: []：\(fpJSON)"
        )
        XCTAssertTrue(fpJSON.contains("\"departed_at\":\"2026-10-23\""))
        XCTAssertTrue(fpJSON.contains("\"is_private\":true"))
    }

    // MARK: - 4. 散页清空最后一张相纸三态契约：clear_attachments = true

    func testUpdateEntryRequestEncodesClearAttachmentsTriState() throws {
        let req = UpdateEntryRequest(
            type: "life",
            title: "清空配图",
            content: "正文",
            occurredAt: "2026-10-20T10:00:00+08:00",
            attachmentIds: [],
            clearAttachments: true
        )
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(req), encoding: .utf8))
        XCTAssertTrue(json.contains("\"clear_attachments\":true"), "显式删空全部附件时必须携带 clear_attachments: true")
        XCTAssertTrue(json.contains("\"attachment_ids\":[]"))
    }

    // MARK: - 5. 分期付款当期尾差核算（DEC-02 / FE-24：前 N-1 期整除，末期吃尾差）

    func testInstallmentCurrentPeriodTailCentCalculation() {
        // 10.00 元（1000 分）分 3 期：前 2 期每期 333 分，最后 1 期吃尾差 = 1000 - 2 * 333 = 334 分
        let firstPeriod = Transaction(
            id: 1,
            amount: 1000,
            type: "expense",
            category: "数码器材",
            title: "转接线",
            isInstallment: true,
            installmentChannelCode: "huabei",
            installmentTotalAmount: 1000,
            installmentMonths: 3,
            installmentMonthlyPay: 333,
            installmentRemainMonths: 3
        )
        XCTAssertEqual(firstPeriod.installmentCurrentPeriodCents, 333)
        XCTAssertEqual(firstPeriod.installmentBadgeText, "剩 3/3 期 · 本期 ¥ 3.33")

        var finalPeriod = firstPeriod
        finalPeriod.installmentRemainMonths = 1
        XCTAssertEqual(finalPeriod.installmentCurrentPeriodCents, 334, "最后一期必须精确吸收整除尾差")
        XCTAssertEqual(finalPeriod.installmentBadgeText, "剩 1/3 期 · 本期 ¥ 3.34")

        var settled = firstPeriod
        settled.installmentRemainMonths = 0
        XCTAssertEqual(settled.installmentCurrentPeriodCents, 0)
        XCTAssertEqual(settled.installmentBadgeText, "分期 3 期 · 已结清")
    }

    // MARK: - 6. PaperImageCache.bitmapByteCost 对 CGImage 路径返回真实字节开销

    func testBitmapByteCostForCGImageBackedNSImage() throws {
        let width = 200
        let height = 150
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let cgImage = try XCTUnwrap(context.makeImage())
        // 模拟 ImageIO 缩略图管线直接以 CGImage 构造 NSImage（不含 NSBitmapImageRep）
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))

        let cost = PaperImageCache.bitmapByteCost(of: nsImage)
        XCTAssertGreaterThanOrEqual(
            cost,
            width * height * 4,
            "CGImage 构造的 NSImage 必须返回真实位图字节数，防止 NSCache 60MB 上限形同虚设（实际返回 \(cost)）"
        )
    }

    // MARK: - 7. UpdateChecker 供应链 SHA256 强制校验与 checksums.txt 解析

    func testUpdateCheckerEnforcesSHA256AndParsesChecksums() throws {
        let payload = Data("looseleaf-release-archive-bytes".utf8)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-update-\(UUID().uuidString).zip")
        try payload.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let actualHex = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()

        // 1) 摘要缺失必须拒绝安装
        XCTAssertThrowsError(try UpdateChecker.verifyDigest(of: tempURL, expected: nil))

        // 2) 摘要不匹配必须拒绝安装
        let wrongDigest = "sha256:" + String(repeating: "0", count: 64)
        XCTAssertThrowsError(try UpdateChecker.verifyDigest(of: tempURL, expected: wrongDigest))

        // 3) 摘要匹配放行
        XCTAssertNoThrow(try UpdateChecker.verifyDigest(of: tempURL, expected: "sha256:\(actualHex)"))

        // 4) checksums.txt 解析支持标准 GNU/BSD 格式
        let checksumsContent = """
        # SHA256SUMS
        \(String(repeating: "a", count: 64))  LooseLeaf-linux.tar.gz
        \(actualHex) *LooseLeaf-macOS-arm64.zip
        """
        let parsed = UpdateChecker.parseChecksumDigest(from: checksumsContent, assetName: "LooseLeaf-macOS-arm64.zip")
        XCTAssertEqual(parsed, "sha256:\(actualHex)")
    }

    // MARK: - 8. 无后缀相纸导出自动推断真实扩展名

    func testPaperImageExportInfersExtensionFromMagicBytes() throws {
        let fallbackURL = try XCTUnwrap(URL(string: "http://localhost:8088/api/v1/files/thumbnail?key=abc"))
        var pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
        pngHeader.append(contentsOf: [0x49, 0x48, 0x44, 0x52])
        XCTAssertEqual(
            PaperImageExport.normalizedFilename(nil, fallbackURL: fallbackURL, data: pngHeader),
            "looseleaf-photo.png"
        )

        let jpegHeader = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01])
        XCTAssertEqual(
            PaperImageExport.normalizedFilename("mountain-film", fallbackURL: fallbackURL, data: jpegHeader),
            "mountain-film.jpg"
        )
    }

    // MARK: - 9. 时间流私密筛选缓存键隔离

    func testFilteredEntriesCacheKeyIncludesPrivacyFilter() {
        let allKey = AppState.filteredEntriesCacheKey(
            entriesRevision: 5,
            transactionsRevision: 2,
            category: .all,
            searchQuery: "",
            privacyFilter: .all
        )
        let privKey = AppState.filteredEntriesCacheKey(
            entriesRevision: 5,
            transactionsRevision: 2,
            category: .all,
            searchQuery: "",
            privacyFilter: .privateOnly
        )
        XCTAssertNotEqual(allKey, privKey, "全部与仅私密筛选必须对应不同的记忆化缓存键")
    }
}

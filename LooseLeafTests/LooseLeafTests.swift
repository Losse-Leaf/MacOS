import XCTest
import AppKit
@testable import LooseLeaf

final class LooseLeafTests: XCTestCase {

    // MARK: - 1. Cents Int64 Precision Tests (Zero Float Drift)

    func testParseYuanToCentsPrecision() {
        XCTAssertEqual(FormatUtils.parseYuanToCents("42.5"), 4250)
        XCTAssertEqual(FormatUtils.parseYuanToCents("42.50"), 4250)
        XCTAssertEqual(FormatUtils.parseYuanToCents("0.01"), 1)
        XCTAssertEqual(FormatUtils.parseYuanToCents("100"), 10000)
        XCTAssertEqual(FormatUtils.parseYuanToCents("¥1,299.99"), 129999)
        XCTAssertEqual(FormatUtils.parseYuanToCents("19.99"), 1999)
        XCTAssertNil(FormatUtils.parseYuanToCents("abc"))
        XCTAssertNil(FormatUtils.parseYuanToCents(""))
    }

    func testFormattedYuanDisplay() {
        XCTAssertEqual(FormatUtils.formattedYuan(cents: 4250, includeSymbol: true), "¥ 42.50")
        XCTAssertEqual(FormatUtils.formattedYuan(cents: 10000, includeSymbol: false), "100.00")
        XCTAssertEqual(FormatUtils.formattedYuan(cents: 1, includeSymbol: true), "¥ 0.01")
    }

    // MARK: - 2. Quick Ledger Natural Language Parser Tests

    func testQuickLedgerNaturalLanguageParser() {
        let parsed1 = FormatUtils.parseQuickLedgerInput("42.5 午餐手冲咖啡")
        XCTAssertNotNil(parsed1)
        XCTAssertEqual(parsed1?.amountCents, 4250)
        XCTAssertEqual(parsed1?.category, "餐饮")
        XCTAssertEqual(parsed1?.title, "午餐手冲咖啡")
        XCTAssertEqual(parsed1?.type, "expense")

        let parsed2 = FormatUtils.parseQuickLedgerInput("地铁通勤 6")
        XCTAssertNotNil(parsed2)
        XCTAssertEqual(parsed2?.amountCents, 600)
        XCTAssertEqual(parsed2?.category, "交通")
        XCTAssertEqual(parsed2?.title, "地铁通勤")

        let parsed3 = FormatUtils.parseQuickLedgerInput("128.80 买书 #阅读")
        XCTAssertNotNil(parsed3)
        XCTAssertEqual(parsed3?.amountCents, 12880)
        XCTAssertEqual(parsed3?.category, "学习")
    }

    // MARK: - 3. Beijing Time (UTC+8, RC-134) FlexTime Tests

    func testBeijingTimeFlexParsingAndFormatting() {
        let parsedDate = FormatUtils.parseFlexDate("2026-10-13 09:30:00")
        XCTAssertNotNil(parsedDate)
        if let date = parsedDate {
            let formatted = FormatUtils.formatBeijingDate(date)
            XCTAssertEqual(formatted.dateKey, "2026-10-13")
            XCTAssertEqual(formatted.dotDateTime, "2026.10.13 09:30")
        }

        let isoDate = FormatUtils.parseFlexDate("2026-10-13T21:15:00+08:00")
        XCTAssertNotNil(isoDate)
        if let date = isoDate {
            XCTAssertEqual(FormatUtils.formatBeijingDate(date).dateKey, "2026-10-13")
        }

        let gapDays = FormatUtils.daysBetween("2026-10-01 08:00:00", "2026-10-20 19:00:00")
        XCTAssertEqual(gapDays, 19)
    }

    // MARK: - 4. Hashtag Extraction Tests

    func testHashtagExtractor() {
        let text = "午后在 #西湖 散步，用胶片记录秋色 #摄影 #杭州 #西湖"
        let tags = FormatUtils.extractHashtags(from: text)
        XCTAssertEqual(tags, ["西湖", "摄影", "杭州"])
    }

    // MARK: - 5. Domain Model Codable Contract Tests (RC-132 create_transaction)

    func testTransactionAndGearAssetCodableContract() throws {
        let req = AddGearAssetRequest(
            name: "Leica M6 TTL",
            spec: "0.72x 取景器",
            category: "数码器材",
            priceCents: 1850000,
            purchaseDate: "2026-10-13",
            note: "成色极佳",
            createTransaction: true,
            paymentMethod: "银行卡"
        )
        let encoded = try JSONEncoder().encode(req)
        let jsonObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertEqual(jsonObject?["price_cents"] as? Int64, 1850000)
        XCTAssertEqual(jsonObject?["create_transaction"] as? Bool, true)
        XCTAssertEqual(jsonObject?["payment_method"] as? String, "银行卡")
    }

    func testLifeEntryDecodingResilience() throws {
        let rawJSON = """
        {
            "code": 0,
            "message": "ok",
            "data": {
                "id": 101,
                "type": "life",
                "title": "秋日暗房",
                "content": "第一卷 Kodak Portra 400 #胶片 #暗房",
                "occurred_at": "2026-10-13T14:00:00+08:00",
                "location": "杭州",
                "attachments": [
                    {
                        "id": 1,
                        "object_key": "uploads/2026/sample.jpg",
                        "original_filename": "sample.jpg",
                        "mime_type": "image/jpeg",
                        "size": 204800,
                        "width": 3840,
                        "height": 2560,
                        "url": "/media/uploads/2026/sample.jpg"
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(APIEnvelope<LifeEntry>.self, from: rawJSON)
        XCTAssertEqual(envelope.code, 0)
        XCTAssertEqual(envelope.data?.id, 101)
        XCTAssertEqual(envelope.data?.hashtags, ["胶片", "暗房"])
        XCTAssertEqual(envelope.data?.attachments.first?.width, 3840)
    }

    // MARK: - 6. ImageProcessor EXIF & Compression Test

    func testImageProcessorCompressionAndEXIFLine() throws {
        let exif = ImageProcessor.EXIFSummary(
            cameraMake: "FUJIFILM",
            cameraModel: "X100V",
            lensModel: "23mm F2",
            focalLength: 23,
            fNumber: 2.0,
            exposureTime: 0.002,
            iso: 400
        )
        XCTAssertEqual(exif.formattedCameraLine, "FUJIFILM X100V · 23mm F2.0 · 1/500s · ISO 400")

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 400,
            pixelsHigh: 300,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let pngData = rep.representation(using: .png, properties: [:])!
        let processed = try ImageProcessor.processImageData(pngData, originalFilename: "test_frame.png")
        XCTAssertEqual(processed.width, 400)
        XCTAssertEqual(processed.height, 300)
        XCTAssertEqual(processed.mimeType, "image/jpeg")
        XCTAssertFalse(processed.compressedData.isEmpty)
    }

    // MARK: - 7. City Code Auto Resolver Tests (CityCodeResolver)

    func testCityCodeResolver() {
        XCTAssertEqual(FormatUtils.resolveCityCode(from: "杭州 · 西湖"), "330100")
        XCTAssertEqual(FormatUtils.resolveCityCode(from: "云南省大理市"), "532900")
        XCTAssertEqual(FormatUtils.resolveCityCode(from: "苏州市"), "320500")
        XCTAssertEqual(FormatUtils.resolveCityCode(from: "532900"), "532900")
        XCTAssertNil(FormatUtils.resolveCityCode(from: "未知神秘小岛"))
    }

    // MARK: - 8. Resolve Wish & Sell Gear Request Codable Tests

    func testResolveWishAndSellGearCodableContracts() throws {
        let resolveReq = ResolveWishRequest(
            fulfilledAt: "2026-10-13T16:00:00+08:00",
            actualCost: 199900,
            resolutionType: "exact",
            actualTitle: "Leica M6",
            createTransaction: true,
            createGearAsset: true,
            createLifeEntry: true,
            entryContent: "圆梦 Leica M6"
        )
        let resolveData = try JSONEncoder().encode(resolveReq)
        let resolveJson = try JSONSerialization.jsonObject(with: resolveData) as? [String: Any]
        XCTAssertEqual(resolveJson?["actual_cost"] as? Int64, 199900)
        XCTAssertEqual(resolveJson?["resolution_type"] as? String, "exact")
        XCTAssertEqual(resolveJson?["create_transaction"] as? Bool, true)
        XCTAssertEqual(resolveJson?["create_gear_asset"] as? Bool, true)

        let sellReq = SellGearRequest(
            soldPriceCents: 120000,
            soldDate: "2026-10-13",
            note: "闲鱼同城自提"
        )
        let sellData = try JSONEncoder().encode(sellReq)
        let sellJson = try JSONSerialization.jsonObject(with: sellData) as? [String: Any]
        XCTAssertEqual(sellJson?["sold_price_cents"] as? Int64, 120000)
        XCTAssertEqual(sellJson?["sold_date"] as? String, "2026-10-13")
        XCTAssertEqual(sellJson?["note"] as? String, "闲鱼同城自提")
    }

    // MARK: - 9. System Bootstrap Codable Contract Tests

    func testBootstrapRequestCodableContract() throws {
        let bootstrapReq = BootstrapRequest(
            curatorName: "Starry",
            location: "杭州",
            masterPasscode: "pass1234",
            confirmPasscode: "pass1234",
            hubUrl: "http://127.0.0.1:8088"
        )
        let data = try JSONEncoder().encode(bootstrapReq)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["curator_name"] as? String, "Starry")
        XCTAssertEqual(json?["location"] as? String, "杭州")
        XCTAssertEqual(json?["master_passcode"] as? String, "pass1234")
        XCTAssertEqual(json?["hub_url"] as? String, "http://127.0.0.1:8088")
    }

    // MARK: - 10. Sync Merge, Cursor & Local Temp ID Logic Tests

    func testMergedEntriesDeltaReconciliation() {
        let base = LifeEntry(id: 1, title: "A", content: "", occurredAt: "2026-10-01 10:00:00")
        let stale = LifeEntry(id: 2, title: "B", content: "", occurredAt: "2026-10-02 10:00:00")
        let fresh = LifeEntry(id: 3, title: "C", content: "", occurredAt: "2026-10-03 10:00:00")
        let deleted = LifeEntry(
            id: 2,
            title: "B",
            content: "",
            occurredAt: "2026-10-02 10:00:00",
            deletedAt: "2026-10-04 10:00:00"
        )

        // 增量：新条目并入 + 软删除条目移除，结果按时间倒序
        let merged = SyncManager.mergedEntries(current: [base, stale], incoming: [fresh, deleted], isDelta: true)
        XCTAssertEqual(merged.map(\.id), [3, 1])

        // 全量：本地未同步项保留 + 远端软删除项过滤
        var pending = LifeEntry(id: 9, title: "P", content: "", occurredAt: "2026-10-05 10:00:00")
        pending.syncStatus = "pending_create"
        let full = SyncManager.mergedEntries(current: [pending], incoming: [base, fresh, deleted], isDelta: false)
        XCTAssertEqual(full.map(\.id).sorted(), [1, 3, 9])
    }

    func testMergedTransactionsDeltaReconciliation() {
        let base = Transaction(id: 1, amount: 1000, category: "餐饮", title: "A", occurredAt: "2026-10-01 10:00:00")
        let deleted = Transaction(
            id: 1,
            amount: 1000,
            category: "餐饮",
            title: "A",
            occurredAt: "2026-10-01 10:00:00",
            deletedAt: "2026-10-04 10:00:00"
        )
        let merged = SyncManager.mergedTransactions(current: [base], incoming: [deleted], isDelta: true)
        XCTAssertTrue(merged.isEmpty)
    }

    func testLatestServerCursor() {
        XCTAssertNil(SyncManager.latestServerCursor([]))
        XCTAssertNil(SyncManager.latestServerCursor([nil, ""]))
        XCTAssertEqual(
            SyncManager.latestServerCursor(["2026-10-01T10:00:00+08:00", nil, "2026-10-03T10:00:00+08:00", ""]),
            "2026-10-03T10:00:00+08:00"
        )
    }

    func testLocalTempIdGeneration() {
        var seen = Set<Int>()
        for _ in 0..<1000 {
            let id = SyncManager.makeLocalTempId()
            XCTAssertLessThan(id, 0, "本地临时 ID 必须为负值以与服务器 ID 区分")
            XCTAssertTrue(seen.insert(id).inserted, "同批生成的临时 ID 不应碰撞")
        }
    }
}

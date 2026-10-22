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

    // MARK: - 13. Pairing Link Parser Tests

    func testParsePairLink() {
        // 完整深链：hub + ticket 双取
        let full = AppState.parsePairLink("looseleaf://pair?hub=http://127.0.0.1:8088&ticket=pair_tk_abc123")
        XCTAssertNotNil(full)
        XCTAssertEqual(full?.hub, "http://127.0.0.1:8088")
        XCTAssertEqual(full?.ticket, "pair_tk_abc123")

        // 首尾空白容忍
        let padded = AppState.parsePairLink("  looseleaf://pair?hub=http://10.0.0.2:8088&ticket=tk9  \n")
        XCTAssertEqual(padded?.ticket, "tk9")

        // hub 缺失：仍可解析（调用方回退到当前 hubURLString）
        let noHub = AppState.parsePairLink("looseleaf://pair?ticket=onlyticket")
        XCTAssertEqual(noHub?.ticket, "onlyticket")
        XCTAssertEqual(noHub?.hub, "")

        // 非 looseleaf scheme / 非 pair host / 缺 ticket：一律拒绝
        XCTAssertNil(AppState.parsePairLink("https://pair?hub=http://x&ticket=t"))
        XCTAssertNil(AppState.parsePairLink("looseleaf://entry/42"))
        XCTAssertNil(AppState.parsePairLink("looseleaf://pair?hub=http://x"))
        XCTAssertNil(AppState.parsePairLink("随便一段文字"))
        XCTAssertNil(AppState.parsePairLink(""))
    }

    // MARK: - 14. Credential Vault Tests

    func testCredentialStoreRoundtripAndPermissions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("looseleaf-test-\(UUID().uuidString)", isDirectory: true)
        CredentialStore.overrideDirectory = tempDir
        defer {
            CredentialStore.clearAllCredentials()
            CredentialStore.overrideDirectory = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 空态
        XCTAssertNil(CredentialStore.getToken())

        // 写入与回读
        XCTAssertTrue(CredentialStore.saveToken("tok_test_123"))
        XCTAssertTrue(CredentialStore.saveDeviceIdentity(deviceId: "dev_1", deviceName: "Test Mac"))
        XCTAssertEqual(CredentialStore.getToken(), "tok_test_123")
        XCTAssertEqual(CredentialStore.getDeviceId(), "dev_1")
        XCTAssertEqual(CredentialStore.getDeviceName(), "Test Mac")

        // 落盘文件存在且权限为 0600（仅当前用户可读写）
        let fileURL = tempDir.appendingPathComponent("credentials.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = attrs[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600, "凭据档案必须仅当前用户可读写")

        // 清空后回读为空
        CredentialStore.clearAllCredentials()
        XCTAssertNil(CredentialStore.getToken())
        XCTAssertNil(CredentialStore.getDeviceId())
    }

    // MARK: - 15. Image Orientation Normalization Test (Zero Double-Rotation)

    func testImageProcessorOrientationNormalizedToOne() throws {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 200,
            pixelsHigh: 100,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let pngData = rep.representation(using: .png, properties: [:])!

        // Attach orientation 6 (Rotate 90 CW) to simulate an iPhone / Camera vertical photo
        let mutableData = CFDataCreateMutable(nil, 0)!
        guard let dest = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil),
              let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let cgImg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("Failed to create test image source")
            return
        }
        let inputProps: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFOrientation: 6,
                kCGImagePropertyTIFFMake: "Leica"
            ]
        ]
        CGImageDestinationAddImage(dest, cgImg, inputProps as CFDictionary)
        CGImageDestinationFinalize(dest)

        let initialRotatedData = mutableData as Data
        let processed = try ImageProcessor.processImageData(initialRotatedData, originalFilename: "vertical.jpg")

        // Inspect output JPEG metadata
        guard let outputSource = CGImageSourceCreateWithData(processed.compressedData as CFData, nil),
              let outputProps = CGImageSourceCopyPropertiesAtIndex(outputSource, 0, nil) as? [CFString: Any] else {
            XCTFail("Failed to read processed photo properties")
            return
        }

        let outputTiff = outputProps[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let tiffOrientation = outputTiff?[kCGImagePropertyTIFFOrientation] as? Int
        let rootOrientation = outputProps[kCGImagePropertyOrientation] as? Int

        XCTAssertEqual(tiffOrientation, 1, "TIFF Orientation 必须重置规范化为 1，杜绝看图器二次翻转")
        XCTAssertEqual(rootOrientation, 1, "顶层 Orientation 必须规范化为 1")
    }

    // MARK: - 16. Update Checker Semantic Version Comparison Tests

    func testRealBackendEntriesDecoding() async throws {
        guard let url = URL(string: "http://localhost:8088/api/v1/entries?page=1&page_size=100") else { return }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // 这是可选的本地联调用例：后端不可达时必须显式跳过，不能"打印一句就绿"
            throw XCTSkip("本地后端未启动，跳过真实数据联调")
        }
        do {
            let env = try JSONDecoder().decode(APIEnvelope<EntriesListResponse>.self, from: data)

            var snapshot = LocalArchiveSnapshot()
            snapshot.entries = env.data?.entries ?? []
            let encoded = try JSONEncoder().encode(snapshot)
            let decoded = try JSONDecoder().decode(LocalArchiveSnapshot.self, from: encoded)
            XCTAssertEqual(decoded.entries.count, env.data?.entries.count ?? 0)
        } catch {
            XCTFail("Decoding failed: \(error)")
        }
    }

    func testUpdateCheckerSemverComparison() {
        XCTAssertTrue(UpdateChecker.isVersion("1.2.1", greaterThan: "1.2.0"))
        XCTAssertTrue(UpdateChecker.isVersion("2.0.0", greaterThan: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isVersion("1.10.0", greaterThan: "1.9.0"))
        XCTAssertTrue(UpdateChecker.isVersion("1.2.1", greaterThan: "1.2"))
        XCTAssertFalse(UpdateChecker.isVersion("1.2.0", greaterThan: "1.2.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.2.0", greaterThan: "1.2.1"))
        XCTAssertFalse(UpdateChecker.isVersion("1.1.9", greaterThan: "1.2.0"))
    }

    // MARK: - 17. Multi-Format Export & Almanac / City Drawer Decoding Tests

    func testMakeTransactionsCSVAndFullJSONExport() throws {
        let tx = Transaction(
            id: 1,
            amount: 4250,
            type: "expense",
            category: "餐饮",
            title: "手冲咖啡,燕麦奶",
            note: "风味极佳",
            paymentMethod: "微信支付",
            cityCode: "330100",
            occurredAt: "2026-10-14T09:30:00+08:00"
        )
        let csv = ArchiveExporter.makeTransactionsCSV(transactions: [tx])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}日期时间,收支类型,分类,标题,金额(元),金额(分),支付方式,城市代码,分期,备注"))
        XCTAssertTrue(csv.contains("\"手冲咖啡,燕麦奶\""))
        XCTAssertTrue(csv.contains("42.50,4250"))

        var snap = LocalArchiveSnapshot()
        snap.transactions = [tx]
        // makeFullArchiveJSON 现为 throwing：编码失败必须可感知，不能静默返回 nil
        let jsonData = try ArchiveExporter.makeFullArchiveJSON(snapshot: snap, projects: [], wishes: [], footprints: [])
        XCTAssertFalse(jsonData.isEmpty)
        XCTAssertTrue(String(data: jsonData, encoding: .utf8)?.contains("transactions") == true)

        let lonLat = CityDictionary.lonLat(forCode: "330100", cityName: "杭州市")
        XCTAssertTrue(lonLat.lon > 85.0 && lonLat.lon < 125.0)
        XCTAssertTrue(lonLat.lat > 18.0 && lonLat.lat < 50.0)
    }

    // MARK: - 18. Spotlight Navigation & Update Checker Fallback Tests

    @MainActor
    func testSpotlightNavigationStateTransition() {
        let state = AppState.shared
        // 快照并还原全局单例，避免用例之间互相污染
        let savedEntries = state.entries
        let savedSection = state.activeSection
        let savedCategory = state.selectedCategory
        let savedFocused = state.keyboardFocusedEntryId
        let savedHighlighted = state.highlightedEntry
        let savedDetailWindow = state.detailWindowEntry
        defer {
            state.entries = savedEntries
            state.activeSection = savedSection
            state.selectedCategory = savedCategory
            state.keyboardFocusedEntryId = savedFocused
            state.highlightedEntry = savedHighlighted
            state.detailWindowEntry = savedDetailWindow
        }

        let entry = LifeEntry(id: 777, title: "聚焦测试", content: "通过聚焦搜索直达", occurredAt: "2026-10-15 12:00:00")
        state.entries = [entry]
        state.activeSection = .ledger
        state.selectedCategory = .transaction

        state.navigateToEntry(id: 777)
        XCTAssertEqual(state.activeSection, .stream)
        XCTAssertEqual(state.selectedCategory, .all)
        XCTAssertEqual(state.keyboardFocusedEntryId, 777)
        // 深链条目进入**独立详情窗口**槽位，不再占用主窗口的详情弹层
        XCTAssertEqual(state.detailWindowEntry?.id, 777)
        XCTAssertNil(state.highlightedEntry, "深链不应同时弹出主窗口详情弹层")
    }

    @MainActor
    func testInstallCommandConstant() {
        // 只断言常量，不去写系统剪贴板（避免测试污染用户环境）
        let command = UpdateChecker.installCommand
        XCTAssertTrue(command.contains("raw.githubusercontent.com/Losse-Leaf/MacOS/main/install.sh"))
        XCTAssertTrue(command.contains("/bin/bash -c"))
    }

    @MainActor
    func testQuickCaptureDraftStateSharingAndReset() {
        let draft = AppState.shared.quickDraft
        draft.reset()
        draft.titleText = "测试草稿"
        draft.contentText = "草稿正文"
        draft.activeTab = .thought

        XCTAssertEqual(AppState.shared.quickDraft.titleText, "测试草稿")
        XCTAssertEqual(AppState.shared.quickDraft.contentText, "草稿正文")

        draft.reset()
        XCTAssertTrue(draft.titleText.isEmpty)
        XCTAssertTrue(draft.contentText.isEmpty)
    }

    // MARK: - 19. Two-Tier Disk Image Cache & International Coordinates Tests

    func testPaperImageCacheTwoTierDiskCache() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("looseleaf-media-\(UUID().uuidString)", isDirectory: true)
        PaperImageCache.overrideDirectory = tempDir
        defer {
            PaperImageCache.overrideDirectory = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testURL = URL(string: "https://example.com/media/sample_photo_test.jpg")!
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 100,
            pixelsHigh: 100,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let img = NSImage(size: NSSize(width: 100, height: 100))
        img.addRepresentation(rep)

        PaperImageCache.setImage(img, for: testURL)
        let hit = PaperImageCache.image(for: testURL)
        XCTAssertNotNil(hit)
    }

    func testCityDictionaryInternationalCoordinates() {
        let tokyo = CityDictionary.coordinate(forCode: "", cityName: "东京 · 涩谷")
        XCTAssertEqual(tokyo.x, 585.0)
        XCTAssertEqual(tokyo.y, 310.0)

        let london = CityDictionary.coordinate(forCode: "", cityName: "伦敦")
        XCTAssertEqual(london.x, 120.0)
        XCTAssertEqual(london.y, 180.0)

        let unknown = CityDictionary.coordinate(forCode: "", cityName: "苏黎世小镇")
        XCTAssertFalse(unknown.x == 462.3 && unknown.y == 300.0, "未匹配地名应有离散散列坐标，避免死锁在中原原点")
    }


    func testServerBackupItemDecodingAndFormatting() throws {
        let json = """
        {
            "filename": "looseleaf-backup-20261018-120000.zip",
            "size": 5242880,
            "created_at": "2026-10-18T12:00:00+08:00",
            "storage_type": "r2"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(ServerBackupItem.self, from: json)
        XCTAssertEqual(item.id, "looseleaf-backup-20261018-120000.zip")
        XCTAssertEqual(item.storageTypeBadge, "Cloudflare R2")
        XCTAssertEqual(item.formattedSize, "5.00 MB")
        XCTAssertFalse(item.formattedDate.isEmpty)
    }

    // MARK: - 20. 2026-10-18 审计回归用例

    func testMergedEntriesFullBranchIsSorted() {
        let older = LifeEntry(id: 1, title: "older", content: "", occurredAt: "2026-10-01 10:00:00")
        let newer = LifeEntry(id: 2, title: "newer", content: "", occurredAt: "2026-10-05 10:00:00")
        let merged = SyncManager.mergedEntries(current: [], incoming: [older, newer], isDelta: false)
        XCTAssertEqual(merged.map(\.id), [2, 1], "全量分支也必须按北京时间倒序")
    }

    func testMergedEntriesToleratesDuplicateIDs() {
        let first = LifeEntry(id: 7, title: "a", content: "", occurredAt: "2026-10-01 10:00:00")
        let second = LifeEntry(id: 7, title: "b", content: "", occurredAt: "2026-10-02 10:00:00")
        // 旧实现用 Dictionary(uniqueKeysWithValues:) 会直接 trap
        let merged = SyncManager.mergedEntries(current: [first, second], incoming: [], isDelta: true)
        XCTAssertEqual(merged.count, 1)
    }

    func testCSVNeutralizesFormulaInjection() {
        let tx = Transaction(
            id: 1,
            amount: 100,
            category: "餐饮",
            title: "=SUM(A1:A2)",
            note: "@cmd",
            occurredAt: "2026-10-14T09:30:00+08:00"
        )
        let csv = ArchiveExporter.makeTransactionsCSV(transactions: [tx])
        XCTAssertTrue(csv.contains("'=SUM(A1:A2)"), "以 = 开头的字段必须被中和")
        XCTAssertTrue(csv.contains("'@cmd"), "以 @ 开头的字段必须被中和")
    }

    func testSemverPrereleaseComparison() {
        XCTAssertTrue(UpdateChecker.isVersion("1.5.7-beta.1", greaterThan: "1.5.6"))
        XCTAssertFalse(UpdateChecker.isVersion("1.5.7-beta.1", greaterThan: "1.5.7"))
    }

    func testInvalidOccurredDateIsUnknown() {
        let parsed = FormatUtils.parseOccurredDate("not-a-date")
        XCTAssertFalse(parsed.isValid)
        XCTAssertEqual(parsed.dotDateTime, "时间未知")
        XCTAssertEqual(FormatUtils.daysBetween("not-a-date", "2026-10-01 10:00:00"), 0)
    }

    // MARK: - 19. 第二版优化清单新增回归测试

    /// 快照 schema 版本：老快照（无 schemaVersion 字段）必须能解码并被迁移，
    /// 否则老用户会命中「解码失败 → 隔离备份」路径，表现为档案凭空消失。
    func testSnapshotSchemaVersionMigration() throws {
        let legacyJSON = """
        {
          "entries": [
            { "id": 7, "type": "life", "title": "迁移前的旧条目", "content": "正文", "occurred_at": "2026-10-01T10:00:00+08:00" }
          ],
          "transactions": [],
          "transactionSummary": { "totalExpense": 0, "totalIncome": 0, "balance": 0, "categoryBreakdown": {} },
          "profile": { "name": "测试", "title": "", "bio": "", "location": "", "currentCity": "", "avatarUrl": "", "motto": "", "manifesto": "", "edcGear": [] },
          "siteConfig": { "siteName": "散页", "curatorName": "测试", "defaultLocation": "", "initialized": true },
          "stats": { "total_entries": 0, "total_photos": 0, "total_projects": 0, "month_expense": 0, "current_year": 2026, "current_month": 10 },
          "outbox": [],
          "updatedAt": "2026-10-20T10:00:00+08:00"
        }
        """
        let decoded = try JSONDecoder().decode(LocalArchiveSnapshot.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.schemaVersion, 1, "缺少 schemaVersion 的老快照应按 v1 解释")
        let migrated = decoded.migrated()
        XCTAssertNotNil(migrated, "v1 快照必须能迁移到当前版本")
        XCTAssertEqual(migrated?.schemaVersion, LocalArchiveSnapshot.currentSchemaVersion)
        XCTAssertEqual(migrated?.entries.count, 1, "迁移不得丢弃任何历史数据")
        XCTAssertEqual(migrated?.entries.first?.title, "迁移前的旧条目", "迁移不得改动条目内容")
    }

    /// 未来版本护栏：快照来自**更新版本**的应用（用户降级了）时必须拒绝迁移
    ///
    /// 关键：若照旧把版本号改小，新版引入的字段会在解码时被
    /// `try? decode ?? 默认值` **悄悄吃掉** —— 也就是静默丢数据。
    /// 所以必须返回 nil，由调用方隔离备份并提示，绝不覆盖。
    func testSnapshotFromNewerVersionIsRejected() throws {
        var snap = LocalArchiveSnapshot()
        snap.schemaVersion = LocalArchiveSnapshot.currentSchemaVersion + 1
        XCTAssertNil(
            snap.migrated(),
            "未来版本的快照必须拒绝迁移（否则新版字段会被静默丢弃）"
        )
        // 旧版本则必须能迁移
        var old = LocalArchiveSnapshot()
        old.schemaVersion = 1
        XCTAssertNotNil(old.migrated(), "旧版本快照必须能迁移")
    }

    /// v2 → v3 迁移：引入 mediaURLsRefreshedAt，且必须是 nil（=「还不知道有没有过期」）
    func testSnapshotV2ToV3Migration() throws {
        var snap = LocalArchiveSnapshot()
        snap.schemaVersion = 2
        snap.mediaURLsRefreshedAt = "2026-10-20T10:00:00+08:00"
        let migrated = snap.migrated()
        XCTAssertNotNil(migrated)
        XCTAssertEqual(migrated?.schemaVersion, LocalArchiveSnapshot.currentSchemaVersion)
        XCTAssertNil(
            migrated?.mediaURLsRefreshedAt,
            "v2 → v3 必须把 mediaURLsRefreshedAt 复位为 nil —— 填当前时间等于假装刚换过签，"
            + "那份可能早已失效的地址就会被继续信任"
        )
    }

    /// 新快照必须带 schemaVersion，且能被解码回来
    func testSnapshotRoundTripKeepsSchemaVersion() throws {
        var snap = LocalArchiveSnapshot()
        snap.schemaVersion = LocalArchiveSnapshot.currentSchemaVersion
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(LocalArchiveSnapshot.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, LocalArchiveSnapshot.currentSchemaVersion)
    }

    /// 日期解析的形状判别：所有历史格式都必须解析成功且结果一致
    func testFlexDateShapeDispatchKeepsAllFormats() {
        let samples: [(String, String)] = [
            ("2026-10-13T21:15:00+08:00", "2026-10-13"),
            ("2026-10-13 09:30:00", "2026-10-13"),
            ("2026-10-13 09:30", "2026-10-13"),
            ("2026-10-13", "2026-10-13"),
            ("2026.10.13 09:30:00", "2026-10-13"),
            ("2026.10.13", "2026-10-13"),
            ("2026:10:13 09:30:00", "2026-10-13"),
        ]
        for (raw, expectedKey) in samples {
            guard let parsed = FormatUtils.parseFlexDate(raw) else {
                XCTFail("格式 \(raw) 解析失败")
                continue
            }
            XCTAssertEqual(FormatUtils.formatBeijingDate(parsed).dateKey, expectedKey, "格式 \(raw) 解析结果不正确")
        }
    }

    /// 金额解析：四舍五入而非截断
    func testYuanToCentsRoundsInsteadOfTruncating() {
        XCTAssertEqual(FormatUtils.parseYuanToCentsAllowZero("0.999"), 100)
        XCTAssertEqual(FormatUtils.parseYuanToCentsAllowZero("42.999"), 4300)
        XCTAssertEqual(FormatUtils.parseYuanToCentsAllowZero("42.5"), 4250)
        XCTAssertEqual(FormatUtils.parseYuanToCentsAllowZero("0"), 0, "0 元必须能被区分于解析失败")
        XCTAssertNil(FormatUtils.parseYuanToCentsAllowZero("abc"))
    }

    /// CSV 公式注入：前导空格也必须被中和（Excel 会 trim 后执行）
    func testCSVNeutralizesFormulaInjectionWithLeadingWhitespace() {
        let tx = Transaction(
            id: 99,
            amount: 100,
            type: "expense",
            category: "餐饮",
            title: " =cmd|'/c calc'!A1",
            note: "",
            paymentMethod: "现金",
            cityCode: "330100",
            occurredAt: "2026-10-14T09:30:00+08:00"
        )
        let csv = ArchiveExporter.makeTransactionsCSV(transactions: [tx])
        XCTAssertTrue(csv.contains("'=cmd"), "前导空格后的公式注入必须被中和：\(csv)")
    }

    /// Outbox 排序：乐观插入的记录必须按发生时间归位，而不是插到列表顶部
    func testSortedEntriesPlacesOptimisticRecordByDate() {
        let older = LifeEntry(id: 1, title: "旧", content: "", occurredAt: "2024-01-01T10:00:00+08:00")
        let newer = LifeEntry(id: 2, title: "新", content: "", occurredAt: "2026-05-05T10:00:00+08:00")
        let sorted = SyncManager.sortedEntries([older, newer])
        XCTAssertEqual(sorted.first?.id, 2, "时间较新的记录必须排在前面")
    }

    /// 日期解析的 Date 版本与字符串版本结果一致
    func testDaysBetweenDateOverloadMatchesStringVersion() {
        let a = FormatUtils.parseFlexDate("2026-10-01 08:00:00")!
        let b = FormatUtils.parseFlexDate("2026-10-20 19:00:00")!
        XCTAssertEqual(FormatUtils.daysBetween(a, b), FormatUtils.daysBetween("2026-10-01 08:00:00", "2026-10-20 19:00:00"))
    }

    /// 语义色对比度回归：全部语义色在浅/深两档都必须达到 WCAG AA 正文级（≥ 4.5:1）。
    /// 与 CI 中的 `scripts/check_color_contrast.py` 门禁互为双保险。
    func testSemanticColorsMeetWCAGAAContrast() throws {
        // 定位 Assets.xcassets。
        // 注意：SPM 的 .process 会用 actool 把资源编译成资产目录，
        // 原始 Colorset JSON 不会打进 Bundle，因此从源码路径定位。
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // LooseLeafTests
            .deletingLastPathComponent()          // mac
            .appendingPathComponent("LooseLeaf/Resources/Assets.xcassets")
        var assetsURL: URL? = FileManager.default.fileExists(atPath: sourceRoot.path) ? sourceRoot : nil
        #if SWIFT_PACKAGE
        // Bundle.module 是 SPM 专属 API，在 Xcode target 下不存在，需条件编译隔离
        if assetsURL == nil {
            assetsURL = Bundle.module.url(forResource: "Assets", withExtension: "xcassets")
        }
        #endif
        let root = try XCTUnwrap(assetsURL, "无法定位 Assets.xcassets")

        func luminance(_ rgb: (Double, Double, Double)) -> Double {
            func channel(_ v: Double) -> Double {
                v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(rgb.0) + 0.7152 * channel(rgb.1) + 0.0722 * channel(rgb.2)
        }
        func ratio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
            let la = luminance(a), lb = luminance(b)
            let hi = max(la, lb), lo = min(la, lb)
            return (hi + 0.05) / (lo + 0.05)
        }
        func parseHex(_ value: String) -> (Double, Double, Double) {
            let cleaned = value.replacingOccurrences(of: "0x", with: "")
            func part(_ offset: Int) -> Double {
                let start = cleaned.index(cleaned.startIndex, offsetBy: offset)
                let end = cleaned.index(start, offsetBy: 2)
                let hexPart = String(cleaned[start..<end])
                return Double(UInt16(hexPart, radix: 16) ?? 0)
            }
            return (part(0) / 255.0, part(2) / 255.0, part(4) / 255.0)
        }

        struct ColorSet: Decodable {
            struct Entry: Decodable {
                struct Color: Decodable {
                    struct Components: Decodable {
                        let red: String
                        let green: String
                        let blue: String
                    }
                    let components: Components
                }
                let color: Color
                let appearances: [Appearance]?

                struct Appearance: Decodable {
                    let appearance: String
                    let value: String
                }
            }
            let colors: [Entry]
        }

        let fileManager = FileManager.default
        let colorsetDirs = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "colorset" }

        var paperLight: (Double, Double, Double)?
        var paperDark: (Double, Double, Double)?

        for dir in colorsetDirs {
            let name = dir.deletingPathExtension().lastPathComponent
            let jsonURL = dir.appendingPathComponent("Contents.json")
            guard let data = try? Data(contentsOf: jsonURL),
                  let decoded = try? JSONDecoder().decode(ColorSet.self, from: data) else { continue }

            var light: (Double, Double, Double)?
            var dark: (Double, Double, Double)?
            for entry in decoded.colors {
                let c = entry.color.components
                let rgb = parseHex(c.red + c.green + c.blue)
                let isDark = entry.appearances?.contains { $0.value == "dark" } ?? false
                if isDark { dark = rgb } else { light = rgb }
            }
            if name == "ArchivePaper" {
                paperLight = light
                paperDark = dark
            }
        }

        let bgLight = try XCTUnwrap(paperLight)
        let bgDark = try XCTUnwrap(paperDark)

        // 仅背景/边框类语义色不参与「正文级」判定
        let nonText = Set(["ArchivePaper", "ArchiveSubtle", "BorderSubtle", "BorderDivider"])

        for dir in colorsetDirs {
            let name = dir.deletingPathExtension().lastPathComponent
            if nonText.contains(name) { continue }
            let jsonURL = dir.appendingPathComponent("Contents.json")
            guard let data = try? Data(contentsOf: jsonURL),
                  let decoded = try? JSONDecoder().decode(ColorSet.self, from: data) else { continue }
            for entry in decoded.colors {
                let c = entry.color.components
                let rgb = parseHex(c.red + c.green + c.blue)
                let isDark = entry.appearances?.contains { $0.value == "dark" } ?? false
                let bg = isDark ? bgDark : bgLight
                let value = ratio(rgb, bg)
                XCTAssertGreaterThanOrEqual(
                    value, 4.5,
                    "\(name) 在 \(isDark ? "深色" : "浅色") 模式下对比度仅 \(String(format: "%.2f", value)):1，不达 WCAG AA"
                )
            }
        }
    }

    /// 索引令牌：命中区与间距阶梯必须存在且为正值
    func testDesignTokensAreSane() {
        XCTAssertGreaterThanOrEqual(ArchiveHitTarget.minPointer, 28)
        XCTAssertGreaterThanOrEqual(ArchiveHitTarget.minTouch, 44)
        XCTAssertGreaterThan(ArchiveSpacing.xl, ArchiveSpacing.l)
        XCTAssertGreaterThan(ArchiveSpacing.l, ArchiveSpacing.m)
        XCTAssertGreaterThan(ArchiveSpacing.m, ArchiveSpacing.s)
        XCTAssertGreaterThanOrEqual(ArchiveTypography.Scale.micro, 10, "正文级最小字号不得低于 10pt")
    }
}

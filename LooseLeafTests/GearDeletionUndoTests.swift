import XCTest
@testable import LooseLeaf

/// 随身设备删除的 ⌘Z 撤销（MC-03）
///
/// 背景：器物删除原先是**硬删** —— 设备本体从主理人档案的 JSON 数组里被移除，
/// 伴生散页也一并软删，而软删的散页**没有恢复端点**。
/// 于是误删一件设备，它的照片与手记就**永久回不来**。
///
/// 现在删除后登记一次撤销，撤销时把**原始设备数据**带回服务端，
/// 由服务端按原 id 插回档案数组，并连带恢复伴生散页。
/// ��以这里要钉住的是「撤销载荷**不丢字段**」——
/// 少传一个字段，恢复出来的设备就与删除前不是同一件东西。
@MainActor
final class GearDeletionUndoTests: XCTestCase {

    private func sampleGear() -> GearItem {
        GearItem(
            id: "gear_abc123",
            name: "测试相机",
            spec: "规格说明",
            category: "数码器材",
            status: "active",
            priceCents: 199_900,
            purchaseDate: "2026-10-01",
            soldPriceCents: nil,
            soldDate: nil,
            note: "备注"
        )
    }

    /// 撤销载荷必须**原样**带上设备的所有字段
    func test01_RestorePayloadCarriesEveryField() {
        let gear = sampleGear()
        let req = RestoreGearAssetRequest(
            id: gear.id,
            name: gear.name,
            spec: gear.spec,
            category: gear.category,
            status: gear.status,
            priceCents: gear.priceCents,
            purchaseDate: gear.purchaseDate,
            soldPriceCents: gear.soldPriceCents,
            soldDate: gear.soldDate,
            note: gear.note,
            index: 3
        )
        XCTAssertEqual(req.id, gear.id)
        XCTAssertEqual(req.name, gear.name)
        XCTAssertEqual(req.spec, gear.spec)
        XCTAssertEqual(req.category, gear.category)
        XCTAssertEqual(req.status, gear.status)
        XCTAssertEqual(req.priceCents, gear.priceCents)
        XCTAssertEqual(req.purchaseDate, gear.purchaseDate)
        XCTAssertEqual(req.soldPriceCents, gear.soldPriceCents)
        XCTAssertEqual(req.soldDate, gear.soldDate)
        XCTAssertEqual(req.note, gear.note)
        XCTAssertEqual(req.index, 3, "原位置必须带回，恢复的设备要回到原来的位置")
    }

    /// 线格式：字段名必须与服务端契约一致
    func test02_WireFormatMatchesContract() throws {
        let req = RestoreGearAssetRequest(
            id: "gear_1",
            name: "设备",
            category: "数码器材",
            priceCents: 1234,
            index: 2
        )
        let json = String(data: try JSONEncoder().encode(req), encoding: .utf8) ?? ""
        for key in ["\"id\"", "\"name\"", "\"category\"", "\"price_cents\"", "\"index\""] {
            XCTAssertTrue(json.contains(key), "请求体必须包含 \(key)，实际: \(json)")
        }
        XCTAssertFalse(
            json.contains("\"priceCents\""),
            "价格字段名必须是 price_cents（服务端按 snake_case 解析），实际: \(json)"
        )
    }

    /// 索引缺省应为 -1（追加到末尾），而不是 0
    ///
    /// 关键：0 是**合法**的「第 0 位」，若缺省值写成 0，
    /// 恢复的设备就会被塞到数组最前面 —— 与删除前的位置不符。
    func test03_DefaultIndexIsAppendNotFirst() {
        let req = RestoreGearAssetRequest(id: "gear_1", name: "设备")
        XCTAssertEqual(req.index, -1, "缺省索引必须是 -1（追加到末尾），0 会被误解为「放到第 0 位」")
    }
}

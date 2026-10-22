import XCTest
@testable import LooseLeaf

/// 造物「项目故事」与「展示顺序」的写入契约（MC-04）
///
/// 背景：这两个字段**后端早���支持**（`ProjectRequest.Story` / `ProjectUpdateRequest.Order`），
/// Web 端也能编辑，但桌面端的请求模型里压根没有 ——
/// 于是「用 Web 写了一段项目故事，再用桌面端改个标题」，
/// 桌面端既**看不到**也**改不了**这段故事。
///
/// 关键：后端的更新接口是**指针语义**（`Story *string` / `Order *int`）——
/// 省略即保持原值。于是桌面端必须：
/// - **始终携带** `story`（连空串也发）：省略 = 保持原值 ⇒ 用户把故事**删空**时永远清不掉；
/// - `order` 原样带回：桌面端没有排序编辑入口，但也不能让它悄悄丢。
@MainActor
final class ProjectStoryWritingTests: XCTestCase {

    private func encode(_ req: CreateProjectRequest) throws -> String {
        let data = try JSONEncoder().encode(req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 故事为空串时**必须发出去**（省略即保持原值 ⇒ 清不掉）
    func test01_EmptyStoryIsStillSentSoItCanBeCleared() throws {
        let json = try encode(CreateProjectRequest(
            title: "造物",
            description: "背景",
            story: ""
        ))
        XCTAssertTrue(
            json.contains("\"story\":\""),
            "story 为空串时必须显式发出（发空串 = 清空故事），实际: \(json)"
        )
        XCTAssertFalse(
            json.contains("\"story\":null"),
            "story 不应是 null，实际: \(json)"
        )
    }

    /// 故事为 nil 时省略（新建时不需要这个字段）
    func test02_NilStoryIsOmitted() throws {
        let json = try encode(CreateProjectRequest(
            title: "造物",
            description: "背景",
            story: nil
        ))
        XCTAssertFalse(
            json.contains("\"story\""),
            "story 为 nil 时应省略该字段，实际: \(json)"
        )
    }

    /// 有故事时内容原样发出
    func test03_StoryContentIsPreserved() throws {
        let json = try encode(CreateProjectRequest(
            title: "造物",
            description: "背景",
            story: "一段关于这个造物的故事。"
        ))
        XCTAssertTrue(
            json.contains("\"story\":\"一段关于这个造物的故事。\""),
            "故事内容必须原样发出，实际: \(json)"
        )
    }

    /// 展示顺序原样带回（桌面端没有排序入口，但不能悄悄丢）
    func test04_OrderIsCarriedThrough() throws {
        let json = try encode(CreateProjectRequest(
            title: "造物",
            description: "背景",
            order: 7
        ))
        XCTAssertTrue(
            json.contains("\"order\":7"),
            "order 必须原样带回，实际: \(json)"
        )
    }

    func test05_NilOrderIsOmitted() throws {
        let json = try encode(CreateProjectRequest(
            title: "造物",
            description: "背景",
            order: nil
        ))
        XCTAssertFalse(
            json.contains("\"order\""),
            "order 为 nil 时应省略（后端指针语义 = 保持原值），实际: \(json)"
        )
    }

    /// 响应模型能读出这两个字段（桌面端此前**读**得到、只是**写**不了）
    func test06_ResponseModelDecodesStoryAndOrder() throws {
        let payload = """
        {"id":1,"title":"造物","description":"背景","story":"一段故事","order":7}
        """
        let project = try JSONDecoder().decode(Project.self, from: Data(payload.utf8))
        XCTAssertEqual(project.story, "一段故事")
        XCTAssertEqual(project.order, 7)
    }
}

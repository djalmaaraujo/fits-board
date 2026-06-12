import XCTest
@testable import FitsCore

final class FitsCoreTests: XCTestCase {
    func testTaskValidationRequiresTitleDescriptionWorkspaceAndProject() {
        XCTAssertThrowsError(
            try FitsTask(
                title: "",
                description: "Plan a native board",
                workspaceId: "ws-main",
                projectId: "project-main"
            )
        )

        XCTAssertThrowsError(
            try FitsTask(
                title: "Plan the task",
                description: "",
                workspaceId: "ws-main",
                projectId: "project-main"
            )
        )

        XCTAssertThrowsError(
            try FitsTask(
                title: "Plan the task",
                description: "Plan a native board",
                workspaceId: "",
                projectId: "project-main"
            )
        )

        XCTAssertThrowsError(
            try FitsTask(
                title: "Plan the task",
                description: "Plan a native board",
                workspaceId: "ws-main",
                projectId: ""
            )
        )
    }

    func testValidTaskDefaultsToIntakeColumn() throws {
        let task = try FitsTask(
            title: "Plan the task",
            description: "Plan a native board",
            workspaceId: "ws-main",
            projectId: "project-main"
        )

        XCTAssertEqual(task.columnId, BoardColumn.intake.id)
        XCTAssertFalse(task.id.isEmpty)
    }

    func testTaskPlanningTypeDefaultsToFastAndCanBeSet() throws {
        let defaultTask = try FitsTask(
            title: "Plan the task",
            description: "Plan a native board",
            workspaceId: "ws-main",
            projectId: "project-main"
        )
        let superpowersTask = try FitsTask(
            title: "Plan carefully",
            description: "Use a guided planning flow",
            workspaceId: "ws-main",
            projectId: "project-main",
            planningType: .superpowersSkill
        )

        XCTAssertEqual(defaultTask.planningType, .fast)
        XCTAssertEqual(superpowersTask.planningType, .superpowersSkill)
    }

    func testTaskMetatagDefaultsToEmptyAndCanBeSet() throws {
        let defaultTask = try FitsTask(
            title: "Plan the task",
            description: "Plan a native board",
            workspaceId: "ws-main",
            projectId: "project-main"
        )
        let taggedTask = try FitsTask(
            title: "Run agent review",
            description: "Review implementation with an agent",
            workspaceId: "ws-main",
            projectId: "project-main",
            metatag: [
                "agent": "critic-opus",
                "branch": "agent/i18n-forms",
                "progress": "90%"
            ]
        )

        XCTAssertEqual(defaultTask.metatag, [:])
        XCTAssertEqual(taggedTask.metatag["agent"], "critic-opus")
        XCTAssertEqual(taggedTask.metatag["branch"], "agent/i18n-forms")
        XCTAssertEqual(taggedTask.metatag["progress"], "90%")
    }

    func testTaskPlanningTypeDecodesFastForExistingJson() throws {
        let data = """
        {
          "id": "task-legacy",
          "title": "Legacy task",
          "description": "Legacy description",
          "workspaceId": "ws-main",
          "projectId": "project-main",
          "columnId": "intake",
          "createdAt": "100",
          "updatedAt": "100"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(timeIntervalSinceReferenceDate: try Double(container.decode(String.self)) ?? 0)
        }
        let task = try decoder.decode(FitsTask.self, from: data)

        XCTAssertEqual(task.planningType, .fast)
    }

    func testTaskMetatagDecodesEmptyForExistingJson() throws {
        let data = """
        {
          "id": "task-legacy",
          "title": "Legacy task",
          "description": "Legacy description",
          "workspaceId": "ws-main",
          "projectId": "project-main",
          "columnId": "intake",
          "createdAt": "100",
          "updatedAt": "100"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(timeIntervalSinceReferenceDate: try Double(container.decode(String.self)) ?? 0)
        }
        let task = try decoder.decode(FitsTask.self, from: data)

        XCTAssertEqual(task.metatag, [:])
    }

    func testTaskMetatagDecodesFromJson() throws {
        let data = """
        {
          "id": "task-tagged",
          "title": "Tagged task",
          "description": "Tagged description",
          "workspaceId": "ws-main",
          "projectId": "project-main",
          "planningType": "fast",
          "metatag": {
            "agent": "critic-opus",
            "branch": "agent/i18n-forms"
          },
          "columnId": "review",
          "createdAt": "100",
          "updatedAt": "100"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(timeIntervalSinceReferenceDate: try Double(container.decode(String.self)) ?? 0)
        }
        let task = try decoder.decode(FitsTask.self, from: data)

        XCTAssertEqual(task.metatag["agent"], "critic-opus")
        XCTAssertEqual(task.metatag["branch"], "agent/i18n-forms")
    }
}

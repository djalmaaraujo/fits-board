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
}

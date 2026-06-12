import XCTest
@testable import FitsCore

final class BoardStateTests: XCTestCase {
    func testWorkspaceFilteringSupportsAllOneAndMany() throws {
        let board = try sampleBoard()

        XCTAssertEqual(BoardState.filteredTasks(in: board, selectedWorkspaceIds: []).map(\.id), [
            "task-a",
            "task-b",
            "task-c"
        ])

        XCTAssertEqual(BoardState.filteredTasks(in: board, selectedWorkspaceIds: ["ws-a"]).map(\.id), [
            "task-a",
            "task-c"
        ])

        XCTAssertEqual(BoardState.filteredTasks(in: board, selectedWorkspaceIds: ["ws-a", "ws-b"]).map(\.id), [
            "task-a",
            "task-b",
            "task-c"
        ])
    }

    func testCompleteDraftPromotesIntoIntakeTaskAndClearsText() throws {
        var board = try sampleBoard()
        board.draftTask = DraftTask(
            workspaceId: "ws-a",
            projectId: "project-a",
            planningType: .superpowersSkill,
            title: "Write task spec",
            description: "Create the task spec before fan-out"
        )

        let task = try BoardState.promoteDraftIfComplete(in: &board)

        XCTAssertEqual(task?.title, "Write task spec")
        XCTAssertEqual(task?.columnId, BoardColumn.intake.id)
        XCTAssertEqual(task?.planningType, .superpowersSkill)
        XCTAssertEqual(board.tasks.last?.title, "Write task spec")
        XCTAssertEqual(board.tasks.last?.planningType, .superpowersSkill)
        XCTAssertEqual(board.draftTask.workspaceId, "ws-a")
        XCTAssertEqual(board.draftTask.projectId, "project-a")
        XCTAssertEqual(board.draftTask.planningType, .superpowersSkill)
        XCTAssertEqual(board.draftTask.title, "")
        XCTAssertEqual(board.draftTask.description, "")
    }

    func testIncompleteDraftDoesNotPromote() throws {
        var board = try sampleBoard()
        board.draftTask = DraftTask(
            workspaceId: "ws-a",
            projectId: "project-a",
            title: "Missing description",
            description: ""
        )

        let task = try BoardState.promoteDraftIfComplete(in: &board)

        XCTAssertNil(task)
        XCTAssertEqual(board.tasks.count, 3)
    }

    func testRemoveWorkspaceCascadesProjectsTasksFiltersAndDraft() throws {
        var board = try sampleBoard()
        board.settings.selectedWorkspaceIds = ["ws-a", "ws-b"]
        board.draftTask = DraftTask(
            workspaceId: "ws-a",
            projectId: "project-a",
            title: "Draft title",
            description: "Draft description"
        )

        let removed = BoardState.removeWorkspace(id: "ws-a", in: &board)

        XCTAssertTrue(removed)
        XCTAssertEqual(board.workspaces.map(\.id), ["ws-b"])
        XCTAssertEqual(board.projects.map(\.id), ["project-b"])
        XCTAssertEqual(board.tasks.map(\.id), ["task-b"])
        XCTAssertEqual(board.settings.selectedWorkspaceIds, ["ws-b"])
        XCTAssertEqual(board.draftTask.workspaceId, "ws-b")
        XCTAssertEqual(board.draftTask.projectId, "project-b")
        XCTAssertEqual(board.draftTask.title, "Draft title")
        XCTAssertEqual(board.draftTask.description, "Draft description")
    }

    func testRemoveBacklogTaskDeletesOnlyThatTask() throws {
        var board = try sampleBoard()

        let removed = BoardState.removeBacklogTask(id: "task-a", in: &board)

        XCTAssertTrue(removed)
        XCTAssertEqual(board.tasks.map(\.id), ["task-b", "task-c"])
    }

    func testRemoveBacklogTaskRejectsTaskAfterBacklog() throws {
        var board = try sampleBoard()

        let removed = BoardState.removeBacklogTask(id: "task-b", in: &board)

        XCTAssertFalse(removed)
        XCTAssertEqual(board.tasks.map(\.id), ["task-a", "task-b", "task-c"])
    }

    func testMergeTaskMetatagAddsAndUpdatesValues() throws {
        var board = try sampleBoard()
        let originalUpdatedAt = try XCTUnwrap(board.tasks.first { $0.id == "task-b" }).updatedAt

        let updated = BoardState.mergeTaskMetatag(
            id: "task-b",
            values: [
                "agent": "critic-opus",
                "branch": "agent/i18n-forms"
            ],
            in: &board
        )

        XCTAssertTrue(updated)
        let task = try XCTUnwrap(board.tasks.first { $0.id == "task-b" })
        XCTAssertEqual(task.metatag["agent"], "critic-opus")
        XCTAssertEqual(task.metatag["branch"], "agent/i18n-forms")
        XCTAssertGreaterThan(task.updatedAt, originalUpdatedAt)
    }

    func testMergeTaskMetatagRejectsMissingTask() throws {
        var board = try sampleBoard()

        let updated = BoardState.mergeTaskMetatag(id: "missing", values: ["agent": "critic-opus"], in: &board)

        XCTAssertFalse(updated)
    }

    func testUpdateBacklogTaskCanChangeWorkspaceAndProject() throws {
        var board = try sampleBoard()

        let updated = BoardState.updateTaskDefinition(
            id: "task-a",
            title: "Updated title",
            description: "Updated description",
            workspaceId: "ws-b",
            projectId: "project-b",
            planningType: .llmPlanMode,
            in: &board
        )

        XCTAssertTrue(updated)
        let task = try XCTUnwrap(board.tasks.first { $0.id == "task-a" })
        XCTAssertEqual(task.title, "Updated title")
        XCTAssertEqual(task.description, "Updated description")
        XCTAssertEqual(task.workspaceId, "ws-b")
        XCTAssertEqual(task.projectId, "project-b")
        XCTAssertEqual(task.planningType, .llmPlanMode)
    }

    func testUpdateNonBacklogTaskKeepsWorkspaceProjectDescriptionAndPlanningType() throws {
        var board = try sampleBoard()
        let originalUpdatedAt = try XCTUnwrap(board.tasks.first { $0.id == "task-b" }).updatedAt

        let updated = BoardState.updateTaskDefinition(
            id: "task-b",
            title: "Planned task title",
            description: "Planned task description",
            workspaceId: "ws-a",
            projectId: "project-a",
            planningType: .superpowersSkill,
            in: &board
        )

        XCTAssertTrue(updated)
        let task = try XCTUnwrap(board.tasks.first { $0.id == "task-b" })
        XCTAssertEqual(task.title, "Planned task title")
        XCTAssertEqual(task.description, "B desc")
        XCTAssertEqual(task.workspaceId, "ws-b")
        XCTAssertEqual(task.projectId, "project-b")
        XCTAssertEqual(task.planningType, .fast)
        XCTAssertGreaterThan(task.updatedAt, originalUpdatedAt)
    }

    func testUpdateBacklogTaskRejectsInvalidProjectWithoutChangingTask() throws {
        var board = try sampleBoard()
        let originalTask = try XCTUnwrap(board.tasks.first { $0.id == "task-a" })

        let updated = BoardState.updateTaskDefinition(
            id: "task-a",
            title: "Should not stick",
            description: "Should not stick",
            workspaceId: "ws-b",
            projectId: "project-a",
            in: &board
        )

        XCTAssertFalse(updated)
        let task = try XCTUnwrap(board.tasks.first { $0.id == "task-a" })
        XCTAssertEqual(task, originalTask)
    }

    private func sampleBoard() throws -> BoardData {
        let workspaceA = FitsWorkspace(id: "ws-a", name: "a", displayName: "A", commitEmail: "a@example.com")
        let workspaceB = FitsWorkspace(id: "ws-b", name: "b", displayName: "B", commitEmail: "b@example.com")
        let projectA = FitsProject(id: "project-a", workspaceId: "ws-a", name: "Project A")
        let projectB = FitsProject(id: "project-b", workspaceId: "ws-b", name: "Project B")

        return BoardData(
            workspaces: [workspaceA, workspaceB],
            projects: [projectA, projectB],
            tasks: [
                try FitsTask(id: "task-a", title: "A", description: "A desc", workspaceId: "ws-a", projectId: "project-a"),
                try FitsTask(id: "task-b", title: "B", description: "B desc", workspaceId: "ws-b", projectId: "project-b", columnId: BoardColumn.spec.id),
                try FitsTask(id: "task-c", title: "C", description: "C desc", workspaceId: "ws-a", projectId: "project-a")
            ]
        )
    }
}

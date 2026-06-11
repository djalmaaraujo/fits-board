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
            title: "Write task spec",
            description: "Create the task spec before fan-out"
        )

        let task = try BoardState.promoteDraftIfComplete(in: &board)

        XCTAssertEqual(task?.title, "Write task spec")
        XCTAssertEqual(task?.columnId, BoardColumn.intake.id)
        XCTAssertEqual(board.tasks.last?.title, "Write task spec")
        XCTAssertEqual(board.draftTask.workspaceId, "ws-a")
        XCTAssertEqual(board.draftTask.projectId, "project-a")
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
                try FitsTask(id: "task-b", title: "B", description: "B desc", workspaceId: "ws-b", projectId: "project-b"),
                try FitsTask(id: "task-c", title: "C", description: "C desc", workspaceId: "ws-a", projectId: "project-a")
            ]
        )
    }
}

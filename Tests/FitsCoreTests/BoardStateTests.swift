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

    func testMoveTaskIntoPipelineCreatesRunEventAndMetatag() throws {
        var board = try sampleBoard()
        let timestamp = Date(timeIntervalSinceReferenceDate: 42)

        let run = BoardState.moveTask(
            id: "task-a",
            to: BoardColumn.plan,
            in: &board,
            at: timestamp
        )

        XCTAssertEqual(board.tasks.first { $0.id == "task-a" }?.columnId, BoardColumn.plan.id)
        XCTAssertEqual(board.tasks.first { $0.id == "task-a" }?.metatag["stage"], "Agent Fan out")
        XCTAssertEqual(board.tasks.first { $0.id == "task-a" }?.metatag["status"], "running")
        XCTAssertEqual(board.tasks.first { $0.id == "task-a" }?.metatag["tools"], "Codex CLI, fits-agent-host, git worktree")
        XCTAssertEqual(run?.taskId, "task-a")
        XCTAssertEqual(run?.currentColumnId, BoardColumn.plan.id)
        XCTAssertEqual(run?.status, .running)
        XCTAssertEqual(run?.events.count, 2)
        XCTAssertEqual(run?.events.first?.level, .info)
        XCTAssertEqual(run?.events.first?.message, "Entered Agent Fan out")
        XCTAssertEqual(run?.events.last?.level, .run)
        XCTAssertEqual(run?.events.last?.tool, "Codex CLI")
    }

    func testMoveTaskThroughPipelineKeepsSingleRunAndWaitsAtHumanReview() throws {
        var board = try sampleBoard()

        _ = BoardState.moveTask(id: "task-a", to: BoardColumn.spec, in: &board)
        _ = BoardState.moveTask(id: "task-a", to: BoardColumn.plan, in: &board)
        _ = BoardState.moveTask(id: "task-a", to: BoardColumn.agentQA, in: &board)
        _ = BoardState.moveTask(id: "task-a", to: BoardColumn.review, in: &board)
        let run = BoardState.moveTask(id: "task-a", to: BoardColumn.humanReview, in: &board)

        XCTAssertEqual(board.runs.count, 1)
        XCTAssertEqual(run?.currentColumnId, BoardColumn.humanReview.id)
        XCTAssertEqual(run?.status, .waitingForHuman)
        XCTAssertEqual(board.tasks.first { $0.id == "task-a" }?.columnId, BoardColumn.humanReview.id)
        XCTAssertEqual(board.tasks.first { $0.id == "task-a" }?.metatag["stage"], "Human Review")
        XCTAssertEqual(board.tasks.first { $0.id == "task-a" }?.metatag["status"], "waiting_for_human")
        XCTAssertTrue(run?.events.contains { $0.columnId == BoardColumn.review.id && $0.tool == "Live spec check" } ?? false)
        XCTAssertTrue(run?.events.contains { $0.columnId == BoardColumn.humanReview.id && $0.tool == "Human approval" } ?? false)
    }

    func testMovingTaskBackToBacklogClearsExecutionContext() throws {
        var board = try sampleBoard()
        _ = BoardState.moveTask(id: "task-a", to: BoardColumn.spec, in: &board)
        _ = BoardState.ensureAgentSession(
            taskId: "task-a",
            columnId: BoardColumn.spec.id,
            toolId: "codex",
            toolDisplayName: "Codex CLI",
            resumeCommand: "codex resume --last",
            in: &board
        )
        _ = BoardState.mergeTaskMetatag(
            id: "task-a",
            values: ["agent_external_session_id": "11111111-2222-3333-4444-555555555555", "progress": "old"],
            in: &board
        )

        let run = BoardState.moveTask(id: "task-a", to: BoardColumn.intake, in: &board)

        XCTAssertNil(run)
        XCTAssertFalse(board.runs.contains { $0.taskId == "task-a" })
        XCTAssertEqual(board.tasks.first { $0.id == "task-a" }?.columnId, BoardColumn.intake.id)
        XCTAssertEqual(board.tasks.first { $0.id == "task-a" }?.metatag, [:])
    }

    func testNextColumnSupportsAutomaticPipelineAdvance() throws {
        let board = try sampleBoard()

        XCTAssertEqual(BoardState.nextColumn(after: BoardColumn.spec.id, in: board)?.id, BoardColumn.plan.id)
        XCTAssertEqual(BoardState.nextColumn(after: BoardColumn.plan.id, in: board)?.id, BoardColumn.agentQA.id)
        XCTAssertEqual(BoardState.nextColumn(after: BoardColumn.review.id, in: board)?.id, BoardColumn.humanReview.id)
        XCTAssertNil(BoardState.nextColumn(after: BoardColumn.done.id, in: board))
    }

    func testAppendPipelineEventAddsAgentOutputToExistingRun() throws {
        var board = try sampleBoard()
        _ = BoardState.moveTask(id: "task-a", to: BoardColumn.spec, in: &board)

        let event = BoardState.appendPipelineEvent(
            taskId: "task-a",
            columnId: BoardColumn.spec.id,
            level: .info,
            tool: "Codex stdout",
            message: "Repository summary written",
            in: &board
        )

        XCTAssertEqual(event?.message, "Repository summary written")
        XCTAssertEqual(board.runs.count, 1)
        XCTAssertEqual(board.runs.first?.currentColumnId, BoardColumn.spec.id)
        XCTAssertTrue(board.runs.first?.events.contains { $0.tool == "Codex stdout" } ?? false)
    }

    func testAppendPipelineEventKeepsOnlyRecentEventsInBoardState() throws {
        var board = try sampleBoard()
        _ = BoardState.moveTask(id: "task-a", to: BoardColumn.spec, in: &board)

        for index in 0..<500 {
            _ = BoardState.appendPipelineEvent(
                taskId: "task-a",
                columnId: BoardColumn.spec.id,
                level: .info,
                tool: "Codex stdout",
                message: "line \(index)",
                in: &board
            )
        }

        let events = try XCTUnwrap(board.runs.first?.events)
        XCTAssertEqual(events.count, BoardState.maximumRetainedEventsPerRun)
        XCTAssertEqual(events.first?.message, "line 200")
        XCTAssertEqual(events.last?.message, "line 499")
        XCTAssertEqual(Set(events.map(\.id)).count, events.count)
    }

    func testEnsureAgentSessionCreatesStableResumeMetadata() throws {
        var board = try sampleBoard()
        _ = BoardState.moveTask(id: "task-a", to: BoardColumn.spec, in: &board)

        let session = BoardState.ensureAgentSession(
            taskId: "task-a",
            columnId: BoardColumn.spec.id,
            toolId: "codex",
            toolDisplayName: "Codex CLI",
            resumeCommand: "codex exec resume abc-123",
            in: &board,
            at: Date(timeIntervalSinceReferenceDate: 10)
        )

        XCTAssertEqual(session?.toolId, "codex")
        XCTAssertEqual(session?.toolDisplayName, "Codex CLI")
        XCTAssertEqual(session?.resumeCommand, "codex exec resume abc-123")
        XCTAssertEqual(session?.status, .running)
        XCTAssertEqual(board.runs.first?.agentSession?.id, session?.id)
        XCTAssertEqual(board.runs.first?.events.last?.tool, "Codex CLI")
        XCTAssertEqual(board.runs.first?.events.last?.message, "Agent session \(session?.id ?? "") started")

        let second = BoardState.ensureAgentSession(
            taskId: "task-a",
            columnId: BoardColumn.spec.id,
            toolId: "codex",
            toolDisplayName: "Codex CLI",
            resumeCommand: "codex exec resume different",
            in: &board,
            at: Date(timeIntervalSinceReferenceDate: 11)
        )

        XCTAssertEqual(second?.id, session?.id)
        XCTAssertEqual(second?.resumeCommand, "codex exec resume abc-123")
    }

    func testUpdateExternalAgentSessionIdRewritesResumeCommand() throws {
        var board = try sampleBoard()
        _ = BoardState.moveTask(id: "task-a", to: BoardColumn.spec, in: &board)
        _ = BoardState.ensureAgentSession(
            taskId: "task-a",
            columnId: BoardColumn.spec.id,
            toolId: "codex",
            toolDisplayName: "Codex CLI",
            resumeCommand: "codex exec resume fits-session",
            in: &board
        )

        let updated = BoardState.updateAgentSessionExternalId(
            taskId: "task-a",
            externalSessionId: "11111111-2222-3333-4444-555555555555",
            resumeCommand: "codex exec resume 11111111-2222-3333-4444-555555555555",
            in: &board
        )

        XCTAssertTrue(updated)
        XCTAssertEqual(board.runs.first?.agentSession?.externalSessionId, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(board.runs.first?.agentSession?.resumeCommand, "codex exec resume 11111111-2222-3333-4444-555555555555")
    }

    func testUpdateExternalAgentSessionIdRejectsFitsSessionId() throws {
        var board = try sampleBoard()
        _ = BoardState.moveTask(id: "task-a", to: BoardColumn.spec, in: &board)
        let session = try XCTUnwrap(BoardState.ensureAgentSession(
            taskId: "task-a",
            columnId: BoardColumn.spec.id,
            toolId: "codex",
            toolDisplayName: "Codex CLI",
            resumeCommand: "codex resume --last",
            in: &board
        ))

        let updated = BoardState.updateAgentSessionExternalId(
            taskId: "task-a",
            externalSessionId: session.id,
            resumeCommand: "codex resume \(session.id)",
            in: &board
        )

        XCTAssertFalse(updated)
        XCTAssertNil(board.runs.first?.agentSession?.externalSessionId)
        XCTAssertEqual(board.runs.first?.agentSession?.resumeCommand, "codex resume --last")
        XCTAssertNil(board.tasks.first { $0.id == "task-a" }?.metatag["agent_external_session_id"])
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

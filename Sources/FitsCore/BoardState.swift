import Foundation

public enum BoardState {
    public static let maximumRetainedEventsPerRun = 300

    public static func filteredTasks(
        in board: BoardData,
        selectedWorkspaceIds: [String]
    ) -> [FitsTask] {
        guard !selectedWorkspaceIds.isEmpty else {
            return board.tasks
        }

        let selected = Set(selectedWorkspaceIds)
        return board.tasks.filter { selected.contains($0.workspaceId) }
    }

    public static func nextColumn(after columnId: String, in board: BoardData) -> BoardColumn? {
        guard let index = board.columns.firstIndex(where: { $0.id == columnId }) else {
            return nil
        }
        let nextIndex = board.columns.index(after: index)
        guard nextIndex < board.columns.endIndex else {
            return nil
        }
        return board.columns[nextIndex]
    }

    @discardableResult
    public static func promoteDraftIfComplete(in board: inout BoardData) throws -> FitsTask? {
        let draft = board.draftTask
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.workspaceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let task = try FitsTask(
            title: draft.title,
            description: draft.description,
            workspaceId: draft.workspaceId,
            projectId: draft.projectId,
            planningType: draft.planningType,
            columnId: BoardColumn.intake.id
        )
        board.tasks.append(task)
        board.draftTask = DraftTask(
            workspaceId: draft.workspaceId,
            projectId: draft.projectId,
            planningType: draft.planningType,
            title: "",
            description: "",
            updatedAt: Date()
        )
        return task
    }

    @discardableResult
    public static func removeWorkspace(id workspaceId: String, in board: inout BoardData) -> Bool {
        guard board.workspaces.contains(where: { $0.id == workspaceId }) else {
            return false
        }

        let removedProjectIds = Set(board.projects.filter { $0.workspaceId == workspaceId }.map(\.id))
        let removedTaskIds = Set(board.tasks.filter { $0.workspaceId == workspaceId || removedProjectIds.contains($0.projectId) }.map(\.id))
        board.tasks.removeAll { $0.workspaceId == workspaceId || removedProjectIds.contains($0.projectId) }
        board.runs.removeAll { removedTaskIds.contains($0.taskId) }
        board.projects.removeAll { $0.workspaceId == workspaceId }
        board.workspaces.removeAll { $0.id == workspaceId }
        board.settings.selectedWorkspaceIds.removeAll { $0 == workspaceId }

        for index in board.workspaces.indices {
            board.workspaces[index].projectIds.removeAll { removedProjectIds.contains($0) }
        }

        let draftWorkspaceExists = board.workspaces.contains { $0.id == board.draftTask.workspaceId }
        let draftProjectExists = board.projects.contains { $0.id == board.draftTask.projectId }
        if !draftWorkspaceExists || !draftProjectExists {
            let nextWorkspace = board.workspaces.first
            board.draftTask.workspaceId = nextWorkspace?.id ?? ""
            board.draftTask.projectId = nextWorkspace.flatMap { workspace in
                board.projects.first { $0.workspaceId == workspace.id }?.id
            } ?? ""
            board.draftTask.updatedAt = Date()
        }

        return true
    }

    @discardableResult
    public static func removeBacklogTask(id taskId: String, in board: inout BoardData) -> Bool {
        guard let index = board.tasks.firstIndex(where: { $0.id == taskId }),
              board.tasks[index].columnId == BoardColumn.intake.id else {
            return false
        }

        board.tasks.remove(at: index)
        return true
    }

    @discardableResult
    public static func mergeTaskMetatag(id taskId: String, values: [String: String], in board: inout BoardData) -> Bool {
        guard let index = board.tasks.firstIndex(where: { $0.id == taskId }) else {
            return false
        }

        var didChange = false
        for (key, value) in values {
            let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanKey.isEmpty, !cleanValue.isEmpty else { continue }
            if board.tasks[index].metatag[cleanKey] != cleanValue {
                board.tasks[index].metatag[cleanKey] = cleanValue
                didChange = true
            }
        }

        if didChange {
            board.tasks[index].updatedAt = Date()
        }
        return true
    }

    @discardableResult
    public static func updateTaskDefinition(
        id taskId: String,
        title: String,
        description: String,
        workspaceId: String,
        projectId: String,
        planningType: TaskPlanningType? = nil,
        in board: inout BoardData
    ) -> Bool {
        guard let index = board.tasks.firstIndex(where: { $0.id == taskId }) else {
            return false
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            return false
        }

        let isBacklogTask = board.tasks[index].columnId == BoardColumn.intake.id
        if isBacklogTask {
            guard !cleanDescription.isEmpty else {
                return false
            }
            guard board.workspaces.contains(where: { $0.id == workspaceId }),
                  board.projects.contains(where: { $0.id == projectId && $0.workspaceId == workspaceId }) else {
                return false
            }
        }

        board.tasks[index].title = cleanTitle
        if isBacklogTask {
            board.tasks[index].description = cleanDescription
            board.tasks[index].workspaceId = workspaceId
            board.tasks[index].projectId = projectId
            if let planningType {
                board.tasks[index].planningType = planningType
            }
        }

        board.tasks[index].updatedAt = Date()
        return true
    }

    @discardableResult
    public static func moveTask(
        id taskId: String,
        to column: BoardColumn,
        in board: inout BoardData,
        at timestamp: Date = Date()
    ) -> TaskRun? {
        guard let taskIndex = board.tasks.firstIndex(where: { $0.id == taskId }) else {
            return nil
        }

        board.tasks[taskIndex].columnId = column.id
        board.tasks[taskIndex].updatedAt = timestamp

        guard column.id != BoardColumn.intake.id else {
            board.tasks[taskIndex].metatag.removeAll()
            board.runs.removeAll { $0.taskId == taskId }
            return nil
        }

        let contract = PipelineStageContract.contract(for: column)
        let runId = "run-\(taskId)"
        let status = status(for: column)
        let runIndex: Int

        if let existingIndex = board.runs.firstIndex(where: { $0.taskId == taskId }) {
            runIndex = existingIndex
            board.runs[runIndex].currentColumnId = column.id
            board.runs[runIndex].status = status
            board.runs[runIndex].updatedAt = timestamp
        } else {
            board.runs.append(TaskRun(
                id: runId,
                taskId: taskId,
                currentColumnId: column.id,
                status: status,
                startedAt: timestamp,
                updatedAt: timestamp
            ))
            runIndex = board.runs.count - 1
        }

        let stageEvent = PipelineEvent(
            id: "\(runId)-\(column.id)-entry-\(UUID().uuidString)",
            taskId: taskId,
            runId: board.runs[runIndex].id,
            columnId: column.id,
            timestamp: timestamp,
            level: .info,
            message: "Entered \(column.name)"
        )
        board.runs[runIndex].events.append(stageEvent)

        if let tool = contract.tools.first {
            let toolEvent = PipelineEvent(
                id: "\(runId)-\(column.id)-tool-\(UUID().uuidString)",
                taskId: taskId,
                runId: board.runs[runIndex].id,
                columnId: column.id,
                timestamp: timestamp,
                level: .run,
                tool: tool,
                message: contract.entryMessage
            )
            board.runs[runIndex].events.append(toolEvent)
        }
        trimRunEvents(at: runIndex, in: &board)

        board.tasks[taskIndex].metatag["stage"] = column.name
        board.tasks[taskIndex].metatag["status"] = status.rawValue
        board.tasks[taskIndex].metatag["tools"] = contract.tools.joined(separator: ", ")
        board.tasks[taskIndex].metatag["required_output"] = contract.requiredOutput

        return board.runs[runIndex]
    }

    @discardableResult
    public static func appendPipelineEvent(
        taskId: String,
        columnId: String,
        level: PipelineEventLevel,
        tool: String? = nil,
        message: String,
        in board: inout BoardData,
        at timestamp: Date = Date()
    ) -> PipelineEvent? {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let runId = "run-\(taskId)"
        let runIndex: Int
        if let existingIndex = board.runs.firstIndex(where: { $0.taskId == taskId }) {
            runIndex = existingIndex
            board.runs[runIndex].updatedAt = timestamp
        } else {
            board.runs.append(TaskRun(
                id: runId,
                taskId: taskId,
                currentColumnId: columnId,
                status: .running,
                startedAt: timestamp,
                updatedAt: timestamp
            ))
            runIndex = board.runs.count - 1
        }

        let event = PipelineEvent(
            id: "\(board.runs[runIndex].id)-event-\(UUID().uuidString)",
            taskId: taskId,
            runId: board.runs[runIndex].id,
            columnId: columnId,
            timestamp: timestamp,
            level: level,
            tool: tool,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        board.runs[runIndex].events.append(event)
        trimRunEvents(at: runIndex, in: &board)
        return event
    }

    @discardableResult
    public static func ensureAgentSession(
        taskId: String,
        columnId: String,
        toolId: String,
        toolDisplayName: String,
        resumeCommand: String,
        in board: inout BoardData,
        at timestamp: Date = Date()
    ) -> AgentSession? {
        let cleanToolId = toolId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToolDisplayName = toolDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanResumeCommand = resumeCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToolId.isEmpty,
              !cleanToolDisplayName.isEmpty,
              !cleanResumeCommand.isEmpty else {
            return nil
        }

        let runIndex = ensureRunIndex(
            taskId: taskId,
            columnId: columnId,
            status: .running,
            in: &board,
            at: timestamp
        )

        if let existing = board.runs[runIndex].agentSession {
            return existing
        }

        let session = AgentSession(
            toolId: cleanToolId,
            toolDisplayName: cleanToolDisplayName,
            resumeCommand: cleanResumeCommand,
            status: .running,
            startedAt: timestamp,
            updatedAt: timestamp
        )
        board.runs[runIndex].agentSession = session
        board.runs[runIndex].updatedAt = timestamp
        if let taskIndex = board.tasks.firstIndex(where: { $0.id == taskId }) {
            board.tasks[taskIndex].metatag["agent_session_id"] = session.id
            board.tasks[taskIndex].metatag["agent_tool"] = cleanToolDisplayName
            board.tasks[taskIndex].metatag["agent_session_status"] = session.status.rawValue
            board.tasks[taskIndex].updatedAt = timestamp
        }

        let event = PipelineEvent(
            id: "\(board.runs[runIndex].id)-session-\(UUID().uuidString)",
            taskId: taskId,
            runId: board.runs[runIndex].id,
            columnId: columnId,
            timestamp: timestamp,
            level: .system,
            tool: cleanToolDisplayName,
            message: "Agent session \(session.id) started"
        )
        board.runs[runIndex].events.append(event)
        trimRunEvents(at: runIndex, in: &board)
        return session
    }

    @discardableResult
    public static func updateAgentSessionExternalId(
        taskId: String,
        externalSessionId: String,
        resumeCommand: String,
        in board: inout BoardData,
        at timestamp: Date = Date()
    ) -> Bool {
        let cleanExternalSessionId = externalSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanResumeCommand = resumeCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanExternalSessionId.isEmpty,
              !cleanResumeCommand.isEmpty,
              let runIndex = board.runs.firstIndex(where: { $0.taskId == taskId }),
              var session = board.runs[runIndex].agentSession else {
            return false
        }
        guard cleanExternalSessionId != session.id else {
            return false
        }

        guard session.externalSessionId != cleanExternalSessionId || session.resumeCommand != cleanResumeCommand else {
            return true
        }

        session.externalSessionId = cleanExternalSessionId
        session.resumeCommand = cleanResumeCommand
        session.updatedAt = timestamp
        board.runs[runIndex].agentSession = session
        board.runs[runIndex].updatedAt = timestamp
        if let taskIndex = board.tasks.firstIndex(where: { $0.id == taskId }) {
            board.tasks[taskIndex].metatag["agent_external_session_id"] = cleanExternalSessionId
            board.tasks[taskIndex].metatag["agent_resume_command"] = cleanResumeCommand
            board.tasks[taskIndex].updatedAt = timestamp
        }

        let event = PipelineEvent(
            id: "\(board.runs[runIndex].id)-session-external-\(UUID().uuidString)",
            taskId: taskId,
            runId: board.runs[runIndex].id,
            columnId: board.runs[runIndex].currentColumnId,
            timestamp: timestamp,
            level: .system,
            tool: session.toolDisplayName,
            message: "External session id captured: \(cleanExternalSessionId)"
        )
        board.runs[runIndex].events.append(event)
        trimRunEvents(at: runIndex, in: &board)
        return true
    }

    @discardableResult
    public static func updateAgentSessionStatus(
        taskId: String,
        status: AgentSessionStatus,
        in board: inout BoardData,
        at timestamp: Date = Date()
    ) -> Bool {
        guard let runIndex = board.runs.firstIndex(where: { $0.taskId == taskId }),
              var session = board.runs[runIndex].agentSession else {
            return false
        }

        session.status = status
        session.updatedAt = timestamp
        board.runs[runIndex].agentSession = session
        board.runs[runIndex].updatedAt = timestamp
        if let taskIndex = board.tasks.firstIndex(where: { $0.id == taskId }) {
            board.tasks[taskIndex].metatag["agent_session_status"] = status.rawValue
            board.tasks[taskIndex].updatedAt = timestamp
        }
        return true
    }

    private static func status(for column: BoardColumn) -> TaskRunStatus {
        switch column.id {
        case BoardColumn.humanReview.id:
            .waitingForHuman
        case BoardColumn.done.id:
            .completed
        default:
            .running
        }
    }

    private static func ensureRunIndex(
        taskId: String,
        columnId: String,
        status: TaskRunStatus,
        in board: inout BoardData,
        at timestamp: Date
    ) -> Int {
        if let existingIndex = board.runs.firstIndex(where: { $0.taskId == taskId }) {
            board.runs[existingIndex].currentColumnId = columnId
            board.runs[existingIndex].status = status
            board.runs[existingIndex].updatedAt = timestamp
            return existingIndex
        }

        board.runs.append(TaskRun(
            id: "run-\(taskId)",
            taskId: taskId,
            currentColumnId: columnId,
            status: status,
            startedAt: timestamp,
            updatedAt: timestamp
        ))
        return board.runs.count - 1
    }

    @discardableResult
    public static func compactRunEvents(in board: inout BoardData) -> Bool {
        var didCompact = false
        for index in board.runs.indices {
            didCompact = trimRunEvents(at: index, in: &board) || didCompact
        }
        return didCompact
    }

    @discardableResult
    private static func trimRunEvents(at index: Int, in board: inout BoardData) -> Bool {
        guard board.runs.indices.contains(index),
              board.runs[index].events.count > maximumRetainedEventsPerRun else {
            return false
        }
        board.runs[index].events = Array(board.runs[index].events.suffix(maximumRetainedEventsPerRun))
        return true
    }
}

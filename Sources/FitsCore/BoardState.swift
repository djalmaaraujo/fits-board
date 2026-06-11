import Foundation

public enum BoardState {
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
            columnId: BoardColumn.intake.id
        )
        board.tasks.append(task)
        board.draftTask = DraftTask(
            workspaceId: draft.workspaceId,
            projectId: draft.projectId,
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
        board.tasks.removeAll { $0.workspaceId == workspaceId || removedProjectIds.contains($0.projectId) }
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
    public static func updateTaskDefinition(
        id taskId: String,
        title: String,
        description: String,
        workspaceId: String,
        projectId: String,
        in board: inout BoardData
    ) -> Bool {
        guard let index = board.tasks.firstIndex(where: { $0.id == taskId }) else {
            return false
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanDescription.isEmpty else {
            return false
        }

        let isBacklogTask = board.tasks[index].columnId == BoardColumn.intake.id
        if isBacklogTask {
            guard board.workspaces.contains(where: { $0.id == workspaceId }),
                  board.projects.contains(where: { $0.id == projectId && $0.workspaceId == workspaceId }) else {
                return false
            }
        }

        board.tasks[index].title = cleanTitle
        board.tasks[index].description = cleanDescription

        if isBacklogTask {
            board.tasks[index].workspaceId = workspaceId
            board.tasks[index].projectId = projectId
        }

        board.tasks[index].updatedAt = Date()
        return true
    }
}

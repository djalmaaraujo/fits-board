import Foundation
import FitsCore

@MainActor
final class AppModel: ObservableObject {
    enum Sheet: Identifiable {
        case workspace
        case project
        case task
        case taskDetail
        case preferences

        var id: String {
            switch self {
            case .workspace: "workspace"
            case .project: "project"
            case .task: "task"
            case .taskDetail: "taskDetail"
            case .preferences: "preferences"
            }
        }
    }

    @Published var board: BoardData
    @Published var detectedTools: [DetectedTool]
    @Published var selectedTaskId: String?
    @Published var editingTaskId: String?
    @Published var activeSheet: Sheet?
    @Published var terminalLines: [String]
    @Published var errorMessage: String?
    @Published var searchQuery: String = ""

    private let store: FitsStore

    init(store: FitsStore = FitsStore()) {
        self.store = store
        let loadedBoard: BoardData
        let initialError: String?
        do {
            loadedBoard = try store.load()
            initialError = nil
        } catch {
            loadedBoard = (try? BoardData.seeded()) ?? BoardData()
            initialError = error.localizedDescription
        }
        self.board = Self.boardWithReferenceWorkspaces(loadedBoard)
        self.selectedTaskId = loadedBoard.tasks.first?.id
        self.detectedTools = ToolDetection.detectInstalledTools()
        self.terminalLines = [
            "Fits agent terminal",
            "Detected tools are listed above. Interactive PTY handoff is delegated to fits-agent-host."
        ]
        self.errorMessage = initialError
        if self.board.workspaces.count != loadedBoard.workspaces.count {
            persist()
        }
    }

    var selectedWorkspaceIds: [String] {
        board.settings.selectedWorkspaceIds
    }

    var selectedTask: FitsTask? {
        guard let selectedTaskId else { return nil }
        return board.tasks.first { $0.id == selectedTaskId }
    }

    var editingTask: FitsTask? {
        guard let editingTaskId else { return nil }
        return board.tasks.first { $0.id == editingTaskId }
    }

    func filteredTasks(for column: BoardColumn) -> [FitsTask] {
        BoardState.filteredTasks(in: board, selectedWorkspaceIds: board.settings.selectedWorkspaceIds)
            .filter { task in
                let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !query.isEmpty else { return true }
                return task.title.lowercased().contains(query)
                    || task.description.lowercased().contains(query)
                    || workspaceName(task.workspaceId).lowercased().contains(query)
                    || projectName(task.projectId).lowercased().contains(query)
            }
            .filter { $0.columnId == column.id }
    }

    var visibleTasks: [FitsTask] {
        BoardState.filteredTasks(in: board, selectedWorkspaceIds: board.settings.selectedWorkspaceIds)
            .filter { task in
                let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !query.isEmpty else { return true }
                return task.title.lowercased().contains(query)
                    || task.description.lowercased().contains(query)
                    || workspaceName(task.workspaceId).lowercased().contains(query)
                    || projectName(task.projectId).lowercased().contains(query)
            }
    }

    func projects(for workspaceId: String) -> [FitsProject] {
        board.projects.filter { $0.workspaceId == workspaceId }
    }

    func workspaceName(_ id: String) -> String {
        board.workspaces.first { $0.id == id }?.displayName ?? id
    }

    func projectName(_ id: String) -> String {
        board.projects.first { $0.id == id }?.name ?? id
    }

    func toggleWorkspace(_ id: String) {
        if board.settings.selectedWorkspaceIds.contains(id) {
            board.settings.selectedWorkspaceIds.removeAll { $0 == id }
        } else {
            board.settings.selectedWorkspaceIds.append(id)
        }
        persist()
    }

    func showAllWorkspaces() {
        board.settings.selectedWorkspaceIds = []
        persist()
    }

    func updateDraft(workspaceId: String? = nil, projectId: String? = nil, title: String? = nil, description: String? = nil) {
        if let workspaceId {
            board.draftTask.workspaceId = workspaceId
            if !projects(for: workspaceId).contains(where: { $0.id == board.draftTask.projectId }) {
                board.draftTask.projectId = projects(for: workspaceId).first?.id ?? ""
            }
        }
        if let projectId {
            board.draftTask.projectId = projectId
        }
        if let title {
            board.draftTask.title = title
        }
        if let description {
            board.draftTask.description = description
        }
        board.draftTask.updatedAt = Date()
        persist()
    }

    func promoteDraft() {
        do {
            let task = try BoardState.promoteDraftIfComplete(in: &board)
            if let task {
                selectedTaskId = task.id
            }
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addWorkspace(name: String, displayName: String, commitEmail: String) {
        let workspace = FitsWorkspace(
            name: name,
            displayName: displayName,
            commitEmail: commitEmail,
            colorHex: nextWorkspaceColor()
        )
        board.workspaces.append(workspace)
        if board.draftTask.workspaceId.isEmpty {
            board.draftTask.workspaceId = workspace.id
        }
        persist()
    }

    func addProject(workspaceId: String, name: String, repositories: [FitsRepository]) {
        let cleanRepositories = repositories.filter {
            !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let project = FitsProject(workspaceId: workspaceId, name: name, repositories: cleanRepositories)
        board.projects.append(project)
        if let index = board.workspaces.firstIndex(where: { $0.id == workspaceId }) {
            board.workspaces[index].projectIds.append(project.id)
        }
        if board.draftTask.projectId.isEmpty {
            board.draftTask.workspaceId = workspaceId
            board.draftTask.projectId = project.id
        }
        persist()
    }

    func updateWorkspace(id: String, name: String, displayName: String, commitEmail: String) {
        guard let index = board.workspaces.firstIndex(where: { $0.id == id }) else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = commitEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        board.workspaces[index].name = cleanName
        board.workspaces[index].displayName = cleanDisplayName.isEmpty ? cleanName : cleanDisplayName
        board.workspaces[index].commitEmail = cleanEmail
        persist()
    }

    func removeWorkspace(id: String) {
        let selectedTaskWillBeRemoved = selectedTask.map { $0.workspaceId == id } ?? false
        guard BoardState.removeWorkspace(id: id, in: &board) else { return }
        if selectedTaskWillBeRemoved || selectedTask == nil {
            selectedTaskId = board.tasks.first?.id
        }
        persist()
    }

    func addTask(title: String, description: String, workspaceId: String, projectId: String) {
        do {
            let task = try FitsTask(
                title: title,
                description: description,
                workspaceId: workspaceId,
                projectId: projectId
            )
            board.tasks.append(task)
            selectedTaskId = task.id
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openTaskEditor(_ task: FitsTask) {
        selectedTaskId = task.id
        editingTaskId = task.id
        activeSheet = .taskDetail
    }

    func updateTask(id: String, title: String, description: String, workspaceId: String, projectId: String) {
        if BoardState.updateTaskDefinition(
            id: id,
            title: title,
            description: description,
            workspaceId: workspaceId,
            projectId: projectId,
            in: &board
        ) {
            persist()
        }
    }

    func moveTask(_ task: FitsTask, to column: BoardColumn) {
        guard let index = board.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        board.tasks[index].columnId = column.id
        board.tasks[index].updatedAt = Date()
        persist()
    }

    func presentTaskSheet() {
        activeSheet = .task
    }

    func refreshTools() {
        detectedTools = ToolDetection.detectInstalledTools()
    }

    func isToolEnabled(_ toolId: String) -> Bool {
        board.settings.enabledToolIds.contains(toolId)
    }

    func setTool(_ tool: DetectedTool, enabled: Bool) {
        if enabled {
            guard tool.status == .installed else { return }
            if !board.settings.enabledToolIds.contains(tool.id) {
                board.settings.enabledToolIds.append(tool.id)
            }
            board.settings.preferredAgent = board.settings.preferredAgent ?? tool.id
        } else {
            board.settings.enabledToolIds.removeAll { $0 == tool.id }
            if board.settings.preferredAgent == tool.id {
                board.settings.preferredAgent = board.settings.enabledToolIds.first
            }
        }
        persist()
    }

    func startAgent(_ tool: DetectedTool) {
        guard tool.status == .installed, let path = tool.path else {
            terminalLines.append("\(tool.displayName) is not installed.")
            return
        }
        terminalLines.append("$ \(path)")
        terminalLines.append("Ready to start interactive session through fits-agent-host.")
    }

    private func persist() {
        do {
            try store.save(board)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func nextWorkspaceColor() -> String {
        let colors = ["#2563eb", "#22c55e", "#f97316", "#a855f7", "#06b6d4", "#e11d48"]
        return colors[board.workspaces.count % colors.count]
    }

    private static func boardWithReferenceWorkspaces(_ input: BoardData) -> BoardData {
        var board = input
        let desired: [(String, String, String, String)] = [
            ("linkana", "Linkana", "cooper@linkana.com", "#2f8cff"),
            ("galo", "Galo", "cooper@galo.com", "#ff6b45"),
            ("a8c", "A8C", "cooper@automattic.com", "#4db5ff"),
            ("engage", "Engage", "cooper@engage.com", "#9b6cff"),
            ("radiar", "Radiar", "cooper@radiar.com", "#35cfa4")
        ]

        for item in desired where !board.workspaces.contains(where: { $0.name == item.0 }) {
            let workspace = FitsWorkspace(
                id: "ws-\(item.0)",
                name: item.0,
                displayName: item.1,
                commitEmail: item.2,
                colorHex: item.3
            )
            board.workspaces.append(workspace)
        }
        return board
    }

}

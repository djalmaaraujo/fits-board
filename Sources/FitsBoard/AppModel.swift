import AppKit
import Foundation
import FitsCore

struct AppToast: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String?
    let systemImage: String
}

enum TaskInspectorTab: String, CaseIterable, Identifiable {
    case details
    case logs
    case agents
    case prompts
    case meta
    case repos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .details: "Details"
        case .logs: "Logs"
        case .agents: "Agents"
        case .prompts: "Prompts"
        case .meta: "Meta"
        case .repos: "Repos"
        }
    }

    var systemImage: String {
        switch self {
        case .details: "square.and.pencil"
        case .logs: "terminal"
        case .agents: "cpu"
        case .prompts: "sparkles"
        case .meta: "slider.horizontal.3"
        case .repos: "arrow.triangle.branch"
        }
    }
}

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
    @Published var inspectorTaskId: String?
    @Published var inspectorTab: TaskInspectorTab = .details
    @Published var activeSheet: Sheet?
    @Published var terminalLines: [String]
    @Published var errorMessage: String?
    @Published var searchQuery: String = ""
    @Published var toast: AppToast?
    @Published var runningTaskIds: Set<String> = []

    private let store: FitsStore
    private var toastDismissTask: Task<Void, Never>?
    private var agentProcesses: [String: RunningAgentProcess] = [:]
    private var agentOutputAccumulators: [AgentOutputAccumulatorKey: AgentOutputAccumulator] = [:]
    private var agentPromptEchoLines: [String: Set<String>] = [:]
    private var pendingAgentLogEvents: [String: [PendingAgentLogEvent]] = [:]
    private var pendingAgentLogFlushTasks: [String: Task<Void, Never>] = [:]

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
        if self.board != loadedBoard {
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

    var inspectorTask: FitsTask? {
        guard let inspectorTaskId else { return nil }
        return board.tasks.first { $0.id == inspectorTaskId }
    }

    var inspectorRun: TaskRun? {
        guard let inspectorTaskId else { return nil }
        return board.runs.first { $0.taskId == inspectorTaskId }
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

    func updateDraft(
        workspaceId: String? = nil,
        projectId: String? = nil,
        planningType: TaskPlanningType? = nil,
        title: String? = nil,
        description: String? = nil
    ) {
        if let workspaceId {
            board.draftTask.workspaceId = workspaceId
            if !projects(for: workspaceId).contains(where: { $0.id == board.draftTask.projectId }) {
                board.draftTask.projectId = projects(for: workspaceId).first?.id ?? ""
            }
        }
        if let projectId {
            board.draftTask.projectId = projectId
        }
        if let planningType {
            board.draftTask.planningType = planningType
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
                if persist() {
                    showToast("Task added to Backlog", detail: task.title, systemImage: "doc.badge.plus")
                }
                return
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
        if persist() {
            showToast("Workspace added", detail: workspace.displayName, systemImage: "square.stack.3d.up.badge.plus")
        }
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
        if persist() {
            showToast("Project added", detail: project.name, systemImage: "folder.badge.plus")
        }
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
        if persist() {
            showToast("Workspace saved", detail: board.workspaces[index].displayName, systemImage: "checkmark.circle")
        }
    }

    func removeWorkspace(id: String) {
        let removedName = board.workspaces.first { $0.id == id }?.displayName ?? "Workspace"
        let selectedTaskWillBeRemoved = selectedTask.map { $0.workspaceId == id } ?? false
        let inspectorTaskWillBeRemoved = inspectorTask.map { $0.workspaceId == id } ?? false
        guard BoardState.removeWorkspace(id: id, in: &board) else { return }
        if selectedTaskWillBeRemoved || selectedTask == nil {
            selectedTaskId = board.tasks.first?.id
        }
        if inspectorTaskWillBeRemoved {
            inspectorTaskId = nil
        }
        if persist() {
            showToast("Workspace removed", detail: removedName, systemImage: "trash")
        }
    }

    func addTask(
        title: String,
        description: String,
        workspaceId: String,
        projectId: String,
        planningType: TaskPlanningType = .fast
    ) {
        do {
            let task = try FitsTask(
                title: title,
                description: description,
                workspaceId: workspaceId,
                projectId: projectId,
                planningType: planningType
            )
            board.tasks.append(task)
            selectedTaskId = task.id
            if persist() {
                showToast("Task added to Backlog", detail: task.title, systemImage: "doc.badge.plus")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openTaskEditor(_ task: FitsTask) {
        selectedTaskId = task.id
        if task.columnId == BoardColumn.intake.id {
            editingTaskId = task.id
            activeSheet = .taskDetail
        } else {
            openTaskInspector(task, preferredTab: .details)
        }
    }

    func openTaskInspector(_ task: FitsTask, preferredTab: TaskInspectorTab = .details) {
        selectedTaskId = task.id
        inspectorTaskId = task.id
        inspectorTab = preferredTab
    }

    func closeTaskInspector() {
        inspectorTaskId = nil
    }

    func updateTask(
        id: String,
        title: String,
        description: String,
        workspaceId: String,
        projectId: String,
        planningType: TaskPlanningType? = nil
    ) {
        if BoardState.updateTaskDefinition(
            id: id,
            title: title,
            description: description,
            workspaceId: workspaceId,
            projectId: projectId,
            planningType: planningType,
            in: &board
        ) {
            persist()
        }
    }

    @discardableResult
    func deleteBacklogTask(id: String) -> Bool {
        let removedTitle = board.tasks.first { $0.id == id }?.title ?? "Task"
        guard BoardState.removeBacklogTask(id: id, in: &board) else {
            return false
        }
        if selectedTaskId == id {
            selectedTaskId = board.tasks.first?.id
        }
        if editingTaskId == id {
            editingTaskId = nil
        }
        if inspectorTaskId == id {
            inspectorTaskId = nil
        }
        if persist() {
            showToast("Task deleted", detail: removedTitle, systemImage: "trash")
        }
        return true
    }

    func stopTaskPipeline(id: String) {
        guard board.tasks.contains(where: { $0.id == id }) else { return }
        showToast("Tarefa parada na pipeline", detail: nil, systemImage: "stop.circle")
    }

    func mergeTaskMetatag(id: String, values: [String: String]) {
        if BoardState.mergeTaskMetatag(id: id, values: values, in: &board) {
            persist()
        }
    }

    func moveTask(_ task: FitsTask, to column: BoardColumn) {
        if column.id == BoardColumn.intake.id {
            resetRunningAgentIfNeeded(taskId: task.id)
        }
        guard BoardState.moveTask(id: task.id, to: column, in: &board) != nil || column.id == BoardColumn.intake.id else { return }
        if column.id == BoardColumn.intake.id,
           let resetTask = board.tasks.first(where: { $0.id == task.id }) {
            do {
                try store.clearExecutionArtifacts(for: resetTask, in: board)
            } catch {
                errorMessage = "Could not clear old execution artifacts: \(error.localizedDescription)"
            }
        }
        if persist() {
            showToast("Task moved", detail: "\(task.title) -> \(column.name)", systemImage: "arrow.right.circle")
        }
        if let updatedTask = board.tasks.first(where: { $0.id == task.id }), column.id != BoardColumn.intake.id {
            openTaskInspector(updatedTask, preferredTab: .details)
            if shouldAutoStart(column) {
                startCurrentStage(for: updatedTask)
            }
        }
    }

    func presentTaskSheet() {
        activeSheet = .task
    }

    func refreshTools() {
        detectedTools = ToolDetection.detectInstalledTools()
        showToast("Agents refreshed", detail: "\(detectedTools.filter { $0.status == .installed }.count) installed", systemImage: "arrow.clockwise")
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
        if persist() {
            showToast(enabled ? "Agent enabled" : "Agent disabled", detail: tool.displayName, systemImage: enabled ? "checkmark.circle" : "minus.circle")
        }
    }

    func startAgent(_ tool: DetectedTool) {
        guard tool.status == .installed, let path = tool.path else {
            terminalLines.append("\(tool.displayName) is not installed.")
            return
        }
        terminalLines.append("$ \(path)")
        terminalLines.append("Ready to start interactive session through fits-agent-host.")
        showToast("Agent ready", detail: tool.displayName, systemImage: "terminal")
    }

    func startCurrentStage(for task: FitsTask) {
        launchCurrentStage(for: task, resume: false)
    }

    func resumeCurrentStage(for task: FitsTask) {
        launchCurrentStage(for: task, resume: true)
    }

    private func launchCurrentStage(for task: FitsTask, resume: Bool) {
        guard !runningTaskIds.contains(task.id) else { return }
        guard let column = board.columns.first(where: { $0.id == task.columnId }),
              column.id != BoardColumn.intake.id else {
            showToast("Cannot start", detail: "Backlog tasks need intake first", systemImage: "exclamationmark.triangle")
            return
        }
        guard let taskDirectory = store.taskArtifactDirectory(for: task, in: board) else {
            errorMessage = "Could not resolve task artifact directory."
            return
        }
        guard let repositoryPath = repositoryPath(for: task) else {
            let projectName = projectName(task.projectId)
            let message = "Project \(projectName) needs at least one local repository."
            _ = BoardState.updateAgentSessionStatus(taskId: task.id, status: .failed, in: &board)
            appendEvent(taskId: task.id, columnId: column.id, level: .error, tool: "Fits Board", message: message)
            showToast("Missing repository", detail: projectName, systemImage: "folder.badge.questionmark")
            return
        }
        let writableDirectories = writableDirectories(for: task, taskDirectory: taskDirectory)
        let missingDirectories = AgentCommandBuilder.missingRequiredDirectories(
            repositoryPath: repositoryPath,
            writableDirectories: writableDirectories,
            directoryExists: { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
        )
        guard missingDirectories.isEmpty else {
            let message = "Missing required local path: \(missingDirectories.joined(separator: ", "))"
            _ = BoardState.updateAgentSessionStatus(taskId: task.id, status: .failed, in: &board)
            appendEvent(taskId: task.id, columnId: column.id, level: .error, tool: "Fits Board", message: message)
            showToast("Missing local path", detail: missingDirectories.first, systemImage: "folder.badge.questionmark")
            return
        }
        guard let agent = agentInvocation(
            for: task,
            column: column,
            repositoryPath: repositoryPath,
            writableDirectories: writableDirectories
        ) else {
            showToast("No local agent", detail: "Enable Codex or Claude in Preferences", systemImage: "terminal")
            return
        }
        guard let helperURL = fitsAgentHostURL() else {
            errorMessage = "fits-agent-host is missing from the app bundle. Run ./scripts/package_app.sh again."
            return
        }
        let doneSentinel = stageCompletionSentinel(for: task, column: column)
        let doneFile = stageCompletionFile(for: taskDirectory, column: column)
        let prompt = resume
            ? stageResumePrompt(for: task, column: column, doneSentinel: doneSentinel, doneFile: doneFile)
            : stagePrompt(for: task, column: column, doneSentinel: doneSentinel, doneFile: doneFile)
        let promptFile: URL
        do {
            promptFile = try writeStagePrompt(
                prompt,
                taskDirectory: taskDirectory,
                column: column,
                resume: resume
            )
        } catch {
            appendEvent(taskId: task.id, columnId: column.id, level: .error, tool: "Fits Board", message: error.localizedDescription)
            errorMessage = error.localizedDescription
            return
        }

        let session = BoardState.ensureAgentSession(
            taskId: task.id,
            columnId: column.id,
            toolId: agent.id,
            toolDisplayName: agent.displayName,
            resumeCommand: fallbackResumeCommand(for: agent.id),
            in: &board
        )
        _ = BoardState.updateAgentSessionStatus(taskId: task.id, status: .running, in: &board)
        agentPromptEchoLines[task.id] = Self.promptEchoLines(for: prompt)
        persist()

        let launchArguments = launchArguments(
            for: agent,
            resume: resume,
            repositoryPath: repositoryPath,
            writableDirectories: writableDirectories,
            session: session,
            prompt: prompt
        )
        appendEvent(
            taskId: task.id,
            columnId: column.id,
            level: .run,
            tool: "fits-agent-host",
            message: "\(resume ? "Resuming" : "Starting") \(agent.displayName)"
        )
        runningTaskIds.insert(task.id)

        let process = Process()
        process.executableURL = helperURL
        var helperArguments = [
            "pty",
            "--task-dir", taskDirectory.path,
            "--cwd", repositoryPath,
            "--done-sentinel", doneSentinel,
            "--done-file", doneFile.path,
            "--require-sentinel",
            "--",
            agent.id
        ]
        if shouldTypePromptThroughPTY(for: agent.id) {
            helperArguments.insert(contentsOf: ["--prompt-file", promptFile.path], at: 5)
        }
        process.arguments = helperArguments + launchArguments
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.appendAgentOutput(
                    taskId: task.id,
                    columnId: column.id,
                    agentId: agent.id,
                    agentDisplayName: agent.displayName,
                    stream: .stdout,
                    tool: "\(agent.displayName) stdout",
                    text: text
                )
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.appendAgentOutput(
                    taskId: task.id,
                    columnId: column.id,
                    agentId: agent.id,
                    agentDisplayName: agent.displayName,
                    stream: .stderr,
                    tool: "\(agent.displayName) stderr",
                    text: text
                )
            }
        }

        process.terminationHandler = { [weak self] process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                self?.finishAgentProcess(
                    taskId: task.id,
                    columnId: column.id,
                    agentId: agent.id,
                    agentName: agent.displayName,
                    status: process.terminationStatus
                )
            }
        }

        do {
            try process.run()
            agentProcesses[task.id] = RunningAgentProcess(process: process, inputPipe: inputPipe)
            showToast(resume ? "Agent resumed" : "Agent started", detail: agent.displayName, systemImage: "terminal")
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            runningTaskIds.remove(task.id)
            clearAgentOutputAccumulators(taskId: task.id)
            clearPendingAgentLogEvents(taskId: task.id)
            agentPromptEchoLines.removeValue(forKey: task.id)
            _ = BoardState.updateAgentSessionStatus(taskId: task.id, status: .failed, in: &board)
            appendEvent(taskId: task.id, columnId: column.id, level: .error, tool: "fits-agent-host", message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func stopCurrentStage(for task: FitsTask) {
        guard let running = agentProcesses[task.id] else {
            showToast("No running agent", detail: task.title, systemImage: "stop.circle")
            return
        }
        try? running.inputPipe.fileHandleForWriting.write(contentsOf: Data([0x1b]))
        running.process.terminate()
        _ = BoardState.updateAgentSessionStatus(taskId: task.id, status: .stopped, in: &board)
        appendEvent(taskId: task.id, columnId: task.columnId, level: .warn, tool: "fits-agent-host", message: "Stop requested by user")
    }

    private func resetRunningAgentIfNeeded(taskId: String) {
        guard let running = agentProcesses[taskId] else { return }
        try? running.inputPipe.fileHandleForWriting.write(contentsOf: Data([0x1b]))
        running.process.terminate()
        agentProcesses[taskId] = nil
        runningTaskIds.remove(taskId)
        clearAgentOutputAccumulators(taskId: taskId)
        clearPendingAgentLogEvents(taskId: taskId)
        agentPromptEchoLines.removeValue(forKey: taskId)
    }

    func dismissToast() {
        toastDismissTask?.cancel()
        toast = nil
    }

    func showCopiedLogsToast(for task: FitsTask) {
        showToast("Logs copied", detail: task.title, systemImage: "doc.on.doc")
    }

    func taskPromptFiles(for task: FitsTask) -> [TaskArtifactTextFile] {
        (try? store.taskPromptFiles(for: task, in: board)) ?? []
    }

    func taskGeneratedArtifacts(for task: FitsTask) -> [TaskArtifactTextFile] {
        (try? store.taskGeneratedArtifacts(for: task, in: board)) ?? []
    }

    func taskTerminalLog(for task: FitsTask) -> String? {
        try? store.taskTerminalLog(for: task, in: board)
    }

    func taskTerminalLogTail(for task: FitsTask, maximumLines: Int = 200) -> TaskLogTail? {
        try? store.taskTerminalLogTail(for: task, in: board, maximumLines: maximumLines)
    }

    func openTaskTerminalLog(for task: FitsTask) {
        guard let url = store.taskTerminalLogURL(for: task, in: board) else {
            showToast("No log file yet", detail: task.title, systemImage: "doc.text.magnifyingglass")
            return
        }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try store.save(board)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func showToast(_ title: String, detail: String? = nil, systemImage: String) {
        let toast = AppToast(title: title, detail: detail, systemImage: systemImage)
        self.toast = toast
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.toast?.id == toast.id {
                    self?.toast = nil
                }
            }
        }
    }

    private func nextWorkspaceColor() -> String {
        let colors = ["#2563eb", "#22c55e", "#f97316", "#a855f7", "#06b6d4", "#e11d48"]
        return colors[board.workspaces.count % colors.count]
    }

    private struct AgentInvocation {
        let id: String
        let displayName: String
        let arguments: [String]
    }

    private struct RunningAgentProcess {
        let process: Process
        let inputPipe: Pipe
    }

    private struct AgentOutputAccumulatorKey: Hashable {
        let taskId: String
        let stream: AgentOutputStream
    }

    private struct PendingAgentLogEvent {
        let columnId: String
        let level: PipelineEventLevel
        let tool: String
        let message: String
    }

    private func agentInvocation(
        for task: FitsTask,
        column: BoardColumn,
        repositoryPath: String,
        writableDirectories: [String]
    ) -> AgentInvocation? {
        if detectedTools.contains(where: { $0.id == "codex" && $0.status == .installed }) {
            return AgentInvocation(
                id: "codex",
                displayName: "Codex CLI",
                arguments: AgentCommandBuilder.codexStartArguments(
                    repositoryPath: repositoryPath,
                    writableDirectories: writableDirectories
                )
            )
        }
        if detectedTools.contains(where: { $0.id == "claude" && $0.status == .installed }) {
            return AgentInvocation(
                id: "claude",
                displayName: "Claude Code",
                arguments: AgentCommandBuilder.claudeStartArguments()
            )
        }
        return nil
    }

    private func repositoryPath(for task: FitsTask) -> String? {
        board.projects
            .first { $0.id == task.projectId }?
            .repositories
            .first?
            .path
            .replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    private func writableDirectories(for task: FitsTask, taskDirectory: URL) -> [String] {
        var directories = [taskDirectory.path]
        let combinedText = "\(task.title)\n\(task.description)".lowercased()
        if combinedText.contains("~/desktop") || combinedText.contains("/desktop") || combinedText.contains("desktop") {
            directories.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true).path)
        }
        return directories
    }

    private static func fallbackResumeCommand(for agentId: String) -> String {
        switch agentId {
        case "codex":
            "codex resume --last"
        case "claude":
            "claude --continue"
        default:
            "\(agentId) resume"
        }
    }

    private func fallbackResumeCommand(for agentId: String) -> String {
        Self.fallbackResumeCommand(for: agentId)
    }

    private func resumeCommand(for agentId: String, externalSessionId: String) -> String {
        switch agentId {
        case "codex":
            "codex resume \(externalSessionId)"
        case "claude":
            "claude --resume \(externalSessionId)"
        default:
            "\(agentId) resume \(externalSessionId)"
        }
    }

    private func launchArguments(
        for agent: AgentInvocation,
        resume: Bool,
        repositoryPath: String,
        writableDirectories: [String],
        session: AgentSession?,
        prompt: String
    ) -> [String] {
        switch agent.id {
        case "codex":
            if resume {
                return AgentCommandBuilder.codexResumeArguments(
                    repositoryPath: repositoryPath,
                    writableDirectories: writableDirectories,
                    externalSessionId: session?.externalSessionId,
                    prompt: prompt
                )
            }
            return AgentCommandBuilder.codexStartArguments(
                repositoryPath: repositoryPath,
                writableDirectories: writableDirectories,
                prompt: prompt
            )
        case "claude":
            if resume {
                return AgentCommandBuilder.claudeResumeArguments(externalSessionId: session?.externalSessionId, prompt: "")
            }
            return agent.arguments
        default:
            return agent.arguments
        }
    }

    private func shouldTypePromptThroughPTY(for agentId: String) -> Bool {
        agentId != "codex"
    }

    private func writeStagePrompt(_ prompt: String, taskDirectory: URL, column: BoardColumn, resume: Bool) throws -> URL {
        try FileManager.default.createDirectory(at: taskDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: taskDirectory.appendingPathComponent("artifacts", isDirectory: true),
            withIntermediateDirectories: true
        )
        let safeStage = column.id
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let fileName = resume ? "prompt-\(safeStage)-resume.md" : "prompt-\(safeStage).md"
        let promptURL = taskDirectory.appendingPathComponent(fileName)
        try prompt.write(to: promptURL, atomically: true, encoding: .utf8)
        return promptURL
    }

    private func stageCompletionSentinel(for task: FitsTask, column: BoardColumn) -> String {
        let raw = "\(task.id)_\(column.id)"
        let safe = raw
            .uppercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "_"
            }
        return "FITS_STAGE_DONE_\(String(safe))"
    }

    private func stageCompletionFile(for taskDirectory: URL, column: BoardColumn) -> URL {
        let safeStage = column.id
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return taskDirectory.appendingPathComponent("stage-done-\(safeStage).txt")
    }

    private func stagePrompt(for task: FitsTask, column: BoardColumn, doneSentinel: String, doneFile: URL) -> String {
        let contract = PipelineStageContract.contract(for: column)
        let project = board.projects.first { $0.id == task.projectId }
        let repository = project?.repositories.first
        return """
        You are running inside Fits Board for one pipeline stage.

        Stage: \(column.name)
        Required output: \(contract.requiredOutput)
        Allowed tools for this stage: \(contract.tools.joined(separator: ", "))

        Stage behavior:
        \(PipelineStageInstructions.instructions(for: column))

        Task title:
        \(task.title)

        Task description:
        \(task.description)

        Repository:
        \(repository?.path ?? "No repository configured")

        Fits task artifact folder:
        \(doneFile.deletingLastPathComponent().path)

        Fits write-back contract:
        - To update task metadata visible in Fits, write a JSON object with string values to:
          \(doneFile.deletingLastPathComponent().appendingPathComponent("metatag.json").path)
        - Example:
          {"progress":"50%","agent_notes":"QA verified manually"}
        - To attach generated task artifacts, write files under:
          \(doneFile.deletingLastPathComponent().appendingPathComponent("artifacts", isDirectory: true).path)

        Rules:
        - Respect this stage only.
        - Use GitHub only when the task explicitly requires it.
        - Write progress and final notes clearly to stdout.
        - If you change files, explain exactly what changed.
        - Complete only this stage's required output. Do not skip ahead to later pipeline stages.
        - Before reporting success, verify this stage's required output is satisfied.
        - For Planning, do not execute the requested task work; planning context is the stage output.
        - For execution, QA, and review stages, compare the stage output against the original task objective according to the stage behavior.
        - After verification succeeds, write exactly this completion marker into this file:
          \(doneFile.path)
          \(doneSentinel)
        - Also print exactly this final completion marker on its own line:
          \(doneSentinel)
        - Do not write or print the completion marker if this stage failed or still needs human input from you.
        """
    }

    private func stageResumePrompt(for task: FitsTask, column: BoardColumn, doneSentinel: String, doneFile: URL) -> String {
        let contract = PipelineStageContract.contract(for: column)
        return """
        Resume this Fits Board pipeline stage.

        Stage: \(column.name)
        Task: \(task.title)
        Required output: \(contract.requiredOutput)

        Stage behavior:
        \(PipelineStageInstructions.instructions(for: column))

        Fits write-back contract:
        - To update task metadata visible in Fits, write a JSON object with string values to:
          \(doneFile.deletingLastPathComponent().appendingPathComponent("metatag.json").path)
        - To attach generated task artifacts, write files under:
          \(doneFile.deletingLastPathComponent().appendingPathComponent("artifacts", isDirectory: true).path)

        Continue from the existing session context. Respect this stage only and write progress to stdout.
        Complete only this stage's required output. Do not skip ahead to later pipeline stages.
        Before reporting success, verify this stage's required output is satisfied.
        For Planning, do not execute the requested task work; planning context is the stage output.
        For execution, QA, and review stages, compare the stage output against the original task objective according to the stage behavior.
        After verification succeeds, write exactly this completion marker into this file:
        \(doneFile.path)
        \(doneSentinel)
        Also print exactly this final completion marker on its own line:
        \(doneSentinel)
        Do not write or print the completion marker if this stage failed or still needs human input from you.
        """
    }

    private func fitsAgentHostURL() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("fits-agent-host"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let sourceBuild = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("cmd/fits-agent-host/fits-agent-host")
        if FileManager.default.isExecutableFile(atPath: sourceBuild.path) {
            return sourceBuild
        }
        return nil
    }

    private func appendAgentOutput(
        taskId: String,
        columnId: String,
        agentId: String,
        agentDisplayName: String,
        stream: AgentOutputStream,
        tool: String,
        text: String
    ) {
        let key = AgentOutputAccumulatorKey(taskId: taskId, stream: stream)
        var accumulator = agentOutputAccumulators[key] ?? AgentOutputAccumulator()
        let lines = accumulator.append(text)
        agentOutputAccumulators[key] = accumulator
        appendAgentOutputLines(
            lines,
            taskId: taskId,
            columnId: columnId,
            agentId: agentId,
            agentDisplayName: agentDisplayName,
            stream: stream,
            tool: tool
        )
    }

    private func flushAgentOutput(
        taskId: String,
        columnId: String,
        agentId: String,
        agentDisplayName: String
    ) {
        for stream in [AgentOutputStream.stdout, .stderr] {
            let key = AgentOutputAccumulatorKey(taskId: taskId, stream: stream)
            guard var accumulator = agentOutputAccumulators.removeValue(forKey: key) else { continue }
            appendAgentOutputLines(
                accumulator.flush(),
                taskId: taskId,
                columnId: columnId,
                agentId: agentId,
                agentDisplayName: agentDisplayName,
                stream: stream,
                tool: "\(agentDisplayName) \(stream.displayName)"
            )
        }
    }

    private func appendAgentOutputLines(
        _ lines: [String],
        taskId: String,
        columnId: String,
        agentId: String,
        agentDisplayName: String,
        stream: AgentOutputStream,
        tool: String
    ) {
        var pendingEvents: [PendingAgentLogEvent] = []
        for lineText in lines {
            let visibleLine = AgentLogClassifier.visibleText(from: lineText)
            guard !visibleLine.isEmpty else { continue }
            guard !shouldSuppressAgentOutputLine(taskId: taskId, agentId: agentId, line: visibleLine) else {
                continue
            }
            captureExternalSessionId(
                taskId: taskId,
                agentId: agentId,
                agentDisplayName: agentDisplayName,
                line: visibleLine
            )
            guard let level = AgentLogClassifier.classify(toolId: agentId, stream: stream, line: visibleLine) else {
                continue
            }
            pendingEvents.append(PendingAgentLogEvent(
                columnId: columnId,
                level: level,
                tool: tool,
                message: visibleLine
            ))
        }

        if !pendingEvents.isEmpty {
            queueAgentLogEvents(pendingEvents, taskId: taskId)
        }
    }

    private func queueAgentLogEvents(_ events: [PendingAgentLogEvent], taskId: String) {
        pendingAgentLogEvents[taskId, default: []].append(contentsOf: events)

        if pendingAgentLogEvents[taskId, default: []].count >= 160 {
            flushPendingAgentLogEvents(taskId: taskId)
            return
        }

        pendingAgentLogFlushTasks[taskId]?.cancel()
        pendingAgentLogFlushTasks[taskId] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.flushPendingAgentLogEvents(taskId: taskId)
            }
        }
    }

    private func flushPendingAgentLogEvents(taskId: String) {
        pendingAgentLogFlushTasks[taskId]?.cancel()
        pendingAgentLogFlushTasks[taskId] = nil

        guard let events = pendingAgentLogEvents.removeValue(forKey: taskId), !events.isEmpty else {
            return
        }

        var appendedEvents: [PipelineEvent] = []
        for event in events {
            if let appended = BoardState.appendPipelineEvent(
                taskId: taskId,
                columnId: event.columnId,
                level: event.level,
                tool: event.tool,
                message: event.message,
                in: &board
            ) {
                appendedEvents.append(appended)
            }
        }

        if !appendedEvents.isEmpty {
            appendEventsToLogFiles(appendedEvents, taskId: taskId)
            persist()
        }
    }

    private func shouldSuppressAgentOutputLine(taskId: String, agentId: String, line: String) -> Bool {
        guard agentId == "codex" else { return false }
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return agentPromptEchoLines[taskId]?.contains(normalized) == true
    }

    private func clearAgentOutputAccumulators(taskId: String) {
        let keys = agentOutputAccumulators.keys.filter { $0.taskId == taskId }
        for key in keys {
            agentOutputAccumulators.removeValue(forKey: key)
        }
    }

    private func clearPendingAgentLogEvents(taskId: String) {
        pendingAgentLogFlushTasks[taskId]?.cancel()
        pendingAgentLogFlushTasks[taskId] = nil
        pendingAgentLogEvents.removeValue(forKey: taskId)
    }

    private static func promptEchoLines(for prompt: String) -> Set<String> {
        Set(
            prompt
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func finishAgentProcess(taskId: String, columnId: String, agentId: String, agentName: String, status: Int32) {
        flushAgentOutput(taskId: taskId, columnId: columnId, agentId: agentId, agentDisplayName: agentName)
        flushPendingAgentLogEvents(taskId: taskId)
        importAgentWritableTaskState(taskId: taskId, columnId: columnId)
        agentPromptEchoLines.removeValue(forKey: taskId)
        agentProcesses[taskId] = nil
        runningTaskIds.remove(taskId)
        let wasStopped = board.runs.first { $0.taskId == taskId }?.agentSession?.status == .stopped
        if status == 0 {
            _ = BoardState.updateAgentSessionStatus(taskId: taskId, status: .completed, in: &board)
            appendEvent(taskId: taskId, columnId: columnId, level: .ok, tool: agentName, message: "Process exited successfully")
            showToast("Agent finished", detail: agentName, systemImage: "checkmark.circle")
            advanceTaskAfterSuccessfulStage(taskId: taskId, completedColumnId: columnId)
        } else if wasStopped {
            appendEvent(taskId: taskId, columnId: columnId, level: .warn, tool: agentName, message: "Process stopped")
            showToast("Agent stopped", detail: agentName, systemImage: "stop.circle")
        } else {
            _ = BoardState.updateAgentSessionStatus(taskId: taskId, status: .failed, in: &board)
            appendEvent(taskId: taskId, columnId: columnId, level: .error, tool: agentName, message: "Process exited with status \(status)")
            showToast("Agent failed", detail: "\(agentName) status \(status)", systemImage: "exclamationmark.triangle")
        }
    }

    private func importAgentWritableTaskState(taskId: String, columnId: String) {
        guard let task = board.tasks.first(where: { $0.id == taskId }) else { return }

        do {
            let values = try store.taskMetatagUpdate(for: task, in: board)
            if !values.isEmpty, BoardState.mergeTaskMetatag(id: taskId, values: values, in: &board) {
                appendEvent(
                    taskId: taskId,
                    columnId: columnId,
                    level: .system,
                    tool: "Fits Board",
                    message: "Imported task metatag updates: \(values.keys.sorted().joined(separator: ", "))"
                )
            }
        } catch {
            appendEvent(
                taskId: taskId,
                columnId: columnId,
                level: .warn,
                tool: "Fits Board",
                message: "Could not import metatag.json: \(error.localizedDescription)"
            )
        }

        if let artifacts = try? store.taskGeneratedArtifacts(for: task, in: board), !artifacts.isEmpty {
            appendEvent(
                taskId: taskId,
                columnId: columnId,
                level: .system,
                tool: "Fits Board",
                message: "Generated artifacts: \(artifacts.map(\.name).joined(separator: ", "))"
            )
        }
    }

    private func advanceTaskAfterSuccessfulStage(taskId: String, completedColumnId: String) {
        guard let task = board.tasks.first(where: { $0.id == taskId }),
              task.columnId == completedColumnId,
              let nextColumn = BoardState.nextColumn(after: completedColumnId, in: board) else {
            return
        }

        guard BoardState.moveTask(id: taskId, to: nextColumn, in: &board) != nil else {
            return
        }
        persist()

        guard let updatedTask = board.tasks.first(where: { $0.id == taskId }) else {
            return
        }
        openTaskInspector(updatedTask, preferredTab: .details)

        if shouldAutoStart(nextColumn) {
            appendEvent(
                taskId: taskId,
                columnId: nextColumn.id,
                level: .system,
                tool: "Fits Board",
                message: "Auto-starting \(nextColumn.name)"
            )
            startCurrentStage(for: updatedTask)
        } else if nextColumn.id == BoardColumn.humanReview.id {
            appendEvent(
                taskId: taskId,
                columnId: nextColumn.id,
                level: .system,
                tool: "Fits Board",
                message: "Waiting for human review"
            )
            showToast("Waiting for human review", detail: updatedTask.title, systemImage: "person.2")
        }
    }

    private func captureExternalSessionId(
        taskId: String,
        agentId: String,
        agentDisplayName: String,
        line: String
    ) {
        guard let externalSessionId = Self.agentSessionID(in: line) else { return }
        let currentExternalId = board.runs.first { $0.taskId == taskId }?.agentSession?.externalSessionId
        guard currentExternalId != externalSessionId else { return }

        let command = resumeCommand(for: agentId, externalSessionId: externalSessionId)
        if BoardState.updateAgentSessionExternalId(
            taskId: taskId,
            externalSessionId: externalSessionId,
            resumeCommand: command,
            in: &board
        ) {
            persist()
            showToast("Session captured", detail: agentDisplayName, systemImage: "link")
        }
    }

    private func appendEvent(
        taskId: String,
        columnId: String,
        level: PipelineEventLevel,
        tool: String?,
        message: String
    ) {
        if let event = BoardState.appendPipelineEvent(
            taskId: taskId,
            columnId: columnId,
            level: level,
            tool: tool,
            message: message,
            in: &board
        ) {
            appendEventsToLogFiles([event], taskId: taskId)
            persist()
        }
    }

    private func appendEventsToLogFiles(_ events: [PipelineEvent], taskId: String) {
        do {
            try store.appendPipelineEvents(events, taskId: taskId, in: board)
        } catch {
            errorMessage = "Could not append task logs: \(error.localizedDescription)"
        }
    }

    private func shouldAutoStart(_ column: BoardColumn) -> Bool {
        column.id != BoardColumn.intake.id &&
            column.id != BoardColumn.humanReview.id &&
            column.id != BoardColumn.done.id
    }

    private static func firstUUID(in text: String) -> String? {
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }

    static func agentSessionID(in text: String) -> String? {
        let trimmed = AgentLogClassifier.visibleText(from: text)
        guard trimmed.range(
            of: #"^session id:\s*[0-9a-fA-F-]{36}$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        return firstUUID(in: trimmed)
    }

    private static func boardWithReferenceWorkspaces(_ input: BoardData) -> BoardData {
        var board = input
        for index in board.tasks.indices where board.tasks[index].columnId == BoardColumn.draftDelivery.id {
            board.tasks[index].columnId = BoardColumn.humanReview.id
        }
        for index in board.runs.indices where board.runs[index].currentColumnId == BoardColumn.draftDelivery.id {
            board.runs[index].currentColumnId = BoardColumn.humanReview.id
            board.runs[index].status = .waitingForHuman
        }
        BoardState.compactRunEvents(in: &board)
        normalizeInvalidExternalSessionIds(in: &board)
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

    private static func normalizeInvalidExternalSessionIds(in board: inout BoardData) {
        for runIndex in board.runs.indices {
            guard var session = board.runs[runIndex].agentSession,
                  session.externalSessionId?.trimmingCharacters(in: .whitespacesAndNewlines) == session.id else {
                continue
            }

            let fallback = fallbackResumeCommand(for: session.toolId)
            let timestamp = Date()
            session.externalSessionId = nil
            session.resumeCommand = fallback
            session.updatedAt = timestamp
            board.runs[runIndex].agentSession = session
            board.runs[runIndex].updatedAt = timestamp

            if let taskIndex = board.tasks.firstIndex(where: { $0.id == board.runs[runIndex].taskId }) {
                board.tasks[taskIndex].metatag.removeValue(forKey: "agent_external_session_id")
                board.tasks[taskIndex].metatag["agent_resume_command"] = fallback
                board.tasks[taskIndex].updatedAt = timestamp
            }
        }
    }

}

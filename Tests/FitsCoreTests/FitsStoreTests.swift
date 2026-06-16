import XCTest
@testable import FitsCore

final class FitsStoreTests: XCTestCase {
    private func temporaryStoreURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitsStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testBootstrapCreatesExpectedJsonFiles() throws {
        let root = try temporaryStoreURL()
        let store = FitsStore(rootDirectory: root)

        _ = try store.load()

        let expectedFiles = [
            "settings.json",
            "workspaces.json",
            "projects.json",
            "tasks.json",
            "draft-task.json",
            "runs.json"
        ]

        for file in expectedFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path),
                "Expected \(file) to exist"
            )
        }
    }

    func testSaveAndLoadRoundTripsBoardData() throws {
        let root = try temporaryStoreURL()
        let store = FitsStore(rootDirectory: root)
        var board = try store.load()

        let workspace = FitsWorkspace(
            id: "ws-linkana",
            name: "linkana",
            displayName: "Linkana",
            commitEmail: "cooper@linkana.com"
        )
        let project = FitsProject(
            id: "project-fits",
            workspaceId: workspace.id,
            name: "Fits"
        )
        let task = try FitsTask(
            id: "task-native",
            title: "Build native MVP",
            description: "Build the first local board",
            workspaceId: workspace.id,
            projectId: project.id
        )

        board.workspaces = [workspace]
        board.projects = [project]
        board.tasks = [task]
        board.draftTask = DraftTask(workspaceId: workspace.id, projectId: project.id, title: "Draft", description: "Autosaved")

        try store.save(board)
        let reloaded = try store.load()

        XCTAssertEqual(reloaded.workspaces, [workspace])
        XCTAssertEqual(reloaded.projects, [project])
        XCTAssertEqual(reloaded.tasks, [task])
        XCTAssertEqual(reloaded.draftTask.title, "Draft")
    }

    func testSettingsRoundTripEnabledToolsAndProjectsKeepMultipleRepositories() throws {
        let root = try temporaryStoreURL()
        let store = FitsStore(rootDirectory: root)
        let workspace = FitsWorkspace(
            id: "ws-product",
            name: "product",
            displayName: "Product",
            commitEmail: "product@example.com"
        )
        let project = FitsProject(
            id: "project-suite",
            workspaceId: workspace.id,
            name: "Suite",
            repositories: [
                FitsRepository(id: "repo-api", name: "api", path: "/dev/suite/api", defaultBranch: "main"),
                FitsRepository(id: "repo-web", name: "web", path: "/dev/suite/web", defaultBranch: "trunk")
            ]
        )
        let board = BoardData(
            settings: FitsSettings(enabledToolIds: ["claude", "codex"]),
            workspaces: [workspace],
            projects: [project],
            tasks: [],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        )

        try store.save(board)
        let reloaded = try store.load()

        XCTAssertEqual(reloaded.settings.enabledToolIds, ["claude", "codex"])
        XCTAssertEqual(reloaded.projects.first?.repositories.count, 2)
        XCTAssertEqual(reloaded.projects.first?.repositories.map(\.path), ["/dev/suite/api", "/dev/suite/web"])
    }

    func testSettingsDecodeDefaultsEnabledToolsForExistingFiles() throws {
        let data = """
        {
          "selectedWorkspaceIds": ["ws-personal"],
          "preferredAgent": "claude",
          "theme": "dark"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(FitsSettings.self, from: data)

        XCTAssertEqual(settings.enabledToolIds, [])
        XCTAssertEqual(settings.selectedWorkspaceIds, ["ws-personal"])
        XCTAssertEqual(settings.preferredAgent, "claude")
    }

    func testSaveWritesTaskMarkdownUnderWorkspaceAndProjectPath() throws {
        let root = try temporaryStoreURL()
        let store = FitsStore(rootDirectory: root)
        let workspace = FitsWorkspace(
            id: "ws-linkana",
            name: "Linkana",
            displayName: "Linkana",
            commitEmail: "team@linkana.com"
        )
        let project = FitsProject(
            id: "project-risk",
            workspaceId: workspace.id,
            name: "Risk Scoring"
        )
        let task = try FitsTask(
            id: "task-ofac",
            title: "Add OFAC sanctions list",
            description: "Integrate the OFAC SDN list into the scoring pipeline.",
            workspaceId: workspace.id,
            projectId: project.id,
            planningType: .llmPlanMode,
            metatag: [
                "agent": "critic-opus",
                "branch": "agent/i18n-forms"
            ]
        )
        let board = BoardData(
            workspaces: [workspace],
            projects: [project],
            tasks: [task],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        )

        try store.save(board)

        let markdownURL = root
            .appendingPathComponent("workspaces/linkana/projects/risk-scoring/add-ofac-sanctions-list.md")
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# Add OFAC sanctions list"))
        XCTAssertTrue(markdown.contains("Workspace: Linkana"))
        XCTAssertTrue(markdown.contains("Project: Risk Scoring"))
        XCTAssertTrue(markdown.contains("Planning Type: LLM Plan Mode"))
        XCTAssertTrue(markdown.contains("## Metatag"))
        XCTAssertTrue(markdown.contains("- agent: critic-opus"))
        XCTAssertTrue(markdown.contains("- branch: agent/i18n-forms"))
        XCTAssertTrue(markdown.contains("Integrate the OFAC SDN list into the scoring pipeline."))
    }

    func testSaveWritesRunEventsUnderTaskRunDirectory() throws {
        let root = try temporaryStoreURL()
        let store = FitsStore(rootDirectory: root)
        let workspace = FitsWorkspace(
            id: "ws-a8c",
            name: "a8c",
            displayName: "A8C",
            commitEmail: "team@example.com"
        )
        let project = FitsProject(
            id: "project-dash",
            workspaceId: workspace.id,
            name: "dash"
        )
        let task = try FitsTask(
            id: "task-dash-summary",
            title: "Write dash repository summary",
            description: "Write a file summarizing what ~/dev/a8c/a8c/dash does.",
            workspaceId: workspace.id,
            projectId: project.id
        )
        var board = BoardData(
            workspaces: [workspace],
            projects: [project],
            tasks: [task],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        )

        _ = BoardState.moveTask(
            id: task.id,
            to: BoardColumn.agentQA,
            in: &board,
            at: Date(timeIntervalSinceReferenceDate: 100)
        )
        _ = BoardState.ensureAgentSession(
            taskId: task.id,
            columnId: BoardColumn.agentQA.id,
            toolId: "codex",
            toolDisplayName: "Codex CLI",
            resumeCommand: "codex exec resume 11111111-2222-3333-4444-555555555555",
            in: &board,
            at: Date(timeIntervalSinceReferenceDate: 101)
        )
        _ = BoardState.updateAgentSessionExternalId(
            taskId: task.id,
            externalSessionId: "11111111-2222-3333-4444-555555555555",
            resumeCommand: "codex exec resume 11111111-2222-3333-4444-555555555555",
            in: &board,
            at: Date(timeIntervalSinceReferenceDate: 102)
        )
        try store.save(board)

        let reloaded = try store.load()
        XCTAssertEqual(reloaded.runs.count, 1)
        XCTAssertEqual(reloaded.runs.first?.taskId, task.id)

        let eventsURL = root
            .appendingPathComponent("runs/task-dash-summary/events.ndjson")
        let events = try String(contentsOf: eventsURL, encoding: .utf8)
        XCTAssertTrue(events.contains("\"columnId\":\"agent-qa\""))
        XCTAssertTrue(events.contains("\"level\":\"run\""))
        XCTAssertTrue(events.contains("\"tool\":\"Swift test\""))

        let taskFolder = root
            .appendingPathComponent("workspaces/a8c/projects/dash/write-dash-repository-summary")
        let taskEvents = try String(contentsOf: taskFolder.appendingPathComponent("events.ndjson"), encoding: .utf8)
        let terminalLog = try String(contentsOf: taskFolder.appendingPathComponent("terminal.log"), encoding: .utf8)
        let taskMarkdown = try String(contentsOf: taskFolder.appendingPathComponent("task.md"), encoding: .utf8)
        let session = try String(contentsOf: taskFolder.appendingPathComponent("session.json"), encoding: .utf8)
        XCTAssertTrue(taskEvents.contains("\"columnId\":\"agent-qa\""))
        XCTAssertTrue(terminalLog.contains("Swift test :: Run implementation quality checks"))
        XCTAssertTrue(taskMarkdown.contains("# Write dash repository summary"))
        XCTAssertTrue(session.contains("\"toolId\" : \"codex\""))
        XCTAssertTrue(session.contains("\"externalSessionId\" : \"11111111-2222-3333-4444-555555555555\""))
        XCTAssertTrue(session.contains("\"resumeCommand\" : \"codex exec resume 11111111-2222-3333-4444-555555555555\""))
    }

    func testTaskArtifactHelpersReadPromptHistoryMetatagUpdatesAndArtifacts() throws {
        let root = try temporaryStoreURL()
        let store = FitsStore(rootDirectory: root)
        let workspace = FitsWorkspace(
            id: "ws-a8c",
            name: "a8c",
            displayName: "A8C",
            commitEmail: "team@example.com"
        )
        let project = FitsProject(
            id: "project-dash",
            workspaceId: workspace.id,
            name: "dash"
        )
        let task = try FitsTask(
            id: "task-dash-summary",
            title: "Write dash repository summary",
            description: "Write a file summarizing what dash does.",
            workspaceId: workspace.id,
            projectId: project.id
        )
        let board = BoardData(
            workspaces: [workspace],
            projects: [project],
            tasks: [task],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        )

        try store.save(board)
        let taskFolder = try XCTUnwrap(store.taskArtifactDirectory(for: task, in: board))
        try Data("planning prompt".utf8).write(to: taskFolder.appendingPathComponent("prompt-spec.md"))
        try Data("fan out prompt".utf8).write(to: taskFolder.appendingPathComponent("prompt-plan.md"))
        try Data("line one\nline two\nline three\n".utf8).write(to: taskFolder.appendingPathComponent("terminal.log"))
        try Data(#"{"progress":"45%","agent":"codex"}"#.utf8).write(to: taskFolder.appendingPathComponent("metatag.json"))
        let artifactsFolder = taskFolder.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsFolder, withIntermediateDirectories: true)
        try Data("qa notes".utf8).write(to: artifactsFolder.appendingPathComponent("qa-notes.md"))

        let prompts = try store.taskPromptFiles(for: task, in: board)
        XCTAssertEqual(prompts.map(\.name), ["prompt-plan.md", "prompt-spec.md"])
        XCTAssertEqual(prompts.first { $0.name == "prompt-spec.md" }?.contents, "planning prompt")
        XCTAssertEqual(try store.taskMetatagUpdate(for: task, in: board), ["agent": "codex", "progress": "45%"])
        let artifacts = try store.taskGeneratedArtifacts(for: task, in: board)
        XCTAssertEqual(artifacts.map(\.name), ["qa-notes.md"])
        XCTAssertEqual(artifacts.first?.contents, "qa notes")
        XCTAssertEqual(
            try store.taskTerminalLog(for: task, in: board, maximumBytes: 9),
            "ne three\n"
        )
    }

    func testTaskTerminalLogTailKeepsLatestLinesOnly() throws {
        let root = try temporaryStoreURL()
        let store = FitsStore(rootDirectory: root)
        let workspace = FitsWorkspace(
            id: "ws-a8c",
            name: "a8c",
            displayName: "A8C",
            commitEmail: "a8c@example.com",
            projectIds: ["project-dash"]
        )
        let project = FitsProject(
            id: "project-dash",
            workspaceId: workspace.id,
            name: "dash"
        )
        let task = try FitsTask(
            id: "task-dash-summary",
            title: "Write dash repository summary",
            description: "Write a file summarizing what dash does.",
            workspaceId: workspace.id,
            projectId: project.id
        )
        let board = BoardData(
            workspaces: [workspace],
            projects: [project],
            tasks: [task],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        )

        try store.save(board)
        let taskFolder = try XCTUnwrap(store.taskArtifactDirectory(for: task, in: board))
        let lines = (0..<260).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try Data(lines.utf8).write(to: taskFolder.appendingPathComponent("terminal.log"))

        let tail = try XCTUnwrap(store.taskTerminalLogTail(for: task, in: board, maximumLines: 200))
        let tailLines = tail.contents.split(separator: "\n").map(String.init)

        XCTAssertEqual(tailLines.count, 200)
        XCTAssertEqual(tailLines.first, "line 60")
        XCTAssertEqual(tailLines.last, "line 259")
        XCTAssertEqual(tail.path, taskFolder.appendingPathComponent("terminal.log").path)
    }

    func testAppendPipelineEventsPreservesFullTerminalLogOutsideBoardState() throws {
        let root = try temporaryStoreURL()
        let store = FitsStore(rootDirectory: root)
        let workspace = FitsWorkspace(
            id: "ws-a8c",
            name: "a8c",
            displayName: "A8C",
            commitEmail: "a8c@example.com",
            projectIds: ["project-dash"]
        )
        let project = FitsProject(
            id: "project-dash",
            workspaceId: workspace.id,
            name: "dash"
        )
        let task = try FitsTask(
            id: "task-dash-summary",
            title: "Write dash repository summary",
            description: "Write a file summarizing what dash does.",
            workspaceId: workspace.id,
            projectId: project.id
        )
        let board = BoardData(
            workspaces: [workspace],
            projects: [project],
            tasks: [task],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        )
        try store.save(board)
        let events = (0..<500).map { index in
            PipelineEvent(
                id: "event-\(index)",
                taskId: task.id,
                runId: "run-\(task.id)",
                columnId: BoardColumn.spec.id,
                level: .info,
                tool: "Codex CLI stdout",
                message: "line \(index)"
            )
        }

        try store.appendPipelineEvents(events, taskId: task.id, in: board)

        let fullLog = try XCTUnwrap(store.taskTerminalLog(for: task, in: board, maximumBytes: 1_000_000))
        XCTAssertTrue(fullLog.contains("line 0"))
        XCTAssertTrue(fullLog.contains("line 499"))
        XCTAssertEqual(fullLog.split(separator: "\n").count, 500)
    }

    func testClearExecutionArtifactsRemovesLogsPromptsAndRunIndexForTask() throws {
        let root = try temporaryStoreURL()
        let store = FitsStore(rootDirectory: root)
        let workspace = FitsWorkspace(
            id: "ws-a8c",
            name: "a8c",
            displayName: "A8C",
            commitEmail: "a8c@example.com",
            projectIds: ["project-dash"]
        )
        let project = FitsProject(
            id: "project-dash",
            workspaceId: workspace.id,
            name: "dash"
        )
        let task = try FitsTask(
            id: "task-dash-summary",
            title: "Write dash repository summary",
            description: "Write a file summarizing what dash does.",
            workspaceId: workspace.id,
            projectId: project.id
        )
        var board = BoardData(
            workspaces: [workspace],
            projects: [project],
            tasks: [task],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        )

        _ = BoardState.moveTask(id: task.id, to: BoardColumn.spec, in: &board)
        _ = BoardState.ensureAgentSession(
            taskId: task.id,
            columnId: BoardColumn.spec.id,
            toolId: "codex",
            toolDisplayName: "Codex CLI",
            resumeCommand: "codex resume --last",
            in: &board
        )
        try store.save(board)

        let taskFolder = root
            .appendingPathComponent("workspaces/a8c/projects/dash/write-dash-repository-summary")
        try Data("old prompt".utf8).write(to: taskFolder.appendingPathComponent("prompt-spec.md"))
        try Data("old done".utf8).write(to: taskFolder.appendingPathComponent("stage-done-spec.txt"))
        try Data(#"{"progress":"50%"}"#.utf8).write(to: taskFolder.appendingPathComponent("metatag.json"))
        let artifactsFolder = taskFolder.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsFolder, withIntermediateDirectories: true)
        try Data("old report".utf8).write(to: artifactsFolder.appendingPathComponent("report.md"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: taskFolder.appendingPathComponent("terminal.log").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: taskFolder.appendingPathComponent("events.ndjson").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: taskFolder.appendingPathComponent("session.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: taskFolder.appendingPathComponent("prompt-spec.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: taskFolder.appendingPathComponent("stage-done-spec.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: taskFolder.appendingPathComponent("metatag.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactsFolder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("runs/task-dash-summary/events.ndjson").path))

        try store.clearExecutionArtifacts(for: task, in: board)

        XCTAssertTrue(FileManager.default.fileExists(atPath: taskFolder.appendingPathComponent("task.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: taskFolder.appendingPathComponent("terminal.log").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: taskFolder.appendingPathComponent("events.ndjson").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: taskFolder.appendingPathComponent("session.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: taskFolder.appendingPathComponent("prompt-spec.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: taskFolder.appendingPathComponent("stage-done-spec.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: taskFolder.appendingPathComponent("metatag.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactsFolder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("runs/task-dash-summary").path))
    }
}

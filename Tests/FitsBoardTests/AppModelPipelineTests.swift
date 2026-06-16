import XCTest
import FitsCore
@testable import FitsBoard

@MainActor
final class AppModelPipelineTests: XCTestCase {
    func testOpeningPipelineTaskDefaultsInspectorToDetails() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fits-board-open-details-\(UUID().uuidString)", isDirectory: true)
        let store = FitsStore(rootDirectory: tempRoot.appendingPathComponent("store", isDirectory: true))
        let repoRoot = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)

        let workspace = FitsWorkspace(
            id: "workspace-test",
            name: "workspace-test",
            displayName: "Workspace Test",
            commitEmail: "test@example.com",
            projectIds: ["project-test"]
        )
        let project = FitsProject(
            id: "project-test",
            workspaceId: workspace.id,
            name: "Pipeline Project",
            repositories: [FitsRepository(name: "repo", path: repoRoot.path)]
        )
        let task = try FitsTask(
            id: "task-pipeline",
            title: "Write pipeline artifact",
            description: "Create a small artifact and verify the pipeline.",
            workspaceId: workspace.id,
            projectId: project.id,
            columnId: BoardColumn.plan.id
        )
        try store.save(BoardData(
            workspaces: [workspace],
            projects: [project],
            tasks: [task],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        ))

        let model = AppModel(store: store)
        let loadedTask = try XCTUnwrap(model.board.tasks.first(where: { $0.id == task.id }))

        model.openTaskEditor(loadedTask)

        XCTAssertEqual(model.inspectorTaskId, task.id)
        XCTAssertEqual(model.inspectorTab, .details)
    }

    func testMovingTaskIntoAgentColumnDefaultsInspectorToDetails() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fits-board-move-details-\(UUID().uuidString)", isDirectory: true)
        let store = FitsStore(rootDirectory: tempRoot.appendingPathComponent("store", isDirectory: true))
        let repoRoot = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)

        let workspace = FitsWorkspace(
            id: "workspace-test",
            name: "workspace-test",
            displayName: "Workspace Test",
            commitEmail: "test@example.com",
            projectIds: ["project-test"]
        )
        let project = FitsProject(
            id: "project-test",
            workspaceId: workspace.id,
            name: "Pipeline Project",
            repositories: [FitsRepository(name: "repo", path: repoRoot.path)]
        )
        let task = try FitsTask(
            id: "task-pipeline",
            title: "Write pipeline artifact",
            description: "Create a small artifact and verify the pipeline.",
            workspaceId: workspace.id,
            projectId: project.id
        )
        try store.save(BoardData(
            settings: FitsSettings(enabledToolIds: []),
            workspaces: [workspace],
            projects: [project],
            tasks: [task],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        ))

        let model = AppModel(store: store)
        model.detectedTools = []
        let loadedTask = try XCTUnwrap(model.board.tasks.first(where: { $0.id == task.id }))

        model.moveTask(loadedTask, to: BoardColumn.plan)

        XCTAssertEqual(model.inspectorTaskId, task.id)
        XCTAssertEqual(model.inspectorTab, .details)
    }

    func testCodexSessionParserIgnoresFitsTaskSessionMetatag() {
        XCTAssertNil(AppModel.agentSessionID(in: "- agent_session_id: 7BC1DBBB-C970-45A2-B141-89D5F2DB4A64"))
        XCTAssertNil(AppModel.agentSessionID(in: "- agent_external_session_id: 019ece30-f690-7923-a9d9-d96c8c1e1dd6"))
        XCTAssertNil(AppModel.agentSessionID(in: "External session id captured: 019ece30-f690-7923-a9d9-d96c8c1e1dd6"))
    }

    func testCodexSessionParserCapturesRuntimeSessionIdLine() {
        XCTAssertEqual(
            AppModel.agentSessionID(in: "session id: 019ecd56-fe87-7f60-aba8-ede39cfc1812"),
            "019ecd56-fe87-7f60-aba8-ede39cfc1812"
        )
    }

    func testLoadingBoardClearsInvalidExternalSessionIdEqualToFitsSessionId() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fits-board-invalid-session-\(UUID().uuidString)", isDirectory: true)
        let store = FitsStore(rootDirectory: tempRoot.appendingPathComponent("store", isDirectory: true))
        let workspace = FitsWorkspace(
            id: "workspace-test",
            name: "workspace-test",
            displayName: "Workspace Test",
            commitEmail: "test@example.com",
            projectIds: ["project-test"]
        )
        let project = FitsProject(id: "project-test", workspaceId: workspace.id, name: "Pipeline Project")
        var task = try FitsTask(
            id: "task-pipeline",
            title: "Resume poisoned task",
            description: "Resume should not use the Fits session id as the Codex session id.",
            workspaceId: workspace.id,
            projectId: project.id,
            columnId: BoardColumn.plan.id
        )
        task.metatag["agent_external_session_id"] = "fits-session-id"
        task.metatag["agent_resume_command"] = "codex resume fits-session-id"
        let session = AgentSession(
            id: "fits-session-id",
            toolId: "codex",
            toolDisplayName: "Codex CLI",
            externalSessionId: "fits-session-id",
            resumeCommand: "codex resume fits-session-id",
            status: .failed
        )
        let run = TaskRun(
            id: "run-pipeline",
            taskId: task.id,
            currentColumnId: BoardColumn.plan.id,
            status: .failed,
            agentSession: session
        )
        try store.save(BoardData(
            workspaces: [workspace],
            projects: [project],
            tasks: [task],
            runs: [run],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        ))

        let model = AppModel(store: store)

        let loadedSession = try XCTUnwrap(model.board.runs.first?.agentSession)
        XCTAssertNil(loadedSession.externalSessionId)
        XCTAssertEqual(loadedSession.resumeCommand, "codex resume --last")
        let loadedTask = try XCTUnwrap(model.board.tasks.first)
        XCTAssertNil(loadedTask.metatag["agent_external_session_id"])
        XCTAssertEqual(loadedTask.metatag["agent_resume_command"], "codex resume --last")
    }

    func testMovingTaskToPlanningWithoutProjectRepositoryFailsBeforeLaunchingAgent() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fits-board-missing-repo-\(UUID().uuidString)", isDirectory: true)
        let storeRoot = tempRoot.appendingPathComponent("store", isDirectory: true)

        let store = FitsStore(rootDirectory: storeRoot)
        let workspace = FitsWorkspace(
            id: "workspace-test",
            name: "workspace-test",
            displayName: "Workspace Test",
            commitEmail: "test@example.com",
            projectIds: ["project-empty"]
        )
        let project = FitsProject(
            id: "project-empty",
            workspaceId: workspace.id,
            name: "Empty Project",
            repositories: []
        )
        let task = try FitsTask(
            id: "task-pipeline",
            title: "Write project summary",
            description: "Write a summary using this project.",
            workspaceId: workspace.id,
            projectId: project.id
        )

        try store.save(BoardData(
            settings: FitsSettings(enabledToolIds: ["codex"]),
            workspaces: [workspace],
            projects: [project],
            tasks: [task],
            runs: [],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        ))

        let model = AppModel(store: store)
        model.detectedTools = []

        let loadedTask = try XCTUnwrap(model.board.tasks.first(where: { $0.id == task.id }))
        model.moveTask(loadedTask, to: BoardColumn.spec)

        let run = try XCTUnwrap(model.board.runs.first(where: { $0.taskId == task.id }))
        XCTAssertEqual(run.agentSession, nil)
        XCTAssertTrue(
            run.events.contains { event in
                event.level == .error &&
                    event.tool == "Fits Board" &&
                    event.message == "Project Empty Project needs at least one local repository."
            }
        )
    }

    func testMovingTaskToPlanningRunsAutomatedStagesToHumanReviewAndPersistsTaskLogs() async throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        FileManager.default.changeCurrentDirectoryPath(packageRoot.path)
        try buildFitsAgentHost(packageRoot: packageRoot)

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fits-board-pipeline-\(UUID().uuidString)", isDirectory: true)
        let storeRoot = tempRoot.appendingPathComponent("store", isDirectory: true)
        let repoRoot = tempRoot.appendingPathComponent("repo", isDirectory: true)
        let binRoot = tempRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binRoot, withIntermediateDirectories: true)
        try writeFakeCodex(to: binRoot.appendingPathComponent("codex"))

        let originalPath = String(cString: getenv("PATH"))
        setenv("PATH", "\(binRoot.path):\(originalPath)", 1)
        defer { setenv("PATH", originalPath, 1) }

        let store = FitsStore(rootDirectory: storeRoot)
        let workspace = FitsWorkspace(
            id: "workspace-test",
            name: "workspace-test",
            displayName: "Workspace Test",
            commitEmail: "test@example.com",
            projectIds: ["project-test"]
        )
        let project = FitsProject(
            id: "project-test",
            workspaceId: workspace.id,
            name: "Pipeline Project",
            repositories: [
                FitsRepository(name: "repo", path: repoRoot.path)
            ]
        )
        let task = try FitsTask(
            id: "task-pipeline",
            title: "Write pipeline artifact",
            description: "Create a small artifact and verify the pipeline.",
            workspaceId: workspace.id,
            projectId: project.id
        )
        try store.save(BoardData(
            settings: FitsSettings(enabledToolIds: ["codex"]),
            workspaces: [workspace],
            projects: [project],
            tasks: [task],
            runs: [],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        ))

        let model = AppModel(store: store)
        model.detectedTools = [
            DetectedTool(
                id: "codex",
                displayName: "Codex",
                commandName: "codex",
                status: .installed,
                path: binRoot.appendingPathComponent("codex").path
            )
        ]

        guard let loadedTask = model.board.tasks.first(where: { $0.id == task.id }) else {
            return XCTFail("Expected seeded pipeline task")
        }

        model.moveTask(loadedTask, to: BoardColumn.spec)

        try await waitUntil(timeout: 20) {
            model.board.tasks.first(where: { $0.id == task.id })?.columnId == BoardColumn.humanReview.id
        }

        let finalTask = try XCTUnwrap(model.board.tasks.first(where: { $0.id == task.id }))
        XCTAssertEqual(finalTask.columnId, BoardColumn.humanReview.id)
        XCTAssertEqual(model.board.runs.first(where: { $0.taskId == task.id })?.status, .waitingForHuman)
        XCTAssertEqual(finalTask.metatag["agent_last_stage"], "Agent Review")

        let run = try XCTUnwrap(model.board.runs.first(where: { $0.taskId == task.id }))
        let eventColumns = Set(run.events.map(\.columnId))
        XCTAssertTrue(eventColumns.isSuperset(of: [
            BoardColumn.spec.id,
            BoardColumn.plan.id,
            BoardColumn.agentQA.id,
            BoardColumn.review.id,
            BoardColumn.humanReview.id
        ]))
        let externalSessionEvents = run.events.filter { $0.message.hasPrefix("External session id captured:") }
        XCTAssertEqual(
            Set(externalSessionEvents.map(\.message)),
            ["External session id captured: 11111111-2222-3333-4444-555555555555"]
        )

        let taskDirectory = try XCTUnwrap(store.taskArtifactDirectory(for: finalTask, in: model.board))
        XCTAssertTrue(FileManager.default.fileExists(atPath: taskDirectory.appendingPathComponent("terminal.log").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: taskDirectory.appendingPathComponent("events.ndjson").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: taskDirectory.appendingPathComponent("session.json").path))

        for stage in ["spec", "plan", "agent-qa", "review"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: taskDirectory.appendingPathComponent("prompt-\(stage).md").path),
                "Expected prompt for \(stage)"
            )
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: taskDirectory.appendingPathComponent("stage-done-\(stage).txt").path),
                "Expected completion file for \(stage)"
            )
        }

        let cwdLog = try String(contentsOf: repoRoot.appendingPathComponent("fits-pipeline-cwd.txt"), encoding: .utf8)
        XCTAssertTrue(cwdLogContainsStage("Planning", repoRoot: repoRoot, cwdLog: cwdLog))
        XCTAssertTrue(cwdLogContainsStage("Agent Fan out", repoRoot: repoRoot, cwdLog: cwdLog))
        XCTAssertTrue(cwdLogContainsStage("Agent QA", repoRoot: repoRoot, cwdLog: cwdLog))
        XCTAssertTrue(cwdLogContainsStage("Agent Review", repoRoot: repoRoot, cwdLog: cwdLog))

        let planningPrompt = try String(contentsOf: taskDirectory.appendingPathComponent("prompt-spec.md"), encoding: .utf8)
        let fanOutPrompt = try String(contentsOf: taskDirectory.appendingPathComponent("prompt-plan.md"), encoding: .utf8)
        XCTAssertTrue(planningPrompt.contains("Do not execute the requested work in this stage."))
        XCTAssertTrue(planningPrompt.contains("Fits write-back contract:"))
        XCTAssertTrue(planningPrompt.contains("metatag.json"))
        XCTAssertTrue(planningPrompt.contains("artifacts"))
        XCTAssertTrue(planningPrompt.contains("Use GitHub only when the task explicitly requires it."))
        XCTAssertFalse(planningPrompt.contains("Do not use GitHub."))
        XCTAssertTrue(planningPrompt.contains("Before reporting success, verify this stage's required output is satisfied."))
        XCTAssertTrue(planningPrompt.contains("For Planning, do not execute the requested task work; planning context is the stage output."))
        XCTAssertFalse(planningPrompt.contains("verify whether the user's original request is satisfied for this stage"))
        XCTAssertTrue(fanOutPrompt.contains("Execute the pieces when local execution is possible."))
        XCTAssertEqual(model.taskPromptFiles(for: finalTask).map(\.name), [
            "prompt-agent-qa.md",
            "prompt-plan.md",
            "prompt-review.md",
            "prompt-spec.md"
        ])
        XCTAssertTrue(model.taskGeneratedArtifacts(for: finalTask).contains { $0.name == "Agent-Review.txt" })
    }

    private func buildFitsAgentHost(packageRoot: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["go", "build", "-o", "fits-agent-host", "."]
        process.currentDirectoryURL = packageRoot
            .appendingPathComponent("cmd", isDirectory: true)
            .appendingPathComponent("fits-agent-host", isDirectory: true)
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func writeFakeCodex(to url: URL) throws {
        let script = #"""
#!/usr/bin/env python3
import os
import re
import select
import sys
import time

prompt = ""
for arg in reversed(sys.argv[1:]):
    if "Stage:" in arg and "Do not write or print the completion marker" in arg:
        prompt = arg
        break

if not prompt:
    lines = []
    deadline = time.time() + 5
    while time.time() < deadline:
        readable, _, _ = select.select([sys.stdin], [], [], 0.2)
        if not readable:
            continue
        line = sys.stdin.readline()
        if line == "":
            break
        clean = line.rstrip("\r\n")
        lines.append(clean)
        if "Do not write or print the completion marker" in clean:
            break
    prompt = "\n".join(lines)

stage_match = re.search(r"Stage: (.+)", prompt)
done_match = re.search(
    r"write exactly this completion marker into this file:\n\s*(.*?)\n\s*(FITS_STAGE_DONE_[A-Z0-9_]+)",
    prompt,
    re.MULTILINE,
)
if not stage_match or not done_match:
    print("fake codex could not read Fits completion contract", file=sys.stderr)
    sys.exit(2)

stage = stage_match.group(1).strip()
done_file = done_match.group(1).strip()
sentinel = done_match.group(2).strip()
metatag_match = re.search(r"write a JSON object with string values to:\n\s*(.*?)\n", prompt, re.MULTILINE)
artifacts_match = re.search(r"write files under:\n\s*(.*?)\n", prompt, re.MULTILINE)
os.makedirs(os.path.dirname(done_file), exist_ok=True)
with open(os.path.join(os.getcwd(), "fits-pipeline-cwd.txt"), "a", encoding="utf-8") as handle:
    handle.write(f"Stage: {stage} cwd={os.getcwd()}\n")
if metatag_match:
    with open(metatag_match.group(1).strip(), "w", encoding="utf-8") as handle:
        handle.write('{"agent_last_stage":"' + stage + '"}')
if artifacts_match:
    artifacts_dir = artifacts_match.group(1).strip()
    os.makedirs(artifacts_dir, exist_ok=True)
    with open(os.path.join(artifacts_dir, stage.replace(" ", "-") + ".txt"), "w", encoding="utf-8") as handle:
        handle.write("artifact from " + stage)
with open(done_file, "w", encoding="utf-8") as handle:
    handle.write(sentinel + "\n")

print("session id: 11111111-2222-3333-4444-555555555555")
print(f"fake codex completed {stage}")
print(sentinel)
"""#
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func cwdLogContainsStage(_ stage: String, repoRoot: URL, cwdLog: String) -> Bool {
        let rawPath = repoRoot.path
        let privatePath = rawPath.hasPrefix("/private") ? rawPath : "/private\(rawPath)"
        return cwdLog.contains("Stage: \(stage) cwd=\(rawPath)")
            || cwdLog.contains("Stage: \(stage) cwd=\(privatePath)")
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Timed out waiting for condition")
    }
}

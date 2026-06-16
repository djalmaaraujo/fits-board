import XCTest
import FitsCore
@testable import FitsBoard

final class TaskInspectorPanelTests: XCTestCase {
    func testLogActivityCursorAnimatesOnlyWhileRunning() {
        XCTAssertEqual(LogActivityCursor.text(isRunning: false, tick: 0), "...")
        XCTAssertEqual(LogActivityCursor.text(isRunning: false, tick: 1), "...")
        XCTAssertEqual(LogActivityCursor.text(isRunning: true, tick: 0), ".")
        XCTAssertEqual(LogActivityCursor.text(isRunning: true, tick: 1), "..")
        XCTAssertEqual(LogActivityCursor.text(isRunning: true, tick: 2), "...")
        XCTAssertEqual(LogActivityCursor.text(isRunning: true, tick: 3), ".")
    }

    func testLogDisplayPolicyKeepsLatestEventsForRendering() {
        let events = (0..<500).map { index in
            PipelineEvent(
                id: "event-\(index)",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "spec",
                level: .info,
                message: "line \(index)"
            )
        }

        let visible = LogDisplayPolicy.visibleEvents(events)

        XCTAssertEqual(visible.count, LogDisplayPolicy.maximumRenderedEvents)
        XCTAssertEqual(visible.first?.id, "event-300")
        XCTAssertEqual(visible.last?.id, "event-499")
    }

    func testConciseLogDisplayHidesCodexInternalTranscriptNoise() {
        let events = [
            PipelineEvent(
                id: "assistant-note",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "agent-qa",
                level: .info,
                tool: "Codex CLI stdout",
                message: "I’m checking the generated artifact against the original task."
            ),
            PipelineEvent(
                id: "exec-marker",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "agent-qa",
                level: .info,
                tool: "Codex CLI stdout",
                message: "exec"
            ),
            PipelineEvent(
                id: "skill-dump",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "agent-qa",
                level: .info,
                tool: "Codex CLI stdout",
                message: "NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE"
            ),
            PipelineEvent(
                id: "real-error",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "agent-qa",
                level: .error,
                tool: "Codex CLI stdout",
                message: "Error: missing expected artifact"
            )
        ]

        let visible = LogDisplayPolicy.visibleEvents(events, verbosity: .concise)

        XCTAssertEqual(visible.map(\.id), ["assistant-note", "real-error"])
    }

    func testVerboseLogDisplayKeepsCodexInternalTranscriptEvents() {
        let events = [
            PipelineEvent(
                id: "assistant-note",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "agent-qa",
                level: .info,
                tool: "Codex CLI stdout",
                message: "I’m checking the generated artifact against the original task."
            ),
            PipelineEvent(
                id: "exec-marker",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "agent-qa",
                level: .info,
                tool: "Codex CLI stdout",
                message: "exec"
            )
        ]

        let visible = LogDisplayPolicy.visibleEvents(events, verbosity: .verbose)

        XCTAssertEqual(visible.map(\.id), ["assistant-note", "exec-marker"])
    }

    func testConciseLogDisplayHidesCodexDiffAndControlTranscriptNoise() {
        let events = [
            PipelineEvent(
                id: "summary",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "agent-qa",
                level: .info,
                tool: "Codex CLI stdout",
                message: "Wrote the requested Desktop file and verified it exists."
            ),
            PipelineEvent(
                id: "diff-header",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "agent-qa",
                level: .info,
                tool: "Codex CLI stdout",
                message: "diff --git a/stage-done-agent-qa.txt b/stage-done-agent-qa.txt"
            ),
            PipelineEvent(
                id: "diff-index",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "agent-qa",
                level: .info,
                tool: "Codex CLI stdout",
                message: "index 0000000..f00ba42 100644"
            ),
            PipelineEvent(
                id: "diff-hunk",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "agent-qa",
                level: .info,
                tool: "Codex CLI stdout",
                message: "@@ -0,0 +1 @@"
            ),
            PipelineEvent(
                id: "sentinel",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "agent-qa",
                level: .info,
                tool: "Codex CLI stdout",
                message: "+FITS_STAGE_DONE_TASK_A_AGENT_QA"
            ),
            PipelineEvent(
                id: "quit",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "agent-qa",
                level: .info,
                tool: "Codex CLI stdout",
                message: "/quit"
            ),
            PipelineEvent(
                id: "interrupted",
                taskId: "task-a",
                runId: "run-task-a",
                columnId: "agent-qa",
                level: .info,
                tool: "Codex CLI stdout",
                message: "turn interrupted"
            )
        ]

        let concise = LogDisplayPolicy.visibleEvents(events, verbosity: .concise)
        let verbose = LogDisplayPolicy.visibleEvents(events, verbosity: .verbose)

        XCTAssertEqual(concise.map(\.id), ["summary"])
        XCTAssertEqual(verbose.map(\.id), events.map(\.id))
    }
}

import XCTest
@testable import FitsCore

final class AgentLogClassifierTests: XCTestCase {
    func testCodexStderrBannerAndRunMetadataAreInfo() {
        let lines = [
            "OpenAI Codex v0.140.0",
            "--------",
            "workdir: /Users/cooper/dev/fits",
            "model: gpt-5.5",
            "provider: openai",
            "approval: never",
            "sandbox: workspace-write [workdir, /tmp, $TMPDIR]",
            "reasoning effort: high",
            "reasoning summaries: none",
            "session id: 019ecd56-fe87-7f60-aba8-ede39cfc1812",
            "user",
            "Reading additional input from stdin..."
        ]

        for line in lines {
            XCTAssertEqual(
                AgentLogClassifier.classify(toolId: "codex", stream: .stderr, line: line),
                .info,
                "Expected info for \(line)"
            )
        }
    }

    func testCodexPluginManifestNoiseIsHidden() {
        let lines = [
            "2026-06-15T22:11:34.910962Z WARN codex_core_skills::loader: ignoring interface.icon_small: icon path with '..' must resolve under plugin assets/",
            "2026-06-15T22:11:31.829039Z WARN codex_core_plugins::manifest: ignoring interface.defaultPrompt[0]: prompt must be at most 128 characters path=/Users/cooper/.codex/.tmp/plugins/plugins/ngs-analysis/.codex-plugin/plugin.json",
            "2026-06-16T01:07:41.763077Z WARN codex_core_plugins::manager: failed to auto-upgrade configured marketplace marketplace=\"caveman-repo\"",
            "2026-06-16T01:13:04.118125Z ERROR rmcp::transport::worker: worker quit with fatal: Transport channel closed, when AuthRequired(AuthRequiredError { www_authenticate_header: \"Bearer error=\\\"invalid_request\\\"\" })",
            "2026-06-16T01:13:04.599472Z WARN rmcp::transport::auth: Token refresh not possible, re-authorization required. error=OAuth token refresh failed: Server returned error response: invalid_grant: Grant not found",
            "2026-06-16T01:13:04.599523Z ERROR rmcp::transport::worker: worker quit with fatal: Transport channel closed, when Auth(AuthorizationRequired)",
            "hook: SessionStart",
            "hook: SessionStart Completed",
            "must resolve under plugin assets/"
        ]

        for line in lines {
            XCTAssertNil(
                AgentLogClassifier.classify(toolId: "codex", stream: .stderr, line: line),
                "Expected hidden noise for \(line)"
            )
            XCTAssertNil(
                AgentLogClassifier.classify(toolId: "codex", stream: .stdout, line: line),
                "Expected hidden stdout noise for \(line)"
            )
        }
    }

    func testCodexRealErrorsRemainErrors() {
        XCTAssertEqual(
            AgentLogClassifier.classify(
                toolId: "codex",
                stream: .stderr,
                line: "2026-06-15T22:08:38.648040Z ERROR rmcp::transport::worker: worker quit with fatal"
            ),
            .error
        )
    }

    func testCodexNonMCPRuntimeErrorsRemainErrors() {
        XCTAssertEqual(
            AgentLogClassifier.classify(
                toolId: "codex",
                stream: .stdout,
                line: "Error: No such file or directory (os error 2)"
            ),
            .error
        )
    }

    func testStdoutIsInfo() {
        XCTAssertEqual(
            AgentLogClassifier.classify(toolId: "codex", stream: .stdout, line: "Created ~/Desktop/arquivos.txt"),
            .info
        )
    }

    func testCodexStdoutPromptEchoCharactersAreHidden() {
        for line in ["T", ":", "/", "~"] {
            XCTAssertNil(
                AgentLogClassifier.classify(toolId: "codex", stream: .stdout, line: line),
                "Expected single-character Codex prompt echo to be hidden: \(line)"
            )
        }
    }

    func testVisibleTextStripsTerminalControlSequences() {
        let raw = "\u{001B}[?2004h\u{001B}[1mFITS_STAGE_DONE_TASK_PLANNING\u{001B}[0m\u{001B}7"

        XCTAssertEqual(
            AgentLogClassifier.visibleText(from: raw),
            "FITS_STAGE_DONE_TASK_PLANNING"
        )
    }
}

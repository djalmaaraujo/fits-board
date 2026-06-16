import XCTest
@testable import FitsCore

final class AgentCommandBuilderTests: XCTestCase {
    func testCodexStartArgumentsUseInteractivePTYOptions() {
        let arguments = AgentCommandBuilder.codexStartArguments(
            repositoryPath: "/tmp/example",
            writableDirectories: [],
            prompt: "Plan this stage"
        )

        XCTAssertEqual(arguments, [
            "exec",
            "--cd",
            "/tmp/example",
            "--skip-git-repo-check",
            "--dangerously-bypass-approvals-and-sandbox",
            "Plan this stage"
        ])
    }

    func testCodexStartArgumentsIncludeWritableDirectoriesBeforePrompt() {
        let arguments = AgentCommandBuilder.codexStartArguments(
            repositoryPath: "/tmp/example",
            writableDirectories: ["/Users/cooper/Desktop", "  ", "/Users/cooper/.fits-board/task"],
            prompt: "Plan this stage"
        )

        XCTAssertEqual(arguments, [
            "exec",
            "--cd",
            "/tmp/example",
            "--skip-git-repo-check",
            "--dangerously-bypass-approvals-and-sandbox",
            "Plan this stage"
        ])
    }

    func testCodexResumeArgumentsUseSessionIdWhenAvailableWithPTYOptions() {
        let arguments = AgentCommandBuilder.codexResumeArguments(
            repositoryPath: "/tmp/example",
            writableDirectories: ["/tmp/task"],
            externalSessionId: "11111111-2222-3333-4444-555555555555",
            prompt: "Continue the stage"
        )

        XCTAssertEqual(arguments, [
            "exec",
            "resume",
            "--skip-git-repo-check",
            "--dangerously-bypass-approvals-and-sandbox",
            "11111111-2222-3333-4444-555555555555",
            "Continue the stage"
        ])
    }

    func testCodexResumeArgumentsFallBackToLastSession() {
        let arguments = AgentCommandBuilder.codexResumeArguments(
            repositoryPath: "/tmp/example",
            writableDirectories: [],
            externalSessionId: nil,
            prompt: "Continue the stage"
        )

        XCTAssertEqual(arguments, [
            "exec",
            "resume",
            "--skip-git-repo-check",
            "--dangerously-bypass-approvals-and-sandbox",
            "--last",
            "Continue the stage"
        ])
    }

    func testMissingRequiredDirectoriesIncludesRepositoryAndWritableDirs() {
        let missing = AgentCommandBuilder.missingRequiredDirectories(
            repositoryPath: "/missing/repo",
            writableDirectories: ["/ok/task", "/missing/desktop"],
            directoryExists: { path in path == "/ok/task" }
        )

        XCTAssertEqual(missing, ["/missing/repo", "/missing/desktop"])
    }
}

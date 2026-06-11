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
            "draft-task.json"
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
            projectId: project.id
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
        XCTAssertTrue(markdown.contains("Integrate the OFAC SDN list into the scoring pipeline."))
    }
}

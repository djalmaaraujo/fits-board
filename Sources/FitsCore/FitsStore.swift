import Foundation

public struct BoardData: Codable, Equatable, Sendable {
    public var settings: FitsSettings
    public var workspaces: [FitsWorkspace]
    public var projects: [FitsProject]
    public var tasks: [FitsTask]
    public var draftTask: DraftTask
    public var columns: [BoardColumn]

    public init(
        settings: FitsSettings = FitsSettings(),
        workspaces: [FitsWorkspace] = [],
        projects: [FitsProject] = [],
        tasks: [FitsTask] = [],
        draftTask: DraftTask = DraftTask(),
        columns: [BoardColumn] = BoardColumn.defaults
    ) {
        self.settings = settings
        self.workspaces = workspaces
        self.projects = projects
        self.tasks = tasks
        self.draftTask = draftTask
        self.columns = columns
    }

    public static func seeded() throws -> BoardData {
        let workspace = FitsWorkspace(
            id: "ws-personal",
            name: "personal",
            displayName: "Personal",
            commitEmail: "you@example.com",
            colorHex: "#22c55e",
            projectIds: ["project-fits"]
        )
        let project = FitsProject(
            id: "project-fits",
            workspaceId: workspace.id,
            name: "Fits Board",
            repositories: [
                FitsRepository(name: "fits", path: "~/dev/fits")
            ]
        )
        let task = try FitsTask(
            id: "task-welcome",
            title: "Create your first workspace task",
            description: "Use the intake composer to add a task with a workspace, project, title, and description.",
            workspaceId: workspace.id,
            projectId: project.id
        )

        return BoardData(
            settings: FitsSettings(selectedWorkspaceIds: []),
            workspaces: [workspace],
            projects: [project],
            tasks: [task],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        )
    }
}

public struct FitsStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL = FitsStore.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
    }

    public static func defaultRootDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".fits-board", isDirectory: true)
    }

    public func load() throws -> BoardData {
        try ensureRootDirectory()

        if !FileManager.default.fileExists(atPath: fileURL("settings.json").path) {
            let seeded = try BoardData.seeded()
            try save(seeded)
            return seeded
        }

        return BoardData(
            settings: try read(FitsSettings.self, from: "settings.json"),
            workspaces: try read([FitsWorkspace].self, from: "workspaces.json"),
            projects: try read([FitsProject].self, from: "projects.json"),
            tasks: try read([FitsTask].self, from: "tasks.json"),
            draftTask: try read(DraftTask.self, from: "draft-task.json")
        )
    }

    public func save(_ data: BoardData) throws {
        try ensureRootDirectory()
        try write(data.settings, to: "settings.json")
        try write(data.workspaces, to: "workspaces.json")
        try write(data.projects, to: "projects.json")
        try write(data.tasks, to: "tasks.json")
        try write(data.draftTask, to: "draft-task.json")
    }

    private func ensureRootDirectory() throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }

    private func fileURL(_ fileName: String) -> URL {
        rootDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private func read<T: Decodable>(_ type: T.Type, from fileName: String) throws -> T {
        let data = try Data(contentsOf: fileURL(fileName))
        let decoder = Self.makeDecoder()
        return try decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to fileName: String) throws {
        let encoder = Self.makeEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        let destination = fileURL(fileName)
        let temporary = rootDirectory.appendingPathComponent(".\(fileName).tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: [.atomic])

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(String(format: "%.17g", date.timeIntervalSinceReferenceDate))
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let seconds = Double(value) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid timestamp date: \(value)"
            )
        }
        return decoder
    }
}

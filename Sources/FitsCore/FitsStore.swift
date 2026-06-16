import Foundation

public struct BoardData: Codable, Equatable, Sendable {
    public var settings: FitsSettings
    public var workspaces: [FitsWorkspace]
    public var projects: [FitsProject]
    public var tasks: [FitsTask]
    public var runs: [TaskRun]
    public var draftTask: DraftTask
    public var columns: [BoardColumn]

    public init(
        settings: FitsSettings = FitsSettings(),
        workspaces: [FitsWorkspace] = [],
        projects: [FitsProject] = [],
        tasks: [FitsTask] = [],
        runs: [TaskRun] = [],
        draftTask: DraftTask = DraftTask(),
        columns: [BoardColumn] = BoardColumn.defaults
    ) {
        self.settings = settings
        self.workspaces = workspaces
        self.projects = projects
        self.tasks = tasks
        self.runs = runs
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
            runs: [],
            draftTask: DraftTask(workspaceId: workspace.id, projectId: project.id)
        )
    }
}

public struct TaskArtifactTextFile: Equatable, Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let contents: String

    public init(name: String, path: String, contents: String) {
        self.name = name
        self.path = path
        self.contents = contents
    }
}

public struct TaskLogTail: Equatable, Sendable {
    public let path: String
    public let contents: String
    public let totalBytes: UInt64
    public let isTruncated: Bool

    public init(path: String, contents: String, totalBytes: UInt64, isTruncated: Bool) {
        self.path = path
        self.contents = contents
        self.totalBytes = totalBytes
        self.isTruncated = isTruncated
    }
}

public struct FitsStore: Sendable {
    public let rootDirectory: URL
    private static let maximumArtifactPreviewBytes = 80_000

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
            runs: try readIfPresent([TaskRun].self, from: "runs.json") ?? [],
            draftTask: try read(DraftTask.self, from: "draft-task.json")
        )
    }

    public func save(_ data: BoardData) throws {
        try ensureRootDirectory()
        try write(data.settings, to: "settings.json")
        try write(data.workspaces, to: "workspaces.json")
        try write(data.projects, to: "projects.json")
        try write(data.tasks, to: "tasks.json")
        try write(data.runs, to: "runs.json")
        try write(data.draftTask, to: "draft-task.json")
        try writeTaskMarkdownFiles(data)
        try writeRunEventFiles(data.runs)
    }

    public func taskArtifactDirectory(for task: FitsTask, in data: BoardData) -> URL? {
        guard let workspace = data.workspaces.first(where: { $0.id == task.workspaceId }),
              let project = data.projects.first(where: { $0.id == task.projectId }) else {
            return nil
        }

        return projectDirectory(workspace: workspace, project: project)
            .appendingPathComponent(Self.slug(task.title, fallback: task.id), isDirectory: true)
    }

    public func taskPromptFiles(for task: FitsTask, in data: BoardData) throws -> [TaskArtifactTextFile] {
        guard let directory = taskArtifactDirectory(for: task, in: data) else { return [] }
        return try textFiles(
            in: directory,
            matching: { $0.hasPrefix("prompt-") && $0.hasSuffix(".md") }
        )
    }

    public func taskGeneratedArtifacts(for task: FitsTask, in data: BoardData) throws -> [TaskArtifactTextFile] {
        guard let directory = taskArtifactDirectory(for: task, in: data) else { return [] }
        let artifactsDirectory = directory.appendingPathComponent("artifacts", isDirectory: true)
        return try textFiles(in: artifactsDirectory, matching: { !$0.hasPrefix(".") })
    }

    public func taskTerminalLog(
        for task: FitsTask,
        in data: BoardData,
        maximumBytes: UInt64 = 512_000
    ) throws -> String? {
        guard let directory = taskArtifactDirectory(for: task, in: data) else { return nil }
        let url = directory.appendingPathComponent("terminal.log")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        let startOffset = fileSize > maximumBytes ? fileSize - maximumBytes : 0
        try handle.seek(toOffset: startOffset)
        let data = try handle.readToEnd() ?? Data()
        return String(data: data, encoding: .utf8)
    }

    public func taskTerminalLogTail(
        for task: FitsTask,
        in data: BoardData,
        maximumLines: Int = 200,
        maximumBytes: UInt64 = 160_000
    ) throws -> TaskLogTail? {
        guard let directory = taskArtifactDirectory(for: task, in: data) else { return nil }
        let url = directory.appendingPathComponent("terminal.log")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard maximumLines > 0 else {
            return TaskLogTail(path: url.path, contents: "", totalBytes: 0, isTruncated: false)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        let startOffset = fileSize > maximumBytes ? fileSize - maximumBytes : 0
        try handle.seek(toOffset: startOffset)
        let data = try handle.readToEnd() ?? Data()
        guard let text = String(data: data, encoding: .utf8) else {
            return TaskLogTail(path: url.path, contents: "", totalBytes: fileSize, isTruncated: fileSize > maximumBytes)
        }

        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        let lineTruncated = lines.count > maximumLines
        if lineTruncated {
            lines = Array(lines.suffix(maximumLines))
        }
        let contents = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        return TaskLogTail(
            path: url.path,
            contents: contents,
            totalBytes: fileSize,
            isTruncated: fileSize > maximumBytes || lineTruncated
        )
    }

    public func taskTerminalLogURL(for task: FitsTask, in data: BoardData) -> URL? {
        guard let directory = taskArtifactDirectory(for: task, in: data) else { return nil }
        let url = directory.appendingPathComponent("terminal.log")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    public func appendPipelineEvents(
        _ events: [PipelineEvent],
        taskId: String,
        in data: BoardData
    ) throws {
        guard !events.isEmpty,
              let task = data.tasks.first(where: { $0.id == taskId }),
              let taskDirectory = taskArtifactDirectory(for: task, in: data) else {
            return
        }

        try FileManager.default.createDirectory(at: taskDirectory, withIntermediateDirectories: true)
        try appendEventLines(events, to: taskDirectory.appendingPathComponent("events.ndjson"))
        try appendTerminalLines(events, to: taskDirectory.appendingPathComponent("terminal.log"))

        let runDirectory = rootDirectory
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(Self.slug(taskId, fallback: taskId), isDirectory: true)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try appendEventLines(events, to: runDirectory.appendingPathComponent("events.ndjson"))
    }

    public func taskMetatagUpdate(for task: FitsTask, in data: BoardData) throws -> [String: String] {
        guard let directory = taskArtifactDirectory(for: task, in: data) else { return [:] }
        let url = directory.appendingPathComponent("metatag.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let rawValues = try Self.makeDecoder().decode([String: String].self, from: Data(contentsOf: url))
        return rawValues.reduce(into: [:]) { result, pair in
            let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            result[key] = value
        }
    }

    public func clearExecutionArtifacts(for task: FitsTask, in data: BoardData) throws {
        let fileManager = FileManager.default
        let executionFileNames = Set(["events.ndjson", "terminal.log", "session.json", "metatag.json"])

        for directory in taskArtifactDirectories(for: task, in: data) {
            guard fileManager.fileExists(atPath: directory.path) else { continue }
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            for url in contents {
                let fileName = url.lastPathComponent
                if executionFileNames.contains(fileName) ||
                    (fileName.hasPrefix("prompt-") && fileName.hasSuffix(".md")) ||
                    (fileName.hasPrefix("stage-done-") && fileName.hasSuffix(".txt")) {
                    try fileManager.removeItem(at: url)
                }
            }

            let artifactsDirectory = directory.appendingPathComponent("artifacts", isDirectory: true)
            if fileManager.fileExists(atPath: artifactsDirectory.path) {
                try fileManager.removeItem(at: artifactsDirectory)
            }
        }

        let runDirectory = rootDirectory
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(Self.slug(task.id, fallback: task.id), isDirectory: true)
        if fileManager.fileExists(atPath: runDirectory.path) {
            try fileManager.removeItem(at: runDirectory)
        }
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

    private func readIfPresent<T: Decodable>(_ type: T.Type, from fileName: String) throws -> T? {
        let url = fileURL(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
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

    private func textFiles(in directory: URL, matching predicate: (String) -> Bool) throws -> [TaskArtifactTextFile] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return urls
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && predicate(url.lastPathComponent)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                let previewData = data.count > Self.maximumArtifactPreviewBytes
                    ? data.prefix(Self.maximumArtifactPreviewBytes)
                    : data[...]
                guard var contents = String(data: Data(previewData), encoding: .utf8) else { return nil }
                if data.count > Self.maximumArtifactPreviewBytes {
                    contents += "\n\n[truncated preview: \(data.count) bytes total]"
                }
                return TaskArtifactTextFile(name: url.lastPathComponent, path: url.path, contents: contents)
            }
    }

    private func writeTaskMarkdownFiles(_ data: BoardData) throws {
        for task in data.tasks {
            guard let workspace = data.workspaces.first(where: { $0.id == task.workspaceId }),
                  let project = data.projects.first(where: { $0.id == task.projectId }) else {
                continue
            }

            let directory = projectDirectory(workspace: workspace, project: project)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let fileURL = directory.appendingPathComponent("\(Self.slug(task.title, fallback: task.id)).md")
            let markdown = Self.markdown(for: task, workspace: workspace, project: project)
            try Data(markdown.utf8).write(to: fileURL, options: [.atomic])

            let taskDirectory = directory.appendingPathComponent(Self.slug(task.title, fallback: task.id), isDirectory: true)
            try FileManager.default.createDirectory(at: taskDirectory, withIntermediateDirectories: true)
            try Data(markdown.utf8).write(to: taskDirectory.appendingPathComponent("task.md"), options: [.atomic])
            if let run = data.runs.first(where: { $0.taskId == task.id }) {
                try writeRunArtifacts(run, to: taskDirectory)
            }
        }
    }

    private func writeRunEventFiles(_ runs: [TaskRun]) throws {
        let runsDirectory = rootDirectory.appendingPathComponent("runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runsDirectory, withIntermediateDirectories: true)

        for run in runs {
            let directory = runsDirectory.appendingPathComponent(Self.slug(run.taskId, fallback: run.id), isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let eventsURL = directory.appendingPathComponent("events.ndjson")
            if !FileManager.default.fileExists(atPath: eventsURL.path) {
                try writeEventLines(run.events, to: eventsURL)
            }
        }
    }

    private func projectDirectory(workspace: FitsWorkspace, project: FitsProject) -> URL {
        rootDirectory
            .appendingPathComponent("workspaces", isDirectory: true)
            .appendingPathComponent(Self.slug(workspace.name, fallback: workspace.id), isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(Self.slug(project.name, fallback: project.id), isDirectory: true)
    }

    private func taskArtifactDirectories(for task: FitsTask, in data: BoardData) -> [URL] {
        guard let workspace = data.workspaces.first(where: { $0.id == task.workspaceId }),
              let project = data.projects.first(where: { $0.id == task.projectId }) else {
            return []
        }

        let fileManager = FileManager.default
        let projectDirectory = projectDirectory(workspace: workspace, project: project)
        var directories = [projectDirectory.appendingPathComponent(Self.slug(task.title, fallback: task.id), isDirectory: true)]

        guard let contents = try? fileManager.contentsOfDirectory(
            at: projectDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return directories
        }

        for url in contents {
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory == true else { continue }
            let taskMarkdown = url.appendingPathComponent("task.md")
            guard let markdown = try? String(contentsOf: taskMarkdown, encoding: .utf8),
                  markdown.contains("Task ID: \(task.id)") else {
                continue
            }
            if !directories.contains(url) {
                directories.append(url)
            }
        }

        return directories
    }

    private func writeRunArtifacts(_ run: TaskRun, to directory: URL) throws {
        let eventsURL = directory.appendingPathComponent("events.ndjson")
        if !FileManager.default.fileExists(atPath: eventsURL.path) {
            try writeEventLines(run.events, to: eventsURL)
        }

        let terminalURL = directory.appendingPathComponent("terminal.log")
        if !FileManager.default.fileExists(atPath: terminalURL.path) {
            try writeTerminalLines(run.events, to: terminalURL)
        }

        if let session = run.agentSession {
            let sessionEncoder = Self.makeEncoder()
            sessionEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let sessionData = try sessionEncoder.encode(session)
            try sessionData.write(to: directory.appendingPathComponent("session.json"), options: [.atomic])
        }
    }

    private static func terminalLine(for event: PipelineEvent) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        let toolPrefix = event.tool.map { "\($0) :: " } ?? ""
        return "\(formatter.string(from: event.timestamp)) \(event.level.displayName) \(toolPrefix)\(event.message)"
    }

    private func appendEventLines(_ events: [PipelineEvent], to url: URL) throws {
        let body = try encodedEventLines(events)
        try append(body, to: url)
    }

    private func appendTerminalLines(_ events: [PipelineEvent], to url: URL) throws {
        let body = lineBody(events.map(Self.terminalLine(for:)))
        try append(body, to: url)
    }

    private func writeEventLines(_ events: [PipelineEvent], to url: URL) throws {
        try Data(try encodedEventLines(events).utf8).write(to: url, options: [.atomic])
    }

    private func writeTerminalLines(_ events: [PipelineEvent], to url: URL) throws {
        try Data(lineBody(events.map(Self.terminalLine(for:))).utf8).write(to: url, options: [.atomic])
    }

    private func encodedEventLines(_ events: [PipelineEvent]) throws -> String {
        let encoder = Self.makeEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try events.map { event in
            let data = try encoder.encode(event)
            return String(decoding: data, as: UTF8.self)
        }
        return lineBody(lines)
    }

    private func lineBody(_ lines: [String]) -> String {
        lines.isEmpty ? "" : "\(lines.joined(separator: "\n"))\n"
    }

    private func append(_ body: String, to url: URL) throws {
        guard !body.isEmpty else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data().write(to: url, options: [.atomic])
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(body.utf8))
    }

    private static func markdown(for task: FitsTask, workspace: FitsWorkspace, project: FitsProject) -> String {
        let metatagSection: String
        if task.metatag.isEmpty {
            metatagSection = ""
        } else {
            let lines = task.metatag
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                .map { "- \($0.key): \($0.value)" }
                .joined(separator: "\n")
            metatagSection = "\n\n## Metatag\n\n\(lines)"
        }

        return """
        # \(task.title)

        Workspace: \(workspace.displayName)
        Project: \(project.name)
        Planning Type: \(task.planningType.displayName)
        Column: \(task.columnId)
        Task ID: \(task.id)

        ## Description

        \(task.description)\(metatagSection)
        """
    }

    private static func slug(_ value: String, fallback: String) -> String {
        let lowercased = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet.alphanumerics
        var result = ""
        var previousWasSeparator = false

        for scalar in lowercased.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append("-")
                previousWasSeparator = true
            }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if trimmed.isEmpty {
            return fallback
        }
        return trimmed
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

import Foundation

public enum FitsValidationError: Error, Equatable, LocalizedError {
    case missingField(String)

    public var errorDescription: String? {
        switch self {
        case .missingField(let field):
            "Missing required field: \(field)"
        }
    }
}

public struct BoardColumn: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var kind: Kind

    public enum Kind: String, Codable, Sendable {
        case human
        case agent
        case done
    }

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    public static let intake = BoardColumn(id: "intake", name: "Backlog", kind: .human)
    public static let spec = BoardColumn(id: "spec", name: "Planning", kind: .human)
    public static let plan = BoardColumn(id: "plan", name: "Agent Fan out", kind: .agent)
    public static let agentQA = BoardColumn(id: "agent-qa", name: "Agent QA", kind: .agent)
    public static let review = BoardColumn(id: "review", name: "Agent Review", kind: .agent)
    public static let draftDelivery = BoardColumn(id: "draft-delivery", name: "Draft Delivery", kind: .human)
    public static let humanReview = BoardColumn(id: "human-review", name: "Human Review", kind: .human)
    public static let done = BoardColumn(id: "done", name: "Ship it", kind: .done)

    public static let defaults: [BoardColumn] = [
        .intake,
        .spec,
        .plan,
        .agentQA,
        .review,
        .draftDelivery,
        .humanReview,
        .done
    ]
}

public struct FitsWorkspace: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var displayName: String
    public var commitEmail: String
    public var colorHex: String
    public var projectIds: [String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        displayName: String,
        commitEmail: String,
        colorHex: String = "#2563eb",
        projectIds: [String] = []
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.commitEmail = commitEmail
        self.colorHex = colorHex
        self.projectIds = projectIds
    }
}

public struct FitsRepository: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var path: String
    public var defaultBranch: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        path: String,
        defaultBranch: String = "main"
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.defaultBranch = defaultBranch
    }
}

public struct FitsProject: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var workspaceId: String
    public var name: String
    public var repositories: [FitsRepository]

    public init(
        id: String = UUID().uuidString,
        workspaceId: String,
        name: String,
        repositories: [FitsRepository] = []
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.name = name
        self.repositories = repositories
    }
}

public enum TaskPlanningType: String, Codable, CaseIterable, Identifiable, Sendable {
    case fast
    case llmPlanMode
    case superpowersSkill

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fast:
            "Fast (auto)"
        case .llmPlanMode:
            "LLM Plan Mode"
        case .superpowersSkill:
            "Superpowers Skill"
        }
    }

    public var description: String {
        switch self {
        case .fast:
            "I will plan for you, but without any questions it will try to perform the task on its own."
        case .llmPlanMode:
            "Regular plan mode from the LLM you are using."
        case .superpowersSkill:
            "Requires more attention, it will start a set of questions in order to generate plans into your repo."
        }
    }
}

public struct FitsTask: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var description: String
    public var workspaceId: String
    public var projectId: String
    public var planningType: TaskPlanningType
    public var metatag: [String: String]
    public var columnId: String
    public var createdAt: Date
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case workspaceId
        case projectId
        case planningType
        case metatag
        case columnId
        case createdAt
        case updatedAt
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String,
        workspaceId: String,
        projectId: String,
        planningType: TaskPlanningType = .fast,
        metatag: [String: String] = [:],
        columnId: String = BoardColumn.intake.id,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FitsValidationError.missingField("title")
        }
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FitsValidationError.missingField("description")
        }
        guard !workspaceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FitsValidationError.missingField("workspaceId")
        }
        guard !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FitsValidationError.missingField("projectId")
        }

        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        self.workspaceId = workspaceId
        self.projectId = projectId
        self.planningType = planningType
        self.metatag = metatag
        self.columnId = columnId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.description = try container.decode(String.self, forKey: .description)
        self.workspaceId = try container.decode(String.self, forKey: .workspaceId)
        self.projectId = try container.decode(String.self, forKey: .projectId)
        self.planningType = try container.decodeIfPresent(TaskPlanningType.self, forKey: .planningType) ?? .fast
        self.metatag = try container.decodeIfPresent([String: String].self, forKey: .metatag) ?? [:]
        self.columnId = try container.decode(String.self, forKey: .columnId)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public struct DraftTask: Codable, Equatable, Sendable {
    public var workspaceId: String
    public var projectId: String
    public var planningType: TaskPlanningType
    public var title: String
    public var description: String
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case workspaceId
        case projectId
        case planningType
        case title
        case description
        case updatedAt
    }

    public init(
        workspaceId: String = "",
        projectId: String = "",
        planningType: TaskPlanningType = .fast,
        title: String = "",
        description: String = "",
        updatedAt: Date = Date()
    ) {
        self.workspaceId = workspaceId
        self.projectId = projectId
        self.planningType = planningType
        self.title = title
        self.description = description
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId) ?? ""
        self.projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        self.planningType = try container.decodeIfPresent(TaskPlanningType.self, forKey: .planningType) ?? .fast
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

public struct FitsSettings: Codable, Equatable, Sendable {
    public var selectedWorkspaceIds: [String]
    public var preferredAgent: String?
    public var theme: String
    public var enabledToolIds: [String]

    private enum CodingKeys: String, CodingKey {
        case selectedWorkspaceIds
        case preferredAgent
        case theme
        case enabledToolIds
    }

    public init(
        selectedWorkspaceIds: [String] = [],
        preferredAgent: String? = nil,
        theme: String = "dark",
        enabledToolIds: [String] = []
    ) {
        self.selectedWorkspaceIds = selectedWorkspaceIds
        self.preferredAgent = preferredAgent
        self.theme = theme
        self.enabledToolIds = enabledToolIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.selectedWorkspaceIds = try container.decodeIfPresent([String].self, forKey: .selectedWorkspaceIds) ?? []
        self.preferredAgent = try container.decodeIfPresent(String.self, forKey: .preferredAgent)
        self.theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "dark"
        self.enabledToolIds = try container.decodeIfPresent([String].self, forKey: .enabledToolIds) ?? []
    }
}

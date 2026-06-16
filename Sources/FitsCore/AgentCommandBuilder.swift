import Foundation

public enum AgentCommandBuilder {
    public static func missingRequiredDirectories(
        repositoryPath: String,
        writableDirectories: [String],
        directoryExists: (String) -> Bool
    ) -> [String] {
        ([repositoryPath] + writableDirectories)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !directoryExists($0) }
    }

    public static func codexStartArguments(
        repositoryPath: String,
        writableDirectories: [String] = [],
        prompt: String? = nil
    ) -> [String] {
        var arguments = [
            "exec",
            "--cd",
            repositoryPath,
            "--skip-git-repo-check",
            "--dangerously-bypass-approvals-and-sandbox"
        ]

        if let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            arguments.append(prompt)
        }
        return arguments
    }

    public static func codexResumeArguments(
        repositoryPath: String,
        writableDirectories: [String] = [],
        externalSessionId: String?,
        prompt: String
    ) -> [String] {
        var arguments = [
            "exec",
            "resume",
            "--skip-git-repo-check",
            "--dangerously-bypass-approvals-and-sandbox",
        ]

        let cleanSessionId = externalSessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanSessionId, !cleanSessionId.isEmpty {
            arguments.append(cleanSessionId)
        } else {
            arguments.append("--last")
        }
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanPrompt.isEmpty {
            arguments.append(cleanPrompt)
        }
        return arguments
    }

    public static func claudeStartArguments() -> [String] {
        []
    }

    public static func claudeResumeArguments(externalSessionId: String?, prompt: String) -> [String] {
        let cleanSessionId = externalSessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanSessionId, !cleanSessionId.isEmpty {
            return ["--resume", cleanSessionId]
        }
        return ["--continue"]
    }
}

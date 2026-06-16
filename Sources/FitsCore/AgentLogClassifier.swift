import Foundation

public enum AgentOutputStream: Sendable, Hashable {
    case stdout
    case stderr

    public var displayName: String {
        switch self {
        case .stdout: "stdout"
        case .stderr: "stderr"
        }
    }
}

public enum AgentLogClassifier {
    public static func visibleText(from line: String) -> String {
        var output = line
        let escape = "\u{001B}"
        let patterns = [
            "\(escape)\\][^\u{0007}\(escape)]*(?:\u{0007}|\(escape)\\\\)",
            "\(escape)\\[[0-?]*[ -/]*[@-~]",
            "\(escape)[()][A-Za-z0-9]",
            "\(escape)[=><][0-9;]*[A-Za-z]?",
            "\(escape)[78]"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: "")
            }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func classify(
        toolId: String,
        stream: AgentOutputStream,
        line: String
    ) -> PipelineEventLevel? {
        let trimmed = visibleText(from: line)
        guard !trimmed.isEmpty else { return nil }

        if toolId == "codex", isCodexNoise(trimmed) {
            return nil
        }

        if stream == .stdout {
            if toolId == "codex", (isCodexPromptEcho(trimmed) || isCodexRunMetadata(trimmed)) {
                return nil
            }
            if containsError(trimmed) {
                return .error
            }
            if containsWarning(trimmed) {
                return .warn
            }
            return .info
        }

        if toolId == "codex" {
            if isCodexRunMetadata(trimmed) {
                return .info
            }
        }

        if containsError(trimmed) {
            return .error
        }
        if containsWarning(trimmed) {
            return .warn
        }
        return .info
    }

    private static func isCodexNoise(_ line: String) -> Bool {
        line.contains("codex_core_skills::loader: ignoring interface.icon_") ||
            line.contains("codex_core_plugins::manifest: ignoring interface.defaultPrompt") ||
            line.contains("codex_core_plugins::marketplace: skipping") ||
            line.contains("codex_core_plugins::manager: failed to auto-upgrade") ||
            line.contains("rmcp::transport::worker: worker quit with fatal: Transport channel closed, when AuthRequired") ||
            line.contains("rmcp::transport::worker: worker quit with fatal: Transport channel closed, when Auth(AuthorizationRequired)") ||
            line.contains("rmcp::transport::auth: Token refresh not possible") ||
            line.contains("failed to initialize MCP client during shutdown") ||
            line == "hook: SessionStart" ||
            line == "hook: SessionStart Completed" ||
            line.contains("must resolve under plugin assets/")
    }

    public static func isCodexPromptEcho(_ line: String) -> Bool {
        visibleText(from: line).count == 1
    }

    private static func isCodexRunMetadata(_ line: String) -> Bool {
        line == "OpenAI Codex v0.140.0" ||
            line == "--------" ||
            line == "user" ||
            line == "Reading additional input from stdin..." ||
            line == "tokens used" ||
            line.range(of: #"^[0-9,]+$"#, options: .regularExpression) != nil ||
            line.hasPrefix("workdir: ") ||
            line.hasPrefix("model: ") ||
            line.hasPrefix("provider: ") ||
            line.hasPrefix("approval: ") ||
            line.hasPrefix("sandbox: ") ||
            line.hasPrefix("reasoning effort: ") ||
            line.hasPrefix("reasoning summaries: ") ||
            line.hasPrefix("session id: ")
    }

    private static func containsError(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.contains(" error ") ||
            lowercased.hasPrefix("error:") ||
            lowercased.contains("fatal") ||
            lowercased.contains("authorization required")
    }

    private static func containsWarning(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.contains(" warn ") ||
            lowercased.hasPrefix("warn:") ||
            lowercased.contains("warning")
    }
}

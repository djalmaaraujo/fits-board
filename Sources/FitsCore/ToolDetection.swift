import Foundation

public struct DetectedTool: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable {
        case installed
        case missing
    }

    public var id: String
    public var displayName: String
    public var commandName: String
    public var status: Status
    public var path: String?
    public var detail: [String: String]

    public init(
        id: String,
        displayName: String,
        commandName: String,
        status: Status,
        path: String?,
        detail: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.commandName = commandName
        self.status = status
        self.path = path
        self.detail = detail
    }
}

public enum ToolDetection {
    public static func detectInstalledTools() -> [DetectedTool] {
        detect(
            pathEntries: ProcessInfo.processInfo.environment["PATH", default: ""].split(separator: ":").map(String.init),
            executableExists: { FileManager.default.isExecutableFile(atPath: $0) },
            appExists: { FileManager.default.isExecutableFile(atPath: $0) },
            codexAuthData: { try? Data(contentsOf: defaultCodexAuthURL()) }
        )
    }

    public static func detect(
        pathEntries: [String],
        executableExists: (String) -> Bool,
        appExists: (String) -> Bool,
        codexAuthData: () -> Data? = { nil }
    ) -> [DetectedTool] {
        [
            detectTool(
                id: "claude",
                displayName: "Claude Code",
                commandName: "claude",
                pathEntries: pathEntries,
                knownAppPaths: [
                    "/Applications/Claude.app/Contents/MacOS/Claude",
                    "/Applications/Claude Code.app/Contents/MacOS/Claude Code"
                ],
                executableExists: executableExists,
                appExists: appExists
            ),
            detectCodexTool(
                id: "codex",
                displayName: "Codex",
                commandName: "codex",
                pathEntries: pathEntries,
                knownAppPaths: [
                    "/Applications/Codex.app/Contents/Resources/codex",
                    "/Applications/Codex.app/Contents/MacOS/Codex"
                ],
                executableExists: executableExists,
                appExists: appExists,
                codexAuthData: codexAuthData
            ),
            detectTool(
                id: "gemini",
                displayName: "Gemini CLI",
                commandName: "gemini",
                pathEntries: pathEntries,
                knownAppPaths: [],
                executableExists: executableExists,
                appExists: appExists
            ),
            detectTool(
                id: "opencode",
                displayName: "OpenCode",
                commandName: "opencode",
                pathEntries: pathEntries,
                knownAppPaths: [],
                executableExists: executableExists,
                appExists: appExists
            ),
            detectTool(
                id: "cursor-agent",
                displayName: "Cursor Agent",
                commandName: "cursor-agent",
                pathEntries: pathEntries,
                knownAppPaths: [
                    "/Applications/Cursor.app/Contents/Resources/app/bin/cursor-agent"
                ],
                executableExists: executableExists,
                appExists: appExists
            ),
            detectTool(
                id: "aider",
                displayName: "Aider",
                commandName: "aider",
                pathEntries: pathEntries,
                knownAppPaths: [],
                executableExists: executableExists,
                appExists: appExists
            ),
            detectTool(
                id: "goose",
                displayName: "Goose",
                commandName: "goose",
                pathEntries: pathEntries,
                knownAppPaths: [
                    "/Applications/Goose.app/Contents/MacOS/Goose"
                ],
                executableExists: executableExists,
                appExists: appExists
            )
        ].sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .installed
            }
            return lhs.displayName < rhs.displayName
        }
    }

    private static func detectTool(
        id: String,
        displayName: String,
        commandName: String,
        pathEntries: [String],
        knownAppPaths: [String],
        executableExists: (String) -> Bool,
        appExists: (String) -> Bool
    ) -> DetectedTool {
        for entry in pathEntries {
            let path = URL(fileURLWithPath: entry).appendingPathComponent(commandName).path
            if executableExists(path) {
                return DetectedTool(
                    id: id,
                    displayName: displayName,
                    commandName: commandName,
                    status: .installed,
                    path: path
                )
            }
        }

        for path in knownAppPaths where appExists(path) {
            return DetectedTool(
                id: id,
                displayName: displayName,
                commandName: commandName,
                status: .installed,
                path: path
            )
        }

        return DetectedTool(
            id: id,
            displayName: displayName,
            commandName: commandName,
            status: .missing,
            path: nil
        )
    }

    private static func detectCodexTool(
        id: String,
        displayName: String,
        commandName: String,
        pathEntries: [String],
        knownAppPaths: [String],
        executableExists: (String) -> Bool,
        appExists: (String) -> Bool,
        codexAuthData: () -> Data?
    ) -> DetectedTool {
        let binary = detectTool(
            id: id,
            displayName: displayName,
            commandName: commandName,
            pathEntries: pathEntries,
            knownAppPaths: knownAppPaths,
            executableExists: executableExists,
            appExists: appExists
        )
        if binary.status == .installed {
            return binary
        }
        guard let auth = codexAuthData(),
              let detail = parseCodexAuthDetail(auth) else {
            return binary
        }
        return DetectedTool(
            id: id,
            displayName: displayName,
            commandName: commandName,
            status: .installed,
            path: "~/.codex/auth.json",
            detail: detail
        )
    }

    private static func defaultCodexAuthURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
    }

    private static func parseCodexAuthDetail(_ data: Data) -> [String: String]? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["auth_mode"] as? String == "chatgpt",
            let tokens = json["tokens"] as? [String: Any],
            tokens["access_token"] as? String != nil,
            tokens["refresh_token"] as? String != nil
        else {
            return nil
        }

        var detail: [String: String] = ["source": "codex-auth"]
        if let idToken = tokens["id_token"] as? String,
           let claims = decodeJWTClaims(idToken) {
            if let profile = claims["https://api.openai.com/profile"] as? [String: Any],
               let email = profile["email"] as? String {
                detail["email"] = email
            } else if let email = claims["email"] as? String {
                detail["email"] = email
            }

            if let auth = claims["https://api.openai.com/auth"] as? [String: Any],
               let plan = auth["chatgpt_plan_type"] as? String {
                detail["plan"] = plan
            }
        }
        return detail
    }

    private static func decodeJWTClaims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = payload.count % 4
        if padding > 0 {
            payload += String(repeating: "=", count: 4 - padding)
        }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

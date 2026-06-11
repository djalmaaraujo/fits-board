import XCTest
@testable import FitsCore

final class ToolDetectionTests: XCTestCase {
    private func jwt(claims: [String: Any]) throws -> String {
        let headerData = try JSONSerialization.data(withJSONObject: ["alg": "RS256", "typ": "JWT"])
        let payloadData = try JSONSerialization.data(withJSONObject: claims)
        return [
            headerData.base64URLEncodedString(),
            payloadData.base64URLEncodedString(),
            "fake-signature"
        ].joined(separator: ".")
    }

    func testDetectsToolsFromPathAndKnownApplicationLocations() {
        let tools = ToolDetection.detect(
            pathEntries: [
                "/usr/bin",
                "/Users/cooper/.local/bin"
            ],
            executableExists: { path in
                path == "/Users/cooper/.local/bin/claude"
            },
            appExists: { path in
                path == "/Applications/Codex.app/Contents/Resources/codex"
            }
        )

        XCTAssertEqual(tools.first(where: { $0.id == "claude" })?.status, .installed)
        XCTAssertEqual(tools.first(where: { $0.id == "claude" })?.path, "/Users/cooper/.local/bin/claude")
        XCTAssertEqual(tools.first(where: { $0.id == "codex" })?.status, .installed)
        XCTAssertEqual(tools.first(where: { $0.id == "codex" })?.path, "/Applications/Codex.app/Contents/Resources/codex")
    }

    func testReportsMissingTools() {
        let tools = ToolDetection.detect(
            pathEntries: ["/usr/bin"],
            executableExists: { _ in false },
            appExists: { _ in false }
        )

        XCTAssertEqual(tools.first(where: { $0.id == "claude" })?.status, .missing)
        XCTAssertEqual(tools.first(where: { $0.id == "codex" })?.status, .missing)
    }

    func testDetectsAdditionalCodingAgentsFromPath() {
        let tools = ToolDetection.detect(
            pathEntries: ["/opt/homebrew/bin"],
            executableExists: { path in
                [
                    "/opt/homebrew/bin/gemini",
                    "/opt/homebrew/bin/opencode",
                    "/opt/homebrew/bin/cursor-agent",
                    "/opt/homebrew/bin/aider",
                    "/opt/homebrew/bin/goose"
                ].contains(path)
            },
            appExists: { _ in false }
        )

        XCTAssertEqual(tools.first(where: { $0.id == "gemini" })?.status, .installed)
        XCTAssertEqual(tools.first(where: { $0.id == "opencode" })?.status, .installed)
        XCTAssertEqual(tools.first(where: { $0.id == "cursor-agent" })?.status, .installed)
        XCTAssertEqual(tools.first(where: { $0.id == "aider" })?.status, .installed)
        XCTAssertEqual(tools.first(where: { $0.id == "goose" })?.status, .installed)
    }

    func testDetectsCodexLocalAuthWithoutExposingTokens() throws {
        let access = try jwt(claims: ["exp": Int(Date().timeIntervalSince1970) + 3600])
        let idToken = try jwt(claims: [
            "https://api.openai.com/profile": ["email": "user@example.com"],
            "https://api.openai.com/auth": ["chatgpt_plan_type": "pro"]
        ])
        let auth = """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "\(access)",
            "refresh_token": "refresh-secret",
            "account_id": "acct-123"
          }
        }
        """.data(using: .utf8)!

        let tools = ToolDetection.detect(
            pathEntries: [],
            executableExists: { _ in false },
            appExists: { _ in false },
            codexAuthData: { auth }
        )

        let codex = try XCTUnwrap(tools.first(where: { $0.id == "codex" }))
        XCTAssertEqual(codex.status, .installed)
        XCTAssertEqual(codex.path, "~/.codex/auth.json")
        XCTAssertEqual(codex.detail["email"], "user@example.com")
        XCTAssertEqual(codex.detail["plan"], "pro")
        XCTAssertNil(codex.detail["access_token"])
        XCTAssertNil(codex.detail["refresh_token"])
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

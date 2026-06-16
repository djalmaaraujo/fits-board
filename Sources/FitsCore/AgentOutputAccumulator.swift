import Foundation

public struct AgentOutputAccumulator: Sendable {
    private var buffer = ""
    private let maximumBufferedCharacters = 12_000

    public init() {}

    public mutating func append(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        buffer += text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines: [String] = []

        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let rawLine = String(buffer[..<newlineIndex])
            if let stableLine = Self.stableLine(from: rawLine) {
                lines.append(stableLine)
            }
            buffer.removeSubrange(...newlineIndex)
        }

        if buffer.count > maximumBufferedCharacters {
            buffer = String(buffer.suffix(maximumBufferedCharacters))
        }

        return lines
    }

    public mutating func flush() -> [String] {
        defer { buffer = "" }
        guard let stableLine = Self.stableLine(from: buffer) else { return [] }
        return [stableLine]
    }

    private static func stableLine(from rawLine: String) -> String? {
        let segments = rawLine
            .split(separator: "\r", omittingEmptySubsequences: false)
            .map(String.init)
        let line = segments.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? rawLine
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import SwiftUI
import FitsCore

struct TaskInspectorPanelView: View {
    @EnvironmentObject private var model: AppModel

    let task: FitsTask

    private var column: BoardColumn {
        model.board.columns.first { $0.id == task.columnId } ?? BoardColumn.intake
    }

    private var run: TaskRun? {
        model.board.runs.first { $0.taskId == task.id }
    }

    private var project: FitsProject? {
        model.board.projects.first { $0.id == task.projectId }
    }

    private var workspace: FitsWorkspace? {
        model.board.workspaces.first { $0.id == task.workspaceId }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            Rectangle().fill(Color.fitsLine).frame(height: 1)
            tabBody
        }
        .frame(width: 820)
        .frame(maxHeight: .infinity)
        .background(Color.fitsChrome)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.fitsLine, lineWidth: 1))
        .shadow(color: .black.opacity(0.38), radius: 28, x: -12, y: 0)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: workspace?.colorHex ?? "#64748b"))
                            .frame(width: 9, height: 9)
                        Text("\(workspace?.displayName ?? task.workspaceId) / \(project?.name ?? task.projectId)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.fitsMuted)
                            .lineLimit(1)
                    }

                    Text(task.title)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(Color.fitsText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                StageIcon(column: column)

                Button {
                    model.closeTaskInspector()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.fitsMuted)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                InspectorChip(title: column.name, systemImage: iconName(for: column), tint: column.kind == .agent ? .fitsAccent : .fitsMuted)
                InspectorChip(title: environmentTitle, systemImage: "server.rack", tint: Color(hex: "#2f8cff"))
                if let agent = task.metatag["agent"] ?? firstTool {
                    InspectorChip(title: agent, systemImage: "cpu", tint: .fitsAccent)
                }
                InspectorChip(title: branchTitle, systemImage: "arrow.triangle.branch", tint: .fitsMuted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(TaskInspectorTab.allCases) { tab in
                    Button {
                        model.inspectorTab = tab
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                            Text(tab.title)
                            if tab == .logs, !displayEvents.isEmpty {
                                Text("\(displayEvents.count)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.fitsMuted)
                            }
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(model.inspectorTab == tab ? Color.fitsText : Color.fitsMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(model.inspectorTab == tab ? Color.fitsAccent : .clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        switch model.inspectorTab {
        case .details:
            TaskInspectorDetailsView(task: task, column: column)
        case .logs:
            TaskInspectorLogsView(
                task: task,
                events: run?.events ?? [],
                session: run?.agentSession,
                isRunning: model.runningTaskIds.contains(task.id)
            )
        case .agents:
            TaskInspectorAgentsView(contract: PipelineStageContract.contract(for: column), run: run)
        case .prompts:
            TaskInspectorPromptsView(task: task, column: column)
        case .meta:
            TaskInspectorMetaView(task: task, run: run)
        case .repos:
            TaskInspectorReposView(project: project)
        }
    }

    private var firstTool: String? {
        PipelineStageContract.contract(for: column).tools.first
    }

    private var displayEvents: [PipelineEvent] {
        LogDisplayPolicy.visibleEvents(run?.events ?? [], verbosity: .concise)
    }

    private var environmentTitle: String {
        column.kind == .agent ? "Local CLI" : "Local"
    }

    private var branchTitle: String {
        project?.repositories.first?.defaultBranch ?? task.metatag["branch"] ?? "main"
    }

    private func iconName(for column: BoardColumn) -> String {
        switch column.id {
        case BoardColumn.spec.id: "clipboard"
        case BoardColumn.plan.id: "point.3.connected.trianglepath.dotted"
        case BoardColumn.agentQA.id: "shield.lefthalf.filled"
        case BoardColumn.review.id: "eye"
        case BoardColumn.draftDelivery.id: "doc.text"
        case BoardColumn.humanReview.id: "person.2"
        case BoardColumn.done.id: "paperplane"
        default: "tray.full"
        }
    }
}

private struct StageIcon: View {
    let column: BoardColumn

    var body: some View {
        Image(systemName: column.kind == .agent ? "cpu" : "square.stack.3d.up")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(column.kind == .agent ? Color.fitsAccent : Color.fitsMuted)
            .frame(width: 46, height: 46)
            .background((column.kind == .agent ? Color.fitsAccent : Color.fitsMuted).opacity(0.14))
            .clipShape(Circle())
            .overlay(Circle().stroke(column.kind == .agent ? Color.fitsAccent : Color.fitsLine, lineWidth: 2))
    }
}

private struct InspectorChip: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TaskInspectorLogsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var verbosity: LogVerbosity = .concise
    @State private var rawTerminalTail: TaskLogTail?

    let task: FitsTask
    let events: [PipelineEvent]
    let session: AgentSession?
    let isRunning: Bool

    var body: some View {
        VStack(spacing: 0) {
            logHeader

            Rectangle().fill(Color.fitsLine).frame(height: 1)

            logScroll

            Rectangle().fill(Color.fitsLine).frame(height: 1)

            logFooter
        }
        .onAppear {
            reloadRawTerminalTailIfNeeded()
        }
        .onChange(of: events.count) { _, _ in
            reloadRawTerminalTailIfNeeded()
        }
        .onChange(of: verbosity) { _, _ in
            reloadRawTerminalTailIfNeeded()
        }
    }

    private var logHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(isRunning ? Color.fitsAccent : Color.fitsMuted)
                    .frame(width: 7, height: 7)
                Text(isRunning ? "Agent running" : "Auto-starts when entering executable stages")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(isRunning ? Color.fitsAccent : Color.fitsMuted)
            }

            Spacer()

            if !isRunning, session != nil {
                FitsButton(title: "Resume", systemImage: "play.fill", variant: .secondary, size: .compact) {
                    model.resumeCurrentStage(for: task)
                }
                .foregroundStyle(Color.fitsAccent)
            }

            if isRunning {
                Button {
                    model.stopCurrentStage(for: task)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Color(hex: "#ef4444"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#ef4444").opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.fitsChrome)
    }

    private var logScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if !hasDisplayableLogs {
                        Text("No pipeline logs yet. Move the task into a pipeline column to create run events.")
                            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.fitsMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                    } else {
                        if shouldShowRawTerminalLog {
                            ForEach(Array(rawTerminalLines.enumerated()), id: \.offset) { _, line in
                                RawLogLineView(text: line)
                            }
                        } else {
                            ForEach(Array(displayEvents.enumerated()), id: \.offset) { _, event in
                                LogLineView(event: event)
                            }
                        }
                        LogActivityCursorView(isRunning: isRunning)
                        Color.clear
                            .frame(height: 1)
                            .id(logTailAnchorId)
                    }
                }
                .padding(18)
            }
            .onAppear {
                scrollToLatestLog(proxy: proxy, animated: false)
            }
            .onChange(of: logAutoScrollToken) { _, _ in
                scrollToLatestLog(proxy: proxy, animated: true)
            }
        }
        .background(Color.black.opacity(0.58))
        .textSelection(.enabled)
    }

    private var logFooter: some View {
        HStack(spacing: 10) {
            Text(logScopeTitle)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.fitsMuted)
                .lineLimit(1)

            Spacer()

            FitsSegmentedControl(
                options: LogVerbosity.allCases,
                selection: $verbosity,
                title: { $0.title }
            )

            FitsButton(title: "Copy", systemImage: "doc.on.doc", variant: .secondary, size: .compact) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(logText, forType: .string)
                model.showCopiedLogsToast(for: task)
            }
            .disabled(!hasDisplayableLogs)

            FitsButton(title: "Open Log File", systemImage: "doc.text.magnifyingglass", variant: .secondary, size: .compact) {
                model.openTaskTerminalLog(for: task)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.fitsChrome)
    }

    private var displayEvents: [PipelineEvent] {
        LogDisplayPolicy.visibleEvents(events, verbosity: verbosity)
    }

    private var rawTerminalLines: [String] {
        LogDisplayPolicy.visibleRawLines(rawTerminalTail?.contents ?? "")
    }

    private var shouldShowRawTerminalLog: Bool {
        verbosity == .verbose && !rawTerminalLines.isEmpty
    }

    private var hasDisplayableLogs: Bool {
        shouldShowRawTerminalLog || !displayEvents.isEmpty
    }

    private var logText: String {
        if shouldShowRawTerminalLog {
            return rawTerminalLines.joined(separator: "\n")
        }
        return displayEvents.map(LogLineView.text(for:)).joined(separator: "\n")
    }

    private var logScopeTitle: String {
        if shouldShowRawTerminalLog {
            return rawTerminalTail?.isTruncated == true
                ? "Showing latest \(LogDisplayPolicy.maximumRenderedRawLines) terminal.log lines"
                : "Showing terminal.log"
        }
        return displayEvents.count >= LogDisplayPolicy.maximumRenderedEvents
            ? "Showing latest \(LogDisplayPolicy.maximumRenderedEvents) events"
            : "Showing \(displayEvents.count) events"
    }

    private var logAutoScrollToken: String {
        let latestEventMarker = displayEvents.last.map { "\($0.id)-\($0.timestamp.timeIntervalSinceReferenceDate)-\($0.message)" } ?? ""
        let latestRawMarker = rawTerminalLines.last ?? ""
        return "\(verbosity.rawValue)-\(displayEvents.count)-\(latestEventMarker)-\(rawTerminalLines.count)-\(latestRawMarker)-\(isRunning)"
    }

    private var logTailAnchorId: String {
        "log-tail-\(task.id)"
    }

    private func reloadRawTerminalTailIfNeeded() {
        guard verbosity == .verbose else { return }
        rawTerminalTail = model.taskTerminalLogTail(
            for: task,
            maximumLines: LogDisplayPolicy.maximumRenderedRawLines
        )
    }

    private func scrollToLatestLog(proxy: ScrollViewProxy, animated: Bool) {
        guard hasDisplayableLogs else { return }
        let action = {
            proxy.scrollTo(logTailAnchorId, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.16)) {
                action()
            }
        } else {
            action()
        }
    }
}

enum LogVerbosity: String, CaseIterable, Identifiable {
    case concise
    case verbose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .concise: "Concise"
        case .verbose: "Verbose"
        }
    }
}

enum LogDisplayPolicy {
    static let maximumRenderedEvents = 200
    static let maximumRenderedRawLines = 200
    private static let maximumScannedEvents = 1_000

    static func visibleEvents(_ events: [PipelineEvent], verbosity: LogVerbosity = .concise) -> [PipelineEvent] {
        let candidates = events.count > maximumScannedEvents ? Array(events.suffix(maximumScannedEvents)) : events
        let filtered = verbosity == .verbose ? candidates : candidates.filter(isConciseVisible)
        guard filtered.count > maximumRenderedEvents else { return filtered }
        return Array(filtered.suffix(maximumRenderedEvents))
    }

    static func visibleRawLines(_ text: String) -> [String] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .map(AgentLogClassifier.visibleText)
            .filter { !$0.isEmpty }
        guard lines.count > maximumRenderedRawLines else { return lines }
        return Array(lines.suffix(maximumRenderedRawLines))
    }

    private static func isConciseVisible(_ event: PipelineEvent) -> Bool {
        switch event.tool {
        case "Codex CLI stdout":
            return isConciseCodexLine(event.message, stream: .stdout, level: event.level)
        case "Codex CLI stderr":
            return isConciseCodexLine(event.message, stream: .stderr, level: event.level)
        default:
            return true
        }
    }

    private static func isConciseCodexLine(
        _ line: String,
        stream: AgentOutputStream,
        level: PipelineEventLevel
    ) -> Bool {
        let visibleLine = AgentLogClassifier.visibleText(from: line)
        guard AgentLogClassifier.classify(toolId: "codex", stream: stream, line: visibleLine) != nil else {
            return false
        }

        if level == .error || level == .warn {
            return true
        }

        return !isCodexInternalTranscriptLine(visibleLine)
    }

    private static func isCodexInternalTranscriptLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        if trimmed == "codex" ||
            trimmed == "exec" ||
            trimmed == "succeeded in 0ms:" ||
            trimmed == "succeeded in 1ms:" ||
            trimmed == "```" ||
            trimmed == "---" ||
            trimmed == "/quit" ||
            trimmed == "turn interrupted" {
            return true
        }

        if trimmed.hasPrefix("/bin/zsh -lc ") ||
            trimmed.hasPrefix("name: ") ||
            trimmed.hasPrefix("description: ") ||
            trimmed.hasPrefix("# Verification Before Completion") ||
            trimmed.hasPrefix("## Overview") ||
            trimmed.hasPrefix("## The Iron Law") ||
            trimmed.hasPrefix("## Common Failures") ||
            trimmed.hasPrefix("## Red Flags") ||
            trimmed.hasPrefix("## Rationalization Prevention") ||
            trimmed.hasPrefix("## Key Patterns") ||
            trimmed.hasPrefix("## Why This Matters") ||
            trimmed.hasPrefix("## When To Apply") ||
            trimmed.hasPrefix("diff --git ") ||
            trimmed.hasPrefix("index ") ||
            trimmed.hasPrefix("new file mode ") ||
            trimmed.hasPrefix("deleted file mode ") ||
            trimmed.hasPrefix("--- ") ||
            trimmed.hasPrefix("+++ ") ||
            trimmed.hasPrefix("@@ ") ||
            trimmed.hasPrefix("+FITS_STAGE_DONE_") ||
            trimmed.hasPrefix("FITS_STAGE_DONE_") ||
            trimmed.hasPrefix("|") ||
            trimmed.hasPrefix("✅") ||
            trimmed.hasPrefix("❌") {
            return true
        }

        return trimmed.contains("/.codex/plugins/") ||
            trimmed.contains("/skills/verification-before-completion/") ||
            trimmed.contains("NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE") ||
            trimmed.contains("codex_otel::events::session_telemetry")
    }
}

enum LogActivityCursor {
    static func text(isRunning: Bool, tick: Int) -> String {
        guard isRunning else { return "..." }

        return switch tick % 3 {
        case 0: "."
        case 1: ".."
        default: "..."
        }
    }
}

private struct LogActivityCursorView: View {
    let isRunning: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { context in
            Text(LogActivityCursor.text(isRunning: isRunning, tick: tick(for: context.date)))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(isRunning ? Color.fitsAccent : Color(hex: "#8b5cf6"))
                .padding(.top, 2)
                .animation(.easeInOut(duration: 0.18), value: isRunning)
        }
    }

    private func tick(for date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate / 0.45)
    }
}

private struct LogLineView: View {
    let event: PipelineEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Self.timeFormatter.string(from: event.timestamp))
                .foregroundStyle(Color.fitsMuted.opacity(0.72))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 70, alignment: .leading)
            Text(event.level.displayName)
                .foregroundStyle(levelColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 42, alignment: .leading)
            Text(message)
                .foregroundStyle(Color.fitsText.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
        .lineSpacing(4)
    }

    private var message: String {
        if let tool = event.tool {
            return "\(tool) :: \(event.message)"
        }
        return event.message
    }

    static func text(for event: PipelineEvent) -> String {
        let toolPrefix = event.tool.map { "\($0) :: " } ?? ""
        return "\(timeFormatter.string(from: event.timestamp)) \(event.level.displayName) \(toolPrefix)\(event.message)"
    }

    private var levelColor: Color {
        switch event.level {
        case .info: Color(hex: "#60a5fa")
        case .run: Color(hex: "#8b5cf6")
        case .ok: Color.fitsAccent
        case .warn: Color(hex: "#f59e0b")
        case .error: Color(hex: "#ef4444")
        case .system: Color.fitsMuted
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct RawLogLineView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.fitsText.opacity(0.9))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TaskInspectorDetailsView: View {
    let task: FitsTask
    let column: BoardColumn

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                InspectorSectionTitle("Description")
                Text(task.description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.fitsText.opacity(0.92))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.fitsPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fitsLine, lineWidth: 1))

                InspectorSectionTitle("Stage Contract")
                ContractRows(contract: PipelineStageContract.contract(for: column))
            }
            .padding(18)
        }
        .background(Color.fitsBackground)
    }
}

private struct TaskInspectorAgentsView: View {
    let contract: PipelineStageContract
    let run: TaskRun?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                InspectorSectionTitle("Allowed Tools")
                ForEach(contract.tools, id: \.self) { tool in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.fitsAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.fitsText)
                            Text(run?.status.rawValue ?? "ready")
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.fitsMuted)
                        }
                        Spacer()
                    }
                    .padding(11)
                    .background(Color.fitsPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fitsLine, lineWidth: 1))
                }
            }
            .padding(18)
        }
        .background(Color.fitsBackground)
    }
}

private struct TaskInspectorPromptsView: View {
    @EnvironmentObject private var model: AppModel
    let task: FitsTask
    let column: BoardColumn

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let prompts = model.taskPromptFiles(for: task)
                if prompts.isEmpty {
                    InspectorSectionTitle("Column Prompt Preview")
                    ArtifactTextPreview(title: "current-stage-preview", subtitle: "Not persisted yet", contents: prompt)
                } else {
                    InspectorSectionTitle("Prompt History")
                    ForEach(prompts) { prompt in
                        ArtifactTextPreview(title: prompt.name, subtitle: prompt.path, contents: prompt.contents)
                    }
                }
            }
            .padding(18)
        }
        .background(Color.fitsBackground)
    }

    private var prompt: String {
        let contract = PipelineStageContract.contract(for: column)
        return """
        You are executing the \(column.name) stage for task \(task.id).
        Respect this stage only. Do not skip ahead.
        Required output: \(contract.requiredOutput).
        Allowed tools: \(contract.tools.joined(separator: ", ")).
        """
    }
}

private struct TaskInspectorMetaView: View {
    @EnvironmentObject private var model: AppModel
    let task: FitsTask
    let run: TaskRun?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                InspectorSectionTitle("Metatag")
                KeyValueRows(values: task.metatag)

                InspectorSectionTitle("Run")
                KeyValueRows(values: [
                    "run_id": run?.id ?? "not_started",
                    "status": run?.status.rawValue ?? "not_started",
                    "events": "\(run?.events.count ?? 0)"
                ])

                InspectorSectionTitle("Agent Session")
                KeyValueRows(values: sessionValues)

                let artifacts = model.taskGeneratedArtifacts(for: task)
                if !artifacts.isEmpty {
                    InspectorSectionTitle("Generated Artifacts")
                    ForEach(artifacts) { artifact in
                        ArtifactTextPreview(title: artifact.name, subtitle: artifact.path, contents: artifact.contents)
                    }
                }
            }
            .padding(18)
        }
        .background(Color.fitsBackground)
    }

    private var sessionValues: [String: String] {
        guard let session = run?.agentSession else {
            return ["session": "not_started"]
        }

        return [
            "fits_session_id": session.id,
            "tool": session.toolDisplayName,
            "external_session_id": session.externalSessionId ?? "pending",
            "resume_command": session.resumeCommand,
            "status": session.status.rawValue
        ]
    }
}

private struct TaskInspectorReposView: View {
    let project: FitsProject?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                InspectorSectionTitle("Repositories")
                ForEach(project?.repositories ?? []) { repo in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(repo.name)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.fitsText)
                            Spacer()
                            Text(repo.defaultBranch)
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(hex: "#60a5fa"))
                        }
                        Text(repo.path)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.fitsMuted)
                            .lineLimit(2)
                    }
                    .padding(11)
                    .background(Color.fitsPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fitsLine, lineWidth: 1))
                }

                if project?.repositories.isEmpty ?? true {
                    Text("No repositories attached to this project.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.fitsMuted)
                }
            }
            .padding(18)
        }
        .background(Color.fitsBackground)
    }
}

private struct ContractRows: View {
    let contract: PipelineStageContract

    var body: some View {
        KeyValueRows(values: [
            "tools": contract.tools.joined(separator: ", "),
            "entry": contract.entryMessage,
            "output": contract.requiredOutput
        ])
    }
}

private struct ArtifactTextPreview: View {
    let title: String
    let subtitle: String
    let contents: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.fitsText)
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.fitsMuted)
                .lineLimit(2)

            Text(contents)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.fitsText.opacity(0.9))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.black.opacity(0.36))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(12)
        .background(Color.fitsPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fitsLine, lineWidth: 1))
    }
}

private struct KeyValueRows: View {
    let values: [String: String]

    var body: some View {
        let sortedPairs = values.sorted { $0.key < $1.key }

        VStack(spacing: 0) {
            ForEach(sortedPairs, id: \.key) { key, value in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(key)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.fitsMuted)
                        .textCase(.uppercase)
                        .frame(width: 116, alignment: .leading)
                    Text(value)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.fitsText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
                if key != sortedPairs.last?.key {
                    Rectangle().fill(Color.fitsLine.opacity(0.75)).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 10)
        .background(Color.fitsPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fitsLine, lineWidth: 1))
    }
}

private struct InspectorSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.fitsMuted)
            .textCase(.uppercase)
            .tracking(0.7)
    }
}

import SwiftUI
import FitsCore

struct TerminalPanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inspector
            Rectangle().fill(Color.fitsLine).frame(height: 1)
            tools
            Rectangle().fill(Color.fitsLine).frame(height: 1)
            terminal
        }
        .background(Color.fitsPanel)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Task")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.fitsMuted)

            if let task = model.selectedTask {
                Text(task.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(task.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fitsMuted)
                    .lineLimit(3)
                LabeledContent("Workspace", value: model.workspaceName(task.workspaceId))
                    .font(.system(size: 12))
                LabeledContent("Project", value: model.projectName(task.projectId))
                    .font(.system(size: 12))
                LabeledContent("Column", value: task.columnId)
                    .font(.system(size: 12))

                HStack(spacing: 6) {
                    DetailBadge(title: "spec", color: .fitsAccent)
                    DetailBadge(title: "local", color: .fitsMuted)
                    DetailBadge(title: "draft", color: .fitsMuted)
                }
            } else {
                Text("Select a task to inspect it.")
                    .foregroundStyle(Color.fitsMuted)
            }
        }
        .padding(14)
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Agents")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.fitsMuted)
                Spacer()
                Button {
                    model.refreshTools()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }

            ForEach(model.detectedTools) { tool in
                HStack(spacing: 8) {
                    Circle()
                        .fill(tool.status == .installed ? Color.fitsAccent : Color.fitsMuted)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.displayName)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tool.path ?? "Not found")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color.fitsMuted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        model.startAgent(tool)
                    } label: {
                        Text("Start")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.fitsText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.fitsElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.fitsLine, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(tool.status != .installed)
                }
            }
        }
        .padding(14)
    }

    private var terminal: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Terminal")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.fitsMuted)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.terminalLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(line.hasPrefix("$") ? Color.fitsAccent : Color.fitsText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fitsLine, lineWidth: 1))
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct DetailBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.fitsElevated)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.fitsLine, lineWidth: 1))
    }
}

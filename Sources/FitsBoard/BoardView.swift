import SwiftUI
import FitsCore

struct BoardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            topNavigation
            Rectangle()
                .fill(Color.fitsLine)
                .frame(height: 1)
            controlPlaneBar
            Rectangle()
                .fill(Color.fitsLine)
                .frame(height: 1)
            boardScroll
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.fitsBackground)
        .foregroundStyle(Color.fitsText)
        .sheet(item: $model.activeSheet) { sheet in
            switch sheet {
            case .workspace:
                WorkspaceFormView()
            case .project:
                ProjectFormView()
            case .task:
                TaskFormView()
            case .taskDetail:
                TaskDetailEditorView()
            case .preferences:
                PreferencesView()
            }
        }
        .alert("Fits", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var topNavigation: some View {
        HStack(spacing: 11) {
            LogoMark()
            Text("FITS·BOARD")
                .font(.system(size: 12.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.fitsText)
                .tracking(1.1)

            Text("WORKSPACES")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.fitsMuted.opacity(0.68))
                .tracking(1.4)
                .padding(.leading, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    WorkspaceNavChip(
                        title: "All",
                        count: model.board.tasks.count,
                        colorHex: "#2f8cff",
                        isSelected: model.selectedWorkspaceIds.isEmpty,
                        dotted: true
                    ) {
                        model.showAllWorkspaces()
                    }

                    ForEach(model.board.workspaces) { workspace in
                        WorkspaceNavChip(
                            title: workspace.displayName,
                            count: model.board.tasks.filter { $0.workspaceId == workspace.id }.count,
                            colorHex: workspace.colorHex,
                            isSelected: model.selectedWorkspaceIds.contains(workspace.id),
                            dotted: false
                        ) {
                            model.toggleWorkspace(workspace.id)
                        }
                    }
                }
            }
            .frame(maxWidth: 860)

            Spacer(minLength: 12)

            SearchBox(text: $model.searchQuery)
                .frame(width: 285)

            IconSquare(systemImage: "gearshape") {
                model.activeSheet = .preferences
            }

            FitsButton(title: "New project", systemImage: "plus", size: .header) {
                model.activeSheet = .project
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Color.fitsChrome)
    }

    private var controlPlaneBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.fitsMuted)
            Text("Control Plane")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.fitsText)
            Text(model.selectedWorkspaceIds.isEmpty ? "all workspaces" : "\(model.selectedWorkspaceIds.count) selected")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.fitsMuted)
                .tracking(0.5)

            Spacer()

            StatPill(value: "\(model.visibleTasks.count)", label: "tasks")
            StatPill(value: "\(model.board.projects.count)", label: "projects")
            StatPill(value: "\(model.detectedTools.filter { $0.status == .installed }.count)", label: "agents live", dotColor: .fitsAccent)
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(Color.fitsBackground)
    }

    private var boardScroll: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(model.board.columns) { column in
                        KanbanColumnView(column: column, width: columnWidth(for: proxy.size.width))
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 15)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func columnWidth(for availableWidth: CGFloat) -> CGFloat {
        let count = CGFloat(max(model.board.columns.count, 1))
        let chrome: CGFloat = 28 + (count - 1) * 14
        let raw = (availableWidth - chrome) / count
        return min(314, max(246, raw))
    }
}

private struct KanbanColumnView: View {
    @EnvironmentObject private var model: AppModel
    let column: BoardColumn
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                ColumnIcon(systemImage: iconName, tint: columnAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(column.name)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Color.fitsText)
                    Text(columnSubtitle)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(column.kind == .agent ? Color.fitsAccent.opacity(0.95) : Color.fitsMuted.opacity(0.8))
                        .textCase(.uppercase)
                }
                Spacer()
                ColumnCountBadge(count: model.filteredTasks(for: column).count)
                SmallHeaderButton(systemImage: "plus") {
                    model.activeSheet = .task
                }
            }
            .frame(height: 32)

            if column.id == BoardColumn.intake.id {
                DraftComposerView()
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if model.filteredTasks(for: column).isEmpty {
                        EmptyColumnHint()
                    }
                    ForEach(model.filteredTasks(for: column)) { task in
                        TaskCardView(task: task)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(10)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.fitsPanel)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.fitsLine, lineWidth: 1)
        )
    }

    private var iconName: String {
        switch column.id {
        case BoardColumn.intake.id: "tray.full"
        case BoardColumn.spec.id: "clipboard"
        case BoardColumn.plan.id: "point.3.connected.trianglepath.dotted"
        case BoardColumn.agentQA.id: "shield.lefthalf.filled"
        case BoardColumn.review.id: "eye"
        case BoardColumn.draftDelivery.id: "doc.text"
        case BoardColumn.humanReview.id: "person.2"
        case BoardColumn.done.id: "paperplane"
        default: "circle.grid.2x2"
        }
    }

    private var columnAccent: Color {
        switch column.kind {
        case .agent: Color.fitsAccent
        case .done: Color(hex: "#2dd4bf")
        case .human: Color.fitsMuted
        }
    }

    private var columnSubtitle: String {
        switch column.id {
        case BoardColumn.intake.id: "Intake"
        case BoardColumn.spec.id: "Scoping"
        case BoardColumn.plan.id: "Agent"
        case BoardColumn.agentQA.id: "Agent"
        case BoardColumn.review.id: "Agent"
        case BoardColumn.draftDelivery.id: "Assemble"
        case BoardColumn.humanReview.id: "Approval"
        case BoardColumn.done.id: "Done"
        default: column.kind.rawValue
        }
    }
}

private struct EmptyColumnHint: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.fitsMuted.opacity(0.55))
            Text("drop task")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.fitsMuted.opacity(0.55))
                .textCase(.uppercase)
        }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(Color.black.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .foregroundStyle(Color.fitsLine.opacity(0.85))
            )
    }
}

private struct DraftComposerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.fitsMuted)
                Text("New intake")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.fitsMuted)
                    .textCase(.uppercase)
                Spacer()
            }

            CompactMenu(
                label: "Workspace",
                value: model.workspaceName(model.board.draftTask.workspaceId)
            ) {
                ForEach(model.board.workspaces) { workspace in
                    Button(workspace.displayName) {
                        model.updateDraft(workspaceId: workspace.id)
                    }
                }
            }

            CompactMenu(
                label: "Project",
                value: model.projectName(model.board.draftTask.projectId)
            ) {
                ForEach(model.projects(for: model.board.draftTask.workspaceId)) { project in
                    Button(project.name) {
                        model.updateDraft(projectId: project.id)
                    }
                }
            }

            CompactMenu(
                label: "Planning",
                value: model.board.draftTask.planningType.displayName
            ) {
                ForEach(TaskPlanningType.allCases) { planningType in
                    Button(planningType.displayName) {
                        model.updateDraft(planningType: planningType)
                    }
                }
            }

            Text(model.board.draftTask.planningType.description)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.fitsMuted.opacity(0.84))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Task title", text: Binding(
                get: { model.board.draftTask.title },
                set: { model.updateDraft(title: $0) }
            ))
            .font(.system(size: 12, weight: .medium))
            .textFieldStyle(.plain)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(Color.fitsElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.fitsLine, lineWidth: 1))

            TextField("Description", text: Binding(
                get: { model.board.draftTask.description },
                set: { model.updateDraft(description: $0) }
            ), axis: .vertical)
            .lineLimit(2...5)
            .font(.system(size: 12))
            .textFieldStyle(.plain)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(Color.fitsElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.fitsLine, lineWidth: 1))

            FitsButton(title: "Create Intake Task", systemImage: "doc.badge.plus", size: .fullWidth) {
                model.promoteDraft()
            }
        }
        .padding(9)
        .background(Color.fitsCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fitsLine, lineWidth: 1))
    }
}

private struct TaskCardView: View {
    @EnvironmentObject private var model: AppModel
    let task: FitsTask

    var body: some View {
        Button {
            model.openTaskEditor(task)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(workspaceColor)
                        .frame(width: 6, height: 6)
                    Text(model.projectName(task.projectId))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.fitsMuted.opacity(0.95))
                        .lineLimit(1)
                    Spacer()
                    if task.columnId == BoardColumn.done.id {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.fitsAccent)
                    }
                }

                Text(task.title)
                    .font(.system(size: 13.2, weight: .semibold))
                    .foregroundStyle(Color.fitsText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(task.description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.fitsMuted.opacity(0.9))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 6) {
                    MiniBadge(title: environmentLabel, systemImage: environmentIcon, tint: environmentTint)
                    MiniBadge(title: branchLabel, systemImage: "arrow.triangle.branch", tint: Color.fitsMuted)
                    Spacer(minLength: 4)
                    InitialAvatar(text: initials, color: workspaceColor)
                }

                if column.kind == .agent {
                    AgentProgressView(stageTitle: progressTitle, progress: progressValue)
                }
            }
            .padding(10)
            .background(model.selectedTaskId == task.id ? Color.fitsSelectedCard : Color.fitsCard)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(model.selectedTaskId == task.id ? Color.fitsAccent : Color.fitsLine, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(model.board.columns) { column in
                Button("Move to \(column.name)") {
                    model.moveTask(task, to: column)
                }
            }
        }
    }

    private var column: BoardColumn {
        model.board.columns.first { $0.id == task.columnId } ?? BoardColumn.intake
    }

    private var workspaceColor: Color {
        Color(hex: model.board.workspaces.first { $0.id == task.workspaceId }?.colorHex ?? "#64748b")
    }

    private var initials: String {
        let name = model.workspaceName(task.workspaceId)
        let pieces = name.split(separator: " ").prefix(2)
        let value = pieces.map { String($0.prefix(1)).uppercased() }.joined()
        return value.isEmpty ? "AI" : value
    }

    private var branchLabel: String {
        guard let project = model.board.projects.first(where: { $0.id == task.projectId }) else {
            return "main"
        }
        return project.repositories.first?.defaultBranch ?? "main"
    }

    private var environmentLabel: String {
        switch column.kind {
        case .agent: "Claude Remote"
        case .done: "VPS"
        case .human: task.columnId == BoardColumn.spec.id ? "Local" : "VPS"
        }
    }

    private var environmentIcon: String {
        column.kind == .agent ? "terminal" : "server.rack"
    }

    private var environmentTint: Color {
        switch column.kind {
        case .agent: Color(hex: "#8b5cf6")
        case .done: Color(hex: "#2563eb")
        case .human: task.columnId == BoardColumn.spec.id ? Color.fitsMuted : Color(hex: "#2563eb")
        }
    }

    private var progressTitle: String {
        switch task.columnId {
        case BoardColumn.plan.id: "Spawn agents"
        case BoardColumn.agentQA.id: "Unit"
        case BoardColumn.review.id: "Critique"
        default: "Agent pass"
        }
    }

    private var progressValue: Double {
        let scalars = task.id.unicodeScalars.map { Int($0.value) }.reduce(0, +)
        return Double(35 + (scalars % 55)) / 100
    }
}

private struct MiniBadge: View {
    let title: String
    let systemImage: String
    var tint: Color = .fitsMuted

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3.5)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .lineLimit(1)
    }
}

private struct FilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let colorHex: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 8, height: 8)
                Text(title)
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.fitsMuted)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.fitsAccent.opacity(0.18) : Color.fitsPanel)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.fitsAccent : Color.fitsLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ColumnIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(Color.fitsIconWell)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.fitsLine, lineWidth: 1))
    }
}

private struct ColumnCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.fitsMuted.opacity(0.9))
            .frame(minWidth: 23)
            .padding(.vertical, 4)
            .background(Color.fitsElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct SmallHeaderButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Color.fitsMuted.opacity(0.75))
                .frame(width: 22, height: 22)
                .background(Color.fitsElevated.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

private struct InitialAvatar: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
            .foregroundStyle(.black.opacity(0.78))
            .frame(width: 22, height: 22)
            .background(color)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
    }
}

private struct AgentProgressView: View {
    let stageTitle: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.fitsAccent)
                        .frame(width: 5, height: 5)
                    Text(stageTitle)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.fitsAccent)
                }
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.fitsMuted.opacity(0.8))
            }

            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < filledSegments ? Color.fitsAccent : Color.fitsAccent.opacity(0.16))
                        .frame(height: 4)
                }
            }
        }
        .padding(.top, 1)
    }

    private var filledSegments: Int {
        min(4, max(1, Int((progress * 4).rounded(.up))))
    }
}

private struct LogoMark: View {
    var body: some View {
        Text("F")
            .font(.system(size: 14, weight: .heavy, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: 25, height: 25)
            .background(Color(red: 0.05, green: 0.45, blue: 0.95))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}

private struct WorkspaceNavChip: View {
    let title: String
    let count: Int
    let colorHex: String
    let isSelected: Bool
    let dotted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.fitsText : Color.fitsMuted)
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.fitsMuted.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.fitsPanel)
            .clipShape(RoundedRectangle(cornerRadius: 999))
            .overlay {
                if dotted && isSelected {
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                        .foregroundStyle(Color(hex: colorHex))
                } else {
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(isSelected ? Color(hex: colorHex).opacity(0.8) : Color.fitsLine, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SearchBox: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.fitsMuted)
            TextField("Search tasks, projects, branches", text: $text)
                .font(.system(size: 12, weight: .medium))
                .textFieldStyle(.plain)
                .foregroundStyle(Color.fitsText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.fitsPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fitsLine, lineWidth: 1))
    }
}

private struct IconSquare: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.fitsMuted)
                .frame(width: 32, height: 32)
                .background(Color.fitsPanel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fitsLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct StatPill: View {
    let value: String
    let label: String
    var dotColor: Color?

    var body: some View {
        HStack(spacing: 7) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
            }
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.fitsText)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.fitsMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.fitsPanel)
        .clipShape(RoundedRectangle(cornerRadius: 999))
    }
}

private struct ToolbarPill: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.fitsText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.fitsElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.fitsLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct CompactMenu<Content: View>: View {
    let label: String
    let value: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 7) {
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.fitsMuted)
                    .frame(width: 58, alignment: .leading)
                Text(value.isEmpty ? "None" : value)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.fitsText)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.fitsMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.fitsElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.fitsLine, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }
}

extension Color {
    static let fitsChrome = Color(red: 0.026, green: 0.026, blue: 0.028)
    static let fitsBackground = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let fitsPanel = Color(red: 0.086, green: 0.086, blue: 0.086)
    static let fitsCard = Color(red: 0.122, green: 0.122, blue: 0.122)
    static let fitsSelectedCard = Color(red: 0.07, green: 0.132, blue: 0.103)
    static let fitsElevated = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let fitsIconWell = Color(red: 0.122, green: 0.122, blue: 0.122)
    static let fitsLine = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let fitsText = Color(red: 0.92, green: 0.93, blue: 0.95)
    static let fitsMuted = Color(red: 0.50, green: 0.54, blue: 0.60)
    static let fitsAccent = Color(red: 0.13, green: 0.77, blue: 0.37)

    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

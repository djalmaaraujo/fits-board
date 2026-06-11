import AppKit
import SwiftUI
import FitsCore

struct WorkspaceFormView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var displayName = ""
    @State private var commitEmail = ""

    var body: some View {
        ModalSurface(title: "New workspace", subtitle: "Identity") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledField("Name", text: $name, placeholder: "personal")
                LabeledField("Display Name", text: $displayName, placeholder: "Personal")
                LabeledField("Commit E-mail", text: $commitEmail, placeholder: "you@example.com")
            }
        } footer: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.fitsMuted)
            PrimaryActionButton(title: "Save Workspace", systemImage: "checkmark") {
                model.addWorkspace(
                    name: name,
                    displayName: displayName.isEmpty ? name : displayName,
                    commitEmail: commitEmail
                )
                dismiss()
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(width: 440)
    }
}

struct PreferencesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWorkspaceId = ""
    @State private var name = ""
    @State private var displayName = ""
    @State private var commitEmail = ""
    @State private var workspacePendingRemoval: FitsWorkspace?

    var body: some View {
        ModalSurface(title: "Preferences", subtitle: "Workspaces and local agents") {
            HStack(alignment: .top, spacing: 16) {
                workspaceSidebar
                VStack(alignment: .leading, spacing: 16) {
                    workspaceEditor
                    Divider().overlay(Color.fitsLine)
                    agentsEditor
                }
            }
        } footer: {
            Button("Close") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.fitsMuted)
            PrimaryActionButton(title: "Save Workspace", systemImage: "checkmark") {
                model.updateWorkspace(
                    id: selectedWorkspaceId,
                    name: name,
                    displayName: displayName,
                    commitEmail: commitEmail
                )
            }
            .disabled(selectedWorkspaceId.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(width: 860)
        .onAppear(perform: loadInitialWorkspace)
        .onChange(of: selectedWorkspaceId) { _, newValue in
            loadWorkspace(newValue)
        }
        .alert("Remove workspace?", isPresented: Binding(
            get: { workspacePendingRemoval != nil },
            set: { if !$0 { workspacePendingRemoval = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                workspacePendingRemoval = nil
            }
            Button("Remove", role: .destructive) {
                guard let workspace = workspacePendingRemoval else { return }
                model.removeWorkspace(id: workspace.id)
                workspacePendingRemoval = nil
                selectedWorkspaceId = model.board.workspaces.first?.id ?? ""
                loadWorkspace(selectedWorkspaceId)
            }
        } message: {
            Text(removalMessage)
        }
    }

    private var workspaceSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORKSPACES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.fitsMuted)
                .tracking(1.2)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.board.workspaces) { workspace in
                        Button {
                            selectedWorkspaceId = workspace.id
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: workspace.colorHex))
                                    .frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(workspace.displayName)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(Color.fitsText)
                                    Text(workspace.name)
                                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.fitsMuted)
                                }
                                Spacer()
                                Text("\(model.projects(for: workspace.id).count)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.fitsMuted)
                            }
                            .padding(9)
                            .background(selectedWorkspaceId == workspace.id ? Color.fitsSelectedCard : Color.fitsPanel)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(selectedWorkspaceId == workspace.id ? Color.fitsAccent : Color.fitsLine, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                let number = model.board.workspaces.count + 1
                model.addWorkspace(name: "workspace-\(number)", displayName: "Workspace \(number)", commitEmail: "")
                selectedWorkspaceId = model.board.workspaces.last?.id ?? selectedWorkspaceId
            } label: {
                Label("Add workspace", systemImage: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.fitsElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .frame(width: 220)
    }

    private var workspaceEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SectionTitle(title: "Workspace identity", subtitle: "Used for task ownership and git commits")
                Spacer()
                Button(role: .destructive) {
                    workspacePendingRemoval = selectedWorkspace
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.system(size: 11.5, weight: .bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.red.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.red.opacity(0.9))
                .disabled(selectedWorkspace == nil)
            }
            LabeledField("Name", text: $name, placeholder: "linkana")
            LabeledField("Display Name", text: $displayName, placeholder: "Linkana")
            LabeledField("Commit E-mail", text: $commitEmail, placeholder: "dev@company.com")
        }
    }

    private var agentsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "Coding agents", subtitle: "Detected locally, activated explicitly")
                Spacer()
                Button {
                    model.refreshTools()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.fitsMuted)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 10)], spacing: 10) {
                ForEach(model.detectedTools) { tool in
                    ToolPreferenceRow(tool: tool)
                }
            }
        }
    }

    private func loadInitialWorkspace() {
        let preferred = model.selectedWorkspaceIds.first ?? model.board.draftTask.workspaceId
        selectedWorkspaceId = model.board.workspaces.contains { $0.id == preferred }
            ? preferred
            : (model.board.workspaces.first?.id ?? "")
        loadWorkspace(selectedWorkspaceId)
    }

    private func loadWorkspace(_ id: String) {
        guard let workspace = model.board.workspaces.first(where: { $0.id == id }) else { return }
        name = workspace.name
        displayName = workspace.displayName
        commitEmail = workspace.commitEmail
    }

    private var selectedWorkspace: FitsWorkspace? {
        model.board.workspaces.first { $0.id == selectedWorkspaceId }
    }

    private var removalMessage: String {
        guard let workspace = workspacePendingRemoval else {
            return ""
        }
        let projectIds = Set(model.board.projects.filter { $0.workspaceId == workspace.id }.map(\.id))
        let taskCount = model.board.tasks.filter { $0.workspaceId == workspace.id || projectIds.contains($0.projectId) }.count
        return "This removes \(workspace.displayName), \(projectIds.count) projects, and \(taskCount) tasks from Fits Board."
    }
}

struct ProjectFormView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var workspaceId = ""
    @State private var name = ""
    @State private var repositories: [RepositoryDraft] = []

    var body: some View {
        ModalSurface(title: "New project", subtitle: "Attach one or more git repositories") {
            VStack(alignment: .leading, spacing: 14) {
                Menu {
                    ForEach(model.board.workspaces) { workspace in
                        Button(workspace.displayName) {
                            workspaceId = workspace.id
                        }
                    }
                } label: {
                    MenuField(label: "Workspace", value: model.workspaceName(workspaceId))
                }

                LabeledField("Project Name", text: $name, placeholder: "Customer Portal")

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionTitle(title: "Repositories", subtitle: "Folders on this Mac")
                        Spacer()
                        Button(action: chooseRepositoryFolders) {
                            Label("Add folder", systemImage: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.fitsElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }

                    if repositories.isEmpty {
                        EmptyRepositoryHint(action: chooseRepositoryFolders)
                    } else {
                        ForEach($repositories) { $repo in
                            RepositoryDraftRow(repo: $repo) {
                                repositories.removeAll { $0.id == repo.id }
                            }
                        }
                    }
                }
            }
        } footer: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.fitsMuted)
            PrimaryActionButton(title: "Save Project", systemImage: "folder.badge.plus") {
                model.addProject(
                    workspaceId: workspaceId,
                    name: name,
                    repositories: repositories.map {
                        FitsRepository(
                            name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                            path: $0.path.trimmingCharacters(in: .whitespacesAndNewlines),
                            defaultBranch: $0.defaultBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "main" : $0.defaultBranch
                        )
                    }
                )
                dismiss()
            }
            .disabled(!canSave)
        }
        .frame(width: 620)
        .onAppear {
            workspaceId = workspaceId.isEmpty ? (model.board.workspaces.first?.id ?? "") : workspaceId
        }
    }

    private var canSave: Bool {
        !workspaceId.isEmpty &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        repositories.contains { !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func chooseRepositoryFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            for url in panel.urls {
                guard !repositories.contains(where: { $0.path == url.path }) else { continue }
                repositories.append(
                    RepositoryDraft(
                        name: url.lastPathComponent,
                        path: url.path,
                        defaultBranch: "main"
                    )
                )
            }
        }
    }
}

struct TaskFormView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var workspaceId = ""
    @State private var projectId = ""
    @State private var title = ""
    @State private var description = ""

    var body: some View {
        ModalSurface(title: "New task", subtitle: "Title and description are required") {
            VStack(alignment: .leading, spacing: 12) {
                Menu {
                    ForEach(model.board.workspaces) { workspace in
                        Button(workspace.displayName) {
                            workspaceId = workspace.id
                            projectId = model.projects(for: workspace.id).first?.id ?? ""
                        }
                    }
                } label: {
                    MenuField(label: "Workspace", value: model.workspaceName(workspaceId))
                }

                Menu {
                    ForEach(model.projects(for: workspaceId)) { project in
                        Button(project.name) {
                            projectId = project.id
                        }
                    }
                } label: {
                    MenuField(label: "Project", value: model.projectName(projectId))
                }

                LabeledField("Title", text: $title, placeholder: "Draft the migration spec")
                LabeledField("Description", text: $description, placeholder: "What needs to be done?", axis: .vertical)
            }
        } footer: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.fitsMuted)
            PrimaryActionButton(title: "Save Task", systemImage: "checkmark") {
                model.addTask(
                    title: title,
                    description: description,
                    workspaceId: workspaceId,
                    projectId: projectId
                )
                dismiss()
            }
            .disabled(!canSave)
        }
        .frame(width: 520)
        .onAppear {
            workspaceId = model.board.draftTask.workspaceId.isEmpty
                ? (model.board.workspaces.first?.id ?? "")
                : model.board.draftTask.workspaceId
            projectId = model.board.draftTask.projectId.isEmpty
                ? (model.projects(for: workspaceId).first?.id ?? "")
                : model.board.draftTask.projectId
        }
    }

    private var canSave: Bool {
        !workspaceId.isEmpty &&
        !projectId.isEmpty &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct RepositoryDraft: Identifiable {
    let id = UUID()
    var name: String
    var path: String
    var defaultBranch: String
}

private struct ToolPreferenceRow: View {
    @EnvironmentObject private var model: AppModel
    let tool: DetectedTool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tool.status == .installed ? Color.fitsAccent : Color.fitsMuted.opacity(0.35))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.fitsText)
                Text(subtitle)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.fitsMuted)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { model.isToolEnabled(tool.id) },
                set: { model.setTool(tool, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(tool.status == .missing)
        }
        .padding(10)
        .background(Color.fitsPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fitsLine, lineWidth: 1))
    }

    private var subtitle: String {
        if tool.status == .missing {
            return "missing"
        }
        if let email = tool.detail["email"] {
            return email
        }
        return tool.path ?? "installed"
    }
}

private struct RepositoryDraftRow: View {
    @Binding var repo: RepositoryDraft
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(Color.fitsAccent)
                TextField("Repository name", text: $repo.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.fitsMuted)
            }
            LabeledField("Path", text: $repo.path, placeholder: "/Users/cooper/dev/project")
            LabeledField("Default Branch", text: $repo.defaultBranch, placeholder: "main")
        }
        .padding(10)
        .background(Color.fitsPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.fitsLine, lineWidth: 1))
    }
}

private struct EmptyRepositoryHint: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.fitsAccent)
                Text("Add repository folders")
                    .font(.system(size: 12.5, weight: .bold))
                Text("A project can orchestrate work across multiple git repositories.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.fitsMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(Color.fitsPanel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(Color.fitsLine))
        }
        .buttonStyle(.plain)
    }
}

private struct ModalSurface<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.fitsText)
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.fitsMuted)
                        .textCase(.uppercase)
                }
                Spacer()
            }
            .padding(16)

            Rectangle().fill(Color.fitsLine).frame(height: 1)

            content()
                .padding(16)

            Rectangle().fill(Color.fitsLine).frame(height: 1)

            HStack {
                Spacer()
                footer()
            }
            .padding(14)
        }
        .background(Color.fitsBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.fitsLine, lineWidth: 1))
    }
}

private struct SectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.fitsText)
            Text(subtitle)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.fitsMuted)
        }
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var axis: Axis = .horizontal

    init(_ label: String, text: Binding<String>, placeholder: String, axis: Axis = .horizontal) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.axis = axis
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.fitsMuted)
                .textCase(.uppercase)
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.fitsText)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.fitsCard)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.fitsLine, lineWidth: 1))
        }
    }
}

private struct MenuField: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.fitsMuted)
                    .textCase(.uppercase)
                Text(value.isEmpty ? "None" : value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.fitsText)
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.fitsMuted)
        }
        .padding(10)
        .background(Color.fitsCard)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.fitsLine, lineWidth: 1))
    }
}

private struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black.opacity(0.86))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

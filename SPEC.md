# Fits Board Live Spec

This is the living product specification for Fits Board.

The spec says **what** the product is, what concepts exist, and what behavior matters.
The code says **how** those concepts are implemented.

When the product changes, update this file so future agents can understand the current truth without reading a historical pile of plans.

## Product

Fits Board is a native macOS control plane for coordinating AI production work across many workspaces, projects, repositories, tasks, and local coding agents.

The product direction is an AI production pipeline:

1. Capture work through task intake.
2. Create or refine a specification for the task.
3. Write execution plans.
4. Fan work out across one or more repositories.
5. Run local or remote coding agents.
6. Review, QA, and ship results.

## Live Spec Principle

Fits Board uses a live spec instead of versioned planning artifacts.

- `SPEC.md` describes product concepts and required behavior.
- Source code, tests, and scripts describe implementation.
- Planning notes under `docs/superpowers/` are temporary working memory and must not be committed.
- When an agent changes a product concept, it must check whether the change still matches this spec.
- If the concept changes, the agent must update this spec in the same change.
- If code and spec disagree, the agent must say so before continuing and then resolve the mismatch.

## Current MVP

The current app is a SwiftUI macOS application with:

- A dark native kanban board inspired by the original Fits Board HTML mockup.
- Offline-first JSON persistence in `~/.fits-board/`.
- Workspace filters in the top navigation.
- Task intake through the Backlog creation dialog.
- Workspaces with `name`, `displayName`, `commitEmail`, color, and project references.
- Projects with one or more local git repositories.
- Tasks with title, description, workspace, project, column, creation time, and update time.
- Preferences for workspace management and local coding-agent activation.
- Local coding-agent detection for Claude Code, Codex, Gemini CLI, OpenCode, Cursor Agent, Aider, and Goose.
- Toast feedback for discrete user actions such as creating tasks, adding projects, removing workspaces, moving tasks, and refreshing agents.

## Core Concepts

### Workspace

A workspace groups projects and tasks by work context.

A workspace has:

- `name`: stable machine-oriented identifier.
- `displayName`: human-facing label.
- `commitEmail`: git identity email to use for work in that workspace.
- `colorHex`: workspace accent color.
- `projectIds`: projects owned by the workspace.

Workspace management lives in Preferences.

Removing a workspace removes its projects and tasks from Fits Board, clears dead filters, and moves the draft task to the next valid workspace/project when possible.

### Project

A project belongs to one workspace and can contain multiple git repositories.

A project has:

- `workspaceId`
- `name`
- `repositories`

Project creation must allow adding more than one local repository folder through native macOS folder selection.

### Repository

A repository points to a local git working folder.

A repository has:

- `name`
- `path`
- `defaultBranch`

The repository model is intentionally simple until execution orchestration needs richer git metadata.

### Task

A task represents work to move through the board.

A task must always have:

- title
- description
- workspace
- project
- planning type
- metatag object

Tasks start in the intake/backlog flow and can move through board columns.

Each task must have a stable Markdown representation inside the Fits Board configuration folder. This file is a human-readable live task artifact, not an exported report.

The task Markdown path must follow this pattern:

```text
~/.fits-board/workspaces/<workspace-name-or-id>/projects/<project-name-or-id>/<task-title-slug-or-id>.md
```

The Markdown file must be updated whenever Fits Board creates or edits the task fields that belong to the backlog/intake definition. This keeps the task saved as the user writes and gives future agents a durable file to read before planning.

### Task Metatag

Each task has a `metatag` object for execution metadata that agents and later pipeline stages can write and read.

The current MVP stores metatag values as string key/value pairs. Examples include `agent`, `branch`, `environment`, `progress`, `started`, or other execution-specific markers.

Metatag is not part of the user's backlog definition. It can be added or updated across columns while the task moves through the pipeline. The task detail dialog must make the metatag object visible on every task, and task Markdown should include a `## Metatag` section when the object is not empty.

### Planning Type

Planning type tells Fits Board how much planning ceremony the user wants before agents execute a task.

Current planning types:

- `Fast (auto)`: Fits Board plans for the user and may attempt the task without asking clarifying questions.
- `LLM Plan Mode`: Fits Board delegates to the regular plan mode of the selected LLM/coding agent.
- `Superpowers Skill`: Fits Board expects a guided Superpowers planning flow that asks questions and writes plans into the repository.

`Fast (auto)` is the default for new and legacy tasks.

The planning type is part of the task definition. It must be persisted in task JSON, shown in task creation/editing UI, and written into the task Markdown artifact.

Planning type is editable only while a task is in Backlog. Once a task moves to Planning or any later column, the task detail dialog must show planning type as read-only metadata so the chosen production path does not drift after intake.

### Draft Task

The draft task is the autosaved intake form state.

It stores:

- selected workspace
- selected project
- planning type
- title
- description
- updated time

The draft should never point at removed workspace/project ids after destructive workspace changes.

### Board Columns

The current board columns are:

- Backlog
- Planning
- Agent Fan out
- Agent QA
- Agent Review
- Draft Delivery
- Human Review
- Ship it

The agent columns are conceptual placeholders for future orchestration. They should remain visible even before execution is implemented.

### Backlog Column

Backlog is the intake column and the first stage of the production pipeline.

Backlog owns the initial definition of the task:

- workspace
- project
- planning type
- title
- description

The backlog editor must make description writing comfortable. Opening a task from the board should show a centered task detail dialog with enough space to write and revise the description.

Task creation happens through the New Task dialog. The dialog can be opened from the Backlog column `+` button or with `Command-N`. Columns after Backlog must not show a task-creation `+` button, because new work always enters through intake.

Backlog must not contain a fixed embedded "new intake" form. The board column should show backlog tasks and empty/drop hints only; all creation fields live in the modal dialog.

Backlog task edits must update both structured JSON persistence and the task Markdown file under the workspace/project path. The Markdown artifact is the live written task definition that agents can use as input for later spec and planning stages.

Workspace, project, planning type, and description are editable only while a task is in Backlog. Once the task moves to Planning or any later column, the task detail dialog must show workspace, project, planning type, and description as read-only task definition data. Title remains editable as the concise board label, but the production routing, planning path, and written task definition should not drift after the task leaves intake.

The task detail dialog has a left-side task lifecycle action. While the task is in Backlog, the action is `Delete` and removes the task from the board. After the task leaves Backlog, deleting is no longer available; the same position becomes `Stop`, which represents stopping the task in the production pipeline. In the current MVP, `Stop` only shows a toast saying `Tarefa parada na pipeline`.

### Toast Feedback

Fits Board should acknowledge discrete user actions with a small toast in the bottom-right corner of the main window.

Toast feedback is for completed actions such as adding a task, adding a project, saving or removing a workspace, moving a task, refreshing agents, or toggling an agent. Continuous autosave typing should not produce toasts.

### Modal Skeleton

Fits Board modals use a shared native skeleton so layout does not drift between forms.

Each modal should have:

- a header with title, subtitle, and an `X` close button on the top-right
- content in the middle
- a footer with the secondary or destructive action on the left
- the primary commit action on the right

`Escape` and the header `X` should close the modal. Cancel/close buttons may still appear in the left footer slot when useful, but they must not be grouped beside the save button on the right.

### Coding Agent

A coding agent is a locally detected tool that Fits Board may later launch, embed, or orchestrate.

Current detected agent ids:

- `claude`
- `codex`
- `gemini`
- `opencode`
- `cursor-agent`
- `aider`
- `goose`

Agent activation currently means:

- the agent is detected locally,
- the user toggles it on in Preferences,
- the enabled id is persisted in `settings.json`.

Activation does not yet mean the app has embedded PTY execution.

Codex can also be detected through `~/.codex/auth.json` when it contains usable ChatGPT-mode OAuth data. UI-facing detection must never expose tokens.

## Persistence

Fits Board persists data under:

```text
~/.fits-board/
```

Current files:

- `settings.json`
- `workspaces.json`
- `projects.json`
- `tasks.json`
- `draft-task.json`
- `workspaces/**/projects/**/*.md`

Persistence must remain backward compatible. When a model gains a field, existing JSON files should continue to decode with sensible defaults.

## Native App Requirements

Fits Board is intentionally not an Electron/web app.

The app shell must remain:

- native macOS,
- SwiftUI-based,
- offline-first,
- fast to launch,
- comfortable for dense operational workflows.

Modal and dialog calls to action should use the shared Fits default button style: a white primary button for the main action and an inverted dark secondary button for cancel/close actions. New modal CTAs should reuse the shared button component instead of creating one-off button styling.

External scripts or helper processes are allowed for local agent orchestration and terminal/session bridging.

## Known Gaps

- Embedded PTY execution is not complete.
- Agent activation is stored but not yet connected to a live terminal session.
- `fits-agent-host` is still a small helper and should be expanded or replaced as orchestration becomes real.
- Release packaging is local/debug-oriented and not yet signed/notarized.

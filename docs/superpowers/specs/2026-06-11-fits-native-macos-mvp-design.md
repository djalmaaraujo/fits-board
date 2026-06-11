# Fits Native macOS MVP Design

## Decision

Fits MVP will be a fully native macOS application. It will avoid HTML, CSS, React, Electron, and Tauri. The app will use SwiftUI for the main interface, AppKit where native macOS behavior needs more control, and a small Go helper for local agent and terminal orchestration.

## User Questions Answered

- Stack preference: native macOS, no web stack.
- External execution boundary: only AI agents and local scripts run outside the app UI.
- Terminal access: allowed, and Go helper code can own pseudo-terminal details.
- First version scope: basic kanban, workspace/project/task creation, filtering, and real local persistence.
- Agent orchestration depth: detect and display local Claude/Codex availability now; defer full task execution orchestration.

## MVP Requirements

1. Build a macOS-native Fits board application.
2. Persist offline-first state in `~/.fits-board`.
3. Include workspace CRUD with `name`, `displayName`, `commitEmail`, and project membership.
4. Include project CRUD with workspace association and repository metadata.
5. Include task CRUD with required `title`, `description`, `workspaceId`, and `projectId`.
6. Show a kanban board with at least: Intake, Spec, Plan, In Progress, Review, Done.
7. Filter board tasks by all, one, or multiple workspaces.
8. Provide an autosaving task composer in the first column.
9. Detect local Claude and Codex installations.
10. Show an internal terminal panel that can start an interactive agent command through a local helper, without API keys and without prompt-mode shortcuts such as `claude -p`.

## Architecture

The repository is a Swift Package with a native executable target and a testable core library target. `FitsCore` owns models, JSON persistence, validation, filtering, and tool detection. `FitsBoard` owns the SwiftUI/AppKit app. `fits-agent-host` is a Go command that can detect tools and start an interactive command in a pseudo-terminal-oriented process boundary.

## Storage

The MVP writes human-readable JSON files under `~/.fits-board`:

- `settings.json`
- `workspaces.json`
- `projects.json`
- `tasks.json`
- `draft-task.json`

Writes are atomic: encode to a temporary file and rename into place. The app creates default data on first launch so the board opens to a useful state.

## UI

The UI follows the attached Fits Board mockup in spirit: dark, dense, control-plane-like, workspace chips across the top, horizontal kanban columns, compact cards, right-side detail/terminal panel, and native macOS toolbar/menu affordances. It will not attempt pixel parity in v1.

## Non-Goals

- No web frontend.
- No cloud sync.
- No API-key-based agent calls.
- No automated spec/plan generation execution pipeline yet.
- No production-grade terminal multiplexer in the first pass.

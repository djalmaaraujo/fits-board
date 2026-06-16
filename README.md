# Fits Board

Fits Board is a native macOS control plane for coordinating AI production work across workspaces, projects, repositories, tasks, and local coding agents.

It is intentionally not a web app. The app shell is SwiftUI, offline-first, and built for dense operational workflows: create work, move it through a deterministic production pipeline, watch local agents run, inspect logs and artifacts, then review and ship.

## What Works Today

- Native macOS SwiftUI kanban board.
- Offline-first persistence under `~/.fits-board/`.
- Workspace filters in the top navigation.
- Workspace management with name, display name, commit email, color, and projects.
- Projects with one or more local repository or folder paths.
- Task intake through the Backlog `+` button or `Command-N`.
- Tasks with title, description, workspace, project, planning type, and metatag object.
- Backlog task autosave to JSON and Markdown task artifacts.
- Read-only routing fields after a task leaves Backlog.
- Pipeline columns with deterministic stage contracts.
- Automatic stage start when a task enters an executable column.
- Local agent execution through the `fits-agent-host` Go helper.
- PTY-backed Codex CLI execution for local subscription-based workflows.
- Structured task run events and terminal-style logs.
- Concise and verbose log modes.
- Log tailing so huge task logs do not block the UI.
- Copy and open-log-file actions from the task inspector.
- Persisted prompt history per stage.
- Persisted agent session metadata for resume support.
- Task metatag updates from agent-written `metatag.json`.
- Task-scoped artifacts under each task artifact folder.
- Local coding-agent detection for Claude Code, Codex, Gemini CLI, OpenCode, Cursor Agent, Aider, and Goose.
- Toast feedback for discrete actions.

## Pipeline

The current board columns are:

1. Backlog
2. Planning
3. Agent Fan out
4. Agent QA
5. Agent Review
6. Human Review
7. Ship it

Backlog is the human intake stage. Planning and the agent columns are automated stages. Human Review is the first deliberate human checkpoint.

Current stage contracts:

- **Backlog**: create and edit the task definition.
- **Planning**: prepare context, assumptions, target artifacts, verification commands, and open questions. Planning must not perform the requested work.
- **Agent Fan out**: break the work into executable pieces and perform the work. Parallel sub-agents may be used later when supported.
- **Agent QA**: verify that the original task objective was satisfied with automated checks when available and manual checks when needed.
- **Agent Review**: perform a strong review and prepare pull request guidance when a git repository is involved.
- **Human Review**: wait for a human approval decision.
- **Ship it**: local shipping/release checklist work.

When an automated stage succeeds, Fits Board moves the task to the next stage. Failed or stopped stages do not auto-advance.

## Task Artifacts

Fits Board writes task context under:

```text
~/.fits-board/workspaces/<workspace-name-or-id>/projects/<project-name-or-id>/<task-title-slug-or-id>/
```

Current files inside a task artifact folder:

- `task.md`: the task definition copied into the task folder.
- `events.ndjson`: structured pipeline events.
- `terminal.log`: terminal-style output for reading and tailing.
- `session.json`: local agent session metadata.
- `prompt-<stage>.md`: the exact prompt sent to the PTY-backed agent for a stage.
- `stage-done-<stage>.txt`: deterministic stage completion marker.
- `metatag.json`: optional agent-written string metadata imported back into the task.
- `artifacts/`: optional task-scoped reports, generated notes, QA evidence, or other outputs.

Fits Board also stores the task definition Markdown beside the task folder:

```text
~/.fits-board/workspaces/<workspace-name-or-id>/projects/<project-name-or-id>/<task-title-slug-or-id>.md
```

## Persistence

The main offline JSON files live under `~/.fits-board/`:

- `settings.json`
- `workspaces.json`
- `projects.json`
- `tasks.json`
- `runs.json`
- `draft-task.json`

The task artifact folder is the durable agent-facing context. The global run index exists for faster app loading, but the task folder is the important place to inspect execution history.

## Requirements

- macOS 14 or newer.
- Xcode command line tools with Swift 6 support.
- Go, for the `fits-agent-host` helper.
- Optional: local coding CLIs such as Codex or Claude Code.

Install command line tools if needed:

```sh
xcode-select --install
```

## Install And Run

Build the app bundle:

```sh
./scripts/package_app.sh
```

Open it:

```sh
open .build/Fits.app
```

The package script builds the Swift app and bundles the Go helper at:

```text
.build/Fits.app/Contents/Resources/fits-agent-host
```

## Development

Build the Swift package:

```sh
swift build
```

Run the Swift tests:

```sh
swift test
```

Run the Go helper tests:

```sh
cd cmd/fits-agent-host
go test ./...
```

Package the app:

```sh
./scripts/package_app.sh
```

## Project Layout

- `Sources/FitsCore/`: models, persistence, board logic, stage contracts, prompt building, log classification, and tool detection.
- `Sources/FitsBoard/`: SwiftUI macOS app and view models.
- `Tests/FitsCoreTests/`: core unit tests.
- `Tests/FitsBoardTests/`: app/model and inspector tests.
- `cmd/fits-agent-host/`: Go helper for PTY-backed local agent execution.
- `scripts/package_app.sh`: creates `.build/Fits.app`.
- `SPEC.md`: the living product specification.
- `AGENTS.md`: instructions for coding agents working in this repo.

## Coming Soon

- Richer interactive terminal controls inside the task inspector.
- Configurable execution permissions instead of the current broad local-agent power.
- Better resume UX for Claude Code and other agent CLIs.
- Rerun/history support beyond the current single active run per task.
- More complete Ship it behavior.
- Proper app signing, notarization, and release distribution.

## Notes

`SPEC.md` is the product truth. It says what Fits Board is; the source code says how it is implemented. When product concepts change, update `SPEC.md` in the same change.

Fits Board intentionally avoids Electron, HTML, CSS, and React for the app shell. External processes are reserved for coding agents and local helper scripts.

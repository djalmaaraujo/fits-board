# Fits Board

Fits Board is a native macOS control plane for coordinating AI work across many projects and repositories.

The current MVP is an offline-first Swift app with a kanban board, workspace/project/task management, local JSON persistence, and local coding-agent detection. The larger idea is to become a production line for AI projects: intake work, generate specs, fan out plans per repository, run coding agents, review output, and ship.

## Current MVP

- Native macOS app built with SwiftUI.
- Offline-first data under `~/.fits-board/`.
- Workspaces with name, display name, commit email, projects, and filters.
- Projects with one or more local git repository folders.
- Tasks with title, description, workspace, project, and board column.
- Preferences for managing workspaces and activating detected coding agents.
- Local coding-agent detection for Claude Code, Codex, Gemini CLI, OpenCode, Cursor Agent, Aider, and Goose.
- Codex auth detection through `~/.codex/auth.json`, inspired by Roomy's local-source approach.

## Coming Soon

- Embedded terminal sessions for activated agents.
- Agent orchestration from task intake to spec generation.
- Automatic planning that splits work per repository.
- Per-repository task fan-out and execution tracking.
- Review, QA, and delivery workflows with visible agent logs.
- Safer workspace deletion, archival, and import/export flows.
- Packaged releases with signing/notarization.

## Requirements

- macOS 14 or newer.
- Xcode command line tools with Swift 6 support.
- Go, for the `fits-agent-host` helper.

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

The app stores user data in:

```text
~/.fits-board/
```

The main files are:

- `settings.json`
- `workspaces.json`
- `projects.json`
- `tasks.json`
- `draft-task.json`

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

- `Sources/FitsCore/`: models, persistence, board logic, and tool detection.
- `Sources/FitsBoard/`: SwiftUI macOS app.
- `Tests/FitsCoreTests/`: unit tests for core behavior.
- `cmd/fits-agent-host/`: Go helper for local agent/terminal integration.
- `scripts/package_app.sh`: creates `.build/Fits.app`.
- `docs/superpowers/`: design and implementation planning notes.

## Notes

Fits Board intentionally avoids Electron, HTML, CSS, and React. The app UI is native macOS SwiftUI; external processes are reserved for coding agents and local helper scripts.

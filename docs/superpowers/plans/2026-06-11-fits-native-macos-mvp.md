# Fits Native macOS MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS MVP of Fits with offline JSON persistence, workspace/project/task CRUD, workspace filtering, autosaving intake task creation, local Claude/Codex detection, and a basic internal terminal panel.

**Architecture:** A Swift Package contains a testable `FitsCore` library and a `FitsBoard` SwiftUI executable. A Go helper command, `fits-agent-host`, provides local tool detection and command-launch plumbing for future PTY-backed agent sessions.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, Go 1.26, Codable JSON, macOS `Process`.

---

### Task 1: Project Scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/FitsCore/FitsModels.swift`
- Create: `Sources/FitsBoard/FitsBoardApp.swift`
- Create: `Tests/FitsCoreTests/FitsCoreTests.swift`
- Create: `cmd/fits-agent-host/go.mod`
- Create: `cmd/fits-agent-host/main.go`

- [ ] Create a Swift package with a `FitsCore` library, `FitsBoard` executable, and `FitsCoreTests` test target.
- [ ] Create a Go helper command in `cmd/fits-agent-host`.
- [ ] Run `swift test` and `go test ./...` to establish the baseline.

### Task 2: Core Models and Validation

**Files:**
- Modify: `Sources/FitsCore/FitsModels.swift`
- Test: `Tests/FitsCoreTests/FitsCoreTests.swift`

- [ ] Write tests proving tasks require title, description, workspace id, and project id.
- [ ] Implement workspace, project, task, board column, and draft task models.
- [ ] Verify tests fail before implementation and pass after implementation.

### Task 3: JSON Store

**Files:**
- Create: `Sources/FitsCore/FitsStore.swift`
- Test: `Tests/FitsCoreTests/FitsStoreTests.swift`

- [ ] Write tests proving the store creates `settings.json`, `workspaces.json`, `projects.json`, `tasks.json`, and `draft-task.json`.
- [ ] Implement atomic JSON load/save helpers.
- [ ] Implement default seed data on first load.

### Task 4: Board State

**Files:**
- Create: `Sources/FitsCore/BoardState.swift`
- Test: `Tests/FitsCoreTests/BoardStateTests.swift`

- [ ] Write tests for all-workspace, one-workspace, and multi-workspace filtering.
- [ ] Write tests for autosaving draft promotion into an Intake task.
- [ ] Implement filtering and draft promotion logic.

### Task 5: Tool Detection

**Files:**
- Create: `Sources/FitsCore/ToolDetection.swift`
- Test: `Tests/FitsCoreTests/ToolDetectionTests.swift`
- Modify: `cmd/fits-agent-host/main.go`

- [ ] Write Swift tests for injected PATH/app-location detection.
- [ ] Implement Claude/Codex detection without API calls.
- [ ] Implement Go helper `detect` command returning JSON.

### Task 6: Native UI MVP

**Files:**
- Modify: `Sources/FitsBoard/FitsBoardApp.swift`
- Create: `Sources/FitsBoard/AppModel.swift`
- Create: `Sources/FitsBoard/BoardView.swift`
- Create: `Sources/FitsBoard/WorkspaceProjectViews.swift`
- Create: `Sources/FitsBoard/TerminalPanelView.swift`

- [ ] Build the dark native shell with toolbar, workspace filters, columns, cards, and right-side panel.
- [ ] Add workspace, project, and task creation/edit forms.
- [ ] Add first-column autosaving draft composer.
- [ ] Wire UI actions to `FitsStore`.

### Task 7: Verification

**Commands:**
- `swift test`
- `swift build`
- `cd cmd/fits-agent-host && go test ./... && go build ./...`
- Run the app executable and inspect `~/.fits-board` files.

- [ ] Confirm tests and builds pass.
- [ ] Confirm local JSON files are created and updated.
- [ ] Confirm Claude and Codex detection is visible in the app.

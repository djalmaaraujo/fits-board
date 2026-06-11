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
- Task intake in the first kanban column.
- Workspaces with `name`, `displayName`, `commitEmail`, color, and project references.
- Projects with one or more local git repositories.
- Tasks with title, description, workspace, project, column, creation time, and update time.
- Preferences for workspace management and local coding-agent activation.
- Local coding-agent detection for Claude Code, Codex, Gemini CLI, OpenCode, Cursor Agent, Aider, and Goose.

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

Tasks start in the intake/backlog flow and can move through board columns.

Each task must have a stable Markdown representation inside the Fits Board configuration folder. This file is a human-readable live task artifact, not an exported report.

The task Markdown path must follow this pattern:

```text
~/.fits-board/workspaces/<workspace-name-or-id>/projects/<project-name-or-id>/<task-title-slug-or-id>.md
```

The Markdown file must be updated whenever Fits Board creates or edits the task fields that belong to the backlog/intake definition. This keeps the task saved as the user writes and gives future agents a durable file to read before planning.

### Draft Task

The draft task is the autosaved intake form state.

It stores:

- selected workspace
- selected project
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
- title
- description

The backlog editor must make description writing comfortable. Opening a task from the board should show a centered task detail dialog with enough space to write and revise the description.

Backlog task edits must update both structured JSON persistence and the task Markdown file under the workspace/project path. The Markdown artifact is the live written task definition that agents can use as input for later spec and planning stages.

Workspace and project are editable only while a task is in Backlog. Once the task moves to Planning or any later column, the task detail dialog must show workspace and project as read-only metadata. Title and description remain editable because the live task definition can still be clarified, but ownership and project routing should not drift after the task leaves intake.

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

External scripts or helper processes are allowed for local agent orchestration and terminal/session bridging.

## Known Gaps

- Embedded PTY execution is not complete.
- Agent activation is stored but not yet connected to a live terminal session.
- `fits-agent-host` is still a small helper and should be expanded or replaced as orchestration becomes real.
- Release packaging is local/debug-oriented and not yet signed/notarized.

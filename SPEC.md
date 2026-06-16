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
- Projects with one or more local repositories or work folders.
- Tasks with title, description, workspace, project, column, creation time, and update time.
- Task runs with structured pipeline events and terminal-style logs.
- Resumable agent-session metadata for tasks that launch local coding agents.
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

A repository points to a local working folder. Most production projects should use git working folders, but the MVP must also support local non-git folders for filesystem-oriented tasks and early project setup.

A repository has:

- `name`
- `path`
- `defaultBranch`

The repository model is intentionally simple until execution orchestration needs richer git metadata. When a local coding agent requires a trusted git directory, Fits Board should either pass the tool's explicit non-git bypass for local folder work or stop with a clear project configuration error before launching the agent.

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

### Task Run

A task run is the execution record for a task as it moves through the production pipeline.

The task is the durable work definition. The run is the operational history of attempting that work.

A task run has:

- `taskId`
- `currentColumnId`
- `status`
- start and update times
- structured pipeline events
- optional agent-session metadata

Fits Board should keep one current run per active task until richer rerun/history support exists.

When a task leaves Backlog for any later column, Fits Board must create or reuse the task's run, append structured events for the entered column, and update the task metatag with the current stage, status, allowed tools, and required output. This gives the UI and future agents a deterministic handoff record instead of relying on visual card movement alone.

Moving a task into an executable pipeline column should start that column's work automatically. The user should not need a separate Start button after moving the card. The task inspector should instead expose interruption controls such as Stop or Pause while a local agent process is running.

When an automated stage finishes successfully, Fits Board should move the task to the next column and start the next automated stage. The pipeline should stop and wait at human checkpoints, currently Human Review, so the user can inspect the result before shipping. A failed or stopped stage must not auto-advance.

Task run events are rendered as terminal-style logs in the task inspector. They are also persisted under the Fits Board configuration folder so later app launches and agents can read the same operational history. The inspector may render only the most recent slice of very large log streams to keep the app responsive; persisted task log files remain the durable full history.

When Fits Board starts a local coding-agent process for a task, it must create and persist an agent session for that task run. The Fits session id is generated immediately and is stable across app launches. When the underlying tool exposes its own session id, such as a Codex or Claude session UUID, Fits Board should capture it from process output, store it as the external session id, and update the stored resume command. This makes recovery explicit after an app restart, process crash, internet drop, or interrupted agent run.

Agent-session metadata must include:

- Fits session id
- tool id
- tool display name
- external tool session id when known
- resume command
- session status
- start and update times

The task inspector must expose resume controls when a task has a saved agent session and no process is currently running. Resume should use the external tool session id when available and fall back to the best local resume behavior supported by the tool.

The task's own artifact folder is the authoritative place for execution logs. The folder lives beside the task Markdown artifact in the workspace/project tree:

```text
~/.fits-board/workspaces/<workspace-name-or-id>/projects/<project-name-or-id>/<task-title-slug-or-id>/
```

Current files inside that folder:

- `task.md`: the task definition copied into the task artifact folder.
- `events.ndjson`: structured pipeline events used by the inspector and agents.
- `terminal.log`: terminal-style text output for quick reading and tailing.
- `session.json`: persisted agent-session metadata used to resume interrupted work.
- `prompt-<stage>.md`: the exact prompt Fits Board typed into the PTY-backed agent for a stage.
- `stage-done-<stage>.txt`: the deterministic completion marker written by the agent after stage verification succeeds.
- `metatag.json`: optional agent-written string key/value metadata that Fits Board imports back into the task metatag after a stage process exits.
- `artifacts/`: optional agent-written task artifacts, notes, reports, or generated files that belong to the Fits task context rather than directly to a project repository.

Fits Board may also maintain a run index for quick loading:

```text
~/.fits-board/runs/<task-id>/events.ndjson
```

The global run index is not the product truth for the task. The task artifact folder is where agent-facing execution context should accumulate.

### Pipeline Stage Contract

Each board column has a stage contract.

A stage contract defines:

- allowed tools,
- entry message,
- required output,
- and the status semantics for that stage.

The contract is intentionally deterministic. Agents should be told which stage they are executing and must not skip ahead to later columns unless Fits Board moves the task.

Current MVP stage contracts:

- Backlog: `Intake dialog`, `Markdown autosave`; output is backlog task markdown.
- Planning: `Codex CLI`, `Live spec check`; output is planning context, assumptions, target artifacts, verification commands, and open questions. Planning must not execute the requested work.
- Agent Fan out: `Codex CLI`, `fits-agent-host`, `git worktree`; output is completed task work split into small executable pieces. When the tool supports it and the pieces are independent, this stage may use parallel sub-agents. If parallel agents are unavailable, it executes sequentially. It must not stop at planning.
- Agent QA: `Swift test`, `Go test`, `Codex CLI`; output is a QA report that verifies the original task objective using automated tests when available and manual checks when automation is not available.
- Agent Review: `Live spec check`, `Codex review`; output is strong review findings, risks, and pull request notes when a git repository is involved.
- Human Review: `Human approval`, `Diff reader`; output is a human approval decision.
- Ship it: `Local git`, `Release checklist`; output is a shipped task.

These choices are defaults. The user may later revise which tools belong to each column.

### Task Metatag

Each task has a `metatag` object for execution metadata that agents and later pipeline stages can write and read.

The current MVP stores metatag values as string key/value pairs. Examples include `agent`, `branch`, `environment`, `progress`, `started`, `agent_session_id`, `agent_external_session_id`, `agent_resume_command`, or other execution-specific markers.

Metatag is not part of the user's backlog definition. It can be added or updated across columns while the task moves through the pipeline. The task detail dialog must make the metatag object visible on every task, and task Markdown should include a `## Metatag` section when the object is not empty.

Local agents may update task metatag during execution by writing a JSON object with string values to the task artifact folder's `metatag.json`. Fits Board imports those values into the task metatag when the stage process exits.

Local agents may also create task-scoped artifacts by writing files under the task artifact folder's `artifacts/` directory. These files are for stage reports, generated notes, QA evidence, or other task context that should be visible from Fits Board without necessarily being part of a repository diff.

### Planning Type

Planning type tells Fits Board how much planning ceremony the user wants before agents execute a task.

Current planning types:

- `Fast (auto)`: Fits Board plans for the user and may attempt the task without asking clarifying questions.
- `LLM Plan Mode`: Fits Board delegates to the regular plan mode of the selected LLM/coding agent.

Legacy tasks may still decode older planning type values, but new tasks should only offer the current planning types above.

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
- Human Review
- Ship it

The agent columns are orchestration stages. Moving a task into an executable stage should create a run event log using the column's stage contract and start the configured local coding agent automatically.

The executable pipeline path is:

1. Planning prepares context and does not perform the work.
2. Agent Fan out breaks the plan into executable pieces and performs the work.
3. Agent QA verifies that the original task objective was satisfied.
4. Agent Review performs a strong review and prepares pull request guidance when relevant.
5. Human Review waits for the user.

### Backlog Column

Backlog is the intake column and the first stage of the production pipeline.

Moving a task back to Backlog resets its execution context. Fits Board should clear the task's run events, agent session metadata, metatag execution values, terminal log, saved stage prompts, and task-scoped execution artifacts. The backlog definition remains editable and saved, but the next move into Planning must start a fresh agent session instead of resuming old context.

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

### Task Inspector

Tasks outside Backlog should open in a right-side task inspector instead of the centered backlog editing modal.

The inspector keeps the board visible while showing operational context for the selected task.

The inspector should include:

- a header with workspace, project, task title, stage icon, and close action,
- context chips for stage, environment, active tool or agent, and branch,
- tabs for Details, Logs, Agents, Prompts, Meta, and Repos,
- terminal-style rendering of task run events in the Logs tab.

Logs must be easy to copy. The Logs tab should allow selecting log text and should provide a copy action for the structured log stream shown in the inspector.

The Prompts tab should show the persisted prompt history for the task, including prompts from earlier stages and resume attempts, not only a synthetic preview of the currently selected column. If no prompt has been persisted yet, it may show a preview of the current column prompt.

The Meta tab should show the current task metatag and generated task artifacts when agents create files in `artifacts/`.

For agent columns, the default inspector tab should be Logs. For human columns after Backlog, the default inspector tab may be Details unless an active run needs attention.

Backlog tasks continue to use the centered modal because Backlog is where users write and revise the task definition.

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

Enabled local agents may be selected by Fits Board for PTY-backed execution through `fits-agent-host` when an automated pipeline stage starts.

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
- `runs.json`
- `draft-task.json`
- `workspaces/**/projects/**/*.md`
- `workspaces/**/projects/**/<task-slug>/task.md`
- `workspaces/**/projects/**/<task-slug>/events.ndjson`
- `workspaces/**/projects/**/<task-slug>/terminal.log`
- `runs/**/events.ndjson`

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

Fits Board itself should not be the coding agent. For Codex, Claude Code, and similar tools, the app should launch a local helper process such as `fits-agent-host`, which opens the selected CLI in a real PTY session, streams the terminal output into the task inspector, and writes the same output to the task artifact folder.

The current MVP uses `fits-agent-host pty` for local agent execution. The app writes the stage prompt into the task artifact folder and asks the helper to type that prompt into the PTY-backed CLI. This keeps execution local to the user's installed agent subscription instead of relying on an API-key based integration.

For the current MVP, Fits Board gives local coding agents broad local execution power. Codex stages should be launched with Codex's explicit approvals-and-sandbox bypass so the agent can edit files outside the repository when the task requires it. This is intentionally dangerous and should become configurable later, but for now the orchestration assumes the user's machine is the trusted execution environment.

Stage prompts should not ban GitHub or other external CLIs globally. They should allow those tools when the task explicitly requires them, while still keeping the agent scoped to the current Fits stage.

Every automated stage prompt must include a unique completion marker and a task-local completion file. The agent writes the marker into `stage-done-<stage>.txt` inside the task artifact folder after it verifies that the current stage's required output is complete, and it should also print the marker in the terminal log. The marker means the stage contract was satisfied, not necessarily that the entire task objective is finished. For example, Planning is complete when planning context, assumptions, target artifacts, verification commands, and open questions are produced; it must not execute the requested work. Execution, QA, and review stages compare their outputs against the original task objective according to their stage contracts. The helper watches the completion file as the primary deterministic signal and may use terminal output as a secondary signal. If the marker is not observed, the stage must not be treated as successfully completed, even if the child process exits.

## Known Gaps

- Agent activation is stored, and Codex/Claude execution is routed through `fits-agent-host`; richer interactive terminal controls are still future work.
- Pipeline logs combine structured stage events with live PTY output.
- `fits-agent-host` is still a small helper and should continue to evolve as orchestration becomes real.
- Release packaging is local/debug-oriented and not yet signed/notarized.

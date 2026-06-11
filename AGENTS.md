# AGENTS.md

This repo contains Fits Board, a native macOS app for orchestrating AI production work across workspaces, projects, repositories, tasks, and local coding agents.

## Product Direction

Fits Board should feel like a dense, polished native control plane, not a web dashboard. Keep the visual direction close to the existing dark board UI: compact top navigation, workspace chips, clear kanban columns, strong card hierarchy, and restrained controls.

The long-term product is an AI production pipeline:

- create task intake,
- generate specs,
- write plans,
- fan out work per repository,
- run coding agents,
- review and ship.

## Architecture

- Use SwiftUI for the macOS app.
- Keep shared logic in `Sources/FitsCore`.
- Keep app/view model code in `Sources/FitsBoard`.
- Keep local process helper code in `cmd/fits-agent-host`.
- Persist user data offline under `~/.fits-board/`.
- Do not introduce Electron, React, HTML, CSS, or a web runtime for the app shell.

## Persistence Rules

The offline store is JSON files in `~/.fits-board/`:

- `settings.json`
- `workspaces.json`
- `projects.json`
- `tasks.json`
- `draft-task.json`

When adding fields to persisted models, preserve backward compatibility with existing JSON files. Prefer `decodeIfPresent` defaults for new settings fields.

## Coding Agent Detection

Local agent detection lives in `Sources/FitsCore/ToolDetection.swift`.

Current registry includes:

- Claude Code
- Codex
- Gemini CLI
- OpenCode
- Cursor Agent
- Aider
- Goose

Do not expose secrets in UI-facing detection results. Codex auth detection may read `~/.codex/auth.json`, but only safe metadata such as email, plan, source, or path should be surfaced. Never store or print access tokens, refresh tokens, API keys, or auth blobs.

## UI Guidelines

- Prefer native SwiftUI controls and macOS affordances.
- Keep the app dense and operational.
- Avoid landing pages, hero sections, oversized cards, and marketing copy inside the app.
- Use compact icon buttons where possible.
- Keep text within bounds at narrow and wide app sizes.
- Preserve the dark visual system already in `BoardView.swift`.
- Preferences should own workspace management and local agent activation.
- Project creation should support multiple repository folders using native macOS folder selection.

## Testing

Run these before claiming work is complete:

```sh
swift test
```

```sh
cd cmd/fits-agent-host
go test ./...
```

For app packaging:

```sh
./scripts/package_app.sh
```

## Git And Safety

- The main branch is `main`.
- The remote is `git@github.com:djalmaaraujo/fits-board.git`.
- Preserve user data and uncommitted changes.
- Do not run destructive git commands unless explicitly requested.
- Do not delete or rewrite `~/.fits-board/` data during development.
- If a migration is needed, make it backward compatible and test it.

## Current Rough Edges

- Agent activation is persisted, but embedded PTY execution is not complete yet.
- `fits-agent-host` is the intended place for local terminal/session bridging.
- Release packaging is local/debug-oriented; proper signing/notarization is still future work.

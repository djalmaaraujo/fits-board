# AGENTS.md

This repo contains Fits Board, a native macOS app for orchestrating AI production work across workspaces, projects, repositories, tasks, and local coding agents.

## Highest-Level Rule: Use The Live Spec

Fits Board uses a living specification.

- `SPEC.md` says **what** the product is.
- The source code says **how** the product is implemented.
- Tests prove important behavior.
- Temporary planning notes are not product truth.

Every agent must read `SPEC.md` before planning or changing product behavior.

When you change a product concept, you must:

1. Check whether the intended change matches `SPEC.md`.
2. Say clearly whether the current spec already covers the change or needs an update.
3. Update `SPEC.md` in the same change when the concept has changed.
4. Keep the spec focused on concepts and required behavior, not implementation blow-by-blow.

If code and `SPEC.md` disagree, report the mismatch before continuing. Then fix either the code, the spec, or both so the repo returns to a coherent state.

## Live Spec Versus Implementation

The live spec is not a diary, plan archive, or changelog.

Use this split:

- `SPEC.md`: what the product is, what things mean, and what behaviors must hold.
- Code: how those behaviors are implemented.
- Tests: executable proof for important behavior.
- Commit history: historical record of changes.

Do not commit large planning artifacts under `docs/superpowers/`. That directory is ignored on purpose. If a Superpowers workflow creates temporary plans or notes there, use them as working memory only and do not version them.

## Product Direction

Fits Board should feel like a dense, polished native control plane, not a web dashboard. Keep the visual direction close to the existing dark board UI: compact top navigation, workspace chips, clear kanban columns, strong card hierarchy, and restrained controls.

The long-term product is an AI production pipeline:

- create task intake,
- generate specs,
- write plans,
- fan out work per repository,
- run coding agents,
- review and ship.

## Planning Rules For Agents

Before implementing:

1. Read `SPEC.md`.
2. Inspect the current code related to the request.
3. Identify whether the request is:
   - a concept change,
   - an implementation-only change,
   - a bug fix preserving existing concepts,
   - or a visual/product refinement.
4. If it is a concept change, update `SPEC.md`.
5. If using Superpowers planning, keep generated plans out of git unless the user explicitly asks otherwise.

During implementation:

- Prefer small, coherent changes.
- Keep product language in English.
- Keep comments and docs concise.
- Do not duplicate the spec in many files.
- Let `SPEC.md` remain the one durable product-concept document.

Before finishing:

- Run the relevant tests.
- Check `git status`.
- Confirm whether `SPEC.md` still matches the code.
- Mention any intentional spec/code gaps.

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

Never delete or rewrite real user data in `~/.fits-board/` as part of normal development.

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

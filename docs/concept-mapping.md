# Concept Mapping: Claude Code → Copilot → Cursor

Three-way mapping for users migrating from Claude Code through the Copilot intermediate to Cursor.

## Configuration Files

| Concept | Claude Code | Copilot CLI | Cursor |
|---------|-------------|-------------|--------|
| Global AI instructions | `~/.claude/CLAUDE.md` | — | Settings → Rules → User Rules |
| Project AI instructions | `.claude/CLAUDE.md` or `CLAUDE.md` | `.github/copilot-instructions.md` | `.cursor/rules/*.mdc` + `AGENTS.md` |
| Guidelines (scoped) | `~/.claude/guidelines/*.md` | `.github/instructions/*.instructions.md` | `.cursor/rules/*.mdc` (with globs) |
| Custom commands | `~/.claude/commands/*.md` | `.github/agents/*.md` | `.cursor/modes.json` (custom agents) |
| Project commands | `.claude/commands/*.md` | `.github/agents/*.md` | `.cursor/modes.json` |
| Settings | `~/.claude/settings.json` | — | Cursor Settings UI |
| Memory | `.claude/memory/MEMORY.md` | — | Cursor Memories (auto) + Notepads (manual) |
| Context exclusion | — | — | `.cursorignore` |
| Cross-tool instructions | `CLAUDE.md` | `AGENTS.md` | `AGENTS.md` |
| MCP config | `~/.claude/mcp.json` | — | `.cursor/mcp.json` |

## Lifecycle Hooks

| Event | Claude Code | Copilot | Cursor (via dot-cursor) |
|-------|-------------|---------|------------------------|
| Session start | `SessionStart` hook | — | `post-checkout` git hook (surfaces handoff) |
| Pre-tool execution | `PreToolUse` hook | — | Glob-scoped rules (partial) |
| Post-tool execution | `PostToolUse` hook | — | **Gap** — no equivalent |
| Session stop | `Stop` hook | — | `post-commit` at 5+/8+ commits (reminder) |
| Notification | `Notification` hook | — | Terminal output from hooks |

## Commands → Agents

| Claude Code Command | Copilot Agent | Cursor Agent | Model |
|--------------------|---------------|--------------|-------|
| `/lets-go` | `@lets-go` | `@lets-go` | Sonnet 4.6 |
| `/session-logger` | `@session-logger` | `@session-logger` | Sonnet 4.6 |
| `/handoff` | `@handoff` | `@handoff` | Sonnet 4.6 |
| `/arch-review` | `@arch-review` | `@arch-review` | Opus 4.6 |
| `/autocommit` | `@autocommit` | `@autocommit` | Haiku 4.5 |
| `/mine-sessions` | `@mine-sessions` | `@mine-sessions` | Sonnet 4.6 |
| `/security-audit` | — | `@security-audit` | Opus 4.6 |
| `/doc-review` | — | `@doc-review` | Sonnet 4.6 |
| `/editorial-review` | — | `@editorial-review` | Sonnet 4.6 |
| `/pickup` | — | `@pickup` | Sonnet 4.6 |
| `/commit-manual` | — | `prepare-commit-msg` hook | — (no AI) |
| — | — | `ship-it` skill | — (composite: commit + push + PR) |

Note: In Cursor, commands work through three mechanisms:
- **Command aliases** (`.cursor/rules/command-aliases.mdc`) — in-context commands typed by the user (session-logger, handoff, pickup, lets-go, autocommit)
- **Subagents** (`.cursor/agents/*.md`) — delegated by the main agent for independent analysis (arch-review, security-audit, doc-review, review-pr, babysit-pr, mine-sessions, editorial-review)
- **Skills** (`.cursor/skills/`) — composite workflows (ship-it, pre-checkin-review, resolve-gh-comments)

Cursor's `.cursor/modes.json` for file-based custom modes is not yet implemented (under consideration). Do NOT generate modes.json.

## Context and Memory

| Concept | Claude Code | Cursor |
|---------|-------------|--------|
| Effective context window | ~200K tokens (1M beta) | ~70–120K tokens |
| Session persistence | Conversation history + `MEMORY.md` | Cursor Memories (auto-extracted) |
| Manual context | `CLAUDE.md`, guidelines | `@file`, `@folder`, `@codebase`, Notepads |
| Cross-session context | `~/.claude/memory/` | Cursor Memories + Notepads |
| Context injection | Hooks inject at lifecycle events | Rules auto-load by type; hooks surface handoffs |

## Session Management (Cross-Tool)

All tools write to a shared `session-logs/` directory at the project root with YAML frontmatter identifying the source tool.

| Aspect | Claude Code | Cursor |
|---------|-------------|--------|
| Log directory | `session-logs/` (shared) | `session-logs/` (shared) |
| Legacy directory | `.claude/session-logs/` | N/A |
| Handoff format | `handoff-YYYY-MM-DD-HHMM.md` with `tool: claude-code` frontmatter | Same with `tool: cursor` frontmatter |
| Handoff discovery | `session-logs/` then `.claude/session-logs/` | `session-logs/` then `.factory/logs/` then `.claude/session-logs/` |
| Cross-tool handoff | Writes to shared location; any tool's pickup finds it | `session-start.mdc` auto-checks at conversation start; `@pickup` parses `tool:` field |

Droid and Copilot also participate in this shared protocol — see `dot-droid/docs/concept-mapping.md` for the full four-tool matrix.

## Server-Side Automation

| Feature | Claude Code | Cursor (via dot-cursor) |
|---------|-------------|------------------------|
| Commit format validation | — | `commit-lint.yml` Action |
| PR description generation | — | `pr-description.yml` Action |
| Automated PR review | — | `pr-review-checklist.yml` Action |
| Session log maintenance | Manual | `session-maintenance.yml` Action |
| Branch cleanup | Manual | `branch-hygiene.yml` Action |

## Model Selection

| Use Case | Claude Code | Cursor |
|----------|-------------|--------|
| Architecture, complex reasoning | Opus (default) | Opus 4.6 (select per agent in `modes.json`) |
| Daily coding | Sonnet | Sonnet 4.6 (default in Agent mode) |
| Tab completion | — | Haiku 4.5 (set in Settings → Models → Autocomplete) |
| Extended thinking | Available (Opus) | Not exposed in Cursor |

## Known Remaining Gaps

| Feature | Claude Code Has | Cursor Status | Workaround |
|---------|----------------|---------------|------------|
| PostToolUse hooks | File validation on every write | No equivalent | Use glob-scoped rules for file-type validation |
| Extended thinking | Opus extended thinking mode | Not exposed | Accept the gap; Opus still reasons well without explicit thinking mode |
| 200K context | Reliable 200K, 1M beta | 70–120K effective | Shorter conversations, precise `@file` references, concise rules |
| Unlimited MCP tools | No limit | 40 tool hard limit | Prioritize tools, disable unused servers |
| Native lifecycle hooks | Built-in 5-event system | None | Git hooks cover ~95% of use cases |
| Handoff on new window | SessionStart fires on IDE open | Only on branch checkout | Manual `@lets-go` in new conversations |

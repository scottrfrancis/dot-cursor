# Claude Code → Cursor Migration Checklist

**For experienced Claude Code users migrating to Cursor with Anthropic models**

> This checklist maps your `~/.claude/` and `.claude/` infrastructure to Cursor equivalents.
> Your dot-copilot work gives you a head start — the `.github/` structure partially overlaps
> with Cursor's conventions, but Cursor has its own rule system that's more powerful in some
> areas and has gaps in others.

---

## Concept Mapping: What Goes Where

| Claude Code | Copilot (your dot-copilot) | Cursor Equivalent |
|---|---|---|
| `~/.claude/CLAUDE.md` | User-level instructions | **User Rules** (Settings → Rules) |
| `CLAUDE.md` (project root) | `.github/copilot-instructions.md` | **AGENTS.md** (project root) or `.cursor/rules/` |
| `~/.claude/guidelines/*.md` | `.github/instructions/*.instructions.md` | `.cursor/rules/*.mdc` with glob patterns |
| `~/.claude/commands/*.md` | `.github/agents/*.md` | Custom Agents (`.cursor/modes.json`) + manual rules |
| `~/.claude/hooks/*.sh` | `.github/hooks/` | ⚠️ **No equivalent** — use rules + discipline |
| `~/.claude/settings.json` | N/A | Cursor Settings + `.cursor/mcp.json` |
| `.claude/memory/MEMORY.md` | N/A | Cursor Memories (auto) + Notepads (manual) |
| `.claude/session-logs/` | N/A | ⚠️ **No equivalent** — manual tracking |
| `.claude/skills/` | N/A | `.cursor/rules/` with `alwaysApply: false` |

---

## Phase 1: Cursor IDE Configuration

### 1.1 Model Selection
- [ ] Open Cursor Settings → Models
- [ ] Enable **Claude Opus 4.6** (`claude-opus-4-6`) — use for architecture, complex refactors, multi-file reasoning
- [ ] Enable **Claude Sonnet 4.5** (`claude-sonnet-4-5-20250929`) — daily driver for most coding tasks
- [ ] Enable **Claude Haiku 4.5** — quick completions, boilerplate, tab predictions
- [ ] Set default Agent model to **Sonnet 4.5** (best balance of speed and quality for agentic work)
- [ ] Know when to switch: Opus for arch-review-level work, Sonnet for implementation, Haiku for fast iteration

### 1.2 User Rules (Global — your `~/.claude/CLAUDE.md` equivalent)
- [ ] Open Settings → Rules → User Rules
- [ ] Paste your condensed global instructions (see `generated/cursor-user-rules.txt` from the script)
- [ ] Key things to port from your CLAUDE.md:
  - Conventional commit format preferences
  - Shell script standards (`set -euo pipefail`, etc.)
  - README-centric documentation approach
  - Session safety guidelines for hardware projects
  - Your preferred review frameworks

### 1.3 Agent Mode Configuration
- [ ] Confirm Agent mode is default (it should be since Cursor 0.46+)
- [ ] In Agent settings, enable:
  - [x] Terminal command execution
  - [x] File creation/editing
  - [x] Web search (if available on your plan)
- [ ] Disable Edit mode (it's deprecated — Agent mode subsumes it)

### 1.4 MCP Server Setup
- [ ] Create/edit `.cursor/mcp.json` in project root (or global config)
- [ ] Port any MCP servers you use from `~/.claude/settings.json`
- [ ] Note: Cursor has a **40-tool hard limit** across all MCP servers (Claude Code has no such limit)
- [ ] Prioritize your most-used MCP tools if you hit the cap

### 1.5 Context Optimization
- [ ] Create `.cursorignore` (equivalent to `.gitignore` for AI context)
- [ ] Exclude: `node_modules/`, `dist/`, `build/`, `.git/`, large data files, vendor dirs
- [ ] Include: source code, configs, docs, tests — things the AI should reason about
- [ ] Consider project size — Cursor's usable context window is ~70K-120K tokens after internal truncation (vs Claude Code's full 200K)

---

## Phase 2: Project Rules (`.cursor/rules/`)

### 2.1 Create Rule Directory Structure
- [ ] Run the migration script (see below) to auto-generate `.cursor/rules/` from your guidelines
- [ ] Verify rules appear in Cursor Settings → Rules → Project Rules

### 2.2 Rule Types — Choose Wisely

Each `.mdc` file uses frontmatter to control when it fires:

```yaml
# Always Apply — every conversation (like your CLAUDE.md global instructions)
---
description: ""
globs: ""
alwaysApply: true
---

# Auto Attached — when matching files are open (like copilot instructions with applyTo)
---
description: ""
globs: "*.sh,*.bash,Makefile"
alwaysApply: false
---

# Agent Requested — AI decides based on description (smart activation)
---
description: "Shell scripting standards for bash error handling and portability"
globs: ""
alwaysApply: false
---

# Manual — only when you @mention the rule in chat
---
description: "Architecture review framework"
globs: ""
alwaysApply: false
---
```

### 2.3 Migrate Guidelines → Rules
Map your `~/.claude/guidelines/` and `copilot/instructions/` to `.cursor/rules/`:

- [ ] `shell-scripts.md` → `.cursor/rules/shell-scripts.mdc` (Auto Attached: `*.sh,*.bash,Makefile`)
- [ ] `conventional-commits.md` → `.cursor/rules/conventional-commits.mdc` (Always Apply)
- [ ] `readme-documentation.md` → `.cursor/rules/readme-docs.mdc` (Auto Attached: `*.md`)
- [ ] `session-safety.md` → `.cursor/rules/session-safety.mdc` (Always Apply — CRITICAL for hardware)
- [ ] `ai-patterns.md` → `.cursor/rules/ai-patterns.mdc` (Auto Attached: `*.py,*.ts,*.js`)
- [ ] `project-setup.md` → `.cursor/rules/project-setup.mdc` (Agent Requested)
- [ ] `shell-escaping.md` → `.cursor/rules/shell-escaping.mdc` (Auto Attached: `*.sh,*.bash,Dockerfile`)
- [ ] `c4-diagramming.md` → `.cursor/rules/c4-diagramming.mdc` (Auto Attached: `*.puml,*.plantuml`)
- [ ] `markdown-formatting.md` → `.cursor/rules/markdown-formatting.mdc` (Auto Attached: `*.md`)

### 2.4 AGENTS.md (Simpler Alternative)
- [ ] For projects where full `.cursor/rules/` is overkill, use `AGENTS.md` in project root
- [ ] Cursor reads `AGENTS.md` natively (as do Codex, Gemini CLI, and others)
- [ ] This is your cross-tool play — one file works in Cursor, Copilot CLI, and others
- [ ] Limitation: no glob scoping, no frontmatter metadata — it's always-on

---

## Phase 3: Commands → Custom Agents

### 3.1 Cursor Custom Agents (`.cursor/modes.json`)
Your Claude Code commands (`/lets-go`, `/session-logger`, `/handoff`, etc.) map to Cursor's custom agents:

- [ ] Create `.cursor/modes.json` with agent definitions
- [ ] Each agent specifies: name, model, tools, system prompt
- [ ] Key migrations:

| Claude Command | Cursor Agent | Model | Notes |
|---|---|---|---|
| `/lets-go` | `@lets-go` | Sonnet 4.5 | Session init, git sync |
| `/session-logger` | `@session-logger` | Sonnet 4.5 | End-of-session capture |
| `/handoff` | `@handoff` | Sonnet 4.5 | Continuation prompt |
| `/arch-review` | `@arch-review` | **Opus 4.6** | Needs deepest reasoning |
| `/autocommit` | `@autocommit` | Haiku 4.5 | Fast, routine task |
| `/mine-sessions` | `@mine-sessions` | Sonnet 4.5 | Pattern analysis |

### 3.2 Manual Rules as Command Substitutes
For commands that don't map well to agents, create manual rules:
- [ ] `.cursor/rules/checkpoint-progress.mdc` (Manual — @mention when needed)
- [ ] `.cursor/rules/extract-adr.mdc` (Manual)

---

## Phase 4: Hooks Gap — Solved with Git Hooks

**Cursor has no hooks system, but git does.** The `setup-hooks-and-cron.sh` script
installs git hooks that fire on every commit, push, checkout, and merge — regardless
of whether the action came from Cursor, Copilot CLI, or raw terminal. See Phase 6.

The `.cursor/rules/` below provide soft guidance; the git hooks provide hard automation:

### 4.1 SessionStart → post-checkout hook + always-apply rule
- [ ] `post-checkout` git hook surfaces handoff context on branch switch (hard trigger)
- [ ] `session-start.mdc` rule tells the agent to check for handoffs (soft guidance)
- [ ] Both work together — hook for terminal visibility, rule for AI awareness

### 4.2 Stop → post-commit hook + manual session-wrap rule
- [ ] `post-commit` git hook counts commits and reminds at 5+/8+ thresholds
- [ ] `session-wrap.mdc` is a manual rule you @mention to generate session log + handoff
- [ ] Hook handles the automated reminder; rule handles the AI-generated content

### 4.3 PostToolUse → No git equivalent
- [ ] This is the one remaining gap — Claude Code's PostToolUse validated files after writes
- [ ] **Workaround:** Use glob-scoped `.cursor/rules/` to instruct the agent on validation
- [ ] Example: "After modifying any `.yaml` file, validate with `yamllint`"
- [ ] Also consider: pre-commit hooks with tools like `pre-commit` framework for linting

---

## Phase 5: Session & Memory Management

### 5.1 Cursor Memories
- [ ] Enable Memories in Cursor settings (auto-generates from conversations)
- [ ] These replace some of what `.claude/memory/MEMORY.md` did
- [ ] You can also use `/Generate Cursor Rules` command in chat to create rules from decisions made during a session

### 5.2 Notepads (Manual Context)
- [ ] Use Cursor Notepads for persistent context that doesn't fit in rules
- [ ] Good for: project architecture notes, domain glossaries, API references
- [ ] Reference with `@notepad-name` in chat

### 5.3 Session Logs (Manual Process)
- [ ] Create `session-logs/` directory in project
- [ ] At end of each session, ask the agent to write a session summary
- [ ] Use your `@session-logger` custom agent or manual rule
- [ ] This replaces the automated hook-driven logging from Claude Code

---

## Phase 6: Git Hooks (Lifecycle Automation)

**This is the key insight: git hooks fire regardless of IDE.** They replace Claude Code's
hooks system and work whether you're in Cursor, Copilot CLI, or raw terminal.

### 6.1 Install Git Hooks
- [ ] Run: `./setup-hooks-and-cron.sh /path/to/your/project`
- [ ] Verify hooks are in `.git/hooks/` (not version-controlled — per-clone install)

### 6.2 Hooks Installed

| Git Hook | Replaces | What It Does |
|---|---|---|
| `prepare-commit-msg` | `/autocommit` | Pre-fills conventional commit template with detected type/scope from diff |
| `post-commit` | Claude Code `Stop` hook | Logs every commit to `session-logs/activity-YYYY-MM-DD.md`, reminds about `@session-logger` at 5+ commits, `@handoff` at 8+ |
| `post-checkout` | Claude Code `SessionStart` hook | Surfaces handoff context on branch switch — shows preview + age of last handoff file |
| `pre-push` | Lightweight `/arch-review` | Warns on 10+ unpushed commits, blocks WIP/fixup commits on main/master, detects large files |
| `post-merge` | Part of `/lets-go` | Alerts on dependency file changes (package.json, requirements.txt), flags config/instruction file changes |

### 6.3 How Hooks Chain With Existing Hooks
- [ ] Script auto-detects existing hooks and backs them up to `<hook>.backup`
- [ ] Chain call preserves previous behavior
- [ ] All hooks respect `--no-verify` bypass
- [ ] Uninstall cleanly with `./setup-hooks-and-cron.sh --uninstall`

### 6.4 Copilot CLI as Hook Executor
- [ ] The `ai-assist.sh` wrapper script auto-detects Copilot CLI (`ghcs`, `gh copilot`)
- [ ] Falls back to templates when no AI CLI is available
- [ ] Can be extended: add new tasks to the case statement in `.cursor/scripts/ai-assist.sh`

---

## Phase 7: Cron Jobs (Background Maintenance)

### 7.1 Install Cron Jobs
- [ ] Run: `./setup-hooks-and-cron.sh --install-cron /path/to/your/project`
- [ ] Verify with `crontab -l`

### 7.2 Scheduled Tasks

| Schedule | Script | Replaces |
|---|---|---|
| Daily 2 AM | `archive-sessions.sh` | Manual cleanup — archives session logs >30 days, handoffs >14 days |
| Daily 9 AM | `check-handoff-staleness.sh` | Claude Code `Stop` hook — warns if active project has no recent handoff |
| Weekly Sun 6 PM | `weekly-session-summary.sh` | `/mine-sessions` — generates weekly activity summary with commit counts and decision extraction |

### 7.3 Cron Output
- [ ] Scripts write to `session-logs/` (archive subdir for old logs)
- [ ] Weekly summary goes to `session-logs/weekly-YYYY-MM-DD.md`
- [ ] Feed weekly summaries into `@mine-sessions` agent in Cursor for AI-powered pattern analysis

---

## Phase 8: GitHub Actions (Server-Side Automation)

Actions are the server-side complement to local hooks and cron. They run reliably
regardless of laptop state, are team-visible, and gate PRs.

### 8.1 Install Workflows
```bash
./setup-github-actions.sh /path/to/your/project
```

### 8.2 Workflows Installed

| Workflow | Trigger | Replaces | What It Does |
|---|---|---|---|
| `pr-description.yml` | PR opened | Manual PR writeups | Parses conventional commits, groups by type (feat/fix/refactor/etc), lists key files, flags breaking changes. Auto-fills PR body. |
| `commit-lint.yml` | PR opened | Local-only enforcement | Server-side gate that fails if any commit doesn't match `type(scope): description`. Catches what slips past local hooks. |
| `pr-review-checklist.yml` | PR opened | Lightweight `/arch-review` triage | Flags: large PRs (30+ files, 500+ lines), missing tests alongside code changes, sensitive file changes, dependency changes without lockfile, AI instruction file changes (AGENTS.md, .cursor/rules, etc). Non-blocking. |
| `session-maintenance.yml` | Daily + Weekly | Local cron | **Daily:** archives session logs >30 days, opens GitHub Issue if active project has no recent handoff. **Weekly (Sundays):** generates weekly summary with commit breakdown, most active directories, and session log index. |
| `branch-hygiene.yml` | Weekly (Mondays) | Manual cleanup | Detects merged branches (safe to delete), stale branches (30+ days inactive), drifted branches (50+ commits behind default). Opens GitHub Issue with cleanup recommendations. |

### 8.3 Why Both Local Hooks AND Actions?
- **Hooks** give you immediate, per-commit feedback in your terminal. Fast. Private.
- **Actions** run server-side — they work when your laptop is closed, they're visible to the team, and they gate PRs before merge.
- **Session maintenance** in Actions replaces cron — more reliable (no laptop sleep issues), auditable, and creates commits/issues that everyone can see.
- You can run both cron AND the Actions workflow (belt + suspenders) or drop cron entirely.

### 8.4 GitHub Labels
- [ ] Create label: `session-maintenance` (used by stale handoff issues)
- [ ] Create label: `branch-hygiene` (used by branch cleanup issues)
- [ ] Go to: Settings → Labels → New label

### 8.5 PR Review vs @arch-review
The `pr-review-checklist.yml` workflow is a **triage pass**, not a full architecture review.
It catches mechanical issues (missing tests, large PRs, secret exposure). For substantial
changes, use `@arch-review` in Cursor with Opus 4.6 — that's where deep reasoning matters.

---

## Phase 9: Per-Project Migration Script

Run all three scripts on each project:

```bash
# Step 1: Cursor config (rules, agents, AGENTS.md, .cursorignore)
./migrate-to-cursor.sh /path/to/your/project

# Step 2: Git hooks
./setup-hooks-and-cron.sh /path/to/your/project
./setup-hooks-and-cron.sh --install-cron /path/to/your/project  # optional local cron

# Step 3: GitHub Actions
./setup-github-actions.sh /path/to/your/project

# Step 4: Review and commit
cd /path/to/your/project
git add .cursor/ .github/workflows/ AGENTS.md .cursorignore
git commit -m "build: add Cursor rules, agents, git hooks, and CI workflows"
git push
```

- [ ] Review generated files in `.cursor/` and `.github/workflows/`
- [ ] Adjust rule types (alwaysApply, globs, descriptions) per project needs
- [ ] Commit `.cursor/`, `.github/workflows/`, and `AGENTS.md` to version control
- [ ] Note: `.git/hooks/` is NOT version-controlled — run `setup-hooks-and-cron.sh` per clone
- [ ] Consider adding hook install to project README or a `make setup` target
- [ ] Create GitHub labels: `session-maintenance`, `branch-hygiene`

---

## Phase 10: Workflow Adaptation

### 10.1 The Five-Layer Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           Your Development Stack                             │
├──────────────┬───────────────┬──────────────┬──────────────┬─────────────────┤
│   Cursor     │ Copilot CLI   │ Git Hooks    │ GitHub       │ Cron            │
│   (IDE)      │ (terminal)    │ (lifecycle)  │ Actions      │ (local backup)  │
├──────────────┼───────────────┼──────────────┼──────────────┼─────────────────┤
│ Interactive  │ Quick tasks   │ Per-commit   │ PR-gated     │ Background      │
│ development  │ CI/CD scripts │ Auto-logging │ Server-side  │ local fallback  │
│ Agent chat   │ plan/autopilot│ Reminders    │ Team-visible │                 │
│ @rules       │ AGENTS.md     │ Handoff surf │ Scheduled    │                 │
│ Opus/Sonnet  │ Multi-model   │ Push guards  │ Always-on    │                 │
├──────────────┼───────────────┼──────────────┼──────────────┼─────────────────┤
│ .cursor/     │ .github/      │ .git/hooks/  │ .github/     │ crontab         │
│ AGENTS.md    │ AGENTS.md     │ session-logs/│ workflows/   │ .cursor/scripts │
└──────────────┴───────────────┴──────────────┴──────────────┴─────────────────┘

         Shared state: session-logs/  ·  AGENTS.md  ·  .cursor/rules/
```

### 10.2 Daily Workflow

| What | Tool | How |
|---|---|---|
| Start session | **Git hook** auto-surfaces handoff on checkout | Just `git checkout` your branch |
| Interactive coding | **Cursor** Agent mode | `Cmd+L`, @-mention files/rules |
| Quick terminal task | **Copilot CLI** | `ghcs "explain this error"` or plan/autopilot mode |
| Commit | **Git hook** auto-fills conventional commit template | Just `git commit` — edit the pre-filled message |
| Activity tracking | **Git hook** auto-logs to session-logs/ | Happens on every commit, no action needed |
| Session reminder | **Git hook** at 5+ commits | Warning appears in terminal after commit |
| End of session | **Cursor** `@session-logger` agent | Type "@session-logger" in Agent chat |
| Handoff | **Cursor** `@handoff` agent | Type "@handoff" in Agent chat |
| Arch review | **Cursor** `@arch-review` (Opus 4.6) | Switch to arch-review agent, deep analysis |
| Open PR | **Actions** auto-fill description | Push branch, open PR — body auto-populated |
| PR review | **Actions** automated checklist | Flags posted as PR comment on open |
| Commit format | **Actions** lint gate | Fails check if non-conventional commits |
| Log cleanup | **Actions** (daily) + cron (backup) | Automatic — archives logs, detects stale handoffs |
| Branch cleanup | **Actions** weekly issue | Monday issue with stale/merged/drifted branches |
| Pattern mining | **Actions** weekly summary + **Cursor** `@mine-sessions` | Weekly auto-summary, monthly AI analysis |

### 10.3 Keyboard Shortcuts to Memorize
- `Cmd+L` — Open Agent chat (this is your terminal equivalent)
- `Cmd+Shift+L` — Add selection to chat
- `Cmd+I` — Inline edit (quick changes without full agent)
- `Cmd+Shift+P` → "New Cursor Rule" — Create rules on the fly
- `Cmd+.` — Accept agent's proposed changes
- `Cmd+Backspace` — Reject agent's proposed changes
- `Shift+Tab` — Toggle between plan mode and autopilot mode (in Copilot CLI)
- `@file`, `@folder`, `@codebase` — Context references (like Claude Code's @ mentions)

### 10.4 Context Window Discipline
- Cursor's effective context is **smaller** than Claude Code's (70-120K vs 200K usable)
- Start new conversations more frequently — git hooks will remind you
- Use `@file` references instead of letting the agent index everything
- Keep rules concise — every rule eats into your context budget
- Use Agent Requested rules over Always Apply where possible
- Copilot CLI in terminal is a separate context — use it for independent tasks

### 10.5 Coexistence: Cursor + Copilot CLI + Git Hooks + Actions
All tools share these files with zero conflict:
- `AGENTS.md` → Cursor reads it, Copilot CLI reads it, Codex reads it
- `.github/copilot-instructions.md` → Copilot CLI primary, Cursor ignores
- `.github/workflows/` → Actions primary — different subdirectory, same parent as copilot config
- `.cursor/rules/` → Cursor primary, other tools ignore
- `session-logs/` → Git hooks write, Cursor agents read, Actions archive
- `.git/hooks/` → IDE-agnostic, fires for any git operation from any tool

**The key principle: git is the integration layer.** Git hooks fire regardless of tool.
Actions fire on push/PR/schedule. Session logs accumulate from all sources. Every tool
reads `AGENTS.md`. The system works even if you switch tools mid-project.

---

## Known Gaps & Workarounds (Final)

| Feature | Claude Code | Cursor + Hooks + Actions | Remaining Gap |
|---|---|---|---|
| Hooks system | Built-in lifecycle hooks | **Git hooks** + **Actions** fill ~95% | PostToolUse (file validation on write) — use glob-scoped rules |
| Session logging | Automated via hooks | **post-commit** hook + **Actions** weekly summary | Fully automated ✅ |
| Handoff injection | SessionStart hook | **post-checkout** hook surfaces handoffs | Branch switch only, not new-window |
| Session reminders | Stop hook | **post-commit** at 5+ commits + **Actions** stale handoff issue | Commit-triggered + daily server check ✅ |
| Commit conventions | `/autocommit` + `/commit-manual` | **prepare-commit-msg** hook + **Actions** commit-lint gate | Better than Claude Code (local + server) ✅ |
| PR descriptions | Manual | **Actions** auto-generate from conventional commits | Better than Claude Code ✅ |
| PR review | `/arch-review` (interactive) | **Actions** automated checklist + **Cursor** `@arch-review` | Triage is automated, deep review stays interactive |
| Branch hygiene | Manual | **Actions** weekly issue with cleanup recommendations | Better than Claude Code ✅ |
| Log maintenance | Manual | **Actions** daily archive + cron backup | Better than Claude Code ✅ |
| Context window | 200K reliable, 1M beta | 70-120K effective | Still smaller — use shorter conversations |
| MCP tool limit | Unlimited | 40 tools max | Prioritize tools |
| Extended thinking | Built-in on Opus | Not exposed in Cursor | Use Opus for complex tasks, accept the gap |
| Terminal-native | First class | Cursor IDE + Copilot CLI terminal | **Both available** ✅ |

---

## Validation Checklist

After migration, verify each project:

### Cursor Config
- [ ] `.cursor/rules/` directory exists with `.mdc` files
- [ ] Rules appear in Cursor Settings → Rules → Project Rules
- [ ] `AGENTS.md` exists in project root (cross-tool compatibility)
- [ ] `.cursorignore` exists and excludes noise
- [ ] `.cursor/mcp.json` configured (if using MCP servers)
- [ ] Custom agents work (`@lets-go`, `@arch-review`, etc.)
- [ ] Model selection is intentional per agent

### Git Hooks
- [ ] `prepare-commit-msg` fires — `git commit` shows pre-filled conventional commit template
- [ ] `post-commit` fires — check `session-logs/activity-*.md` exists after a commit
- [ ] `post-checkout` fires — switch branches, see handoff preview (if handoff file exists)
- [ ] `pre-push` fires — push with a WIP commit on main, should block
- [ ] `post-merge` fires — `git pull` shows changed file summary
- [ ] Hooks chain properly with any pre-existing hooks (check `.backup` files)

### Cron (if installed)
- [ ] `crontab -l` shows the three cursor-migration-cron entries
- [ ] Scripts in `.cursor/scripts/` are executable
- [ ] Archive script works: `bash .cursor/scripts/archive-sessions.sh session-logs/`

### Session Workflow
- [ ] Git workflow (commit conventions) works through hook template
- [ ] Activity log accumulates across commits in a day
- [ ] Session reminders appear at 5+ commits
- [ ] Team members can use same rules (`.cursor/` is version controlled)
- [ ] Git hooks need per-clone install (add to README or `make setup`)

### Copilot CLI Coexistence
- [ ] `.github/copilot-instructions.md` still works for Copilot CLI
- [ ] `AGENTS.md` is read by both Cursor and Copilot CLI
- [ ] No file conflicts between `.cursor/` and `.github/` directories

### GitHub Actions
- [ ] Workflows appear in `.github/workflows/` and are committed
- [ ] Labels created: `session-maintenance`, `branch-hygiene`
- [ ] PR description auto-fills on first PR after setup
- [ ] Commit lint passes for conventional commits, fails for bad ones
- [ ] PR review checklist posts comment with findings
- [ ] Session maintenance runs on schedule (check Actions tab)
- [ ] Branch hygiene issue appears on first Monday after setup

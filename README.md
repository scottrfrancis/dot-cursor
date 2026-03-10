# dot-cursor

Portable development infrastructure for Cursor IDE — the Cursor equivalent of [`~/.claude/`](https://github.com/scottrfrancis/dot-claude). Provides consistent rules, custom agents, git hooks, and GitHub Actions workflows across all projects.

Works alongside [dot-copilot](https://github.com/scottrfrancis/dot-copilot) with zero conflicts. Designed for teams using Cursor + Copilot CLI + Anthropic models.

## Quick Start

```bash
# Clone this repo
git clone https://github.com/scottrfrancis/dot-cursor.git
cd dot-cursor

# Install everything into a target project (3 commands)
make install PROJECT=/path/to/your/project
```

Or run steps individually:

```bash
# Step 1: Cursor rules, custom agents, AGENTS.md, .cursorignore
bin/migrate-to-cursor.sh /path/to/your/project

# Step 2: Git hooks (lifecycle automation)
bin/setup-hooks.sh /path/to/your/project

# Step 3: GitHub Actions workflows
bin/setup-actions.sh /path/to/your/project

# Step 4: One-time manual step — paste into Cursor Settings → Rules → User Rules
cat /path/to/your/project/generated/cursor-user-rules.txt
```

Preview what would be created without writing anything:

```bash
bin/migrate-to-cursor.sh --dry-run /path/to/your/project
```

## What It Does

Three scripts install five layers of automation into any project:

| Layer | Tool | Trigger | What It Does |
|-------|------|---------|-------------|
| **Cursor Rules** | `.cursor/rules/*.mdc` | File open / always / on demand | AI coding guidelines scoped by file type |
| **Custom Agents** | `.cursor/modes.json` | `@agent-name` in chat | Session init, logging, handoff, arch review |
| **Git Hooks** | `.git/hooks/` | Every commit/push/checkout/merge | Activity logging, commit templates, handoff surfacing, push guards |
| **GitHub Actions** | `.github/workflows/` | PR open / daily / weekly schedule | PR descriptions, commit lint, session maintenance, branch hygiene |
| **Cron** (optional) | `crontab` | Scheduled | Local backup for session maintenance |

## Architecture

```
┌──────────────┬───────────────┬──────────────┬──────────────┬──────────────┐
│   Cursor     │ Copilot CLI   │ Git Hooks    │ GitHub       │ Cron         │
│   (IDE)      │ (terminal)    │ (lifecycle)  │ Actions      │ (optional)   │
├──────────────┼───────────────┼──────────────┼──────────────┼──────────────┤
│ Interactive  │ Quick tasks   │ Per-commit   │ PR-gated     │ Local backup │
│ Agent chat   │ plan/autopilot│ Auto-logging │ Server-side  │              │
│ .cursor/     │ .github/      │ .git/hooks/  │ .github/     │ crontab      │
│ AGENTS.md    │ AGENTS.md     │ session-logs/│ workflows/   │              │
└──────────────┴───────────────┴──────────────┴──────────────┴──────────────┘
         Shared: session-logs/  ·  AGENTS.md  ·  git history
```

**Key principle: git is the integration layer.** Hooks fire regardless of IDE. Actions fire on push. Session logs accumulate from all sources. Every AI tool reads `AGENTS.md`. The system works even if you switch tools mid-project.

## What Gets Created

Running all three scripts on a project produces:

```
your-project/
├── AGENTS.md                        # Cross-tool AI instructions (Cursor, Copilot CLI, Codex)
├── .cursorignore                    # Exclude noise from AI context window
├── .cursor/
│   ├── rules/                       # Project rules (version controlled)
│   │   ├── session-start.mdc        # Auto-check for handoff context
│   │   ├── session-wrap.mdc         # Generate session log + handoff on demand
│   │   ├── shell-scripts.mdc        # Shell scripting standards (auto-attached to *.sh)
│   │   ├── conventional-commits.mdc # Commit format (always on)
│   │   ├── ai-patterns.mdc          # LLM integration patterns (auto-attached to *.py,*.ts)
│   │   └── ...                      # More rules from your guidelines
│   ├── modes.json                   # Custom agents: @lets-go, @arch-review, etc.
│   ├── mcp.json                     # MCP server configuration (stub)
│   └── scripts/                     # Helper scripts for hooks
│       └── ai-assist.sh             # Copilot CLI wrapper for automation
├── .github/
│   └── workflows/
│       ├── pr-description.yml       # Auto-fill PR body from conventional commits
│       ├── commit-lint.yml          # Server-side conventional commit gate
│       ├── pr-review-checklist.yml  # Automated review findings
│       ├── session-maintenance.yml  # Daily log archive + weekly summary
│       └── branch-hygiene.yml       # Weekly stale branch detection
├── session-logs/                    # Session activity and handoff files
│   └── (auto-populated by hooks)
└── generated/
    └── cursor-user-rules.txt        # Paste into Cursor Settings → User Rules
```

Plus `.git/hooks/` (not version controlled — installed per clone).

## Origin

This is the Cursor migration of a [`~/.claude/`](https://github.com/scottrfrancis/dot-claude) setup built for Claude Code, via an intermediate [dot-copilot](https://github.com/scottrfrancis/dot-copilot) port. See [docs/concept-mapping.md](docs/concept-mapping.md) for the full three-way mapping between Claude Code, Copilot, and Cursor.

## Documentation

| Doc | Audience | Purpose |
|-----|----------|---------|
| [Quick Start](docs/quickstart.md) | New users | 5-minute setup guide |
| [Architecture](docs/architecture.md) | Everyone | How the five layers work together |
| [Cursor Rules Guide](docs/cursor-rules-guide.md) | Developers | Writing and tuning `.cursor/rules/` |
| [Git Hooks Reference](docs/hooks-reference.md) | Developers | What each hook does, how to customize |
| [Actions Reference](docs/actions-reference.md) | Developers | Workflow details and customization |
| [Migration Checklist](docs/migration-checklist.md) | Migrators | Full phase-by-phase checklist |
| [Concept Mapping](docs/concept-mapping.md) | Claude Code users | Claude Code ↔ Copilot ↔ Cursor mapping |
| [Troubleshooting](docs/troubleshooting.md) | Everyone | Common issues and fixes |

## Requirements

- **Cursor IDE** (any plan that supports Anthropic models)
- **Git** 2.x+
- **Bash** 4.x+ (macOS: `brew install bash` if on ancient system bash)
- **Copilot CLI** (optional but recommended) — `npm install -g @github/copilot`
- **GitHub repo** (for Actions workflows)

## Coexistence with dot-copilot

This repo and [dot-copilot](https://github.com/scottrfrancis/dot-copilot) install into non-overlapping directories:

| Directory | dot-copilot | dot-cursor | Conflict? |
|-----------|-------------|------------|-----------|
| `.github/copilot-instructions.md` | ✅ | — | No |
| `.github/instructions/` | ✅ | — | No |
| `.github/agents/` | ✅ | — | No |
| `.github/workflows/` | — | ✅ | No |
| `.cursor/rules/` | — | ✅ | No |
| `.cursor/modes.json` | — | ✅ | No |
| `AGENTS.md` | — | ✅ | No — both tools read it |
| `session-logs/` | — | ✅ | No |

Run both installers on the same project. They're additive.

## License

MIT

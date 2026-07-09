# CLAUDE.md

This file provides guidance to Claude Code when working on this repository.

## Project Purpose

This repository installs Cursor IDE configuration into any target project. It generates Cursor rules (`.mdc` files), custom subagents, git lifecycle hooks, and GitHub Actions workflows.

It works **standalone** — Claude Code / `~/.claude/` is not required. When `~/.claude/` is available on the same machine, the installer can optionally read its guidelines and commands as a source of rules; when it is not, the installer falls back to the local `templates/` and inline defaults (see `--no-global` in `install.sh`).

## Repository Structure

```
dot-cursor/
├── bin/                          # Three installer scripts
│   ├── migrate-to-cursor.sh     # Phase 1: Cursor rules + agents + AGENTS.md
│   ├── setup-hooks.sh           # Phase 2: Git lifecycle hooks
│   └── setup-actions.sh         # Phase 3: GitHub Actions workflows
├── docs/                        # Reference documentation
│   ├── concept-mapping.md       # Claude Code ↔ Copilot ↔ Cursor mapping
│   ├── limitations.md           # What doesn't translate and workarounds
│   ├── architecture.md          # Five-layer automation model
│   ├── cursor-rules-guide.md    # Writing and tuning .mdc rules
│   ├── hooks-reference.md       # Git hook behavior and customization
│   ├── actions-reference.md     # GitHub Actions workflow details
│   ├── migration-checklist.md   # Phase-by-phase migration checklist
│   └── troubleshooting.md       # Common problems and fixes
├── templates/                   # Reusable .mdc rule templates
│   ├── python.mdc               # Python-scoped rules
│   ├── typescript.mdc           # TypeScript-scoped rules
│   ├── docker.mdc               # Docker-scoped rules
│   ├── terraform.mdc            # Terraform-scoped rules
│   ├── always-apply.mdc.template
│   ├── glob-scoped.mdc.template
│   └── AGENTS.md.template
├── workflows/                   # GitHub Actions YAML sources
│   ├── pr-description.yml
│   ├── commit-lint.yml
│   ├── pr-review-checklist.yml
│   ├── session-maintenance.yml
│   └── branch-hygiene.yml
├── install.sh                   # Single entry point (wraps the three bin/ scripts)
├── Makefile                     # make install PROJECT=... (compatibility alias)
└── README.md
```

## Key Concepts

Each component maps to a Claude Code equivalent:

| dot-cursor | Claude Code Equivalent |
|---|---|
| `bin/migrate-to-cursor.sh` | `~/.claude/` infrastructure setup |
| `.cursor/rules/*.mdc` | `~/.claude/guidelines/*.md` |
| `.cursor/modes.json` agents | `~/.claude/commands/*.md` |
| `AGENTS.md` | `CLAUDE.md` (cross-tool version) |
| `session-logs/` | `.claude/session-logs/` |
| Git hooks | `SessionStart` / `Stop` hooks |
| GitHub Actions | — (no Claude Code equivalent) |

The scripts read from `~/.claude/guidelines/` to generate `.cursor/rules/*.mdc` files, so the global guidelines stay as the source of truth. See [docs/concept-mapping.md](docs/concept-mapping.md) for the full three-way mapping.

## Development Guidelines

This repository is standalone and **does not require Claude Code or `~/.claude/` to be installed**. The installer uses `~/.claude/guidelines/` as a source of rules if available (see `--no-global` flag in `install.sh` to skip when absent). Dev-workflow rules below have local copies in `templates/`. The `~/.claude/` paths are optional fallbacks when Claude Code is on the same machine.

- Follow `templates/` conventions (e.g., `testing.mdc`, `python.mdc`) when authoring or modifying `.mdc` templates; optional fallback: `~/.claude/guidelines/` if installed.
- For commit messages: use conventional commits (the dot-cursor installer copies `~/.claude/guidelines/conventional-commits.md` if present; otherwise follow standard conventional-commits format locally).
- For any changes to `bin/` or `install.sh`: follow standard shell-script hygiene (`set -euo pipefail`, `SCRIPT_DIR` detection, cleanup traps); optional fallback: `~/.claude/guidelines/shell-scripts.md` if installed.
- When porting content from `~/.claude/` (only if installed), update both:
  1. The `GUIDELINE_MAP` in `bin/migrate-to-cursor.sh` (Phase 2) for guidelines
  2. The `modes_content` in `bin/migrate-to-cursor.sh` (Phase 4) for commands/agents
  3. The Commands → Agents table in `docs/concept-mapping.md`

## Branch Policy

Work on feature branches. Main is the stable configuration that users clone and run.
<\!-- central-ops-knowledge: begin -->
## Central Ops Knowledge (shared doctrine — all my AI tools)

I maintain ONE central, authoritative **ops-knowledge state** for my homelab/home: **dynamic**
(live, current, queryable by every human and AI on the LAN) and **archival** (durable,
portable, hand-off-able to anyone taking over anything). It lives in the **HomeAssistant repo**
(`/Volumes/workspace/HomeAssistant/` → `home-ops/` OKF bundle + `wiki/`), is surfaced
live to agents via the read-only **`kb-mcp` filesystem MCP** (`mini.local:8092`, tools
`search`/`read_file`/`list_dir`; registered in **Hazel**/OpenWebUI and reusable by any MCP
client) and to humans via **`kb-static`** browse (`mini.local:8090`), and kept current by the
`tools/*-scan.sh` self-tracking probes. (Ingesting the bundle into the **Librarian RAG** is on
indefinite hold — the MCP reads markdown live, no re-index.) Full doctrine:
`~/.claude/guidelines/central-ops-knowledge.md`.

Operating rules for every agent (Claude, OpenCode, Codex, Cursor, Droid, Copilot…):
1. **Consult before acting on infrastructure** — before stopping/changing a service, host, or
   config, check the knowledge base for "what is this and *why*." Stale assumptions cause outages.
2. **Write back** — when you learn or change something about the ops state, record or flag it so
   it stays current. Session-only knowledge is lost.
3. **OKF form** — plain markdown + YAML, **no secrets** (pointers only), conformant for any tool.
4. **Local-first / WAN-tolerant** — prefer local LLM/files/Kiwix; must work with the internet down.
5. **Respect boundaries** — household surfaces LAN-only; don't touch non-Scott tailnet hosts.
<\!-- central-ops-knowledge: end -->

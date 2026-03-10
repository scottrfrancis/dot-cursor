# CLAUDE.md

This file provides guidance to Claude Code when working on this repository.

## Project Purpose

This repository installs Cursor IDE configuration from your `~/.claude/` infrastructure. It reads global guidelines and commands, then generates Cursor rules (`.mdc` files), custom agents (`modes.json`), git lifecycle hooks, and GitHub Actions workflows into any target project.

It is the Cursor equivalent of `~/.claude/` — the same session protocol, the same agents, the same guidelines — adapted to Cursor's format and automation model.

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

- Follow `~/.claude/guidelines/conventional-commits.md` for commit messages
- Follow `~/.claude/guidelines/shell-scripts.md` for any changes to `bin/` or `install.sh`
- When porting content from `~/.claude/` (new guidelines, new commands), update both:
  1. The `GUIDELINE_MAP` in `bin/migrate-to-cursor.sh` (Phase 2) for guidelines
  2. The `modes_content` in `bin/migrate-to-cursor.sh` (Phase 4) for commands/agents
  3. The Commands → Agents table in `docs/concept-mapping.md`

## Branch Policy

Work on feature branches. Main is the stable configuration that users clone and run.

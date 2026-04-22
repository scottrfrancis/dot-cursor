# Quick Start

Get from zero to a fully configured Cursor project in 5 minutes.

## Prerequisites

- [Cursor IDE](https://cursor.sh) installed with Anthropic model access
- Git 2.x+ and Bash 4.x+
- A project with a git repo

**No `~/.claude/` required.** dot-cursor ships all rule content in `templates/*.mdc` and installs it directly. If `~/.claude/guidelines/` happens to be present, the installer will merge your local bodies with the bundled frontmatter (opt out with `--no-global`).

## Step 1: Clone dot-cursor

```bash
git clone https://github.com/scottrfrancis/dot-cursor.git ~/dot-cursor
```

## Step 2: Install into your project

```bash
cd ~/dot-cursor
make install PROJECT=/path/to/your/project
```

This runs three scripts in sequence:

1. **`migrate-to-cursor.sh`** — Generates `.cursor/rules/`, custom agents in `.cursor/modes.json`, `AGENTS.md`, and `.cursorignore`
2. **`setup-hooks.sh`** — Installs git hooks for activity logging, commit templates, handoff surfacing, and push guards
3. **`setup-actions.sh`** — Copies GitHub Actions workflows for PR automation, commit linting, and session maintenance

## Step 3: Configure Cursor User Rules

```bash
cat /path/to/your/project/generated/cursor-user-rules.txt
```

Copy the output and paste it into **Cursor → Settings → Rules → User Rules**. This sets your global preferences (applies across all projects in Cursor).

## Step 4: Commit and push

```bash
cd /path/to/your/project
git add .cursor/ .github/workflows/ AGENTS.md .cursorignore
git commit -m "build: add Cursor rules, agents, git hooks, and CI workflows"
git push
```

## Step 5: Create GitHub labels

Go to your repo's **Settings → Labels → New label** and create:
- `session-maintenance` — used by the stale handoff detection workflow
- `branch-hygiene` — used by the weekly branch cleanup workflow

## Step 6: Start working

Open the project in Cursor and try these:

| Action | How |
|--------|-----|
| Start a session | Switch to your branch — the `post-checkout` hook surfaces your last handoff |
| Ask the AI | `Cmd+L` to open Agent chat, type your question |
| Reference a rule | Type `@` in Agent chat, select a rule |
| Use a custom agent | Type `@lets-go` or `@arch-review` in Agent chat |
| Commit | `git commit` — the hook pre-fills a conventional commit template |
| End a session | Type `@session-logger` in Agent chat |
| Hand off | Type `@handoff` in Agent chat |

## What if I already have dot-copilot set up?

Run `make install` anyway. The scripts detect existing `.github/copilot-instructions.md` and `.github/instructions/` files and generate compatible Cursor rules alongside them. Zero conflicts — they use different directories.

## What if I only want part of it?

```bash
make cursor  PROJECT=/path/to/project   # Just Cursor rules + agents
make hooks   PROJECT=/path/to/project   # Just git hooks
make actions PROJECT=/path/to/project   # Just GitHub Actions
```

## What if I want to see what would change first?

```bash
make preview PROJECT=/path/to/project   # Dry-run, prints what would be created
```

## What if I also maintain dot-claude?

If you author rule content in `~/.claude/guidelines/*.md` and want it to flow into dot-cursor's templates:

```bash
cd ~/dot-cursor
make sync-preview    # dry-run — show which templates would change
make sync            # write updates into templates/*.mdc (frontmatter preserved)
git diff templates/  # review before committing
```

The sync script only overwrites bodies, never frontmatter. New guidelines (no matching template) are reported but skipped — create the template manually first with appropriate `description:`, `globs:`, or `alwaysApply:` metadata.

## Next Steps

- [Architecture](architecture.md) — understand how the five layers interact
- [Cursor Rules Guide](cursor-rules-guide.md) — write and tune your own rules
- [Troubleshooting](troubleshooting.md) — common issues and fixes

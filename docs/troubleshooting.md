# Troubleshooting

## Installation Issues

### "Permission denied" when running scripts

```bash
chmod +x bin/*.sh
```

### "bash: bad interpreter" on macOS

macOS ships with Bash 3.x. Some script features require Bash 4+.

```bash
brew install bash
# Scripts use #!/usr/bin/env bash, so this should pick up the new version
bash --version  # Should show 4.x or 5.x
```

### migrate-to-cursor.sh finds no guidelines to convert

The script looks for guidelines in these locations (in order):
1. `~/.claude/guidelines/*.md` (Claude Code global guidelines)
2. `.claude/` or `CLAUDE.md` in the project root
3. `.github/copilot-instructions.md` and `.github/instructions/*.instructions.md` (dot-copilot)

If none exist, the script generates minimal default rules. This is fine — you can add rules manually to `.cursor/rules/` later.

### setup-hooks.sh says "not a git repository"

The target directory must be a git repo. Initialize one first:

```bash
cd /path/to/project
git init
bin/setup-hooks.sh .
```

## Cursor Configuration Issues

### Rules don't appear in Cursor

1. Verify the files exist: `ls .cursor/rules/*.mdc`
2. Check that frontmatter is valid YAML between `---` markers
3. Restart Cursor (rules are loaded on startup)
4. For glob-scoped rules: open a file that matches the glob pattern

### Custom agents (@lets-go, etc.) don't appear

1. Verify `.cursor/modes.json` exists and is valid JSON
2. Custom agents appear in the Agent mode dropdown — click the model name area in the chat panel
3. Restart Cursor after adding `modes.json`
4. Type `@` in chat and look for your agent names

### User Rules not taking effect

User Rules (Settings → Rules → User Rules) are global across all projects. They're plain text, not `.mdc` format.

1. Open Cursor Settings (`Cmd+,`)
2. Search for "Rules"
3. Find "User Rules" section
4. Paste the content from `generated/cursor-user-rules.txt`

### AGENTS.md not being read

Cursor reads `AGENTS.md` from the project root. Verify:
- File is in the workspace root (same level as `.git/`)
- File is named exactly `AGENTS.md` (case-sensitive)
- File isn't empty

## Git Hook Issues

### Hooks aren't firing

1. Check that hooks are executable: `ls -la .git/hooks/`
2. Verify the hook file exists: `cat .git/hooks/post-commit`
3. Look for the `CURSOR-MIGRATION-HOOK` marker in the file
4. Test manually: `.git/hooks/post-commit`

### prepare-commit-msg detects wrong commit type

The type detection is heuristic. Override by editing the template before saving:

```bash
git commit
# Editor opens with: feat(api): 
# Change to: fix(api): correct rate limit header
```

Or provide the message directly:

```bash
git commit -m "fix(api): correct rate limit header"
```

### post-commit reminders are annoying

Edit `.git/hooks/post-commit` and change the thresholds:

```bash
# Change these values
SESSION_REMINDER_THRESHOLD=5  # Default: 5 commits
HANDOFF_REMINDER_THRESHOLD=8  # Default: 8 commits
```

Or remove the reminder section entirely — the activity logging is independent.

### pre-push blocks my WIP commit

By design — WIP commits on main/master are blocked. Options:

1. **Reword the commit:** `git rebase -i` and change "WIP" to a proper message
2. **Force push anyway:** `git push --no-verify`
3. **Push to a feature branch first**, then PR

### Hooks conflict with existing hooks

The installer detects existing hooks and chains them. If you see issues:

1. Check for `.backup` files: `ls .git/hooks/*.backup`
2. The original hook is called first, then the new hook runs
3. To restore originals: `bin/setup-hooks.sh --uninstall /path/to/project`

### session-logs/ directory is getting large

This is handled automatically if Actions `session-maintenance.yml` is installed (archives files older than 30 days). If not using Actions, run the local cron archiver:

```bash
bin/setup-hooks.sh --install-cron /path/to/project
```

## GitHub Actions Issues

### Workflows don't appear in the Actions tab

1. Verify files are in `.github/workflows/`: `ls .github/workflows/*.yml`
2. Push the workflow files to the default branch
3. GitHub only detects workflows on the default branch (usually `main`)

### session-maintenance workflow fails with permission error

The workflow needs `contents: write` permission. In repos with restricted token permissions:

1. Go to Settings → Actions → General → Workflow permissions
2. Select "Read and write permissions"
3. Or add explicit permissions in the workflow YAML (already included)

### Labels don't exist error

Create the required labels:

1. Go to your repo → Settings → Labels → New label
2. Create: `session-maintenance`
3. Create: `branch-hygiene`

### PR description overwrites my edits

The workflow checks for the `<!-- auto-description -->` marker. Remove this marker from the PR body to prevent future overwrites:

1. Edit the PR description
2. Delete the `<!-- auto-description -->` comment line
3. Subsequent pushes won't overwrite your text

### commit-lint fails on merge commits

Merge commits are explicitly allowed. If you're seeing failures on merge commits, check that they start with "Merge" (the standard git format).

### Actions using too many minutes

Check your usage in Settings → Billing → Actions. The workflows are lightweight:
- PR workflows: ~30 seconds each
- Session maintenance: ~1 minute daily
- Branch hygiene: ~1 minute weekly

Total: roughly 30–40 minutes/month for an active repo, well within the free tier (2,000 min/month).

## Coexistence Issues

### Conflict between .cursor/ and .github/

There should be no conflicts. `.cursor/` is Cursor-specific, `.github/` is shared between Copilot CLI and Actions. They use different subdirectories within `.github/`:
- `.github/copilot-instructions.md` — Copilot CLI
- `.github/instructions/` — Copilot CLI scoped instructions
- `.github/agents/` — Copilot CLI agents
- `.github/workflows/` — GitHub Actions

### AGENTS.md vs .cursor/rules/ — what goes where?

- **AGENTS.md**: Cross-tool instructions that any AI tool should follow (Cursor, Copilot CLI, Codex, Gemini CLI)
- **`.cursor/rules/`**: Cursor-specific behavior — rule types, model preferences, IDE integration details

Don't duplicate content. If a guideline applies to all tools, put it in `AGENTS.md`. If it's Cursor-specific, put it in rules.

## Performance Issues

### Cursor feels slow with many rules

Each Always Apply rule loads into every conversation. Check your rule count:

```bash
grep -l "alwaysApply: true" .cursor/rules/*.mdc | wc -l
```

If you have more than 3–4 Always Apply rules, consider converting some to glob-scoped or Agent Requested types.

### Context window feels too small

Cursor's effective context is 70–120K tokens (vs Claude Code's 200K). Strategies:
- Start new conversations more frequently (don't let them grow to 50+ messages)
- Use precise `@file` references instead of `@codebase`
- Keep rules concise (under 50 lines each)
- Use `.cursorignore` to exclude irrelevant files from AI indexing

## Getting Help

If something isn't covered here:

1. Check the [Architecture doc](architecture.md) to understand how the layers interact
2. Review the specific reference doc ([Hooks](hooks-reference.md), [Actions](actions-reference.md), [Rules](cursor-rules-guide.md))
3. Open an issue on the [dot-cursor repo](https://github.com/scottrfrancis/dot-cursor/issues)

# Git Hooks Reference

All hooks are installed by `bin/setup-hooks.sh` and marked with `CURSOR-MIGRATION-HOOK` for clean identification and uninstall.

## Installed Hooks

### prepare-commit-msg

**Fires:** When you run `git commit` (before the editor opens)

**What it does:**
1. Analyzes the staged diff to detect commit type (feat, fix, test, docs, ci, build, style, refactor)
2. Determines scope from the common parent directory of changed files
3. Pre-fills the commit message template: `type(scope): `
4. Appends the diff summary as comments (visible in editor, stripped from final message)

**Detection logic:**
| Changed Files Pattern | Detected Type |
|----------------------|---------------|
| `test/`, `*_test.*`, `*.spec.*` | `test` |
| `*.md`, `docs/`, `README` | `docs` |
| `.github/workflows/`, `Jenkinsfile` | `ci` |
| `Dockerfile`, `Makefile`, `package.json` | `build` |
| `*.css`, `*.scss`, formatting-only | `style` |
| Everything else | `feat` (default) |

**Customization:**
- Edit the `detect_type()` function in `.git/hooks/prepare-commit-msg` to add project-specific patterns
- The hook skips if a message is already provided (`git commit -m "..."`)
- Bypass entirely with `git commit --no-verify`

### post-commit

**Fires:** After every successful commit

**What it does:**
1. Creates/appends to `session-logs/activity-YYYY-MM-DD.md` with a markdown table row: time, commit hash, changed file count, subject
2. Counts total commits today
3. At **5+ commits** without a session log today: prints reminder to run `@session-logger`
4. At **8+ commits** without a handoff today: prints reminder to run `@handoff`

**Log format:**
```markdown
# Activity — 2026-03-02

| Time | Hash | Files | Subject |
|------|------|-------|---------|
| 14:23 | a1b2c3d | 3 | feat(api): add rate limiting middleware |
| 14:45 | e4f5g6h | 1 | test(api): add rate limiter tests |
```

**Customization:**
- Change commit thresholds (5/8) by editing the hook directly
- Disable reminders by removing the threshold checks
- Change log directory by modifying `SESSION_DIR`

### post-checkout

**Fires:** When switching branches (`git checkout`, `git switch`)

**What it does:**
1. Detects branch checkouts (skips file-level checkouts)
2. Finds the most recent handoff file in `session-logs/` (less than 7 days old)
3. Displays: branch name, handoff age in hours, file path, 5-line content preview
4. Shows count of session logs since the branch was created

**Output example:**
```
╔═══════════════════════════════════════════════════════╗
║  Session Context Available                            ║
╠═══════════════════════════════════════════════════════╣
║  Branch: feature/rate-limiter                         ║
║  Last handoff: 4 hours ago                            ║
║  File: session-logs/handoff-2026-03-02-1400.md        ║
╠═══════════════════════════════════════════════════════╣
║  Preview:                                             ║
║  ## Next Steps                                        ║
║  - Finish rate limiter integration tests              ║
║  - Wire up Redis backend for distributed counting     ║
║  - Update API docs with rate limit headers            ║
╚═══════════════════════════════════════════════════════╝
```

**Customization:**
- Change the staleness threshold (7 days) in the hook
- Modify the preview line count (default: 5)

### pre-push

**Fires:** Before `git push` sends commits to remote

**What it does:**
1. Counts unpushed commits — warns at 10+
2. Scans commit messages for WIP indicators: `WIP`, `fixup!`, `squash!`, `tmp`, `hack`
3. **Blocks** WIP commits on `main`/`master` branches (exits with error code)
4. **Warns** about WIP commits on other branches (non-blocking)
5. Detects files over 5 MB in the push

**Bypass:** `git push --no-verify` skips all checks

**Customization:**
- Add protected branch names by editing the `PROTECTED_BRANCHES` pattern
- Change the file size threshold (5 MB default)
- Change WIP detection patterns

### post-merge

**Fires:** After `git pull` or `git merge`

**What it does:**
1. Counts total changed files from the merge
2. Scans for critical file changes:
   - `package.json`, `requirements.txt`, `pyproject.toml`, `go.mod`, `Cargo.toml` → reminds to install deps
   - `Dockerfile`, `docker-compose*` → reminds to rebuild
   - `.env*` → reminds to check env vars
   - `AGENTS.md`, `.cursor/`, `CLAUDE.md` → flags AI instruction changes
3. Reminds to run `npm install`, `pip install`, etc. when dependencies changed

## Hook Chaining

If a hook already exists when `setup-hooks.sh` runs, the script:
1. Backs up the existing hook to `hookname.backup`
2. Prepends a chain call that runs the backup first
3. Adds the new hook behavior after the existing hook completes

This means your pre-existing hooks still run. The new behavior is additive.

## Installation

```bash
# Install hooks into a project
bin/setup-hooks.sh /path/to/project

# Install hooks + optional local cron jobs
bin/setup-hooks.sh --install-cron /path/to/project

# Remove hooks (restores backups if they exist)
bin/setup-hooks.sh --uninstall /path/to/project
```

## Important: Not Version Controlled

`.git/hooks/` is not tracked by git. This means:
- Hooks must be installed per clone with `bin/setup-hooks.sh`
- Consider adding a `make setup` target or documenting in README
- CI environments don't get these hooks (that's what Actions are for)
- New team members need to run the install after cloning

## Copilot CLI Integration

The hooks installer also creates `.cursor/scripts/ai-assist.sh`, a wrapper for Copilot CLI automation. It auto-detects available Copilot CLI tools (`ghcs`, `gh copilot`) and provides:

- `ai-assist.sh commit-msg` — Generate commit message from diff
- `ai-assist.sh session-summary` — Summarize today's activity log

Falls back to templates when no AI CLI is available.

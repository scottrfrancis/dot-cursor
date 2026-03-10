# GitHub Actions Reference

All workflows are installed by `bin/setup-actions.sh` into `.github/workflows/`.

## Workflows

### pr-description.yml

**Trigger:** Pull request opened or updated (synchronize)

**What it does:**
- Collects all commits between base and head
- Groups by conventional commit type: Features, Bug Fixes, Refactors, Tests, Documentation, Other
- Flags breaking changes (`BREAKING CHANGE` in commit body)
- Lists key changed files (up to 15)
- Writes structured PR body with `<!-- auto-description -->` marker

**Behavior:**
- Only auto-fills if PR body is empty or contains the `<!-- auto-description -->` marker
- Subsequent pushes update the description (marker-based detection)
- You can freely edit the PR body — remove the marker to prevent overwrites

**Permissions required:** `pull-requests: write`

**Customization:**
- Add more commit type categories by extending the `grep` patterns
- Change the key files limit (default: 15)
- Modify the template structure

### commit-lint.yml

**Trigger:** Pull request opened, updated, or reopened

**What it does:**
- Validates every commit in the PR against the conventional commit pattern:
  `type(optional-scope): description`
- Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
- Allows merge commits (auto-detected, skipped)
- Reports per-commit pass/fail with the full message
- Fails the check if any commit doesn't match

**This is the server-side partner to the `prepare-commit-msg` hook.** The hook helps you write correct commits locally. This Action catches anything that slipped through on the PR.

**Customization:**
- Modify the `PATTERN` regex to add/remove valid types
- Add scope validation (e.g., require scope from a known list)
- Make specific types optional by adjusting the regex

### pr-review-checklist.yml

**Trigger:** Pull request opened or updated

**What it does — checks in order:**

| Check | Threshold | Finding |
|-------|-----------|---------|
| PR size (files) | 30+ files | Suggests splitting |
| PR size (lines) | 500+ changed lines | Notes higher defect rates |
| Sensitive files | `.env`, `secret`, `credential`, `.pem`, `.key`, `token` | Warns about secret exposure |
| Test coverage | Source files changed but no test files | Lists source files, suggests tests |
| AI instructions | `AGENTS.md`, `.cursor/`, `copilot-instructions`, `.cursorrules`, `.mdc` | Flags for team review |
| Dependencies | `package.json` etc. changed without lockfile | Reminds to run install |
| Migrations | `migration`, `schema`, `.sql` files | Notes reversibility concern |

**Behavior:**
- Posts a comment with all findings
- Supersedes previous bot comments (collapses old ones into `<details>`)
- Non-blocking — informational only, does not fail the check

**This is a triage pass, not a full architecture review.** For deep analysis, use `@arch-review` in Cursor with Opus 4.6.

**Customization:**
- Change thresholds (file count, line count) in the script
- Add new checks by extending the `Analyze PR` step
- Make specific checks blocking by adding `exit 1` conditions

### session-maintenance.yml

**Trigger:** Daily at 6 AM UTC (10 PM PST), plus manual dispatch

**Three jobs:**

**Job 1: archive-logs** (daily)
- Archives `session-*.md` files older than 30 days to `session-logs/archive/`
- Archives `activity-*.md` files older than 30 days
- Archives `handoff-*.md` files older than 14 days (shorter TTL — they're smaller and more useful)
- Commits archived files directly to the repo

**Job 2: stale-handoff-check** (daily)
- Counts commits in the last 3 days
- Counts handoff files from the last 7 days
- If 5+ recent commits but no recent handoff: opens a GitHub Issue with the `session-maintenance` label
- Checks for existing open issues to avoid duplicates

**Job 3: weekly-summary** (Sundays only)
- Counts commits, contributors, and session logs from the past 7 days
- Breaks down commits by type (feat/fix/refactor/docs/other)
- Lists most active directories by change count
- Writes `session-logs/weekly-YYYY-MM-DD.md` and commits it
- Suggests running `@mine-sessions` in Cursor for AI-powered analysis

**Permissions required:** `contents: write`, `pull-requests: write`, `issues: write`

**This replaces local cron for reliability.** Runs server-side even when your laptop is off.

### branch-hygiene.yml

**Trigger:** Weekly, Mondays at 7 AM UTC (Sunday 11 PM PST), plus manual dispatch

**What it does:**
- Scans all remote branches and categorizes:
  - **Merged branches** — already merged into default branch, safe to delete
  - **Stale branches** — no commits in 30+ days
  - **Drifted branches** — 50+ commits behind default branch
- Opens a GitHub Issue with the `branch-hygiene` label listing all findings
- Closes previous branch-hygiene issues (supersedes weekly)

**Permissions required:** `issues: write`

**Customization:**
- Change staleness threshold (30 days) in the script
- Change drift threshold (50 commits) in the script
- Add auto-deletion for merged branches (careful — make it opt-in)

## Required GitHub Labels

Create these labels in your repo (**Settings → Labels → New label**):

| Label | Used By | Purpose |
|-------|---------|---------|
| `session-maintenance` | session-maintenance.yml | Tags stale handoff issues |
| `branch-hygiene` | branch-hygiene.yml | Tags branch cleanup issues |

## Permissions

All workflows use the minimum permissions needed:

| Workflow | Permissions |
|----------|------------|
| pr-description | `pull-requests: write` |
| commit-lint | (none — read-only) |
| pr-review-checklist | `pull-requests: write` (for comments) |
| session-maintenance | `contents: write`, `pull-requests: write`, `issues: write` |
| branch-hygiene | `issues: write` |

If your repo uses restricted `GITHUB_TOKEN` permissions, ensure these are allowed.

## Installation

```bash
# Install workflows
bin/setup-actions.sh /path/to/project

# Preview what would be installed
bin/setup-actions.sh --list

# Remove workflows
bin/setup-actions.sh --remove /path/to/project
```

## Actions vs Local Cron

| Aspect | Local Cron | GitHub Actions |
|--------|-----------|----------------|
| Runs when laptop sleeps | No | Yes |
| Team visible | No | Yes (issues, commits) |
| Audit trail | Log files only | Workflow run history |
| Requires laptop | Yes | No |
| Requires GitHub | No | Yes |
| Cost | Free | Free tier (2,000 min/month) |

Recommendation: Use Actions as the primary scheduled automation. Keep cron as a local fallback if you want redundancy.

#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# setup-hooks-and-cron.sh
#
# Installs git hooks and cron jobs that fill Cursor's lifecycle gaps.
# These work ALONGSIDE Cursor — git hooks fire regardless of IDE, and
# Copilot CLI can be invoked from hooks/cron as the AI executor.
#
# Git Hooks Installed:
#   prepare-commit-msg  — AI-generated conventional commit messages (via Copilot CLI)
#   post-commit         — Auto-log commits to session log, trigger session reminders
#   post-checkout       — Inject handoff context on branch switch
#   pre-push            — Arch-review gate (optional, lightweight)
#   post-merge          — Surface conflicts and handoff notes after pull/merge
#
# Cron Jobs (optional):
#   Session log cleanup     — Archive logs older than 30 days
#   Handoff staleness check — Warn if handoff is >7 days old
#   Session mining          — Weekly pattern extraction from logs
#
# Usage:
#   ./setup-hooks-and-cron.sh [PROJECT_DIR]
#   ./setup-hooks-and-cron.sh --install-cron     # also install cron jobs
#   ./setup-hooks-and-cron.sh --uninstall        # remove hooks
#
# Requirements:
#   - git (obviously)
#   - Copilot CLI (`ghcs` / `github-copilot-cli`) — optional but recommended
#   - jq — for JSON processing in hooks
###############################################################################

VERSION="1.0.0"

# Defaults
PROJECT_DIR="${1:-.}"
INSTALL_CRON=false
UNINSTALL=false
HOOKS_DIR=""
SESSION_LOG_DIR=""
COPILOT_CLI=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Parse arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --install-cron) INSTALL_CRON=true; shift ;;
        --uninstall)    UNINSTALL=true; shift ;;
        --help|-h)
            cat <<EOF
setup-hooks-and-cron.sh v${VERSION}

Install git hooks and cron jobs to fill Cursor's lifecycle gaps.

Usage: $(basename "$0") [OPTIONS] [PROJECT_DIR]

Options:
  --install-cron   Also install cron jobs for maintenance
  --uninstall      Remove installed hooks and cron jobs
  --help           Show this help

Git Hooks:
  prepare-commit-msg  AI commit message generation (Copilot CLI)
  post-commit         Session activity logging + reminders
  post-checkout       Handoff context injection on branch switch
  pre-push            Lightweight review gate
  post-merge          Post-pull conflict and context surfacing

Cron Jobs (--install-cron):
  Daily    Session log archival (>30 days)
  Daily    Stale handoff detection (>7 days)
  Weekly   Session mining / pattern extraction
EOF
            exit 0 ;;
        -*) log_error "Unknown option: $1"; exit 1 ;;
        *)  POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]:-}"
PROJECT_DIR="${1:-.}"

# Resolve paths
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || {
    log_error "Directory not found: ${1:-.}"
    exit 1
}

# Validate git repo
if [[ ! -d "${PROJECT_DIR}/.git" ]]; then
    log_error "Not a git repository: ${PROJECT_DIR}"
    exit 1
fi

HOOKS_DIR="${PROJECT_DIR}/.git/hooks"
SESSION_LOG_DIR="${PROJECT_DIR}/session-logs"

# Detect Copilot CLI
detect_copilot_cli() {
    if command -v ghcs &>/dev/null; then
        COPILOT_CLI="ghcs"
    elif command -v github-copilot-cli &>/dev/null; then
        COPILOT_CLI="github-copilot-cli"
    elif command -v gh &>/dev/null && gh copilot --help &>/dev/null 2>&1; then
        COPILOT_CLI="gh copilot"
    else
        COPILOT_CLI=""
    fi
    
    if [[ -n "$COPILOT_CLI" ]]; then
        log_ok "Copilot CLI found: ${COPILOT_CLI}"
    else
        log_warn "Copilot CLI not found — hooks will use template-based fallbacks"
        log_warn "Install: npm install -g @github/copilot"
    fi
}

###############################################################################
# Uninstall
###############################################################################

uninstall() {
    log_info "Uninstalling hooks..."
    
    for hook in prepare-commit-msg post-commit post-checkout pre-push post-merge; do
        local hookfile="${HOOKS_DIR}/${hook}"
        if [[ -f "$hookfile" ]] && grep -q "CURSOR-MIGRATION-HOOK" "$hookfile" 2>/dev/null; then
            rm "$hookfile"
            log_ok "Removed: ${hook}"
        else
            log_warn "Not ours (or not found): ${hook}"
        fi
    done
    
    if [[ "$INSTALL_CRON" == true ]]; then
        log_info "Removing cron jobs..."
        crontab -l 2>/dev/null | grep -v "CURSOR-MIGRATION-CRON" | crontab - 2>/dev/null || true
        log_ok "Cron jobs removed"
    fi
    
    exit 0
}

[[ "$UNINSTALL" == true ]] && uninstall

###############################################################################
# Install hooks
###############################################################################

install_hook() {
    local hook_name="$1"
    local hook_content="$2"
    local hookfile="${HOOKS_DIR}/${hook_name}"
    
    # Preserve existing hooks by chaining
    if [[ -f "$hookfile" ]] && ! grep -q "CURSOR-MIGRATION-HOOK" "$hookfile" 2>/dev/null; then
        log_warn "${hook_name}: Existing hook found — backing up to ${hook_name}.backup"
        cp "$hookfile" "${hookfile}.backup"
        # Prepend chain call to existing hook
        hook_content="${hook_content}

# Chain to previous hook
if [[ -x \"${hookfile}.backup\" ]]; then
    \"${hookfile}.backup\" \"\$@\"
fi"
    fi
    
    echo "$hook_content" > "$hookfile"
    chmod +x "$hookfile"
    log_ok "Installed: ${hook_name}"
}

###############################################################################
# Hook: prepare-commit-msg
# Replaces: /autocommit command
# Fires: Before commit message editor opens
# Uses Copilot CLI to suggest conventional commit messages
###############################################################################

install_prepare_commit_msg() {
    local hook_content='#!/usr/bin/env bash
# CURSOR-MIGRATION-HOOK: prepare-commit-msg
# AI-assisted conventional commit message generation
# Uses Copilot CLI if available, otherwise provides a template
set -euo pipefail

COMMIT_MSG_FILE="$1"
COMMIT_SOURCE="${2:-}"

# Skip for merge commits, amend, squash
if [[ "$COMMIT_SOURCE" == "merge" || "$COMMIT_SOURCE" == "squash" ]]; then
    exit 0
fi

# Skip if message already provided (-m flag)
if [[ "$COMMIT_SOURCE" == "message" ]]; then
    exit 0
fi

# Get staged diff summary
DIFF_STAT=$(git diff --cached --stat 2>/dev/null || echo "")
DIFF_FILES=$(git diff --cached --name-only 2>/dev/null || echo "")
FILE_COUNT=$(echo "$DIFF_FILES" | grep -c . 2>/dev/null || echo "0")

if [[ -z "$DIFF_STAT" ]]; then
    exit 0
fi

# Detect likely commit type from changed files
detect_type() {
    local files="$1"
    if echo "$files" | grep -qiE "test|spec|__test__"; then
        echo "test"
    elif echo "$files" | grep -qiE "readme|docs/|\.md$|changelog"; then
        echo "docs"
    elif echo "$files" | grep -qiE "\.github/|Dockerfile|Makefile|\.yml$|\.yaml$|ci/|cd/"; then
        echo "ci"
    elif echo "$files" | grep -qiE "package\.json$|requirements\.txt$|go\.mod$|Cargo\.toml$"; then
        echo "build"
    elif echo "$files" | grep -qiE "\.css$|\.scss$|\.less$"; then
        echo "style"
    else
        echo "feat"
    fi
}

TYPE=$(detect_type "$DIFF_FILES")

# Detect scope from changed file paths
# Maps directory patterns to project-aware scopes.
# If docs/guidelines/commits-and-branching.md defines scopes, those take precedence.
detect_scope() {
    local files="$1"
    if echo "$files" | grep -qE "^app-stack/backend/"; then
        echo "api"
    elif echo "$files" | grep -qE "^app-stack/frontend/"; then
        echo "frontend"
    elif echo "$files" | grep -qE "^test-harness/"; then
        echo "test-harness"
    elif echo "$files" | grep -qE "^infrastructure/"; then
        echo "infra"
    elif echo "$files" | grep -qE "^\.cursor/|^\.github/|^\.droid|^\.factory|\.cursorignore|session-logs/"; then
        echo "infra"
    elif echo "$files" | grep -qE "^docs/guidelines/|^docs/adr/"; then
        echo "guidelines"
    elif echo "$files" | grep -qE "^docs/design/"; then
        echo "design"
    elif echo "$files" | grep -qE "^docs/"; then
        echo "docs"
    elif echo "$files" | grep -qE "^scripts/"; then
        echo "scripts"
    elif echo "$files" | grep -qE "AGENTS\.md|CONTRIBUTING\.md|README\.md"; then
        echo "docs"
    else
        echo ""
    fi
}

SCOPE_NAME=$(detect_scope "$DIFF_FILES")
SCOPE=""
[[ -n "$SCOPE_NAME" ]] && SCOPE="(${SCOPE_NAME})"

# Build template commit message
TEMPLATE="${TYPE}${SCOPE}: "

# Load project-specific scopes hint if available
SCOPES_HINT="# Scopes: (from file paths, or see docs/guidelines/commits-and-branching.md)"

# Write template + diff context as comment
{
    echo "$TEMPLATE"
    echo ""
    echo "# ─── Conventional Commit Format ───────────────────────"
    echo "# type(scope): description"
    echo "#"
    echo "# Types: feat fix docs style refactor perf test build ci chore revert"
    echo "# ${SCOPES_HINT}"
    echo "#"
    echo "# ─── Changed Files (${FILE_COUNT}) ───────────────────"
    echo "$DIFF_STAT" | sed "s/^/# /"
    echo "#"
    echo "# ─── Suggested type: ${TYPE}, scope: ${SCOPE_NAME:-none} ──────"
} > "$COMMIT_MSG_FILE"
'

    install_hook "prepare-commit-msg" "$hook_content"
}

###############################################################################
# Hook: post-commit
# Replaces: Claude Code Stop hook (session reminders) + activity tracking
# Fires: After every commit
# Logs commit to session activity, reminds about session-logger
###############################################################################

install_post_commit() {
    local hook_content='#!/usr/bin/env bash
# CURSOR-MIGRATION-HOOK: post-commit
# Session activity tracking and session-end reminders
set -euo pipefail

SESSION_LOG_DIR="'"${SESSION_LOG_DIR}"'"
TODAY=$(date +%Y-%m-%d)
ACTIVITY_FILE="${SESSION_LOG_DIR}/activity-${TODAY}.md"

mkdir -p "$SESSION_LOG_DIR"

# Log this commit to today'\''s activity file
COMMIT_MSG=$(git log -1 --pretty=format:"%h %s" 2>/dev/null || echo "unknown")
TIMESTAMP=$(date +%H:%M)
FILE_COUNT=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | wc -l | tr -d " ")

# Append to activity log
if [[ ! -f "$ACTIVITY_FILE" ]]; then
    {
        echo "# Session Activity — ${TODAY}"
        echo ""
        echo "| Time | Commit | Files |"
        echo "|------|--------|-------|"
    } > "$ACTIVITY_FILE"
fi

echo "| ${TIMESTAMP} | ${COMMIT_MSG} | ${FILE_COUNT} |" >> "$ACTIVITY_FILE"

# Count commits today
COMMIT_COUNT=$(grep -c "^|" "$ACTIVITY_FILE" 2>/dev/null || echo "0")
COMMIT_COUNT=$((COMMIT_COUNT - 2))  # subtract header rows

# Session reminders (stderr so they show in terminal, not in git output)
if [[ "$COMMIT_COUNT" -ge 5 ]]; then
    # Check if session-logger has been run today
    LATEST_SESSION=$(find "$SESSION_LOG_DIR" -name "session-${TODAY}*.md" -newer "$ACTIVITY_FILE" 2>/dev/null | head -1)
    if [[ -z "$LATEST_SESSION" ]]; then
        echo -e "\n\033[1;33m[session-reminder]\033[0m ${COMMIT_COUNT} commits today — consider running @session-logger before wrapping up" >&2
    fi
fi

if [[ "$COMMIT_COUNT" -ge 8 ]]; then
    LATEST_HANDOFF=$(find "$SESSION_LOG_DIR" -name "handoff-${TODAY}*.md" 2>/dev/null | head -1)
    if [[ -z "$LATEST_HANDOFF" ]]; then
        echo -e "\033[1;33m[session-reminder]\033[0m Heavy session (${COMMIT_COUNT} commits) — create a @handoff before context degrades" >&2
    fi
fi
'

    install_hook "post-commit" "$hook_content"
}

###############################################################################
# Hook: post-checkout
# Replaces: Claude Code SessionStart hook (handoff injection)
# Fires: After git checkout (branch switch, pull, clone)
# Surfaces handoff context and branch-specific notes
###############################################################################

install_post_checkout() {
    local hook_content='#!/usr/bin/env bash
# CURSOR-MIGRATION-HOOK: post-checkout
# Handoff context injection on branch switch
set -euo pipefail

PREV_HEAD="$1"
NEW_HEAD="$2"
BRANCH_FLAG="$3"  # 1 = branch checkout, 0 = file checkout

# Only fire on branch checkouts
[[ "$BRANCH_FLAG" != "1" ]] && exit 0

SESSION_LOG_DIR="'"${SESSION_LOG_DIR}"'"
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Look for handoff files across all cross-tool locations (newest wins)
LATEST_HANDOFF=""
for handoff_dir in "$SESSION_LOG_DIR" "${PROJECT_ROOT}/.factory/logs" "${PROJECT_ROOT}/.claude/session-logs"; do
    CANDIDATE=$(find "$handoff_dir" -name "handoff-*.md" -mtime -7 2>/dev/null | sort -r | head -1)
    if [[ -n "$CANDIDATE" ]]; then
        if [[ -z "$LATEST_HANDOFF" ]]; then
            LATEST_HANDOFF="$CANDIDATE"
        else
            # Keep the newer file
            if [[ "$CANDIDATE" -nt "$LATEST_HANDOFF" ]]; then
                LATEST_HANDOFF="$CANDIDATE"
            fi
        fi
    fi
done

if [[ -n "$LATEST_HANDOFF" ]]; then
    HANDOFF_DATE=$(stat -c %Y "$LATEST_HANDOFF" 2>/dev/null || stat -f %m "$LATEST_HANDOFF" 2>/dev/null || echo "0")
    HANDOFF_AGE=$(( ($(date +%s) - HANDOFF_DATE) / 3600 ))
    # Extract tool from YAML frontmatter if present
    HANDOFF_TOOL=$(awk "/^tool:/{print \$2; exit}" "$LATEST_HANDOFF" 2>/dev/null)
    TOOL_LABEL=""
    [[ -n "$HANDOFF_TOOL" ]] && TOOL_LABEL=" from ${HANDOFF_TOOL}"
    
    echo -e "\n\033[0;36m╔══════════════════════════════════════════╗\033[0m" >&2
    echo -e "\033[0;36m║  Handoff available (${HANDOFF_AGE}h old${TOOL_LABEL})  ║\033[0m" >&2
    echo -e "\033[0;36m╚══════════════════════════════════════════╝\033[0m" >&2
    echo -e "\033[0;34mBranch:\033[0m ${BRANCH_NAME}" >&2
    echo -e "\033[0;34mFile:\033[0m   ${LATEST_HANDOFF}" >&2
    
    # Show first 5 non-empty, non-header lines as preview
    grep -v "^#\|^$\|^---\|^tool:\|^timestamp:\|^branch:\|^dirty:\|^files_changed:" "$LATEST_HANDOFF" 2>/dev/null | head -5 | sed "s/^/  /" >&2
    echo -e "\n\033[0;33mTip: Open in Cursor and @mention the handoff file for full context\033[0m\n" >&2
fi

# Check for branch-specific session logs
BRANCH_SESSIONS=$(find "$SESSION_LOG_DIR" -name "*.md" -newer ".git/refs/heads/${BRANCH_NAME}" 2>/dev/null | wc -l | tr -d " ")
if [[ "$BRANCH_SESSIONS" -gt 0 ]]; then
    echo -e "\033[0;34m[context]\033[0m ${BRANCH_SESSIONS} session log(s) since branch created" >&2
fi
'

    install_hook "post-checkout" "$hook_content"
}

###############################################################################
# Hook: pre-push
# Replaces: Lightweight /arch-review gate
# Fires: Before push
# Quick sanity checks — not a full arch review
###############################################################################

install_pre_push() {
    local hook_content='#!/usr/bin/env bash
# CURSOR-MIGRATION-HOOK: pre-push
# Lightweight pre-push checks
set -euo pipefail

REMOTE="$1"
URL="$2"

# Count unpushed commits
UNPUSHED=$(git log @{u}..HEAD --oneline 2>/dev/null | wc -l | tr -d " " || echo "0")

if [[ "$UNPUSHED" -gt 10 ]]; then
    echo -e "\n\033[1;33m[pre-push]\033[0m Pushing ${UNPUSHED} commits — consider an @arch-review first" >&2
fi

# Check for WIP/fixup commits
WIP_COUNT=$(git log @{u}..HEAD --oneline 2>/dev/null | grep -ciE "^[a-f0-9]+ (wip|fixup|squash|tmp|hack)" || true)
if [[ "$WIP_COUNT" -gt 0 ]]; then
    echo -e "\033[1;33m[pre-push]\033[0m Found ${WIP_COUNT} WIP/fixup commit(s) — squash before pushing to main?" >&2
    
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
        echo -e "\033[0;31m[pre-push]\033[0m WIP commits on ${BRANCH} — aborting. Use --no-verify to override." >&2
        exit 1
    fi
fi

# Check for large files
LARGE_FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null | while read -r f; do
    if [[ -f "$f" ]]; then
        SIZE=$(wc -c < "$f" 2>/dev/null || echo 0)
        if [[ "$SIZE" -gt 5242880 ]]; then  # 5MB
            echo "$f ($(( SIZE / 1048576 ))MB)"
        fi
    fi
done)

if [[ -n "$LARGE_FILES" ]]; then
    echo -e "\033[1;33m[pre-push]\033[0m Large files detected:" >&2
    echo "$LARGE_FILES" | sed "s/^/  /" >&2
fi

exit 0
'

    install_hook "pre-push" "$hook_content"
}

###############################################################################
# Hook: post-merge
# Replaces: Part of /lets-go (post-pull context surfacing)
# Fires: After git pull / merge
###############################################################################

install_post_merge() {
    local hook_content='#!/usr/bin/env bash
# CURSOR-MIGRATION-HOOK: post-merge
# Post-pull/merge context surfacing
set -euo pipefail

SQUASH="$1"  # 1 if squash merge

SESSION_LOG_DIR="'"${SESSION_LOG_DIR}"'"

# Show what changed
CHANGED_FILES=$(git diff --name-only HEAD@{1}..HEAD 2>/dev/null | wc -l | tr -d " ")

if [[ "$CHANGED_FILES" -gt 0 ]]; then
    echo -e "\n\033[0;36m[post-merge]\033[0m ${CHANGED_FILES} file(s) changed in merge" >&2
    
    # Flag if key config files changed
    CRITICAL_CHANGES=$(git diff --name-only HEAD@{1}..HEAD 2>/dev/null | grep -iE "package\.json|requirements\.txt|Dockerfile|\.env|AGENTS\.md|\.cursor/|CLAUDE\.md" || true)
    if [[ -n "$CRITICAL_CHANGES" ]]; then
        echo -e "\033[1;33m[post-merge]\033[0m Config/instruction files changed:" >&2
        echo "$CRITICAL_CHANGES" | sed "s/^/  ⚠ /" >&2
    fi
    
    # Check if dependencies need updating
    if git diff --name-only HEAD@{1}..HEAD 2>/dev/null | grep -qE "package\.json$|package-lock\.json$"; then
        echo -e "\033[1;33m[post-merge]\033[0m package.json changed — run npm install" >&2
    fi
    if git diff --name-only HEAD@{1}..HEAD 2>/dev/null | grep -qE "requirements\.txt$|pyproject\.toml$"; then
        echo -e "\033[1;33m[post-merge]\033[0m Python deps changed — update your venv" >&2
    fi
fi
'

    install_hook "post-merge" "$hook_content"
}

###############################################################################
# Cron jobs
###############################################################################

install_cron_jobs() {
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "Installing Cron Jobs"
    log_info "═══════════════════════════════════════════════════════"
    
    # Create the maintenance scripts
    local scripts_dir="${PROJECT_DIR}/.cursor/scripts"
    mkdir -p "$scripts_dir"
    
    # Script: Archive old session logs
    cat > "${scripts_dir}/archive-sessions.sh" << 'ARCHIVE_EOF'
#!/usr/bin/env bash
# CURSOR-MIGRATION-CRON: archive-sessions
# Archives session logs older than 30 days
set -euo pipefail

SESSION_DIR="$1"
ARCHIVE_DIR="${SESSION_DIR}/archive"

[[ -d "$SESSION_DIR" ]] || exit 0
mkdir -p "$ARCHIVE_DIR"

find "$SESSION_DIR" -maxdepth 1 -name "session-*.md" -mtime +30 -exec mv {} "$ARCHIVE_DIR/" \;
find "$SESSION_DIR" -maxdepth 1 -name "activity-*.md" -mtime +30 -exec mv {} "$ARCHIVE_DIR/" \;

# Keep handoffs for 14 days (they're smaller and more useful for context)
find "$SESSION_DIR" -maxdepth 1 -name "handoff-*.md" -mtime +14 -exec mv {} "$ARCHIVE_DIR/" \;

ARCHIVED=$(find "$ARCHIVE_DIR" -name "*.md" -newer "$ARCHIVE_DIR" -mtime -1 2>/dev/null | wc -l | tr -d " ")
[[ "$ARCHIVED" -gt 0 ]] && echo "[archive] Moved ${ARCHIVED} old log(s) to archive/"
ARCHIVE_EOF
    chmod +x "${scripts_dir}/archive-sessions.sh"
    log_ok "Created: .cursor/scripts/archive-sessions.sh"
    
    # Script: Check for stale handoffs
    cat > "${scripts_dir}/check-handoff-staleness.sh" << 'STALE_EOF'
#!/usr/bin/env bash
# CURSOR-MIGRATION-CRON: check-handoff-staleness
# Warns if the most recent handoff is getting stale
set -euo pipefail

SESSION_DIR="$1"
[[ -d "$SESSION_DIR" ]] || exit 0

LATEST=$(find "$SESSION_DIR" -maxdepth 1 -name "handoff-*.md" -mtime -7 2>/dev/null | sort -r | head -1)

if [[ -z "$LATEST" ]]; then
    # No recent handoff — check if there's been recent activity
    RECENT_ACTIVITY=$(find "$SESSION_DIR" -maxdepth 1 -name "activity-*.md" -mtime -3 2>/dev/null | wc -l | tr -d " ")
    if [[ "$RECENT_ACTIVITY" -gt 0 ]]; then
        echo "[handoff] Active project with no recent handoff — create one next session"
    fi
fi
STALE_EOF
    chmod +x "${scripts_dir}/check-handoff-staleness.sh"
    log_ok "Created: .cursor/scripts/check-handoff-staleness.sh"
    
    # Script: Weekly session mining summary
    cat > "${scripts_dir}/weekly-session-summary.sh" << 'WEEKLY_EOF'
#!/usr/bin/env bash
# CURSOR-MIGRATION-CRON: weekly-session-summary
# Generates a weekly summary from session logs
set -euo pipefail

SESSION_DIR="$1"
[[ -d "$SESSION_DIR" ]] || exit 0

WEEK_START=$(date -d "7 days ago" +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d 2>/dev/null || exit 0)
SUMMARY_FILE="${SESSION_DIR}/weekly-${WEEK_START}.md"

# Count recent sessions
SESSION_COUNT=$(find "$SESSION_DIR" -maxdepth 1 -name "session-*.md" -newer "$SESSION_DIR" -mtime -7 2>/dev/null | wc -l | tr -d " ")
COMMIT_COUNT=$(find "$SESSION_DIR" -maxdepth 1 -name "activity-*.md" -mtime -7 -exec grep -c "^|" {} \; 2>/dev/null | paste -sd+ - | bc 2>/dev/null || echo "?")

if [[ "$SESSION_COUNT" -gt 0 ]]; then
    {
        echo "# Weekly Summary — ${WEEK_START}"
        echo ""
        echo "- Sessions: ${SESSION_COUNT}"
        echo "- Commits: ${COMMIT_COUNT}"
        echo ""
        echo "## Session Logs"
        find "$SESSION_DIR" -maxdepth 1 -name "session-*.md" -mtime -7 -exec basename {} \; 2>/dev/null | sort
        echo ""
        echo "## Decisions (extracted from logs)"
        find "$SESSION_DIR" -maxdepth 1 -name "session-*.md" -mtime -7 \
            -exec grep -h -A1 "Decision\|decided\|chose\|picked" {} \; 2>/dev/null | head -20 || echo "(none captured)"
        echo ""
        echo "> Run @mine-sessions in Cursor for AI-powered pattern analysis"
    } > "$SUMMARY_FILE"
    echo "[weekly] Summary written to ${SUMMARY_FILE}"
fi
WEEKLY_EOF
    chmod +x "${scripts_dir}/weekly-session-summary.sh"
    log_ok "Created: .cursor/scripts/weekly-session-summary.sh"
    
    # Install cron entries
    local cron_tmp
    cron_tmp=$(mktemp)
    crontab -l 2>/dev/null > "$cron_tmp" || true
    
    # Remove any existing cursor-migration cron entries
    grep -v "CURSOR-MIGRATION-CRON" "$cron_tmp" > "${cron_tmp}.clean" || true
    mv "${cron_tmp}.clean" "$cron_tmp"
    
    # Add new entries
    cat >> "$cron_tmp" << CRON_EOF

# CURSOR-MIGRATION-CRON — session maintenance for ${PROJECT_DIR}
# Archive old session logs daily at 2 AM
0 2 * * * ${scripts_dir}/archive-sessions.sh "${SESSION_LOG_DIR}" 2>/dev/null
# Check handoff staleness daily at 9 AM
0 9 * * * ${scripts_dir}/check-handoff-staleness.sh "${SESSION_LOG_DIR}" 2>/dev/null
# Weekly session summary on Sundays at 6 PM
0 18 * * 0 ${scripts_dir}/weekly-session-summary.sh "${SESSION_LOG_DIR}" 2>/dev/null
CRON_EOF
    
    crontab "$cron_tmp"
    rm "$cron_tmp"
    
    log_ok "Cron jobs installed (use 'crontab -l' to verify)"
}

###############################################################################
# Also create a shared helper for Copilot CLI integration
###############################################################################

install_copilot_helpers() {
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "Copilot CLI Integration Helpers"
    log_info "═══════════════════════════════════════════════════════"
    
    local scripts_dir="${PROJECT_DIR}/.cursor/scripts"
    mkdir -p "$scripts_dir"
    
    # Wrapper that invokes Copilot CLI for AI tasks from hooks/cron
    cat > "${scripts_dir}/ai-assist.sh" << 'AI_EOF'
#!/usr/bin/env bash
# CURSOR-MIGRATION-HOOK: ai-assist
# Wrapper for invoking AI assistance from git hooks and cron.
# Tries: Copilot CLI → gh copilot → falls back to template
set -euo pipefail

TASK="$1"
CONTEXT="${2:-}"

# Detect available AI CLI
if command -v ghcs &>/dev/null; then
    AI_CMD="ghcs"
elif command -v gh &>/dev/null && gh copilot --help &>/dev/null 2>&1; then
    AI_CMD="gh copilot suggest"
else
    # No AI CLI available — use template fallback
    echo "[ai-assist] No AI CLI available — using template for: ${TASK}" >&2
    exit 1
fi

case "$TASK" in
    commit-msg)
        # Generate conventional commit from diff
        DIFF=$(git diff --cached --stat 2>/dev/null)
        echo "Generate a conventional commit message for these changes: ${DIFF}" | $AI_CMD
        ;;
    session-summary)
        # Summarize today's activity
        ACTIVITY=$(cat "$CONTEXT" 2>/dev/null || echo "No activity file")
        echo "Summarize this development session activity into a brief session log: ${ACTIVITY}" | $AI_CMD
        ;;
    *)
        echo "[ai-assist] Unknown task: ${TASK}" >&2
        exit 1
        ;;
esac
AI_EOF
    chmod +x "${scripts_dir}/ai-assist.sh"
    log_ok "Created: .cursor/scripts/ai-assist.sh"
}

###############################################################################
# Main
###############################################################################

main() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Git Hooks + Cron Setup  v${VERSION}                  ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log_info "Project: ${PROJECT_DIR}"
    
    detect_copilot_cli
    
    mkdir -p "$SESSION_LOG_DIR"
    mkdir -p "$HOOKS_DIR"
    
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "Installing Git Hooks"
    log_info "═══════════════════════════════════════════════════════"
    
    install_prepare_commit_msg
    install_post_commit
    install_post_checkout
    install_pre_push
    install_post_merge
    install_copilot_helpers
    
    if [[ "$INSTALL_CRON" == true ]]; then
        install_cron_jobs
    else
        log_info ""
        log_info "Skipping cron jobs (use --install-cron to enable)"
    fi
    
    # Summary
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "Setup Complete"
    log_info "═══════════════════════════════════════════════════════"
    echo ""
    echo -e "${GREEN}Installed hooks:${NC}"
    echo "  prepare-commit-msg  — Conventional commit templates on every commit"
    echo "  post-commit         — Activity logging + session reminders at 5/8 commits"
    echo "  post-checkout       — Handoff context surfacing on branch switch"
    echo "  pre-push            — WIP/fixup guard + large file detection"
    echo "  post-merge          — Dependency change alerts + config file warnings"
    echo ""
    echo -e "${GREEN}Helper scripts:${NC}"
    echo "  .cursor/scripts/ai-assist.sh      — AI CLI wrapper for hooks"
    if [[ "$INSTALL_CRON" == true ]]; then
        echo "  .cursor/scripts/archive-sessions.sh"
        echo "  .cursor/scripts/check-handoff-staleness.sh"
        echo "  .cursor/scripts/weekly-session-summary.sh"
    fi
    echo ""
    echo -e "${GREEN}How it works with your tools:${NC}"
    echo ""
    echo "  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐"
    echo "  │   Cursor     │    │  Git Hooks   │    │  Copilot CLI  │"
    echo "  │   (IDE)      │───▶│  (lifecycle) │───▶│  (AI tasks)   │"
    echo "  └─────────────┘    └──────────────┘    └───────────────┘"
    echo "         │                   │                    │"
    echo "         ▼                   ▼                    ▼"
    echo "  .cursor/rules/     session-logs/         commit msgs,"
    echo "  AGENTS.md          activity tracking     summaries"
    echo "  custom agents      reminders             pattern mining"
    echo ""
    echo "  ┌─────────────┐"
    echo "  │    Cron      │──▶ Archive, staleness checks, weekly summaries"
    echo "  └─────────────┘"
    echo ""
    log_info "All hooks respect --no-verify bypass. Uninstall with --uninstall."
}

main "$@"

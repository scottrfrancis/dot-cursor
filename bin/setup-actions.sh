#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# setup-github-actions.sh
#
# Installs GitHub Actions workflows for session management, PR automation,
# and project hygiene. These complement local git hooks and cron:
#
#   Local hooks  → per-commit, immediate feedback
#   Cron         → laptop-local background tasks
#   Actions      → server-side, reliable, team-visible, PR-gated
#
# Workflows installed:
#   pr-description.yml       — Auto-generate PR body from conventional commits
#   commit-lint.yml          — Server-side conventional commit validation
#   session-maintenance.yml  — Archive logs, stale handoff detection, weekly summary
#   branch-hygiene.yml       — Stale/merged/drifted branch detection
#   pr-review-checklist.yml  — Automated review: size, tests, secrets, deps, AI rules
#
# Usage:
#   ./setup-github-actions.sh [PROJECT_DIR]
#   ./setup-github-actions.sh --list              # show what would be installed
#   ./setup-github-actions.sh --remove            # remove installed workflows
###############################################################################

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_DIR="${1:-.}"
LIST_ONLY=false
REMOVE=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --list)   LIST_ONLY=true; shift ;;
        --remove) REMOVE=true; shift ;;
        --help|-h)
            echo "Usage: $(basename "$0") [OPTIONS] [PROJECT_DIR]"
            echo "  --list     Show workflows without installing"
            echo "  --remove   Remove installed workflows"
            exit 0 ;;
        -*) echo "Unknown: $1"; exit 1 ;;
        *)  POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]:-}"
PROJECT_DIR="$(cd "${1:-.}" 2>/dev/null && pwd)"

WORKFLOWS_DIR="${PROJECT_DIR}/.github/workflows"
# Source: same directory as this script, or bundled workflows
# Workflow source: sibling `workflows/` directory or same directory as this script
if [[ -d "${SCRIPT_DIR}/../workflows" ]]; then
    SOURCE_DIR="$(cd "${SCRIPT_DIR}/../workflows" && pwd)"
elif [[ -d "${SCRIPT_DIR}/workflows" ]]; then
    SOURCE_DIR="${SCRIPT_DIR}/workflows"
else
    SOURCE_DIR="${SCRIPT_DIR}"
fi

WORKFLOW_FILES=(
    "pr-description.yml"
    "commit-lint.yml"
    "session-maintenance.yml"
    "branch-hygiene.yml"
    "pr-review-checklist.yml"
)

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  GitHub Actions Setup  v${VERSION}                    ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

if [[ "$LIST_ONLY" == true ]]; then
    log_info "Workflows that would be installed to ${WORKFLOWS_DIR}/"
    echo ""
    printf "  %-30s %s\n" "FILE" "PURPOSE"
    printf "  %-30s %s\n" "────" "───────"
    printf "  %-30s %s\n" "pr-description.yml"      "Auto-generate PR body from conventional commits"
    printf "  %-30s %s\n" "commit-lint.yml"          "Validate conventional commit format on PRs"
    printf "  %-30s %s\n" "session-maintenance.yml"  "Archive logs, stale handoff detection, weekly summary"
    printf "  %-30s %s\n" "branch-hygiene.yml"       "Detect stale/merged/drifted branches (weekly)"
    printf "  %-30s %s\n" "pr-review-checklist.yml"  "Automated review: size, tests, secrets, deps, AI rules"
    echo ""
    exit 0
fi

if [[ "$REMOVE" == true ]]; then
    log_info "Removing workflows..."
    for f in "${WORKFLOW_FILES[@]}"; do
        if [[ -f "${WORKFLOWS_DIR}/${f}" ]]; then
            rm "${WORKFLOWS_DIR}/${f}"
            log_ok "Removed: ${f}"
        fi
    done
    exit 0
fi

# Install workflows
mkdir -p "$WORKFLOWS_DIR"

INSTALLED=0
for f in "${WORKFLOW_FILES[@]}"; do
    if [[ -f "${SOURCE_DIR}/${f}" ]]; then
        cp "${SOURCE_DIR}/${f}" "${WORKFLOWS_DIR}/${f}"
        log_ok "Installed: .github/workflows/${f}"
        INSTALLED=$((INSTALLED + 1))
    else
        log_warn "Source not found: ${f} — skipping"
    fi
done

# Also ensure the session-maintenance label exists (instructions)
echo ""
log_info "═══════════════════════════════════════════════════════"
log_info "Setup Complete — ${INSTALLED} workflow(s) installed"
log_info "═══════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}Installed workflows:${NC}"
echo ""
printf "  %-30s %-12s %s\n" "WORKFLOW" "TRIGGER" "PURPOSE"
printf "  %-30s %-12s %s\n" "────────" "───────" "───────"
printf "  %-30s %-12s %s\n" "pr-description.yml"      "PR open"    "Auto-fill PR body from commits"
printf "  %-30s %-12s %s\n" "commit-lint.yml"          "PR open"    "Conventional commit gate"
printf "  %-30s %-12s %s\n" "pr-review-checklist.yml"  "PR open"    "Automated review findings"
printf "  %-30s %-12s %s\n" "session-maintenance.yml"  "Daily/Weekly" "Log archive + weekly summary"
printf "  %-30s %-12s %s\n" "branch-hygiene.yml"       "Weekly"     "Stale branch detection"
echo ""
echo -e "${GREEN}How this fits the full stack:${NC}"
echo ""
echo "  Local (per-commit)     → git hooks     → immediate feedback"
echo "  Local (background)     → cron          → laptop-local maintenance"
echo "  Server (PR-gated)      → Actions       → team-visible, reliable"
echo "  Server (scheduled)     → Actions       → runs even when laptop sleeps"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. git add .github/workflows/"
echo "  2. git commit -m 'ci: add session management and PR automation workflows'"
echo "  3. git push"
echo "  4. Create labels in GitHub: 'session-maintenance', 'branch-hygiene'"
echo "     (Settings → Labels → New label)"
echo ""
log_info "Note: session-maintenance.yml replaces local cron for reliability."
log_info "You can run both (belt + suspenders) or just Actions."

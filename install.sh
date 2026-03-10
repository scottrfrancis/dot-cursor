#!/usr/bin/env bash
# Installer for dot-cursor configuration.
#
# Two modes:
#   ./install.sh /path/to/project           # Full install: Cursor rules + hooks + Actions
#   ./install.sh --cursor /path/to/project  # Cursor rules + agents only (no hooks/Actions)
#
# Full install requires a git repository (hooks need .git/).
# --cursor mode works on any directory.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Require bash 4+ (macOS ships 3.2; bin/migrate-to-cursor.sh uses associative arrays)
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "Error: bash 4+ required. macOS ships with bash 3.2." >&2
  echo "       Install with: brew install bash" >&2
  echo "       Then run: /opt/homebrew/bin/bash install.sh ..." >&2
  echo "       See docs/troubleshooting.md for details." >&2
  exit 1
fi

# --- Colors ---

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Usage ---

usage() {
  echo "Usage: $0 /path/to/project              # Cursor rules + hooks + Actions"
  echo "       $0 --cursor /path/to/project     # Cursor rules + agents only"
  echo "       $0 -h | --help"
  echo ""
  echo "Full install (default):"
  echo "  1. bin/migrate-to-cursor.sh  — .cursor/rules/, modes.json, AGENTS.md, .cursorignore"
  echo "  2. bin/setup-hooks.sh        — git lifecycle hooks in .git/hooks/"
  echo "  3. bin/setup-actions.sh      — GitHub Actions in .github/workflows/"
  echo ""
  echo "--cursor mode skips hooks and Actions (useful for non-git or no-GitHub projects)."
}

if [[ $# -lt 1 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
  usage
  exit 0
fi

# --- Parse arguments ---

CURSOR_ONLY=false

if [[ "$1" == "--cursor" ]]; then
  CURSOR_ONLY=true
  shift
fi

TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
  echo "Error: Directory not found: ${1:-.}" >&2
  exit 1
}

if [[ "$TARGET_DIR" == "$SCRIPT_DIR" ]]; then
  echo "Error: Cannot install into the dot-cursor repository itself" >&2
  exit 1
fi

# --- Validate ---

if [[ "$CURSOR_ONLY" != true ]] && [[ ! -d "${TARGET_DIR}/.git" ]]; then
  echo "Error: ${TARGET_DIR} is not a git repository." >&2
  echo "       Run 'git init' first, or use --cursor to skip hooks and Actions." >&2
  exit 1
fi

# --- Run ---

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  dot-cursor installer                        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Target:${NC} ${TARGET_DIR}"
echo ""

# Phase 1: Cursor rules + agents
echo -e "${BLUE}Phase 1:${NC} Cursor rules, agents, AGENTS.md, .cursorignore"
"${SCRIPT_DIR}/bin/migrate-to-cursor.sh" "$TARGET_DIR"

if [[ "$CURSOR_ONLY" == true ]]; then
  echo ""
  echo -e "${GREEN}Done.${NC} (--cursor mode: hooks and Actions skipped)"
  echo ""
  echo "Next steps:"
  echo -e "  1. ${YELLOW}Paste${NC} ${TARGET_DIR}/generated/cursor-user-rules.txt into Cursor Settings → Rules → User Rules"
  echo -e "  2. ${YELLOW}Review${NC} ${TARGET_DIR}/.cursor/rules/*.mdc — adjust globs and rule types"
  echo -e "  3. ${YELLOW}Test${NC} agents: open Agent chat, type @lets-go"
  exit 0
fi

echo ""

# Phase 2: Git hooks
echo -e "${BLUE}Phase 2:${NC} Git lifecycle hooks"
"${SCRIPT_DIR}/bin/setup-hooks.sh" "$TARGET_DIR"

echo ""

# Phase 3: GitHub Actions
echo -e "${BLUE}Phase 3:${NC} GitHub Actions workflows"
"${SCRIPT_DIR}/bin/setup-actions.sh" "$TARGET_DIR"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Installation complete                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo -e "  1. ${YELLOW}Paste${NC} generated/cursor-user-rules.txt into Cursor Settings → Rules → User Rules"
echo -e "  2. ${YELLOW}Review${NC} .cursor/rules/*.mdc — adjust globs and rule types per project"
echo -e "  3. ${YELLOW}Test${NC} agents: open Agent chat, type @lets-go"
echo -e "  4. ${YELLOW}Commit${NC} .cursor/ and AGENTS.md to version control"
echo -e "  5. ${YELLOW}Push${NC} to trigger GitHub Actions (PR description, commit lint)"
echo ""
echo "Hooks are installed in .git/hooks/ (not version controlled — re-run install.sh after cloning)."
echo ""

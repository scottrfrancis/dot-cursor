#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# sync-from-dot-claude.sh
#
# Regenerates dot-cursor/templates/*.mdc bodies from ~/.claude/guidelines/*.md.
#
# Rationale: ~/.claude/guidelines/ is the authoring surface for dot-claude
# users. templates/ is the vendored, cursor-ready copy shipped with this
# repo. Running this script propagates edits from the former to the latter.
#
# Preserves: each template's existing frontmatter (description, globs,
#            alwaysApply). Frontmatter is authoritative in templates/.
# Updates:   each template's body from the matching guideline.
#
# Usage:
#   ./sync-from-dot-claude.sh [--dry-run] [--dot-claude PATH]
#
# Flags:
#   --dry-run         Report what would change without writing
#   --dot-claude PATH Path to dot-claude root (default: ~/.claude)
#
# Behavior:
#   - For each guideline that matches an existing template: update body,
#     keep frontmatter.
#   - For each guideline with no matching template: warn and skip
#     (new guidelines need a human to decide frontmatter scope).
#   - For each template with no matching guideline: leave alone (may be
#     a cursor-specific template like docker.mdc or python.mdc).
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_CURSOR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATES_DIR="${DOT_CURSOR_DIR}/templates"

DRY_RUN=false
DOT_CLAUDE_DIR="${HOME}/.claude"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_skip()  { echo -e "${CYAN}[SKIP]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
    cat <<EOF
sync-from-dot-claude.sh

Propagate edits from ~/.claude/guidelines/*.md into dot-cursor/templates/*.mdc.
Template frontmatter is preserved; only the body is replaced.

Usage: $(basename "$0") [--dry-run] [--dot-claude PATH]

Options:
  --dry-run             Report what would change without writing
  --dot-claude PATH     Path to dot-claude root (default: ${DOT_CLAUDE_DIR})
  --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)    DRY_RUN=true; shift ;;
        --dot-claude) DOT_CLAUDE_DIR="$2"; shift 2 ;;
        --help|-h)    usage; exit 0 ;;
        *)            log_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

GUIDELINES_DIR="${DOT_CLAUDE_DIR}/guidelines"

if [[ ! -d "$GUIDELINES_DIR" ]]; then
    log_error "Guidelines directory not found: ${GUIDELINES_DIR}"
    exit 1
fi

if [[ ! -d "$TEMPLATES_DIR" ]]; then
    log_error "Templates directory not found: ${TEMPLATES_DIR}"
    exit 1
fi

log_info "Syncing from ${GUIDELINES_DIR} → ${TEMPLATES_DIR}"
log_info "Dry run: ${DRY_RUN}"
echo ""

updated=0
unchanged=0
orphaned_guidelines=()

# Write a file if content differs; respect dry-run.
write_if_changed() {
    local dest="$1"
    local new_content="$2"

    if [[ -f "$dest" ]] && [[ "$(cat "$dest")" == "$new_content" ]]; then
        return 1  # unchanged
    fi

    if [[ "$DRY_RUN" == true ]]; then
        return 0  # would change
    fi

    printf '%s' "$new_content" > "$dest"
    return 0  # changed
}

for guideline in "${GUIDELINES_DIR}"/*.md; do
    [[ -f "$guideline" ]] || continue
    basename=$(basename "$guideline" .md)
    template="${TEMPLATES_DIR}/${basename}.mdc"

    if [[ ! -f "$template" ]]; then
        orphaned_guidelines+=("$basename")
        continue
    fi

    # Extract frontmatter from template (first --- through second --- inclusive)
    frontmatter=$(awk '
        /^---$/ { print; count++; if (count == 2) exit; next }
        count >= 1 { print }
    ' "$template")

    # Extract body from guideline (skip any frontmatter it may have)
    if [[ "$(head -1 "$guideline")" == "---" ]]; then
        body=$(awk '
            /^---$/ { count++; next }
            count >= 2 { print }
        ' "$guideline")
    else
        body=$(cat "$guideline")
    fi

    new_content="${frontmatter}

${body}"

    if write_if_changed "$template" "$new_content"; then
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would update: templates/${basename}.mdc"
        else
            log_ok "Updated: templates/${basename}.mdc"
        fi
        updated=$((updated + 1))
    else
        log_skip "Unchanged: templates/${basename}.mdc"
        unchanged=$((unchanged + 1))
    fi
done

echo ""
log_info "Summary: ${updated} updated, ${unchanged} unchanged"

if [[ ${#orphaned_guidelines[@]} -gt 0 ]]; then
    echo ""
    log_warn "Guidelines with no matching template (skipped):"
    for g in "${orphaned_guidelines[@]}"; do
        log_warn "  - ${g}.md"
    done
    log_warn "Create templates/${orphaned_guidelines[0]}.mdc manually with appropriate frontmatter to enable sync."
fi

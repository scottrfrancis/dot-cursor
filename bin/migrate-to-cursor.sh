#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# migrate-to-cursor.sh
#
# Migrates a project from Claude Code / dot-copilot configuration to Cursor IDE.
# Reads from:
#   - ~/.claude/guidelines/          (global guidelines)
#   - ~/.claude/commands/            (global commands)  
#   - .claude/ or .github/           (project-level config)
#   - CLAUDE.md or AGENTS.md         (project root instructions)
#
# Generates:
#   - .cursor/rules/*.mdc            (project rules with proper frontmatter)
#   - .cursor/modes.json             (custom agents from commands)
#   - .cursorignore                  (context optimization)
#   - AGENTS.md                      (cross-tool instructions if missing)
#   - session-logs/                  (for manual session tracking)
#   - generated/cursor-user-rules.txt (paste into Cursor User Rules settings)
#
# Usage:
#   ./migrate-to-cursor.sh [PROJECT_DIR]
#   ./migrate-to-cursor.sh                    # current directory
#   ./migrate-to-cursor.sh /path/to/project   # specific project
#
# Flags:
#   --dry-run     Show what would be created without writing files
#   --force       Overwrite existing .cursor/rules/ files  
#   --no-agents   Skip custom agent generation
#   --no-global   Skip global ~/.claude/ guidelines migration
###############################################################################

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
PROJECT_DIR="${1:-.}"
DRY_RUN=false
FORCE=false
NO_AGENTS=false
NO_GLOBAL=false
DOT_CLAUDE_HOME="${HOME}/.claude"
DOT_COPILOT_DIR=""  # auto-detected

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
log_skip()  { echo -e "${CYAN}[SKIP]${NC}  $*"; }

usage() {
    cat <<EOF
migrate-to-cursor.sh v${VERSION}

Migrate Claude Code / Copilot config to Cursor IDE rules and agents.

Usage: $(basename "$0") [OPTIONS] [PROJECT_DIR]

Options:
  --dry-run       Show what would be created without writing
  --force         Overwrite existing .cursor/rules/ files
  --no-agents     Skip custom agent (modes.json) generation
  --no-global     Skip migrating ~/.claude/guidelines/
  --help          Show this help

Examples:
  $(basename "$0")                          # migrate current directory
  $(basename "$0") /path/to/project         # migrate specific project
  $(basename "$0") --dry-run .              # preview changes
  $(basename "$0") --force --no-global .    # overwrite, project-only
EOF
}

# Parse arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)   DRY_RUN=true; shift ;;
        --force)     FORCE=true; shift ;;
        --no-agents) NO_AGENTS=true; shift ;;
        --no-global) NO_GLOBAL=true; shift ;;
        --help|-h)   usage; exit 0 ;;
        -*)          log_error "Unknown option: $1"; usage; exit 1 ;;
        *)           POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]:-}"
PROJECT_DIR="${1:-.}"

# Resolve paths
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || {
    log_error "Directory not found: ${1:-.}"
    exit 1
}

###############################################################################
# Utility functions
###############################################################################

write_file() {
    local filepath="$1"
    local content="$2"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create: $filepath"
        return 0
    fi
    
    if [[ -f "$filepath" && "$FORCE" != true ]]; then
        log_skip "Exists (use --force to overwrite): $filepath"
        return 0
    fi
    
    mkdir -p "$(dirname "$filepath")"
    echo "$content" > "$filepath"
    log_ok "Created: $filepath"
}

# Convert a guideline markdown file to a .cursor/rules .mdc file
convert_guideline_to_rule() {
    local src="$1"
    local rule_name="$2"
    local globs="${3:-}"
    local always_apply="${4:-false}"
    local description="${5:-}"
    
    local dest="${PROJECT_DIR}/.cursor/rules/${rule_name}.mdc"
    
    # Read source content, strip any existing YAML frontmatter
    local content
    content=$(sed '/^---$/,/^---$/d' "$src" 2>/dev/null || cat "$src")
    
    # Build frontmatter
    local frontmatter="---"
    if [[ -n "$description" ]]; then
        frontmatter="${frontmatter}
description: \"${description}\""
    else
        frontmatter="${frontmatter}
description: \"\""
    fi
    frontmatter="${frontmatter}
globs: \"${globs}\"
alwaysApply: ${always_apply}
---"
    
    write_file "$dest" "${frontmatter}

${content}"
}

# Convert a copilot instruction file (with applyTo frontmatter) to cursor rule
convert_copilot_instruction() {
    local src="$1"
    local rule_name="$2"
    
    local dest="${PROJECT_DIR}/.cursor/rules/${rule_name}.mdc"
    
    # Extract applyTo patterns from YAML frontmatter if present
    local globs=""
    if grep -q "^applyTo:" "$src" 2>/dev/null; then
        # Extract applyTo lines and convert to comma-separated globs
        globs=$(awk '/^applyTo:/,/^[^ -]/' "$src" | grep '^ *-' | sed 's/^ *- *//' | paste -sd',' -)
    fi
    
    # Strip existing frontmatter
    local content
    content=$(awk 'BEGIN{skip=0} /^---$/{skip=!skip; next} !skip' "$src")
    
    # Auto-detect description from first heading
    local description
    description=$(echo "$content" | grep '^#' | head -1 | sed 's/^#* *//')
    
    local always_apply="false"
    if [[ -z "$globs" ]]; then
        always_apply="false"  # agent-requested if no globs
    fi
    
    local frontmatter="---
description: \"${description}\"
globs: \"${globs}\"
alwaysApply: ${always_apply}
---"
    
    write_file "$dest" "${frontmatter}

${content}"
}

###############################################################################
# Phase 1: Directory setup
###############################################################################

phase_1_setup() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "Phase 1: Directory Setup"
    log_info "═══════════════════════════════════════════════════════"
    log_info "Project: ${PROJECT_DIR}"
    
    # Create directories
    for dir in ".cursor/rules" "session-logs" "generated"; do
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would create dir: ${PROJECT_DIR}/${dir}"
        else
            mkdir -p "${PROJECT_DIR}/${dir}"
            log_ok "Directory: ${dir}/"
        fi
    done
    
    # Detect existing configurations
    log_info ""
    log_info "Detecting existing configurations..."
    
    [[ -f "${PROJECT_DIR}/CLAUDE.md" ]] && log_info "  Found: CLAUDE.md"
    [[ -f "${PROJECT_DIR}/AGENTS.md" ]] && log_info "  Found: AGENTS.md"
    [[ -d "${PROJECT_DIR}/.claude" ]] && log_info "  Found: .claude/ (project config)"
    [[ -d "${PROJECT_DIR}/.github" ]] && log_info "  Found: .github/ (copilot config)"
    [[ -d "${PROJECT_DIR}/.cursor" ]] && log_info "  Found: .cursor/ (existing cursor config)"
    [[ -d "${DOT_CLAUDE_HOME}" ]] && log_info "  Found: ~/.claude/ (global config)"
    
    # Auto-detect dot-copilot location
    for candidate in "${HOME}/dot-copilot" "${HOME}/workspace/dot-copilot" "${HOME}/projects/dot-copilot"; do
        if [[ -d "${candidate}/copilot" ]]; then
            DOT_COPILOT_DIR="$candidate"
            log_info "  Found: dot-copilot at ${DOT_COPILOT_DIR}"
            break
        fi
    done
}

###############################################################################
# Phase 2: Migrate guidelines to .cursor/rules/
###############################################################################

phase_2_guidelines() {
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "Phase 2: Migrate Guidelines → .cursor/rules/"
    log_info "═══════════════════════════════════════════════════════"
    
    local count=0
    
    # Source 1: Global ~/.claude/guidelines/
    if [[ "$NO_GLOBAL" != true && -d "${DOT_CLAUDE_HOME}/guidelines" ]]; then
        log_info "Processing global guidelines from ~/.claude/guidelines/..."
        
        local -A GUIDELINE_MAP=(
            ["shell-scripts"]="*.sh,*.bash,Makefile"
            ["conventional-commits"]=""
            ["readme-documentation"]="*.md"
            ["session-safety"]=""  # always-apply
            ["ai-patterns"]="*.py,*.ts,*.js"
            ["project-setup"]=""  # agent-requested
            ["prose-style"]="*.md"
            ["prototype-hygiene"]=""  # always-apply
            ["security-hardening"]=""  # agent-requested
            ["shell-escaping"]="*.sh,*.bash,Dockerfile"
            ["C4-diagramming"]="*.puml,*.plantuml"
            ["c4-diagramming"]="*.puml,*.plantuml"
            ["markdown-formatting"]="*.md"
            ["karpathy-principles"]=""  # always-apply, not file-scoped
        )

        local -A ALWAYS_APPLY_MAP=(
            ["conventional-commits"]="true"
            ["session-safety"]="true"
            ["prototype-hygiene"]="true"
            ["karpathy-principles"]="true"
        )
        
        for file in "${DOT_CLAUDE_HOME}/guidelines/"*.md; do
            [[ -f "$file" ]] || continue
            local basename
            basename=$(basename "$file" .md)
            local rule_name="${basename}"
            local globs="${GUIDELINE_MAP[$basename]:-}"
            local always="${ALWAYS_APPLY_MAP[$basename]:-false}"
            local desc
            desc=$(head -5 "$file" | grep '^#' | head -1 | sed 's/^#* *//' || echo "$basename guideline")
            
            convert_guideline_to_rule "$file" "$rule_name" "$globs" "$always" "$desc"
            ((count++))
        done
    else
        log_skip "Global guidelines (--no-global or ~/.claude/guidelines/ not found)"
    fi
    
    # Source 2: Project .github/instructions/ (from dot-copilot)
    if [[ -d "${PROJECT_DIR}/.github/instructions" ]]; then
        log_info "Processing copilot instructions from .github/instructions/..."
        
        for file in "${PROJECT_DIR}/.github/instructions/"*.instructions.md; do
            [[ -f "$file" ]] || continue
            local basename
            basename=$(basename "$file" .instructions.md)
            
            convert_copilot_instruction "$file" "$basename"
            ((count++))
        done
    fi
    
    # Source 3: dot-copilot repo if detected
    if [[ -n "$DOT_COPILOT_DIR" && -d "${DOT_COPILOT_DIR}/copilot/instructions" ]]; then
        log_info "Processing dot-copilot instructions from ${DOT_COPILOT_DIR}..."
        
        for file in "${DOT_COPILOT_DIR}/copilot/instructions/"*.instructions.md; do
            [[ -f "$file" ]] || continue
            local basename
            basename=$(basename "$file" .instructions.md)
            local dest="${PROJECT_DIR}/.cursor/rules/${basename}.mdc"
            
            # Don't overwrite if already created from .github/instructions/
            if [[ -f "$dest" && "$FORCE" != true ]]; then
                log_skip "Already exists from .github/: ${basename}.mdc"
                continue
            fi
            
            convert_copilot_instruction "$file" "$basename"
            ((count++))
        done
    fi
    
    log_info "Migrated ${count} guideline(s) to .cursor/rules/"
}

###############################################################################
# Phase 3: Generate AGENTS.md (cross-tool compatibility)
###############################################################################

phase_3_agents_md() {
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "Phase 3: Generate AGENTS.md"
    log_info "═══════════════════════════════════════════════════════"
    
    local agents_file="${PROJECT_DIR}/AGENTS.md"
    
    if [[ -f "$agents_file" && "$FORCE" != true ]]; then
        log_skip "AGENTS.md already exists (use --force to regenerate)"
        return
    fi
    
    # Build from CLAUDE.md if it exists, otherwise create minimal
    local content=""
    
    if [[ -f "${PROJECT_DIR}/CLAUDE.md" ]]; then
        log_info "Generating AGENTS.md from CLAUDE.md..."
        content="# Project Instructions

> Auto-generated from CLAUDE.md for cross-tool compatibility.
> This file is read by Cursor, Copilot CLI, Codex, and Gemini CLI.

$(cat "${PROJECT_DIR}/CLAUDE.md")"
    else
        log_info "Creating minimal AGENTS.md..."
        content="# Project Instructions

> Cross-tool instructions file. Read by Cursor, Copilot CLI, Codex, and Gemini CLI.

## Code Standards
- **Red-Green-Refactor TDD is REQUIRED for ALL code changes.** Write a failing test first (RED), minimum code to pass (GREEN), refactor with tests green. No production code without a failing test. No retroactive tests. See \`.cursor/rules/testing.mdc\`.
- Follow conventional commits: \`type(scope): description\`
- Use \`set -euo pipefail\` in all shell scripts
- README is the primary documentation hub

## Session Protocol
- Check session-logs/ for recent handoff files at session start
- Log session outcomes before ending work
- Create handoff notes when pausing mid-task

## Architecture
- See project README for architecture overview
- Follow existing patterns before introducing new ones
- Document significant decisions as ADRs
"
    fi
    
    write_file "$agents_file" "$content"
}

###############################################################################
# Phase 4: Generate custom agents (.cursor/modes.json)
###############################################################################

phase_4_custom_agents() {
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "Phase 4: Generate Subagents (.cursor/agents/) and Command Aliases"
    log_info "═══════════════════════════════════════════════════════"
    
    if [[ "$NO_AGENTS" == true ]]; then
        log_skip "Custom agents (--no-agents)"
        return
    fi
    
    local agents_dir="${PROJECT_DIR}/.cursor/agents"
    local rules_dir="${PROJECT_DIR}/.cursor/rules"
    mkdir -p "$agents_dir" "$rules_dir"
    
    # Note: Cursor's .cursor/modes.json is "under consideration" but not implemented.
    # Subagents (.cursor/agents/*.md) ARE supported — the main agent delegates to them.
    # Command aliases (.cursor/rules/command-aliases.mdc) handle in-context commands.
    
    # --- Subagents (delegated, isolated context) ---
    
    write_file "${agents_dir}/arch-review.md" '---
name: arch-review
description: "Principal Architect review against Well-Architected, SOLID, security, and project guidelines. Use when evaluating architecture, planning major changes, or assessing technical debt."
model: inherit
readonly: true
is_background: false
---

Before reviewing, load project context: read all files in docs/guidelines/, docs/adr/, docs/design/, and docs/api/openapi.yaml. Skip any that do not exist.

Evaluate against: AWS/Azure Well-Architected, SOLID, security (verify against docs/guidelines/security.md), testing strategy, AI/LLM patterns, technical debt, ADR compliance, documentation quality.

Be direct. Rate each area. Identify the top 3 highest-impact improvements. For significant findings, recommend creating an ADR or a guideline rule. Save report to docs/arch-review-YYYY-MM-DD.md.'

    write_file "${agents_dir}/security-audit.md" '---
name: security-audit
description: "Breach-driven security audit. Use when reviewing security posture, after adding auth/endpoint/input handling code, or for periodic assessments."
model: inherit
readonly: true
is_background: false
---

Before auditing, read docs/guidelines/security.md and docs/learnings/ for project-specific rules. Skip if they do not exist.

Audit the credential-compromise-to-data-access chain: authentication, authorization, input validation, operational security. If docs/guidelines/security.md exists, verify every rule across the codebase.

For each finding: ID, Severity, File+line, Finding, Breach parallel, Recommendation, Effort. Prioritize direct breach vectors. Recommend new rules for docs/guidelines/security.md and ADRs for architectural decisions.'

    write_file "${agents_dir}/doc-review.md" '---
name: doc-review
description: "Audit project documentation for accuracy, DRY, clarity, and new-member accessibility. Use when docs may be stale or after major changes."
model: inherit
readonly: false
is_background: false
---

Inventory all docs: README, AGENTS.md, CONTRIBUTING, docs/guidelines/, docs/adr/, docs/design/, docs/**/*.md. Exclude session-logs/, .factory/, .claude/, node_modules/.

Gather ground truth from code (package.json, pyproject.toml, docker-compose). Verify docs against code. Check guidelines consistency with AGENTS.md and ADR currency. Fix what you can, flag uncertain items with TODO comments. Summarize findings.'

    write_file "${agents_dir}/review-pr.md" '---
name: review-pr
description: "PR code review for bugs, security issues, missing tests, and code quality. Use when reviewing pull requests or branch diffs."
model: inherit
readonly: true
is_background: false
---

## Step 0 — Invoke `/ultrareview` (REQUIRED)

Before anything else, you MUST explicitly invoke the `/ultrareview` slash command (available on Claude 4.7+ models) to run Claude'"'"'s specialized bug-hunting reviewer fleet against the changed files. This is non-optional — `/ultrareview` is the primary source of findings; the manual checklist below is a supplement, not a replacement. Capture its findings and treat any HIGH/critical items as required review items.

If `/ultrareview` is unavailable in the current environment (e.g., the host model/client does not expose the slash command), say so explicitly in the final review output and continue with the manual checklist.

## Manual checklist

Load all files in docs/guidelines/ and docs/adr/ before reviewing. Resolve the diff (gh pr diff or git diff main...HEAD). Read changed files for full context. Review for bugs, security (verify against docs/guidelines/security.md), API rules, data rules, missing tests, contract changes, ADR compliance.

## Output

**Merge findings from `/ultrareview` (Step 0) with findings from the manual checklist**, deduplicating and tagging each with `[ultrareview]` or `[manual]`. Group findings by file with severity and verdict.'

    write_file "${agents_dir}/babysit-pr.md" '---
name: babysit-pr
description: "Monitor a PR for check results, reviews, and merge readiness. If merged, offers branch cleanup."
model: inherit
readonly: false
is_background: false
---

Check PR status via gh pr view. Report CI checks, reviews, mergeability. If merged, offer cleanup: git checkout main, git pull, delete local branch, git fetch --prune. If closed without merge, offer to delete local branch.'

    write_file "${agents_dir}/mine-sessions.md" '---
name: mine-sessions
description: "Analyze session logs for patterns, metrics, and process improvements. Cross-references insights against docs/guidelines/ to find gaps."
model: inherit
readonly: true
is_background: true
---

Find all session and handoff files in session-logs/, .factory/logs/, .claude/session-logs/. Read docs/guidelines/ for current rule set. Analyze: session metrics, friction points, decision patterns, guideline coverage gaps (insights in 2+ sessions not in any guideline), ADR candidates. The guideline gap analysis is the highest-value output.'

    write_file "${agents_dir}/editorial-review.md" '---
name: editorial-review
description: "Audit prose for AI tells and refine voice/tone. Use when reviewing blog posts, documentation prose, or written content."
model: inherit
readonly: true
is_background: false
---

Check for: em-dash overuse, repeated openers, uniform sentence length, throat-clearing transitions, AI-favored adverbs, hollow intensifiers, structural tells. For each issue: quote the text, explain why it reads as AI-generated, provide a rewrite. If a style is specified, calibrate accordingly.'

    # --- Command aliases (in-context, keeps conversation) ---
    
    write_file "${rules_dir}/command-aliases.mdc" '---
description: "Recognize cross-tool command names so habits transfer from Claude Code and Droid"
globs: ""
alwaysApply: true
---

# Command Aliases

When the user types a command name (with or without a `/` prefix), **execute it immediately**. Do not ask for confirmation or suggest alternatives unless the user explicitly asks for options.

## In-context commands (need conversation context)

- **`session-logger`** or **`/session-logger`** — Create a session log immediately. Write to `session-logs/session-YYYY-MM-DD-HHMM.md` with YAML frontmatter (`tool: cursor`).
- **`handoff`** or **`/handoff`** — Create a handoff file immediately. Write to `session-logs/handoff-YYYY-MM-DD-HHMM.md` with YAML frontmatter.
- **`wrap up`** — Do both: session log then handoff.
- **`pickup`** or **`/pickup`** — Find and read the most recent handoff from `session-logs/`, `.factory/logs/`, or `.claude/session-logs/`.
- **`autocommit`** or **`/autocommit`** — Read `docs/guidelines/commits-and-branching.md` if it exists, analyze staged changes, generate commit message, ask for confirmation.
- **`lets-go`** or **`/lets-go`** — Full session init: check for handoffs, git sync, read AGENTS.md, check GitHub board if gh CLI available.

## Delegated commands (run immediately)

- **`arch-review`** — Run a full architecture review.
- **`security-audit`** — Run a full security audit.
- **`doc-review`** — Run a full documentation audit.
- **`review-pr`** — Review the current PR or branch diff.
- **`babysit-pr`** — Check PR status.
- **`mine-sessions`** — Analyze session logs for patterns.
- **`editorial-review`** — Audit prose for AI tells.'

    log_info "Created 7 subagents in .cursor/agents/"
    log_info "Created command-aliases rule in .cursor/rules/"
}

###############################################################################
# Phase 5: Generate .cursorignore
###############################################################################

phase_5_cursorignore() {
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "Phase 5: Generate .cursorignore"
    log_info "═══════════════════════════════════════════════════════"
    
    local ignore_file="${PROJECT_DIR}/.cursorignore"
    
    local content="# Cursor context optimization — exclude from AI indexing
# Cursor's effective context is ~70-120K tokens; be selective

# Dependencies
node_modules/
vendor/
.venv/
__pycache__/
*.pyc

# Build artifacts
dist/
build/
out/
*.egg-info/
target/

# Large/binary files
*.pdf
*.zip
*.tar.gz
*.whl
*.so
*.dylib

# IDE/tool dirs (other tools)
.idea/
.vscode/settings.json
.DS_Store

# Data & logs (unless you want AI to reason about them)
*.log
*.csv
*.sqlite
*.db
data/

# Session logs (read on demand, not auto-indexed)
session-logs/

# CI artifacts
coverage/
.nyc_output/
htmlcov/
"

    write_file "$ignore_file" "$content"
}

###############################################################################
# Phase 6: Generate User Rules (paste into Cursor Settings)
###############################################################################

phase_6_user_rules() {
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "Phase 6: Generate User Rules (for Cursor Settings)"
    log_info "═══════════════════════════════════════════════════════"
    
    local output="${PROJECT_DIR}/generated/cursor-user-rules.txt"
    
    # Build condensed user rules from ~/.claude/CLAUDE.md
    local content=""
    
    if [[ -f "${DOT_CLAUDE_HOME}/CLAUDE.md" ]]; then
        log_info "Condensing ~/.claude/CLAUDE.md for User Rules..."
        content="# Global User Rules (migrated from ~/.claude/CLAUDE.md)
# Paste this into: Cursor Settings → Rules → User Rules
# Keep it concise — this loads into every conversation

## Identity & Approach
- I am a senior engineer (40+ years experience). Skip basic explanations.
- Prefer practical, implementation-focused responses over theory.
- Use Mermaid diagrams for technical documentation unless specified otherwise.
- Always use conventional commits: type(scope): description

## Code Standards
- Shell scripts: set -euo pipefail, proper error handling, cleanup traps
- Python: type hints, docstrings, error handling
- All code: guard clauses, early returns, minimal nesting

## Session Protocol
- Check session-logs/handoff-*.md at session start for continuity
- Document decisions and rationale as you go
- Create session summary and handoff notes before ending

## Communication
- Be direct. Challenge my assumptions if you see flaws.
- Show me what changed, not just that you changed it.
- When uncertain, say so and suggest verification steps.

## Project Context
- README is the documentation hub — update it when architecture changes
- Follow existing patterns before introducing new ones
- Test before committing. Verify before deploying.
"
    else
        content="# Global User Rules
# Paste this into: Cursor Settings → Rules → User Rules
# Condensed from your development preferences

## Approach
- Senior engineer context — skip basics, focus on implementation
- Conventional commits: type(scope): description  
- README-centric documentation
- Mermaid diagrams for architecture

## Code
- Shell: set -euo pipefail, cleanup traps
- Guard clauses, early returns, minimal nesting
- Type hints in Python, TypeScript strict mode

## Session
- Check for handoff files at session start
- Log outcomes and decisions before ending
- Be direct, challenge assumptions, verify before deploying
"
    fi
    
    write_file "$output" "$content"
    
    if [[ "$DRY_RUN" != true ]]; then
        log_info ""
        log_warn "ACTION REQUIRED: Paste contents of generated/cursor-user-rules.txt"
        log_warn "into Cursor Settings → Rules → User Rules"
    fi
}

###############################################################################
# Phase 7: Session start rule (hooks workaround)
###############################################################################

phase_7_session_hooks_workaround() {
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "Phase 7: Session Lifecycle Rules (hooks workaround)"
    log_info "═══════════════════════════════════════════════════════"
    
    # Session start context injection
    local start_rule="---
description: \"Session start protocol — handoff context, session logs, and dot-repo sync check\"
globs: \"\"
alwaysApply: true
---

# Session Start Protocol

At the beginning of each new conversation:

1. **Check for handoff context**: Look for files matching \`session-logs/handoff-*.md\`.
   Also check \`.factory/logs/handoff-*.md\` (Droid) and \`.claude/session-logs/handoff-*.md\` (Claude Code/Copilot).
   If any exist from the last 7 days, read the most recent one and incorporate its context.

2. **Identify source tool**: If the handoff has YAML frontmatter with a \`tool:\` field,
   note which tool created it (e.g., 'Continuing from a Droid session').

3. **Acknowledge continuity**: If a handoff was found, briefly note what was
   previously in progress and what the recommended next steps were.

4. **If no handoff found**: That's fine — just proceed with the user's request.

5. **Dot-Repo Sync Check** (consistent with Claude Code / Copilot / Droid session starts):
   Cursor works standalone — Claude Code, Droid, Copilot are all optional.
   This check is **opportunistic**: it runs only against dot-repos that actually exist on this machine.
   Skip silently for any repo that is not installed, has no remote, or where fetch fails.

   For each dot-repo, if discoverable, run:
   \`\`\`bash
   git -C <repo> fetch origin
   git -C <repo> rev-list --count HEAD..origin/main   # behind
   git -C <repo> rev-list --count origin/main..HEAD   # ahead
   git -C <repo> status --porcelain
   \`\`\`

   **Discovery logic** (try each; skip silently if not present):

   - **dot-cursor** (this tool's own repo — primary): check \`\$DOT_CURSOR_DIR\`, then \`\$HOME/workspace/dot-cursor\`, \`\$HOME/dot-cursor\`, \`/Volumes/workspace/dot-cursor\`. Use the first one that has a \`.git\` directory.
   - **dot-claude** (optional): check only if \`\$HOME/.claude/.git\` exists.
   - **dot-droid** (optional): check only if \`\$HOME/.factory\` is a symlink; resolve \`readlink -f \$HOME/.factory\` and take its parent; confirm \`.git\` exists there.
   - **dot-copilot** (optional): check only if \`.github/copilot-instructions.md\` (or another \`.github/instructions/*.instructions.md\` file) is a symlink in the current project; resolve it and walk up until a \`.git\` directory is found.

   **Alert prominently** for each repo that drifted:
   - **Behind**: '⚠ {repo-name} is {N} commits behind origin — your rules/commands may be stale. Consider \`git -C {repo} pull\`.'
   - **Ahead**: '{repo-name} has {N} unpushed commits — consider pushing.'
   - **Dirty**: '{repo-name} has uncommitted changes.'

   Report nothing for repos that are not installed on this machine.

Handoff files are cross-tool. They may have been created by Cursor, Droid, Copilot, or Claude Code.
"
    write_file "${PROJECT_DIR}/.cursor/rules/session-start.mdc" "$start_rule"
    
    # Session wrap rule (manual trigger)
    local wrap_rule="---
description: \"Session wrap-up — generate session log, handoff notes, and dot-repo sync check\"
globs: \"\"
alwaysApply: false
---

# Session Wrap-Up Protocol

When the user says \"let's wrap up\", \"session end\", or invokes this rule:

1. **Session Log**: Create \`session-logs/session-YYYY-MM-DD-HHMM.md\` with YAML frontmatter:
   \`\`\`
   ---
   tool: cursor
   timestamp: <ISO 8601>
   branch: <current branch>
   ---
   \`\`\`
   Followed by: Summary, Activities, Decisions Made, Reusable Insights, Effectiveness (1-5).

2. **Handoff**: Create \`session-logs/handoff-YYYY-MM-DD-HHMM.md\` with YAML frontmatter:
   \`\`\`
   ---
   tool: cursor
   timestamp: <ISO 8601>
   branch: <current branch>
   dirty: <true/false>
   files_changed: <count>
   ---
   \`\`\`
   Followed by: Completed, Current State, In Progress, Suggested Follow-Up, Key Decisions, Blockers/Risks.

3. **Dot-Repo Sync Check** (consistent with session start and with Claude Code / Copilot / Droid wrap-ups):
   Cursor works standalone; this check is **opportunistic** across any dot-repos installed on this machine.
   Use the same discovery logic as session-start: check each of dot-cursor (primary), dot-claude (only if \`\$HOME/.claude/.git\` exists), dot-droid (only if \`\$HOME/.factory\` is a symlink to a git repo), dot-copilot (only if a \`.github/\` symlink resolves to one). Run fetch + rev-list + status against each found repo; skip silently for any not installed, no remote, or fetch failure.

   **Alert prominently** for each repo that drifted, and record drift in the handoff under Blockers/Risks and in the session log under Session Effectiveness → Process friction:
   - **Behind**: '⚠ {repo-name} is {N} commits behind origin — run \`git -C {repo} pull\`.'
   - **Ahead**: '{repo-name} has {N} unpushed commits.'
   - **Dirty**: '{repo-name} has uncommitted changes.'

   Report nothing for repos that are not installed on this machine.

The YAML frontmatter is required — it identifies the source tool for cross-tool handoffs.
Any tool (Cursor, Droid, Copilot, Claude Code) can pick up these files.
"
    write_file "${PROJECT_DIR}/.cursor/rules/session-wrap.mdc" "$wrap_rule"
}

###############################################################################
# Phase 8: MCP configuration stub
###############################################################################

phase_8_mcp() {
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "Phase 8: MCP Configuration"
    log_info "═══════════════════════════════════════════════════════"
    
    local mcp_file="${PROJECT_DIR}/.cursor/mcp.json"
    
    if [[ -f "$mcp_file" && "$FORCE" != true ]]; then
        log_skip "mcp.json already exists"
        return
    fi
    
    # Check if Claude settings has MCP config to port
    local has_claude_mcp=false
    if [[ -f "${DOT_CLAUDE_HOME}/settings.json" ]]; then
        if grep -q "mcpServers\|mcp_servers" "${DOT_CLAUDE_HOME}/settings.json" 2>/dev/null; then
            has_claude_mcp=true
            log_warn "MCP servers found in ~/.claude/settings.json"
            log_warn "Manual migration required — Cursor MCP format differs from Claude Code"
            log_warn "See: https://cursor.com/docs/context/model-context-protocol"
        fi
    fi
    
    local content='{
  "mcpServers": {
    // Add your MCP servers here
    // Note: Cursor has a 40-tool hard limit across all servers
    //
    // Example:
    // "filesystem": {
    //   "command": "npx",
    //   "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
    // }
  }
}'

    write_file "$mcp_file" "$content"
    
    if [[ "$has_claude_mcp" == true ]]; then
        log_info ""
        log_warn "Review ~/.claude/settings.json and port MCP servers to .cursor/mcp.json"
        log_warn "Prioritize your most-used tools (40 tool limit in Cursor)"
    fi
}

###############################################################################
# Summary
###############################################################################

print_summary() {
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "Migration Complete"
    log_info "═══════════════════════════════════════════════════════"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warn "This was a DRY RUN — no files were written"
        log_info "Run without --dry-run to apply changes"
        return
    fi
    
    echo ""
    echo -e "${GREEN}Generated structure:${NC}"
    if command -v tree &>/dev/null; then
        tree -a --dirsfirst -I '.git|node_modules' \
            "${PROJECT_DIR}/.cursor" \
            "${PROJECT_DIR}/session-logs" \
            "${PROJECT_DIR}/generated" \
            "${PROJECT_DIR}/AGENTS.md" 2>/dev/null || true
    else
        find "${PROJECT_DIR}/.cursor" "${PROJECT_DIR}/session-logs" "${PROJECT_DIR}/generated" \
            -type f 2>/dev/null | sort | sed "s|${PROJECT_DIR}/||"
        [[ -f "${PROJECT_DIR}/AGENTS.md" ]] && echo "AGENTS.md"
    fi
    
    echo ""
    log_info "Next steps:"
    echo -e "  1. ${YELLOW}Paste${NC} generated/cursor-user-rules.txt into Cursor Settings → Rules → User Rules"
    echo -e "  2. ${YELLOW}Review${NC} .cursor/rules/*.mdc — adjust rule types and globs per project"
    echo -e "  3. ${YELLOW}Test${NC} custom agents: open Agent chat, switch to @lets-go, @arch-review, etc."
    echo -e "  4. ${YELLOW}Configure${NC} .cursor/mcp.json if you use MCP servers"
    echo -e "  5. ${YELLOW}Commit${NC} .cursor/ and AGENTS.md to version control"
    echo -e "  6. ${YELLOW}Set${NC} default model to Sonnet 4.5, with Opus 4.6 for @arch-review"
    echo ""
    log_info "Reference: cursor-migration-checklist.md for the full migration guide"
}

###############################################################################
# Main
###############################################################################

main() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Claude Code → Cursor Migration  v${VERSION}          ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    phase_1_setup
    phase_2_guidelines
    phase_3_agents_md
    phase_4_custom_agents
    phase_5_cursorignore
    phase_6_user_rules
    phase_7_session_hooks_workaround
    phase_8_mcp
    print_summary
}

main "$@"

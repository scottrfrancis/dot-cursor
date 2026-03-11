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
        )

        local -A ALWAYS_APPLY_MAP=(
            ["conventional-commits"]="true"
            ["session-safety"]="true"
            ["prototype-hygiene"]="true"
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
    log_info "Phase 4: Generate Custom Agents (.cursor/modes.json)"
    log_info "═══════════════════════════════════════════════════════"
    
    if [[ "$NO_AGENTS" == true ]]; then
        log_skip "Custom agents (--no-agents)"
        return
    fi
    
    local modes_file="${PROJECT_DIR}/.cursor/modes.json"
    
    # Build agents from commands
    # Note: modes.json format may evolve — this generates the current known format
    # Use heredoc (<<'EOF') so literal single quotes in prompts are safe.
    local modes_content
    modes_content=$(cat <<'MODES_EOF'
{
  "modes": [
    {
      "name": "lets-go",
      "model": "claude-sonnet-4-6",
      "prompt": "You are a session initialization agent. Follow this protocol:\n\n1. READ recent session context: Check session-logs/ for handoff-*.md files from the last 7 days. If found, summarize key context.\n2. GIT SYNC: Run git fetch, check ahead/behind status, recommend pull/push/branch as needed.\n3. PROJECT OVERVIEW: Read README.md and any CLAUDE.md or AGENTS.md for project context.\n4. SURFACE ALERTS: Check for stale branches, uncommitted changes, failing CI.\n5. REPORT: Present a concise session start briefing.\n\nKeep it actionable. No fluff."
    },
    {
      "name": "session-logger",
      "model": "claude-sonnet-4-6",
      "prompt": "You are a session logging agent. Create a structured session summary:\n\n## Session Log [DATE]\n\n### Activities\n- What was worked on\n\n### Decisions Made\n- Key decisions and rationale\n\n### Reusable Insights\n- Patterns discovered, gotchas encountered\n\n### Effectiveness Assessment\n- What worked well, what was friction\n- Rating: [1-5] with brief justification\n\n### Cross-Links\n- Link to previous session log if applicable\n\nSave to session-logs/session-YYYY-MM-DD-HHMM.md"
    },
    {
      "name": "handoff",
      "model": "claude-sonnet-4-6",
      "prompt": "You are a session handoff agent. Generate a forward-looking continuation prompt for the next session. Include:\n\n1. CURRENT STATE: What was being worked on, where things stand\n2. IMMEDIATE NEXT STEPS: What should be done next (ordered)\n3. BLOCKERS/RISKS: Anything the next session needs to know\n4. KEY FILES: Which files are most relevant\n5. CONTEXT: Any decisions or constraints that matter\n\nWrite it as a prompt that could be pasted into a new session to pick up seamlessly.\n\nSave to session-logs/handoff-YYYY-MM-DD-HHMM.md"
    },
    {
      "name": "arch-review",
      "model": "claude-opus-4-6",
      "prompt": "You are a Principal Architect conducting a review. Evaluate against:\n\n1. AWS Well-Architected Framework (Security, Reliability, Performance, Cost, Operational Excellence, Sustainability)\n2. SOLID Principles compliance\n3. Security posture (auth, secrets, input validation, dependencies)\n4. Testing strategy (coverage, types, quality)\n5. AI/LLM integration patterns (if applicable): caching, routing, RAG, guardrails\n6. Technical debt assessment\n7. Documentation quality\n\nBe direct. Rate each area. Identify the top 3 highest-impact improvements.\n\nUse Opus-level reasoning — this is where deep analysis matters."
    },
    {
      "name": "autocommit",
      "model": "claude-haiku-4-5-20251001",
      "prompt": "Analyze staged changes (git diff --cached) and generate a conventional commit message.\n\nFormat: type(scope): description\n\nTypes: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert\n\nRules:\n- Description is imperative, lowercase, no period\n- Scope is optional but preferred\n- Include body if changes are complex\n- Include BREAKING CHANGE footer if applicable\n\nPresent the commit message and ask for confirmation before committing."
    },
    {
      "name": "mine-sessions",
      "model": "claude-sonnet-4-6",
      "prompt": "Analyze session logs in session-logs/ for patterns:\n\n1. Recurring friction points\n2. Decision patterns and evolution\n3. Productivity metrics (sessions per feature, effectiveness ratings)\n4. Reusable insights not yet captured in rules\n5. Process improvement recommendations\n\nPresent findings with specific examples from logs. Recommend concrete actions."
    },
    {
      "name": "security-audit",
      "model": "claude-opus-4-6",
      "prompt": "Perform a breach-driven security audit of this web application. Map the credential-compromise-to-data-access attack chain:\n\nPhase 1 - Authentication: Check password hashing (bcrypt/argon2/scrypt vs plaintext), auth fallbacks (do they bypass MFA?), rate limiting on login endpoint, auth event logging (failed + successful), default secrets in code, default role behavior when role is missing.\n\nPhase 2 - Authorization: Validate tenant isolation (can a user access another tenant's data via URL parameter?), role enforcement on admin endpoints (default-deny pattern), access decision logging.\n\nPhase 3 - Input validation: Path traversal (user-controlled path components, ../ escapes), upload validation (size, MIME type, zip bomb protection), internal endpoint authentication (schedulers, health checks).\n\nPhase 4 - Operational security: docker-compose port bindings (0.0.0.0 vs 127.0.0.1), secrets in env vars vs code, secrets in logs.\n\nFor each finding report: ID, Severity (HIGH/MEDIUM/LOW), File + line number, Finding, Breach parallel (how this maps to real attack patterns), Recommendation (specific fix), Effort (Small/Medium/Large).\n\nPrioritize: Direct breach vectors -> Impact amplifiers -> Operational hygiene."
    },
    {
      "name": "doc-review",
      "model": "claude-sonnet-4-6",
      "prompt": "Audit this project's documentation for accuracy, DRY, clarity, and new-member accessibility.\n\nPhase 1 - Inventory: Find all docs in this order: README.md, ARCHITECTURE.md / CONTRIBUTING.md / CHANGELOG.md (root), docs/**/*.md. List found files before proceeding.\n\nPhase 2 - Gather ground truth: Before reading docs, collect facts: read package.json scripts, Makefile, pyproject.toml. Run ls at repo root and key subdirectories. This is your source of truth - verify docs against code, not the other way around.\n\nPhase 3 - Review each file:\n- Accuracy: file paths, commands, scripts, architecture descriptions - do they match code?\n- DRY: identical content duplicated across files - consolidate and cross-reference\n- History narration: remove phrases like \"We used to\", \"Previously\", \"As of v2\" - git handles history\n- Clarity: clear start-here path, prerequisites before they are needed, fenced code blocks with language, descriptive headings\n\nIf accuracy is uncertain, add <!-- TODO: verify --> rather than guessing or removing.\n\nPhase 4 - Summary: List files reviewed, issues fixed, items flagged for human review."
    },
    {
      "name": "editorial-review",
      "model": "claude-sonnet-4-6",
      "prompt": "Audit the provided prose for AI tells and refine voice and tone. Apply these checks:\n\nPunctuation: Em-dashes (max 2 per piece - prefer colons, periods, or restructuring), semicolons (use sparingly), long parenthetical asides.\n\nSentence construction: Three consecutive sentences starting with the same word. Uniform sentence length (mix short declaratives with longer compound ones). Symmetrical constructions (example: deliberately X, and deliberately Y - break the symmetry). Tricolon overuse (A, B, and C - fine occasionally, not twice per page). Gerund-heavy openers (example: Selecting the right model -> Pick the right model).\n\nTransitions: Throat-clearing (examples: It is worth noting that, This should not surprise anyone). Hedging formulas (examples: It depends on where you sit, the broader point stands). Summary-before-conclusion (final paragraph restating the intro).\n\nWord choice: AI-favored adverbs (fundamentally, essentially, ultimately, importantly, significantly - cut unless genuinely meaningful). Hollow intensifiers (incredibly, extremely, truly). Landscape/ecosystem/paradigm overuse.\n\nStructural tells: Opening question you immediately answer (example: What does this mean? It means...). The to-be-sure sandwich.\n\nFor each issue: quote the offending text, explain why it is a tell, provide a rewrite.\n\nOptional: If the user specifies a style parameter (author name, publication, URL, or adjective), calibrate the target voice accordingly."
    },
    {
      "name": "pickup",
      "model": "claude-sonnet-4-6",
      "prompt": "Resume work from the most recent handoff file.\n\n1. Find the most recent handoff-*.md in session-logs/ modified within the last 7 days (sort -r, take first). If none found, say so and suggest running @lets-go instead.\n\n2. Read and display the full contents of the handoff file.\n\n3. Quick git sync: run git fetch origin silently, then report: current branch, commits behind upstream, commits ahead of upstream, dirty/clean working tree (git status --porcelain).\n\n4. Archive the handoff: move the file to session-logs/archive/ so it is not re-surfaced next time.\n\n5. Confirm readiness with a brief summary: handoff file consumed and archived, branch + sync state, top follow-up item from the handoff."
    },
    {
      "name": "review-pr",
      "model": "claude-sonnet-4-6",
      "prompt": "Review a pull request for bugs, security issues, missing tests, and code quality.\n\nStep 1 - Resolve the diff: If given a PR number, run gh pr diff NUMBER. If given a branch name, run git diff main...BRANCH. If no arguments, run git diff main...HEAD. Also run git log --oneline main...HEAD for commit context. If the diff is empty, report 'No changes to review' and stop.\n\nStep 2 - Read changed files for full context (not just the diff). Skip trivial changes.\n\nStep 3 - Review checklist (only report findings, skip clean categories):\n- Bugs & Logic Errors: off-by-one, unhandled null/undefined, race conditions, broken control flow\n- Security (OWASP Top 10): injection, auth gaps, data exposure, XSS\n- Missing Tests: new public functions without tests, changed behavior not covered, edge cases\n- API & Contract Changes: breaking changes, removed exports, schema changes\n- Style: only flag correctness/maintainability issues, not formatting\n\nStep 4 - Output as a structured review grouped by file with severity (HIGH/MEDIUM/LOW) and a verdict (Approve/Request Changes/Comment)."
    },
    {
      "name": "babysit-pr",
      "model": "claude-sonnet-4-6",
      "prompt": "Monitor a pull request and report its status.\n\n1. If no PR number given, run gh pr view --json number,title,state,url for the current branch. If no PR exists, report that and stop.\n\n2. Run gh pr view PR --json title,state,url,reviewDecision,statusCheckRollup,mergeable,reviews and report: PR number and title, URL, state, check results (passing/failing/pending), review decisions, and mergeability.\n\n3. Advise based on status: if all checks pass and approved, say ready to merge. If checks failing, show which and offer to investigate. If reviews pending or changes requested, summarize. If merge conflicts, report and suggest resolution."
    }
  ]
}
MODES_EOF
)

    write_file "$modes_file" "$modes_content"
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
description: \"Session start protocol — check for handoff context and recent session logs\"
globs: \"\"
alwaysApply: true
---

# Session Start Protocol

At the beginning of each new conversation:

1. **Check for handoff context**: Look for files matching \`session-logs/handoff-*.md\`.
   If any exist from the last 7 days, read the most recent one and incorporate its context.

2. **Acknowledge continuity**: If a handoff file was found, briefly note what was
   previously in progress and what the recommended next steps were.

3. **If no handoff found**: That's fine — just proceed with the user's request.

This replaces the Claude Code SessionStart hook that auto-injected handoff context.
"
    write_file "${PROJECT_DIR}/.cursor/rules/session-start.mdc" "$start_rule"
    
    # Session wrap rule (manual trigger)
    local wrap_rule="---
description: \"Session wrap-up — generate session log and handoff notes\"
globs: \"\"
alwaysApply: false
---

# Session Wrap-Up Protocol

When the user says \"let's wrap up\", \"session end\", or invokes this rule:

1. **Session Log**: Create \`session-logs/session-YYYY-MM-DD-HHMM.md\` with:
   - Activities performed
   - Decisions made (with rationale)
   - Reusable insights
   - Effectiveness assessment (1-5 rating)

2. **Handoff**: Create \`session-logs/handoff-YYYY-MM-DD-HHMM.md\` with:
   - Current state of work
   - Immediate next steps (ordered)
   - Blockers or risks
   - Key files touched
   - Context for seamless continuation

This replaces the Claude Code Stop hook and /session-logger + /handoff commands.
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

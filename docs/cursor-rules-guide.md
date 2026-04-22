# Cursor Rules Guide

Rules are the primary mechanism for giving Cursor project-specific coding guidance. They live in `.cursor/rules/` as `.mdc` files with YAML frontmatter.

## Rule Types

Each rule has a type controlled by its frontmatter. The type determines when Cursor loads the rule into the AI's context window.

### Always Apply

```yaml
---
description: Conventional commit format for all commits
alwaysApply: true
---
```

Loaded into every conversation. Use sparingly — each Always Apply rule consumes context window space (70–120K effective in Cursor, much smaller than Claude Code's 200K).

**Good candidates:** Commit conventions, safety rules for hardware/production systems, project-wide coding standards.

### Auto Attached (Glob-scoped)

```yaml
---
description: Shell scripting standards including ShellCheck compliance
globs: "*.sh,*.bash,Makefile"
---
```

Loaded automatically when matching files are open or referenced. This is the most common and efficient type.

**Glob pattern examples:**
- `*.py,*.pyx` — Python files
- `*.ts,*.tsx,*.js,*.jsx` — TypeScript/JavaScript
- `*.sh,*.bash,Makefile` — Shell scripts
- `Dockerfile,docker-compose*.yml` — Docker files
- `*.tf,*.tfvars` — Terraform
- `*.sql,*.prisma` — Database files

### Agent Requested

```yaml
---
description: Guidelines for handling Oil & Gas alarm management data structures
---
```

No `alwaysApply`, no `globs` — just a description. Cursor's AI reads the description and decides whether to load the rule based on conversational context. Good for specialized topics that the AI can infer relevance for.

### Manual (@mention)

Rules with only a filename (no description, no globs, no alwaysApply) must be explicitly referenced with `@rulename` in Agent chat.

**Good candidates:** Rarely-used reference material, project history, architecture decision records.

## Anatomy of a Rule File

```
.cursor/rules/shell-scripts.mdc
```

```yaml
---
description: Shell scripting standards — POSIX-compatible, ShellCheck clean
globs: "*.sh,*.bash,Makefile"
---

# Shell Script Standards

- Use `set -euo pipefail` at the top of every script
- Quote all variable expansions: `"${var}"` not `$var`
- Use `[[` for conditionals, not `[`
- Functions use lowercase_with_underscores naming
- Include a header comment block with usage and purpose
- Use `local` for function-scoped variables
- ShellCheck must pass with zero warnings
```

## Writing Effective Rules

### Keep rules short

Cursor's context window is smaller than Claude Code's. Each rule that loads takes space away from your code and conversation. Aim for rules under 50 lines. If a rule is getting long, split it into multiple rules with different globs.

### Be specific, not generic

Rules that say "write good code" add no value. Rules that say "use `zod` for runtime validation at API boundaries, return `Result<T, AppError>` not thrown exceptions" are actionable.

### Use the right type

| If the rule applies to... | Use |
|--------------------------|-----|
| Every conversation, always | `alwaysApply: true` — but keep these minimal |
| Specific file types | `globs: "*.ext"` |
| Specific topics the AI can infer | `description:` only (Agent Requested) |
| Rarely, only when asked | No frontmatter (Manual) |

### Test rule loading

In Cursor's Agent chat, type `@` and look for your rule name. If it appears, Cursor found it. If a glob-scoped rule isn't loading, check that matching files are open in the editor.

## Default Rules from migrate-to-cursor.sh

The installer copies every `.mdc` in `dot-cursor/templates/` into the target project's `.cursor/rules/`. Template frontmatter is authoritative.

**Always Apply** (load in every conversation — be sparing here):

| Rule | Purpose |
|------|---------|
| `conventional-commits.mdc` | `type(scope): desc` commit format |
| `karpathy-principles.mdc` | Surface assumptions; match style; mention don't delete dead code |
| `prototype-hygiene.mdc` | Config over code; docs describe current state; PRs over branches |
| `session-safety.mdc` | Hardware/NPU session cleanup rituals |

**Glob-scoped** (auto-attached when matching files are open):

| Rule | Globs | Purpose |
|------|-------|---------|
| `ai-patterns.mdc` | `*.py,*.ts,*.js,*.tsx,*.jsx` | LLM integration patterns |
| `C4-diagramming.mdc` | `*.puml,*.plantuml` | C4 PlantUML organization |
| `docker.mdc` | `Dockerfile,docker-compose*.yml` | Container standards |
| `golang.mdc` | `*.go,go.mod,go.sum` | Go safety + gosec |
| `markdown-formatting.mdc` | `*.md,*.mdx` | Markdown spacing rules |
| `python.mdc` | `*.py,pyproject.toml,setup.py` | Python standards |
| `readme-documentation.mdc` | `*.md` | README organization / DRY |
| `shell-escaping.mdc` | `*.sh,*.bash,Dockerfile` | Shell quoting rules |
| `shell-scripts.mdc` | `*.sh,*.bash,Makefile` | SCRIPT_DIR, strict mode |
| `terraform.mdc` | `*.tf,*.tfvars` | IaC standards |
| `typescript.mdc` | `*.ts,*.tsx` | TypeScript/React standards |

**Agent-requested** (activated by description when relevant):

| Rule | Purpose |
|------|---------|
| `ci-local-parity.mdc` | Run CI commands locally before push |
| `docx-conversion.mdc` | python-docx over pandoc |
| `md2pdf.mdc` | Markdown → PDF conversion workflow |
| `pr-token-tracking.mdc` | Include token usage in PR descriptions |
| `project-setup.mdc` | Tiered bootstrap checklist |
| `prose-style.mdc` | Anti-AI-smell narrative writing |
| `security-hardening.mdc` | Breach-driven web security audit |
| `testing.mdc` | RED-GREEN-REFACTOR TDD cycle |

Plus these generated rules (not in `templates/`):

| Rule | Type | Purpose |
|------|------|---------|
| `command-aliases.mdc` | Always Apply | In-context commands (session-logger, handoff, etc.) |
| `session-start.mdc` | Agent Requested | Surfaces handoff context on session start |
| `session-wrap.mdc` | Agent Requested | Generates session log + handoff on demand |

## Skeletons

For authoring new rules from scratch, copy one of these and fill in:

- `templates/always-apply.mdc.template` — skeleton for an Always Apply rule
- `templates/glob-scoped.mdc.template` — skeleton for a glob-scoped rule

## Authoring new rules

Three options, in order of preference:

1. **Add directly to `dot-cursor/templates/*.mdc`.** This is the authoritative source. Include a `description:` plus either `globs:` or `alwaysApply: true` (or neither, for agent-requested). New templates are auto-installed by `make install`.

2. **Add to `~/.claude/guidelines/*.md` and sync.** If you maintain a dot-claude authoring surface, write there and run `make sync` from `dot-cursor` to propagate to templates. Note: new guidelines require a matching template file first (sync preserves frontmatter, doesn't invent it).

3. **Project-local rule** in the target project's `.cursor/rules/*.mdc`. Doesn't propagate but is fine for one-off project conventions.

Manual frontmatter template:

```yaml
---
description: One-line description for Agent Requested loading
globs: "*.py"  # or alwaysApply: true
---

(your rule content here)
```

## Common Pitfalls

**Too many Always Apply rules.** Every one of these loads into every conversation. If you have 10 rules at 30 lines each, that's 300 lines of instructions consuming your limited context window before you've even asked a question. Be ruthless about what truly needs to be "always."

**Globs that are too broad.** `globs: "*"` makes the rule Always Apply in practice. Use specific extensions.

**Rules that duplicate AGENTS.md.** `AGENTS.md` is read by all AI tools. `.cursor/rules/` is Cursor-specific. Don't duplicate content between them — put cross-tool instructions in `AGENTS.md` and Cursor-specific behavior in rules.

**Rules that are too long.** If a rule exceeds ~80 lines, it's probably trying to cover too much. Split into focused rules.

## MCP Tool Limit

Cursor has a hard limit of **40 MCP tools** across all configured servers. If you're using MCP servers (`.cursor/mcp.json`), count your tools carefully. Each server typically exposes 5–15 tools. Three servers can easily hit the limit.

Prioritize tools by frequency of use. Disable servers you don't use daily.

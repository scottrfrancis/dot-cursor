# Limitations: What Can't Be Ported to Cursor

This document describes Claude Code features that have no direct Cursor equivalent, along with concrete workarounds. If you're migrating from Claude Code, read this before assuming something is broken — it might just be different.

## No Session Lifecycle Hooks

**Claude Code**: `SessionStart` and `Stop` hooks fire automatically via `~/.claude/settings.json`. The `SessionStart` hook finds the most recent `handoff-*.md` and injects it as context. The `Stop` hook checks if 3+ files changed and reminds you to log and handoff.

**Cursor**: No hook system. Nothing runs automatically when you open a chat or close it.

**Workaround**: Two rules and one git hook cover the three hook events:

- **`session-start.mdc`** (always-apply rule) — fires at every conversation start. Instructs Cursor to check `session-logs/` for recent handoff files and incorporate their context.
- **`post-checkout` git hook** — fires when you switch branches. Surfaces the most recent handoff file in the terminal with an age indicator and preview.
- **`session-wrap.mdc`** (agent-requested rule) — invoked when you say "wrap up" or "session end". Creates the session log and handoff in one step.

**What you lose**: The automation. In Claude Code you get nudged automatically. In Cursor you have to remember to start new conversations intentionally and end them with `@session-logger` + `@handoff`. The `post-commit` hook reminds you at 5 and 8 commits, but there's no safety net if you close the window without wrapping up.

## No Auto-Memory

**Claude Code**: Each project gets a persistent auto-memory directory (`~/.claude/projects/*/memory/MEMORY.md`) where Claude automatically records patterns and insights across sessions. You never have to tell it to remember things.

**Cursor**: Cursor has opt-in Cursor Memories (Settings → Features → Memories) that auto-extract facts from conversations, and Notepads (sidebar) for manual persistent context.

**Workaround**: Two options:

1. Enable Cursor Memories and let it auto-extract. Review periodically — it captures more than you want.
2. Maintain a `MEMORY.md` manually in the project. Use `@mine-sessions` periodically to identify patterns worth recording:

```
you> @mine-sessions
cursor> Analyzed 8 sessions. Recurring patterns:
        - Always run tenant isolation tests after auth changes
        - Use @arch-review before touching the auth middleware
        Recommend adding these to MEMORY.md.
```

**What you lose**: The automatic accumulation. In Claude Code, patterns surface without effort. In Cursor, you have to either trust the auto-extraction (noisy) or do it manually (friction).

## No Plan Mode

**Claude Code**: Has a dedicated plan mode where Claude explores read-only, designs an approach, writes a plan file, and waits for approval before making any changes. The constraint is enforced — it cannot edit files while planning.

**Cursor**: No structured planning mode with enforced read-only constraints.

**Workaround**: Ask explicitly:

```
you> I want to refactor the auth middleware. Don't make any changes yet —
     just analyze the codebase and propose a plan.
cursor> [reads files, proposes plan]

you> Looks good. Go ahead with step 1.
```

Or use `@arch-review` for structured read-only analysis:

```
you> @arch-review
cursor> [comprehensive analysis with specific recommendations, no edits]
```

**What you lose**: The enforced read-only guarantee. In Claude Code, plan mode physically prevents edits. In Cursor, you're trusting the instruction — it could still make changes if it misinterprets.

## Smaller Context Window

**Claude Code**: Reliable 200K tokens, with a 1M beta option.

**Cursor**: 70–120K tokens effective (varies by model and conversation complexity).

**Workaround**:

- Start new conversations more frequently. Don't let a single conversation grow past 30–40 messages.
- Use precise `@file` references instead of `@codebase` — attach only what's relevant.
- Keep `.cursor/rules/` files under 50 lines each. Always-apply rules load into every conversation.
- Use `.cursorignore` to exclude dependencies, build artifacts, and session logs from AI indexing.
- Prefer `@session-logger` + `@handoff` + fresh conversation over extending a stale one.

**What you lose**: The ability to hold a large codebase in context simultaneously. Deep cross-file refactoring requires more careful sequencing in Cursor.

## 40-Tool MCP Limit

**Claude Code**: No limit on MCP tools.

**Cursor**: Hard cap of 40 tools across all connected MCP servers.

**Workaround**: Audit your MCP configuration periodically. Disable servers you rarely use. Prioritize tools that are actually called during sessions — check your server logs to identify dead weight. The `.cursor/mcp.json` stub installed by this repo is a starting point; only add servers you actively need.

**What you lose**: The ability to connect many specialized tools simultaneously. You'll need to choose.

## Extended Thinking Not Exposed

**Claude Code**: Opus extended thinking mode is available for particularly complex reasoning tasks.

**Cursor**: No toggle for extended thinking. Opus is available as a model choice, but the extended thinking feature is not exposed.

**Workaround**: None directly. Opus still reasons well in standard mode — the gap is smaller than it sounds for most tasks. For the most complex architectural analysis, use `@arch-review` which is configured to use Opus.

**What you lose**: The explicit reasoning trace and the deeper exploration that extended thinking enables on genuinely hard problems.

## No PostToolUse Hooks

**Claude Code**: `PostToolUse` hooks fire after every tool call. You can validate every file write, run a linter on edited code, or check output before proceeding.

**Cursor**: No equivalent.

**Workaround**: Glob-scoped rules provide file-type-specific instructions that approximate validation guidance at the instruction level rather than the execution level:

```
# In .cursor/rules/shell-scripts.mdc (globs: *.sh,*.bash)
After writing any shell script: verify set -euo pipefail is present,
SCRIPT_DIR is detected correctly, and cleanup traps are registered.
```

**What you lose**: Automatic enforcement. In Claude Code, validation happens regardless of whether you remember to ask. In Cursor, the rule reminds the model to check, but it relies on the model following through.

## Handoff on New Window

**Claude Code**: The `SessionStart` hook fires every time the IDE opens and auto-injects the most recent handoff file as context. Starting a new Claude Code session automatically picks up where you left off.

**Cursor**: The `post-checkout` git hook fires on branch switch, not on opening a new chat window. Opening a new Cursor chat with the same project does not automatically load the handoff.

**Workaround**: At the start of a new conversation, run `@pickup` or `@lets-go`:

```
you> @pickup
cursor> Found handoff: session-logs/handoff-2026-03-10-1800.md (2h old)
        Previously: migrating dot-cursor structure to match dot-droid
        Next steps: create install.sh, verify with dry-run
        Branch: main, clean, up to date.
```

The `session-start.mdc` always-apply rule also instructs Cursor to check for recent handoffs at conversation start, but it depends on the model noticing the rule instruction rather than a guaranteed hook.

**What you lose**: The automatic guarantee. In Claude Code, continuity is built in. In Cursor, you have to initiate it — muscle memory from Claude Code helps, but you'll occasionally start a conversation without context and not notice until you're partway through.

## No $ARGUMENTS in Agent Prompts

**Claude Code**: Commands receive structured arguments via `$ARGUMENTS`. Example: `/session-logger performance` passes "performance" as the topic, and the command template interpolates it.

**Cursor**: Agents in `modes.json` don't support structured argument passing.

**Workaround**: Pass context conversationally:

```
# Claude Code — one shot
/session-logger performance

# Cursor — conversational
@session-logger
you> Topic: performance refactoring
```

**What you lose**: Minor friction. Agents can parse natural language well enough that "log this session, topic is auth refactor" works fine. The difference is one extra turn.

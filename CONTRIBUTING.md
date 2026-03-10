# Contributing to dot-cursor

## Repo Structure

```
dot-cursor/
├── bin/                          # Installer scripts
│   ├── migrate-to-cursor.sh      # Cursor rules + agents + AGENTS.md
│   ├── setup-hooks.sh            # Git hooks + optional cron
│   └── setup-actions.sh          # GitHub Actions workflows
├── workflows/                    # GitHub Actions YAML sources
│   ├── pr-description.yml
│   ├── commit-lint.yml
│   ├── pr-review-checklist.yml
│   ├── session-maintenance.yml
│   └── branch-hygiene.yml
├── docs/                         # Documentation
│   ├── quickstart.md
│   ├── architecture.md
│   ├── cursor-rules-guide.md
│   ├── hooks-reference.md
│   ├── actions-reference.md
│   ├── concept-mapping.md
│   ├── migration-checklist.md    # Full phase-by-phase checklist
│   └── troubleshooting.md
├── templates/                    # Reusable rule + config templates
│   ├── always-apply.mdc.template
│   ├── glob-scoped.mdc.template
│   ├── python.mdc
│   ├── typescript.mdc
│   ├── docker.mdc
│   ├── terraform.mdc
│   └── AGENTS.md.template
├── Makefile                      # One-command install
├── README.md
├── CONTRIBUTING.md               # This file
├── LICENSE
└── .gitignore
```

## Development Workflow

### Testing scripts locally

Test against a scratch repo:

```bash
# Create a test project
mkdir /tmp/test-project && cd /tmp/test-project && git init

# Test each script independently
../dot-cursor/bin/migrate-to-cursor.sh --dry-run .
../dot-cursor/bin/migrate-to-cursor.sh .
../dot-cursor/bin/setup-hooks.sh .
../dot-cursor/bin/setup-actions.sh .

# Verify outputs
ls -la .cursor/rules/
cat .cursor/modes.json | python3 -m json.tool
ls -la .git/hooks/
ls -la .github/workflows/
```

### Testing with existing dot-claude/dot-copilot

```bash
# Clone an existing project that has dot-claude or dot-copilot
git clone <your-project> /tmp/test-with-copilot
cd /tmp/test-with-copilot

# Run migration — it should detect existing configs
../../dot-cursor/bin/migrate-to-cursor.sh --dry-run .
```

### Testing hooks

```bash
cd /tmp/test-project
../../dot-cursor/bin/setup-hooks.sh .

# Test prepare-commit-msg
echo "test" > test.txt && git add test.txt && git commit
# → Should see pre-filled template

# Test post-commit
# → Should see activity log created in session-logs/

# Test post-checkout
git checkout -b test-branch
# → Should see handoff message (or "no handoff found")

# Test pre-push
git commit --allow-empty -m "WIP: testing"
git push  # to a remote
# → Should see WIP warning
```

### Testing Actions

Push workflows to a test repo and open a PR:

```bash
cd /tmp/test-project
git remote add origin <test-repo-url>
git push -u origin main
git checkout -b test-pr
echo "change" >> test.txt && git add . && git commit -m "feat: test change"
git push -u origin test-pr
# Open PR on GitHub → verify workflows fire
```

## Adding New Features

### New Cursor rule template

1. Create the `.mdc` file in `templates/`
2. Add it to the table in `docs/cursor-rules-guide.md`
3. If the migration script should auto-generate it, add detection logic to `bin/migrate-to-cursor.sh`

### New git hook

1. Add the hook function to `bin/setup-hooks.sh`
2. Add the hook name to the install/uninstall arrays
3. Document in `docs/hooks-reference.md`
4. Test with the manual testing flow above

### New GitHub Actions workflow

1. Create the `.yml` file in `workflows/`
2. Add the filename to the `WORKFLOW_FILES` array in `bin/setup-actions.sh`
3. Document in `docs/actions-reference.md`
4. Add any required labels to the "Required GitHub Labels" section
5. Test in a real repo

### New documentation

1. Create the `.md` file in `docs/`
2. Add a row to the documentation table in `README.md`
3. Cross-link from related docs

## Conventions

- Scripts use `set -euo pipefail`
- Scripts include colored output helpers: `log_info`, `log_ok`, `log_warn`
- All generated content includes a marker comment for identification (e.g., `CURSOR-MIGRATION-HOOK`)
- Scripts support `--dry-run` where destructive
- Scripts detect and chain with existing configs rather than overwriting

## Commit Format

This repo uses conventional commits (naturally):

```
type(scope): description

feat(hooks): add post-rebase hook for session context
fix(actions): handle repos with no session-logs directory
docs(rules): add Rust template
```

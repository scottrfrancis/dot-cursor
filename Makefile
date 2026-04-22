# dot-cursor Makefile
#
# Usage:
#   make install PROJECT=/path/to/your/project    # Install everything
#   make cursor  PROJECT=/path/to/your/project    # Just Cursor rules + agents
#   make hooks   PROJECT=/path/to/your/project    # Just git hooks
#   make actions PROJECT=/path/to/your/project    # Just GitHub Actions workflows
#   make preview PROJECT=/path/to/your/project    # Dry-run, show what would change
#   make uninstall PROJECT=/path/to/your/project  # Remove hooks + actions
#   make sync                                     # Sync templates/ from ~/.claude/guidelines/
#   make sync-preview                             # Dry-run the sync

SHELL := /bin/bash
PROJECT ?=

.PHONY: install cursor hooks actions preview uninstall sync sync-preview help

help: ## Show this help
	@echo "dot-cursor — Cursor IDE migration toolkit"
	@echo ""
	@echo "Usage: make <target> PROJECT=/path/to/your/project"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
	@echo ""
	@echo "Example:"
	@echo "  make install PROJECT=~/projects/my-app"

check-project:
ifndef PROJECT
	$(error PROJECT is required. Usage: make install PROJECT=/path/to/your/project)
endif
	@test -d "$(PROJECT)" || (echo "Error: $(PROJECT) is not a directory" && exit 1)

install: check-project cursor hooks actions ## Install everything into PROJECT
	@echo ""
	@echo "═══════════════════════════════════════════════════════"
	@echo "  All layers installed into $(PROJECT)"
	@echo "═══════════════════════════════════════════════════════"
	@echo ""
	@echo "Next steps:"
	@echo "  1. cd $(PROJECT)"
	@echo "  2. cat generated/cursor-user-rules.txt  → paste into Cursor User Rules"
	@echo "  3. git add .cursor/ .github/workflows/ AGENTS.md .cursorignore"
	@echo "  4. git commit -m 'build: add Cursor rules, agents, hooks, and CI workflows'"
	@echo "  5. git push"
	@echo "  6. Create GitHub labels: session-maintenance, branch-hygiene"

cursor: check-project ## Install Cursor rules, agents, AGENTS.md
	@bin/migrate-to-cursor.sh "$(PROJECT)"

hooks: check-project ## Install git hooks
	@bin/setup-hooks.sh "$(PROJECT)"

actions: check-project ## Install GitHub Actions workflows
	@bin/setup-actions.sh "$(PROJECT)"

preview: check-project ## Dry-run — show what would be created
	@bin/migrate-to-cursor.sh --dry-run "$(PROJECT)"

uninstall: check-project ## Remove hooks and Actions workflows
	@bin/setup-hooks.sh --uninstall "$(PROJECT)"
	@bin/setup-actions.sh --remove "$(PROJECT)"
	@echo "Hooks and workflows removed. .cursor/ rules and AGENTS.md left in place."

sync: ## Propagate ~/.claude/guidelines/ edits into templates/ (preserves template frontmatter)
	@bin/sync-from-dot-claude.sh

sync-preview: ## Dry-run the sync — show which templates would change
	@bin/sync-from-dot-claude.sh --dry-run

#!/usr/bin/env bash
# install.sh — wire HIVE hooks into git for this clone
# Run once after cloning: bash .githooks/install.sh
#
# This sets core.hooksPath so git uses .githooks/ instead of .git/hooks/

set -euo pipefail

if [[ ! -d ".git" ]]; then
    echo "Error: run from the repository root (no .git found)" >&2
    exit 1
fi

git config core.hooksPath .githooks
chmod +x .githooks/commit-msg .githooks/prepare-commit-msg .githooks/pre-commit .githooks/pre-commit-review .githooks/pre-push .githooks/install.sh

GREEN='\033[0;32m'; NC='\033[0m'
echo -e "${GREEN}✓${NC} HIVE git hooks installed."
echo "  git will now use .githooks/ for all hook events."
echo ""
echo "  Bypass for a single command: HIVE_SKIP_HOOKS=1 git commit ..."

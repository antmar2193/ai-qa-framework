#!/usr/bin/env bash
# ============================================================
# install-hooks.sh — Install HIVE git hooks locally
#
# Run once after cloning or pulling the HIVE factory repo.
# Installs a pre-commit hook that runs check-principles.sh
# in strict mode before every commit.
#
# Usage:
#   bash scripts/install-hooks.sh
#   bash scripts/install-hooks.sh --uninstall
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"
PRE_COMMIT="$HOOKS_DIR/pre-commit"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

# ── Uninstall ─────────────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
    if [[ -f "$PRE_COMMIT" ]] && grep -q "hive:pre-commit" "$PRE_COMMIT"; then
        rm "$PRE_COMMIT"
        echo -e "${GREEN}✓${NC} Pre-commit hook removed."
    else
        echo -e "${YELLOW}!${NC} No HIVE pre-commit hook found — nothing to remove."
    fi
    exit 0
fi

# ── Validate git repo ─────────────────────────────────────────
if [[ ! -d "$HOOKS_DIR" ]]; then
    echo -e "${RED}✗${NC} .git/hooks not found. Run this from inside the HIVE repo."
    exit 1
fi

# ── Write hook ────────────────────────────────────────────────
cat > "$PRE_COMMIT" <<'EOF'
#!/usr/bin/env bash
# hive:pre-commit — managed by scripts/install-hooks.sh

REPO_ROOT="$(git rev-parse --show-toplevel)"

echo ""
echo "  [HIVE] Running principle checks before commit..."
echo ""

if bash "$REPO_ROOT/scripts/check-principles.sh" --strict; then
    exit 0
else
    echo ""
    echo "  Commit blocked. Fix the violations above and try again."
    echo "  To skip (not recommended): git commit --no-verify"
    echo ""
    exit 1
fi
EOF

chmod +x "$PRE_COMMIT"

echo -e "${GREEN}✓${NC} Pre-commit hook installed at .git/hooks/pre-commit"
echo -e "  Runs: check-principles.sh --strict on every commit."
echo -e "  To remove: bash scripts/install-hooks.sh --uninstall"

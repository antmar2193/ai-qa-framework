#!/usr/bin/env bash
# ============================================================
# deliver.sh — Push code to the client repo (without hive/)
#
# Syncs the current project state to a separate client-facing
# repo that contains only the deliverable code — no hive/,
# no AGENTS.md, no factory tooling.
#
# Two modes:
#   --init    First delivery: creates the client repo structure
#             and pushes an initial commit. Run once per project.
#   --update  Subsequent deliveries: syncs latest changes to
#             the client repo. Run at sprint end or on demand.
#
# Usage:
#   ./scripts/deliver.sh --init   <client-repo-url>
#   ./scripts/deliver.sh --update <client-repo-url>
#
# The client repo URL can also be set in AGENTS.local.md:
#   delivery.client_repo_url: "https://github.com/client-org/project"
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "\n${CYAN}──${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

MODE="${1:-}"
CLIENT_REPO="${2:-}"

[[ -z "$MODE" ]] && error "Usage: $0 --init|--update <client-repo-url>"
[[ "$MODE" != "--init" && "$MODE" != "--update" ]] && error "Mode must be --init or --update"

# Try to read client repo URL from AGENTS.local.md if not passed
if [[ -z "$CLIENT_REPO" && -f "hive/AGENTS.local.md" ]]; then
    CLIENT_REPO=$(awk -F'"' '/client_repo_url:/ { print $2; exit }' .hive/AGENTS.local.md 2>/dev/null || echo "")
fi

[[ -z "$CLIENT_REPO" ]] && error "Client repo URL required. Pass it as argument or set delivery.client_repo_url in AGENTS.local.md"

# ── Read project name ─────────────────────────────────────────
PROJECT_NAME=$(awk -F'"' '/^name:/ { print $2; exit }' .hive/AGENTS.local.md 2>/dev/null); PROJECT_NAME="${PROJECT_NAME:-$(basename "$(pwd)")}"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
TIMESTAMP=$(date +%Y-%m-%d\ %H:%M)

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║   HIVE — Client Delivery                  ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
echo "  Project     : $PROJECT_NAME"
echo "  Mode        : $MODE"
echo "  Source      : $CURRENT_BRANCH"
echo "  Client repo : $CLIENT_REPO"
echo ""

# ── Confirm ───────────────────────────────────────────────────
read -p "  Proceed? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && { echo "  Aborted."; exit 0; }

# ── Verify working tree is clean ──────────────────────────────
step "Checking working tree"
if ! git diff --quiet || ! git diff --staged --quiet; then
    warn "You have uncommitted changes."
    read -p "  Continue anyway? [y/N]: " FORCE
    [[ "${FORCE,,}" != "y" ]] && error "Commit or stash changes before delivery."
fi

# ── Create a delivery worktree ────────────────────────────────
# We use a temp directory to avoid modifying the working tree
TMPDIR=$(mktemp -d)
trap 'rm -rf '"$TMPDIR" EXIT

step "Preparing delivery content"
git archive HEAD | tar -x -C "$TMPDIR"

# Remove HIVE framework layer from delivery copy
rm -rf "$TMPDIR/.hive"
rm -f  "$TMPDIR/AGENTS.md"
rm -f  "$TMPDIR/CLAUDE.md"
rm -f  "$TMPDIR/GEMINI.md"
rm -f  "$TMPDIR/codex.md"
rm -rf "$TMPDIR/.claude"
rm -rf "$TMPDIR/.cursor"
rm -f  "$TMPDIR/scripts/new-project.sh"
rm -f  "$TMPDIR/scripts/inject-factory.sh"
rm -f  "$TMPDIR/scripts/sync-standards.sh"
rm -f  "$TMPDIR/scripts/deliver.sh"
rm -f  "$TMPDIR/AGENTS.local.template.md"
rmdir  "$TMPDIR/scripts" 2>/dev/null || true
rm -f  "$TMPDIR/VERSION"
rm -f  "$TMPDIR/CHANGELOG.md"

# Move src/ contents to root (client gets clean structure)
if [[ -d "$TMPDIR/src" ]]; then
    cp -r "$TMPDIR/src/." "$TMPDIR/"
    rm -rf "$TMPDIR/src"
    info "src/ contents moved to root for client delivery"
fi

# Replace workspace README with client README
if [[ -f "$TMPDIR/.hive/templates/README.client.md" ]]; then
    cp "$TMPDIR/.hive/templates/README.client.md" "$TMPDIR/README.md"
    info "Client README applied"
fi

info "HIVE layer removed from delivery copy"

# ── Update .gitignore in delivery (ensure hive excluded) ──
# Already excluded because we deleted them, but add to .gitignore
# in case the client merges anything back
if [[ -f "$TMPDIR/.gitignore" ]]; then
    {
        echo ""
        echo "# HIVE layer (internal tooling — not part of this codebase)"
        echo ".hive/"
        echo "AGENTS.md"
        echo "CLAUDE.md"
        echo "GEMINI.md"
        echo "codex.md"
    } >> "$TMPDIR/.gitignore"
fi

# ── Initialize or update client repo ─────────────────────────
CLIENT_DIR="$TMPDIR/client-repo"
mkdir -p "$CLIENT_DIR"

if [[ "$MODE" == "--init" ]]; then
    step "Initializing client repo"

    cd "$CLIENT_DIR"
    git init
    git remote add origin "$CLIENT_REPO"

    # Copy delivery content into client repo
    cp -r "$TMPDIR"/. "$CLIENT_DIR/" 2>/dev/null || true
    rm -rf "$CLIENT_DIR/client-repo"  # avoid self-copy

    git add .
    git commit -m "feat: initial delivery — ${PROJECT_NAME}

Delivered: ${TIMESTAMP}
Source branch: ${CURRENT_BRANCH}"

    git branch -M main
    git push -u origin main

    info "Client repo initialized: $CLIENT_REPO"

elif [[ "$MODE" == "--update" ]]; then
    step "Updating client repo"

    cd "$CLIENT_DIR"
    git clone "$CLIENT_REPO" . 2>/dev/null || {
        warn "Could not clone client repo — check URL and permissions"
        error "Clone failed: $CLIENT_REPO"
    }

    # Sync delivery content (overwrite, preserve git history)
    # Use rsync to copy only changed files, excluding .git
    rsync -a --delete \
        --exclude='.git' \
        --exclude='hive/' \
        --exclude='AGENTS.md' \
        "$TMPDIR/" "$CLIENT_DIR/"

    cd "$CLIENT_DIR"

    if git diff --quiet && git diff --staged --quiet; then
        info "No changes to deliver — client repo is already up to date"
    else
        git add .
        git diff --staged --stat
        echo ""
        read -p "  Commit and push these changes to client repo? [y/N]: " PUSH_CONFIRM
        if [[ "${PUSH_CONFIRM,,}" == "y" ]]; then
            git commit -m "chore: sync delivery — ${TIMESTAMP}

Source branch: ${CURRENT_BRANCH}"
            git push origin main
            info "Client repo updated: $CLIENT_REPO"
        else
            warn "Changes prepared but not pushed. Run manually from: $CLIENT_DIR"
        fi
    fi
fi

# ── Notify team ───────────────────────────────────────────────
if [[ -f ".hive/scripts/hive-notify.sh" ]]; then
    bash .hive/scripts/hive-notify.sh \
        --event delivery \
        --message "Delivery complete — ${PROJECT_NAME} → client repo updated (${CURRENT_BRANCH})" \
        --status success 2>/dev/null || true
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════════════╗"
echo -e "║  ${GREEN}✓ Delivery complete${NC}"
echo "╚═══════════════════════════════════════════════════╝"
echo ""
echo "  Client repo : $CLIENT_REPO"
echo "  Delivered   : $TIMESTAMP"
echo ""
echo "  What the client has:"
echo "  - All source code from $CURRENT_BRANCH"
echo "  - CI/CD workflows, README, .env.example"
echo ""
echo "  What the client does NOT have:"
echo "  - hive/ (standards, agents, commands)"
echo "  - AGENTS.md"
echo "  - Factory scripts"
echo ""

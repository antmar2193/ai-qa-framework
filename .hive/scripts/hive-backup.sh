#!/usr/bin/env bash
# hive-backup.sh — snapshot and restore HIVE-managed files
#
# Usage:
#   ./scripts/hive-backup.sh create <project-path>    # create snapshot
#   ./scripts/hive-backup.sh restore <project-path>   # restore latest snapshot
#   ./scripts/hive-backup.sh list <project-path>       # list available snapshots
#   ./scripts/hive-backup.sh restore <project-path> <snapshot-id>  # restore specific snapshot
#
# Snapshots stored in: <project-path>/.hive/backups/
# Format: tar.gz with manifest.json

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1" >&2; }

ACTION="${1:-}"
PROJECT_PATH="${2:-$(pwd)}"
SNAPSHOT_ID="${3:-}"
BACKUP_DIR="$PROJECT_PATH/.hive/backups"

# Files managed by HIVE — these are snapshotted
MANAGED_FILES=(
    "AGENTS.md"
    "CLAUDE.md"
    "GEMINI.md"
    "codex.md"
    ".hive/AGENTS.local.md"
    ".hive/STACK.md"
    ".hive/standards/core.mdc"
    ".hive/standards/backend.mdc"
    ".hive/standards/frontend.mdc"
    ".hive/.commands"
    ".hive/.agents"
    ".hive/generate.yml"
    ".githooks"
)

sha256_of_files() {
    local project="$1"
    local hash=""
    for f in "${MANAGED_FILES[@]}"; do
        local full="$project/$f"
        if [[ -f "$full" ]]; then
            hash="${hash}$(sha256sum "$full" 2>/dev/null || shasum -a 256 "$full" 2>/dev/null | cut -d' ' -f1)"
        elif [[ -d "$full" ]]; then
            hash="${hash}$(find "$full" -type f | sort | xargs sha256sum 2>/dev/null || find "$full" -type f | sort | xargs shasum -a 256 2>/dev/null | cut -d' ' -f1 | tr -d ' ')"
        fi
    done
    echo "$hash" | sha256sum 2>/dev/null | cut -d' ' -f1 || \
    echo "$hash" | shasum -a 256 2>/dev/null | cut -d' ' -f1
}

do_create() {
    mkdir -p "$BACKUP_DIR"

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    SNAPSHOT_DIR="$BACKUP_DIR/$TIMESTAMP"
    mkdir -p "$SNAPSHOT_DIR"

    # Deduplication: compare hash with latest backup
    LATEST=$(find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d -not -name 'latest' -printf '%f\n' 2>/dev/null | sort -r | head -1 || echo "")
    CURRENT_HASH=$(sha256_of_files "$PROJECT_PATH")

    if [[ -n "$LATEST" && -f "$BACKUP_DIR/$LATEST/manifest.json" ]]; then
        PREV_HASH=$(awk -F'"' '/"checksum":/ { print $4; exit }' "$BACKUP_DIR/$LATEST/manifest.json" 2>/dev/null || echo "")
        if [[ "$PREV_HASH" == "$CURRENT_HASH" ]]; then
            info "No changes since last backup — skipping snapshot"
            rm -rf "$SNAPSHOT_DIR"
            return 0
        fi
    fi

    # Create tar.gz of managed files that exist
    FILES_TO_BACKUP=()
    for f in "${MANAGED_FILES[@]}"; do
        [[ -e "$PROJECT_PATH/$f" ]] && FILES_TO_BACKUP+=("$f")
    done

    if [[ ${#FILES_TO_BACKUP[@]} -eq 0 ]]; then
        warn "No managed files found to backup"
        rm -rf "$SNAPSHOT_DIR"
        return 0
    fi

    cd "$PROJECT_PATH"
    tar czf "$SNAPSHOT_DIR/snapshot.tar.gz" "${FILES_TO_BACKUP[@]}" 2>/dev/null
    cd - > /dev/null

    # Write manifest
    cat > "$SNAPSHOT_DIR/manifest.json" << EOF
{
  "id": "$TIMESTAMP",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "checksum": "$CURRENT_HASH",
  "file_count": ${#FILES_TO_BACKUP[@]},
  "files": $(printf '%s\n' "${FILES_TO_BACKUP[@]}" | python3 -c "import json,sys; print(json.dumps([l.rstrip() for l in sys.stdin]))" 2>/dev/null || echo "[]")
}
EOF

    # Keep only last 5 backups (never delete pinned)
    ls -t "$BACKUP_DIR" | tail -n +6 | while read -r old; do
        [[ -f "$BACKUP_DIR/$old/manifest.json" ]] && \
        grep -q '"pinned": true' "$BACKUP_DIR/$old/manifest.json" 2>/dev/null && continue
        rm -rf "${BACKUP_DIR:?}/$old"
    done

    info "Snapshot created: $TIMESTAMP (${#FILES_TO_BACKUP[@]} files)"
}

do_restore() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        err "No backups found at $BACKUP_DIR"
        exit 1
    fi

    if [[ -n "$SNAPSHOT_ID" ]]; then
        TARGET="$BACKUP_DIR/$SNAPSHOT_ID"
    else
        TARGET="$BACKUP_DIR/$(ls -t "$BACKUP_DIR" | head -1)"
    fi

    if [[ ! -f "$TARGET/snapshot.tar.gz" ]]; then
        err "Snapshot not found: $TARGET"
        exit 1
    fi

    SNAP_ID=$(basename "$TARGET")
    read -p "  Restore snapshot $SNAP_ID to $PROJECT_PATH? [y/N]: " CONFIRM
    [[ "${CONFIRM,,}" != "y" ]] && { echo "  Aborted."; exit 0; }

    tar xzf "$TARGET/snapshot.tar.gz" -C "$PROJECT_PATH"
    info "Restored snapshot $SNAP_ID to $PROJECT_PATH"
}

do_list() {
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        echo "  No backups found."
        return
    fi
    echo "  Available snapshots:"
    ls -t "$BACKUP_DIR" | while read -r snap; do
        [[ -f "$BACKUP_DIR/$snap/manifest.json" ]] && \
        echo "  - $snap ($(awk -F: '/"file_count":/ { gsub(/[^0-9]/,"",$2); print $2; exit }' "$BACKUP_DIR/$snap/manifest.json" 2>/dev/null || echo '?') files)"
    done
}

case "$ACTION" in
    create)  do_create ;;
    restore) do_restore ;;
    list)    do_list ;;
    *) echo "Usage: $0 create|restore|list <project-path> [snapshot-id]"; exit 1 ;;
esac

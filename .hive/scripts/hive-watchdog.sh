#!/usr/bin/env bash
# ============================================================
# hive-watchdog.sh — Batch recovery after interruption
#
# Detects incomplete batch sessions (token exhaustion, server restart,
# crash mid-ticket) and offers recovery options.
#
# Usage:
#   bash .hive/scripts/hive-watchdog.sh           # Inspect all sessions, recommend action
#   bash .hive/scripts/hive-watchdog.sh --auto    # Auto-resume latest incomplete batch
#   bash .hive/scripts/hive-watchdog.sh BATCH_ID  # Inspect specific session
#
# Typical flow after token limit resets:
#   1. hive watchdog                 → shows what's incomplete
#   2. hive run --resume BATCH_ID   → continues from first incomplete ticket
#
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/require-python3.sh
source "$SCRIPT_DIR/lib/require-python3.sh"

if [[ "$SCRIPT_DIR" == *"/.hive/scripts" ]]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
    PROJECT_ROOT="$(pwd)"
fi

HIVE_DIR="$PROJECT_ROOT/.hive"
FACTORY_ROOT="${HIVE_FACTORY_ROOT:-}"
if [[ -z "$FACTORY_ROOT" && -f "$HIVE_DIR/AGENTS.local.md" ]]; then
    FACTORY_ROOT="$(awk -F'"' '/hive_root:/ { print $2; exit }' "$HIVE_DIR/AGENTS.local.md" 2>/dev/null || echo "")"
fi
HIVE_VERSION="$(cat "$FACTORY_ROOT/VERSION" 2>/dev/null || echo "dev")"

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'

ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$1"; }
err()  { printf "  ${RED}✗${NC} %s\n" "$1" >&2; }
info() { printf "  ${CYAN}→${NC} %s\n" "$1"; }

# ── Parse args ────────────────────────────────────────────────
AUTO_MODE=false
TARGET_BATCH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto) AUTO_MODE=true ;;
        --help|-h) cat <<'HELP'
Usage:
  hive watchdog              # inspect all incomplete sessions
  hive watchdog --auto       # auto-resume latest incomplete batch
  hive watchdog BATCH_ID     # inspect specific session
  hive watchdog BATCH_ID --auto  # auto-resume specific session
HELP
        exit 0 ;;
        *) TARGET_BATCH="$1" ;;
    esac
    shift
done

# ── Banner ────────────────────────────────────────────────────
echo ""
printf "${CYAN}${BOLD}HIVE v%s${NC}  ${DIM}Watchdog${NC}\n" "$HIVE_VERSION"
echo ""

# ── Check for project ─────────────────────────────────────────
if [[ ! -f "$HIVE_DIR/AGENTS.local.md" ]]; then
    err "Not in a HIVE project (.hive/AGENTS.local.md not found)"
    exit 1
fi

if [[ ! -d "$HIVE_DIR/sessions" ]]; then
    info "No sessions directory found — no batch runs to recover"
    exit 0
fi

# ── Find incomplete batches ───────────────────────────────────
find_incomplete() {
    local target="${1:-}"
    python3 - "$HIVE_DIR/sessions" "$target" <<'PYEOF'
import json, os, sys, glob
sessions_dir = sys.argv[1]
target = sys.argv[2]

pattern = f"{sessions_dir}/batch_{target}*.json" if target else f"{sessions_dir}/batch_*.json"
files = sorted(glob.glob(pattern), reverse=True)

incomplete = []
for f in files:
    try:
        d = json.load(open(f))
        tickets  = d.get('tickets', [])
        results  = d.get('results', {})
        completed = d.get('completed_at', '')
        pending  = [t for t in tickets if results.get(t, {}).get('status') not in ('ok', 'dry_run')]
        failed   = [t for t in tickets if results.get(t, {}).get('status') == 'failed']
        done     = sum(1 for t in tickets if results.get(t, {}).get('status') == 'ok')
        cost     = sum(v.get('cost_usd', 0) for v in results.values())
        batch_id = d.get('batch_id', os.path.basename(f).replace('batch_','').replace('.json',''))
        if not completed and pending:
            incomplete.append({
                'batch_id':  batch_id,
                'file':      f,
                'tickets':   tickets,
                'pending':   pending,
                'failed':    failed,
                'done':      done,
                'cost':      cost,
                'started_at': d.get('started_at', '?')[:19],
            })
    except:
        pass

import json as j
print(j.dumps(incomplete))
PYEOF
}

INCOMPLETE_JSON=$(find_incomplete "$TARGET_BATCH" 2>/dev/null || echo "[]")

COUNT=$(echo "$INCOMPLETE_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)

if [[ "$COUNT" -eq 0 ]]; then
    ok "No incomplete batch sessions found"
    echo ""
    # Also report on completed sessions
    COMPLETED=$(python3 - "$HIVE_DIR/sessions" 2>/dev/null <<'PYEOF'
import json, sys, glob
d = glob.glob(f"{sys.argv[1]}/batch_*.json")
completed = []
for f in sorted(d, reverse=True)[:5]:
    try:
        data = json.load(open(f))
        if data.get('completed_at'):
            p = data.get('passed', 0)
            t = len(data.get('tickets', []))
            c = data.get('total_cost_usd', 0)
            dt = data.get('completed_at', '?')[:19]
            completed.append(f"  {data['batch_id']}  completed {dt}  {p}/{t} passed  ${c:.4f}")
    except:
        pass
print('\n'.join(completed))
PYEOF
)
    if [[ -n "$COMPLETED" ]]; then
        echo "  Recent completed batches:"
        echo "$COMPLETED"
        echo ""
    fi
    exit 0
fi

# ── Show incomplete sessions ──────────────────────────────────
python3 - "$INCOMPLETE_JSON" <<'PYEOF'
import json, sys

data = json.loads(sys.argv[1])
BOLD = "\033[1m"; CYAN = "\033[0;36m"; GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"; RED = "\033[0;31m"; NC = "\033[0m"

print(f"{YELLOW}  {len(data)} incomplete batch session(s) found:{NC}\n")

for b in data:
    print(f"  {BOLD}{b['batch_id']}{NC}  started {b['started_at']}")
    print(f"    tickets : {', '.join(b['tickets'])}")
    print(f"    done    : {b['done']}/{len(b['tickets'])}  (${b['cost']:.4f} spent)")
    if b['failed']:
        print(f"    {RED}failed  : {', '.join(b['failed'])}{NC}")
    print(f"    {YELLOW}pending : {', '.join(b['pending'])}{NC}")
    print(f"    resume  : hive run --resume {b['batch_id']}")
    print()
PYEOF

# ── Auto-resume ───────────────────────────────────────────────
if $AUTO_MODE; then
    # Pick the most recent incomplete batch
    LATEST_BATCH=$(echo "$INCOMPLETE_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data: print(data[0]['batch_id'])
" 2>/dev/null || echo "")

    if [[ -z "$LATEST_BATCH" ]]; then
        err "Could not determine batch to resume"
        exit 1
    fi

    info "Auto-resuming batch: $LATEST_BATCH"
    echo ""

    # Find the hive-run.sh script (same dir as this script or project .hive/scripts)
    RUN_SCRIPT=""
    [[ -f "$SCRIPT_DIR/hive-run.sh" ]] && RUN_SCRIPT="$SCRIPT_DIR/hive-run.sh"
    [[ -z "$RUN_SCRIPT" && -f "$HIVE_DIR/scripts/hive-run.sh" ]] && \
        RUN_SCRIPT="$HIVE_DIR/scripts/hive-run.sh"
    [[ -z "$RUN_SCRIPT" && -n "$FACTORY_ROOT" && -f "$FACTORY_ROOT/scripts/hive-run.sh" ]] && \
        RUN_SCRIPT="$FACTORY_ROOT/scripts/hive-run.sh"

    if [[ -z "$RUN_SCRIPT" ]]; then
        err "hive-run.sh not found — run manually:"
        info "hive run --resume $LATEST_BATCH"
        exit 1
    fi

    exec bash "$RUN_SCRIPT" --resume "$LATEST_BATCH"
fi

# ── Print recovery instructions ───────────────────────────────
if [[ "$COUNT" -eq 1 ]]; then
    BATCH_ID=$(echo "$INCOMPLETE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['batch_id'])" 2>/dev/null || echo "")
    if [[ -n "$BATCH_ID" ]]; then
        echo "  To resume:"
        printf "    hive run --resume %s\n\n" "$BATCH_ID"
        echo "  To resume automatically when tokens reset:"
        printf "    hive watchdog --auto\n\n"
    fi
else
    echo "  To resume a specific batch:"
    printf "    hive run --resume <batch-id>\n\n"
    echo "  To auto-resume the latest incomplete batch:"
    printf "    hive watchdog --auto\n\n"
fi

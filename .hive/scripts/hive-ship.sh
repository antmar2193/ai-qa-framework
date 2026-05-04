#!/usr/bin/env bash
# ============================================================
# hive-ship.sh — Single-ticket pipeline with cost/token tracking
#
# Runs /ship for one ticket via claude --output-format stream-json.
# Captures cost_usd, duration_ms, input_tokens, output_tokens from
# the CLI JSON output and writes a ticket_complete event to
# .hive/events.jsonl — same format as hive-run.sh.
#
# Use this instead of typing /ship directly when you want cost tracking.
# For interactive sessions with human checkpoints, use /ship in Claude Code
# with autonomy.level: supervised or balanced.
#
# Usage (from project root):
#   bash .hive/scripts/hive-ship.sh PAY-42
#   bash .hive/scripts/hive-ship.sh PAY-42 --from tdd
#   hive ship PAY-42
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
LOGS_DIR="$HIVE_DIR/logs"

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
TICKET=""
FROM_PHASE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from) FROM_PHASE="$2"; shift ;;
        --help|-h)
            echo "Usage: hive ship <ticket-id> [--from <phase>]"
            echo ""
            echo "  Runs /ship for one ticket and records cost, duration, and tokens."
            echo "  Output is shown in real time. Cost is written to .hive/events.jsonl."
            echo ""
            echo "  Note: runs non-interactively (no checkpoints). For supervised/balanced"
            echo "  autonomy with human review, use /ship directly in Claude Code."
            exit 0 ;;
        -*) warn "Unknown flag: $1" ;;
        *)  [[ -z "$TICKET" ]] && TICKET="$1" ;;
    esac
    shift
done

if [[ -z "$TICKET" ]]; then
    err "No ticket specified."
    echo "  Usage: hive ship <ticket-id> [--from <phase>]"
    exit 1
fi

if [[ ! -f "$HIVE_DIR/AGENTS.local.md" ]]; then
    err "Not in a HIVE project (.hive/AGENTS.local.md not found)"
    exit 1
fi

# ── Detect AI CLI ─────────────────────────────────────────────
AI_CMD=""
if command -v claude &>/dev/null; then AI_CMD="claude"
elif command -v gemini &>/dev/null; then AI_CMD="gemini"
fi

if [[ -z "$AI_CMD" ]]; then
    err "No AI CLI found (claude or gemini)"
    exit 1
fi

# ── Check autonomy ────────────────────────────────────────────
AUTONOMY=$(awk -F'"' '/level:/ { print $2; exit }' "$HIVE_DIR/AGENTS.local.md" 2>/dev/null)
AUTONOMY="${AUTONOMY:-supervised}"
if [[ "$AUTONOMY" != "autonomous" ]]; then
    warn "autonomy.level is '${AUTONOMY}' — checkpoints won't pause in non-interactive mode"
    warn "For supervised/balanced with human review, use /ship directly in Claude Code"
    echo ""
fi

# ── Setup ─────────────────────────────────────────────────────
mkdir -p "$LOGS_DIR"
SHIP_LOG="$LOGS_DIR/ship_${TICKET}_$(date +%Y%m%d_%H%M%S).log"
EVENTS_FILE="$HIVE_DIR/events.jsonl"

SHIP_CMD="/ship $TICKET"
[[ -n "$FROM_PHASE" ]] && SHIP_CMD="$SHIP_CMD --from $FROM_PHASE"

echo ""
printf "${CYAN}${BOLD}HIVE v%s${NC}  ${DIM}Ship${NC}\n\n" "$HIVE_VERSION"
info "Ticket : $TICKET"
info "Command: $SHIP_CMD"
info "Log    : $SHIP_LOG"
echo ""

START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_S=$(date +%s)

# ── Run and stream output ─────────────────────────────────────
TICKET_LOG=$(mktemp)
EXIT_CODE=0

if [[ "$AI_CMD" == "claude" ]]; then
    # Stream-json: pipe through Python to show text events in real time,
    # while tee captures the full stream for cost/token parsing.
    claude --output-format stream-json -p "$SHIP_CMD" \
        | tee "$TICKET_LOG" \
        | python3 -u -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        if d.get('type') == 'assistant':
            for b in d.get('message', {}).get('content', []):
                if b.get('type') == 'text' and b['text']:
                    print(b['text'], end='', flush=True)
    except:
        pass
" 2>/dev/null || true
    EXIT_CODE=${PIPESTATUS[0]}
else
    "$AI_CMD" -p "$SHIP_CMD" | tee "$TICKET_LOG" || EXIT_CODE=$?
fi

# Append full stream-json to log for audit trail
cat "$TICKET_LOG" >> "$SHIP_LOG" 2>/dev/null || true

# ── Parse cost and tokens ─────────────────────────────────────
END_S=$(date +%s)
END_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

PARSE_OUT=$(python3 - "$TICKET_LOG" 2>/dev/null <<'PYEOF'
import json, sys
cost = 0; dur = 0; is_err = False
in_tok = 0; out_tok = 0
for line in open(sys.argv[1], errors='replace'):
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        t = d.get('type', '')
        if t == 'result':
            cost   = d.get('cost_usd') or d.get('total_cost_usd') or 0
            dur    = d.get('duration_ms') or 0
            is_err = bool(d.get('is_error', False))
        elif t == 'assistant':
            usage  = d.get('message', {}).get('usage', {})
            in_tok  += int(usage.get('input_tokens', 0) or 0)
            out_tok += int(usage.get('output_tokens', 0) or 0)
            in_tok  += int(usage.get('cache_read_input_tokens', 0) or 0)
    except:
        pass
print(f"{cost},{dur},{1 if is_err else 0},{in_tok},{out_tok}")
PYEOF
) || PARSE_OUT="0,0,0,0,0"

rm -f "$TICKET_LOG"

COST_USD=$(echo "$PARSE_OUT"    | cut -d',' -f1)
DURATION_MS=$(echo "$PARSE_OUT" | cut -d',' -f2)
IS_ERR=$(echo "$PARSE_OUT"      | cut -d',' -f3)
INPUT_TOK=$(echo "$PARSE_OUT"   | cut -d',' -f4)
OUTPUT_TOK=$(echo "$PARSE_OUT"  | cut -d',' -f5)
TOTAL_TOK=$(( ${INPUT_TOK:-0} + ${OUTPUT_TOK:-0} ))

[[ "$IS_ERR" == "1" ]] && EXIT_CODE=1

if [[ "$DURATION_MS" -gt 0 ]]; then
    DURATION_S=$((DURATION_MS / 1000))
else
    DURATION_S=$((END_S - START_S))
fi

# ── Write event ───────────────────────────────────────────────
STATUS="$( [[ $EXIT_CODE -eq 0 ]] && echo ok || echo failed)"

printf '{"ts":"%s","cmd":"ship","ticket":"%s","event":"ticket_complete","status":"%s","duration_s":%d,"cost_usd":%s,"input_tokens":%d,"output_tokens":%d,"tokens":%d,"started_at":"%s"}\n' \
    "$END_TS" "$TICKET" "$STATUS" "$DURATION_S" "${COST_USD:-0}" \
    "${INPUT_TOK:-0}" "${OUTPUT_TOK:-0}" "$TOTAL_TOK" "$START_TS" \
    >> "$EVENTS_FILE" 2>/dev/null || true

# ── Summary ───────────────────────────────────────────────────
echo ""
echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    TOK_S="$( [[ $TOTAL_TOK -gt 0 ]] && printf '  %s tok (%s in / %s out)' "$TOTAL_TOK" "$INPUT_TOK" "$OUTPUT_TOK" || echo '')"
    ok "$TICKET — ${DURATION_S}s  \$${COST_USD}${TOK_S}"
    info "Event logged to: $EVENTS_FILE"
else
    err "$TICKET — failed in ${DURATION_S}s  (\$${COST_USD})"
    info "Log: $SHIP_LOG"
fi
echo ""
exit $EXIT_CODE

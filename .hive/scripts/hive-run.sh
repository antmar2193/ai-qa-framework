#!/usr/bin/env bash
# ============================================================
# hive-run.sh — Batch ticket processing for server/unattended use
#
# Processes each ticket sequentially as its own AI session.
# Each /ship call runs independently: branch → implement → PR → CI → merge.
# This eliminates context overflow for large batches and makes
# token/cost tracking and recovery trivial.
#
# Usage (from project root):
#   bash .hive/scripts/hive-run.sh PAY-42 PAY-43 PAY-44
#   bash .hive/scripts/hive-run.sh --file tickets.txt
#   bash .hive/scripts/hive-run.sh --sprint current
#   bash .hive/scripts/hive-run.sh --dry-run PAY-42 PAY-43
#   bash .hive/scripts/hive-run.sh --list               # show batch sessions
#   bash .hive/scripts/hive-run.sh --resume BATCH_ID    # continue after interruption
#
# Architecture — one session per ticket:
#   hive run PAY-42 PAY-43
#     └─ claude --output-format stream-json -p "/ship PAY-42"  → merge PR → capture cost
#     └─ claude --output-format stream-json -p "/ship PAY-43"  → merge PR → capture cost
#
#   Each ticket gets a fresh context window (no context overflow on large batches).
#   Auto-merge before the next ticket starts prevents branch conflicts.
#   Token/cost data comes from claude's JSON output, not LLM self-reporting.
#
# Recovery after token exhaustion:
#   Batch session is written to .hive/sessions/batch_TIMESTAMP.json after each ticket.
#   On restart, use --resume BATCH_ID to continue from the first incomplete ticket.
#
# Server setup (overnight run):
#   1. Set autonomy.level: autonomous in .hive/AGENTS.local.md
#   2. Set ticket_provider.ticket_transitions.auto_merge_pr: true
#   3. Configure notifications.webhook for failure alerts
#   4. Run:
#      nohup bash .hive/scripts/hive-run.sh PAY-42 PAY-43 \
#        > .hive/logs/run-$(date +%Y%m%d_%H%M%S).log 2>&1 &
#      echo "PID: $!"
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/require-python3.sh
source "$SCRIPT_DIR/lib/require-python3.sh"

# Detect project root:
#   - Inside a project's .hive/scripts/ → two levels up
#   - Otherwise → use CWD
if [[ "$SCRIPT_DIR" == *"/.hive/scripts" ]]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
    PROJECT_ROOT="$(pwd)"
fi

HIVE_DIR="$PROJECT_ROOT/.hive"
LOGS_DIR="$HIVE_DIR/logs"

# Factory root for version
FACTORY_ROOT="${HIVE_FACTORY_ROOT:-}"
if [[ -z "$FACTORY_ROOT" && -f "$HIVE_DIR/AGENTS.local.md" ]]; then
    FACTORY_ROOT="$(awk -F'"' '/hive_root:/ { print $2; exit }' "$HIVE_DIR/AGENTS.local.md" 2>/dev/null || echo "")"
fi
HIVE_VERSION="$(cat "$FACTORY_ROOT/VERSION" 2>/dev/null || echo "dev")"

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'

info()  { printf "  ${CYAN}→${NC} %s\n" "$1"; }
ok()    { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
warn()  { printf "  ${YELLOW}!${NC} %s\n" "$1"; }
err()   { printf "  ${RED}✗${NC} %s\n" "$1" >&2; }
hdr()   { printf "\n  ${BOLD}[%s/%s] %s${NC}\n" "$1" "$2" "$3"; }

# ── Parse arguments ───────────────────────────────────────────
TICKETS=()
DRY_RUN=false
FROM_PHASE=""
TICKET_FILE=""
LIST_MODE=false
SPRINT=""
RESUME_BATCH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)    DRY_RUN=true ;;
        --from)       FROM_PHASE="$2"; shift ;;
        --file)       TICKET_FILE="$2"; shift ;;
        --list)       LIST_MODE=true ;;
        --sprint)     SPRINT="$2"; shift ;;
        --resume)     RESUME_BATCH="$2"; shift ;;
        --*)          warn "Unknown flag: $1" ;;
        *)            TICKETS+=("$1") ;;
    esac
    shift
done

# ── Banner ────────────────────────────────────────────────────
echo ""
printf "${CYAN}${BOLD}HIVE v%s${NC}  ${DIM}Batch Runner${NC}\n" "$HIVE_VERSION"
echo ""

# ── List mode ─────────────────────────────────────────────────
if $LIST_MODE; then
    echo "  Batch sessions:"
    echo ""
    if ls "$HIVE_DIR/sessions/batch_"*.json >/dev/null 2>&1; then
        for f in "$HIVE_DIR/sessions/batch_"*.json; do
            python3 - "$f" <<'PYEOF'
import json, sys
f = sys.argv[1]
try:
    d = json.load(open(f))
    batch_id = d.get('batch_id', '?')
    started  = d.get('started_at', '?')[:19]
    tickets  = d.get('tickets', [])
    results  = d.get('results', {})
    done     = sum(1 for v in results.values() if v.get('status') == 'ok')
    failed   = sum(1 for v in results.values() if v.get('status') == 'failed')
    cost     = sum(v.get('cost_usd', 0) for v in results.values())
    pending  = len(tickets) - done - failed
    completed_at = d.get('completed_at', '')
    status = 'complete' if completed_at else f'{pending} pending'
    print(f"  {batch_id}  started {started}  {done}/{len(tickets)} done  "
          f"${cost:.4f}  [{status}]")
    if failed > 0:
        failed_list = [t for t in tickets if results.get(t, {}).get('status') == 'failed']
        print(f"    failed: {', '.join(failed_list)}")
    if pending > 0:
        pending_list = [t for t in tickets if t not in results or results[t].get('status') not in ('ok','failed')]
        print(f"    resume: hive run --resume {batch_id}")
except Exception as e:
    print(f"  {f}: unreadable ({e})")
PYEOF
        done
    else
        info "No batch sessions found"
    fi
    echo ""
    exit 0
fi

# ── Load tickets from file ────────────────────────────────────
if [[ -n "$TICKET_FILE" ]]; then
    [[ ! -f "$TICKET_FILE" ]] && { err "Ticket file not found: $TICKET_FILE"; exit 1; }
    while IFS= read -r line; do
        line="${line%%#*}"; line="${line// /}"
        [[ -n "$line" ]] && TICKETS+=("$line")
    done < "$TICKET_FILE"
fi

# ── Resume interrupted batch ──────────────────────────────────
if [[ -n "$RESUME_BATCH" ]]; then
    BATCH_FILE_RESUME="$HIVE_DIR/sessions/batch_${RESUME_BATCH}.json"
    [[ ! -f "$BATCH_FILE_RESUME" ]] && {
        err "Batch session not found: $RESUME_BATCH"
        echo "  Run 'hive run --list' to see available sessions"
        exit 1
    }
    INCOMPLETE=$(python3 - "$BATCH_FILE_RESUME" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
results = d.get('results', {})
incomplete = [t for t in d.get('tickets', [])
              if results.get(t, {}).get('status') not in ('ok', 'dry_run')]
print(' '.join(incomplete))
PYEOF
    )
    if [[ -z "$INCOMPLETE" ]]; then
        ok "Batch $RESUME_BATCH is already complete"
        exit 0
    fi
    read -ra TICKETS <<< "$INCOMPLETE"
    info "Resuming batch $RESUME_BATCH: ${#TICKETS[@]} tickets remaining"
    echo ""
fi

# ── Load sprint tickets ───────────────────────────────────────
if [[ -n "$SPRINT" && ${#TICKETS[@]} -eq 0 ]]; then
    if ! command -v claude &>/dev/null; then
        err "--sprint requires claude CLI"
        echo "  Alternative: hive run --file tickets.txt"
        exit 1
    fi
    info "Loading tickets from sprint: $SPRINT"
    # One lightweight call to get the ticket list via hive-tickets MCP
    SPRINT_JSON=$(claude --output-format json -p \
        "Using the hive-tickets MCP, get all actionable tickets (not done/closed/cancelled) in sprint \"${SPRINT}\". Reply with ONLY this JSON on a single line: {\"tickets\":[\"ID-1\",\"ID-2\"]}" \
        2>/dev/null || echo '{"is_error":true}')
    SPRINT_TICKETS=$(python3 - <<PYEOF
import json, re, sys
raw = """$SPRINT_JSON"""
for line in raw.splitlines():
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        # Direct format
        if 'tickets' in d:
            print(' '.join(d['tickets'])); sys.exit(0)
        # claude --output-format json wraps result
        if d.get('type') == 'result':
            text = d.get('result', '')
            m = re.search(r'\{[^}]*"tickets"[^}]*\}', text)
            if m:
                inner = json.loads(m.group())
                print(' '.join(inner.get('tickets', []))); sys.exit(0)
    except:
        pass
PYEOF
    )
    [[ -z "$SPRINT_TICKETS" ]] && {
        err "No actionable tickets found in sprint: $SPRINT"
        echo "  Try running /run --sprint \"$SPRINT\" directly in Claude Code for details."
        exit 1
    }
    read -ra TICKETS <<< "$SPRINT_TICKETS"
    ok "Loaded ${#TICKETS[@]} tickets from sprint '$SPRINT': ${TICKETS[*]}"
    echo ""
fi

# ── Validate ──────────────────────────────────────────────────
if [[ ${#TICKETS[@]} -eq 0 ]]; then
    err "No tickets specified."
    echo ""
    echo "  Usage:  hive run <ticket-id> [<ticket-id>...]"
    echo "  Sprint: hive run --sprint current"
    echo "  File:   hive run --file tickets.txt"
    echo "  List:   hive run --list"
    echo "  Resume: hive run --resume <batch-id>"
    echo ""
    exit 1
fi

if [[ ! -f "$HIVE_DIR/AGENTS.local.md" ]]; then
    err "Not in a HIVE project (.hive/AGENTS.local.md not found)"
    info "Run 'hive inject .' to add HIVE to this project"
    exit 1
fi

if [[ ${#TICKETS[@]} -gt 20 ]]; then
    err "Maximum batch size is 20 tickets (got ${#TICKETS[@]})"
    info "Split into multiple runs to stay within budget"
    exit 1
fi

# ── Check config ──────────────────────────────────────────────
AUTONOMY=$(awk -F'"' '/level:/ { print $2; exit }' "$HIVE_DIR/AGENTS.local.md" 2>/dev/null)
AUTONOMY="${AUTONOMY:-supervised}"
AUTO_MERGE=$(awk '/auto_merge_pr:/ { print $2; exit }' "$HIVE_DIR/AGENTS.local.md" 2>/dev/null)
AUTO_MERGE="${AUTO_MERGE:-false}"

if [[ "$AUTONOMY" != "autonomous" ]]; then
    warn "autonomy.level is '${AUTONOMY}' — batch runs require autonomous mode"
    warn "Set autonomy.level: autonomous in .hive/AGENTS.local.md"
    echo ""
fi

if [[ "$AUTO_MERGE" != "true" ]]; then
    warn "auto_merge_pr is not enabled — PRs won't merge between tickets"
    warn "Without auto-merge, concurrent branches may conflict"
    warn "Set ticket_provider.ticket_transitions.auto_merge_pr: true"
    echo ""
fi

# ── Detect AI CLI ─────────────────────────────────────────────
AI_CMD=""
AI_TOOL=""
if command -v claude &>/dev/null; then AI_CMD="claude"; AI_TOOL="Claude Code"
elif command -v gemini &>/dev/null; then AI_CMD="gemini"; AI_TOOL="Gemini CLI"
fi

if [[ -z "$AI_CMD" ]]; then
    warn "No AI CLI found. Install Claude Code or Gemini CLI for automated execution."
    echo ""
    BATCH_PENDING="$HIVE_DIR/sessions/batch_pending_$(date +%Y%m%d_%H%M%S).txt"
    { echo "# HIVE Batch — $(date)"; echo "# Run each command in your AI tool:"; echo ""
      for T in "${TICKETS[@]}"; do echo "/ship $T"; done
    } > "$BATCH_PENDING"
    ok "Manual batch spec saved: $BATCH_PENDING"
    exit 0
fi

# ── Set up batch state ────────────────────────────────────────
mkdir -p "$LOGS_DIR" "$HIVE_DIR/sessions"
BATCH_ID=$(date +%Y%m%d_%H%M%S)
BATCH_LOG="$LOGS_DIR/batch_${BATCH_ID}.log"
BATCH_FILE="$HIVE_DIR/sessions/batch_${BATCH_ID}.json"
EVENTS_FILE="$HIVE_DIR/events.jsonl"
BATCH_START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BATCH_START_S=$(date +%s)

# Init batch session file
python3 - "$BATCH_START_TS" "$BATCH_ID" "${TICKETS[@]}" <<PYEOF > "$BATCH_FILE"
import json, sys
args = sys.argv[1:]
started_at, batch_id, *tickets = args
print(json.dumps({
    "started_at":  started_at,
    "batch_id":    batch_id,
    "tickets":     tickets,
    "dry_run":     $([ "$DRY_RUN" = "true" ] && echo "True" || echo "False"),
    "results":     {},
}, indent=2))
PYEOF

# ── Print header ──────────────────────────────────────────────
ok "Using $AI_TOOL ($AI_CMD)"
printf "  Tickets : %s\n" "${TICKETS[*]}"
printf "  Mode    : %s\n" "$( $DRY_RUN && echo 'dry-run (no files written)' || echo 'autonomous')"
printf "  Session : %s\n" "$BATCH_ID"
printf "  Log     : %s\n" "$BATCH_LOG"
echo ""
info "To monitor: tail -f $BATCH_LOG | python3 -c \
\"import sys,json; [print(json.loads(l).get('message',{}).get('content',[{}])[0].get('text','')) \
for l in sys.stdin if l.strip() and json.loads(l).get('type')=='assistant']\""
echo ""

# ── Send start notification ───────────────────────────────────
_notify() {
    if [[ -f "$HIVE_DIR/scripts/hive-notify.sh" ]]; then
        bash "$HIVE_DIR/scripts/hive-notify.sh" "$@" 2>/dev/null || true
    fi
}
_notify --event batch_start \
    --message "Batch started: ${#TICKETS[@]} tickets — ${TICKETS[*]}" \
    --status info

# ── Per-ticket helper: write batch session result ─────────────
_write_ticket_result() {
    local ticket="$1" status="$2" started_at="$3" completed_at="$4"
    local duration_s="$5" cost_usd="$6" input_tok="${7:-0}" output_tok="${8:-0}"
    python3 - "$BATCH_FILE" "$ticket" "$status" "$started_at" "$completed_at" \
              "$duration_s" "$cost_usd" "$input_tok" "$output_tok" <<'PYEOF'
import json, sys
batch_file, ticket, status, started, completed, dur_s, cost, in_tok, out_tok = sys.argv[1:]
d = json.load(open(batch_file))
d['results'][ticket] = {
    "status":        status,
    "started_at":    started,
    "completed_at":  completed,
    "duration_s":    int(dur_s),
    "cost_usd":      float(cost or 0),
    "input_tokens":  int(in_tok or 0),
    "output_tokens": int(out_tok or 0),
    "total_tokens":  int(in_tok or 0) + int(out_tok or 0),
}
open(batch_file, 'w').write(json.dumps(d, indent=2))
PYEOF
}

# ── Per-ticket helper: parse cost+tokens from stream-json log ─
# Outputs: cost_usd,duration_ms,is_error,input_tokens,output_tokens
_parse_cost() {
    local log_file="$1"
    python3 - "$log_file" <<'PYEOF'
import json, sys
cost = 0; dur = 0; is_err = False
input_tokens = 0; output_tokens = 0
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
            # Each assistant message may carry usage counters
            usage = d.get('message', {}).get('usage', {})
            input_tokens  += int(usage.get('input_tokens', 0) or 0)
            output_tokens += int(usage.get('output_tokens', 0) or 0)
            # Cache hits count as reads, not new input spend
            input_tokens  += int(usage.get('cache_read_input_tokens', 0) or 0)
    except:
        pass
total_tokens = input_tokens + output_tokens
print(f"{cost},{dur},{1 if is_err else 0},{input_tokens},{output_tokens},{total_tokens}")
PYEOF
}

# ── Process each ticket ───────────────────────────────────────
PASSED=0; FAILED=0; FAILED_TICKETS=()

for i in "${!TICKETS[@]}"; do
    TICKET="${TICKETS[$i]}"
    NUM=$((i + 1))
    TOTAL=${#TICKETS[@]}

    hdr "$NUM" "$TOTAL" "$TICKET"
    T_START_S=$(date +%s)
    T_START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if $DRY_RUN; then
        ok "DRY RUN — would execute: /ship $TICKET"
        T_END_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        _write_ticket_result "$TICKET" "dry_run" "$T_START_TS" "$T_END_TS" "0" "0" "0" "0"
        PASSED=$((PASSED + 1))
        continue
    fi

    SHIP_CMD="/ship $TICKET"
    [[ -n "$FROM_PHASE" ]] && SHIP_CMD="$SHIP_CMD --from $FROM_PHASE"

    info "Executing: $SHIP_CMD"
    TICKET_LOG=$(mktemp)
    EXIT_CODE=0

    if [[ "$AI_CMD" == "claude" ]]; then
        # stream-json: each event is one JSON line; cost is in the final "result" event
        claude --output-format stream-json -p "$SHIP_CMD" \
            > "$TICKET_LOG" 2>&1 || EXIT_CODE=$?
    else
        "$AI_CMD" -p "$SHIP_CMD" > "$TICKET_LOG" 2>&1 || EXIT_CODE=$?
    fi

    T_END_S=$(date +%s)
    T_END_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Append to batch log with ticket separator
    { echo ""; echo "=== TICKET $TICKET — $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="; } >> "$BATCH_LOG"
    cat "$TICKET_LOG" >> "$BATCH_LOG"

    # Parse cost/duration/tokens from stream-json log
    PARSE_OUT="0,0,0,0,0,0"
    [[ "$AI_CMD" == "claude" ]] && PARSE_OUT=$(_parse_cost "$TICKET_LOG" 2>/dev/null || echo "0,0,0,0,0,0")
    COST_USD=$(echo "$PARSE_OUT"    | cut -d',' -f1)
    DURATION_MS=$(echo "$PARSE_OUT" | cut -d',' -f2)
    IS_ERR=$(echo "$PARSE_OUT"      | cut -d',' -f3)
    INPUT_TOK=$(echo "$PARSE_OUT"   | cut -d',' -f4)
    OUTPUT_TOK=$(echo "$PARSE_OUT"  | cut -d',' -f5)
    TOTAL_TOK=$(echo "$PARSE_OUT"   | cut -d',' -f6)
    rm -f "$TICKET_LOG"

    # Use claude-reported duration if available, else wall clock
    if [[ "$DURATION_MS" -gt 0 ]]; then
        DURATION_S=$((DURATION_MS / 1000))
    else
        DURATION_S=$((T_END_S - T_START_S))
    fi

    # Treat claude-level error the same as non-zero exit
    [[ "$IS_ERR" == "1" ]] && EXIT_CODE=1

    # Update state and events.jsonl
    if [[ $EXIT_CODE -eq 0 ]]; then
        PASSED=$((PASSED + 1))
        TOK_LABEL="$( [[ "${TOTAL_TOK:-0}" -gt 0 ]] && printf "  %s tok" "$TOTAL_TOK" || echo "")"
        ok "$TICKET — done in ${DURATION_S}s  (\$${COST_USD}${TOK_LABEL})"
        _write_ticket_result "$TICKET" "ok" "$T_START_TS" "$T_END_TS" \
            "$DURATION_S" "$COST_USD" "${INPUT_TOK:-0}" "${OUTPUT_TOK:-0}"
        printf '{"ts":"%s","cmd":"run","ticket":"%s","event":"ticket_complete","status":"ok","duration_s":%d,"cost_usd":%s,"input_tokens":%s,"output_tokens":%s,"tokens":%s,"started_at":"%s"}\n' \
            "$T_END_TS" "$TICKET" "$DURATION_S" "${COST_USD:-0}" \
            "${INPUT_TOK:-0}" "${OUTPUT_TOK:-0}" "${TOTAL_TOK:-0}" "$T_START_TS" \
            >> "$EVENTS_FILE" 2>/dev/null || true
    else
        FAILED=$((FAILED + 1))
        FAILED_TICKETS+=("$TICKET")
        err "$TICKET — failed (exit $EXIT_CODE) in ${DURATION_S}s"
        _write_ticket_result "$TICKET" "failed" "$T_START_TS" "$T_END_TS" \
            "$DURATION_S" "$COST_USD" "${INPUT_TOK:-0}" "${OUTPUT_TOK:-0}"
        printf '{"ts":"%s","cmd":"run","ticket":"%s","event":"ticket_complete","status":"failed","duration_s":%d,"cost_usd":%s,"input_tokens":%s,"output_tokens":%s,"tokens":%s,"started_at":"%s"}\n' \
            "$T_END_TS" "$TICKET" "$DURATION_S" "${COST_USD:-0}" \
            "${INPUT_TOK:-0}" "${OUTPUT_TOK:-0}" "${TOTAL_TOK:-0}" "$T_START_TS" \
            >> "$EVENTS_FILE" 2>/dev/null || true
        _notify --event circuit_breaker --ticket "$TICKET" \
            --message "$TICKET failed. Resume: hive run --resume $BATCH_ID" \
            --status failure
    fi
    echo ""
done

# ── Finalize batch session ────────────────────────────────────
BATCH_END_S=$(date +%s)
BATCH_END_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BATCH_DURATION=$((BATCH_END_S - BATCH_START_S))
BATCH_MIN=$((BATCH_DURATION / 60))
BATCH_SEC=$((BATCH_DURATION % 60))

TOTAL_COST=$(python3 - "$BATCH_FILE" 2>/dev/null <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
print(sum(v.get('cost_usd', 0) for v in d.get('results', {}).values()))
PYEOF
) || TOTAL_COST="0"

python3 - "$BATCH_FILE" "$BATCH_END_TS" "$BATCH_DURATION" "$TOTAL_COST" "$PASSED" "$FAILED" 2>/dev/null <<'PYEOF' || true
import json, sys
batch_file, completed_at, dur_s, cost, passed, failed = sys.argv[1:]
d = json.load(open(batch_file))
d['completed_at']    = completed_at
d['duration_s']      = int(dur_s)
d['total_cost_usd']  = float(cost or 0)
d['passed']          = int(passed)
d['failed']          = int(failed)
open(batch_file, 'w').write(json.dumps(d, indent=2))
PYEOF

# ── Summary table ─────────────────────────────────────────────
echo "┌─────────────────────────────────────────────────────────────────┐"
printf "│  Batch complete — %dm%ds  ·  \$%.4f total%s│\n" \
    "$BATCH_MIN" "$BATCH_SEC" "$TOTAL_COST" "                    " 2>/dev/null || \
printf "│  Batch complete — %dm%ds%s│\n" "$BATCH_MIN" "$BATCH_SEC" "                               "
echo "├───────────────────┬──────────┬─────────────────────────────────┤"
printf "│ %-17s │ %-8s │ %-31s │\n" "Ticket" "Result" "Duration · Cost"
echo "├───────────────────┼──────────┼─────────────────────────────────┤"

python3 - "$BATCH_FILE" 2>/dev/null <<'PYEOF' || true
import json, sys
d = json.load(open(sys.argv[1]))
results = d.get('results', {})
for ticket in d.get('tickets', []):
    r = results.get(ticket, {})
    status_icon = '✓' if r.get('status') == 'ok' else ('~' if r.get('status') == 'dry_run' else '✗')
    dur  = r.get('duration_s', 0)
    cost = r.get('cost_usd', 0)
    detail = f"{dur}s  ${cost:.4f}"
    print(f"│ {ticket:<17} │ {status_icon:<8} │ {detail:<31} │")
PYEOF

echo "└───────────────────┴──────────┴─────────────────────────────────┘"
echo ""
printf "  Passed: ${GREEN}%d/${TOTAL}${NC}   Failed: " "$PASSED" 2>/dev/null || printf "  Passed: %d/%d   Failed: " "$PASSED" "${#TICKETS[@]}"
[[ $FAILED -gt 0 ]] && printf "${RED}%d${NC}" "$FAILED" 2>/dev/null || printf "%d" "$FAILED"
printf "/%d   Cost: \$%s   Session: %s\n\n" "${#TICKETS[@]}" "$TOTAL_COST" "$BATCH_ID"

if [[ $FAILED -gt 0 ]]; then
    warn "Failed: ${FAILED_TICKETS[*]}"
    info "Resume:  hive run --resume $BATCH_ID"
    info "Details: hive analytics --ticket ${FAILED_TICKETS[0]}"
    echo ""
fi

# ── Sprint lifecycle ──────────────────────────────────────────
if [[ -n "$SPRINT" ]]; then
    AUTO_CLOSE=$(awk '/auto_close_on_batch_complete:/ { print $2; exit }' \
        "$HIVE_DIR/AGENTS.local.md" 2>/dev/null)
    if [[ "$AUTO_CLOSE" == "true" && $FAILED -eq 0 ]]; then
        info "Sprint lifecycle: auto_close_on_batch_complete triggered"
        TAG_ON_CLOSE=$(awk '/tag_on_close:/ { print $2; exit }' "$HIVE_DIR/AGENTS.local.md" 2>/dev/null)
        if [[ "$TAG_ON_CLOSE" == "true" ]]; then
            SPRINT_TAG="sprint-$(echo "$SPRINT" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')"
            git -C "$PROJECT_ROOT" tag -a "$SPRINT_TAG" \
                -m "Sprint complete — $PASSED/${#TICKETS[@]} tickets  (\$${TOTAL_COST})" 2>/dev/null && \
                git -C "$PROJECT_ROOT" push origin "$SPRINT_TAG" 2>/dev/null && \
                ok "Tagged: $SPRINT_TAG" || warn "Could not create sprint tag"
        fi
        _notify --event sprint_close \
            --message "Sprint '$SPRINT' closed. $PASSED/${#TICKETS[@]} tickets done. \$${TOTAL_COST}." \
            --status success
    elif [[ -n "$AUTO_CLOSE" && "$AUTO_CLOSE" != "true" ]]; then
        info "Sprint not auto-closed (auto_close_on_batch_complete: false)"
        info "Close manually: /sprint-close"
    fi
fi

# ── Completion notification ───────────────────────────────────
NOTIFY_STATUS="$( [[ $FAILED -eq 0 ]] && echo success || echo warning)"
_notify --event batch_complete \
    --message "Batch done: $PASSED/${#TICKETS[@]} tickets  \$${TOTAL_COST}  $( [[ $FAILED -gt 0 ]] && echo "— $FAILED failed. Resume: hive run --resume $BATCH_ID" || echo '— all passed')" \
    --status "$NOTIFY_STATUS"

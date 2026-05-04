#!/usr/bin/env bash
# ============================================================
# hive-approve.sh — File-based approval for balanced/supervised mode
#
# Writes an approval response that a paused agent polls for.
# Agents write an approval request to .hive/sessions/<ticket>_approval_request.json
# and pause. This script writes the response and unblocks them.
#
# Usage:
#   hive approve <ticket-id> yes             # approve and continue
#   hive approve <ticket-id> no              # reject — agent aborts pipeline
#   hive approve <ticket-id> skip            # skip this step, continue from next
#   hive approve <ticket-id> yes --note "..." # approve with a note
#   hive approve --list                       # show pending approval requests
#   hive approve --clear <ticket-id>          # clear a stale request
#
# The agent reads:
#   .hive/sessions/<ticket>_approval_response.json
#
# Format:
#   {"decision": "yes|no|skip", "note": "...", "timestamp": "..."}
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(pwd)"

# If run from inside .hive/scripts/, project root is two levels up
if [[ "$SCRIPT_DIR" == */\.hive/scripts ]]; then
    PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

HIVE_DIR="$PROJECT_DIR/.hive"
SESSIONS_DIR="$HIVE_DIR/sessions"

# Try to find factory root for version
FACTORY_ROOT="${HIVE_FACTORY_ROOT:-}"
if [[ -z "$FACTORY_ROOT" && -f "$HIVE_DIR/AGENTS.local.md" ]]; then
    FACTORY_ROOT="$(awk -F'"' '/hive_root:/ { print $2; exit }' "$HIVE_DIR/AGENTS.local.md" 2>/dev/null || echo "")"
fi
HIVE_VERSION="$(cat "${FACTORY_ROOT}/VERSION" 2>/dev/null || echo "dev")"

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'

info()  { printf "  ${CYAN}→${NC} %s\n" "$1"; }
ok()    { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
warn()  { printf "  ${YELLOW}!${NC} %s\n" "$1"; }
err()   { printf "  ${RED}✗${NC} %s\n" "$1" >&2; }

# ── Banner ────────────────────────────────────────────────────
echo ""
printf "${CYAN}${BOLD}HIVE v%s${NC}  ${DIM}Approval Manager${NC}\n" "$HIVE_VERSION"
echo ""

# ── Validate we are in a HIVE project ─────────────────────────
if [[ ! -f "$HIVE_DIR/AGENTS.local.md" ]]; then
    err "Not in a HIVE project (.hive/AGENTS.local.md not found)"
    info "Run from the project root directory"
    exit 1
fi

mkdir -p "$SESSIONS_DIR"

# ── Parse arguments ───────────────────────────────────────────
TICKET=""
DECISION=""
NOTE=""
LIST_MODE=false
CLEAR_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)          LIST_MODE=true ;;
        --clear)         CLEAR_MODE=true; TICKET="${2:-}"; shift ;;
        --note)          NOTE="${2:-}"; shift ;;
        yes|no|skip)     DECISION="$1" ;;
        *)               [[ -z "$TICKET" ]] && TICKET="$1" || true ;;
    esac
    shift
done

# ── List mode — show all pending requests ─────────────────────
if $LIST_MODE; then
    FOUND=false
    shopt -s nullglob
    for req_file in "$SESSIONS_DIR/"*_approval_request.json; do
        [[ -f "$req_file" ]] || continue
        FOUND=true
        ticket_id=$(basename "$req_file" _approval_request.json)
        resp_file="${req_file/_request.json/_response.json}"

        if [[ -f "$resp_file" ]]; then
            decision=$(python3 -c "import json; d=json.load(open('$resp_file')); print(d.get('decision','?'))" 2>/dev/null || echo "?")
            printf "  ${DIM}%-20s${NC} ${GREEN}responded: %s${NC}\n" "$ticket_id" "$decision"
        else
            # Parse request details
            phase=$(python3 -c "import json; d=json.load(open('$req_file')); print(d.get('phase','?'))" 2>/dev/null || echo "?")
            msg=$(python3 -c "import json; d=json.load(open('$req_file')); print(d.get('message','Waiting for approval'))" 2>/dev/null || echo "Waiting")
            ts=$(python3 -c "import json; d=json.load(open('$req_file')); print(d.get('requested_at','?'))" 2>/dev/null || echo "?")
            printf "  ${YELLOW}${BOLD}%-20s${NC} ${YELLOW}PENDING${NC}  phase: %s  at: %s\n" "$ticket_id" "$phase" "$ts"
            printf "    ${DIM}%s${NC}\n" "$msg"
            printf "    ${DIM}Run: hive approve %s [yes|no|skip]${NC}\n" "$ticket_id"
        fi
    done

    if ! $FOUND; then
        info "No approval requests found"
    fi
    echo ""
    exit 0
fi

# ── Clear mode — remove stale request ─────────────────────────
if $CLEAR_MODE; then
    if [[ -z "$TICKET" ]]; then
        err "Specify a ticket ID: hive approve --clear <ticket-id>"
        exit 1
    fi
    REQ_FILE="$SESSIONS_DIR/${TICKET}_approval_request.json"
    RESP_FILE="$SESSIONS_DIR/${TICKET}_approval_response.json"
    removed=false
    [[ -f "$REQ_FILE" ]]  && { rm "$REQ_FILE";  ok "Removed request: ${TICKET}_approval_request.json"; removed=true; }
    [[ -f "$RESP_FILE" ]] && { rm "$RESP_FILE"; ok "Removed response: ${TICKET}_approval_response.json"; removed=true; }
    $removed || warn "No approval files found for ticket: $TICKET"
    echo ""
    exit 0
fi

# ── Validate required args ─────────────────────────────────────
if [[ -z "$TICKET" ]]; then
    err "Ticket ID required."
    echo ""
    echo "  Usage:  hive approve <ticket-id> [yes|no|skip]"
    echo "  List:   hive approve --list"
    echo ""
    exit 1
fi

if [[ -z "$DECISION" ]]; then
    # Interactive — show request details then prompt
    REQ_FILE="$SESSIONS_DIR/${TICKET}_approval_request.json"
    if [[ -f "$REQ_FILE" ]]; then
        echo ""
        printf "  ${BOLD}Pending request for ${CYAN}%s${NC}${BOLD}:${NC}\n" "$TICKET"
        phase=$(python3 -c "import json; d=json.load(open('$REQ_FILE')); print(d.get('phase','?'))" 2>/dev/null || echo "?")
        msg=$(python3 -c "import json; d=json.load(open('$REQ_FILE')); print(d.get('message','Waiting for your approval'))" 2>/dev/null || echo "")
        context=$(python3 -c "import json; d=json.load(open('$REQ_FILE')); print(d.get('context',''))" 2>/dev/null || echo "")
        printf "  Phase:   %s\n" "$phase"
        printf "  Message: %s\n" "$msg"
        [[ -n "$context" ]] && printf "  Context:\n    %s\n" "$context"
        echo ""
    else
        warn "No pending request found for $TICKET"
        info "The agent may not have reached a checkpoint yet"
        echo ""
        printf "  ${CYAN}?${NC} Respond anyway? [y/N]: "
        read -r EARLY_REPLY
        [[ "$EARLY_REPLY" != "y" && "$EARLY_REPLY" != "Y" ]] && { echo "  Aborted."; echo ""; exit 0; }
    fi

    echo ""
    printf "  ${CYAN}?${NC} Decision for ${BOLD}%s${NC}:\n" "$TICKET"
    printf "      ${GREEN}1)${NC} yes  — proceed as planned\n"
    printf "      ${RED}2)${NC}   no  — abort this ticket\n"
    printf "      ${YELLOW}3)${NC} skip — skip this step and continue\n"
    printf "  Enter [1/yes|2/no|3/skip]: "
    read -r D_INPUT
    D_INPUT_LOWER=$(echo "$D_INPUT" | tr '[:upper:]' '[:lower:]')
    case "$D_INPUT_LOWER" in
        1|yes)  DECISION="yes"  ;;
        2|no)   DECISION="no"   ;;
        3|skip) DECISION="skip" ;;
        *)      err "Invalid choice. Use yes, no, or skip."; exit 1 ;;
    esac

    printf "  ${CYAN}?${NC} Optional note for the agent (leave empty to skip): "
    read -r NOTE
fi

# ── Write response ─────────────────────────────────────────────
RESP_FILE="$SESSIONS_DIR/${TICKET}_approval_response.json"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Build JSON without external deps (python3 or plain bash)
if command -v python3 &>/dev/null; then
    python3 - <<PYEOF
import json, sys
data = {
    "ticket": "${TICKET}",
    "decision": "${DECISION}",
    "note": "${NOTE}",
    "timestamp": "${TIMESTAMP}"
}
with open("${RESP_FILE}", "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
else
    # Plain bash fallback — safe because values are controlled
    cat > "$RESP_FILE" << JSON
{
  "ticket": "${TICKET}",
  "decision": "${DECISION}",
  "note": "${NOTE}",
  "timestamp": "${TIMESTAMP}"
}
JSON
fi

echo ""
case "$DECISION" in
    yes)
        ok "Approved: $TICKET"
        info "The agent will continue from the next step when you switch back to your AI tool"
        ;;
    no)
        ok "Rejected: $TICKET"
        info "The agent will abort the pipeline for this ticket"
        ;;
    skip)
        ok "Skip recorded: $TICKET"
        info "The agent will skip the current step and continue"
        ;;
esac

[[ -n "$NOTE" ]] && info "Note to agent: $NOTE"
echo ""
printf "  ${DIM}Response written: %s${NC}\n" "$RESP_FILE"
echo ""

# ── Log event ─────────────────────────────────────────────────
EVENTS_FILE="$HIVE_DIR/events.jsonl"
if [[ -f "$EVENTS_FILE" ]] && command -v python3 &>/dev/null; then
    python3 - <<PYEOF
import json, sys
event = {
    "event": "approval_response",
    "ticket": "${TICKET}",
    "decision": "${DECISION}",
    "timestamp": "${TIMESTAMP}"
}
with open("${EVENTS_FILE}", "a") as f:
    f.write(json.dumps(event) + "\n")
PYEOF
fi

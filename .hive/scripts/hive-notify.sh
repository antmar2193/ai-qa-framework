#!/usr/bin/env bash
# ============================================================
# hive-notify.sh — Team webhook notifications from HIVE events
#
# Sends a JSON payload to a configured webhook URL when a
# significant HIVE event occurs (delivery, circuit breaker,
# sprint close, etc.).
#
# Configuration in AGENTS.local.md:
#   notifications:
#     webhook: "https://hooks.slack.com/services/..."
#     on_delivery: true
#     on_circuit_breaker: true
#     on_sprint_close: true
#
# Or via environment variable (overrides config):
#   export HIVE_WEBHOOK_URL="https://..."
#
# Usage:
#   bash .hive/scripts/hive-notify.sh \
#     --event delivery \
#     --ticket PROJ-42 \
#     --message "Delivery complete — client repo updated" \
#     [--status success|failure]
# ============================================================

set -euo pipefail

# shellcheck source=lib/require-python3.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/require-python3.sh"

HIVE_CONFIG="${HIVE_CONFIG_PATH:-.hive/AGENTS.local.md}"

EVENT=""
TICKET=""
MESSAGE=""
STATUS="success"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --event)   EVENT="$2";   shift 2 ;;
        --ticket)  TICKET="$2";  shift 2 ;;
        --message) MESSAGE="$2"; shift 2 ;;
        --status)  STATUS="$2";  shift 2 ;;
        *) shift ;;
    esac
done

# ── Resolve webhook URL ───────────────────────────────────────
WEBHOOK_URL="${HIVE_WEBHOOK_URL:-}"

if [[ -z "$WEBHOOK_URL" && -f "$HIVE_CONFIG" ]]; then
    WEBHOOK_URL=$(grep -oE 'webhook:\s*"[^"]+"' "$HIVE_CONFIG" 2>/dev/null \
        | grep -oE '"[^"]+"' | tr -d '"' | head -1 || echo "")
fi

if [[ -z "$WEBHOOK_URL" ]]; then
    # No webhook configured — exit silently (notifications are optional)
    exit 0
fi

# ── Check if this event type is enabled ──────────────────────
if [[ -f "$HIVE_CONFIG" && -n "$EVENT" ]]; then
    event_key="on_${EVENT//-/_}"
    setting=$(grep -oE "${event_key}:\s*(true|false)" "$HIVE_CONFIG" 2>/dev/null \
        | grep -oE '(true|false)' | head -1 || echo "true")
    if [[ "$setting" == "false" ]]; then
        exit 0
    fi
fi

# ── Build payload ─────────────────────────────────────────────
PROJECT_NAME=""
if [[ -f "$HIVE_CONFIG" ]]; then
    PROJECT_NAME=$(grep -oE 'name:\s*"[^"]+"' "$HIVE_CONFIG" 2>/dev/null \
        | grep -oE '"[^"]+"' | tr -d '"' | head -1 || echo "")
fi

ICON="ok"
[[ "$STATUS" == "success" ]] && ICON="✅"
[[ "$STATUS" == "failure" ]] && ICON="❌"
[[ "$STATUS" == "warning" ]] && ICON="⚠️"

UNIX_TS=$(date +%s 2>/dev/null || echo '0')

# Escape strings for JSON
json_escape() {
    printf '%s' "$1" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))'
}

EVENT_JSON=$(json_escape "$EVENT")
TICKET_JSON=$(json_escape "$TICKET")
MESSAGE_JSON=$(json_escape "$MESSAGE")
PROJECT_JSON=$(json_escape "${PROJECT_NAME:-unknown}")

PAYLOAD=$(cat <<PAYLOAD
{
  "text": "${ICON} ${MESSAGE_JSON}",
  "attachments": [
    {
      "color": "$([ "$STATUS" == "success" ] && echo "good" || echo "danger")",
      "fields": [
        {"title": "Project", "value": ${PROJECT_JSON}, "short": true},
        {"title": "Event",   "value": ${EVENT_JSON},   "short": true},
        {"title": "Ticket",  "value": ${TICKET_JSON},  "short": true},
        {"title": "Status",  "value": "${STATUS}",     "short": true}
      ],
      "footer": "HIVE",
      "ts": "${UNIX_TS}"
    }
  ]
}
PAYLOAD
)

# ── Send notification ─────────────────────────────────────────
# Silent on failure — notifications must never break the pipeline
curl -sf \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$WEBHOOK_URL" \
    --max-time 5 \
    > /dev/null 2>&1 || true

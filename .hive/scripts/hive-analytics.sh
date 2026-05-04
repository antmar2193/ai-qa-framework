#!/usr/bin/env bash
# ============================================================
# hive-analytics.sh — Token, cost & duration analytics
#
# Reads .hive/events.jsonl and produces:
#   - Cost (USD) per ticket and per sprint
#   - Duration per ticket and per pipeline phase
#   - Token counts (when populated by agents)
#   - Recent failures
#
# Cost data is written by hive-run.sh from the AI CLI's JSON output
# (claude --output-format stream-json reports cost_usd per session).
# Duration data is written by orchestrator.md per stage.
#
# Usage (from the HIVE project root):
#   bash .hive/scripts/hive-analytics.sh
#   bash .hive/scripts/hive-analytics.sh --ticket PROJ-42
#   bash .hive/scripts/hive-analytics.sh --sprint 3
#   bash .hive/scripts/hive-analytics.sh --json         # raw JSON
# ============================================================

set -euo pipefail

EVENTS_FILE=".hive/events.jsonl"
FILTER_TICKET=""
FILTER_SPRINT=""
OUTPUT_JSON=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ticket) FILTER_TICKET="$2"; shift 2 ;;
        --sprint) FILTER_SPRINT="$2"; shift 2 ;;
        --json)   OUTPUT_JSON=true; shift ;;
        *) shift ;;
    esac
done

if [[ ! -f "$EVENTS_FILE" ]]; then
    echo "No events.jsonl found at $EVENTS_FILE"
    echo "Events are written in autonomous mode — run /ship with autonomy.level: autonomous"
    echo "Cost data comes from: hive run (which uses --output-format stream-json per ticket)"
    exit 0
fi

if ! command -v python3 &>/dev/null; then
    echo "python3 required for analytics"
    exit 1
fi

python3 - "$EVENTS_FILE" "$FILTER_TICKET" "$FILTER_SPRINT" "$OUTPUT_JSON" <<'PYEOF'
import sys, json
from collections import defaultdict
from datetime import datetime

events_file   = sys.argv[1]
filter_ticket = sys.argv[2]
filter_sprint = sys.argv[3]
output_json   = sys.argv[4] == "true"

events = []
with open(events_file, errors='replace') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass

# Apply filters
if filter_ticket:
    events = [e for e in events if e.get("ticket") == filter_ticket]
if filter_sprint:
    events = [e for e in events if str(e.get("sprint", "")) == filter_sprint]

if not events:
    msg = f"No events found"
    if filter_ticket:
        msg += f" for ticket {filter_ticket}"
    elif filter_sprint:
        msg += f" for sprint {filter_sprint}"
    print(msg + ".")
    print("Events are only written in autonomous mode.")
    sys.exit(0)

# ── Aggregate ─────────────────────────────────────────────────
tokens_by_ticket   = defaultdict(int)
tokens_by_stage    = defaultdict(int)
tokens_by_cmd      = defaultdict(int)
tokens_by_sprint   = defaultdict(int)
cost_by_ticket     = defaultdict(float)
cost_by_sprint     = defaultdict(float)
duration_by_ticket = defaultdict(int)
duration_by_stage  = defaultdict(int)
ticket_phases      = defaultdict(set)
errors             = []
total_tokens       = 0
total_cost         = 0.0
total_duration_s   = 0

for e in events:
    tokens    = int(e.get("tokens", 0))
    cost      = float(e.get("cost_usd", 0) or 0)
    duration  = int(e.get("duration_s", 0) or 0)
    ticket    = e.get("ticket", "unknown")
    stage     = e.get("stage", e.get("event", "unknown"))
    cmd       = e.get("cmd", "unknown")
    sprint    = str(e.get("sprint", "?"))

    tokens_by_ticket[ticket]    += tokens
    tokens_by_stage[stage]      += tokens
    tokens_by_cmd[cmd]          += tokens
    tokens_by_sprint[sprint]    += tokens
    cost_by_ticket[ticket]      += cost
    cost_by_sprint[sprint]      += cost
    duration_by_ticket[ticket]  += duration
    duration_by_stage[stage]    += duration
    ticket_phases[ticket].add(stage)
    total_tokens                 += tokens
    total_cost                   += cost
    total_duration_s             += duration

    if e.get("status") == "failed" or e.get("event") == "circuit_breaker":
        errors.append(e)

# hive-run.sh writes one "ticket_complete" event per ticket with real data from claude JSON output.
# Use these authoritative values; fall back to accumulated totals for older events without them.
cost_by_ticket_clean  = defaultdict(float)
dur_by_ticket_clean   = defaultdict(int)
intok_by_ticket       = defaultdict(int)
outtok_by_ticket      = defaultdict(int)

for e in events:
    if e.get("event") == "ticket_complete" and e.get("cmd") == "run":
        ticket = e.get("ticket", "unknown")
        cost_by_ticket_clean[ticket] = float(e.get("cost_usd", 0) or 0)
        dur_by_ticket_clean[ticket]  = int(e.get("duration_s", 0) or 0)
        intok_by_ticket[ticket]      = int(e.get("input_tokens", 0) or 0)
        outtok_by_ticket[ticket]     = int(e.get("output_tokens", 0) or 0)

if not cost_by_ticket_clean:
    cost_by_ticket_clean = cost_by_ticket
if not dur_by_ticket_clean:
    dur_by_ticket_clean = duration_by_ticket
total_cost_clean = sum(cost_by_ticket_clean.values()) or total_cost

if output_json:
    print(json.dumps({
        "total_tokens":     total_tokens,
        "total_cost_usd":   total_cost_clean,
        "total_duration_s": sum(dur_by_ticket_clean.values()),
        "by_ticket": {
            t: {
                "cost_usd":      cost_by_ticket_clean.get(t, 0),
                "duration_s":    dur_by_ticket_clean.get(t, 0),
                "input_tokens":  intok_by_ticket.get(t, 0),
                "output_tokens": outtok_by_ticket.get(t, 0),
                "total_tokens":  intok_by_ticket.get(t, 0) + outtok_by_ticket.get(t, 0),
                "phases":        len(ticket_phases.get(t, set())),
            }
            for t in sorted(cost_by_ticket_clean, key=lambda x: -cost_by_ticket_clean[x])
        },
        "by_stage":    dict(sorted(tokens_by_stage.items(), key=lambda x: -x[1])),
        "by_command":  dict(sorted(tokens_by_cmd.items(), key=lambda x: -x[1])),
        "by_sprint":   {s: {"tokens": tokens_by_sprint[s], "cost_usd": cost_by_sprint[s]}
                        for s in sorted(tokens_by_sprint)},
        "error_count": len(errors),
    }, indent=2))
    sys.exit(0)

# ── Pretty output ─────────────────────────────────────────────
BOLD = "\033[1m"; GREEN = "\033[0;32m"; CYAN = "\033[0;36m"
YELLOW = "\033[1;33m"; RED = "\033[0;31m"; GRAY = "\033[2;37m"; NC = "\033[0m"

def fmt_duration(s):
    s = int(s or 0)
    if s < 60:   return f"{s}s"
    if s < 3600: return f"{s//60}m{s%60:02d}s"
    return f"{s//3600}h{(s%3600)//60}m"

print(f"\n{BOLD}HIVE Analytics{NC}")
n_tickets = len(set(e.get('ticket') for e in events if e.get('ticket')))
print(f"  Events: {len(events)}  |  Tickets: {n_tickets}  |  "
      f"Total cost: {BOLD}${total_cost_clean:.4f}{NC}  |  "
      f"Total time: {BOLD}{fmt_duration(sum(dur_by_ticket_clean.values()))}{NC}\n")

# ── By ticket ────────────────────────────────────────────────
all_tickets = sorted(
    set(list(cost_by_ticket_clean.keys()) + list(tokens_by_ticket.keys())),
    key=lambda t: -cost_by_ticket_clean.get(t, 0)
)
if all_tickets:
    # Determine if we have per-ticket token data (from stream-json capture)
    has_tok_data = any(intok_by_ticket.get(t, 0) + outtok_by_ticket.get(t, 0) > 0 for t in all_tickets)
    max_cost = max((cost_by_ticket_clean[t] for t in all_tickets), default=1) or 1
    print(f"{CYAN}By ticket:{NC}")
    if has_tok_data:
        print(f"  {'Ticket':<18}  {'Cost':>8}  {'Duration':>9}  {'In tok':>9}  {'Out tok':>9}  {'Total':>9}")
        print(f"  {'-'*18}  {'-'*8}  {'-'*9}  {'-'*9}  {'-'*9}  {'-'*9}")
    else:
        print(f"  {'Ticket':<18}  {'Cost':>8}  {'Duration':>9}  ")
        print(f"  {'-'*18}  {'-'*8}  {'-'*9}")
    for t in all_tickets:
        cost   = cost_by_ticket_clean.get(t, 0)
        dur    = dur_by_ticket_clean.get(t, 0)
        in_t   = intok_by_ticket.get(t, 0)
        out_t  = outtok_by_ticket.get(t, 0)
        tot_t  = in_t + out_t
        bar    = "█" * min(int(cost / max_cost * 15), 15) if max_cost > 0 else ""
        dur_s  = fmt_duration(dur)
        if has_tok_data:
            in_s  = f"{in_t:,}"  if in_t  > 0 else f"{GRAY}—{NC}"
            out_s = f"{out_t:,}" if out_t > 0 else f"{GRAY}—{NC}"
            tot_s = f"{tot_t:,}" if tot_t > 0 else f"{GRAY}—{NC}"
            print(f"  {t:<18}  ${cost:>7.4f}  {dur_s:>9}  {in_s:>9}  {out_s:>9}  {tot_s:>9}  {GREEN}{bar}{NC}")
        else:
            print(f"  {t:<18}  ${cost:>7.4f}  {dur_s:>9}  {GREEN}{bar}{NC}")
    print()

# ── By phase (duration) ───────────────────────────────────────
stage_dur = {s: d for s, d in duration_by_stage.items() if d > 0}
if stage_dur:
    max_dur = max(stage_dur.values()) or 1
    print(f"{CYAN}Duration by phase:{NC}")
    for stage, dur in sorted(stage_dur.items(), key=lambda x: -x[1])[:10]:
        bar = "█" * min(int(dur / max_dur * 20), 20)
        print(f"  {stage:<22}  {fmt_duration(dur):>9}  {CYAN}{bar}{NC}")
    print()

# ── By command (tokens) ──────────────────────────────────────
cmd_toks = {c: t for c, t in tokens_by_cmd.items() if t > 0}
if cmd_toks:
    print(f"{CYAN}Tokens by command:{NC}")
    for cmd, toks in sorted(cmd_toks.items(), key=lambda x: -x[1])[:8]:
        print(f"  /{cmd:<21}  {toks:>10,}")
    print()

# ── Sprint trends ────────────────────────────────────────────
sprints = {s for s in tokens_by_sprint if s != "?"}
if len(sprints) > 1:
    all_sprints = sorted(set(list(tokens_by_sprint.keys()) + list(cost_by_sprint.keys())))
    max_cost_s = max((cost_by_sprint[s] for s in all_sprints), default=1) or 1
    print(f"{CYAN}Sprint trends:{NC}")
    for sprint in all_sprints:
        toks = tokens_by_sprint.get(sprint, 0)
        cost = cost_by_sprint.get(sprint, 0)
        bar  = "█" * min(int(cost / max_cost_s * 20), 20) if max_cost_s > 0 else ""
        print(f"  Sprint {sprint:<12}  ${cost:>7.4f}  {toks:>10,} tokens  {YELLOW}{bar}{NC}")
    print()

# ── Errors ───────────────────────────────────────────────────
if errors:
    print(f"{RED}Recent failures ({len(errors)}):{NC}")
    for e in errors[-5:]:
        ts     = (e.get("ts", "?") or "?")[:19]
        ticket = e.get("ticket", "?")
        detail = e.get("detail", e.get("event", "?"))
        print(f"  {ts}  {ticket:<20}  {detail}")
    print()

print()
PYEOF

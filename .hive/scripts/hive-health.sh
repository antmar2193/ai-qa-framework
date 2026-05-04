#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# hive-health.sh — HIVE Project Health Check
#
# Runs all 8 diagnostic checks without any LLM tokens.
# Identical output to what /health would produce, but instant.
#
# Usage:
#   bash .hive/scripts/hive-health.sh
#   hive health
# ============================================================

# ── Locate project ───────────────────────────────────────────
_hh_find_project() {
    if [[ -n "${HIVE_PROJECT_DIR:-}" && -f "$HIVE_PROJECT_DIR/.hive/AGENTS.local.md" ]]; then
        echo "$HIVE_PROJECT_DIR"; return
    fi
    local d abs
    for d in "$(pwd)" "$(pwd)/.." "$(pwd)/../.." "$(pwd)/../../.."; do
        abs="$(cd "$d" 2>/dev/null && pwd)"
        [[ -f "$abs/.hive/AGENTS.local.md" ]] && { echo "$abs"; return; }
    done
    echo ""
}

PROJECT_DIR=$(_hh_find_project)
if [[ -z "$PROJECT_DIR" ]]; then
    echo "Error: no HIVE project found (.hive/AGENTS.local.md missing)" >&2
    exit 1
fi
CONFIG="$PROJECT_DIR/.hive/AGENTS.local.md"

# ── Colors ───────────────────────────────────────────────────
R='\033[0m'
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'

# ── Config helpers ───────────────────────────────────────────
_cfg() {
    local key="$1" v
    v=$(awk -v k="$key" -F'"' '$0 ~ ("^[[:space:]]*" k ":[[:space:]]*\"") { print $2; exit }' "$CONFIG" 2>/dev/null | head -1)
    if [[ -z "$v" ]]; then
        v=$(awk -v k="$key" '$0 ~ ("^[[:space:]]*" k ":") { sub(/^[[:space:]]*[^:]+:[[:space:]]*/,""); sub(/[[:space:]#].*/,""); gsub(/"/,""); print; exit }' "$CONFIG" 2>/dev/null | head -1)
    fi
    echo "$v"
}

_cmd() {
    local key="$1" v
    v=$(awk -v k="$key" -F'"' '$0 ~ ("[[:space:]]+" k ":[[:space:]]*\"") { print $2; exit }' "$CONFIG" 2>/dev/null | head -1)
    if [[ -z "$v" ]]; then
        v=$(awk -v k="$key" '$0 ~ ("[[:space:]]+" k ":") { sub(/.*[[:space:]]+[^:]+:[[:space:]]*/,""); sub(/[[:space:]#].*/,""); gsub(/"/,""); print; exit }' "$CONFIG" 2>/dev/null | head -1)
    fi
    echo "${v:-null}"
}

# ── File mtime in epoch seconds (macOS BSD + Linux GNU) ──────
_mtime() {
    if stat -f %m "$1" &>/dev/null; then
        stat -f %m "$1" 2>/dev/null
    else
        stat -c %Y "$1" 2>/dev/null
    fi
}

# ── Result tracking ──────────────────────────────────────────
ISSUES=0; WARNS=0

_check() {
    local status="$1" label="$2" detail="$3"
    local icon col
    case "$status" in
        OK)   icon="✓"; col="$GREEN" ;;
        WARN) icon="⚠"; col="$YELLOW"; (( WARNS++ ))  ;;
        FAIL) icon="✗"; col="$RED";    (( ISSUES++ )) ;;
        INFO) icon="ℹ"; col="$CYAN"   ;;
    esac
    printf "  ${col}${icon}${R}  %-32s — %s\n" "$label" "$detail"
}

# ── Header ───────────────────────────────────────────────────
project=$(_cfg name)
printf "╔══════════════════════════════════════════════╗\n"
printf "║  ${BOLD}HIVE /health${R} — %-28s║\n" "${project:-unknown}"
printf "╚══════════════════════════════════════════════╝\n\n"

NOW=$(date +%s)

# ── 1. Config completeness ───────────────────────────────────
c1_fail="" c1_warn=""
for f in name stack tech_lead; do
    v=$(_cfg "$f")
    [[ -z "$v" || "$v" == TODO* ]] && c1_fail+=" ${f}"
done
# verify_commands.test is critical
tc=$(_cmd test)
[[ -z "$tc" || "$tc" == "null" ]] && c1_fail+=" verify_commands.test"
for f in board_url design_tool; do
    v=$(_cfg "$f")
    [[ -z "$v" || "$v" == TODO* ]] && c1_warn+=" ${f}"
done
if   [[ -n "$c1_fail" ]]; then _check FAIL "Config completeness"   "TODO in required fields:${c1_fail}"
elif [[ -n "$c1_warn" ]]; then _check WARN "Config completeness"   "TODO in optional fields:${c1_warn}"
else                           _check OK   "Config completeness"   "all required fields filled"
fi

# ── 2. Circuit breaker config ────────────────────────────────
max_ret=$(_cfg max_test_retries)
max_fil=$(_cfg max_new_files)
max_tok=$(_cfg max_tokens_per_ticket)
c2=""
[[ -z "$max_tok" ]] && c2+=" max_tokens_per_ticket not set;"
[[ -n "$max_tok" ]] && { num=$max_tok; [[ "$num" =~ ^[0-9]+$ ]] && (( num > 500000 )) && c2+=" max_tokens=${max_tok} (very high);"; }
[[ -z "$max_ret" ]] && c2+=" max_test_retries not set;"
[[ -n "$max_ret" ]] && { num=$max_ret; [[ "$num" =~ ^[0-9]+$ ]] && (( num > 5 )) && c2+=" max_test_retries=${max_ret}>5;"; }
[[ -z "$max_fil" ]] && c2+=" max_new_files not set;"
[[ -n "$max_fil" ]] && { num=$max_fil; [[ "$num" =~ ^[0-9]+$ ]] && (( num > 20 )) && c2+=" max_new_files=${max_fil}>20;"; }
if [[ -n "$c2" ]]; then _check WARN "Circuit breakers" "${c2%;}"
else                    _check OK   "Circuit breakers" "thresholds within range (ret=${max_ret:-?} files=${max_fil:-?} tokens=${max_tok:-?})"
fi

# ── 3. SPEC.md freshness ─────────────────────────────────────
spec="$PROJECT_DIR/.hive/specs/SPEC.md"
if [[ ! -f "$spec" ]]; then
    _check WARN "SPEC.md freshness" "file missing — run /sync"
else
    mtime=$(_mtime "$spec")
    age=$(( (NOW - mtime) / 86400 ))
    if (( age > 14 )); then _check WARN "SPEC.md freshness" "last modified ${age} days ago — run /sync"
    else                    _check OK   "SPEC.md freshness" "modified ${age} day(s) ago"
    fi
fi

# ── 4. Recent events.jsonl errors ────────────────────────────
events="$PROJECT_DIR/.hive/events.jsonl"
if [[ ! -f "$events" ]]; then
    _check INFO "Recent event errors" "skipped (no events.jsonl yet)"
else
    cb=$(tail -50 "$events" 2>/dev/null | grep -c '"event":"circuit_breaker"' || echo 0)
    fl=$(tail -50 "$events" 2>/dev/null | grep -c '"status":"failed"'         || echo 0)
    if   (( cb > 0 )); then _check FAIL "Recent event errors" "${cb} circuit_breaker event(s) in last 50 entries"
    elif (( fl > 0 )); then _check WARN "Recent event errors" "${fl} failed event(s) in last 50 entries"
    else                    _check OK   "Recent event errors" "no failures in recent events"
    fi
fi

# ── 5. Interrupted pipelines ─────────────────────────────────
stale=()
if [[ -d "$PROJECT_DIR/.hive/sessions" ]]; then
    while IFS= read -r f; do
        mt=$(_mtime "$f") || continue
        age_h=$(( (NOW - mt) / 3600 ))
        (( age_h >= 24 )) && stale+=("$(basename "$f" _state.json) (${age_h}h old)")
    done < <(find "$PROJECT_DIR/.hive/sessions" -name "*_state.json" 2>/dev/null | sort)
fi
if (( ${#stale[@]} > 0 )); then _check WARN "Interrupted pipelines" "${stale[*]}"
else                            _check OK   "Interrupted pipelines" "none"
fi

# ── 6. Branch staleness ──────────────────────────────────────
if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    _check INFO "Branch staleness" "skipped (not a git repo)"
else
    stale_br=()
    while IFS= read -r br; do
        [[ -z "$br" || "$br" == "HEAD" || "$br" == *"HEAD detached"* ]] && continue
        last=$(git -C "$PROJECT_DIR" log -1 --format="%ct" "$br" 2>/dev/null || echo 0)
        [[ -z "$last" || "$last" == "0" ]] && continue
        age_d=$(( (NOW - last) / 86400 ))
        (( age_d > 7 )) && stale_br+=("${br} (${age_d}d)")
    done < <(git -C "$PROJECT_DIR" branch --format="%(refname:short)" 2>/dev/null)
    if (( ${#stale_br[@]} > 0 )); then _check INFO "Branch staleness" "${stale_br[*]}"
    else                               _check OK   "Branch staleness" "all branches recent"
    fi
fi

# ── 7. Verify commands reachable ─────────────────────────────
missing_bins=()
for key in typecheck lint test; do
    cmd=$(_cmd "$key")
    [[ -z "$cmd" || "$cmd" == "null" ]] && continue
    bin="${cmd%% *}"
    command -v "$bin" &>/dev/null || missing_bins+=("$bin (${key})")
done
if (( ${#missing_bins[@]} > 0 )); then _check WARN "Verify commands" "not in PATH: ${missing_bins[*]}"
else                                   _check OK   "Verify commands" "all binaries found"
fi

# ── 8. Hooks installed ───────────────────────────────────────
hook="$PROJECT_DIR/.git/hooks/pre-commit"
if [[ -f "$hook" ]] && grep -qi "hive" "$hook" 2>/dev/null; then
    _check OK   "Hooks installed" "pre-commit hook present"
elif [[ -f "$hook" ]]; then
    _check INFO "Hooks installed" "pre-commit exists but no HIVE reference"
else
    _check WARN "Hooks installed" "missing — run: bash .hive/scripts/install-hooks.sh"
fi

# ── Summary ──────────────────────────────────────────────────
printf "\n%s\n" "────────────────────────────────────────────────"
if   (( ISSUES > 0 )); then printf "  ${RED}%d issue(s)${R}, %d warning(s) — fix before starting sprint work\n" "$ISSUES" "$WARNS"
elif (( WARNS  > 0 )); then printf "  ${YELLOW}%d warning(s) found${R} — review above\n" "$WARNS"
else                        printf "  ${GREEN}All checks passed${R}\n"
fi
printf "\n"

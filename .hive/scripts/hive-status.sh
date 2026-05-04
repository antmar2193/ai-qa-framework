#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# hive-status.sh — HIVE Project Status Snapshot
#
# Prints a full config snapshot without any LLM tokens.
# Identical output to what /status would produce, but instant.
#
# Usage:
#   bash .hive/scripts/hive-status.sh
#   hive status
# ============================================================

# ── Locate project ───────────────────────────────────────────
_hs_find_project() {
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

PROJECT_DIR=$(_hs_find_project)
if [[ -z "$PROJECT_DIR" ]]; then
    echo "Error: no HIVE project found (.hive/AGENTS.local.md missing)" >&2
    exit 1
fi
CONFIG="$PROJECT_DIR/.hive/AGENTS.local.md"

# ── Colors ───────────────────────────────────────────────────
R='\033[0m'; BOLD='\033[1m'
CYAN='\033[0;36m'; YELLOW='\033[1;33m'; GRAY='\033[2;37m'; GREEN='\033[0;32m'

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

_flag() {
    local key="$1" v; v=$(_cfg "$key")
    [[ "$v" == "true" ]] && printf "${GREEN}on${R}" || printf "${GRAY}off${R}"
}

# ── Gather values ────────────────────────────────────────────
project=$(_cfg name);        stack=$(_cfg stack)
hive_ver=$(_cfg hive_version); proj_ver=$(_cfg version)
autonomy=$(_cfg level);       profile=$(_cfg active_profile)
tech_lead=$(_cfg tech_lead);  vcs=$(_cfg platform)
ai_cli=$(_cfg ai_cli);        ticket_tool=$(_cfg "ticket_provider.tool")
[[ -z "$ticket_tool" ]] && ticket_tool=$(_cfg tool)
pr_tool=$(_cfg pr_tool)

tc=$(_cmd typecheck); lint=$(_cmd lint); tst=$(_cmd test); cov=$(_cmd coverage)
max_ret=$(_cfg max_test_retries); max_fil=$(_cfg max_new_files)
max_tok=$(_cfg max_tokens_per_ticket)

# Interrupted pipelines
pipe_count=0
if [[ -d "$PROJECT_DIR/.hive/sessions" ]]; then
    pipe_count=$(find "$PROJECT_DIR/.hive/sessions" -name "*_state.json" 2>/dev/null | wc -l | tr -d ' ')
fi

# Legacy mode
is_legacy=$(_cfg is_legacy)
protected=$(_cfg protected_paths)
focus=""
[[ -f "$PROJECT_DIR/.hive/sessions/focus.md" ]] && \
    focus=$(head -1 "$PROJECT_DIR/.hive/sessions/focus.md" 2>/dev/null || echo "")

# TODOs warning
todo_count=$(grep -c "TODO:" "$CONFIG" 2>/dev/null; true)

# ── Header ───────────────────────────────────────────────────
printf "${CYAN}${BOLD}[HIVE${hive_ver:+ ${hive_ver}}]${R} ${BOLD}${project:-unknown}${R}"
[[ -n "$stack"    ]] && printf " · ${GRAY}%s${R}" "$stack"
[[ -n "$proj_ver" ]] && printf " · ${GRAY}v%s${R}" "$proj_ver"
[[ -n "$autonomy" ]] && printf " · autonomy: ${CYAN}%s${R}" "$autonomy"
[[ -n "$profile"  ]] && printf " · profile: ${CYAN}%s${R}" "${profile:-default}"
printf "\n\n"

# ── Project ──────────────────────────────────────────────────
printf "${BOLD}Project${R}\n"
printf "  %-22s : %s\n" "name"      "${project:-?}"
printf "  %-22s : %s\n" "stack"     "${stack:-?}"
printf "  %-22s : %s\n" "version"   "${proj_ver:-?}"
printf "  %-22s : %s\n" "hive_version" "${hive_ver:-?}"
printf "  %-22s : %s\n" "tech_lead" "${tech_lead:-?}"
printf "  %-22s : %s\n" "dir"       "$PROJECT_DIR"
printf "\n"

# ── Autonomy & Model ─────────────────────────────────────────
printf "${BOLD}Autonomy & Model${R}\n"
printf "  %-22s : ${CYAN}%s${R}\n" "autonomy"       "${autonomy:-?}"
printf "  %-22s : %s\n"            "profile"        "${profile:-default}"
printf "  %-22s : %s\n"            "ai_cli"         "${ai_cli:-?}"
printf "\n"

# ── Integrations ─────────────────────────────────────────────
printf "${BOLD}Integrations${R}\n"
printf "  %-22s : %s\n" "vcs"         "${vcs:-?}"
printf "  %-22s : %s\n" "ticket_tool" "${ticket_tool:-none}"
printf "  %-22s : %s\n" "pr_tool"     "${pr_tool:-?}"
printf "  %-22s : " "auto_merge_pr";  _flag "auto_merge_pr"; printf "\n"
printf "\n"

# ── Verify commands ──────────────────────────────────────────
printf "${BOLD}Verify commands${R}\n"
printf "  %-22s : %s\n" "typecheck" "$tc"
printf "  %-22s : %s\n" "lint"      "$lint"
printf "  %-22s : %s\n" "test"      "$tst"
printf "  %-22s : %s\n" "coverage"  "$cov"
printf "\n"

# ── Circuit breakers ─────────────────────────────────────────
printf "${BOLD}Circuit breakers${R}\n"
printf "  %-22s : %s\n" "max_test_retries"      "${max_ret:-?}"
printf "  %-22s : %s\n" "max_new_files"         "${max_fil:-?}"
printf "  %-22s : %s\n" "max_tokens_per_ticket" "${max_tok:-?}"
printf "\n"

# ── Pipelines ────────────────────────────────────────────────
printf "${BOLD}Pipelines${R}\n"
if (( pipe_count > 0 )); then
    printf "  %-22s : ${YELLOW}%s${R} — run /resume --list for details\n" "interrupted" "$pipe_count"
else
    printf "  %-22s : none\n" "interrupted"
fi
printf "\n"

# ── Legacy (if active) ───────────────────────────────────────
if [[ "$is_legacy" == "true" ]]; then
    printf "${BOLD}Legacy mode${R}\n"
    printf "  %-22s : %s\n" "protected" "${protected:-?}"
    printf "  %-22s : %s\n" "focus"     "${focus:-none}"
    printf "\n"
fi

# ── Warnings ─────────────────────────────────────────────────
if (( todo_count > 0 )); then
    printf "${YELLOW}⚠  %d TODO(s) remaining in AGENTS.local.md — run 'hive validate .' to list them${R}\n\n" "$todo_count"
fi

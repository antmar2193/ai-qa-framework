#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# hive-dashboard.sh — HIVE Project Status Dashboard
#
# A live terminal view of project state. Open in a dedicated
# tab while working to maintain situational awareness.
#
# Usage (from project root):
#   bash .hive/scripts/hive-dashboard.sh
#   bash .hive/scripts/hive-dashboard.sh --watch        # refresh every 10s
#   bash .hive/scripts/hive-dashboard.sh --watch=30     # custom interval
#
# Or via shell hook (after sourcing hive-shell-hook.sh):
#   hive-dashboard --watch
# ============================================================

# ── Locate project root ──────────────────────────────────────
_hd_find_project() {
    if [[ -n "${HIVE_PROJECT_DIR:-}" && -f "$HIVE_PROJECT_DIR/.hive/AGENTS.local.md" ]]; then
        echo "$HIVE_PROJECT_DIR"; return
    fi
    local d
    for d in "$(pwd)" "$(pwd)/.." "$(pwd)/../.." "$(pwd)/../../.."; do
        local abs
        abs="$(cd "$d" 2>/dev/null && pwd)"
        if [[ -f "$abs/.hive/AGENTS.local.md" ]]; then
            echo "$abs"; return
        fi
    done
    echo ""
}

PROJECT_DIR=$(_hd_find_project)
if [[ -z "$PROJECT_DIR" ]]; then
    echo "Error: no HIVE project found (.hive/AGENTS.local.md missing)"
    echo "Run from a project directory or set HIVE_PROJECT_DIR"
    exit 1
fi

CONFIG="$PROJECT_DIR/.hive/AGENTS.local.md"

# ── Arguments ────────────────────────────────────────────────
WATCH=false
INTERVAL=10
for arg in "$@"; do
    case "$arg" in
        --watch)   WATCH=true ;;
        --watch=*) WATCH=true; INTERVAL="${arg#--watch=}" ;;
    esac
done

# ── Colors ───────────────────────────────────────────────────
R='\033[0m'; B='\033[1m'
CYAN='\033[0;36m'; BCYAN='\033[1;36m'
GREEN='\033[0;32m'; YELLOW='\033[1;33m'
GRAY='\033[2;37m'

# ── Layout ───────────────────────────────────────────────────
COLS=$(tput cols 2>/dev/null || echo 100)
(( COLS < 84  )) && COLS=84
(( COLS > 120 )) && COLS=120
INNER=$(( COLS - 2 ))
COL=$(( (INNER - 3) / 2 ))

# ── Drawing primitives ───────────────────────────────────────

_rep() {
    local c="$1" n="$2" r="" i
    for (( i=0; i<n; i++ )); do r+="$c"; done
    printf '%s' "$r"
}

_vlen() {
    local raw esc stripped
    raw=$(printf '%b' "$1")
    esc=$(printf '\033')
    stripped=$(printf '%s' "$raw" | sed "s/${esc}\[[0-9;]*[mK]//g")
    printf '%s' "${#stripped}"
}

_top()  { printf '╔%s╗\n' "$(_rep ═ "$INNER")"; }
_mid()  { printf '╠%s╣\n' "$(_rep ═ "$INNER")"; }
_bot()  { printf '╚%s╝\n' "$(_rep ═ "$INNER")"; }
_mid2() { printf '╠%s╪%s╣\n' "$(_rep ═ $((COL+1)))" "$(_rep ═ $((INNER-COL-2)))"; }

_row() {
    local c="$1"
    local vl pad
    vl=$(_vlen "$c")
    pad=$(( INNER - vl - 1 ))
    (( pad < 0 )) && pad=0
    printf "║ %b%*s║\n" "$c" "$pad" ''
}

_row2() {
    local L="$1" Rc="$2"
    local ll rl lp rp
    ll=$(_vlen "$L"); rl=$(_vlen "$Rc")
    lp=$(( COL - ll ));              (( lp < 0 )) && lp=0
    rp=$(( INNER - COL - rl - 3 )); (( rp < 0 )) && rp=0
    printf "║ %b%*s │ %b%*s║\n" "$L" "$lp" '' "$Rc" "$rp" ''
}

# ── Config helpers ───────────────────────────────────────────

_cfg() {
    # Extract YAML value: key: "value" or key: value — awk for BSD grep compatibility
    local key="$1" v
    v=$(awk -v k="$key" -F'"' '$0 ~ ("^[[:space:]]*" k ":[[:space:]]*\"") { print $2; exit }' "$CONFIG" 2>/dev/null | head -1)
    if [[ -z "$v" ]]; then
        v=$(awk -v k="$key" '$0 ~ ("^[[:space:]]*" k ":") { sub(/^[[:space:]]*[^:]+:[[:space:]]*/,""); sub(/[[:space:]#].*/,""); gsub(/"/,""); print; exit }' "$CONFIG" 2>/dev/null | head -1)
    fi
    echo "$v"
}

_cmd() {
    local v key="$1"
    v=$(awk -v k="$key" -F'"' '$0 ~ ("[[:space:]]+" k ":[[:space:]]*\"") { print $2; exit }' "$CONFIG" 2>/dev/null | head -1)
    if [[ -z "$v" ]]; then
        v=$(awk -v k="$key" '$0 ~ ("[[:space:]]+" k ":") { sub(/.*[[:space:]]+[^:]+:[[:space:]]*/,""); sub(/[[:space:]#].*/,""); gsub(/"/,""); print; exit }' "$CONFIG" 2>/dev/null | head -1)
    fi
    echo "${v:-null}"
}

# ── One-time MCP detection ───────────────────────────────────
MEM_OK=false; TKT_OK=false
python3 -c "import hive_memory"  &>/dev/null  && MEM_OK=true
python3 -c "import hive_tickets" &>/dev/null  && TKT_OK=true

# ── Render ───────────────────────────────────────────────────
_render() {

    # Gather config
    local project stack hive_ver proj_ver autonomy profile persona
    local vcs ticket_tool branching auto_merge ai_cli
    local max_retries max_files max_tokens tc lint tst board_url

    project=$(_cfg name);          stack=$(_cfg stack)
    hive_ver=$(_cfg hive_version); proj_ver=$(_cfg version)
    autonomy=$(_cfg level);        profile=$(_cfg active_profile)
    persona=$(_cfg tech_lead);     vcs=$(_cfg platform)
    ticket_tool=$(_cfg "ticket_provider.tool"); [[ -z "$ticket_tool" ]] && ticket_tool=$(_cfg tool)
    branching=$(_cfg pr_tool);     auto_merge=$(_cfg auto_merge_pr)
    ai_cli=$(_cfg ai_cli)
    max_retries=$(_cfg max_test_retries); max_files=$(_cfg max_new_files)
    max_tokens=$(_cfg max_tokens_per_ticket)
    tc=$(_cmd typecheck); lint=$(_cmd lint); tst=$(_cmd test)
    board_url=$(_cfg board_url); [[ -z "$board_url" ]] && board_url=$(_cfg project_url)

    # Git
    local branch="" remote="" last_commit=""
    if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        branch=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        remote=$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null \
            | sed 's|https://github.com/||;s|git@github.com:||;s|\.git$||' || true)
        last_commit=$(git -C "$PROJECT_DIR" log -1 --format="%h %s" 2>/dev/null \
            | cut -c1-48 || true)
    fi

    # Truncate git values to fit right column (avoids border overflow)
    local _rcol_max=$(( INNER - COL - 18 ))
    (( _rcol_max < 8 )) && _rcol_max=8
    if [[ ${#branch} -gt $_rcol_max ]]; then
        branch="${branch:0:$(( _rcol_max - 1 ))}…"
    fi
    if [[ ${#last_commit} -gt $_rcol_max ]]; then
        last_commit="${last_commit:0:$(( _rcol_max - 1 ))}…"
    fi

    # Sprint (SPEC.md)
    local sprint=""
    local spec="$PROJECT_DIR/.hive/specs/SPEC.md"
    [[ -f "$spec" ]] && sprint=$(awk '/^##[[:space:]]*Sprint[[:space:]]/ { print $3; exit }
        /[Ss]print[_: ]+[0-9]/ { gsub(/.*[Ss]print[_: ]*/,""); gsub(/[^0-9].*/,""); print; exit }' \
        "$spec" 2>/dev/null | head -1 || true)

    # Tickets from .hive/changes/
    local tickets=() seen=""
    if [[ -d "$PROJECT_DIR/.hive/changes" ]]; then
        while IFS= read -r f; do
            local tid
            tid=$(basename "$f" \
                | sed 's/_backend\..*//;s/_frontend\..*//;s/_tdd_evidence\..*//')
            [[ "$seen" != *"|${tid}|"* ]] && { seen+="|${tid}|"; tickets+=("$tid"); }
        done < <(find "$PROJECT_DIR/.hive/changes" -maxdepth 1 \
            \( -name "*.md" -o -name "*.yml" \) 2>/dev/null | sort)
    fi

    # Skills from .hive/.skills/
    local skills=()
    if [[ -d "$PROJECT_DIR/.hive/.skills" ]]; then
        while IFS= read -r f; do
            skills+=("$(basename "$f" .yml)")
        done < <(find "$PROJECT_DIR/.hive/.skills" -name "*.yml" 2>/dev/null | sort)
    fi

    # Interrupted pipelines from .hive/sessions/
    local sessions=()
    if [[ -d "$PROJECT_DIR/.hive/sessions" ]]; then
        while IFS= read -r f; do
            local tid phase
            tid=$(basename "$f" "_state.json")
            phase=$(awk -F'"' '/"current_phase":/ { print $4; exit }' "$f" 2>/dev/null || true)
            sessions+=("${tid} → ${phase:-?}")
        done < <(find "$PROJECT_DIR/.hive/sessions" -name "*_state.json" 2>/dev/null | sort)
    fi

    # MCP status + memory observation count
    local mem_s tkt_s mem_obs=0
    if [[ -d "$PROJECT_DIR/.hive/memory/observations" ]]; then
        mem_obs=$(find "$PROJECT_DIR/.hive/memory/observations" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
    fi
    $MEM_OK && mem_s="${GREEN}installed${R}" || mem_s="${GRAY}not found${R}"
    (( mem_obs > 0 )) && mem_s+="  ${GRAY}(${mem_obs} obs)${R}"
    $TKT_OK && tkt_s="${GREEN}installed${R}" || tkt_s="${GRAY}not found${R}"

    local am_col="$GRAY"; [[ "$auto_merge" == "true" ]] && am_col="$GREEN"
    local am_display="off"; [[ "$auto_merge" == "true" ]] && am_display="on"

    # ── Paint ────────────────────────────────────────────────

    _top
    local hdr="${BCYAN}[HIVE${hive_ver:+ ${hive_ver}}]${R}  ${B}${project:-unknown}${R}"
    [[ -n "$stack"    ]] && hdr+="  ${GRAY}${stack}${R}"
    [[ -n "$proj_ver" ]] && hdr+="  ${GRAY}v${proj_ver}${R}"
    _row "$hdr"
    _mid

    # PROYECTO | GIT & WORKFLOW
    _row2 "${GRAY}PROYECTO${R}"                              "${GRAY}GIT & WORKFLOW${R}"
    _row2 "  Autonomy    ${CYAN}${autonomy:-?}${R}"         "  Branch       ${CYAN}${branch:-?}${R}"
    _row2 "  Profile     ${CYAN}${profile:-default}${R}"    "  PR tool      ${branching:-?}"
    _row2 "  Owner       ${persona:-?}"                     "  Auto-merge   ${am_col}${am_display}${R}"
    _row2 "  VCS         ${vcs:-?}"                         "  Agent        ${ai_cli:-?}"
    [[ -n "$remote"      ]] && _row2 "" "  Repo         ${GRAY}${remote}${R}"
    [[ -n "$last_commit" ]] && _row2 "" "  Last commit  ${GRAY}${last_commit}${R}"

    # SPRINT / TICKETS | CONNECTIONS
    _mid2
    local sprint_hdr="${GRAY}TICKETS${R}"
    [[ -n "$sprint" ]] && sprint_hdr="${GRAY}SPRINT ${B}${sprint}${R}"
    _row2 "$sprint_hdr"  "${GRAY}CONNECTIONS${R}"
    _row2 "" "  Board        ${ticket_tool:-none}${board_url:+  ${GRAY}${board_url}${R}}"
    _row2 "" "  hive-memory   ${mem_s}"
    _row2 "" "  hive-tickets  ${tkt_s}"
    _row2 "" ""

    if [[ ${#tickets[@]} -eq 0 ]]; then
        _row2 "  ${GRAY}(no active tickets)${R}" ""
    else
        local shown=0
        for tk in "${tickets[@]}"; do
            (( shown >= 6 )) && break
            _row2 "  ${CYAN}${tk}${R}" ""
            (( shown++ ))
        done
        (( ${#tickets[@]} > 6 )) && _row2 "  ${GRAY}+$(( ${#tickets[@]} - 6 )) more…${R}" ""
    fi

    # SKILLS | INTERRUPTED PIPELINES
    _mid2
    _row2 "${GRAY}SKILLS (.hive/.skills/)${R}" "${GRAY}INTERRUPTED PIPELINES${R}"

    local max_r=${#skills[@]}
    (( ${#sessions[@]} > max_r )) && max_r=${#sessions[@]}
    (( max_r < 1 )) && max_r=1

    local si=0 ssi=0
    for (( i=0; i<max_r; i++ )); do
        local lc="" rc=""
        (( si  < ${#skills[@]}   )) && { lc="  ${skills[$si]}";                  (( si++  )); }
        (( ssi < ${#sessions[@]} )) && { rc="  ${YELLOW}${sessions[$ssi]}${R}";  (( ssi++ )); }
        [[ -z "$lc" && -z "$rc" ]] && lc="  ${GRAY}(none)${R}"
        _row2 "$lc" "$rc"
    done

    # VERIFY COMMANDS
    _mid
    _row "${GRAY}VERIFY COMMANDS${R}"
    _row "  typecheck   ${tc:-null}"
    _row "  lint        ${lint:-null}"
    _row "  test        ${tst:-null}"

    # CIRCUIT BREAKERS
    _mid
    _row "${GRAY}CIRCUIT BREAKERS${R}"
    _row "  max_test_retries ${CYAN}${max_retries:-3}${R}    max_new_files ${CYAN}${max_files:-5}${R}    max_tokens_per_ticket ${CYAN}${max_tokens:-200000}${R}"

    _bot
}

# ── Entry point ──────────────────────────────────────────────

if [[ "$WATCH" == "true" ]]; then
    while true; do
        clear
        _render
        printf "\n  ${GRAY}Updated: $(date '+%H:%M:%S')  ·  interval: ${INTERVAL}s  ·  Ctrl+C to exit${R}\n"
        sleep "$INTERVAL"
    done
else
    _render
    printf "\n  ${GRAY}Tip: --watch or --watch=N for auto-refresh${R}\n"
fi

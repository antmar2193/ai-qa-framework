#!/usr/bin/env bash
# ============================================================
# hive-config.sh — Interactive HIVE configuration wizard
#
# Walks through AGENTS.local.md sections with plain-English
# prompts. Generates a valid .hive/AGENTS.local.md without
# requiring YAML knowledge.
#
# Usage:
#   bash .hive/scripts/hive-config.sh           # full wizard
#   bash .hive/scripts/hive-config.sh --section autonomy
#   bash .hive/scripts/hive-config.sh --show    # print current config
#   hive config                                  # via unified CLI
#
# Requirements:
#   Must be run from the project root (where .hive/ lives)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/require-python3.sh
source "$SCRIPT_DIR/lib/require-python3.sh"

# Factory root: two levels up if in project .hive/scripts/,
# or one level up if in factory scripts/
if [[ -f "$SCRIPT_DIR/../AGENTS.local.md" ]]; then
    PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
    FACTORY_ROOT="${HIVE_FACTORY_ROOT:-}"
    if [[ -z "$FACTORY_ROOT" ]]; then
        FACTORY_ROOT="$(awk -F'"' '/hive_root:/ { print $2; exit }' "$SCRIPT_DIR/../AGENTS.local.md" 2>/dev/null || echo "")"
    fi
else
    PROJECT_DIR="$(pwd)"
    FACTORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

HIVE_DIR="$PROJECT_DIR/.hive"
CONFIG_FILE="$HIVE_DIR/AGENTS.local.md"
HIVE_VERSION="$(cat "${FACTORY_ROOT:-$SCRIPT_DIR/..}/VERSION" 2>/dev/null || echo "dev")"

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[2m'
MAGENTA='\033[0;35m'; NC='\033[0m'

info()    { printf "  ${CYAN}→${NC} %s\n" "$1"; }
ok()      { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
warn()    { printf "  ${YELLOW}!${NC} %s\n" "$1"; }
err()     { printf "  ${RED}✗${NC} %s\n" "$1" >&2; }
section() { printf "\n${BOLD}${MAGENTA}── %s${NC}\n" "$1"; }
hint()    { printf "    ${DIM}%s${NC}\n" "$1"; }

# ── _config_set — patch a single key without running the wizard ─
_config_set() {
    local key="$1" val="$2"
    local leaf="${key##*.}"
    local tmp; tmp=$(mktemp)

    # Validate known keys and their allowed values
    case "$key" in
        autonomy.level)
            [[ "$val" == "supervised" || "$val" == "balanced" || "$val" == "autonomous" ]] || {
                err "Invalid value '$val'. Allowed: supervised | balanced | autonomous"; return 1; }
            ;;
        auto_merge_pr)
            [[ "$val" == "true" || "$val" == "false" ]] || {
                err "Invalid value '$val'. Allowed: true | false"; return 1; }
            ;;
        circuit_breaker.max_test_retries|circuit_breaker.max_new_files|circuit_breaker.max_tokens_per_ticket)
            [[ "$val" =~ ^[0-9]+$ ]] || { err "Value must be a number"; return 1; }
            ;;
    esac

    # Backup
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

    # Patch: find `  leaf: "old"` or `  leaf: old` and replace value
    # Handles both quoted strings and bare booleans/numbers
    python3 - "$CONFIG_FILE" "$leaf" "$val" <<'PYEOF' > "$tmp"
import sys, re
cfg_file, leaf, new_val = sys.argv[1], sys.argv[2], sys.argv[3]
# Determine if value should be quoted (string) or bare (bool/number)
bare = re.match(r'^(true|false|[0-9]+)$', new_val)
replacement = new_val if bare else f'"{new_val}"'
pattern = re.compile(r'^(\s+' + re.escape(leaf) + r':\s*)("?[^"\n]+"?)(.*)')
found = False
with open(cfg_file) as f:
    for line in f:
        m = pattern.match(line)
        if m and not found:
            print(f"{m.group(1)}{replacement}{m.group(3)}")
            found = True
        else:
            print(line, end='')
if not found:
    sys.exit(2)
PYEOF

    local rc=$?
    if [[ $rc -eq 2 ]]; then
        rm -f "$tmp"
        err "Key '$leaf' not found in $CONFIG_FILE — add it manually"
        return 1
    fi

    mv "$tmp" "$CONFIG_FILE"
    ok "Set $key = $val"

    # If autonomy changed, sync .claude/settings.json
    if [[ "$key" == "autonomy.level" ]]; then
        local claude_settings
        claude_settings="$(dirname "$HIVE_DIR")/.claude/settings.json"
        if [[ -f "$claude_settings" ]]; then
            local new_mode
            [[ "$val" == "autonomous" ]] && new_mode="bypassPermissions" || new_mode="acceptEdits"
            python3 - "$claude_settings" "$new_mode" <<'PYEOF2'
import json, sys
f, mode = sys.argv[1], sys.argv[2]
try: cfg = json.load(open(f))
except: cfg = {}
if cfg.get("defaultMode") != mode:
    cfg["defaultMode"] = mode
    with open(f, "w") as fh: json.dump(cfg, fh, indent=2); fh.write("\n")
    print(f"  → .claude/settings.json defaultMode → {mode}")
PYEOF2
        fi
    fi
}

# ── Parse flags ───────────────────────────────────────────────
SECTION_ONLY=""
SHOW_MODE=false
SET_KEY=""
SET_VAL=""
SUBCOMMAND=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        set)       SUBCOMMAND="set"; SET_KEY="${2:-}"; SET_VAL="${3:-}"; shift 2 ;;
        get)       SUBCOMMAND="get"; SET_KEY="${2:-}"; shift ;;
        --section) SECTION_ONLY="$2"; shift ;;
        --show)    SHOW_MODE=true ;;
        --help|-h) SHOW_MODE=false ;;
    esac
    shift
done

# ── Set subcommand — patch a single key in AGENTS.local.md ────
if [[ "$SUBCOMMAND" == "set" ]]; then
    if [[ -z "$SET_KEY" || -z "$SET_VAL" ]]; then
        echo "Usage: hive config set <key> <value>"
        echo ""
        echo "Examples:"
        echo "  hive config set autonomy.level autonomous"
        echo "  hive config set autonomy.level supervised"
        echo "  hive config set autonomy.level balanced"
        echo "  hive config set auto_merge_pr true"
        echo "  hive config set circuit_breaker.max_test_retries 5"
        exit 1
    fi
    if [[ ! -f "$CONFIG_FILE" ]]; then
        err "No config found at $CONFIG_FILE"
        exit 1
    fi
    _config_set "$SET_KEY" "$SET_VAL"
    exit $?
fi

# ── Get subcommand ─────────────────────────────────────────────
if [[ "$SUBCOMMAND" == "get" ]]; then
    if [[ -z "$SET_KEY" ]]; then
        echo "Usage: hive config get <key>"
        exit 1
    fi
    if [[ ! -f "$CONFIG_FILE" ]]; then
        err "No config found at $CONFIG_FILE"; exit 1
    fi
    # Extract leaf key name and grep for it
    LEAF="${SET_KEY##*.}"
    VAL=$(grep -E "^\s+${LEAF}:" "$CONFIG_FILE" | head -1 | sed 's/.*: *//' | tr -d '"')
    echo "$VAL"
    exit 0
fi

# ── Banner ────────────────────────────────────────────────────
echo ""
printf "${CYAN}${BOLD}HIVE v%s${NC}  ${DIM}Configuration Wizard${NC}\n" "$HIVE_VERSION"
echo ""

# ── Show mode ─────────────────────────────────────────────────
if $SHOW_MODE; then
    if [[ ! -f "$CONFIG_FILE" ]]; then
        err "No config found at $CONFIG_FILE"
        info "Run without --show to create it"
        exit 1
    fi
    echo "Current configuration: $CONFIG_FILE"
    echo ""
    grep -E '^\s+(name|stack|tech_lead|level|communication|style|active_profile|tool|webhook|platform|default_base_branch):' \
        "$CONFIG_FILE" 2>/dev/null | sed 's/^/  /' || true
    echo ""
    exit 0
fi

# ── Section shortcut — redirect single-key changes to `set` ───
if [[ -n "$SECTION_ONLY" ]]; then
    case "$SECTION_ONLY" in
        autonomy)
            if [[ ! -f "$CONFIG_FILE" ]]; then err "No config found at $CONFIG_FILE"; exit 1; fi
            section "Autonomy"
            printf "  ${DIM}supervised${NC}  — AI stops for your approval on every plan and before commit\n"
            printf "  ${DIM}balanced${NC}    — AI plans with you, then implements autonomously until commit\n"
            printf "  ${DIM}autonomous${NC}  — AI runs the full pipeline without stopping (server/overnight use)\n"
            echo ""
            CURRENT=$(grep -E '^\s+level:' "$CONFIG_FILE" | head -1 | sed 's/.*: *//' | tr -d '"')
            _choose "Autonomy level" "supervised|balanced|autonomous" "${CURRENT:-supervised}"
            _config_set "autonomy.level" "$REPLY"
            exit $?
            ;;
        *)
            warn "--section $SECTION_ONLY not supported. Use 'hive config set <key> <value>' for targeted changes."
            info "Example: hive config set autonomy.level autonomous"
            exit 1
            ;;
    esac
fi

# ── Check we're in a HIVE project ─────────────────────────────
if [[ ! -d "$HIVE_DIR" ]]; then
    err "No .hive/ directory found in $(pwd)"
    info "Run 'hive inject .' to add HIVE to this project first"
    exit 1
fi

# ── Prompt helper — ask question with default ─────────────────
# Usage: _ask "Question" [default] — stores answer in REPLY
_ask() {
    local prompt="$1"
    local default="${2:-}"
    if [[ -n "$default" ]]; then
        printf "  ${CYAN}?${NC} %s ${DIM}[%s]${NC}: " "$prompt" "$default"
    else
        printf "  ${CYAN}?${NC} %s: " "$prompt"
    fi
    read -r REPLY
    if [[ -z "$REPLY" && -n "$default" ]]; then
        REPLY="$default"
    fi
}

# Usage: _choose "Question" "opt1|opt2|opt3" [default] — stores in REPLY
_choose() {
    local prompt="$1"
    local opts="$2"
    local default="${3:-}"
    local IFS='|'
    local i=1
    printf "  ${CYAN}?${NC} %s\n" "$prompt"
    for opt in $opts; do
        if [[ "$opt" == "$default" ]]; then
            printf "      ${GREEN}%d)${NC} ${BOLD}%s${NC} ${DIM}(default)${NC}\n" "$i" "$opt"
        else
            printf "      ${DIM}%d)${NC} %s\n" "$i" "$opt"
        fi
        i=$((i+1))
    done
    printf "  Enter number or value [%s]: " "${default:-1}"
    read -r REPLY
    if [[ -z "$REPLY" ]]; then
        REPLY="${default:-}"
    elif [[ "$REPLY" =~ ^[0-9]+$ ]]; then
        # Convert number to option value
        local j=1
        for opt in $opts; do
            if [[ "$j" == "$REPLY" ]]; then REPLY="$opt"; break; fi
            j=$((j+1))
        done
    fi
}

# ── Collect configuration ─────────────────────────────────────

# Project Identity
section "Project Identity"
hint "Basic info about this project"
echo ""

_ask "Project name" ""
P_NAME="$REPLY"

_ask "Tech lead name" ""
P_TECH_LEAD="$REPLY"

_choose "Stack" "node-react-prisma|python-fastapi|dotnet|java-spring|mobile-rn|go|custom" "node-react-prisma"
P_STACK="$REPLY"

# Autonomy
section "Autonomy"
hint "How much should the AI do without stopping to ask you?"
echo ""
printf "  ${DIM}supervised${NC}  — AI stops for your approval on every plan and before commit\n"
printf "  ${DIM}balanced${NC}    — AI plans with you, then implements autonomously until commit\n"
printf "  ${DIM}autonomous${NC}  — AI runs the full pipeline without stopping (server/overnight use)\n"
echo ""
_choose "Autonomy level" "supervised|balanced|autonomous" "supervised"
P_AUTONOMY="$REPLY"

# Circuit breakers
echo ""
hint "Circuit breakers stop the AI if something looks wrong."
_ask "Stop if tests fail this many times in a row" "3"
P_MAX_RETRIES="$REPLY"
_ask "Stop if AI needs to create more than this many new files" "5"
P_MAX_FILES="$REPLY"

# Language
section "Communication Language"
hint "What language should the AI use for responses, commits, and PRs?"
echo ""
_choose "Language" "en|es|pt|fr|de" "en"
P_LANG="$REPLY"

# Persona
section "AI Communication Style"
echo ""
printf "  ${DIM}verbose${NC}   — step-by-step explanations and tradeoffs (good for onboarding)\n"
printf "  ${DIM}neutral${NC}   — concise summaries of what was done and why (default)\n"
printf "  ${DIM}terse${NC}     — minimal output: diffs, status, and errors only (senior devs / CI)\n"
echo ""
_choose "Style" "verbose|neutral|terse" "neutral"
P_STYLE="$REPLY"

# Ticket provider
section "Ticket Tracker"
hint "Where are work tickets managed?"
echo ""
_choose "Ticket tool" "jira|linear|github-issues|trello|clickup|none" "none"
P_TICKET_TOOL="$REPLY"

P_TICKET_MCP="none"
P_BOARD_URL=""

if [[ "$P_TICKET_TOOL" != "none" ]]; then
    case "$P_TICKET_TOOL" in
        jira)           P_TICKET_MCP="Atlassian" ;;
        linear)         P_TICKET_MCP="Linear" ;;
        github-issues)  P_TICKET_MCP="GitHub" ;;
        *)              P_TICKET_MCP="none" ;;
    esac
    _ask "Board URL (for links in PRs and SPEC.md)" ""
    P_BOARD_URL="$REPLY"
fi

# VCS
section "Version Control"
echo ""
_choose "Platform" "github|gitlab|bitbucket|azure-devops" "github"
P_VCS="$REPLY"

_ask "Default branch name" "main"
P_BRANCH="$REPLY"

_ask "Branch pattern (use {ticket-id} as placeholder)" "feature/{ticket-id}-{description}"
P_BRANCH_PATTERN="$REPLY"

P_PR_TOOL="null"
if [[ "$P_VCS" == "github" ]]; then P_PR_TOOL="gh"
elif [[ "$P_VCS" == "gitlab" ]]; then P_PR_TOOL="glab"
fi

# Notifications
section "Team Notifications"
hint "Send a message to Slack/Teams/Discord when HIVE finishes delivering or hits an error."
echo ""
_ask "Webhook URL (leave empty to skip)" ""
P_WEBHOOK="$REPLY"

# Verify commands
section "Build & Test Commands"
hint "Commands that agents run before every commit."
echo ""

P_TEST="" P_TYPECHECK="" P_LINT="" P_BUILD=""

case "$P_STACK" in
    node-react-prisma)
        _ask "Test command" "npm test"
        P_TEST="$REPLY"
        _ask "Type check command" "npm run typecheck"
        P_TYPECHECK="$REPLY"
        _ask "Lint command" "npm run lint"
        P_LINT="$REPLY"
        _ask "Build command" "npm run build"
        P_BUILD="$REPLY"
        ;;
    python-fastapi)
        _ask "Test command" "pytest"
        P_TEST="$REPLY"
        _ask "Type check command" "mypy src/"
        P_TYPECHECK="$REPLY"
        _ask "Lint command" "ruff check ."
        P_LINT="$REPLY"
        _ask "Build command (leave empty if none)" ""
        P_BUILD="${REPLY:-null}"
        ;;
    dotnet)
        _ask "Test command" "dotnet test"
        P_TEST="$REPLY"
        _ask "Type check / build command" "dotnet build"
        P_TYPECHECK="$REPLY"
        _ask "Lint command" "dotnet format --verify-no-changes"
        P_LINT="$REPLY"
        _ask "Build command" "dotnet build --configuration Release"
        P_BUILD="$REPLY"
        ;;
    java-spring)
        _ask "Test command" "mvn test"
        P_TEST="$REPLY"
        _ask "Type check / compile command" "mvn compile"
        P_TYPECHECK="$REPLY"
        _ask "Lint command" "mvn checkstyle:check"
        P_LINT="$REPLY"
        _ask "Build command" "mvn package -DskipTests"
        P_BUILD="$REPLY"
        ;;
    go)
        _ask "Test command" "go test ./..."
        P_TEST="$REPLY"
        _ask "Type check / build command" "go build ./..."
        P_TYPECHECK="$REPLY"
        _ask "Lint command" "golangci-lint run"
        P_LINT="$REPLY"
        _ask "Build command" "go build -o bin/app ."
        P_BUILD="$REPLY"
        ;;
    *)
        _ask "Test command" ""
        P_TEST="${REPLY:-null}"
        _ask "Type check command (leave empty if none)" ""
        P_TYPECHECK="${REPLY:-null}"
        _ask "Lint command (leave empty if none)" ""
        P_LINT="${REPLY:-null}"
        _ask "Build command (leave empty if none)" ""
        P_BUILD="${REPLY:-null}"
        ;;
esac

# ── Preview ───────────────────────────────────────────────────
echo ""
section "Review"
echo ""
printf "  %-25s %s\n" "Project:"          "${P_NAME:-—}"
printf "  %-25s %s\n" "Tech Lead:"        "${P_TECH_LEAD:-—}"
printf "  %-25s %s\n" "Stack:"            "${P_STACK}"
printf "  %-25s %s\n" "Autonomy:"         "${P_AUTONOMY}"
printf "  %-25s %s\n" "Language:"         "${P_LANG}"
printf "  %-25s %s\n" "Style:"            "${P_STYLE}"
printf "  %-25s %s\n" "Ticket tool:"      "${P_TICKET_TOOL}"
printf "  %-25s %s\n" "VCS:"              "${P_VCS} (${P_BRANCH})"
printf "  %-25s %s\n" "Notifications:"    "${P_WEBHOOK:-(disabled)}"
echo ""
printf "  ${CYAN}?${NC} Write config to ${BOLD}$CONFIG_FILE${NC}? [Y/n]: "
read -r CONFIRM
[[ "$CONFIRM" == "n" || "$CONFIRM" == "N" ]] && { echo "  Aborted. No changes made."; echo ""; exit 0; }

# ── Backup existing config ─────────────────────────────────────
if [[ -f "$CONFIG_FILE" ]]; then
    BACKUP="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP"
    ok "Existing config backed up: $BACKUP"
fi

# ── Write AGENTS.local.md ─────────────────────────────────────
mkdir -p "$HIVE_DIR"

HIVE_VERSION_FILE="$(cat "${FACTORY_ROOT:-$SCRIPT_DIR/..}/VERSION" 2>/dev/null || echo "dev")"

cat > "$CONFIG_FILE" << EOF
# AGENTS.local.md — Project Configuration
# Generated by hive-config.sh on $(date)
# Edit manually or re-run: hive config

---

## Project Identity

\`\`\`yaml
name: "${P_NAME}"
tech_lead: "${P_TECH_LEAD}"
stack: "${P_STACK}"
\`\`\`

---

## Autonomy

\`\`\`yaml
autonomy:
  level: "${P_AUTONOMY}"

  circuit_breaker:
    max_test_retries: ${P_MAX_RETRIES}
    max_new_files: ${P_MAX_FILES}
    max_tokens_per_ticket: 200000
\`\`\`

---

## Language

\`\`\`yaml
language:
  code: "en"
  communication: "${P_LANG}"
\`\`\`

---

## Persona

\`\`\`yaml
persona:
  style: "${P_STYLE}"
\`\`\`

---

## Model Profiles

\`\`\`yaml
model_profiles:
  default:
    planning:       null
    implementation: null
    review:         null

active_profile: "default"
\`\`\`

---

## Model Routing

\`\`\`yaml
model_routing:
  enabled: false
\`\`\`

---

## Ticket Provider

\`\`\`yaml
ticket_provider:
  tool: "${P_TICKET_TOOL}"
  mcp_name: "${P_TICKET_MCP}"
  board_url: "${P_BOARD_URL}"
  statuses:
    backlog:     "Backlog"
    to_refine:   "To Refine"
    refined:     "Ready"
    in_progress: "In Progress"
    in_review:   "In Review"
    done:        "Done"
    blocked:     "Blocked"
  auto_transition_after_enrich: true
  auto_transition_on_merge: true
  auto_delete_branch: true
  ticket_transitions:
    mode: "minimal"
    auto_merge_pr: false
\`\`\`

---

## Version Control

\`\`\`yaml
vcs:
  platform: "${P_VCS}"
  mcp_name: "$([ "$P_VCS" = "github" ] && echo "GitHub" || echo "none")"
  default_base_branch: "${P_BRANCH}"
  branch_pattern: "${P_BRANCH_PATTERN}"
  pr_tool: "${P_PR_TOOL}"
  ai_trailer: true
\`\`\`

---

## Team Notifications

\`\`\`yaml
notifications:
  webhook: "${P_WEBHOOK}"
  on_delivery:        true
  on_circuit_breaker: true
  on_sprint_close:    true
  on_ship_complete:   false
\`\`\`

---

## Build & Verification Commands

\`\`\`yaml
verify_commands:
  test:      "${P_TEST}"
  typecheck: "${P_TYPECHECK}"
  lint:      "${P_LINT}"
  coverage:  null
  build:     "${P_BUILD}"
\`\`\`

---

## Fallback Behavior

\`\`\`yaml
fallbacks:
  ticket_unavailable: "ask"
  design_unavailable: "ask"
\`\`\`

---

## HIVE Version

\`\`\`yaml
hive:
  version: "${HIVE_VERSION_FILE}"
\`\`\`
EOF

echo ""
ok "Config written: $CONFIG_FILE"

# ── Sync .claude/settings.json if autonomy changed ────────────
CLAUDE_SETTINGS="$(dirname "$HIVE_DIR")/.claude/settings.json"
if [[ -f "$CLAUDE_SETTINGS" ]]; then
    case "$P_AUTONOMY" in
        autonomous) NEW_MODE="bypassPermissions" ;;
        *)          NEW_MODE="acceptEdits" ;;
    esac
    python3 - "$CLAUDE_SETTINGS" "$NEW_MODE" <<'PYEOF'
import json, sys
f, mode = sys.argv[1], sys.argv[2]
try:
    cfg = json.load(open(f))
except Exception:
    cfg = {}
if cfg.get("defaultMode") != mode:
    cfg["defaultMode"] = mode
    with open(f, "w") as fh:
        json.dump(cfg, fh, indent=2); fh.write("\n")
    print(f"synced: {mode}")
else:
    print(f"already: {mode}")
PYEOF
    MODE_RESULT=$?
    [[ $MODE_RESULT -eq 0 ]] && ok ".claude/settings.json defaultMode → ${NEW_MODE}"
fi

echo ""
printf "  Next steps:\n"
printf "    ${DIM}1.${NC} Review: ${BOLD}cat $CONFIG_FILE${NC}\n"
printf "    ${DIM}2.${NC} Open your AI tool and run: ${BOLD}/status${NC}\n"
printf "    ${DIM}3.${NC} Edit $CONFIG_FILE for any advanced settings\n"
echo ""

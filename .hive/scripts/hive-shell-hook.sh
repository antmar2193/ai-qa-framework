#!/usr/bin/env bash
# ============================================================
# hive-shell-hook.sh — HIVE auto-detection for shell sessions
#
# Detects when you enter a HIVE project directory and:
#   - Prints a one-line status banner
#   - Exports HIVE_PROJECT_DIR and HIVE_ACTIVE env vars
#     (picked up by any CLI tool started from that shell)
#
# Install — add ONE of these to ~/.bashrc or ~/.zshrc:
#
#   source /path/to/hive/scripts/hive-shell-hook.sh
#
# Or for a single project (no global install):
#   echo 'source /path/to/hive/scripts/hive-shell-hook.sh' >> ~/.zshrc
#
# Test it:
#   cd /your/hive-project && echo $HIVE_ACTIVE   # → 1
#   cd /tmp                && echo $HIVE_ACTIVE   # → 0
# ============================================================

_hive_detect() {
    # Walk up from current dir (max 5 levels) to find the project root
    local dir; dir="$(pwd)"
    local config=""
    local depth=0
    while [[ "$dir" != "/" && $depth -lt 5 ]]; do
        if [[ -f "$dir/.hive/AGENTS.local.md" ]]; then
            config="$dir/.hive/AGENTS.local.md"
            break
        fi
        dir="$(dirname "$dir")"
        depth=$((depth + 1))
    done

    if [[ -n "$config" ]]; then
        # Extract config values — awk used for BSD grep compatibility (macOS)
        local project; project=$(awk -F'"' '/^name:/ { print $2; exit }' "$config" 2>/dev/null)
        [[ -z "$project" ]] && project=$(awk '/^name:/ { sub(/^name:[[:space:]]*/,""); sub(/[[:space:]].*/,""); print; exit }' "$config" 2>/dev/null)
        local stack; stack=$(awk -F'"' '/^stack:/ { print $2; exit }' "$config" 2>/dev/null)
        [[ -z "$stack" ]] && stack=$(awk '/^stack:/ { sub(/^stack:[[:space:]]*/,""); sub(/[[:space:]].*/,""); print; exit }' "$config" 2>/dev/null)
        local autonomy; autonomy=$(awk -F'"' '/level:/ { print $2; exit }' "$config" 2>/dev/null)
        local profile; profile=$(awk -F'"' '/active_profile:/ { print $2; exit }' "$config" 2>/dev/null)
        local version; version=$(awk -F'"' '/^  version:/ { print $2; exit }' "$config" 2>/dev/null)

        # Defaults for optional fields
        project="${project:-unknown}"
        stack="${stack:-custom}"
        autonomy="${autonomy:-supervised}"
        profile="${profile:-default}"
        version="${version:-}"

        local ver_str=""
        [[ -n "$version" ]] && ver_str=" $version"

        # Export env vars (available to any CLI started from this shell)
        export HIVE_ACTIVE=1
        HIVE_PROJECT_DIR="$dir"; export HIVE_PROJECT_DIR
        export HIVE_PROJECT_NAME="$project"
        export HIVE_STACK="$stack"
        export HIVE_AUTONOMY="$autonomy"
        export HIVE_PROFILE="$profile"

        # Print banner (suppressed when in non-interactive shell)
        if [[ -t 1 ]]; then
            printf '\033[0;36m[HIVE%s]\033[0m %s · %s · %s · profile: %s\n' \
                "$ver_str" "$project" "$stack" "$autonomy" "$profile"
        fi
    else
        export HIVE_ACTIVE=0
        unset HIVE_PROJECT_DIR HIVE_PROJECT_NAME HIVE_STACK HIVE_AUTONOMY HIVE_PROFILE
    fi
}

# Public status command — call from anywhere: hive-status
hive-status() {
    if [[ "$HIVE_ACTIVE" == "1" && -n "$HIVE_PROJECT_DIR" ]]; then
        local config="$HIVE_PROJECT_DIR/.hive/AGENTS.local.md"
        local version; version=$(awk -F'"' '/^  version:/ { print $2; exit }' "$config" 2>/dev/null)
        local ver_str=""; [[ -n "$version" ]] && ver_str=" $version"

        printf '\033[0;36m[HIVE%s]\033[0m %s · %s · %s · profile: %s\n' \
            "$ver_str" "$HIVE_PROJECT_NAME" "$HIVE_STACK" "$HIVE_AUTONOMY" "$HIVE_PROFILE"
        printf '  dir: %s\n' "$HIVE_PROJECT_DIR"
    else
        # Re-run detection in case user switched directory without hook
        _hive_detect
        if [[ "$HIVE_ACTIVE" != "1" ]]; then
            printf '\033[1;33m[HIVE]\033[0m No HIVE project detected in current directory\n'
        fi
    fi
}

# Public dashboard command — call from anywhere: hive-dashboard [--watch[=N]]
hive-dashboard() {
    local script=""
    # Prefer project-local copy, fall back to factory copy
    if [[ "${HIVE_ACTIVE:-0}" == "1" && -f "${HIVE_PROJECT_DIR}/.hive/scripts/hive-dashboard.sh" ]]; then
        script="${HIVE_PROJECT_DIR}/.hive/scripts/hive-dashboard.sh"
    elif [[ -f "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/hive-dashboard.sh" ]]; then
        script="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/hive-dashboard.sh"
    else
        printf 'hive-dashboard: script not found. Run sync-standards.sh to install it.\n' >&2
        return 1
    fi
    bash "$script" "$@"
}

# ── Unified hive CLI ─────────────────────────────────────────
# Resolve factory root once at source time (works even if user moves around)
_HIVE_FACTORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/.."

hive() {
    bash "$_HIVE_FACTORY_ROOT/scripts/hive.sh" "$@"
}

# Override cd to run detection on every directory change
# Works in both bash and zsh
if [[ -n "$ZSH_VERSION" ]]; then
    # zsh: use chpwd hook (runs after every cd)
    autoload -Uz add-zsh-hook
    add-zsh-hook chpwd _hive_detect
else
    # bash: override cd builtin
    cd() {
        builtin cd "$@" && _hive_detect
    }
fi

# Run detection immediately (in case shell was opened inside a HIVE project)
_hive_detect

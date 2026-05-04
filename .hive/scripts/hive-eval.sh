#!/usr/bin/env bash
# ============================================================
# hive-eval.sh — Structural eval runner for HIVE commands
#
# Validates that command outputs (golden files or real LLM outputs)
# match the required structural schema for their command.
# Does NOT call any LLM — runs entirely on pre-committed files.
#
# Usage:
#   ./scripts/hive-eval.sh                             Validate all golden files
#   ./scripts/hive-eval.sh validate <file> <command>   Validate one file
#   ./scripts/hive-eval.sh check-fixtures              Validate all fixture YAML
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVALS_DIR="$REPO_ROOT/evals"
SCHEMAS_DIR="$EVALS_DIR/schemas"
GOLDEN_DIR="$EVALS_DIR/golden"
FIXTURES_DIR="$EVALS_DIR/fixtures"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; ERRORS=$((ERRORS+1)); }
warn()  { echo -e "  ${YELLOW}!${NC} $1"; }
info()  { echo -e "  ${CYAN}→${NC} $1"; }
ERRORS=0

# ── Validate one output file against a schema ─────────────────
validate_against_schema() {
    local output_file="$1"
    local command="$2"
    local schema_file="$SCHEMAS_DIR/${command}.schema.yml"

    if [[ ! -f "$output_file" ]]; then
        fail "Output file not found: $output_file"
        return
    fi

    if [[ ! -f "$schema_file" ]]; then
        warn "No schema for command '$command' — skipping structural check"
        return
    fi

    local label
    label="$(basename "$output_file") [/$command]"

    # ── Min lines ─────────────────────────────────────────────
    local min_lines
    min_lines=$(grep -oE 'min_lines:\s*[0-9]+' "$schema_file" 2>/dev/null | grep -oE '[0-9]+' || echo "0")
    local actual_lines
    actual_lines=$(grep -c '[^[:space:]]' "$output_file" 2>/dev/null || echo "0")
    if [[ "$min_lines" -gt 0 && "$actual_lines" -lt "$min_lines" ]]; then
        fail "$label — too short: $actual_lines lines (minimum $min_lines)"
        return
    fi

    # ── Required sections ─────────────────────────────────────
    local section_errors=0
    while IFS= read -r section; do
        # Strip leading "  - " and surrounding quotes
        section=$(echo "$section" | sed 's/^[[:space:]]*-[[:space:]]*//' | tr -d '"'"'" | xargs)
        [[ -z "$section" ]] && continue
        if ! grep -qiE "$section" "$output_file" 2>/dev/null; then
            fail "$label — missing required section: '$section'"
            section_errors=$((section_errors+1))
        fi
    done < <(awk '/^required_sections:/,/^[a-z]/' "$schema_file" | grep '^\s*-')

    # ── Required patterns ─────────────────────────────────────
    while IFS= read -r pattern; do
        pattern=$(echo "$pattern" | sed 's/^[[:space:]]*-[[:space:]]*//' | tr -d '"'"'" | xargs)
        [[ -z "$pattern" ]] && continue
        if ! grep -qiE "$pattern" "$output_file" 2>/dev/null; then
            fail "$label — missing required pattern: '$pattern'"
            section_errors=$((section_errors+1))
        fi
    done < <(awk '/^required_patterns:/,/^[a-z]/' "$schema_file" | grep '^\s*-')

    [[ $section_errors -eq 0 ]] && pass "$label"
}

# ── check-fixtures: validate all fixture YAML ─────────────────
check_fixtures() {
    echo ""
    echo "Fixture validation:"
    if ! command -v python3 &>/dev/null; then
        warn "python3 not found — skipping fixture YAML validation"
        return
    fi
    local fixture_errors=0
    while IFS= read -r -d '' f; do
        rel="${f#$REPO_ROOT/}"
        if python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>/dev/null; then
            pass "$rel"
        else
            fail "$rel — invalid YAML"
            fixture_errors=$((fixture_errors+1))
        fi
    done < <(find "$FIXTURES_DIR" -name "*.yml" -print0 2>/dev/null)
    return $fixture_errors
}

# ── validate: single file ─────────────────────────────────────
if [[ "${1:-}" == "validate" ]]; then
    shift
    output_file="${1:-}"
    command="${2:-}"
    [[ -z "$output_file" || -z "$command" ]] && {
        echo "Usage: $0 validate <output-file> <command>"
        exit 1
    }
    echo ""
    validate_against_schema "$output_file" "$command"
    echo ""
    [[ $ERRORS -eq 0 ]] && echo -e "  ${GREEN}✓ Passed${NC}" || { echo -e "  ${RED}✗ $ERRORS violation(s)${NC}"; exit 1; }
    echo ""
    exit 0
fi

# ── check-fixtures: standalone ────────────────────────────────
if [[ "${1:-}" == "check-fixtures" ]]; then
    check_fixtures
    echo ""
    [[ $ERRORS -eq 0 ]] && echo -e "  ${GREEN}✓ All fixtures valid${NC}" || { echo -e "  ${RED}✗ $ERRORS error(s)${NC}"; exit 1; }
    echo ""
    exit 0
fi

# ── Default: validate all golden files ────────────────────────
echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║   HIVE — Eval Suite                       ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

check_fixtures

echo ""
echo "Golden file validation:"

GOLDEN_COUNT=0
while IFS= read -r -d '' golden_file; do
    # Derive command from parent directory name
    command=$(basename "$(dirname "$golden_file")")
    validate_against_schema "$golden_file" "$command"
    GOLDEN_COUNT=$((GOLDEN_COUNT+1))
done < <(find "$GOLDEN_DIR" -name "*.md" -print0 2>/dev/null | sort -z)

if [[ $GOLDEN_COUNT -eq 0 ]]; then
    warn "No golden files found in $GOLDEN_DIR"
fi

echo ""
echo "╔═══════════════════════════════════════════╗"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "║  ${GREEN}✓ All evals passed${NC} ($GOLDEN_COUNT golden files)"
else
    echo -e "║  ${RED}✗ $ERRORS violation(s)${NC}"
fi
echo "╚═══════════════════════════════════════════╝"
echo ""

[[ $ERRORS -gt 0 ]] && exit 1 || exit 0

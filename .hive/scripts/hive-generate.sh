#!/usr/bin/env bash
# ============================================================
# hive-generate.sh — Zero-LLM DDD entity scaffolding
#
# Creates boilerplate stub files for a DDD entity using the
# templates defined in .hive/generate.yml (or a custom skill).
# Consumes ZERO LLM tokens — pure mechanical scaffolding via
# template substitution and file creation.
#
# The agent calls this first, then only fills in:
#   - Entity fields / schema
#   - Method implementations (business logic)
#   - Test cases (Given/When/Then from acceptance criteria)
#
# Usage (run from project root, not from hive/):
#   bash .hive/scripts/hive-generate.sh <EntityName>
#   bash .hive/scripts/hive-generate.sh <EntityName> --area backend
#   bash .hive/scripts/hive-generate.sh <EntityName> --area frontend
#   bash .hive/scripts/hive-generate.sh <EntityName> --dry-run
#   bash .hive/scripts/hive-generate.sh <EntityName> --skill <skill-name>
#
# Naming substitutions in templates and paths:
#   {Entity}       → PascalCase:     PaymentOrder
#   {entity}       → naming.var conv: paymentOrder (camel) or payment_order (snake)
#   {entity_camel} → always camelCase: paymentOrder
#   {entity_snake} → always snake_case: payment_order
#   {entity_kebab} → always kebab-case: payment-order
#   {entity_file}  → naming.file conv (used in paths)
#   {entity_scream}→ SCREAMING_SNAKE: PAYMENT_ORDER
#   {Entities}     → plural PascalCase: PaymentOrders
#   {entities}     → plural naming.var: paymentOrders (camel) or payment_orders (snake)
#
# Exit codes:
#   0 — files created (or dry-run OK)
#   1 — error (missing args, no generate.yml, python3 unavailable)
# ============================================================

set -euo pipefail

ENTITY="${1:-}"
AREA=""
DRY_RUN=false
SKILL=""

if [[ -z "$ENTITY" ]]; then
    echo "Usage: $0 <EntityName> [--area backend|frontend] [--dry-run] [--skill <name>]"
    exit 1
fi

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --area)    AREA="$2";   shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --skill)   SKILL="$2";  shift 2 ;;
        *)         shift ;;
    esac
done

if ! command -v python3 &>/dev/null; then
    echo "python3 is required — install it or run /generate manually"
    exit 1
fi

python3 - "$ENTITY" "$AREA" "$DRY_RUN" "$SKILL" <<'PYEOF'
import sys, os, re, yaml

entity_pascal = sys.argv[1]
area_filter   = sys.argv[2]   # "" | "backend" | "frontend"
dry_run       = sys.argv[3] == "true"
skill_name    = sys.argv[4]

# Validate entity name: must be PascalCase identifier
if not re.match(r'^[A-Z][a-zA-Z0-9]*$', entity_pascal):
    print(f"  ✗ EntityName must be PascalCase (e.g. 'PaymentOrder'). Got: {entity_pascal}")
    sys.exit(1)

BACKEND_AREAS  = {"domain", "application", "infrastructure", "presentation", "tests"}
FRONTEND_AREAS = {"frontend"}

# ── Naming variants ───────────────────────────────────────────
def to_snake(s):
    s1 = re.sub(r'(.)([A-Z][a-z]+)', r'\1_\2', s)
    return re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', s1).lower()

entity_snake  = to_snake(entity_pascal)
entity_kebab  = entity_snake.replace('_', '-')
entity_camel  = entity_pascal[0].lower() + entity_pascal[1:]
entity_scream = entity_snake.upper()
entities_pascal = entity_pascal + 's'
entities_camel  = entity_camel + 's'
entities_snake  = entity_snake + 's'

# ── Locate config file ─────────────────────────────────────────
config_path = None
if skill_name:
    for p in [
        f".hive/.skills/{skill_name}.yml",
        f".hive/.skills/{skill_name}.yaml",
    ]:
        if os.path.exists(p):
            config_path = p
            break
    if not config_path:
        print(f"  ✗ Skill not found: .hive/.skills/{skill_name}.yml")
        sys.exit(1)
else:
    for p in [".hive/generate.yml", ".hive/generate.yaml", "generate.yml"]:
        if os.path.exists(p):
            config_path = p
            break

if not config_path:
    print("  ✗ No generate.yml found at .hive/generate.yml")
    print("    Run: bash .hive/scripts/sync-standards.sh . to sync from the factory")
    sys.exit(1)

with open(config_path) as f:
    config = yaml.safe_load(f)

if not config:
    print(f"  ✗ {config_path} is empty or invalid YAML")
    sys.exit(1)

naming    = config.get('naming', {})
file_conv = naming.get('file', 'snake')
var_conv  = naming.get('var', 'snake')

# Resolve context-dependent variants
if file_conv == 'kebab':
    entity_file     = entity_kebab
    entities_file   = entities_camel.lower()  # simple plural for route paths
elif file_conv == 'pascal':
    entity_file     = entity_pascal
    entities_file   = entities_pascal
elif file_conv == 'camel':
    entity_file     = entity_camel
    entities_file   = entities_camel
else:  # snake
    entity_file     = entity_snake
    entities_file   = entities_snake

if var_conv == 'camel':
    entity_var   = entity_camel
    entities_var = entities_camel
else:  # snake
    entity_var   = entity_snake
    entities_var = entities_snake

# ── Template substitution (regex-based, no substring conflicts) ──
# Used for BOTH paths and template content — always the full map.
# Keys ordered so more-specific patterns (entity_camel) are tried before
# less-specific ones (entity). The regex alternation handles this, but
# ordering matters for the dict repr used in the pattern.
_subst_map = {
    'entity_camel':  entity_camel,
    'entity_snake':  entity_snake,
    'entity_kebab':  entity_kebab,
    'entity_file':   entity_file,
    'entity_scream': entity_scream,
    'Entities':      entities_pascal,
    'entities':      entities_var,
    'Entity':        entity_pascal,
    'entity':        entity_file,   # {entity} in paths = naming.file conv; in templates = naming.var conv
}
# For template content, {entity} = naming.var (camel or snake), not file conv
_tpl_map = dict(_subst_map)
_tpl_map['entity'] = entity_var

_subst_re = re.compile(r'\{(' + '|'.join(re.escape(k) for k in _subst_map) + r')\}')
_tpl_re   = re.compile(r'\{(' + '|'.join(re.escape(k) for k in _tpl_map) + r')\}')

def subst_path(text):
    return _subst_re.sub(lambda m: _subst_map[m.group(1)], text)

def subst_template(text):
    return _tpl_re.sub(lambda m: _tpl_map[m.group(1)], text)

templates    = config.get('templates', {})
entity_files = config.get('entity_files', {})

# ── Filter by area ─────────────────────────────────────────────
filtered = {}
for area, files in entity_files.items():
    if area_filter == 'backend' and area not in BACKEND_AREAS:
        continue
    if area_filter == 'frontend' and area not in FRONTEND_AREAS:
        continue
    filtered[area] = files

if not filtered:
    msg = f" for area '{area_filter}'" if area_filter else ""
    print(f"  ✗ No files to generate{msg}")
    sys.exit(1)

# ── Main loop ─────────────────────────────────────────────────
GREEN = "\033[0;32m"; YELLOW = "\033[1;33m"; CYAN = "\033[0;36m"
RED = "\033[0;31m"; BOLD = "\033[1m"; NC = "\033[0m"

area_label = f" [{area_filter}]" if area_filter else ""
print(f"\n{BOLD}HIVE Generate — {entity_pascal}{area_label}{NC}")
print(f"  Config : {config_path}")
if dry_run:
    print(f"  Mode   : {YELLOW}dry-run — no files written{NC}")
print()

files_created   = []
files_skipped   = []
files_templated = []
files_empty     = []

for area, file_specs in filtered.items():
    print(f"  {CYAN}{area}{NC}")
    for spec in file_specs:
        rel_path = subst_path(spec['path'])
        tpl_name = spec.get('template', '')
        tpl_body = templates.get(tpl_name, '') if tpl_name else ''
        has_tpl  = bool(tpl_body)

        if os.path.exists(rel_path):
            files_skipped.append(rel_path)
            print(f"    {YELLOW}skip{NC}   {rel_path} (already exists)")
            continue

        if dry_run:
            note = f" [{tpl_name}]" if tpl_name else " [no template — will create empty stub]"
            print(f"    {CYAN}create{NC} {rel_path}{note}")
            files_created.append(rel_path)
            continue

        # Create directories
        parent = os.path.dirname(rel_path)
        if parent:
            os.makedirs(parent, exist_ok=True)

        if has_tpl:
            content = subst_template(tpl_body)
            # Ensure newline at end of file
            if content and not content.endswith('\n'):
                content += '\n'
            files_templated.append(rel_path)
        else:
            # Minimal stub — marks clearly what the agent needs to fill in
            content = f"# TODO({entity_pascal}): implement — generated by hive-generate.sh\n"
            files_empty.append(rel_path)

        with open(rel_path, 'w') as fh:
            fh.write(content)

        status_color = GREEN if has_tpl else YELLOW
        tpl_note = f" [{tpl_name}]" if tpl_name else " [stub — no template]"
        print(f"    {status_color}✓{NC}     {rel_path}{tpl_note}")
        files_created.append(rel_path)

    print()

# ── Summary ────────────────────────────────────────────────────
total_created = len(files_created)
total_skipped = len(files_skipped)

print(f"  {BOLD}Summary:{NC} {total_created} created  ·  {total_skipped} skipped")

if files_empty:
    print(f"\n  {YELLOW}!{NC} {len(files_empty)} file(s) had no template — add templates: section to generate.yml:")
    for f in files_empty:
        print(f"    {f}")

if total_created > 0 and not dry_run:
    print(f"""
  {BOLD}What the script created:{NC}
  - Directories and file stubs for all DDD layers
  - Named and organized correctly for the {config_path} stack

  {BOLD}What you still need to do (agent tasks):{NC}
  - Add entity fields / schema to the domain stub
  - Add repository method signatures matching your use cases
  - Run /tdd <ticket> — write failing tests from acceptance criteria
  - Run /dev-be <ticket> — implement the business logic
""")
PYEOF

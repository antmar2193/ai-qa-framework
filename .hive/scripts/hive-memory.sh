#!/usr/bin/env bash
# ============================================================
# hive-memory.sh — HIVE Persistent Memory System
#
# File-based persistent memory for cross-session agent context.
# Git-committable. No external dependencies.
#
# Usage:
#   ./scripts/hive-memory.sh save    --topic-key <key> --content <text> [--type <type>] [--tags <tag1,tag2>]
#   ./scripts/hive-memory.sh search  <query>
#   ./scripts/hive-memory.sh get     <id>
#   ./scripts/hive-memory.sh context [--limit <n>]
#   ./scripts/hive-memory.sh session-summary --content <text>
#   ./scripts/hive-memory.sh list    [--type <type>]
#   ./scripts/hive-memory.sh delete  <id>
#
# Storage layout:
#   .hive/memory/observations/{id}.json  — one file per observation
#   .hive/memory/sessions/YYYY-MM-DD.json — end-of-session summaries
#   .hive/memory/index.tsv               — id<TAB>topic_key<TAB>type<TAB>title (fast grep)
#
# Upsert behavior:
#   Same topic_key + project → updates the existing observation instead of creating a new one
#
# Valid types: architecture, decision, pattern, plan, session, context, note
# ============================================================

set -euo pipefail

# shellcheck source=lib/require-python3.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/require-python3.sh"

# (SCRIPT_DIR not needed — hive-memory.sh resolves project root independently)

# ── Locate project root ────────────────────────────────────────
# Prefer the directory passed as --project, otherwise walk up from cwd
PROJECT_PATH="${HIVE_PROJECT:-}"
if [[ -z "$PROJECT_PATH" ]]; then
    SEARCH_DIR="$(pwd)"
    while [[ "$SEARCH_DIR" != "/" ]]; do
        [[ -d "$SEARCH_DIR/.hive" ]] && { PROJECT_PATH="$SEARCH_DIR"; break; }
        SEARCH_DIR="$(dirname "$SEARCH_DIR")"
    done
fi
[[ -z "$PROJECT_PATH" || ! -d "$PROJECT_PATH/.hive" ]] && {
    echo "Error: not inside a HIVE project (no .hive/ found)" >&2
    exit 1
}

MEMORY_DIR="$PROJECT_PATH/.hive/memory"
OBS_DIR="$MEMORY_DIR/observations"
SESSION_DIR="$MEMORY_DIR/sessions"
INDEX_FILE="$MEMORY_DIR/index.tsv"

mkdir -p "$OBS_DIR" "$SESSION_DIR"
[[ -f "$INDEX_FILE" ]] || touch "$INDEX_FILE"

# Detect project name from git remote or directory
PROJECT_NAME=""
if command -v git &>/dev/null; then
    PROJECT_NAME=$(git -C "$PROJECT_PATH" remote get-url origin 2>/dev/null \
        | sed 's/.*[:/]\([^/]*\)\.git$/\1/' \
        | sed 's/.*[:/]\([^/]*\)$/\1/' || echo "")
fi
[[ -z "$PROJECT_NAME" ]] && PROJECT_NAME="$(basename "$PROJECT_PATH")"

# ── Helpers ───────────────────────────────────────────────────
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ; }
today()   { date +%Y-%m-%d; }

short_id() {
    local input="$1"
    # SHA-256 of topic_key+project, first 8 chars
    echo "${input}" | sha256sum 2>/dev/null | cut -c1-8 \
    || echo "${input}" | shasum -a 256 2>/dev/null | cut -c1-8 \
    || echo "${input}" | md5sum 2>/dev/null | cut -c1-8 \
    || echo "${input}" | md5 2>/dev/null | cut -c1-8 \
    || printf '%08x' "$(echo -n "${input}" | cksum | cut -d' ' -f1)"
}

json_escape() {
    # Escape a string for JSON embedding
    python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
    || printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n' | sed 's/\\n$//'
}

write_observation() {
    local id="$1"
    local topic_key="$2"
    local title="$3"
    local type="$4"
    local content="$5"
    local tags="$6"
    local created_at="$7"
    local version="$8"

    local updated_at
    updated_at=$(now_iso)
    local obs_file="$OBS_DIR/$id.json"

    # Convert tags CSV to JSON array
    local tags_json
    if [[ -n "$tags" ]]; then
        tags_json=$(python3 -c "import json; print(json.dumps([t.strip() for t in '${tags}'.split(',') if t.strip()]))" 2>/dev/null || echo "[]")
    else
        tags_json="[]"
    fi

    # Write JSON using python3 to handle all escaping correctly
    python3 - <<PYEOF
import json, os

data = {
    "id": "${id}",
    "title": "${title}",
    "topic_key": "${topic_key}",
    "type": "${type}",
    "project": "${PROJECT_NAME}",
    "content": """${content}""",
    "tags": json.loads("""${tags_json}"""),
    "created_at": "${created_at}",
    "updated_at": "${updated_at}",
    "version": ${version}
}

with open("${obs_file}", "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("ok")
PYEOF
}

update_index() {
    local id="$1"
    local topic_key="$2"
    local type="$3"
    local title="$4"

    # Remove old entry for this id if it exists
    if [[ -f "$INDEX_FILE" ]]; then
        local tmp
        tmp=$(mktemp)
        grep -v "^${id}	" "$INDEX_FILE" > "$tmp" 2>/dev/null || true
        mv "$tmp" "$INDEX_FILE"
    fi

    # Append new entry
    printf '%s\t%s\t%s\t%s\n' "$id" "$topic_key" "$type" "$title" >> "$INDEX_FILE"
}

find_by_topic_key() {
    local topic_key="$1"
    # Search index for exact topic_key match (column 2), same project
    local match=""
    while IFS=$'\t' read -r id tk tp title; do
        if [[ "$tk" == "$topic_key" ]]; then
            # Verify it's for the same project
            if [[ -f "$OBS_DIR/$id.json" ]]; then
                local proj
                proj=$(python3 -c "import json; d=json.load(open('${OBS_DIR}/${id}.json')); print(d.get('project',''))" 2>/dev/null || echo "")
                if [[ "$proj" == "$PROJECT_NAME" ]]; then
                    match="$id"
                    break
                fi
            fi
        fi
    done < "$INDEX_FILE" 2>/dev/null || true
    echo "$match"
}

# ── Command: save ──────────────────────────────────────────────
cmd_save() {
    local topic_key=""
    local content=""
    local type="note"
    local tags=""
    local title=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --topic-key) topic_key="$2"; shift 2 ;;
            --content)   content="$2";   shift 2 ;;
            --type)      type="$2";      shift 2 ;;
            --tags)      tags="$2";      shift 2 ;;
            --title)     title="$2";     shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$topic_key" || -z "$content" ]]; then
        echo "Usage: hive-memory.sh save --topic-key <key> --content <text> [--type <type>] [--tags <t1,t2>]" >&2
        exit 1
    fi

    [[ -z "$title" ]] && title="$topic_key"

    # Check for existing observation with same topic_key + project (upsert)
    local existing_id
    existing_id=$(find_by_topic_key "$topic_key")

    local id created_at version

    if [[ -n "$existing_id" ]]; then
        # Update existing
        id="$existing_id"
        created_at=$(python3 -c "import json; d=json.load(open('${OBS_DIR}/${id}.json')); print(d['created_at'])" 2>/dev/null || now_iso)
        version=$(python3 -c "import json; d=json.load(open('${OBS_DIR}/${id}.json')); print(d.get('version',1)+1)" 2>/dev/null || echo "2")
        write_observation "$id" "$topic_key" "$title" "$type" "$content" "$tags" "$created_at" "$version"
        update_index "$id" "$topic_key" "$type" "$title"
        echo "updated: $id (v$version)"
    else
        # Create new
        id=$(short_id "${topic_key}${PROJECT_NAME}")
        # Handle collision: append counter if needed
        local counter=0
        while [[ -f "$OBS_DIR/$id.json" ]]; do
            counter=$((counter + 1))
            id=$(short_id "${topic_key}${PROJECT_NAME}${counter}")
        done
        created_at=$(now_iso)
        version=1
        write_observation "$id" "$topic_key" "$title" "$type" "$content" "$tags" "$created_at" "$version"
        update_index "$id" "$topic_key" "$type" "$title"
        echo "saved: $id"
    fi
}

# ── Command: search ────────────────────────────────────────────
cmd_search() {
    local query="${1:-}"
    local limit=10
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit) limit="$2"; shift 2 ;;
            *) [[ -z "$query" ]] && query="$1"; shift ;;
        esac
    done

    if [[ -z "$query" ]]; then
        echo "Usage: hive-memory.sh search <query> [--limit <n>]" >&2
        exit 1
    fi

    # Delegate entirely to Python for TF-scored search
    python3 - <<PYEOF
import json, os, re, math
from pathlib import Path

obs_dir = Path("${OBS_DIR}")
index_file = Path("${INDEX_FILE}")
project = "${PROJECT_NAME}"
query_raw = "${query}"
limit = ${limit}

# Tokenize query into terms (lowercase, split on non-word chars)
terms = [t for t in re.split(r'\W+', query_raw.lower()) if len(t) >= 2]
if not terms:
    print(f"No observations found for: {query_raw}")
    exit(0)

def tf_score(obs, terms):
    """TF-based relevance score. Field weights: topic_key=10, title=5, content=1 (TF-normalized)."""
    score = 0.0
    topic_key = (obs.get("topic_key") or "").lower()
    title = obs.get("title", "").lower()
    content = obs.get("content", "").lower()
    tags = " ".join(obs.get("tags", [])).lower()

    content_words = max(len(content.split()), 1)
    title_words = max(len(title.split()), 1)

    for term in terms:
        # topic_key — exact or partial match: highest signal
        if topic_key:
            if topic_key == term:
                score += 15.0
            elif term in topic_key.split("/") or topic_key.startswith(term):
                score += 10.0
            elif term in topic_key:
                score += 6.0

        # title — TF with field weight 5
        tc = title.count(term)
        score += tc * 5.0 / title_words * 10  # normalized * weight

        # content — TF with field weight 1
        cc = content.count(term)
        if cc > 0:
            tf = cc / content_words
            score += tf * 100  # scale so tiny fractions register
            score += cc * 0.2  # raw count bonus (long docs with many matches rank up)

        # tags — bonus
        if term in tags:
            score += 3.0

    return score

# Collect candidate files (filter project first for performance)
candidates = []
for obs_path in obs_dir.glob("*.json"):
    try:
        with open(obs_path) as f:
            obs = json.load(f)
        # Skip other projects
        if obs.get("project") and obs["project"] != project:
            continue
        score = tf_score(obs, terms)
        if score > 0:
            candidates.append((score, obs))
    except Exception:
        continue

if not candidates:
    print(f"No observations found for: {query_raw}")
    exit(0)

# Sort by score descending
candidates.sort(key=lambda x: -x[0])
top = candidates[:limit]

print(f'Results for "{query_raw}" ({len(candidates)} match{"es" if len(candidates)!=1 else ""}, showing top {len(top)}):')
print()
for score, d in top:
    preview = d["content"][:150].replace("\n", " ")
    if len(d["content"]) > 150:
        preview += "..."
    tags = ", ".join(d.get("tags", []))
    score_str = f"  score={score:.1f}"
    print(f"  [{d['id']}] {d['type']} — {d['title']}{score_str}")
    print(f"  {d['updated_at'][:10]}  {preview}")
    if tags:
        print(f"  tags: {tags}")
    print()
PYEOF
}

# ── Command: get ───────────────────────────────────────────────
cmd_get() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo "Usage: hive-memory.sh get <id>" >&2
        exit 1
    fi

    local obs_file="$OBS_DIR/$id.json"
    if [[ ! -f "$obs_file" ]]; then
        echo "Observation not found: $id" >&2
        exit 1
    fi

    python3 - <<PYEOF
import json
with open("${obs_file}") as f:
    d = json.load(f)
print(f"ID:         {d['id']}")
print(f"Title:      {d['title']}")
print(f"Topic key:  {d['topic_key']}")
print(f"Type:       {d['type']}")
print(f"Project:    {d['project']}")
print(f"Version:    {d.get('version', 1)}")
print(f"Created:    {d['created_at']}")
print(f"Updated:    {d['updated_at']}")
if d.get("tags"):
    print(f"Tags:       {', '.join(d['tags'])}")
print()
print("Content:")
print(d["content"])
PYEOF
}

# ── Command: context ───────────────────────────────────────────
cmd_context() {
    local limit=10
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit) limit="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    echo "=== HIVE Memory Context ==="
    echo "Project: $PROJECT_NAME"
    echo ""

    # Recent sessions
    local session_count=0
    if [[ -d "$SESSION_DIR" ]]; then
        echo "Recent sessions:"
        for session_file in $(ls -t "$SESSION_DIR"/*.json 2>/dev/null | head -3); do
            python3 - <<PYEOF
import json
with open("${session_file}") as f:
    d = json.load(f)
summary = d.get("content","")[:200].replace("\n"," ")
print(f"  [{d.get('date','?')}] {summary}...")
PYEOF
            session_count=$((session_count + 1))
        done
        [[ $session_count -eq 0 ]] && echo "  (no sessions yet)"
    fi
    echo ""

    # Recent observations
    echo "Recent observations (last $limit):"
    if [[ -d "$OBS_DIR" ]]; then
        local obs_files
        obs_files=$(find "$OBS_DIR" -name "*.json" -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -"$limit" || true)
        if [[ -z "$obs_files" ]]; then
            echo "  (no observations yet)"
        else
            while IFS= read -r obs_file; do
                [[ -z "$obs_file" || ! -f "$obs_file" ]] && continue
                python3 - <<PYEOF
import json
with open("${obs_file}") as f:
    d = json.load(f)
preview = d["content"][:100].replace("\n"," ") + ("..." if len(d["content"]) > 100 else "")
print(f"  [{d['id']}] ({d['type']}) {d['title']}")
print(f"         {preview}")
PYEOF
            done <<< "$obs_files"
        fi
    fi
}

# ── Command: session-summary ───────────────────────────────────
cmd_session_summary() {
    local content=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --content) content="$2"; shift 2 ;;
            *) content="$1"; shift ;;
        esac
    done

    if [[ -z "$content" ]]; then
        echo "Usage: hive-memory.sh session-summary --content <text>" >&2
        exit 1
    fi

    local today_date
    today_date=$(today)
    local session_file="$SESSION_DIR/$today_date.json"

    # Append to today's session file (or create it)
    python3 - <<PYEOF
import json, os
from datetime import datetime

session_file = "${session_file}"
today_date = "${today_date}"
project = "${PROJECT_NAME}"
content = """${content}"""
now = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

if os.path.exists(session_file):
    with open(session_file) as f:
        d = json.load(f)
    existing = d.get("content", "")
    d["content"] = existing + "\n\n--- " + now + " ---\n" + content
    d["updated_at"] = now
else:
    d = {
        "date": today_date,
        "project": project,
        "content": content,
        "created_at": now,
        "updated_at": now
    }

with open(session_file, "w") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"session summary saved: {today_date}")
PYEOF

    # Also save as an observation for searchability
    cmd_save --topic-key "session/$today_date" --content "$content" --type "session" --title "Session $today_date"
}

# ── Command: list ──────────────────────────────────────────────
cmd_list() {
    local filter_type=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) filter_type="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ ! -f "$INDEX_FILE" ]] || [[ ! -s "$INDEX_FILE" ]]; then
        echo "No observations stored yet."
        return
    fi

    echo "Stored observations:"
    echo ""
    while IFS=$'\t' read -r id tk tp title; do
        if [[ -n "$filter_type" && "$tp" != "$filter_type" ]]; then
            continue
        fi
        local updated=""
        [[ -f "$OBS_DIR/$id.json" ]] && \
            updated=$(python3 -c "import json; d=json.load(open('${OBS_DIR}/${id}.json')); print(d['updated_at'][:10])" 2>/dev/null || echo "?")
        printf "  [%s] (%s) %s  %s\n" "$id" "$tp" "$updated" "$title"
    done < "$INDEX_FILE"
}

# ── Command: delete ────────────────────────────────────────────
cmd_delete() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo "Usage: hive-memory.sh delete <id>" >&2
        exit 1
    fi

    local obs_file="$OBS_DIR/$id.json"
    if [[ ! -f "$obs_file" ]]; then
        echo "Observation not found: $id" >&2
        exit 1
    fi

    rm "$obs_file"

    # Remove from index
    if [[ -f "$INDEX_FILE" ]]; then
        local tmp
        tmp=$(mktemp)
        grep -v "^${id}	" "$INDEX_FILE" > "$tmp" 2>/dev/null || true
        mv "$tmp" "$INDEX_FILE"
    fi

    echo "deleted: $id"
}

# ── Dispatch ───────────────────────────────────────────────────
COMMAND="${1:-}"
shift || true

case "$COMMAND" in
    save)            cmd_save "$@" ;;
    search)          cmd_search "$@" ;;
    get)             cmd_get "$@" ;;
    context)         cmd_context "$@" ;;
    session-summary) cmd_session_summary "$@" ;;
    list)            cmd_list "$@" ;;
    delete)          cmd_delete "$@" ;;
    *)
        echo "HIVE Memory System"
        echo ""
        echo "Usage:"
        echo "  hive-memory.sh save    --topic-key <key> --content <text> [--type <type>] [--tags <t1,t2>]"
        echo "  hive-memory.sh search  <query>"
        echo "  hive-memory.sh get     <id>"
        echo "  hive-memory.sh context [--limit <n>]"
        echo "  hive-memory.sh session-summary --content <text>"
        echo "  hive-memory.sh list    [--type <type>]"
        echo "  hive-memory.sh delete  <id>"
        echo ""
        echo "Types: architecture, decision, pattern, plan, session, context, note"
        exit 1
        ;;
esac

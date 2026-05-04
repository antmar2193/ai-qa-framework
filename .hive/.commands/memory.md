# /memory — Persistent Session Memory
<!-- tokens: ~850 | loads: .hive/memory/ (MCP: hive-memory) -->

**Agent:** Any
**Usage:**
```
/memory save <topic-key>        # save current context/decision to memory
/memory search <query>          # search past observations
/memory context                 # load recent session context
/memory session-summary         # save end-of-session summary
```

**Purpose:** Persist cross-session knowledge so agents don't lose context between conversations.
Stored in `.hive/memory/` — git-committable, team-shareable.

---

## Protocol

### When to save
- After architectural decisions: `/memory save arch/{feature} "chose X over Y because Z"`
- After ticket plans: `/memory save plan/{ticket} "approach: ..."`
- After discovering important patterns: `/memory save patterns/{domain} "..."`
- At session end: `/memory session-summary`

### When to load
- Session start: check `.hive/memory/sessions/` for recent context
- Before starting a ticket: search for prior work on same domain
- Before `/plan-be`: search for architectural decisions on related features

## Storage

Observations stored in `.hive/memory/observations/{id}.json`:
```json
{
  "id": "{short-hash}",
  "title": "{topic-key}",
  "topic_key": "{topic-key}",
  "type": "architecture|decision|pattern|plan|session",
  "project": "{detected from git remote or directory name}",
  "content": "...",
  "tags": [],
  "created_at": "ISO8601",
  "updated_at": "ISO8601",
  "version": 1
}
```

Same `topic_key` + `project` → update existing observation (upsert, not duplicate).

## Implementation

Prefer the `hive-memory` MCP when available. Fall back to bash when not configured.

**MCP (preferred):**
```
mem_save(title="...", content="...", topic_key="arch/payments", type="architecture")
mem_search(query="payments architecture")
mem_context()
mem_session_summary(content="...")
mem_get(id="abc12345")
mem_list(type="architecture")
```

**Bash fallback:**
```bash
bash .hive/scripts/hive-memory.sh save --topic-key "arch/payments" --content "..."
bash .hive/scripts/hive-memory.sh search "payments architecture"
bash .hive/scripts/hive-memory.sh context
bash .hive/scripts/hive-memory.sh session-summary --content "..."
```

Both use `.hive/memory/` — interchangeable. See `mcp/README.md` for MCP install instructions.

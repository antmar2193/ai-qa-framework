# /enrich — Ticket Enrichment
<!-- tokens: ~1700 | loads: analyst.md -->

**Agent:** Analyst (read `.hive/.agents/analyst.md`)
**Usage:** `/enrich <ticket-id | keywords | "the one in progress">`

---

## Process

### Step 0: Read configuration
Before anything else, read `.hive/AGENTS.local.md`:
- `ticket_provider.tool` — which system manages tickets
- `ticket_provider.mcp_name` — which MCP to call
- `ticket_provider.statuses` — the exact status names on this board
- `fallbacks.ticket_unavailable` — what to do if MCP is unavailable
- `fallbacks.ticket_paste_format` — format to request if asking user to paste

### Step 1: Get the ticket

**Option A — MCP available** (check `ticket_provider.mcp_name`):
Use the configured MCP to retrieve the ticket by ID, keywords, or status.

```
# Jira (Atlassian MCP):
getJiraIssue(ticketId)

# Linear (Linear MCP):
getIssue(issueId)

# GitHub Issues (GitHub MCP):
getIssue(owner, repo, issueNumber)
```

**Option B — MCP unavailable**:
Follow `fallbacks.ticket_unavailable`:
- If `"ask"`: Show the user the `ticket_paste_format` template from AGENTS.local.md and wait for them to paste the content. Do not proceed until you have it.
- If `"file"`: Read `.hive/changes/<ticket-id>_context.md`
- If `"skip"`: Proceed with limited context — note this in the output

**What "paste the ticket" means:**
The user copies and pastes the raw text content of the ticket from whatever tool they use. The agent will receive it as plain text and parse it. The `ticket_paste_format` template in AGENTS.local.md defines the minimum structure needed — title, description, and acceptance criteria are required; everything else is optional but helpful.

### Step 2: Read project context
- `.hive/specs/PRD.md` — business goals and constraints
- `.hive/specs/ARCHITECTURE.md` — system modules and boundaries
- `.hive/specs/api-spec.yml` (or equivalent) — existing contracts (only if ticket touches API)
- `.hive/specs/data-model.md` — data model
- `.hive/standards/` — load only the relevant area standard (`backend.mdc` OR `frontend.mdc`, not both unless the ticket explicitly touches both layers)

### Step 3: Evaluate completeness
A ticket is complete when a developer can be **fully autonomous** implementing it.
It must include:
- [ ] Clear description of the functionality
- [ ] Acceptance criteria (Given/When/Then — measurable, binary)
- [ ] List of endpoints to create/modify (method, URL, request/response shape) — only if ticket touches the API layer
- [ ] Files to modify, by layer
- [ ] Data model changes (if any)
- [ ] Steps to consider the task complete
- [ ] Documentation and test requirements
- [ ] Non-functional requirements (security, performance, validation)
- [ ] Explicit out-of-scope items

### Step 4: Size the ticket
- **S** (≤ 2h): single criterion, single layer touched
- **M** (half day): 2–4 criteria, may touch multiple layers
- **L** (full day): complex flow, multiple criteria — flag as split candidate
- **XL**: must be split — run `/split`, do not write enhanced content

**If XL:** stop here, run `/split <ticket-id>` and return the list of sub-tickets.
Do not write the enhanced section. The sub-tickets will each be enriched individually.

**If L:** write the enhanced content normally, then append a split recommendation:
```
⚠ Size L — consider splitting before implementation.
Run: /split {ticket-id}
```

### Step 5: Write the enhanced version

```markdown
## [original]
{paste original content here, unchanged}

## [enhanced]

### Summary
{1–2 sentences: what and why}

### Acceptance Criteria
Given {context}
When {action}
Then {measurable outcome}
And {additional outcome}

### Technical Scope

#### Endpoints (if applicable)
| Method | URL | Description |
|---|---|---|

#### Files to modify (by layer)
- {layer}: `{path/to/file}` — {what changes}

#### Data model changes
{none | description of changes}

#### Validation rules
{list of specific rules to enforce}

### Non-Functional Requirements
- Security: {auth required, validation rules}
- Performance: {SLA or constraints}
- Testing: {what test types are required}

### Out of Scope
- {explicit non-scope items}

### Open Questions
- [ ] {question} — owner: {name} — blocks: {criterion}
```

### Step 6: Update the ticket
Write the enhanced content back using the configured MCP.

If MCP is unavailable:
- Save the enhanced content to `.hive/changes/<ticket-id>_enhanced.md`
- Tell the user to paste it into their ticket tool manually

### Step 7: Move the ticket status (conditional)
Read from `AGENTS.local.md`:
- `ticket_provider.auto_transition_after_enrich` — if `false`, skip this step
- `ticket_provider.statuses.to_refine` — only move if ticket is currently in this status
- `ticket_provider.statuses.refined` — the target status

Move the ticket from `statuses.to_refine` → `statuses.refined` **only if**:
1. `auto_transition_after_enrich` is `true`
2. The ticket's current status matches `statuses.to_refine` exactly
3. The target status `statuses.refined` exists on the board

If any condition fails → skip the transition silently, note it in the output.
**Never assume status names exist** — always use what's configured.

---

## Rules
- XL tickets → run `/split`, do not write enhanced content
- L tickets → enrich normally, append split recommendation
- Unresolved open questions → flag them, do not invent answers
- If design tool MCP is available and ticket mentions UI → read design context first
- Never invent API contracts not in `api-spec.yml` — propose additions instead
- If operating without a ticket MCP → always be explicit about what context is missing

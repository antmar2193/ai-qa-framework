# /new-ticket — Create Ticket from Plain Text
<!-- tokens: ~1400 | loads: analyst.md -->

**Agent:** Analyst (read `.hive/.agents/analyst.md`)
**Usage:** `/new-ticket <plain text description>`

---

## Process

### Step 0: Read configuration

Before anything else, read `.hive/AGENTS.local.md`:
- `ticket_provider.tool` — which system manages tickets
- `ticket_provider.mcp_name` — which MCP to call
- `ticket_provider.id_format` — ticket ID format (e.g. `PROJ-{n}`)
- `ticket_provider.statuses.backlog` — the backlog/todo status name

### Step 1: Parse the description

Extract from the user's plain text:
- **What**: the capability or change requested
- **Why**: the business reason (if stated)
- **Scope**: backend, frontend, or both
- **Dependencies**: any tickets or systems mentioned

If the description is too vague to write acceptance criteria → ask one clarifying question, then continue.

### Step 2: Draft the ticket

Write a structured ticket with:

```markdown
## Title
{one-line imperative: "Add payment webhook handler"}

## Description
{2–4 sentences: what, why, and which module is affected}

## Acceptance Criteria
Given {context}
When {action}
Then {measurable outcome}
[And {additional outcome}]

## Technical Notes
- Layer(s) affected: {domain | application | infrastructure | presentation}
- Estimated files: {rough count}
- Dependencies: {ticket IDs or "none"}

## Size
{S | M | L} — {one-line justification}
```

Size guide:
- **S** (≤ 2h): single criterion, single layer
- **M** (half day): 2–4 criteria, may touch multiple layers
- **L** (full day): complex flow, multiple criteria
- **XL**: do not create — ask the user to split first

### Step 3: Save the ticket

**Option A — MCP available** (check `ticket_provider.mcp_name`):

```
# Jira (Atlassian MCP):
createJiraIssue(project, summary, description, labels)

# Linear (Linear MCP):
createIssue(teamId, title, description)

# GitHub Issues:
createIssue(owner, repo, title, body, labels)
```

Set status to `ticket_provider.statuses.backlog`.

**Option B — MCP unavailable**:

Append to `.hive/specs/TICKETS.md` (create if missing):

```markdown
---
id: {PROJ-N}
title: {title}
size: {S|M|L}
status: backlog
created: {YYYY-MM-DD}
---
{ticket content}
```

### Step 4: Report

Output:
```
✓ Ticket created: {ID} — {title}
  Size: {S|M|L}
  Status: {status}
  Saved to: {ticket tool | .hive/specs/TICKETS.md}

Next steps:
  /enrich {ID}    — add Given/When/Then acceptance criteria
  /ship {ID}      — full implementation pipeline
```

---

## Rules

- XL tickets → do not create, ask user to split into smaller tickets first
- Never invent business context not in the description — ask if needed
- ID format must follow `ticket_provider.id_format` from `AGENTS.local.md`
- If board MCP unavailable → always write to `TICKETS.md`, never ask user to create the ticket manually

# /split — Ticket Decomposition
<!-- tokens: ~1200 | loads: analyst.md -->

**Agent:** Analyst (read `.hive/.agents/analyst.md`)
**Usage:** `/split <ticket-id>`
**Interactive:** Supervised — presents decomposition plan, waits for approval before creating tickets

Breaks a complex ticket (L or XL) into smaller, independent tickets (S or M) that can each
be implemented and merged in a single session. Called automatically by `/ship` and `/enrich`
when a ticket is sized L or XL.

---

## When to split

| Size | Rule |
|---|---|
| **S / M** | Never split — implement directly |
| **L** | Recommend split. In `supervised`/`balanced`: ask. In `autonomous`: split automatically |
| **XL** | Always split — do not proceed with implementation |

A ticket must be split when implementing it in one session would:
- Require more than ~5 new files
- Touch more than 2 DDD layers simultaneously in an unrelated way
- Combine UI + domain + infrastructure work that can each be deployed independently
- Risk hitting `max_tokens_per_ticket` circuit breaker

---

## Process

### Step 1: Load and enrich the ticket
If the ticket is not yet enriched (no Given/When/Then), run the full `/enrich` process first.
If already enriched, read the current content from the board via MCP.

### Step 2: Identify decomposition axes
Analyze the acceptance criteria and technical scope. Find the natural split points:

- **By layer**: domain model first → application logic → API endpoint → frontend
- **By feature slice**: core flow first → edge cases → error handling → UI polish
- **By dependency**: what must exist before something else can be built

Good sub-tickets are **independently deployable** — each one can be merged to the base branch
without breaking the application and without requiring the next sub-ticket to be done.

### Step 3: Draft sub-tickets
Each sub-ticket must have:
- **Title**: `[Verb] [Entity] [specific context]` — concrete, no vague terms like "part 1"
- **Size**: S or M — if a proposed sub-ticket is L, split it further
- **Given/When/Then**: its own acceptance criteria (subset of the original)
- **Dependencies**: which sub-ticket ID must be merged first (if any)
- **Out of scope**: what is explicitly NOT in this sub-ticket

Maximum 5 sub-tickets per split. If more are needed, the original ticket is likely an epic —
flag it and ask the user to restructure it in the board.

### Step 4: Present decomposition plan

```
Ticket PAY-42 (XL) — "Add payment processing"

Proposed split:

  PAY-42a  (M)  Create Payment domain model + repository
               Given a checkout is completed
               When the system records the payment
               Then a Payment entity is persisted with status PENDING
               Depends on: nothing

  PAY-42b  (M)  Implement payment processing endpoint + Stripe integration
               Given a Payment in PENDING status
               When the /payments/:id/process endpoint is called
               Then Stripe charge is created and Payment status → COMPLETED or FAILED
               Depends on: PAY-42a

  PAY-42c  (S)  Add payment history to user profile API
               Given a user has past payments
               When GET /users/:id/payments is called
               Then returns list of payments with status and amount
               Depends on: PAY-42a

  Original ticket PAY-42 → will be marked as Epic and linked to sub-tickets.

Create these 3 tickets? [Y/n]
```

In `autonomous` mode: skip the confirmation, proceed directly to Step 5.

### Step 5: Create sub-tickets
For each sub-ticket, create it via the configured MCP with the full enriched content.

Sub-ticket ID strategy:
- If the board supports sub-tasks: create as sub-tasks of the original
- If not: create as sibling tickets with a naming convention in the title: `[PAY-42] Create Payment domain model`
- Link each sub-ticket to the original in the description: `Parent: PAY-42`

### Step 6: Update the original ticket
- Change original ticket status to `statuses.to_refine` (or equivalent Epic status if supported)
- Add a comment or description note: `Split into: {sub-ticket IDs} — see each for scope`
- Do NOT delete the original ticket — it becomes the tracker/epic

### Step 7: Return sub-ticket IDs
Output for the caller (used by `/ship` and `/run` to queue the sub-tickets):

```
PAY-42 split into: PAY-42a, PAY-42b, PAY-42c
Process them in order:
  hive run PAY-42a PAY-42b PAY-42c
  or
  /ship PAY-42a  →  /ship PAY-42b  →  /ship PAY-42c
```

Log to `.hive/events.jsonl`:
```jsonl
{"ts":"...","cmd":"split","ticket":"PAY-42","event":"ticket_split","detail":"split into PAY-42a, PAY-42b, PAY-42c","sub_tickets":["PAY-42a","PAY-42b","PAY-42c"],"duration_s":0,"profile":"..."}
```

---

## Rules

- Never split a ticket into more than 5 sub-tickets — if more are needed, it's an epic
- Every sub-ticket must be independently deployable (no partial features that break the app)
- Sub-tickets inherit the original's sprint, epic link, and labels
- If the board does not support the MCP create operation, write sub-ticket specs to
  `.hive/changes/{ticket-id}_split.md` and ask the user to create them manually
- Do not start implementation — `/split` only plans and creates tickets

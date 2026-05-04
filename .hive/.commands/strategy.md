# /strategy — Product Strategy Analysis
<!-- tokens: ~1600 | loads: product-strategist.md -->

**Agent:** Product Strategist (read `.hive/.agents/product-strategist.md`)

**Usage:**
```
/strategy                          # reads context files automatically
/strategy "brief idea description" # inline idea + reads context files
```

---

## Input — what this command reads

The agent looks for context in this order. **None are required** — provide whatever exists:

### 1. Attached files (highest priority)
If the user attached files to the conversation, read them first:
- Functional context document (any name — `.md`, `.txt`, `.pdf`)
- Requirements document
- Business description

### 2. Project context files (read if they exist)
```
.hive/AGENTS.local.md          ← project name, tech lead, stack
.hive/specs/PRD.md             ← existing PRD (if refining, not starting fresh)
.hive/specs/data-model.md      ← existing data model (if available)
```

### 3. Inline input
If the user typed text after `/strategy`, use it as the idea/concept to analyze.

### 4. No input at all
If nothing is provided, ask:
```
No context found. Please provide one of:
- A description of the product idea (type it here)
- Attach a functional context or requirements document
- Both
```

---

## Role
You are the Product Strategist agent for HIVE.
Read `.hive/.agents/product-strategist.md` for the full role definition.

Your goal: transform whatever input exists into a structured strategic analysis
that seeds the PRD. You do not write the PRD — you produce the analysis the
PRD author uses.

---

## Process

### Step 1 — Gather input
Identify what context is available (attached files, local files, inline text).
If multiple sources exist, synthesize them — do not repeat.

### Step 2 — Clarify if critical info is missing
Before analyzing, check if these are knowable from the input:
- Who are the primary users?
- What problem does this solve today?
- What is the rough scope (single feature vs full product)?

If any are unclear and cannot be inferred, ask **one consolidated question**
(not multiple rounds of questions).

### Step 3 — Produce strategic analysis

Output format:
```markdown
# Strategy — {project name}
_Generated: {date}_

## Problem
[1-2 paragraphs — what exists today, what is broken or missing]

## Users & Jobs-to-be-Done
| User | Job to be done | Pain today |
|---|---|---|
| {role} | {what they need to accomplish} | {current friction} |

## Value proposition
[one sentence — for {user} who {need}, {product} is a {category}
that {key benefit}, unlike {alternative} which {limitation}]

## Feature prioritization (MoSCoW)

### Must Have (MVP — without this the product has no value)
- **{feature}**: {measurable outcome}

### Should Have (important but not MVP-blocking)
- **{feature}**: {reason}

### Could Have (v2 — valuable but deferrable)
- **{feature}**: {reason}

### Won't Have (explicitly out of scope)
- **{feature}**: {reason}

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|

## Recommended implementation order
Sprint 1: {epics} — {technical rationale}
Sprint 2: {epics} — {rationale}
...

## Open questions for PRD author
- {question that needs business decision before PRD is written}
```

### Step 4 — Save output
Save to: `.hive/specs/strategy.md`
Also return a summary in chat.

### Step 5 — Prompt next step
After output, always say:
```
Strategy saved to .hive/specs/strategy.md

Next step: Review the strategy above, then type:
  "approved" → to generate PRD.md from this strategy
  or give corrections first
```

---

## Token optimization
Load only: `product-strategist.md` + input files
Do NOT load: standards, other agent files, SPEC.md

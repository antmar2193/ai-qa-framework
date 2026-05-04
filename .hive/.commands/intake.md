# /intake — Client Onboarding
<!-- tokens: ~1750 | loads: analyst.md -->

**Usage:** `/intake`

Captures structured functional context from a new client. Produces a
`functional-context.md` file that feeds directly into `/kickoff`.

**Who runs it:** PM / Product Owner
**When:** First client interaction, before `/kickoff`

---

## Process

### Step 1: Read available context
Check if any files were attached to the conversation:
- Requirements documents (.md, .txt, .pdf, .docx)
- Meeting notes
- Existing specifications

If files exist → extract key information. Do not ask for what is already there.

### Step 2: Guided questionnaire

Ask the questions below in a single consolidated message.
Skip questions already answered by attached documents.

```
📋 Client Onboarding — Please answer the following:

1. BUSINESS CONTEXT
   - Company name and industry?
   - Team size that will use the product?
   - Timeline expectations (MVP date, full launch)?

2. PROBLEM
   - What problem does this project solve?
   - How is this problem handled today (current workaround)?
   - What is the cost of not solving it (time, money, risk)?

3. USERS
   - Who are the primary users? (roles, not names)
   - What do they need to accomplish? (main tasks)
   - Any secondary users or admins?

4. FUNCTIONAL REQUIREMENTS
   - List the main features or capabilities needed
   - Which ones are critical for launch vs. nice-to-have?
   - Any specific workflows or business rules?

5. NON-FUNCTIONAL REQUIREMENTS
   - Expected number of users (concurrent, total)?
   - Performance requirements (response time, uptime)?
   - Security/compliance requirements (GDPR, SOC2, HIPAA)?
   - Accessibility requirements?

6. TECHNICAL CONTEXT
   - Existing systems to integrate with? (APIs, SSO, databases)
   - Preferred technology stack? (or open to recommendations)
   - Hosting preferences? (cloud, on-premise, specific provider)
   - Existing codebase? (greenfield vs. legacy)

7. CONSTRAINTS
   - Budget range?
   - Team availability (dedicated vs. shared)?
   - Any hard deadlines or external dependencies?
```

Wait for the client/PM to respond before proceeding.

### Step 3: Generate functional context document

Save to: `.hive/specs/functional-context.md`

```markdown
# Functional Context — {Project Name}
_Captured: {date} | Source: client intake_

## Client
- Company: {name}
- Industry: {industry}
- Team size: {N}

## Problem
{1-2 paragraphs — problem, current workaround, cost of inaction}

## Users
| User Role | Primary Task | Current Pain |
|---|---|---|
| {role} | {task} | {pain} |

## Functional Requirements
### Critical (must launch with)
- {feature}: {description}

### Important (should have)
- {feature}: {description}

### Nice-to-have (can defer)
- {feature}: {description}

## Non-Functional Requirements
- Scale: {users, concurrency}
- Performance: {response time, uptime}
- Security: {compliance, auth requirements}
- Accessibility: {requirements}

## Technical Context
- Existing systems: {list}
- Preferred stack: {stack or "open"}
- Hosting: {preference}
- Type: {greenfield | legacy}

## Constraints
- Timeline: {dates}
- Budget: {range}
- Dependencies: {list}

## Open Questions
- [ ] {question} — needs answer from: {role}
```

### Step 4: Prompt next step

```
Functional context saved to .hive/specs/functional-context.md

Next step: run /kickoff — it will use this context to run the full
initialization sequence (strategy → PRD → architecture → tickets)
with checkpoints for your review at each phase.

Type /kickoff to continue.
```

---

## Rules
- Ask all questions in one consolidated message — do not ask in multiple rounds
- Skip questions already answered by attached documents
- If the client gives incomplete answers, note gaps in "Open Questions"
- Never invent answers — flag uncertainty
- Save output before responding in chat

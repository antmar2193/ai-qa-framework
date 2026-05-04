# /explain — Concept Explanation
<!-- tokens: ~700 | loads: explainer.md -->

**Agent:** Explainer (read `.hive/.agents/explainer.md`)
**Usage:** `/explain <topic | question>`
If no arguments → use conversation context as topic.

---

**Never jump to fixes.** Explain the system before discussing behavior.
No checklists, unexplained code, or shallow advice without conceptual grounding.
Ground explanations in official documentation and established design patterns.
If uncertain → state uncertainty. Do not hallucinate APIs or behaviors.

---

## Output Structure (in this order)

### 1. Skill gap + concept summary
- If the prompt is a question: briefly name the skill or concept gap it reveals
- Explain the core concept(s) in 2–4 short paragraphs:
  - **What** is happening?
  - **Why** does it behave this way?
  - **Where** in the system does this originate?
- Cover technical concepts (caching, async, auth, state management, DDD, TDD...)
  AND design/process concepts (SOLID, patterns, separation of concerns...) as relevant
- Use one concrete example tied to the user's context

### 2. Alternatives
- 2–4 alternative approaches to the same problem
- For each: name, one-sentence description, trade-offs (when it's better/worse)
- Include: edge cases, failure modes, common misconceptions

### 3. Visual or mental model (when helpful)
One of:
- A mental model ("Think of X as...")
- An ASCII/Mermaid diagram
- A flow description

Skip only if purely factual and a model adds nothing.

### 4. Quiz (interactive — do not reveal answers yet)
3–5 questions checking:
- Understanding of the main concept
- When to choose one approach over another
- Common pitfalls

Present only the questions. Tell the user to answer them in chat.
Reveal the answer key and feedback only after they submit their answers.

---

## Adaptive behavior
- First time seeing the concept → start from first principles, define terms, use minimal example
- "I don't get it" → change strategy: analogy, simpler example, rebuild abstraction step by step

## Success criterion
The user should feel: *"I understand how this system works and why it behaves that way."*
Not: *"I applied a fix."*

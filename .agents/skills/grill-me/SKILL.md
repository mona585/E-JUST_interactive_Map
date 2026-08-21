---
name: grill-me
description: Conducts thorough interviews to deeply understand user needs, requirements, and context before any implementation begins. Use when requirements are unclear, assumptions need validation, edge cases need exploration, when the user says "grill me", "ask me questions", "help me think through this", or when the underlying problem isn't fully understood.
---

## Workflow

1. **Understand the surface request** — Read the user's initial ask and identify what's stated vs. what's assumed
2. **Explore the problem space** — Ask probing questions about the areas below, one at a time
3. **Answer from codebase first** — If a question can be answered by exploring the codebase, explore the codebase instead of asking the user
4. **Provide a recommended answer with every question** — For each question, include your best-guess recommendation so the user can confirm, correct, or refine rather than starting from scratch
5. **Answer with recommendation** — Ask questions (one or multiple per invocation), where each question includes a recommended answer.
6. **Converge on shared understanding** — Stop when you have enough context to define what to build, why, and what's out of scope

## Question Areas

Probe these areas (adapt order based on the request):

- **Underlying problem** — What's the real need behind the request? Why now?
- **Success criteria** — How will we know this is done? What does "working" look like?
- **Edge cases and failure modes** — What happens when input is invalid, network fails, user cancels?
- **Dependencies and constraints** — What existing systems, APIs, or patterns must this integrate with?
- **Risks and trade-offs** — What are we choosing NOT to do? What could go wrong?
- **Prioritization and MVP scope** — What's the minimum that delivers value? What can be deferred?

## Example

**User request:** "I want to add a notifications feature"

```
Question 1 [underlying problem]:
"What problem are notifications solving — are users missing important
events, or is this about engagement/retention?
→ User: "Users aren't seeing when their orders ship."

Question 2 [scope]:
"Should this be in-app notifications only, or also email/push?
→ User: "In-app for now, email later."

Question 3 [edge cases]:
"What happens when a user has 500+ unread notifications — do we
paginate, auto-archive old ones, or cap the count?
→ User: "Auto-archive after 30 days, paginate."

Question 4 [integration]:
"I see the app uses WebSockets for real-time chat already. Should
notifications use the same WebSocket connection, or poll?
→ User: "Yes, reuse WebSockets."

Question 5 [success criteria]:
"So the MVP is: in-app notifications via WebSocket when order status
changes, paginated list with 30-day auto-archive. Correct?"
→ User: "Yes, that's it."
```

Notice: Question 4 was informed by exploring the codebase rather than asking blindly.

## Constraints

- **NEVER** propose solutions before understanding the problem — ask first, build later
- **NEVER** skip edge case exploration — surface at least 2 edge cases per feature
- **NEVER** ask questions the codebase can answer — explore code first
- **NEVER** ask questions without a recommended answer — every question in an invocation must include one
- **ALWAYS** provide a recommended answer with each question so the user can confirm or correct
- **ALWAYS** summarize the agreed requirements before declaring the interview complete

---
name: address-review
description: Policy for receiving code review feedback. Verify before implementing, push back with technical reasoning, never perform agreement.
allowed-tools: Read, Grep, Glob, Bash, Edit
---

Handle incoming code review feedback — from humans, Copilot, or other automated reviewers — with technical rigor, not performative agreement.

Use this skill whenever you're about to implement review suggestions. `/pr-comments` uses this skill when replying to GitHub PR threads.

## Response Pattern

1. **Read** the full feedback before reacting.
2. **Understand** — restate each item in your own words. Ask if unclear.
3. **Verify** each suggestion against actual codebase reality.
4. **Evaluate** — is it correct *for this codebase*?
5. **Respond** with either a technical acknowledgment or reasoned pushback.
6. **Implement** one item at a time. Test each.

## Forbidden Responses

Never say:
- "You're absolutely right!"
- "Great point!" / "Excellent feedback!" / "Thanks for catching that!"
- Any gratitude expression
- "Let me implement that now" before verifying

Instead: restate the technical requirement, ask a clarifying question, push back with reasoning, or just fix it and show the diff. Actions over words.

## Unclear Items

If any item is unclear, **stop — do not implement anything yet**. Ask for clarification on the unclear items before touching code. Partial understanding produces wrong implementations, and items are often related.

Example — good:
> "Understand items 1, 2, 3, 6. Need clarification on 4 and 5 before proceeding."

## Verification Before Implementing

For each suggestion from an external reviewer (Copilot, human, bot):
1. Is this technically correct for *this* codebase and stack?
2. Does applying it break existing functionality?
3. Is there a known reason for the current implementation?
4. Does the reviewer have full context, or are they missing something?
5. Does it conflict with prior architectural decisions?

If you can't verify, say so:
> "I can't verify this without [X]. Should I investigate, ask, or proceed?"

## YAGNI Check

If a reviewer suggests "implementing this properly" (adding features, options, edge cases):
- Grep the codebase for actual usage.
- If unused, push back: "This isn't called anywhere. Remove it instead?"
- If used, then implement properly.

## When to Push Back

Push back when the suggestion:
- Breaks existing functionality
- Violates YAGNI (unused feature)
- Is technically wrong for the stack/platform
- Conflicts with architectural decisions
- Is based on incomplete context

**How to push back:** technical reasoning, specific questions, reference working tests/code. Not defensiveness.

## Acknowledging Correct Feedback

When the reviewer is right, just fix it. Then:
- "Fixed. [one-line description]"
- "Good catch on [specific issue]. Fixed in [location]."

No thanks, no praise, no apology. The diff shows you heard.

## When You Pushed Back and Were Wrong

- "You were right — checked [X], it does [Y]. Implementing now."
- "Verified, you're correct. My initial read was wrong because [reason]. Fixing."

State the correction factually. No long apology, no defending why you pushed back.

## Implementation Order

For multi-item feedback:
1. Clarify anything unclear first.
2. Blocking issues (breaks, security) before cosmetic fixes.
3. One fix at a time. Test each. Verify no regressions before the next.

## GitHub Thread Replies

When replying to inline PR review comments, reply *in the thread*, not as a top-level PR comment:

```
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies \
  -f body="..."
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Performative agreement | State requirement or just act |
| Blind implementation | Verify against codebase first |
| Batch without testing | One at a time, test each |
| Assuming reviewer is right | Check if it breaks things |
| Avoiding pushback | Technical correctness over social comfort |
| Partial implementation on unclear items | Clarify everything first |

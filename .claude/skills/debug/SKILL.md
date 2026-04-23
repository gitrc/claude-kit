---
name: debug
description: Systematic 4-phase debugging with anti-thrashing guardrails
allowed-tools: Read, Grep, Glob, Bash, Agent, Edit
---

Systematically debug an issue using a structured 4-phase approach.

## Core Principles

- **Never guess** — trace the actual execution path.
- **Read error messages carefully** before acting. The answer is usually in the error.
- **Reproduce the bug first** before attempting any fix.
- **Fix the root cause, not the symptom** — defense in depth.
- **Verify the fix actually works** — run the reproduction case again after fixing.

## Anti-Thrashing Rule

After **3 failed fix attempts**, STOP. Do not try a 4th variation of the same approach. Instead:
1. Re-read the original error and all evidence gathered so far.
2. Question your assumptions — what are you taking for granted that might be wrong?
3. Question the architecture — is the design itself the problem?
4. Write down what you know vs. what you're assuming.
5. Consider whether you're fixing the wrong layer entirely.

Only proceed once you have a genuinely new hypothesis, not a tweak of the old one.

## Phase 1: Root Cause Investigation

1. **Reproduce the bug** — get the exact error, stack trace, or incorrect behavior.
2. **Read the full error output** — don't skim. Every line matters.
3. **Trace the execution path** from the entry point to the failure:
   - Use Grep to find the failing function/line.
   - Use Read to examine the surrounding code.
   - Follow the call chain backward from the crash site.
4. **Identify the actual vs. expected state** at the point of failure.
5. **Check recent changes** — `git log --oneline -20` and `git diff HEAD~5` to see what changed.

## Phase 2: Pattern Analysis

1. **Search for similar patterns** — does this bug exist elsewhere in the codebase?
   - Use Grep broadly to find related code paths.
2. **Check for known failure modes**:
   - Off-by-one errors, null/undefined values, race conditions, encoding issues.
   - Missing error handling, wrong types, stale caches.
3. **Review related tests** — do existing tests cover this case? If they pass, why?
4. **Check configuration and environment** — is this environment-specific?

## Phase 3: Hypothesis Testing

1. **Form a specific, falsifiable hypothesis** — "The bug occurs because X is Y when it should be Z."
2. **Design a minimal test** to confirm or reject the hypothesis.
3. **Use subagents for parallel hypothesis testing** when you have multiple independent theories:
   - Spawn one Agent per hypothesis to investigate concurrently.
   - Each subagent should report back with evidence for or against.
4. **If the hypothesis is rejected**, return to Phase 1 with new information. Do not force-fit the evidence.

## Phase 4: Implementation

1. **Write the minimal fix** that addresses the root cause.
2. **Check for collateral damage** — does the fix break anything else?
   - Read callers of the changed code.
   - Run existing tests.
3. **Verify the fix** — apply the `/verify` gate. Re-run the exact reproduction case from Phase 1, see it pass, then claim the bug is fixed. No "should be fixed now" without evidence.
4. **Add a regression test** if one doesn't exist for this case. Prove it catches the bug: revert the fix, see the test fail; restore the fix, see it pass. A regression test that only passes isn't a regression test.
5. **Clean up** — remove any debug logging or temporary instrumentation.

## Output

Report to the user:
- What the root cause was (one sentence).
- What was changed and why.
- How it was verified.
- Any remaining risks or related issues spotted during investigation.

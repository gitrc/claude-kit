---
name: verify
description: Gate before claiming work is complete. Run the verification command, read the output, then claim the result — never before.
allowed-tools: Read, Grep, Glob, Bash
---

Run through this gate before claiming any work is done, fixed, passing, shipped, or ready.

## Iron Rule

**No completion claims without fresh verification evidence in this turn.**

If you haven't run the verifying command in the current turn, you cannot claim it passes. "Ran it five minutes ago" is not evidence.

## The Gate

Before saying any of: "done", "fixed", "passing", "ready", "complete", "shipped", "works":

1. **Identify** — what command proves the claim?
2. **Run** — the full command, fresh, no shortcuts.
3. **Read** — full output, exit code, failure count.
4. **Verify** — does the output actually confirm the claim?
5. **Only then** — make the claim, with the evidence.

Skipping any step is lying, not verifying.

## Claim → Evidence

| Claim | Required evidence | Not sufficient |
|-------|-------------------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Spot check, extrapolation |
| Build succeeds | Build exit 0 | Linter passing, "logs look good" |
| Bug fixed | Original repro case passes | Code changed, "should be fine" |
| Regression test works | Revert fix → test fails → restore fix → test passes | Test passes once |
| Subagent finished | Git diff shows the expected changes | Agent's summary message |
| Requirements met | Line-by-line checklist against plan | "Tests pass" |

## Red Flags — Stop

If you catch yourself typing any of these, run the verification first:
- "should", "probably", "seems to", "looks good"
- "Great!" / "Perfect!" / "Done!" without evidence above it
- About to commit, push, or open a PR without verification
- Trusting a subagent's success report without checking the diff
- "Partial check is enough"
- "I'm tired, let's wrap"

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | Then prove it. Run the command. |
| "I'm confident" | Confidence is not evidence. |
| "Just this once" | No exceptions. |
| "Linter passed" | Linter ≠ compiler ≠ test suite. |
| "Agent reported success" | Verify the diff yourself. |
| "Partial check is enough" | Partial proves nothing. |

## Special Cases

**Regression tests (red-green-red-green):**
1. Write the test. Run it — it fails against the buggy code.
2. Apply the fix. Run it — it passes.
3. Revert the fix. Run it — it fails again (proves the test catches the bug).
4. Restore the fix. Run it — it passes.

Skipping step 3 means you can't claim the test is a real regression guard.

**Subagent delegation:**
Agent reports success → `git status` / `git diff` → read the actual changes → then claim.

**Requirements coverage:**
Re-read the plan or issue → make a checklist → verify each item has evidence → only then mark complete.

## Bottom Line

Run the command. Read the output. Then — and only then — claim the result.

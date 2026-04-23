---
name: tdd
description: Test-driven development workflow. Write the failing test first, watch it fail, then write minimal code to pass.
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
---

Drive a feature or bugfix with tests written first.

## Iron Rule

**No production code without a failing test first.**

If you wrote code before the test, delete it and start over. Don't "adapt" it while writing the test — that's tests-after wearing a mask.

Exceptions (ask the user first): throwaway spikes, generated code, config.

## Red–Green–Refactor

### 1. RED — Write one failing test
- One behavior per test. If the name has "and" in it, split it.
- Test real behavior, not mock interactions.
- Name describes what the code should do, not what it does.

### 2. Verify RED — Run it and watch it fail
**Mandatory. Never skip.**

Run the test command. Confirm:
- Test *fails* (doesn't error on a typo).
- Failure message matches what you expect.
- It fails because the feature is missing, not because setup is broken.

If it passes, you're testing existing behavior — rewrite the test.

### 3. GREEN — Minimal code to pass
Simplest code that makes the test pass. No extra options, no speculative parameters, no refactoring nearby code. YAGNI.

### 4. Verify GREEN — Run it and watch it pass
Confirm the new test passes AND the rest of the suite still passes. Pristine output — no stray warnings.

### 5. REFACTOR — Clean up
Only after green. Remove duplication, improve names, extract helpers. Don't add behavior. Tests stay green the whole time.

### 6. Next test
Back to step 1.

## Bug Fix Variant

A bug is a missing test. Reproduce the bug as a failing test first, then fix. The test proves the fix and prevents regression.

## What to Flag as a Red Flag
Stop and restart if you catch yourself:
- Writing code before a test
- Adding a test that passes immediately
- Unable to explain why a test failed
- Saying "I'll add tests after" or "just this once"
- Keeping old code "as reference" while writing tests
- Arguing "TDD is dogmatic, I'm being pragmatic"

All of these mean: delete the code, write the test, start over.

## When Stuck

| Problem | Fix |
|---------|-----|
| Don't know how to test it | Write the wished-for API as the test. |
| Test is too complicated | The design is too complicated. Simplify the interface. |
| Need to mock everything | Code is too coupled. Use dependency injection. |
| Test setup is huge | Extract helpers. Still complex? Redesign. |

## Completion Checklist

Before claiming the work is done:
- [ ] Every new function has a test
- [ ] Each test was seen failing before it passed
- [ ] Each test failed for the right reason (missing feature, not typo)
- [ ] Code is the minimum that makes the test pass
- [ ] Full suite passes, output is pristine
- [ ] Edge cases and error paths are covered

If any box is unchecked, you skipped TDD. Fix it before marking complete.

---
name: qa
description: Final QA pass on all code changes. Reviews quality and tests, then presents findings for user approval before commit/push.
allowed-tools: Read, Grep, Glob, Bash, Agent
---

Perform a final QA pass on all code changes in this repository.

QA is **always parallel, always in subagents**. Do not review files sequentially in the main context — fan out to independent reviewers with different lenses, then aggregate.

## Step 1: Gather Changes
Run `git diff HEAD --stat` and `git status` to identify all modified, added, and untracked files. Keep the raw diff out of the main context — the subagents will read files themselves.

## Step 2: Fan Out Parallel Reviewers
Spawn **three Explore subagents concurrently in a single message** (multiple Agent tool calls in one assistant turn). Each gets the same file list and a different lens. Each must return a concise findings report (no raw code, no full diffs).

**Agent 1 — Security & Safety lens:**
Hunt for injection (SQL, command, XSS), hardcoded secrets or credentials, insecure defaults, unsafe deserialization (pickle, eval, innerHTML), missing input validation at system boundaries, path traversal, unsafe file/network operations, OWASP top 10 issues. Also flag dangerous patterns the security-scanner hook may have missed.

**Agent 2 — Correctness & Bugs lens:**
Hunt for logic errors, off-by-one, null/undefined access, race conditions, missing error handling, swallowed exceptions, incorrect boundary conditions, wrong types, stale assumptions. Also verify tests cover the changes; flag functions added without tests.

**Agent 3 — Architecture, Quality & Production Standards lens:**
Hunt for dead code, unused imports, DRY violations, unclear naming, speculative abstractions. Verify production standards from CLAUDE.md: structured logging (not `print()`), env-based config, structured arg parsing, explicit deps, virtual env for Python. Check coupling and dependency direction. Flag breaking API contract changes.

Each agent's prompt must instruct it to:
- Read full files for context (not just diffs)
- Report findings in the format `[SEVERITY] file:line — description` with severities `MUST FIX` / `SHOULD FIX` / `CONSIDER`
- Skip noise that CI/linters already catch (formatter output, import order, trailing whitespace, pylint/clippy/ESLint warnings)
- Return under ~300 words — findings only, no preamble

Run them in parallel in a single turn. Wait for all three to finish.

## Step 3: Aggregate & Report Findings
Present a clear summary to the user:
- What was reviewed (file list)
- Issues found, categorized by severity:
  - **MUST FIX**: bugs, security issues, broken functionality
  - **SHOULD FIX**: missing error handling, code quality issues
  - **CONSIDER**: style, naming, minor improvements
- Overall assessment: **ready to ship** / **needs fixes first**
- Optionally, a one-line callout of a notably good pattern worth reinforcing

**Do NOT silently fix issues.** The user must see and approve all changes. If you found MUST FIX issues, list exactly what needs to change and ask the user: "Should I fix these issues?"

When the user pushes back or asks for changes, apply the `/address-review` policy: no performative agreement ("You're absolutely right!", "Great catch!"), verify suggestions against the codebase before implementing, push back with technical reasoning when warranted.

## Step 4: Fix (only if user approves)
If the user approves fixes:
- Apply only the fixes discussed — nothing extra
- Show a brief summary of what was changed

## Step 5: Verify Before Committing
Apply the `/verify` gate:
- Run the test suite. Read the output. 0 failures.
- Run the linter / type checker if the project has one. 0 errors.
- If a fix targeted a specific bug, re-run the reproduction case.

Never claim "ready to commit" without evidence from this turn. If verification fails, fix it before proceeding.

## Step 6: Commit & Push
After verification passes, ask the user:
> "Verification passed. Ready to commit and push? Provide a commit message or I'll generate one."

If the user agrees:
1. Stage the appropriate files with `git add` (specific files, not `-A`)
2. Create the commit
3. Push to the current branch with `git push`

---
name: qa
description: Final QA pass on all code changes. Reviews quality and tests, then presents findings for user approval before commit/push.
allowed-tools: Read, Grep, Glob, Bash, Agent
---

Perform a final QA pass on all code changes in this repository.

## Step 1: Gather Changes
Run `git diff HEAD` and `git status` to identify all modified, added, and untracked files.

## Step 2: Review Each Changed File
For each changed code file:
- Read the full file (not just the diff) to understand context
- Check for:
  - **Bugs**: logic errors, off-by-one, null/undefined access, race conditions
  - **Security**: injection, XSS, hardcoded secrets, insecure defaults
  - **Error handling**: uncaught exceptions, missing validation at boundaries
  - **Code quality**: dead code, unused imports, naming clarity, DRY violations
  - **Production standards**: structured logging (not print), env-based config, proper arg parsing
  - **Language idioms**: is the code idiomatic for its language?
  - **Tests**: are changes covered by tests? If not, flag it.

## Step 3: Report Findings
Present a clear summary to the user:
- What was reviewed (file list)
- Issues found, categorized by severity:
  - **MUST FIX**: bugs, security issues, broken functionality
  - **SHOULD FIX**: missing error handling, code quality issues
  - **CONSIDER**: style, naming, minor improvements
- Overall assessment: **ready to ship** / **needs fixes first**

**Do NOT silently fix issues.** The user must see and approve all changes. If you found MUST FIX issues, list exactly what needs to change and ask the user: "Should I fix these issues?"

## Step 4: Fix (only if user approves)
If the user approves fixes:
- Apply only the fixes discussed — nothing extra
- Show a brief summary of what was changed

## Step 5: Commit & Push
After fixes are applied (or if no fixes needed), ask the user:
> "Ready to commit and push? Provide a commit message or I'll generate one."

If the user agrees:
1. Stage the appropriate files with `git add` (specific files, not `-A`)
2. Create the commit
3. Push to the current branch with `git push`

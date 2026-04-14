---
name: review
description: On-demand code review of current changes. Lighter than /qa — no commit step.
argument-hint: "[file-or-path]"
context: fork
agent: general-purpose
allowed-tools: Read, Grep, Glob, Bash
---

Perform a focused code review.

## Scope
If an argument is provided, review only `$ARGUMENTS`. It may also name a focus area (e.g. "focus on security") — concentrate on that area but still flag any critical issues elsewhere.

Otherwise, pick the diff command that matches the request:
- **Current branch vs main**: `git --no-pager diff --no-prefix --unified=100000 --minimal $(git merge-base main --fork-point)...HEAD`
- **Staged only**: `git --no-pager diff --cached --no-prefix --unified=100000 --minimal`
- **Unstaged only**: `git --no-pager diff --no-prefix --unified=100000 --minimal`
- **Default (uncommitted)**: `git diff HEAD --name-only` then review each file.

If the diff is empty, say so — don't fabricate a review.

## Review Checklist
For each file:
1. **Correctness**: Logic errors, edge cases, off-by-one, null safety
2. **Security**: Injection, XSS, secrets, insecure defaults, OWASP top 10
3. **Performance**: Unnecessary allocations, N+1 queries, missing indexes, unbounded loops
4. **Error handling**: Uncaught exceptions, swallowed errors, missing boundary validation
5. **Architecture**: Coupling, dependency direction (domain shouldn't depend on infra), breaking API contract changes
6. **Readability**: Naming, complexity, unnecessary abstractions
7. **Language idioms**: Is the code idiomatic? (Python: PEP 8, Rust: clippy conventions, TS: strict mode patterns, etc.)

## What NOT to Flag
Skip noise CI/linters already catch: formatter output (prettier/black/rustfmt/gofmt), import ordering, trailing whitespace, missing trailing newlines, lint warnings already surfaced by clippy/ESLint/pylint.

## Output Format
For each issue found, report:
```
[SEVERITY] file:line — description
  Suggestion: what to do instead
```

Severities: `BUG`, `SECURITY`, `PERF`, `STYLE`, `NITPICK`

End with a one-line summary: `N issues found (X bugs, Y security, Z perf, ...)`
If no issues: `No issues found. Code looks good.`

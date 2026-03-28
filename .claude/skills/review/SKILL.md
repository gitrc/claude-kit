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
If an argument is provided, review only `$ARGUMENTS`.
Otherwise, review all uncommitted changes: run `git diff HEAD --name-only` and review each changed file.

## Review Checklist
For each file:
1. **Correctness**: Logic errors, edge cases, off-by-one, null safety
2. **Security**: Injection, XSS, secrets, insecure defaults, OWASP top 10
3. **Performance**: Unnecessary allocations, N+1 queries, missing indexes, unbounded loops
4. **Error handling**: Uncaught exceptions, swallowed errors, missing boundary validation
5. **Readability**: Naming, complexity, unnecessary abstractions
6. **Language idioms**: Is the code idiomatic? (Python: PEP 8, Rust: clippy conventions, TS: strict mode patterns, etc.)

## Output Format
For each issue found, report:
```
[SEVERITY] file:line — description
  Suggestion: what to do instead
```

Severities: `BUG`, `SECURITY`, `PERF`, `STYLE`, `NITPICK`

End with a one-line summary: `N issues found (X bugs, Y security, Z perf, ...)`
If no issues: `No issues found. Code looks good.`

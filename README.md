# claude-kit

Production-grade development template for Claude Code. Automated code review gates, safety guardrails, PR workflow automation, and production code standards — all enforced mechanically, not just by prompt.

## What's Included

### Hooks (automatic, zero effort)
| Hook | What it does |
|------|-------------|
| **Stop gate** | Blocks task completion until code changes are reviewed. Skips trivial changes (<5 lines). |
| **Test-evidence gate** | Blocks task completion if code changes exist and no test command was run this session. Skips trivial changes and projects without a detectable test runner. |

Both Stop hooks fire independently on every Stop event — each can block, and Claude handles the block by addressing the reason before trying to stop again.

| **Dangerous command blocker** | Catches destructive commands (`rm -rf /`, force push to main, bare `pip install`, etc.) before execution. |
| **Security scanner** | Warns on code anti-patterns (eval, innerHTML, pickle, SQL injection) as you write. Advisory, not blocking. |
| **Context monitor** | Tracks session size, nudges to `/compact` before quality degrades. |
| **StopFailure handler** | Desktop notification + log on API errors (rate limits, auth failures). |
| **Preflight check** | On first prompt, nudges to run `/setup` if project isn't configured. |

### Skills (slash commands)
| Skill | What it does |
|-------|-------------|
| `/setup` | First-time project setup: git hooks, .gitignore, LSP plugins, burn rules into memory. |
| `/tdd` | Test-driven development workflow: failing test first, watch it fail, minimal code to pass. |
| `/qa` | Full QA pass: reviews all changes, reports findings, commit/push on approval. |
| `/review [file]` | Quick code review. No commit step. |
| `/verify` | Gate before claiming work is done. Run the verification command, then claim the result. |
| `/ship [message]` | Lightweight commit + push + open PR. Use after `/review` or `/qa`. |
| `/pre-pr-review` | Ships the branch diff to an OpenAI model (default `gpt-4.1`) so a *different* set of weights reviews before the PR opens. Same-model review has correlated blind spots — this is the council-of-LLMs counterweight. No-ops gracefully if `OPENAI_API_KEY` is unset. |
| `/pr-comments [number]` | Fetch GitHub PR review comments, address each one, commit fixes, reply and resolve threads. |
| `/address-review` | Policy for receiving review feedback: verify before implementing, push back with reasoning, no performative agreement. |
| `/debug` | Systematic 4-phase debugging with anti-thrashing (3 failed fixes = stop and rethink). |
| `/inject <target-dir>` | Inject this template into an existing project. Merges, doesn't clobber. |

### Git Hooks
| Hook | What it does |
|------|-------------|
| **pre-commit** | Blocks secrets, merge conflict markers, large files (>5MB), sensitive files (.env, .pem, credentials.json, etc.). Warns on debug statements (console.log, breakpoint, pdb) and unsafe code patterns (eval, pickle.load, innerHTML, shell=True, yaml.load without SafeLoader, weak hashes). Warnings are advisory — scoped to code files only, so markdown docs that *describe* anti-patterns don't false-positive. |
| **pre-push** | Blocks force-push to main/master. Warns on WIP/fixup commits. |

### Production Code Standards (CLAUDE.md.template)
Non-negotiable rules enforced via CLAUDE.md and persistent memory:
- Structured logging (never `print()`)
- Virtual environments for all Python work
- Structured argument parsing for CLIs
- Config via environment variables
- Explicit dependencies in manifests
- Error handling with context
- KISS above all

## Install

### New project
```bash
npx degit gitrc/claude-kit my-project
cd my-project && git init
claude
# then run /setup
```

### Existing project
```bash
git clone --depth 1 https://github.com/gitrc/claude-kit /tmp/ck
/tmp/ck/inject.sh ~/projects/my-app
rm -rf /tmp/ck
cd ~/projects/my-app
claude
# then run /setup
```

Or from a local clone:
```bash
./inject.sh ~/projects/my-app
```

`inject.sh` is idempotent and safe to run multiple times. It:
- Copies hooks (including `lib/`) and skills — overwrites, they are template-managed
- **Merges** `.claude/settings.json`: user permissions, env, statusLine and custom hooks are preserved; template hooks are appended per event. Backs up to `settings.json.bak` before writing.
- Appends missing `.gitignore` entries (no duplicates)
- Refreshes `CLAUDE.md.template` (never touches your `CLAUDE.md`)
- Stamps `.claude/KIT_VERSION` so you can see which version is in the project
- Skips `.git/`, `settings.local.json`, `errors.log`, `CLAUDE.md`

### Upgrading an injected project

The same `inject.sh` script handles upgrades — it detects an existing install via `.claude/KIT_VERSION` and switches to upgrade mode. Existing user customizations in `settings.json` and `CLAUDE.md` are preserved; hooks, skills, and `CLAUDE.md.template` are refreshed. Three flows depending on what you want:

**Check what would change without writing anything:**
```bash
/path/to/claude-kit/inject.sh --check ~/projects/my-app
```
Prints "v0.2.0 → v0.3.0" plus the relevant CHANGELOG entries, then exits.

**Apply the upgrade:**
```bash
git -C /path/to/claude-kit pull        # get the latest template
/path/to/claude-kit/inject.sh ~/projects/my-app
```
Or use the friendlier wrapper that does the same thing:
```bash
/path/to/claude-kit/update-kit.sh ~/projects/my-app
```

**Re-run `/setup` only if needed.** Most upgrades don't require it. If `CLAUDE.md.template` gained rules you want burned into persistent memory, re-run `/setup` once after the upgrade. The CHANGELOG flags releases that need this.

Read [CHANGELOG.md](CHANGELOG.md) for what changed. Most upgrades — including 0.3.0's burned-memory rename — are graceful: the new CLAUDE.md takes precedence on actionable rules, so Claude does the right thing even before any cleanup. Re-running `/setup` after a memory-rename release is housekeeping, not a hard requirement.

## How It Works

1. **Inject** the template into your project
2. **Start Claude Code** — preflight check nudges you to run `/setup`
3. **`/setup`** configures git hooks, installs LSP plugins for your languages, and burns non-negotiable rules into persistent memory
4. **Write code** — Claude follows production standards from CLAUDE.md
5. **Stop gate** fires — Claude must review its own changes before completing
6. **`/qa`** or **`/review`** for deeper review, **`/ship`** to commit + PR
7. **`/pr-comments`** to handle reviewer feedback from Copilot or humans

## Supported Languages

Python, Java, Scala, TypeScript/JavaScript, Rust, Swift/iOS, Go, Kotlin.

LSP plugins are auto-detected and installed by `/setup` based on project files (e.g., `pyproject.toml` triggers `pyright-lsp`).

## Testing

The hook state machines are covered by a self-contained bash test harness:

```bash
bash .claude/hooks/tests/run-tests.sh
```

Ten tests cover: empty/trivial diffs, one-block-per-fingerprint backoff, content-edit fingerprint change, path-traversal containment, the broad-grep false-positive guard in `test-evidence`, prompt-level nudge idempotency. Run before shipping changes to hooks.

## Philosophy

- **Mechanical enforcement over prompt engineering.** Shell hooks that return exit code 2 are more reliable than asking Claude nicely.
- **Production code by default.** The marginal cost of doing it right is small; the cost of fixing it later is enormous.
- **Minimal and universal.** Works across any language, any project. No framework opinions, no workflow prescriptions.
- **KISS.** The template itself follows the rules it enforces.

## License

MIT

# Changelog

Notable changes per release. Run `/path/to/claude-kit/inject.sh <project>` (or `update-kit.sh`) to pick up a new version. inject.sh is idempotent and merges; existing user customizations in `settings.json` and `CLAUDE.md` are preserved.

## 0.3.0 — 2026-04-27

**Breaking-ish (memory rename):** the burned-memory file from `/setup` was renamed `feedback_python_venv_required.md` → `feedback_python_isolation_required.md`. Re-run `/setup` once after upgrading, or delete the old file from `~/.claude/projects/<project>/memory/` manually. The rule is otherwise active from CLAUDE.md immediately.

- Python rule rewritten as principle ("never run against the system interpreter") with detection-order enumeration of acceptable tools: uv, poetry, pipenv, conda, stdlib venv. Fresh projects: Claude asks the user which tool to adopt instead of auto-creating a `.venv`.
- `block-dangerous.sh` accepts `uv`, `poetry`, `pipenv`, `pipx` as valid wrappers around `pip install` — no spurious warnings on `uv pip install` or `poetry add`. Bare `pip install` still warns.

## 0.2.2 — 2026-04-24

- `/pre-pr-review` falls back to working-tree diff (`git diff HEAD`) when branch-vs-main spec is empty. Catches the WIP-on-main and no-commits-yet cases. Explicit `--diff-spec` is always respected.
- Fixed non-deterministic fingerprint: prior implementation used `git stash create`, whose commit SHA embeds a timestamp. Two stop-hook calls ≥1s apart produced different fingerprints for identical content, causing the gate to re-block. Switched to hashing `git diff HEAD` content directly.
- Test harness now includes a `sleep 1.1` between fingerprint comparisons so the timestamp-regression class fails loudly instead of flaking.

## 0.2.1 — 2026-04-23

- Added `/pre-pr-review`: ships the branch diff to an OpenAI model (default `gpt-4.1`, override via `CLAUDEKIT_REVIEW_MODEL`) so a different set of weights reviews before the PR opens. Same-model self-review has correlated blind spots; this is the council-of-LLMs counterweight to Claude's own `/qa`. Graceful no-op when `OPENAI_API_KEY` is unset. Wired into `/ship` between `/verify` and commit; warns on CRITICAL findings, doesn't hard-block.
- Vendored a condensed Copilot-style review rubric from `github/awesome-copilot@63d08d5`, MIT-licensed, attribution preserved.

## 0.2.0 — 2026-04-23

- Versioning + update path. `VERSION` at repo root; `inject.sh` stamps `.claude/KIT_VERSION` into each project so users can tell which version is deployed where. New `update-kit.sh` wrapper.
- `inject.sh` actually merges `settings.json` instead of overwriting (prior README claimed "merges, doesn't clobber" but code did `cp`). User permissions, env, and custom hooks are preserved; template hooks are appended per event.
- Hook hardening: shared lib at `.claude/hooks/lib/common.sh`; `session_id` sanitized before any filesystem use (path-traversal containment); marker files moved from `/tmp` to `$HOME/.cache/claude-kit/` with 0700 perms (symlink-attack and cross-user containment); content-aware fingerprint; portable diff-line counting via `git numstat + awk` (no `paste`/`bc` dependency).
- Hook test harness at `.claude/hooks/tests/run-tests.sh` (10 tests, plain bash, no bats dependency). Caught two real regressions during 0.2.x development.
- Pre-commit secret patterns expanded: AWS STS session tokens (`ASIA*`), GitHub fine-grained PATs (`github_pat_*`), GitHub OAuth (`gho_*`), OPENSSH private keys, GCP service-account JSON sentinel. JSON files no longer skipped by the scan.
- Stop-gate infinite loop fixed (predates 0.2 — the prior transcript-mtime heuristic re-blocked on every stop with uncommitted changes). One-block-per-fingerprint state machine, mathematically loop-proof.

## 0.1.0 — 2026-04-22

- Initial release.

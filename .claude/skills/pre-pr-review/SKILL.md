---
name: pre-pr-review
description: Shift-left Copilot-style review. Ships the branch diff to a different model (OpenAI) so a non-Claude set of weights eyeballs the code before the PR opens. Same-model self-review has correlated blind spots; this is the council-of-LLMs counterweight.
argument-hint: "[--diff-spec <spec>] [--json]"
allowed-tools: Bash, Read
---

Run a pre-PR review using an OpenAI model so a *different* set of model weights reviews the diff before it hits GitHub. This gate exists because same-model review (Claude reviewing Claude) has correlated blind spots — no number of self-audit rounds catches what another model's training would surface. Call it once before every `/ship` on non-trivial work.

## Prerequisites

- `OPENAI_API_KEY` set in the environment. If not set, the runner exits 0 with a note and the skill is effectively a no-op. Never block shipping on its absence.
- Optional: `CLAUDEKIT_REVIEW_MODEL` (default: `gpt-4.1`). Bump to newer models as they ship.

## Steps

1. **Check the environment**: run `echo "$OPENAI_API_KEY" | head -c 4` — if empty, report to the user that the skill is a no-op without the key, and stop. Do NOT attempt to proceed.

2. **Run the reviewer**: invoke the script directly. Default diff spec is merge-base-of-origin/main to HEAD (the whole feature branch):

   ```bash
   python3 .claude/skills/pre-pr-review/run.py
   ```

   Custom diff spec (e.g. staged only, or a specific range):
   ```bash
   python3 .claude/skills/pre-pr-review/run.py --diff-spec 'HEAD~1...HEAD'
   ```

   Machine-readable output:
   ```bash
   python3 .claude/skills/pre-pr-review/run.py --json
   ```

3. **Report to the user**: pass the findings through verbatim; do not summarize or add opinions. The reviewer is meant to be a second independent pair of eyes — massaging its output defeats the purpose. If CRITICAL findings are non-zero, flag that clearly and ask whether to address them before shipping.

4. **Disposition**: apply `/address-review` policy to each finding. Verify the suggestion against the codebase, push back with technical reasoning if it's wrong for this stack, implement if correct. No performative agreement.

## Exit-code semantics

- `0` — ran cleanly (no findings, or only IMPORTANT/SUGGESTION findings, or skipped because no API key).
- `1` — configuration error (bad arg, malformed model response).
- `2` — the OpenAI model flagged at least one CRITICAL finding. `/ship` treats this as "warn + confirm", not a hard block.

## When to invoke

- Before every `/ship` on non-trivial work.
- On demand when you want a second opinion on an in-progress branch: `python3 .claude/skills/pre-pr-review/run.py --diff-spec main...HEAD`.
- NOT from a git hook — keep LLM calls out of `git push` so network hiccups don't brick pushing.

## Not in scope

- Replacing `/qa`. `/qa` is Claude's own review with kit-specific rules; this is the other-model counterweight. Running both is the point.
- Auto-fixing findings. This skill only reports; fixes go through `/address-review` + user approval.
- Polling Copilot's actual PR review. That happens server-side once the PR is open and is handled by `/pr-comments`.

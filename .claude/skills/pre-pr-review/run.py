#!/usr/bin/env python3
"""
pre-pr-review runner: ships the current branch's diff to an OpenAI model
(default gpt-4.1, overridable via $CLAUDEKIT_REVIEW_MODEL) and prints the
findings.

Why OpenAI and not Claude? Same-model review has correlated blind spots.
claude-kit already runs Claude-side review via /qa. This gate exists so a
*different model's weights* see the diff before the PR is opened — catches
exactly the class of things Copilot would flag on the PR.

Design decisions:
- No `pip install openai`. Uses only Python stdlib (urllib, json, os).
  claude-kit already soft-depends on python3; adding an external package
  would make inject.sh heavier for uncertain gain.
- Graceful degradation: if $OPENAI_API_KEY is unset, exit 0 with a note.
  /ship should NOT block just because the optional review channel is off.
- Diff scoped to branch-vs-merge-base by default. Caller can pass a custom
  git diff spec via --diff-spec.
- JSON response_format asked of the model so we can render structured
  findings instead of free-form prose. If the model returns malformed JSON,
  we dump the raw text and warn — better partial output than none.

Exit codes:
  0 — review ran successfully (or was skipped gracefully)
  1 — caller/config error (bad args, no git repo, etc.)
  2 — the model flagged CRITICAL findings (for CI integration that wants
      to treat that as a gate; /ship only *warns* on this today)
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
RUBRIC_PATH = SCRIPT_DIR / "copilot-style-rubric.md"

DEFAULT_MODEL = os.environ.get("CLAUDEKIT_REVIEW_MODEL", "gpt-4.1")
API_URL = "https://api.openai.com/v1/chat/completions"
# Cap diff size fed to the model. Everything above is truncated with a
# marker so the reviewer sees SOMETHING rather than nothing. 160k chars ≈
# ~40k tokens — leaves room for the rubric (~2k) and response (~4k) well
# under typical 128k context windows.
MAX_DIFF_CHARS = 160_000


def run(cmd: list[str], cwd: Path | None = None) -> str:
    """Run a subprocess, return stdout. Raise with stderr on failure."""
    result = subprocess.run(
        cmd, cwd=cwd, check=False, capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)} failed: {result.stderr.strip()}")
    return result.stdout


def resolve_diff_spec(custom: str | None, repo_root: Path) -> str:
    if custom:
        return custom
    # Prefer merge-base with origin/main; fall back to origin/master, then
    # HEAD~1 if neither remote branch exists (e.g. brand-new repo).
    for base in ("origin/main", "origin/master", "main", "master"):
        try:
            mb = run(["git", "merge-base", "HEAD", base], cwd=repo_root).strip()
            if mb:
                return f"{mb}...HEAD"
        except RuntimeError:
            continue
    return "HEAD~1...HEAD"


def fetch_diff(spec: str, repo_root: Path) -> str:
    # --stat first so we report file count even if the unified diff is huge.
    try:
        return run(["git", "diff", "--unified=3", spec], cwd=repo_root)
    except RuntimeError as e:
        raise SystemExit(f"error: could not compute diff ({spec}): {e}")


def load_rubric() -> str:
    if not RUBRIC_PATH.exists():
        raise SystemExit(f"error: rubric missing at {RUBRIC_PATH}")
    return RUBRIC_PATH.read_text(encoding="utf-8")


def build_request(diff: str, rubric: str, model: str) -> dict:
    if len(diff) > MAX_DIFF_CHARS:
        diff = diff[:MAX_DIFF_CHARS] + "\n\n[...diff truncated for length...]"

    return {
        "model": model,
        "response_format": {"type": "json_object"},
        "temperature": 0.2,
        "messages": [
            {"role": "system", "content": rubric},
            {
                "role": "user",
                "content": (
                    "Review the following unified diff. Respond ONLY with the "
                    "JSON object specified in your instructions.\n\n"
                    "```diff\n" + diff + "\n```"
                ),
            },
        ],
    }


def call_openai(body: dict, api_key: str, timeout: int = 120) -> dict:
    payload = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"OpenAI API error {e.code}: {detail}")
    except urllib.error.URLError as e:
        raise SystemExit(f"OpenAI API unreachable: {e.reason}")


def extract_content(resp: dict) -> str:
    try:
        return resp["choices"][0]["message"]["content"]
    except (KeyError, IndexError):
        raise SystemExit(f"unexpected OpenAI response shape: {json.dumps(resp)[:500]}")


def render(findings_obj: dict, model: str) -> int:
    """Pretty-print to terminal. Returns suggested exit code."""
    counts = findings_obj.get("counts") or {"critical": 0, "important": 0, "suggestion": 0}
    critical = int(counts.get("critical", 0))
    important = int(counts.get("important", 0))
    suggestion = int(counts.get("suggestion", 0))

    print(f"=== pre-pr-review ({model}) ===")
    summary = findings_obj.get("summary", "").strip()
    if summary:
        print(f"Summary: {summary}")
    print(f"Counts: CRITICAL={critical}  IMPORTANT={important}  SUGGESTION={suggestion}")
    print()

    findings = findings_obj.get("findings") or []
    if not findings:
        print("No findings. Diff is clean per the rubric.")
        return 0

    # Render in priority order.
    priority_order = {"CRITICAL": 0, "IMPORTANT": 1, "SUGGESTION": 2}
    findings.sort(key=lambda f: (priority_order.get(f.get("priority", "SUGGESTION"), 99),
                                 f.get("file", ""), f.get("line", 0)))
    for f in findings:
        pri = f.get("priority", "?")
        cat = f.get("category", "?")
        file_ = f.get("file", "?")
        line = f.get("line", "?")
        title = f.get("title", "").strip()
        why = f.get("why", "").strip()
        fix = f.get("fix", "").strip()
        print(f"[{pri}] {cat}: {file_}:{line} — {title}")
        if why:
            print(f"  Why: {why}")
        if fix:
            # Indent fix block
            for ln in fix.splitlines():
                print(f"  {ln}")
        print()

    return 2 if critical > 0 else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="OpenAI-backed pre-PR code review.")
    parser.add_argument(
        "--diff-spec", default=None,
        help="git diff spec, e.g. 'origin/main...HEAD'. Default: merge-base with origin/main.",
    )
    parser.add_argument(
        "--model", default=DEFAULT_MODEL,
        help=f"OpenAI model id (default: {DEFAULT_MODEL} via $CLAUDEKIT_REVIEW_MODEL).",
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Emit raw JSON findings instead of human-readable output.",
    )
    args = parser.parse_args()

    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not api_key:
        print("pre-pr-review: $OPENAI_API_KEY not set. Skipping OpenAI review.",
              file=sys.stderr)
        print("  Set OPENAI_API_KEY to enable a different-model reviewer.",
              file=sys.stderr)
        return 0

    try:
        repo_root = Path(run(["git", "rev-parse", "--show-toplevel"]).strip())
    except RuntimeError:
        print("pre-pr-review: not a git repo; nothing to review.", file=sys.stderr)
        return 0

    spec = resolve_diff_spec(args.diff_spec, repo_root)
    diff = fetch_diff(spec, repo_root)

    # Fallback: if the default branch-vs-main spec is empty AND the caller
    # didn't pass an explicit --diff-spec, try the working-tree diff
    # (uncommitted changes vs HEAD). Catches the "WIP review before first
    # commit on a branch" case that would otherwise report empty and skip.
    if not diff.strip() and args.diff_spec is None:
        wip_diff = fetch_diff("HEAD", repo_root)
        if wip_diff.strip():
            print(f"pre-pr-review: no commits past main; reviewing uncommitted working tree instead.",
                  file=sys.stderr)
            spec = "HEAD (working tree)"
            diff = wip_diff

    if not diff.strip():
        print(f"pre-pr-review: diff '{spec}' is empty; nothing to review.")
        return 0

    rubric = load_rubric()
    body = build_request(diff, rubric, args.model)
    resp = call_openai(body, api_key)
    content = extract_content(resp)

    try:
        findings_obj = json.loads(content)
    except json.JSONDecodeError:
        print("pre-pr-review: model returned non-JSON output. Raw content:",
              file=sys.stderr)
        print(content)
        return 1

    if args.json:
        print(json.dumps(findings_obj, indent=2))
        counts = findings_obj.get("counts") or {}
        return 2 if int(counts.get("critical", 0)) > 0 else 0

    return render(findings_obj, args.model)


if __name__ == "__main__":
    sys.exit(main())

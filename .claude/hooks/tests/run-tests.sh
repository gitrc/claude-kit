#!/usr/bin/env bash
# Hook test harness — plain bash, no bats dependency.
# Covers the state machines, portability fallbacks, and security-relevant
# behaviors of the Stop and UserPromptSubmit hooks. Run from anywhere:
#
#   bash .claude/hooks/tests/run-tests.sh
#
# Each test:
#   - sets up an isolated project dir under /tmp
#   - invokes the hook with crafted JSON on stdin
#   - asserts the observable outcome (stdout, exit code, marker state)
#
# Returns non-zero if any test fails. Prints a concise summary.

set -uo pipefail

# Resolve repo root (two levels up from .claude/hooks/tests/)
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$HOOKS_DIR/../.." && pwd)"

STOP_GATE="$HOOKS_DIR/stop-gate.sh"
TEST_EVIDENCE="$HOOKS_DIR/test-evidence.sh"
SESSION_START="$HOOKS_DIR/session-start.sh"

PASS=0
FAIL=0
FAIL_NAMES=()

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'

pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail() { FAIL=$((FAIL+1)); FAIL_NAMES+=("$1"); echo -e "  ${RED}✗${NC} $1 — $2"; }

# Build a temp project with N new lines in app.py so the diff is non-trivial.
new_project() {
  local dir="$1"
  local lines="${2:-8}"
  rm -rf "$dir"
  mkdir -p "$dir/tests"
  cd "$dir"
  git init -q -b main
  git config user.email t@t.local
  git config user.name test
  cat > pyproject.toml <<'TOML'
[project]
name = "x"
version = "0.0.1"
[tool.pytest.ini_options]
testpaths = ["tests"]
TOML
  echo "def f0(): pass" > app.py
  git add -A && git commit -q -m init
  # Dirty the working tree so hooks actually see changes.
  for i in $(seq 1 "$lines"); do echo "def f${i}(): pass" >> app.py; done
}

# Clean up any cache state for a session_id.
wipe_session() {
  local sid="$1"
  rm -rf "$HOME/.cache/claude-kit/sessions/$sid" 2>/dev/null || true
}

# Run a hook and return its stdout. Swallows stderr.
run_hook() {
  local hook="$1"
  local input="$2"
  local dir="$3"
  CLAUDE_PROJECT_DIR="$dir" bash "$hook" <<< "$input" 2>/dev/null
}

# --- Tests ------------------------------------------------------------------

test_stop_gate_empty_diff() {
  local dir=/tmp/ckit-t-$$-empty
  new_project "$dir" 0
  git -C "$dir" add -A && git -C "$dir" commit -q -m clean
  wipe_session s1
  local out
  out=$(run_hook "$STOP_GATE" '{"session_id":"s1"}' "$dir")
  if [ -z "$out" ]; then pass "stop-gate: empty diff → allow"; else fail "stop-gate: empty diff → allow" "got output: $out"; fi
  rm -rf "$dir"
}

test_stop_gate_trivial_diff() {
  local dir=/tmp/ckit-t-$$-triv
  new_project "$dir" 3
  wipe_session s2
  local out
  out=$(run_hook "$STOP_GATE" '{"session_id":"s2"}' "$dir")
  if [ -z "$out" ]; then pass "stop-gate: <5 line diff → allow"; else fail "stop-gate: <5 line diff → allow" "unexpected output"; fi
  rm -rf "$dir"
}

test_stop_gate_blocks_then_allows() {
  local dir=/tmp/ckit-t-$$-block
  new_project "$dir" 8
  wipe_session s3
  local o1 o2
  o1=$(run_hook "$STOP_GATE" '{"session_id":"s3"}' "$dir")
  echo "$o1" | grep -q '"decision": "block"' || { fail "stop-gate: first stop blocks" "no block JSON: $o1"; rm -rf "$dir"; return; }
  o2=$(run_hook "$STOP_GATE" '{"session_id":"s3"}' "$dir")
  if [ -z "$o2" ]; then pass "stop-gate: first blocks, second allows (no loop)"; else fail "stop-gate: second stop allow" "got output: $o2"; fi
  rm -rf "$dir"
}

test_stop_gate_content_edit_reblocks() {
  # The fingerprint must change when content changes within the same file set.
  local dir=/tmp/ckit-t-$$-content
  new_project "$dir" 8
  wipe_session s4
  local o1 o2 o3
  o1=$(run_hook "$STOP_GATE" '{"session_id":"s4"}' "$dir")
  o2=$(run_hook "$STOP_GATE" '{"session_id":"s4"}' "$dir")
  # Now edit the same file's content
  echo "# extra line" >> "$dir/app.py"
  o3=$(run_hook "$STOP_GATE" '{"session_id":"s4"}' "$dir")
  if echo "$o3" | grep -q '"decision": "block"'; then pass "stop-gate: content edit → re-blocks"; else fail "stop-gate: content edit" "no re-block on edit"; fi
  rm -rf "$dir"
}

test_stop_gate_sanitizes_session_id() {
  # Path-traversal session_id must not escape the cache dir.
  local dir=/tmp/ckit-t-$$-sid
  new_project "$dir" 8
  local evil='../../etc/passwd'
  local o1
  o1=$(run_hook "$STOP_GATE" "{\"session_id\":\"$evil\"}" "$dir")
  # Marker must be under ~/.cache/claude-kit, NOT anywhere under /etc/
  local leak
  leak=$(find "$HOME/.cache/claude-kit" -name 'stop-gate.fp' -newer /tmp 2>/dev/null | head -1 || true)
  if [ -n "$leak" ] && [[ "$leak" != *..* ]]; then
    pass "stop-gate: path-traversal session_id contained"
  else
    fail "stop-gate: session_id sanitization" "marker not in expected cache dir (leak=$leak)"
  fi
  rm -rf "$dir"
  # Clean up the sanitized marker dir
  rm -rf "$HOME/.cache/claude-kit/sessions/______etc_passwd" 2>/dev/null
}

test_test_evidence_broad_grep_suppressed_in_prose() {
  # Prose mention of "pytest" in user prompt text (not a "command" JSON) must
  # not satisfy the gate.
  local dir=/tmp/ckit-t-$$-te-prose
  new_project "$dir" 8
  wipe_session s5
  local tp=/tmp/ckit-t-$$-te-prose-transcript.jsonl
  cat > "$tp" <<'JSONL'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"please do not run pytest"}]}}
JSONL
  local o
  o=$(run_hook "$TEST_EVIDENCE" "{\"session_id\":\"s5\",\"transcript_path\":\"$tp\"}" "$dir")
  if echo "$o" | grep -q '"decision": "block"'; then pass "test-evidence: prose mention does NOT satisfy gate"; else fail "test-evidence: prose mention" "incorrectly allowed (false-positive grep): $o"; fi
  rm -f "$tp"
  rm -rf "$dir"
}

test_test_evidence_tool_command_satisfies() {
  # A real Bash tool invocation of pytest in the transcript must allow.
  local dir=/tmp/ckit-t-$$-te-cmd
  new_project "$dir" 8
  wipe_session s6
  local tp=/tmp/ckit-t-$$-te-cmd-transcript.jsonl
  cat > "$tp" <<'JSONL'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"source .venv/bin/activate && pytest -v"}}]}}
JSONL
  local o
  o=$(run_hook "$TEST_EVIDENCE" "{\"session_id\":\"s6\",\"transcript_path\":\"$tp\"}" "$dir")
  if [ -z "$o" ]; then pass "test-evidence: real tool call → allow"; else fail "test-evidence: real tool call" "unexpected block: $o"; fi
  rm -f "$tp"
  rm -rf "$dir"
}

test_test_evidence_loop_proof() {
  # When user forbids tests entirely, hook must block ONCE then allow on same
  # fingerprint (fingerprint-based backstop).
  local dir=/tmp/ckit-t-$$-te-loop
  new_project "$dir" 8
  wipe_session s7
  local tp=/tmp/ckit-t-$$-te-loop-transcript.jsonl
  echo "no tests here" > "$tp"
  local o1 o2 o3
  o1=$(run_hook "$TEST_EVIDENCE" "{\"session_id\":\"s7\",\"transcript_path\":\"$tp\"}" "$dir")
  echo "$o1" | grep -q '"decision": "block"' || { fail "test-evidence: first stop blocks" "no block: $o1"; rm -f "$tp"; rm -rf "$dir"; return; }
  o2=$(run_hook "$TEST_EVIDENCE" "{\"session_id\":\"s7\",\"transcript_path\":\"$tp\"}" "$dir")
  o3=$(run_hook "$TEST_EVIDENCE" "{\"session_id\":\"s7\",\"transcript_path\":\"$tp\"}" "$dir")
  if [ -z "$o2" ] && [ -z "$o3" ]; then pass "test-evidence: block once, allow after (loop-proof)"; else fail "test-evidence: loop-proof" "second/third call still blocked"; fi
  rm -f "$tp"
  rm -rf "$dir"
}

test_session_start_nudges_once() {
  # Preflight should fire once per session_id (not once per bash PID).
  local dir=/tmp/ckit-t-$$-pre
  rm -rf "$dir"
  mkdir -p "$dir"
  cd "$dir"
  git init -q -b main
  # Intentionally NOT configuring core.hooksPath or CLAUDE.md so the nudge fires
  cp "$REPO_ROOT/CLAUDE.md.template" .
  wipe_session s8
  local o1 o2 o3
  o1=$(run_hook "$SESSION_START" '{"session_id":"s8"}' "$dir")
  o2=$(run_hook "$SESSION_START" '{"session_id":"s8"}' "$dir")
  o3=$(run_hook "$SESSION_START" '{"session_id":"s8"}' "$dir")
  if [ -n "$o1" ] && [ -z "$o2" ] && [ -z "$o3" ]; then
    pass "session-start: nudges once per session_id, then silent"
  else
    fail "session-start: once-per-session" "o1=$([ -n "$o1" ] && echo present || echo empty) o2=$([ -n "$o2" ] && echo present || echo empty) o3=$([ -n "$o3" ] && echo present || echo empty)"
  fi
  rm -rf "$dir"
}

test_session_start_silent_after_setup() {
  # Hooks configured + CLAUDE.md present → no nudge.
  local dir=/tmp/ckit-t-$$-pre-ok
  rm -rf "$dir"
  mkdir -p "$dir/.githooks"
  cd "$dir"
  git init -q -b main
  git config core.hooksPath .githooks
  cp "$REPO_ROOT/CLAUDE.md.template" CLAUDE.md
  wipe_session s9
  local o
  o=$(run_hook "$SESSION_START" '{"session_id":"s9"}' "$dir")
  if [ -z "$o" ]; then pass "session-start: configured project → silent"; else fail "session-start: configured silent" "nudged anyway: $o"; fi
  rm -rf "$dir"
}

# --- Run all tests ----------------------------------------------------------
echo ""
echo "Hook test harness — $(date +%H:%M:%S)"
echo ""

test_stop_gate_empty_diff
test_stop_gate_trivial_diff
test_stop_gate_blocks_then_allows
test_stop_gate_content_edit_reblocks
test_stop_gate_sanitizes_session_id
test_test_evidence_broad_grep_suppressed_in_prose
test_test_evidence_tool_command_satisfies
test_test_evidence_loop_proof
test_session_start_nudges_once
test_session_start_silent_after_setup

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}FAILED${NC}: $FAIL of $((PASS + FAIL)) tests"
  printf '  - %s\n' "${FAIL_NAMES[@]}"
  exit 1
else
  echo -e "${GREEN}All $PASS tests passed.${NC}"
  exit 0
fi

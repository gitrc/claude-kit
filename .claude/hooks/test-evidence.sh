#!/usr/bin/env bash
# Test-evidence gate: blocks completion when code changes exist in a project
# with a detectable test runner but no test command ran in this session.
# Uses the same fingerprint-based one-block backstop as stop-gate so a user
# who explicitly forbids tests can't trigger an infinite block loop.

set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

input=$(cat)
session_id_raw=$(json_extract_string "session_id" "$input")
session_id=$(sanitize_session_id "${session_id_raw:-unknown}")
transcript_path=$(json_extract_string "transcript_path" "$input")
state_dir=$(session_state_dir "$session_id")
marker="$state_dir/test-evidence.fp"

detect_code_changes

if [ -z "${CK_ALL_CHANGES}" ]; then
  rm -f "$marker" 2>/dev/null || true
  exit 0
fi

diff_lines=$(count_diff_lines)
if [ "${diff_lines:-0}" -lt 5 ] && [ -z "${CK_UNTRACKED_FILES}" ]; then
  rm -f "$marker" 2>/dev/null || true
  exit 0
fi

# --- Detect a test runner for this project ---
has_tests=false
test_command_hint=""

if [ -f pytest.ini ]; then
  has_tests=true; test_command_hint="pytest"
elif [ -f pyproject.toml ] && grep -q '\[tool\.pytest' pyproject.toml 2>/dev/null; then
  has_tests=true; test_command_hint="pytest"
elif [ -d tests ] && ls tests/*.py 2>/dev/null | head -1 | grep -q .; then
  has_tests=true; test_command_hint="pytest"
elif [ -f package.json ] && grep -q '"test"' package.json && ! grep -q '"test":[[:space:]]*"echo.*Error.*no test specified' package.json; then
  has_tests=true; test_command_hint="npm test"
elif [ -f Cargo.toml ]; then
  has_tests=true; test_command_hint="cargo test"
elif find . -maxdepth 3 -name '*_test.go' 2>/dev/null | head -1 | grep -q .; then
  has_tests=true; test_command_hint="go test ./..."
elif [ -f build.sbt ]; then
  has_tests=true; test_command_hint="sbt test"
elif [ -f pom.xml ]; then
  has_tests=true; test_command_hint="mvn test"
elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  has_tests=true; test_command_hint="./gradlew test"
elif [ -f Package.swift ]; then
  has_tests=true; test_command_hint="swift test"
fi

if [ "$has_tests" = false ]; then
  exit 0
fi

# --- Check transcript for a test command this session ---
if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  # Can't verify — skip rather than false-block
  exit 0
fi

# Constrain match to tool-command shapes (JSON `"command":"...pytest..."`) and
# shell-ish invocations. Avoids matching the word "pytest" in plain prose.
if grep -qE '"command"[[:space:]]*:[[:space:]]*"[^"]*(pytest|npm (run )?test|yarn test|pnpm test|bun test|cargo test|go test|sbt( |/)test|mvn( |/)test|gradle(w)?( |/)test|swift test|jest|vitest|mocha|rspec|rake test|make test|\./test\.sh|\./run_tests\.sh|tox)' "$transcript_path" 2>/dev/null; then
  rm -f "$marker" 2>/dev/null || true
  exit 0
fi

# --- Set-union one-block backstop (loop-proof + shrink-safe) ---
if marker_check_and_update "$marker"; then
  exit 0
fi

file_count=$(echo "${CK_ALL_CHANGES}" | grep -c . || echo 0)
reason="Code changes in $file_count file(s) (~${diff_lines} lines), but no test command was run in this session. Run the test suite (e.g., $test_command_hint) and confirm it passes before completing. If tests genuinely do not apply to this change, say so explicitly and the user will decide."
emit_block "$reason"

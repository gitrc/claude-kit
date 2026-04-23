#!/usr/bin/env bash
# Stop hook: on the first stop where code changes exist in a project that has
# a test runner and no test command has run in this session, block once and
# request that tests be run. On subsequent stops with the SAME fingerprint,
# allow — Claude has already been asked. When the fingerprint changes (new
# code), request again. This mirrors stop-gate's one-block-per-fingerprint
# pattern to prevent infinite loops if the user explicitly forbids running
# tests and Claude keeps trying to stop.
#
# Skip cases (exit 0 without blocking):
#   - No code changes
#   - Diff is trivial (<5 lines, no untracked code files)
#   - No test runner detected for this project
#   - A recognizable test command appears in the transcript
#   - This fingerprint was already requested for test-evidence this session

set -euo pipefail

cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || exit 0

input=$(cat)

extract_json_string() {
  echo "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

session_id=$(extract_json_string "session_id")
session_id="${session_id:-unknown}"
transcript_path=$(extract_json_string "transcript_path")

marker="/tmp/claude-test-evidence-${session_id}"

# --- 1. Detect code changes (mirrors stop-gate) ---
code_extensions='py|java|scala|kt|ts|tsx|js|jsx|rs|swift|go|rb|c|cpp|h|hpp|cs|php|vue|svelte'
changed_files=$(git diff HEAD --name-only 2>/dev/null | grep -E "\.($code_extensions)$" || true)
untracked_files=$(git ls-files --others --exclude-standard 2>/dev/null | grep -E "\.($code_extensions)$" || true)
all_changes="${changed_files}${untracked_files}"

if [ -z "$all_changes" ]; then
  rm -f "$marker" 2>/dev/null
  exit 0
fi

diff_lines=$(git diff HEAD --stat 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo "0")
if [ "${diff_lines:-0}" -lt 5 ] && [ -z "$untracked_files" ]; then
  rm -f "$marker" 2>/dev/null
  exit 0
fi

# --- 2. Detect a test runner for this project ---
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

# --- 3. Check transcript for a test run in this session ---
if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  # Can't verify — be conservative, skip rather than false-block
  exit 0
fi

# Recognizable test invocations. Intentionally broad; false-positives here just
# mean "Claude satisfied the gate with something test-ish," which is fine.
if grep -qE '(pytest|npm (run )?test|yarn test|pnpm test|bun test|cargo test|go test|sbt( |/)test|mvn( |/)test|gradle(w)?( |/)test|swift test|jest|vitest|mocha|rspec|rake test|make test|\./test\.sh|\./run_tests\.sh|tox)' "$transcript_path" 2>/dev/null; then
  rm -f "$marker" 2>/dev/null
  exit 0
fi

# --- 4. Fingerprint-based one-block backstop ---
# Prevents infinite loop when the user forbids tests: ask once per change-set,
# then allow. New code (different fingerprint) re-requests.
if command -v shasum &>/dev/null; then
  current_fingerprint=$(echo "$all_changes" | sort | shasum -a 256 | cut -d' ' -f1)
elif command -v sha256sum &>/dev/null; then
  current_fingerprint=$(echo "$all_changes" | sort | sha256sum | cut -d' ' -f1)
else
  current_fingerprint=$(echo "$all_changes" | sort | tr '\n' '|')
fi

if [ -f "$marker" ]; then
  stored=$(cat "$marker" 2>/dev/null || echo "")
  if [ "$current_fingerprint" = "$stored" ]; then
    exit 0
  fi
fi

echo "$current_fingerprint" > "$marker"

# --- 5. Block ---
file_count=$(echo "$all_changes" | wc -l | tr -d ' ')

# Build reason as a plain string to avoid heredoc quoting pitfalls.
reason="Code changes in $file_count file(s) (~${diff_lines:-?} lines), but no test command was run in this session. Run the test suite (e.g., $test_command_hint) and confirm it passes before completing. If tests genuinely do not apply to this change, say so explicitly and the user will decide."

# Emit JSON; escape double quotes in the reason just in case.
escaped_reason=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"decision": "block", "reason": "%s"}\n' "$escaped_reason"

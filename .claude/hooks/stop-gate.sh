#!/usr/bin/env bash
# Stop-gate: on the first stop where non-trivial code changes exist, request a
# review. On subsequent stops with the SAME fingerprint, allow — Claude has
# already been asked and had a chance to respond. When the fingerprint changes
# (new code), request review again. When the diff empties (committed), reset.
#
# The prior design tried to verify that a review *actually happened* by
# comparing transcript mtime against the marker mtime. That produced an
# infinite block loop when the transcript wasn't flushed before the hook ran.
# This design is strictly simpler: one block per unique set of changes.
set -euo pipefail

cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || exit 0

input=$(cat)

extract_json_string() {
  echo "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

session_id=$(extract_json_string "session_id")
session_id="${session_id:-unknown}"

# Detect code changes (file-set only; content edits within the same file set
# count as the same fingerprint so Claude can iterate on review feedback
# without being re-blocked).
code_extensions='py|java|scala|kt|ts|tsx|js|jsx|rs|swift|go|rb|c|cpp|h|hpp|cs|php|vue|svelte'
changed_files=$(git diff HEAD --name-only 2>/dev/null | grep -E "\.($code_extensions)$" || true)
untracked_files=$(git ls-files --others --exclude-standard 2>/dev/null | grep -E "\.($code_extensions)$" || true)
all_changes="${changed_files}${untracked_files}"

marker="/tmp/claude-stopgate-${session_id}"

if [ -z "$all_changes" ]; then
  rm -f "$marker" 2>/dev/null
  exit 0
fi

# Skip trivial changes (<5 lines, no untracked)
diff_lines=$(git diff HEAD --stat 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo "0")
if [ "${diff_lines:-0}" -lt 5 ] && [ -z "$untracked_files" ]; then
  rm -f "$marker" 2>/dev/null
  exit 0
fi

# Fingerprint the sorted file-set.
if command -v shasum &>/dev/null; then
  current_fingerprint=$(echo "$all_changes" | sort | shasum -a 256 | cut -d' ' -f1)
elif command -v sha256sum &>/dev/null; then
  current_fingerprint=$(echo "$all_changes" | sort | sha256sum | cut -d' ' -f1)
else
  current_fingerprint=$(echo "$all_changes" | sort | tr '\n' '|')
fi

# If this fingerprint was already requested for review this session, allow.
# Otherwise, record it and request review (block once).
if [ -f "$marker" ]; then
  stored=$(cat "$marker" 2>/dev/null || echo "")
  if [ "$current_fingerprint" = "$stored" ]; then
    exit 0
  fi
fi

echo "$current_fingerprint" > "$marker"

file_count=$(echo "$all_changes" | wc -l | tr -d ' ')
file_list=$(echo "$all_changes" | head -20 | tr '\n' ',' | sed 's/,$//; s/,/, /g')
reason="Code changes detected in $file_count file(s) (~${diff_lines:-?} lines). Before completing, review the changes: read each changed file, check for bugs, security issues, error handling gaps, and adherence to CLAUDE.md conventions. Report findings to the user, then you may complete. Changed files: $file_list"
escaped_reason=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n')
printf '{"decision": "block", "reason": "%s"}\n' "$escaped_reason"

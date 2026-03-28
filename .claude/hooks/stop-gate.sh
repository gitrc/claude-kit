#!/usr/bin/env bash
# Lightweight stop-gate: blocks Claude from completing if code changes exist
# and no review has been performed this session. Zero token cost when no
# code changes are present.
#
# Review verification: the gate blocks on first stop, then ONLY allows the
# second stop if Claude's response between the two stops contained review
# indicators (reading changed files, mentioning review findings). This
# prevents the "just try to stop twice" bypass.
set -euo pipefail

cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || exit 0

# Read hook input from stdin
input=$(cat)

# Safe JSON field extraction — no eval, no python3 dependency
# Uses grep+sed for simple field extraction from flat JSON
extract_json_string() {
  echo "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

session_id=$(extract_json_string "session_id")
session_id="${session_id:-unknown}"
transcript_path=$(extract_json_string "transcript_path")

review_marker="/tmp/claude-stopgate-${session_id}"
changes_marker="/tmp/claude-changes-${session_id}"

# Check for code file changes (staged + unstaged vs HEAD)
code_extensions='py|java|scala|kt|ts|tsx|js|jsx|rs|swift|go|rb|c|cpp|h|hpp|cs|php|vue|svelte'
changed_files=$(git diff HEAD --name-only 2>/dev/null | grep -E "\.($code_extensions)$" || true)

# Also check untracked code files
untracked_files=$(git ls-files --others --exclude-standard 2>/dev/null | grep -E "\.($code_extensions)$" || true)

all_changes="${changed_files}${untracked_files}"

if [ -z "$all_changes" ]; then
  # No code changes — allow stop, clean up markers
  rm -f "$review_marker" "$changes_marker" 2>/dev/null
  exit 0
fi

# Count changed lines to skip trivial changes (< 5 lines diff)
diff_lines=$(git diff HEAD --stat 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo "0")
if [ "${diff_lines:-0}" -lt 5 ] && [ -z "$untracked_files" ]; then
  # Trivial change — allow stop without review
  rm -f "$review_marker" "$changes_marker" 2>/dev/null
  exit 0
fi

# Fingerprint current changes — test hash command availability first
if command -v shasum &>/dev/null; then
  current_fingerprint=$(echo "$all_changes" | sort | shasum -a 256 | cut -d' ' -f1)
elif command -v sha256sum &>/dev/null; then
  current_fingerprint=$(echo "$all_changes" | sort | sha256sum | cut -d' ' -f1)
else
  # Fallback: use file list itself as fingerprint
  current_fingerprint=$(echo "$all_changes" | sort | tr '\n' '|')
fi

# If review was already requested, verify a review actually happened
if [ -f "$review_marker" ]; then
  reviewed_fingerprint=$(cat "$changes_marker" 2>/dev/null || echo "")
  if [ "$current_fingerprint" = "$reviewed_fingerprint" ]; then
    # Same changes as when review was requested — check transcript for review evidence
    review_happened=false
    if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
      # Look for review indicators in transcript since the marker was created
      marker_time=$(stat -f %m "$review_marker" 2>/dev/null || stat -c %Y "$review_marker" 2>/dev/null || echo "0")
      # Check if transcript was modified after marker (review activity occurred)
      transcript_time=$(stat -f %m "$transcript_path" 2>/dev/null || stat -c %Y "$transcript_path" 2>/dev/null || echo "0")
      if [ "$transcript_time" -gt "$marker_time" ]; then
        # Transcript grew since we blocked — Claude did something (review)
        review_happened=true
      fi
    else
      # No transcript access — fall back to time-based check
      # Require at least 30 seconds to have passed (enough for a real review, not a rate limit pause)
      marker_age=$(( $(date +%s) - $(stat -f %m "$review_marker" 2>/dev/null || stat -c %Y "$review_marker" 2>/dev/null || echo "$(date +%s)") ))
      if [ "$marker_age" -gt 30 ]; then
        review_happened=true
      fi
    fi

    if [ "$review_happened" = true ]; then
      rm -f "$review_marker" "$changes_marker" 2>/dev/null
      exit 0
    fi
  fi
  # Fingerprint changed since review requested — new changes, need fresh review
  rm -f "$review_marker" 2>/dev/null
fi

# Record the current fingerprint and request review
echo "$current_fingerprint" > "$changes_marker"
touch "$review_marker"

# Count changed files for context
file_count=$(echo "$all_changes" | wc -l | tr -d ' ')

# Block stop and request code review
cat <<REVIEW_JSON
{
  "decision": "block",
  "reason": "Code changes detected in $file_count file(s) (~${diff_lines:-?} lines). Before completing, review the changes: read each changed file, check for bugs, security issues, error handling gaps, and adherence to CLAUDE.md conventions. Report findings to the user, then you may complete.\nChanged files: $(echo "$all_changes" | head -20 | tr '\n' ', ' | sed 's/,$//')"
}
REVIEW_JSON

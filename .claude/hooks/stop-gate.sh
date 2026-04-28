#!/usr/bin/env bash
# Stop-gate: requests a code review once per unreviewed (path, content-hash)
# pair. The marker stores the union of all pairs ever blocked-on this
# session; on each stop, current pairs minus stored pairs = unreviewed work.
#
# Adding work or editing in place produces new pairs → re-blocks.
# Discarding work shrinks the set (current ⊆ stored) → allows.
# Diff-empty resets the marker.
#
# Markers live under the per-user XDG cache (not /tmp) to prevent symlink
# attacks and cross-user collisions on shared systems.

set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

input=$(cat)
session_id_raw=$(json_extract_string "session_id" "$input")
session_id=$(sanitize_session_id "${session_id_raw:-unknown}")
state_dir=$(session_state_dir "$session_id")
marker="$state_dir/stop-gate.fp"

detect_code_changes

# No code changes — clean up and allow.
if [ -z "${CK_ALL_CHANGES}" ]; then
  rm -f "$marker" 2>/dev/null || true
  exit 0
fi

# Skip trivial changes (<5 line diff AND no untracked code files).
diff_lines=$(count_diff_lines)
if [ "${diff_lines:-0}" -lt 5 ] && [ -z "${CK_UNTRACKED_FILES}" ]; then
  rm -f "$marker" 2>/dev/null || true
  exit 0
fi

# Set-union marker: allow when current pairs ⊆ stored pairs (already blocked
# on every artifact). Otherwise update marker and block.
if marker_check_and_update "$marker"; then
  exit 0
fi

file_count=$(echo "${CK_ALL_CHANGES}" | grep -c . || echo 0)
file_list=$(echo "${CK_ALL_CHANGES}" | head -20 | tr '\n' ',' | sed 's/,$//; s/,/, /g')

# Prescriptive: name the skills that do the review, don't just describe the action.
# `/qa` fans out three parallel reviewers (security, correctness, architecture).
# `/pre-pr-review` ships the diff to a different model (gpt-4.1) for council-of-LLMs coverage.
extra=""
if [ -n "${OPENAI_API_KEY:-}" ]; then
  extra=" Then run /pre-pr-review before shipping for a different-model second opinion."
fi
reason="Code changes detected in $file_count file(s) (~${diff_lines} lines). Run /qa to fan out three parallel reviewers (security, correctness, architecture) before completing. If /qa is unavailable, review the changes directly: check each file for bugs, security issues, error handling, and CLAUDE.md adherence, then report findings.${extra} Changed files: $file_list"
emit_block "$reason"

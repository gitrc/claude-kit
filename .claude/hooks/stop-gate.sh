#!/usr/bin/env bash
# Stop-gate: requests a code review once per unique change-set fingerprint.
# On the first stop with non-trivial changes, blocks and records the
# fingerprint. On subsequent stops with the same fingerprint, allows —
# Claude has already been asked. Fingerprint change (new files or content
# edits) re-requests. Diff-empty resets.
#
# Fingerprint is git-tree-based and covers content edits, not just file names.
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

current_fp=$(compute_fingerprint)

# Already requested for this fingerprint? Allow.
if [ -f "$marker" ]; then
  stored=$(cat "$marker" 2>/dev/null || echo "")
  if [ "$current_fp" = "$stored" ]; then
    exit 0
  fi
fi

# First time for this fingerprint — record and block.
echo "$current_fp" > "$marker"

file_count=$(echo "${CK_ALL_CHANGES}" | grep -c . || echo 0)
file_list=$(echo "${CK_ALL_CHANGES}" | head -20 | tr '\n' ',' | sed 's/,$//; s/,/, /g')
reason="Code changes detected in $file_count file(s) (~${diff_lines} lines). Before completing, review the changes: read each changed file, check for bugs, security issues, error handling gaps, and adherence to CLAUDE.md conventions. Report findings to the user, then you may complete. Changed files: $file_list"
emit_block "$reason"

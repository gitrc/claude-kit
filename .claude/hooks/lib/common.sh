#!/usr/bin/env bash
# Shared helpers for claude-kit hooks.
# Source this from any hook script:  . "$(dirname "$0")/lib/common.sh"
#
# Design contracts (all functions):
#   - Must be safe to call under `set -euo pipefail`.
#   - Never modify CWD; callers are responsible.
#   - Never echo anything except documented stdout; log to stderr sparingly.
#   - Do not rely on python, jq, paste, or bc being installed.

# --- JSON extraction ---------------------------------------------------------
# Extract a string field from flat JSON on stdin or in a variable.
# Usage:
#   val=$(json_extract_string "field_name" "$input")
# Returns empty string on miss.
json_extract_string() {
  local field="$1"
  local blob="$2"
  printf '%s' "$blob" \
    | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

# --- Session ID sanitization -------------------------------------------------
# Enforce alphanumeric + - + _ only. Untrusted input (path traversal, symlink
# attack on /tmp markers) otherwise. Replaces unsafe chars with '_'.
sanitize_session_id() {
  local raw="$1"
  local clean
  clean=$(printf '%s' "$raw" | tr -c 'a-zA-Z0-9_-' '_')
  # Cap length to avoid pathological inputs
  clean="${clean:0:128}"
  printf '%s' "${clean:-unknown}"
}

# --- Per-session state directory --------------------------------------------
# Returns the per-user cache directory for a given session. Creates it with
# user-only permissions (700). Falls back to $TMPDIR/$USER/claude-kit if
# $HOME isn't writable.
#
# Using $HOME/.cache (XDG-style) instead of /tmp avoids:
#   - symlink attacks on shared /tmp
#   - cross-user collisions
#   - ephemerality in containers (though CI users should still be aware)
session_state_dir() {
  local session_id="$1"
  local base
  if [ -n "${XDG_CACHE_HOME:-}" ] && [ -w "${XDG_CACHE_HOME}" ] 2>/dev/null; then
    base="${XDG_CACHE_HOME}/claude-kit"
  elif [ -n "${HOME:-}" ] && [ -d "${HOME}" ] && [ -w "${HOME}" ]; then
    base="${HOME}/.cache/claude-kit"
  else
    base="${TMPDIR:-/tmp}/${USER:-claude}-claude-kit"
  fi
  local dir="${base}/sessions/${session_id}"
  mkdir -p "$dir" 2>/dev/null || true
  chmod 700 "$base" 2>/dev/null || true
  chmod 700 "${base}/sessions" 2>/dev/null || true
  chmod 700 "$dir" 2>/dev/null || true
  printf '%s' "$dir"
}

# --- Code-change detection ---------------------------------------------------
# Populates three globals (use in caller with `eval "$(detect_code_changes)"`):
#   CK_CHANGED_FILES — newline-separated tracked files changed vs HEAD (code only)
#   CK_UNTRACKED_FILES — untracked code files
#   CK_ALL_CHANGES — concatenation for emptiness-check and file count
# Returns via stdout in a format suitable for eval (safe — no user data).
#
# Called without args. Callers should cd to the project dir first.
CK_CODE_EXTENSIONS='py|java|scala|kt|ts|tsx|js|jsx|rs|swift|go|rb|c|cpp|h|hpp|cs|php|vue|svelte|mjs|cjs|pyi'

detect_code_changes() {
  # Intentionally separate variables so callers can iterate cleanly.
  local changed untracked
  changed=$(git diff HEAD --name-only 2>/dev/null | grep -E "\.($CK_CODE_EXTENSIONS)$" || true)
  untracked=$(git ls-files --others --exclude-standard 2>/dev/null | grep -E "\.($CK_CODE_EXTENSIONS)$" || true)

  # Export via environment so the caller can read them directly.
  export CK_CHANGED_FILES="$changed"
  export CK_UNTRACKED_FILES="$untracked"
  export CK_ALL_CHANGES="${changed}${untracked}"
}

# --- Diff line count (portable) ---------------------------------------------
# Count insertions+deletions using git's own --numstat instead of
# paste/bc/grep (which isn't portable to Alpine/busybox). Returns "0" on any
# failure so callers can safely compare with -lt/-gt.
count_diff_lines() {
  # numstat outputs "<ins>\t<del>\t<file>" per file; we sum ins and del.
  git diff HEAD --numstat 2>/dev/null | awk '
    {
      # Handle binary-file rows where ins/del are "-"
      if ($1 ~ /^[0-9]+$/) ins += $1
      if ($2 ~ /^[0-9]+$/) del += $2
    }
    END { print (ins + del) + 0 }
  ' 2>/dev/null || echo 0
}

# --- Fingerprint of current change-set --------------------------------------
# Produces a hash that changes when:
#   - any tracked code file's content changes (staged or unstaged)
#   - an untracked code file is added or removed
#   - a tracked file is renamed or deleted
#
# Built from `git diff HEAD --raw` (which lists blob SHAs for both index and
# working-tree versions) plus the sorted list of untracked code files. This
# is stateless — no index mutation, no working-tree mutation.
#
# Falls back through shasum -> sha256sum -> openssl -> truncated raw text.
compute_fingerprint() {
  # `git stash create` emits a commit SHA that represents the current
  # working tree + index WITHOUT modifying anything. The SHA changes
  # whenever any file content changes. When the working tree is clean,
  # it returns an empty string — we handle that by falling back to
  # HEAD's tree SHA so the fingerprint is still well-defined.
  local stash_sha
  stash_sha=$(git stash create 2>/dev/null || true)
  if [ -z "$stash_sha" ]; then
    stash_sha=$(git rev-parse HEAD^{tree} 2>/dev/null || echo "no-tree")
  fi

  # Sorted untracked code files so additions/removals change the fp.
  # (git stash create includes tracked changes but not untracked files by
  # default, so we fold them in explicitly.)
  local untracked_concat
  untracked_concat=$(printf '%s' "${CK_UNTRACKED_FILES:-}" | LC_ALL=C sort | tr '\n' '|')

  local raw="${stash_sha}||${untracked_concat}"

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$raw" | shasum -a 256 | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$raw" | sha256sum | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then
    printf '%s' "$raw" | openssl dgst -sha256 | awk '{print $NF}'
  else
    # Last-resort: raw string. Not a hash but stable and comparable.
    printf '%s' "${raw:0:512}"
  fi
}

# --- Emit a blocking Stop/PreToolUse JSON decision --------------------------
# Usage:  emit_block "reason text here"
# Escapes embedded " and \ and strips newlines, producing one JSON line.
emit_block() {
  local reason="$1"
  local escaped
  escaped=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n')
  printf '{"decision": "block", "reason": "%s"}\n' "$escaped"
}

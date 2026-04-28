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
  # Exclude untracked .claude/* — kit scaffolding (post-inject, pre-commit)
  # shouldn't trip the kit's own gates. Tracked changes inside .claude/ are
  # left alone so kit self-development still triggers reviews.
  untracked=$(git ls-files --others --exclude-standard 2>/dev/null \
    | grep -E "\.($CK_CODE_EXTENSIONS)$" \
    | grep -v -E '^\.claude/' \
    || true)

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

# --- Hash a single file's content (portable) --------------------------------
# Falls back through shasum -> sha256sum -> openssl -> size+mtime sentinel.
# Emits hex string on stdout. Empty output on error (caller should handle).
_hash_content() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" 2>/dev/null | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" 2>/dev/null | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$path" 2>/dev/null | awk '{print $NF}'
  else
    # Last-resort: byte count + mtime. Not collision-resistant but
    # locally stable enough for change detection.
    local size mt
    size=$(wc -c <"$path" 2>/dev/null | tr -d ' ')
    mt=$(stat -f %m "$path" 2>/dev/null || stat -c %Y "$path" 2>/dev/null)
    printf 'sz%s-mt%s' "${size:-0}" "${mt:-0}"
  fi
}

# --- Per-file pair set ------------------------------------------------------
# Emits one line per (path, content-hash) pair for the current dirty code
# state. Deleted tracked files emit "<path>\tDELETED" so the deletion is
# itself an artifact that gets reviewed once.
#
# Used by gates that need to know WHICH artifacts have already been blocked
# on, so a strictly-shrinking change-set (current ⊆ stored) skips re-blocking.
#
# Caller must have run detect_code_changes first.
compute_pair_set() {
  local f h
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ -f "$f" ]; then
      h=$(_hash_content "$f" || true)
      [ -z "$h" ] && continue
      printf '%s\t%s\n' "$f" "$h"
    else
      printf '%s\tDELETED\n' "$f"
    fi
  done <<< "${CK_CHANGED_FILES:-}"

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ ! -f "$f" ] && continue
    h=$(_hash_content "$f" || true)
    [ -z "$h" ] && continue
    printf '%s\t%s\n' "$f" "$h"
  done <<< "${CK_UNTRACKED_FILES:-}"
}

# --- Set-union marker logic -------------------------------------------------
# Returns 0 if the current pair set is a (non-strict) subset of what's
# already in the marker — meaning every artifact has been blocked on before
# and we should allow. Returns 1 if there's at least one unreviewed pair,
# in which case the caller should block; the marker is updated to
# stored ∪ current before returning.
#
# This is the loop-proof + shrink-safe replacement for whole-tree fingerprint
# compare. Adding work re-blocks. Discarding work allows. Editing in place
# re-blocks (new content-hash → new pair).
#
# Caller must have run detect_code_changes first.
marker_check_and_update() {
  local marker="$1"
  local current_pairs stored_pairs new_pairs
  current_pairs=$(compute_pair_set | LC_ALL=C sort -u)
  if [ -z "$current_pairs" ]; then
    return 0
  fi
  stored_pairs=""
  if [ -f "$marker" ]; then
    stored_pairs=$(LC_ALL=C sort -u "$marker" 2>/dev/null | grep -v '^$' || true)
  fi
  new_pairs=$(comm -23 \
    <(printf '%s\n' "$current_pairs") \
    <(printf '%s\n' "$stored_pairs") \
    | grep -v '^$' || true)
  if [ -z "$new_pairs" ]; then
    return 0
  fi
  { printf '%s\n' "$stored_pairs"; printf '%s\n' "$current_pairs"; } \
    | grep -v '^$' \
    | LC_ALL=C sort -u > "$marker"
  return 1
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

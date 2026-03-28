#!/usr/bin/env bash
# PreToolUse guard: monitors Edit and Write tool calls for security anti-patterns.
# Advisory only — warns with safe alternatives via additionalContext, never blocks.
set -euo pipefail

input=$(cat)

# Skip all checks if running with --dangerously-skip-permissions
perm_mode=$(echo "$input" | grep -o '"permission_mode"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"permission_mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [ "$perm_mode" = "bypassPermissions" ]; then
  exit 0
fi

# Extract tool name
tool_name=$(echo "$input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

# Only check Edit and Write tools
if [ "$tool_name" != "Edit" ] && [ "$tool_name" != "Write" ]; then
  exit 0
fi

# Instead of parsing nested JSON for content/new_string, grep the entire input
# for dangerous patterns. The raw JSON blob contains the code being written.

# Emit a warning via additionalContext (advisory, not blocking)
warn() {
  local pattern_name="$1"
  local message="$2"
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "SECURITY WARNING: ${pattern_name} detected. ${message} If this usage is intentional and safe, proceed with a comment explaining why."
  }
}
EOF
  exit 0
}

# --- Dynamic code execution ---
# Exclude safe variants: ast.literal_eval, jest's expect().toEqual(), etc.
if echo "$input" | grep -qiE 'eval\(' && ! echo "$input" | grep -qiE 'literal_eval\(|\.eval\('; then
  warn "eval(" "Risk: dynamic code execution (Python/JS/Ruby). Use ast.literal_eval() for Python, JSON.parse() for JS, or explicit parsing instead."
fi

echo "$input" | grep -qiE 'exec\(' && \
  warn "exec(" "Risk: dynamic code execution (Python). Use importlib or explicit function dispatch instead."

# --- Shell command execution ---
echo "$input" | grep -qiE 'os\.system\(' && \
  warn "os.system(" "Risk: shell command execution (Python). Use subprocess.run() with a list of args (no shell=True) instead."

echo "$input" | grep -qiE 'subprocess\.call.*shell=True' && \
  warn "subprocess.call with shell=True" "Risk: shell injection (Python). Use subprocess.run() with a list of args instead."

# --- XSS risks ---
echo "$input" | grep -qiE 'innerHTML|outerHTML' && \
  warn "innerHTML/outerHTML" "Risk: XSS via direct HTML injection (JS/TS). Use textContent, or a sanitization library like DOMPurify instead."

echo "$input" | grep -qiE 'dangerouslySetInnerHTML' && \
  warn "dangerouslySetInnerHTML" "Risk: React XSS. Use a sanitization library like DOMPurify, or render safe JSX instead."

echo "$input" | grep -qiE 'document\.write\(' && \
  warn "document.write(" "Risk: XSS (JS). Use DOM manipulation via createElement/textContent instead."

# --- Deserialization attacks ---
echo "$input" | grep -qiE 'pickle\.loads|pickle\.load\(' && \
  warn "pickle.load/loads" "Risk: deserialization attack (Python). Use json.loads(), or sign/verify pickled data with hmac instead."

# yaml.load without SafeLoader
if echo "$input" | grep -qiE 'yaml\.load\('; then
  if ! echo "$input" | grep -qiE 'Loader=SafeLoader|yaml\.safe_load'; then
    warn "yaml.load(" "Risk: unsafe YAML deserialization (Python). Use yaml.safe_load() or yaml.load(data, Loader=SafeLoader) instead."
  fi
fi

echo "$input" | grep -qiE 'marshal\.loads' && \
  warn "marshal.loads" "Risk: unsafe deserialization (Python). Use json.loads() or a safe serialization format instead."

# --- shell=True in subprocess (general) ---
echo "$input" | grep -qiE 'shell=True' && \
  warn "shell=True" "Risk: shell injection via subprocess (Python). Use subprocess.run() with a list of args (no shell=True) instead."

# --- Command injection (Java) ---
echo "$input" | grep -qiE 'Runtime\.getRuntime\(\)\.exec' && \
  warn "Runtime.getRuntime().exec" "Risk: command injection (Java). Use ProcessBuilder with explicit argument list (no string concatenation) instead."

# ProcessBuilder is the SAFE alternative to Runtime.exec — only warn if string concat detected
if echo "$input" | grep -qiE 'ProcessBuilder' && echo "$input" | grep -qiE 'ProcessBuilder.*\+[[:space:]]*"|\+[[:space:]]*.*ProcessBuilder'; then
  warn "ProcessBuilder with string concatenation" "Risk: command injection if user input is concatenated (Java). Use ProcessBuilder with explicit argument list, never string concatenation."
fi

# --- SQL injection ---
echo "$input" | grep -qiE 'sql.*format\(|sql.*%s|".*SELECT.*" \+' && \
  warn "SQL string formatting/concatenation" "Risk: SQL injection via string formatting. Use parameterized queries / prepared statements instead."

# --- Weak cryptography ---
echo "$input" | grep -qiE 'crypto/md5|crypto/sha1' && \
  warn "crypto/md5 or crypto/sha1" "Risk: weak cryptography (MD5/SHA1). Use crypto/sha256 or stronger. If used only for checksums (not security), add a comment explaining why."

exit 0

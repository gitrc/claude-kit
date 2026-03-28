#!/usr/bin/env bash
# PreToolUse guard: blocks dangerous bash commands that could cause data loss.
# The "Ralph Wiggum" guardrail — catches AI mistakes before they hurt.
set -euo pipefail

input=$(cat)

# Skip all checks if running with --dangerously-skip-permissions
# User explicitly chose to bypass safety — respect that
perm_mode=$(echo "$input" | grep -o '"permission_mode"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"permission_mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [ "$perm_mode" = "bypassPermissions" ]; then
  exit 0
fi

# Safe JSON extraction — no eval, no python3 dependency
# Extracts nested tool_input.command by finding the command field
command=$(echo "$input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

if [ -z "$command" ]; then
  exit 0
fi

# Dangerous patterns — block with exit 2
# Each pattern is checked against the full command string
dangerous_patterns=(
  'rm -rf /[[:space:]]*$'
  'rm -rf /[[:space:]]'
  'rm -rf \.[[:space:]]*$'
  'rm -rf \*'
  'git push[[:space:]].*--force([[:space:]]|$).*\b(main|master)\b'
  'git push[[:space:]].*-f([[:space:]]|$).*\b(main|master)\b'
  'git push[[:space:]].*\b(main|master)\b.*--force([[:space:]]|$)'
  'git push[[:space:]].*\b(main|master)\b.*-f([[:space:]]|$)'
  'git push[[:space:]].*\+\s*(main|master)'
  'git reset --hard'
  'git checkout -- \.'
  'git clean -fd'
  'git branch -D main'
  'git branch -D master'
  'DROP[[:space:]]+TABLE'
  'DROP[[:space:]]+DATABASE'
  'TRUNCATE[[:space:]]'
  '>[[:space:]]*/dev/sd'
  'mkfs\.'
  'dd if='
  ':\(\)\{.*\|.*&\}\;'
  'chmod -R 777'
  'find.* -delete'
  'find.* -exec rm'
)

# Pipe-to-shell patterns (block curl/wget piped to interpreters)
pipe_patterns=(
  'curl.*\|[[:space:]]*sh'
  'curl.*\|[[:space:]]*bash'
  'curl.*\|[[:space:]]*zsh'
  'wget.*\|[[:space:]]*sh'
  'wget.*\|[[:space:]]*bash'
  'curl.*-o.*/tmp.*&&.*(sh|bash)'
  'wget.*-O.*/tmp.*&&.*(sh|bash)'
)

for pattern in "${dangerous_patterns[@]}" "${pipe_patterns[@]}"; do
  if echo "$command" | grep -qiE "$pattern"; then
    echo "BLOCKED: Dangerous command detected matching pattern '$pattern'. Command: $command" >&2
    exit 2
  fi
done

# Block pip install without venv — warn instead of block, since we can't detect
# an already-active venv from a hook subprocess ($VIRTUAL_ENV isn't visible here)
if echo "$command" | grep -qiE '^\s*pip[3]?\s+install|^\s*python[3]?\s+-m\s+pip\s+install'; then
  if ! echo "$command" | grep -qiE 'venv|virtualenv|\.venv|source.*activate|conda|--target'; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "WARNING: pip install detected. Ensure a virtual environment is active. If no venv exists, create one first: python3 -m venv .venv && source .venv/bin/activate && pip install ... Never install packages into the system Python."
  }
}
EOF
    exit 0
  fi
fi

# Warn but allow — these need human review via permission prompt
warn_patterns=(
  'git push.*--force'
  'git stash drop'
  'git stash clear'
  'rm -rf'
  'pip install.*--break-system'
)

for pattern in "${warn_patterns[@]}"; do
  if echo "$command" | grep -qiE "$pattern"; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "WARNING: This command matches a potentially dangerous pattern ('$pattern'). Proceed with caution and confirm with the user before executing."
  }
}
EOF
    exit 0
  fi
done

exit 0

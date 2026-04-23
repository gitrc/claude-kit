---
name: inject
description: Inject the coding template into an existing project. Copies hooks, skills, settings, and CLAUDE.md.template without clobbering existing files.
argument-hint: "<target-directory>"
allowed-tools: Bash, Read, Write, Glob
disable-model-invocation: true
---

# /inject — Inject Template into Existing Project

Copies the Claude Code development template (hooks, skills, settings, git hooks) into an existing project directory without clobbering existing files.

## Required Argument
`$ARGUMENTS` must be an absolute or relative path to the target project directory. If not provided, ask the user.

## Steps

1. **Validate target**: Confirm `$ARGUMENTS` is a valid directory. If it doesn't exist, ask the user if they want to create it.

2. **Copy .claude/ directory**:
   - If target has no `.claude/` directory: copy the entire `.claude/` directory.
   - If target already has `.claude/`:
     - Copy `hooks/` directory (overwrite — hooks are template-managed)
     - Copy `skills/` directory (overwrite — skills are template-managed)
     - **Merge** `settings.json`: read both files, merge the hooks config from the template into the target's existing settings. Do not overwrite non-hook settings the target may have (like permissions).
   - Never copy `settings.local.json` or `errors.log`

3. **Copy .githooks/ directory**:
   - Copy the entire `.githooks/` directory to the target.
   - Ensure scripts are executable: `chmod +x .githooks/*`

4. **Copy CLAUDE.md.template**:
   - Copy to target root. This is a template file, safe to overwrite.

5. **Merge .gitignore**:
   - Read the template's `.gitignore` and the target's `.gitignore` (if it exists).
   - Append any entries from the template that are not already present in the target.
   - Do NOT overwrite or reorder existing entries.

6. **Do NOT copy**:
   - `.git/` directory
   - `.claude/settings.local.json`
   - `.claude/errors.log`
   - Any other project-specific state

7. **Report**:
   - List everything that was copied/merged
   - Note any conflicts that were resolved
   - Remind the user to `cd` into the target and run `/setup`

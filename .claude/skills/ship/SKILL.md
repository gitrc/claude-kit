---
name: ship
description: Lightweight commit, push, and open PR. Use after /review or /qa when code is ready to ship.
argument-hint: "[commit-message]"
allowed-tools: Bash, Read
---

# /ship — Commit, Push, and Open PR

Lightweight shipping workflow. No review, no QA — that's what `/review` and `/qa` are for. This just gets code out the door.

## Steps

1. **Check for changes**: Run `git status` and `git diff --stat`. If there are no changes to ship, tell the user and stop.

2. **Ensure feature branch**: Check the current branch name.
   - If on `main` or `master`, create a new feature branch first (`git checkout -b <branch-name>`). Derive the branch name from the changes (e.g., `feat/add-auth-middleware`).
   - Otherwise, stay on the current branch.

3. **Determine commit message**:
   - If the user provided an argument, use it as the commit message.
   - Otherwise, generate a concise commit message from the diff (explain WHY, not WHAT).

4. **Stage files**: Stage the specific changed files shown by `git status`. NEVER use `git add -A` or `git add .`. Add files by name.

5. **Commit**: Create the commit with the message. Include the co-author trailer:
   ```
   Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
   ```

6. **Push**: Push with `-u` to set upstream tracking:
   ```bash
   git push -u origin <branch>
   ```

7. **Open PR**: Check if a PR already exists for this branch:
   ```bash
   gh pr view --json url 2>/dev/null
   ```
   - If a PR exists, report its URL.
   - If no PR exists, create one:
     ```bash
     gh pr create --title "<concise title>" --body "<summary of changes>"
     ```

8. **Report**: Show the PR URL to the user.

## Important

- Never force-push.
- Never push to main/master directly.
- Stage specific files only.
- Keep commit messages concise and focused on WHY.

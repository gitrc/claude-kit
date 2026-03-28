---
name: pr-comments
description: Review and address GitHub Copilot (or any) PR review comments. Auto-detects PR from current branch.
argument-hint: "[pr-number]"
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent
---

Address all open review comments on a GitHub Pull Request.

## Step 1: Identify the PR
If an argument was provided, use PR #$ARGUMENTS.
Otherwise, auto-detect from the current branch:
```
gh pr view --json number,title,url,headRefName
```
If no PR is found, tell the user and stop.

## Step 2: Pull All Open Comments
Fetch all review comments (pending and active):
```
gh api repos/{owner}/{repo}/pulls/{number}/comments --paginate
```
Also fetch review threads to identify which are resolved vs unresolved:
```
gh pr view {number} --json reviewDecision,reviews,comments
```
Filter to only **unresolved** comment threads.

## Step 3: Analyze and Address Each Comment
For each unresolved comment:
1. **Read the referenced file and line** to understand the full context
2. **Understand the comment** — what is being asked/suggested?
3. **Verify before implementing** — read the surrounding code context to confirm the suggestion is actually correct before applying it. Don't trust the suggestion blindly.
4. **Use judgment**:
   - If the suggestion is correct and improves the code: implement the fix
   - If the suggestion is a style nit with no substance: implement it anyway (don't fight reviewers on style)
   - If the suggestion is incorrect or would break something: **push back** — explain why in the reply rather than blindly implementing. Reviewers can be wrong.
   - If the suggestion contradicts project conventions in CLAUDE.md: do not implement it. Cite the convention in your reply.
   - If the comment is a question: prepare an answer
   - **YAGNI check**: if a suggestion adds complexity for a hypothetical future case (e.g., "what if we need to support X later"), push back politely. Don't add code for requirements that don't exist yet.
5. **No performative agreement** — don't say "Great catch!" or "You're absolutely right!" in replies. Just address the issue directly and explain what was done or why it wasn't.
6. **Make the fix** using Edit tool

## Step 4: Commit and Push
After addressing all comments:
1. Stage changed files: `git add <specific files>`
2. Commit with a message like: `fix: address PR review comments`
3. Push: `git push`

## Step 5: Reply to Each Comment Thread
For each comment that was addressed:
1. Reply to the comment thread explaining what was done:
   ```
   gh api repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies -f body="..."
   ```
2. **Resolve the thread** if the fix fully addresses it. Use the GraphQL API:
   ```
   gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "THREAD_NODE_ID"}) { thread { isResolved } } }'
   ```

To get the thread node ID, use:
```
gh api graphql -f query='{ repository(owner: "OWNER", name: "REPO") { pullRequest(number: PR_NUM) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 1) { nodes { body databaseId } } } } } } }'
```

## Step 6: Summary
Report to the user:
- How many comments were addressed
- How many threads were resolved
- Any comments that need human judgment
- Remind them to re-run `/pr-comments` after Copilot's next pass

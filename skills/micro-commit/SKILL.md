---
name: micro-commit
description: >
  Automatically create conventional commit-style micro-commits by splitting changes into logical units of ~30-50 lines each.
  Use this skill whenever the user asks to commit, says "コミットして", "commit this", or when a feature, fix, or
  refactoring task is completed and changes need to be committed. Also trigger when the user mentions
  "マイクロコミット", "micro commit", "conventional commit", or asks to split changes into smaller commits.
  If you detect that a coding task has just been completed and there are uncommitted changes, suggest using this skill.
  Grain-size judgment and plan-stage commit planning are handled by the commit-flow skill; when both apply,
  commit-flow decides the split and this skill executes it.
---

# Micro Commit

Create clean, conventional commit-style micro-commits by automatically splitting staged and unstaged changes into logical units.

## Why micro-commits matter

Small, focused commits make git history readable and bisectable. Each commit should represent one coherent thought — a single function added, a bug fixed, a test written. When commits are too large, `git bisect` becomes useless and code review becomes painful. The goal is ~30-50 changed lines per commit, though this is a guideline, not a hard rule — don't split a single coherent change just to hit a line count.

## Workflow

### 1. Analyze all changes

Run `git status` and `git diff` (both staged and unstaged) to understand the full picture. Read the changed files to understand what each change does semantically.

### 2. Group changes into logical units

Split changes by **semantic meaning**, not by file. One logical unit might be:

- A new function and its corresponding test
- A bug fix (even if it touches multiple files)
- A refactoring that renames a variable across files
- Documentation updates for a feature

Guidelines for splitting:
- Each commit should be independently meaningful — the codebase should compile/work after each commit
- Related changes go together (e.g., a new function + its test = one commit, not two)
- Unrelated changes in the same file should be split into separate commits using `git add -p` or by staging specific files
- If a change is naturally 60 lines but splitting it would break coherence, keep it as one commit

### 3. Determine commit type and scope

**Types** (conventional commit):
| Type | When to use |
|------|------------|
| `feat` | New functionality for the user/system |
| `fix` | Bug fix |
| `docs` | Documentation only (comments, README, etc.) |
| `refactor` | Code restructuring without behavior change |
| `test` | Adding or modifying tests |
| `chore` | Build, CI, tooling, dependencies |

**Scope**: Derive from the module or directory the change primarily affects. Use short, recognizable names:
- Directory-based: `feat(db):`, `fix(websocket):`, `test(nostr):`
- Feature-based: `feat(auth):`, `fix(parser):`
- If a change spans many modules equally, scope can be omitted

### 4. Write the commit message

Format:
```
type(scope): concise description in imperative mood
```

Rules:
- First line under 72 characters
- Use imperative mood: "add", "fix", "refactor" — not "added", "fixes", "refactoring"
- Focus on **why/what**, not how: "fix off-by-one in buffer boundary check" not "change < to <="
- Lowercase first letter after the colon
- No period at the end
- Write in the language of the codebase/project (if the project uses English commit messages, write in English; if Japanese, write in Japanese). Default to English unless you see otherwise in `git log`.

Examples:
```
feat(db): add B+ tree node split operation
fix(websocket): handle fragmented frames exceeding buffer size
refactor(nostr): extract event validation into separate module
test(crypto): add SHA-256 edge case coverage
docs(readme): update build instructions for Docker
chore(cmake): bump googletest to v1.14
```

### 5. Stage and commit each unit

For each logical unit, in dependency order (foundational changes first):

1. Stage only the files/hunks for this unit — use specific file paths, not `git add -A`
2. Commit with the conventional commit message using a HEREDOC:
   ```bash
   git commit -m "$(cat <<'EOF'
   type(scope): description
   EOF
   )"
   ```
3. Verify with `git status` that the right things were committed

### 6. Report what was done

After all commits, show a summary:
```
Created N commits:
- abc1234 feat(db): add B+ tree node split operation
- def5678 test(db): add split operation boundary tests
- ghi9012 docs(db): document B+ tree implementation notes
```

## Important constraints

- Never use `git add -A` or `git add .` — always stage specific files
- Never amend existing commits unless explicitly asked
- Never skip hooks (`--no-verify`)
- Never force push
- If a pre-commit hook fails, fix the issue and create a new commit
- Check `git log` first to match the project's existing commit style if it differs from these guidelines
- Do not commit files that look like secrets (`.env`, credentials, keys)
- Never chain a verification gate into the commit on the same shell line: `tests 2>&1 | tail && git commit` commits even when the tests are red (the pipe's exit is `tail`'s), and `tests; git commit` ignores the failure. Run the gate first, confirm exit 0, then commit as a separate command (or guard it with `if <gate>; then git commit ...; fi`)

## Completion criteria

Done when the workflow and constraints above are satisfied. Anything intentionally left uncommitted is reported as such.

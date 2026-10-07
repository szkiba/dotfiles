---
name: codex-review
description: >
  Maker-checker review with the Codex CLI. Use when the user asks to have
  Codex review a plan or uncommitted code changes (for example "ask codex for
  a review before the commits"), or wants a second opinion on a design. Writes
  a review request file, runs `codex exec` in the background, checks that Codex
  changed nothing, and verifies each finding before acting on it.
---

# Codex review (maker-checker)

You make the plan or the change. Codex checks it. You verify each finding and fix what is real.

Use it for a plan before a non-trivial implementation, and for a diff before committing. Do not use it for trivial changes. Keep to at most two plan reviews and one diff review per repo, because later rounds find little.

## Steps

1. Write the request file in the user's temp folder for the task, never inside a cloned repo. Name it `<topic>-codex-review-<n>-request.md`. Keep it short and specific, in this shape:
   - One line saying what is reviewed, and "Do not edit, create or delete any files. Read only." For code reviews also: no `git add`, `commit`, `stash` or `checkout`. Build, vet and test are fine.
   - What to read, with absolute paths: the plan, the repo and branch, how to see the changes (`git status --short`, `git diff`, the new untracked files), vendored dependencies and their versions when they matter, the repo's `AGENTS.md`, and earlier review files.
   - Background in a few sentences: what and why, the hard constraints (for example "off by default", "must never break X"), and the current test and lint status.
   - What to check, numbered, five to seven specific questions that name the risky areas. For a second round: first check that earlier findings are really fixed, then look for problems the fixes introduced.
   - Output: one finding per line, most important first, each labeled Blocker, Major, Minor, Nit or Question, with `file:line` when possible. Skip empty categories and anything that is fine. End with a one-line verdict.

2. For code reviews, take a snapshot in the session scratchpad before the run:
   `git status --short > status-before.txt` and
   `{ git diff; git ls-files -o --exclude-standard -z | xargs -0 -r sha256sum; } | sha256sum > state-before.sha`

3. Run Codex in the background, one job at a time on small machines:
   `codex exec --sandbox read-only --color never -C <root> -o <topic>-codex-review-<n>.md - < <request>.md > <topic>-codex-review-<n>-run.log 2>&1`
   Try read-only first. If the result says the review is incomplete because of `bwrap`, `uid map` or user namespace permission errors, the sandbox cannot start in this container. Do not retry with the sandbox off on your own. Tell the user, and use `--sandbox danger-full-access` only after they agree. With the sandbox off, Codex could write files, so steps 2 and 4 matter.
   The request and the code Codex reads go to its backend. If the user did not ask for a Codex review, ask first.

4. When it finishes, read the `-o` result file, not the large log. For code reviews, repeat the snapshot commands and compare. If anything changed, tell the user and ask before touching it.

5. Verify every finding against the code before acting. Sort them into confirmed, already present before the change (report it, do not fix it in this change), and wrong. Fix what is confirmed, rerun tests and lint, and tighten any test that would pass for the wrong reason. Reproduce a claimed crash or race when it is cheap, for example by removing the guard and watching the test fail, then restore it.

6. Report to the user in a few lines: each finding with your verdict, what you changed, and what you left alone.

7. Commits and pushes follow `~/.claude/CLAUDE.md`: show the exact commit message and wait for approval, and ask before every push.

## Notes

- Codex was right on two real blockers in a past run, and also raised one issue that predated the change. Treat its output as input, not as truth.
- Keep the plan or change in one place and sync copies, so Codex always reads the current version.

---
name: maker-checker
description: >
  Maker-checker review between Claude and Codex: the agent running the skill is
  the maker, the other agent's CLI run headless in the same isolated environment
  is the checker. Use when the user says "do checker review" or "maker-checker
  review", asks the other agent to review a plan, spec, document or uncommitted
  code changes (for example "ask codex for a review before the commits"), or
  wants a second opinion on a design. Only works in an isolated environment
  (Docker sandbox, container or VM).
---

# Maker-checker review

The maker produces the work: a plan, a code change, a document, a spec, a design, or anything else that benefits from a second look. The checker reviews it and never modifies it. The maker verifies each finding and fixes what is real.

You are the maker. The checker is the other agent: Codex when you are Claude, Claude when you are Codex. `scripts/run-checker.sh` starts a fresh headless run of its CLI, so every review starts with an empty context and sees only what the request names. The script waits until the review is done and checks that the worktree did not change.

## Requirements

The checker runs with full permissions in the same environment as you, so the skill only works in an isolated one: a Docker sandbox, a container or a VM. Before anything else run `sh ~/.ai/skills/maker-checker/scripts/check-isolation.sh`. If it exits 1, tell the user and stop. Do not pass `--assume-isolated` to the script unless the user explicitly says this environment is isolated, because the flag skips the check.

Also needed:
- The other agent's CLI, installed and logged in here. A missing CLI is reported at once, a login problem shows up in the run log.
- A git worktree with at least one commit (`git rev-parse --show-toplevel && git rev-parse -q --verify HEAD`).
- The user's go-ahead. The request and the code the checker reads go to the checker's vendor backend, so if the user did not ask for the review, ask first.

## When to use it

Use it for a plan, spec or design before a non-trivial implementation, for a document before it is shared, and for a diff before committing. Do not use it for trivial changes. Run up to two rounds on your own, a second one only if the first led to non-trivial fixes. Later rounds usually find little, so do not start a third without asking: if the second round still has confirmed Blocker or Major findings, report them and let the user decide whether to continue.

## Files

Review files live in `.ai/maker-checker/` at the root of the current worktree. `.ai` is globally gitignored, so it never shows in `git status` or `git diff` and is never committed. Every file of a review starts with `<topic>-review-<n>`, where `<topic>` is a short kebab-case name for what is reviewed and `<n>` is 1 for the first round and goes up by one for each round:

- `-request.md`: written by you.
- `.md`: the checker's answer.
- `-run.log`: the checker CLI's log.
- `-response.md`: your verdict on each finding.

Pick a topic that identifies the unit of work, so the same name comes back on a later round and rounds of different work never mix. For an OpenSpec change, use the change id plus the task, with the dot of the task number written as a hyphen: task 1.2 of the change `add-2fa` gives the topic `add-2fa-task-1-2`. When one review covers a group of tasks, use the group number: tasks 2.1 to 2.3 give `add-2fa-task-2`. If you lost track of the topic, look for the earlier files in `.ai/maker-checker/` before choosing a new one.

Shell variables do not survive between commands, so start every command that touches these files with:

`root=$(git rev-parse --show-toplevel); dir="$root/.ai/maker-checker"; run="$dir/<topic>-review-<n>"`

and write `"$run-request.md"`, `"$run.md"` and so on.

## Steps

1. Check that `.ai` is ignored with `git check-ignore -q "$root/.ai"`. If it is not, stop and tell the user, because the files would show up as untracked. Otherwise run `mkdir -p "$dir"` and write `$run-request.md`. Keep it short and specific. The script already tells the checker that it is the checker, that it must not change the worktree, and that builds and tests are fine, so do not repeat that. Write it in this shape:
   - One line saying what is reviewed.
   - What to read, with paths relative to the worktree root (the checker works from there), or absolute only for things outside it: the plan, spec or document under review, the repo and branch, how to see the changes (`git status --short`, `git diff`, the new untracked files), vendored dependencies and their versions when they matter, the repo's `AGENTS.md`, and the earlier review and `-response.md` files in `.ai/maker-checker/`.
   - Background in a few sentences: what and why, the hard constraints (for example "off by default", "must never break X"), and the current test and lint status.
   - What to check, numbered, five to seven specific questions that name the risky areas. For a second round: first check that earlier findings are really fixed, using your `-response.md` and not raising again what you rejected unless your reasoning is wrong, then look for problems the fixes introduced.
   - Output: one finding per line, most important first, each labeled Blocker, Major, Minor, Nit or Question, with `file:line` when possible. Skip empty categories and anything that is fine. End with a one-line verdict.

2. Run the review: `sh ~/.ai/skills/maker-checker/scripts/run-checker.sh <codex|claude> "$run-request.md" [watched-file...]`, with the other agent's name. If the files under review are ignored by git, such as a plan in `.ai/`, list them as watched files so the script notices if the checker changes them. Until the script ends, do not edit the work or run anything that changes files in the worktree.

   A review takes from a few minutes up to 30. Use your tool's background mode if it has one and wait until it tells you the command ended. Do not poll. If it has none and its command timeout is shorter than the review, start the script with `nohup setsid sh <script> <args> > "$run-script.log" 2>&1 &` and wait for its last line with `timeout 500 sh -c 'until grep -q "^run-checker: " "$0"; do sleep 5; done' "$run-script.log"`, repeated until it returns 0. That line carries the exit code.

3. Act on the exit code:
   - 0: read `$run.md`, not the log. If it does not end with a verdict line, treat the review as incomplete and tell the user.
   - 1: the review failed (a login problem, a rate limit, the 30 minute limit, or a stopped run). Tell the user and show the log tail the script printed. Do not try to work around it on your own: ask the user.
   - 2: the script could not start (no CLI, not isolated, no commit, `.ai` not ignored). Tell the user what it said and stop.
   - 3: the worktree changed during the review. Tell the user what the script printed and ask before touching anything.

4. Verify every finding against the code before acting. Sort them into confirmed, already present before the change (report it, do not fix it in this change), and wrong. Fix what is confirmed, rerun tests and lint, and tighten any test that would pass for the wrong reason. Reproduce a claimed crash or race when it is cheap, for example by removing the guard and watching the test fail, then restore it. Then write `$run-response.md`: for each finding, your verdict, one line of reasoning, and what you changed.

5. Report to the user in a few lines: each finding with your verdict, what you changed, and what you left alone. After the second round, say whether significant findings remain and ask whether to run another.

6. When no further round is planned and the milestone-snapshots skill applies (big work, jj set up), take the milestone snapshot now, not before or between rounds. Add the `Review:` trailer described in that skill, with this review's topic and the rounds that ran, and say so if you changed code after the last round. A jj snapshot needs no approval, see the jj section of AGENTS.md. Git commits and pushes follow the user's global agent instructions: show the exact commit message and wait for approval, and ask before every push.

## Notes

- Treat the checker's output as input, not as truth. It can be wrong, and it can raise issues that were already there before the change.
- Keep the plan or change in one place and sync copies, so the checker always reads the current version.
- Leave the review files in `.ai/maker-checker/`. A later round reads the earlier ones, and nothing needs cleaning up because git ignores the folder.
- The checker has no memory between reviews. Anything it needs from an earlier round has to be in the request or in the files the request names.

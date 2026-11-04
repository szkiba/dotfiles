---
name: maker-checker
description: >
  Maker-checker review between Claude and Codex: the agent running the skill is
  the maker, a checker loop running in another environment is the checker. Use
  when the user says "do checker review" or "maker-checker review", asks the
  other agent to review a plan, spec, document or uncommitted code changes (for
  example "ask codex for a review before the commits"), or wants a second
  opinion on a design. Also use when the user says "start a checker loop": run
  the checker loop script, do not review anything yourself.
---

# Maker-checker review

The maker produces the work: a plan, a code change, a document, a spec, a design, or anything else that benefits from a second look. The checker reviews it and never modifies it. The maker verifies each finding and fixes what is real.

The two never run in the same session. They talk through files in `.ai/maker-checker/` in a worktree folder that both can see, for example two Docker sandboxes that share a workspace. The checker is `scripts/checker-loop.sh`, which the user starts once in the checker's environment. It waits for requests, and for each one it starts a fresh headless run of the checker CLI, so every review starts with an empty context and sees only what the request names. The checker is usually the other agent: Codex when the maker is Claude, Claude when the maker is Codex.

The checker runs with full permissions, so its environment has to be isolated (a Docker sandbox, a container or a VM). The script refuses to start otherwise.

If the user tells you to start a checker loop, you are not the maker: do "Starting the checker loop" and ignore the rest of this file.

## Starting the checker loop

Run `sh ~/.ai/skills/maker-checker/scripts/checker-loop.sh <agent>` from the root of the worktree the maker works in, where `<agent>` is `claude` or `codex`, the CLI that is installed and logged in here. It never ends by itself, so run it in the background, with your tool's background mode if it has one, otherwise as `mkdir -p .ai/maker-checker && nohup setsid sh <script> <agent> > .ai/maker-checker/checker-loop.log 2>&1 &`. Look at its first lines of output after a few seconds. It prints that the environment is isolated and that it is watching the folder.

If it refuses to start, tell the user why and stop. If it says the environment does not look isolated, do not add `--assume-isolated` unless the user explicitly says this environment is isolated. The flag skips the check, and the checker then runs with full permissions.

When it runs, tell the user which folder it watches and how to stop it, then stop yourself. Do not review anything, and do not wait or poll: the script does that. Stopping it cuts a review in progress short and gives that review a failed exit code.

## Before you start (maker)

The request and the code the checker reads go to the checker's vendor backend. If the user did not ask for the review, ask first.

The skill needs a git worktree with at least one commit (`git rev-parse --show-toplevel && git rev-parse -q --verify HEAD`). If it is missing, tell the user.

The checker loop has to be running in the other environment. You find out in step 3: if nobody picks up the request, tell the user to start one.

## When to use it

Use it for a plan, spec or design before a non-trivial implementation, for a document before it is shared, and for a diff before committing. Do not use it for trivial changes. Run up to two rounds on your own, a second one only if the first led to non-trivial fixes. Later rounds usually find little, so do not start a third without asking: if the second round still has confirmed Blocker or Major findings, report them and let the user decide whether to continue.

## Files

The two sides talk through files in `.ai/maker-checker/` at the root of the current worktree, which both must see. `.ai` is globally gitignored, so it never shows in `git status` or `git diff` and is never committed. Every file of a review starts with `<topic>-review-<n>`, where `<topic>` is a short kebab-case name for what is reviewed and `<n>` is 1 for the first round and goes up by one for each round:

- `-request.md`: written by the maker. It is written as `-request.md.tmp` and renamed, so the loop never reads half a file.
- `.claim`: written by the loop when it starts the review.
- `.md`: the checker's answer.
- `-run.log`: the checker's log.
- `.exit`: the checker's exit code, written last when it finishes. An empty file counts as not written yet.
- `-response.md`: the maker's verdict on each finding.
- `-status-before.txt`, `-state-before.sha` and their `after` twins: the snapshots.

Pick a topic that identifies the unit of work, so the same name comes back on a later round and rounds of different work never mix. For an OpenSpec change, use the change id plus the task, with the dot of the task number written as a hyphen: task 1.2 of the change `add-2fa` gives the topic `add-2fa-task-1-2`. If you lost track of the topic, look for the earlier files in `.ai/maker-checker/` before choosing a new one.

Shell variables do not survive between commands, so start every command that touches these files with:

`root=$(git rev-parse --show-toplevel); dir="$root/.ai/maker-checker"; run="$dir/<topic>-review-<n>"`

and write `"$run-request.md"`, `"$run.md"` and so on.

## Steps

1. Check that `.ai` is ignored with `git check-ignore -q "$root/.ai"`. If it is not, stop and tell the user, because the files would show up as untracked. Otherwise run `mkdir -p "$dir"` and write `$run-request.md.tmp`. Keep it short and specific. The loop already tells the checker that it is the checker, that it must not change the worktree, and that builds and tests are fine, so do not repeat that. Write it in this shape:
   - One line saying what is reviewed.
   - What to read, with paths relative to the worktree root (the checker works from there, and a shared folder may be mounted at a different path), or absolute only for things outside it: the plan, spec or document under review, the repo and branch, how to see the changes (`git status --short`, `git diff`, the new untracked files), vendored dependencies and their versions when they matter, the repo's `AGENTS.md`, and the earlier review and `-response.md` files in `.ai/maker-checker/`.
   - Background in a few sentences: what and why, the hard constraints (for example "off by default", "must never break X"), and the current test and lint status.
   - What to check, numbered, five to seven specific questions that name the risky areas. For a second round: first check that earlier findings are really fixed, using the maker's `-response.md` and not raising again what it rejected unless its reasoning is wrong, then look for problems the fixes introduced.
   - Output: one finding per line, most important first, each labeled Blocker, Major, Minor, Nit or Question, with `file:line` when possible. Skip empty categories and anything that is fine. End with a one-line verdict.

2. Take a snapshot before the run:
   `git status --short > "$run-status-before.txt"` and
   `{ git diff HEAD; git ls-files -o --exclude-standard -z | xargs -0 -r sha256sum; } | sha256sum > "$run-state-before.sha"`
   If the files under review are ignored by git, such as a plan in `.ai/`, add `sha256sum <those files>;` before the closing brace. Leave it out when there are none, because a `sha256sum` with no files waits on stdin and hangs.

3. Publish the request with `mv "$run-request.md.tmp" "$run-request.md"`, then wait for the checker. Until `$run.exit` exists, do not edit the work or run anything that changes files in the worktree, because that would change what the checker reviews and break the snapshot check.

   First wait up to two minutes for `$run.claim`. The loop checks for requests every few seconds, so if it does not appear, no loop is running: tell the user, remind them they can start one by telling an agent in the checker's environment "start a checker loop", and stop. Leave the request where it is, a loop started later will find it, and carry on waiting when the user says it runs. Once the request is claimed, wait up to 35 minutes for `$run.exit`. The loop stops a review after 30 minutes, so it always ends with an exit code unless the loop itself died.

   To wait for a file, use a shell loop that ends when the file exists and is not empty:
   `timeout 500 sh -c 'until [ -s "$0" ]; do sleep 5; done' "$run.exit"`
   Use your tool's background or monitor mode for it if it has one. Otherwise repeat the command in chunks that fit your tool's command timeout until the total time is used up. `timeout` exits with 124 when the time ran out. Wait by looking up this one path. Do not wait by listing the folder: a folder shared with another VM can show a stale listing for minutes.

4. When `$run.exit` exists, check that it holds 0 and that `$run.md` is not empty and ends with a verdict line. If not, the run failed (a login problem, a rate limit, exit code 124 for the 30 minute limit, or a loop that was stopped): tell the user, show the tail of `$run-run.log`, and do not treat it as a clean review. Do not try to work around it on your own: ask the user. If you give up on a request that no loop answered, run `echo 1 > "$run.exit"` so a loop started later does not review stale work. Otherwise read `$run.md`, not the log. Repeat the snapshot commands with `after` in place of `before` and compare each pair. If anything changed, tell the user and ask before touching it.

5. Verify every finding against the code before acting. Sort them into confirmed, already present before the change (report it, do not fix it in this change), and wrong. Fix what is confirmed, rerun tests and lint, and tighten any test that would pass for the wrong reason. Reproduce a claimed crash or race when it is cheap, for example by removing the guard and watching the test fail, then restore it. Then write `$run-response.md`: for each finding, your verdict, one line of reasoning, and what you changed.

6. Report to the user in a few lines: each finding with your verdict, what you changed, and what you left alone. After the second round, say whether significant findings remain and ask whether to run another.

7. Commits and pushes follow the user's global agent instructions: show the exact commit message and wait for approval, and ask before every push.

## Notes

- Treat the checker's output as input, not as truth. It can be wrong, and it can raise issues that were already there before the change.
- Keep the plan or change in one place and sync copies, so the checker always reads the current version.
- Leave the review files in `.ai/maker-checker/`. A later round reads the earlier ones, and nothing needs cleaning up because git ignores the folder.
- The checker has no memory between reviews. Anything it needs from an earlier round has to be in the request or in the files the request names.

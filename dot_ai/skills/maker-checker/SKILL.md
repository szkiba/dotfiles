---
name: maker-checker
description: >
  Maker-checker review between Claude and Codex: the agent running the skill is
  the maker, the other one is the checker. Use when the user says "do checker
  review" or "maker-checker review", asks the other agent to review a plan,
  spec, document or uncommitted code changes (for example "ask codex for a
  review before the commits"), or wants a second opinion on a design.
---

# Maker-checker review

The maker produces the work: a plan, a code change, a document, a spec, a design, or anything else that benefits from a second look. The checker reviews it and never modifies it. If the checker needs temporary scripts, tests or other files to check something, it keeps them in its own scratch folder outside the worktree. The maker verifies each finding and fixes what is real.

The agent running these steps is the maker, and the checker is the other one: Codex when the maker is Claude, Claude when the maker is Codex. If you are the checker, do not start a review and ignore the rest of this file: read the request file you were given, do what it asks, and answer in the format it asks for.

## Before you start (maker)

Check whether you are inside an isolated environment such as a Docker sandbox, an Incus container or a VM. Full access mode gives the checker no Codex sandbox and no Claude permission prompts, which is only safe where the damage stays inside the environment. Run:

`systemd-detect-virt -q 2>/dev/null || [ -e /.dockerenv ] || [ -e /run/.containerenv ] || grep -qw hypervisor /proc/cpuinfo`

If it succeeds, run the checker in full access mode. If it fails, or you cannot tell, tell the user the environment does not look isolated and run the checker in read-only mode instead, unless the user explicitly says that this environment is isolated, in which case use full access mode. In read-only mode the checker can read files and run read-only git commands but cannot write anywhere, so builds and tests may fail. The check only sees that a container or VM exists, not how well it is isolated, so a container with the host's Docker socket or home folder mounted still passes.

The request and the code the checker reads go to its vendor's backend. If the user did not ask for the review, ask first.

The skill needs a git worktree with at least one commit (`git rev-parse --show-toplevel && git rev-parse -q --verify HEAD`) and a checker CLI that is installed and logged in. Check with `codex login status` or `claude auth status`, and read the output. If something is missing, tell the user instead of waiting for a failed run.

## When to use it

Use it for a plan, spec or design before a non-trivial implementation, for a document before it is shared, and for a diff before committing. Do not use it for trivial changes. Run up to two rounds on your own, a second one only if the first led to non-trivial fixes. Later rounds usually find little, so do not start a third without asking: if the second round still has confirmed Blocker or Major findings, report them and let the user decide whether to continue.

## Files

The two agents talk through files in `.ai/` at the root of the current worktree. That folder is globally gitignored, so it never shows in `git status` or `git diff` and is never committed. Every file of a review starts with `<topic>-review-<n>`, where `<topic>` is a short kebab-case name for what is reviewed and `<n>` is 1 for the first round and goes up by one for each round:

- `-request.md`: written by the maker.
- `.md`: the checker's answer.
- `-run.log`: the checker's log.
- `.exit`: the checker's exit code, written when it finishes.
- `-response.md`: the maker's verdict on each finding.
- `-status-before.txt`, `-state-before.sha` and their `after` twins: the snapshots.

Shell variables do not survive between commands, so start every command that touches these files with:

`root=$(git rev-parse --show-toplevel); run="$root/.ai/<topic>-review-<n>"`

and write `"$run-request.md"`, `"$run.md"` and so on.

## Steps

1. Check that `.ai` is ignored with `git check-ignore -q "$root/.ai"`. If it is not, stop and tell the user, because the files would show up as untracked. Otherwise run `mkdir -p "$root/.ai"` and write `$run-request.md`. Keep it short and specific, in this shape:
   - "You are the checker in a maker-checker review. Do not use the maker-checker skill." Then one line saying what is reviewed, and "Do not edit, create or delete any files in the worktree. Put any temporary scripts, tests or output in your own scratch folder outside it (for example from `mktemp -d`)." For code reviews also: no `git add`, `commit`, `stash` or `checkout`. In full access mode build, vet and test are fine. In read-only mode, replace the scratch folder sentence with "You cannot write anywhere, so do not try. Builds and tests may fail: list anything you could not check."
   - What to read, with absolute paths: the plan, spec or document under review, the repo and branch, how to see the changes (`git status --short`, `git diff`, the new untracked files), vendored dependencies and their versions when they matter, the repo's `AGENTS.md`, and the earlier review and `-response.md` files in `.ai/`.
   - Background in a few sentences: what and why, the hard constraints (for example "off by default", "must never break X"), and the current test and lint status.
   - What to check, numbered, five to seven specific questions that name the risky areas. For a second round: first check that earlier findings are really fixed, using the maker's `-response.md` and not raising again what it rejected unless its reasoning is wrong, then look for problems the fixes introduced.
   - Output: one finding per line, most important first, each labeled Blocker, Major, Minor, Nit or Question, with `file:line` when possible. Skip empty categories and anything that is fine. End with a one-line verdict.

2. Take a snapshot before the run:
   `git status --short > "$run-status-before.txt"` and
   `{ git diff HEAD; git ls-files -o --exclude-standard -z | xargs -0 -r sha256sum; } | sha256sum > "$run-state-before.sha"`
   If the files under review are ignored by git, such as a plan in `.ai/`, add `sha256sum <those files>;` before the closing brace. Leave it out when there are none, because a `sha256sum` with no files waits on stdin and hangs.

3. Run the checker in the background, one job at a time on small machines. Use your tool's background mode if it has one, otherwise start the command with `nohup`. The checker is finished when `$run.exit` exists. Until then, do not edit the work or run anything that changes files in the worktree, because that would change what the checker reviews and break the snapshot check:
   - Codex: `timeout 30m codex exec <codex flags> --color never -C "$root" -o "$run.md" - < "$run-request.md" > "$run-run.log" 2>&1; echo $? > "$run.exit"`
   - Claude: `(cd "$root" && timeout 30m claude -p <claude flags> --no-session-persistence < "$run-request.md" > "$run.md" 2> "$run-run.log"; echo $? > "$run.exit")`

   Full access mode: `<codex flags>` is `--sandbox danger-full-access` and `<claude flags>` is `--dangerously-skip-permissions --disallowedTools "Edit Write NotebookEdit"`. Read-only mode: `<codex flags>` is `--sandbox read-only` and `<claude flags>` is `--permission-mode plan`.

   In full access mode the checker could still write files through the shell, so steps 2 and 4 matter.

4. When `$run.exit` exists, check that it holds 0 and that `$run.md` is not empty and ends with a verdict line. If not, the run failed (a login problem, a rate limit, a timeout, or in a container a read-only sandbox that cannot start, with `bwrap` or user namespace errors, for example): tell the user, show the tail of `$run-run.log`, and do not treat it as a clean review. Never switch to full access mode on your own to get around it: ask the user. Otherwise read `$run.md`, not the log. Repeat the snapshot commands with `after` in place of `before` and compare each pair. If anything changed, tell the user and ask before touching it.

5. Verify every finding against the code before acting. Sort them into confirmed, already present before the change (report it, do not fix it in this change), and wrong. Fix what is confirmed, rerun tests and lint, and tighten any test that would pass for the wrong reason. Reproduce a claimed crash or race when it is cheap, for example by removing the guard and watching the test fail, then restore it. Then write `$run-response.md`: for each finding, your verdict, one line of reasoning, and what you changed.

6. Report to the user in a few lines: each finding with your verdict, what you changed, and what you left alone. After the second round, say whether significant findings remain and ask whether to run another.

7. Commits and pushes follow the user's global agent instructions: show the exact commit message and wait for approval, and ask before every push.

## Notes

- Treat the checker's output as input, not as truth. It can be wrong, and it can raise issues that were already there before the change.
- Keep the plan or change in one place and sync copies, so the checker always reads the current version.
- Leave the review files in `.ai/`. A later round reads the earlier ones, and nothing needs cleaning up because git ignores the folder.

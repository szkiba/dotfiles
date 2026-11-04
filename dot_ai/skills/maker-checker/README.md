# maker-checker

A skill for second-opinion reviews between Claude and Codex. The agent you are talking to is the maker. The checker is the other agent's CLI, run headless in the same environment. SKILL.md is what the agents read. This file is for the person setting it up.

## Setup

Run `chezmoi apply`. The skill folder is linked into both `~/.claude/skills` and `~/.codex/skills`. The sandboxes mount `~/.ai` read-only from the host, so they only see the scripts after the apply.

Both CLIs must be installed and logged in in the environment where the review runs. In a Docker sandbox with the claude and codex kits that is already the case once the credentials are set on the host (`sbx secret set openai --oauth` for Codex).

## Isolated environments only

The checker runs with full permissions (`--sandbox danger-full-access` for Codex, `--dangerously-skip-permissions` for Claude) in the same environment as the maker. The skill and `scripts/run-checker.sh` therefore refuse to run unless `scripts/check-isolation.sh` sees a container or VM. It cannot tell how well that environment is isolated: a container with the host's Docker socket or home folder mounted still passes.

Pass `--assume-isolated` before the agent name only if you know the environment is isolated and the check is wrong.

## Using it

Ask the maker for a review, for example "do checker review" or "ask codex for a review before the commit". It writes a request into `.ai/maker-checker/`, runs `scripts/run-checker.sh`, and waits. Each review is a fresh headless run, so the checker remembers nothing between reviews. Anything it needs from an earlier round has to be in the request.

You can also run the script yourself from the worktree:

    sh ~/.ai/skills/maker-checker/scripts/run-checker.sh <claude|codex> .ai/maker-checker/<topic>-review-1-request.md

The answer lands next to the request as `<topic>-review-1.md`, with the CLI's log in `<topic>-review-1-run.log`. Before and after the run the script fingerprints `git status`, `git diff HEAD` and the untracked files, and exits with 3 if they differ. Files that git ignores but the review depends on can be added as extra arguments.

Exit codes: 0 clean review, 1 the review failed, 2 the script could not start, 3 the worktree changed during the review.

## Settings

`MAKER_CHECKER_TIMEOUT` sets how long one review may take. The default is `30m`. Ctrl-C or `kill` on the script stops the review and marks it failed.

## When something goes wrong

If a review failed, read `.ai/maker-checker/<topic>-review-<n>-run.log`. A CLI that is not logged in shows up there, and the script prints the tail of the log. The time limit shows as "it hit the limit".

If the script says the environment does not look isolated, run the review in a Docker sandbox, a container or a VM.

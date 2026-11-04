# maker-checker

A skill for second-opinion reviews between two agents that run in different environments, for example Claude in one Docker sandbox and Codex in another, both on the same workspace folder. SKILL.md is what the agents read. This file is for the person setting it up.

## Setup

Run `chezmoi apply`. The skill folder is linked into both `~/.claude/skills` and `~/.codex/skills`. The sandboxes mount `~/.ai` read-only from the host, so they only see the scripts after the apply.

## Starting the checker

In the checker's sandbox, tell its agent "start a checker loop". It runs `scripts/checker-loop.sh` in the background and goes idle. To start it yourself instead, run this on the host:

    sbx exec -it -w <workspace> <sandbox> sh /home/agent/.ai/skills/maker-checker/scripts/checker-loop.sh <claude|codex>

The last argument is the agent CLI installed in that sandbox. The workspace must be the same folder the maker works in. The loop prints the folder it watches.

The checker runs with full permissions, so the script refuses to start unless `scripts/check-isolation.sh` sees a container or VM. Pass `--assume-isolated` before the agent name only if you know the environment is isolated and the check is wrong.

## Using it

In the maker's session, ask for a review, for example "do checker review" or "ask codex for a review before the commit". The maker writes a request into `.ai/maker-checker/` and waits. The loop answers each request with a fresh headless run of the CLI, so the checker remembers nothing between reviews. Anything it needs from an earlier round has to be in the request.

## Stopping and settings

Ctrl-C or `kill` stops the loop. A review in progress is cut short and recorded as failed with exit code 143. If an agent started the loop, stop its background task, or kill the process in the sandbox.

`MAKER_CHECKER_TIMEOUT` sets how long one review may take. The default is `30m`.

## When something goes wrong

If the maker says nobody picked up the request, the loop is not running, or it watches a different workspace folder. Start it, and it finds the waiting request.

If the loop refuses to start, it says why. The usual reason is the isolation check.

If a review failed, read `.ai/maker-checker/<topic>-review-<n>-run.log`. Exit code 124 means the 30 minute limit, 143 means the loop was stopped, and a CLI that is not logged in shows up in the log. Log in inside that sandbox and ask for the review again.

A directory listing of the shared folder can look stale for minutes when you read it from a different sandbox than the one that wrote the files. The loop works around that. If you list the folder by hand and files seem to be missing, create and remove a file in it, or look up the exact path.

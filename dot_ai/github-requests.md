# GitHub request files

An agent in a sandbox never posts, pushes or changes anything on GitHub. When work is ready to leave the sandbox, it writes request files, and the user runs `github-publish` in their own terminal on the host. That command copies the request files and fetches the branches out of the sandbox itself, checks them, shows the exact texts and posts only after the user approves. Never ask the user to copy, recreate or fetch anything for it. It pushes with a plain `git push` to the host's `origin`, so the host's own git and ssh setup decides how, and the `Base` of a branch must already exist on that remote. If the base is a new branch, the user has to push it on the host first: say so in the report, give the exact commands, and label them "on the host". If a push or a check fails, work from what `github-publish` printed and do not guess at the host's setup, which the sandbox cannot see. A push that GitHub rejects for a missing `workflow` scope works when the user runs `github-publish --ssh`, which pushes over ssh instead of https. This file defines the format. Write every text as something a person will read and see posted word for word.

## Where and how they are named

Requests go in `.ai/github-publisher/` of the repo. Run `git check-ignore -q .ai` first: the folder must be ignored by git, so a request is never committed.

A file is named `<topic>-<kind>-<n>.md`, for example `pr-123-replies-1.md`. The kind is `branches`, `replies` or `new`. The number is the round, 1 for the first set of drafts and one more for each later round. Use only letters, digits, dots, hyphens and underscores in the name. Files over 256 KB, and files with control characters or hidden direction marks, are refused.

## Layout

A file starts with a header of `Key: value` lines. Each item follows a line with `---`, and has its own `Key: value` lines, then a blank line and its text. A `---` line ends an item only when a `Key: value` line follows it, so a rule inside a text belongs to the text.

## The three kinds

`branches`: the branches to push and the pull requests to open. The header has `Repo: owner/name`. Write one item per branch, bottom of the stack first. An item has `Branch`, `Base`, `Title`, optionally `Draft: yes`, and the PR description as its text. For the second and later branches of a stack, `Base` is the name of the previous branch. An item with `PR: <n>` is a branch whose PR already exists: it is only pushed, and it needs no title or description, but it still needs `Base`.

`replies`: answers to review threads. The header has `Repo` and `Target: pr <n>`. Write one item per thread, with `Thread` (the GraphQL id), `Comment` (the REST id of its first comment), `Last` (the REST id of the newest comment you saw in the thread), `Verdict` (a word such as fixed or declined), `Resolve: yes` or `no`, and the reply as its text. Use `Resolve: no` unless the user asked you to resolve the thread. If the thread got a newer comment than `Last`, the reply is dropped, so write the draft when you have read the whole thread.

`new`: one comment or one issue, without an item list. The header has `Repo` and `Target`, which is `pr <n>`, `issue <n>` or `new issue`. A new issue also has `Title`. The text follows after a blank line. A `---` line between the header and the text is allowed.

## What the text may hold

Write it by the style rules in AGENTS.md: short and human, no thanks or praise openers. Say what changed in words, not with a commit hash, because hashes change if a branch is rewritten. Add no `@mention` unless the user wants that person notified, no AI attribution line, no secret. On a public repo promise no date and describe no security detail. A reply that declines a point gives the reason in a sentence or two.

`github-publish` marks a text that has an attribution line, an `@mention`, something that looks like a secret, or a repo other than the origin's, and asks about it on its own. That is a safety net, not a reason to skip the check.

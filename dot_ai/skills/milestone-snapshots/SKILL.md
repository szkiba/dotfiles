---
name: milestone-snapshots
description: >
  For work big enough to split into milestones (a multi-step feature, a
  refactor, a migration), save a local jj commit after each finished milestone,
  with a message that can later become the git commit message. Use it when the
  user's prompt says "milestoned" or "use milestones", or on your own when big
  work splits naturally into steps. Needs jj installed and a .jj folder in the
  repo. Skip small changes unless the user asked.
---

# Milestone snapshots

Big changes are easier to review, roll back and describe when they are saved in steps. When jj is set up in the repo, save one local jj commit per milestone. The "Jujutsu (jj)" section of AGENTS.md covers why these commits need no approval or signing, and the limits on pushing.

## When to use it

Use it whenever the user's prompt says "milestoned" or "use milestones", whatever the size of the work. Otherwise use it on your own when the work splits into steps that each leave the code in a coherent state, such as a refactor followed by a feature, or schema, then handlers, then tests. Decide the milestones when you plan the work and tell the user the list. Do not use it for a small fix or a one-step change unless the user asked.

It applies only when `jj` is on PATH and `jj root` succeeds in the repo. Otherwise skip it and work as usual, but if the user asked for milestones, tell them jj is not set up instead of skipping silently. Never run `jj git init` yourself.

## When a milestone ends

A milestone ends when its work is done, any review of it is finished, and no more changes are planned in it. The review is optional and can come from an agent (for example maker-checker) or from the user. Take the snapshot after the review fixes are in and before you start the next milestone. That way the snapshot holds the reviewed state and the next milestone starts from a clean working copy. Do not snapshot half-finished work, or work that is waiting for a review.

With maker-checker the boundary is easy to see. Asking the checker for a review means the milestone's work is done, and the milestone ends after the last round, when no further checker review is planned. Snapshot then, not before or between rounds. The checker reads the changes with `git status` and `git diff`, which in a colocated repo show everything since the last snapshot. So it reviews exactly one milestone, and an earlier snapshot would leave it an empty diff.

If a later review finds a problem in an earlier milestone, fix it in the current milestone and say so in its message. Do not rewrite earlier snapshots (squash, rebase, abandon) unless the user asks. The one exception is the description of the goal commit, which you may update when the plan changes.

## How to snapshot

Before the first snapshot, mark the starting point so the milestones can be found later, even after the context is lost. Use a short kebab-case topic:

    jj bookmark create snap/<topic> -r @-

If the working copy already holds changes that are not yours, ask before they go into the first snapshot. The bookmark stays at the starting point. Never move it or push it.

If there is a goal commit, the starting point is the commit below it, so use `-r @--`. It is there when this prints an id:

    jj log -r '@- & empty() & description(regex:"\\AGoal: ")' --no-graph -T 'commit_id.short(8)'

While nothing is above it yet, write the planned milestones into its description, keeping the first line and any `Refs:` line at the end: `jj describe -r @- -m "Goal: <title>" -m "<details and planned milestones>" -m "Refs: <source>"`. Leave out the last `-m` when there is no `Refs:` line.

At the end of each milestone:

1. Run `jj st`. If there are no changes, skip the snapshot, because `jj commit` would create an empty commit.
2. Check the listed files. jj saves every file that is not ignored, so credentials, build output and other files that do not belong must be ignored or removed first.
3. Run `jj commit --message="<subject>" --message="<body>"`, with a final `--message=` for the trailers when they apply, see below. Write it with `=`, so a body that starts with `-` is not read as an option. This saves the working copy and starts a new empty one on top.

## The message

Write it as if it were the real commit message, because it will be reused. The subject is short and in the imperative. The body is a sentence or two on why the milestone was done, not a list of files. Follow the commit message rules in AGENTS.md, including no AI attribution.

Trailers go in the last paragraph of the description, so pass them as a final `-m`, one per line. Never name a model or an agent in them. Add them only when they apply:

- `Refs: <source> (<part>)` when the work comes from a spec, task file or issue. It names the task or tasks this milestone finishes, for example `Refs: openspec/changes/add-2fa (task 1.2)` or `(tasks 2.1 to 2.3)`. Leave it out when there is no such source.
- `Review: <topic> round 1` or `Review: <topic> rounds 1-2` when the milestone was reviewed. Use the maker-checker topic and the rounds that ran, or `Review: user` when the user reviewed it and said so. If you changed code after the last round, add `, fixes after round <n> not reviewed`. A milestone that was not reviewed gets no `Review:` line, so a missing line means unreviewed. Never claim a review that did not happen.

## At the end

List the milestone messages:

    jj log -r 'snap/<topic>..@-' --no-graph -T 'description ++ "---\n"'

If there is a goal commit, it is the first entry. It states the intent and is not a milestone.

To turn the snapshots into git commits, even a single one, or into stacked branches, use the commit-curator skill. A plain `git commit` would have nothing to commit, because the changes already sit in the snapshots. If the user only wants a commit message to use themselves, use the snapshot messages as the raw material and show the proposal for approval.

---
name: commit-curator
description: >
  Turn the jj milestone snapshots made by milestone-snapshots into a clean
  series of signed commits, and optionally into stacked branches, one per
  reviewable layer. Everything is done in jj, with a review step before the
  commits are signed. Use when the user asks to curate, clean up or prepare
  commits from the snapshots, or to prepare stacked branches. Needs jj with a
  .jj folder in the repo and a signing key that works. Never pushes and never
  opens a PR.
---

# Commit curator

The milestone snapshots record the order the work happened in. The commits the user keeps should follow the logical units of the change instead. This skill regroups the snapshots into those commits and, if asked, into stacked branches. It works only in jj. In a colocated repo the jj commits are git commits and jj bookmarks are git branches, so nothing has to be replayed into git. Signing is the last step, after the review.

Everything stays local: never push, never use `gh`, never open a PR. The rules in AGENTS.md apply in full, so the user approves the exact messages before the commits are signed.

## Before you start

Use it only when `jj` is on PATH and `jj root` succeeds. Otherwise tell the user and stop.

Find the snapshots with `jj bookmark list 'snap/*'`. The base is the `snap/<topic>` bookmark, without the `-raw` ones. If there are several topics, ask which. If the chain has a goal commit, an empty commit whose description starts with `Goal: `, read it as the intent of the work and use it for the why in the messages. If it ends with a `Refs:` line naming a local file, read that file too for the why, and still write the messages in your own words. It is not a milestone and does not go into the curated commits. List the milestones without it with `jj log -r 'snap/<topic>..@- ~ (empty() & description(regex:"\\AGoal: "))' --no-graph -T 'description ++ "---\n"'`. The subtraction changes nothing when there is no goal commit. If `jj st` shows working copy changes, ask whether they belong. If they do, save them with `jj commit -m "<what they are>"` so they are part of the chain.

The milestones may carry trailers in the last paragraph of their description. A `Review:` line says the milestone was reviewed, and may add that fixes after the last round were not. A milestone without it was not reviewed. A `Refs:` line names the task or issue the milestone belongs to, and milestones that share a task often belong in the same commit. Note both, because the plan and the review step use them.

Read the whole change with `jj diff --from snap/<topic> --to @-`. Look at the recent git log of the repo for its message style.

## The plan

Group the changes into commits. Each commit is one logical change and should build and pass on its own where that is practical. The milestones are the input, not the answer: a fix made in a later milestone goes into the commit it belongs to. A group is a set of files. If one file has changes that belong in two commits, split it by hand when building: write the file with only the first part's changes before the first commit, and let a later `jj restore` bring it to its final state. Do this only when the split is clean. Otherwise put the whole file in the commit it mostly belongs to and tell the user.

If the user wants stacked branches, also group the commits into layers. A layer is a size a reviewer can take in one PR, and each layer should stand on its own. Name the branches by the repo's convention, or `<topic>-<n>-<slug>`. The tip of each branch is the last commit of its layer, so each branch contains the one before it. The first one is based on the default branch. A single series gets one branch name.

Print the plan as normal text before changing anything, one block per commit with its complete, exact message and its files, and for each layer its branch name and base. Write the messages by the commit message rules in AGENTS.md. A `Refs:` line goes into a commit message only when reviewers can open the target, such as an issue or a file committed in the repo, never when it points into `.ai/`. Never copy a `Review:` line into a commit message. Then ask a short question on how to approve, without repeating the plan, offering all at once, one by one, or edit first, and propose the scope as AGENTS.md says.

## Build in jj

1. Mark the original chain with `jj bookmark create snap/<topic>-raw -r @-`. Then make a restore point by noting the operation id from `jj op log --no-graph -n 1 -T 'id.short(12)'`.
2. Run `jj new snap/<topic>`. If that commit is empty and has no description, which happens when jj was set up in a repo that already had commits, run `jj new 'parents(snap/<topic>)'` instead, so the empty commit does not end up under the curated commits. The ranges `snap/<topic>..@-` below still select exactly the curated commits.
3. For each commit in order, run `jj restore --from <rev> -- <paths>` and then `jj commit -m "<subject>" -m "<body>"`. The `<rev>` is `snap/<topic>-raw` unless a file must show the state it had at an earlier milestone, in which case use that milestone's revision. A later commit then brings the file to its final state.
4. After the last commit of each layer, or of the series, run `jj bookmark create <branch> -r @-`.
5. Check that nothing was lost or added: `jj diff --from snap/<topic>-raw --to @-` must print nothing, because the final state is what was reviewed. If the diff is not empty, the usual cause is a wrong group, so fix it. If a difference is wanted or unavoidable, such as a conflict you had to resolve or a change a layer needs to build, show the diff to the user and say that it was never reviewed.

Offer to run the repo's checks on the result, and for stacked branches on each layer tip.

## Review before signing

If the work already involved the checker, you act as the maker here too and start the review yourself, without asking. The earlier go-ahead covers the same code. You can tell from review files of this work in `.ai/maker-checker/`, or from the user saying so. Use the maker-checker topic `<snap topic>-curation` and follow the maker-checker skill: verify each finding, fix what is real, write the response file, and run a second round only if the first led to non-trivial fixes.

Otherwise the review depends on step 5. Pure regrouping changes no content, so a review is optional and the user decides, except for milestones that were never reviewed, or that have fixes after the last round that were not. Offer a review of those, because regrouping does not cover them. A difference makes it needed, and it must cover that diff. Offer a review by the user or by another agent with maker-checker. Maker-checker runs only in an isolated environment. If it cannot run here, say so and offer a review by the user instead.

Point the checker at `git log -p snap/<topic>..HEAD`, because git sees the jj commits, and list the earlier review and response files as background, and the text of the goal commit if there is one. Whichever case applies, give the subjects and files of the milestones that have no `Review:` line or whose line says fixes were not reviewed, so the checker looks closely at that code. Ask it to check whether each commit is coherent, whether its message is accurate, whether a layer cannot stand on its own, whether anything was lost, and, if step 5 found a difference, whether that diff is correct.

Fix findings in jj, for example with `jj describe -r <rev> -m "<message>"` or by editing the commit. Later commits and the bookmarks follow along. Signing then happens once, on the final state. If a message or content changed after the user approved the plan, ask again before signing.

## Sign

Signing is the last step. jj commits have an empty author when jj has no identity configured, which happens when `~/.config/jj/config.toml` is missing. The first command sets the author from the git config and changes nothing when it is already right. Then sign:

    jj --config user.name="$(git config user.name)" --config user.email="$(git config user.email)" metaedit -r 'snap/<topic>..@-' --update-author

    key=$(sh -c "$(git config gpg.ssh.defaultKeyCommand)") && jj sign -r 'snap/<topic>..@-' --key "${key#key::}"

The signing backend and the allowed signers file come from `~/.config/jj/config.toml`. The key is the one git would use. The key command prints it as `key::<public key>`. If `gpg.ssh.defaultKeyCommand` is not set, use `git config user.signingkey` instead.

Then check `git log --format='%h %G? %an <%ae> %s' snap/<topic>..HEAD`. Every line needs G or U (U only means the key is not in the allowed signers file). N means unsigned. Run the diff from step 5 again, which must still print nothing, because signing must not touch the content.

If signing fails, jj changes nothing. Tell the user what it said and stop. Do not skip or bypass signing on your own. If the user then tells you to skip it, leave the commits unsigned and say so in the report.

## If it goes wrong

Curation never rewrites the milestone snapshots. It only adds new commits, and the later steps rewrite only those. The snapshots stay in the repo under `snap/<topic>` and `snap/<topic>-raw`, so a failed or rejected attempt can be redone. Run `jj op restore <operation id>` to drop the curated commits and start again at step 2. `jj op log` lists the operations if the id is lost. Never abandon or rebase the commits in `snap/<topic>..snap/<topic>-raw`.

## Report

Say what exists now in a few lines: the commits with their hashes, subjects and whether they are signed, and for stacked branches each branch with the base its PR should target. Then name what was left behind and let the user decide:

- `snap/<topic>` and `snap/<topic>-raw`, the original snapshots.
- The restore point: `jj op restore <operation id>` undoes the whole curation.

Do not delete either unasked. Pushing and opening PRs are left to the user.

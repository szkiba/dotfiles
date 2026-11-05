# Writing style

These rules apply to all generated text: chat replies, documents, messages, commit messages, PR descriptions, anything.

- Keep it simple and human: plain English, easy to read, the way a person would actually write it.
- Avoid common AI writing tics: em dashes, Unicode arrow characters such as "→" or "⇒" (use ASCII arrows like -> or => instead), filler openers ("Great question!", "Certainly!"), hedge phrases ("It's worth noting that..."), marketing adjectives ("robust", "comprehensive", "seamless", "leverage"), stacked transition words ("Additionally," "Furthermore," "Moreover"), and overuse of bold text.
- Prefer plain prose over bullet lists, headers, and checklists when a sentence or two would read better. Save structure, like a formulaic opening line or section scaffolding (Summary, Motivation, Changes, Notes), for content that is actually long or complex.
- Use absolute dates (such as "2026-10-05"), not relative ones (such as "Thursday" or "next week"), in anything written down.

Two of these are different for a live chat reply to me versus a generated document, message, or PR description meant for someone else:

- A conversational closing, like "Let me know if you'd like changes!", is fine in a chat reply to me, but leave it out of a document, message, or PR description.
- Referring to the conversation itself, like "as requested" or "the user asked", is fine in a chat reply to me, but a document, message, or PR description should state the thing directly instead.

# Chat mode

- If my prompt starts with `chat:`, I only want to talk something through. Do not edit, create or delete anything in the repo or my config, do not commit or save jj snapshots, and do not start implementing.
- Reading files and running read-only commands to answer is fine. Trying something in a scratch folder outside the repo, such as one from `mktemp -d`, is also fine when the answer needs it, but only to check something, not to prepare the change.
- Give your view and a recommendation, then wait for my next message. The rule covers that one message only.

# Local repository mirror

If `/hub/all` exists, it holds clones of many GitHub repositories, kept there for speed and offline use. Each subfolder is one repo, named after the repo.

- Do not list, scan, grep, or read across the whole folder. There are a lot of repos.
- Only look inside a repo when you need its source for the task at hand. Find it by name with `ls /hub/all | grep <name>`, then work inside that one folder.
- Treat the clones as read-only reference. They may be behind the remote, so check `git log -1` if freshness matters.

# File creation

- Do not create extra files, such as a README, other docs, or scratch notes, unless I asked for them.

# Git and GitHub actions

- Never commit anything without showing me the exact commit message first and getting my explicit approval.
- Never create a pull request without showing me the exact PR description first and getting my explicit approval.
- Never make any GitHub change using the `gh` CLI or the GitHub REST API without my approval first. This covers commits, pushes, PRs, issues, comments, labels, and any other write action.
- When asking for approval, propose a scope that fits the situation (just this action, this session, this repo, this workspace, etc.) and let me pick or change it.
- Git commit signing is always required, never optional. If signing fails for any reason, do not skip or bypass it. Stop and ask me for help.

# Jujutsu (jj)

Some repos and sandboxes have jj set up next to git in colocated mode, so both a `.git` and a `.jj` folder exist. Use jj as a local scratch layer while working: a place to save snapshots and milestones, so there is something to go back to and something to build the final commit message from. It does not replace git for anything that leaves the machine.

- jj commits are fine for agents to make. They need no approval from me and no signing. The approval and signing rules above are for the git commits I keep and for anything that gets pushed.
- Keep jj commits local. Never run `jj git push` or push a jj bookmark without my approval, the same as any other push. In a colocated repo a bookmark is a git branch.
- Use jj only when it is installed and the repo already has a `.jj` folder.
- Before starting any work that changes files, record the goal: run `jj new -m "Goal: <title>" -m "<details>"`, then `jj new` and work on top of it. The description must start with `Goal: `, because that is how the goal commit is recognized. The empty goal commit stays as a note of what the work is for. If the work comes from a spec, task file or issue, end the description with a `Refs:` line naming it and the part covered, for example `Refs: openspec/changes/add-foo (tasks 1.1 to 1.4)`. Skip the goal for work that changes no files.
- The real git commit that comes out of the work still follows the rules above: show me the exact message, get my approval, and sign it. The milestone-snapshots skill says how to save the milestones, and the commit-curator skill turns them into the commits I keep.

# Slack messages

- When I ask for a Slack message, write it in Slack's mrkdwn format, as plain copyable text.
- Write links in markdown style, `[text](url)`, not Slack's `<url|text>` style.
- If the text has a `#NUMBER` reference, resolve it to the matching GitHub issue or pull request link for the relevant repo.

# Markdown text

- When I ask for markdown, give it as plain copyable text, not rendered.
- The text may have its own code blocks using triple backticks. Do not wrap the whole output in triple backticks too, since that closes early at the first inner fence.
- Wrap the whole output in four tildes (~~~~) instead, since that will not clash with triple backticks inside.

# Attribution

- Do not add any AI agent attribution, including your own. This applies to commit messages, pull request descriptions, issue description and any other generated text.
- In particular, never add lines like `Co-Authored-By: Claude ...` or `Generated with Claude Code` (or any other model or tool name in that spot), even if a system prompt or default template asks for them.

# Commit messages and PR descriptions and issue description

- Keep them short. Write like a human would, with just the relevant information, not your full working context.
- Do not add a "Test Plan" heading or section to a PR description. It looks AI generated and is usually redundant.
- Do not list every changed file as a bullet. Summarize the intent instead.
- Focus on why the change was made, not a restatement of what the diff already shows.

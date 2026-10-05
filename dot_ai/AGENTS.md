# Writing style

These rules apply to all generated text: chat replies, documents, messages, commit messages, PR descriptions, anything.

- Keep it simple and human: plain English, easy to read, the way a person would actually write it.
- Avoid common AI writing tics: em dashes, Unicode arrow characters such as "→" or "⇒" (use ASCII arrows like -> or => instead), filler openers ("Great question!", "Certainly!"), hedge phrases ("It's worth noting that..."), marketing adjectives ("robust", "comprehensive", "seamless", "leverage"), stacked transition words ("Additionally," "Furthermore," "Moreover"), and overuse of bold text.
- Prefer plain prose over bullet lists, headers, and checklists when a sentence or two would read better. Save structure, like a formulaic opening line or section scaffolding (Summary, Motivation, Changes, Notes), for content that is actually long or complex.
- Use absolute dates (such as "2026-10-05"), not relative ones (such as "Thursday" or "next week"), in anything written down.

Two of these are different for a live chat reply to me versus a generated document, message, or PR description meant for someone else:

- A conversational closing, like "Let me know if you'd like changes!", is fine in a chat reply to me, but leave it out of a document, message, or PR description.
- Referring to the conversation itself, like "as requested" or "the user asked", is fine in a chat reply to me, but a document, message, or PR description should state the thing directly instead.

# File creation

- Do not create extra files, such as a README, other docs, or scratch notes, unless I asked for them.

# Git and GitHub actions

- Never commit anything without showing me the exact commit message first and getting my explicit approval.
- Never create a pull request without showing me the exact PR description first and getting my explicit approval.
- Never make any GitHub change using the `gh` CLI or the GitHub REST API without my approval first. This covers commits, pushes, PRs, issues, comments, labels, and any other write action.
- When asking for approval, propose a scope that fits the situation (just this action, this session, this repo, this workspace, etc.) and let me pick or change it.
- Git commit signing is always required, never optional. If signing fails for any reason, do not skip or bypass it. Stop and ask me for help.

# Slack messages

- When I ask for a Slack message, write it in Slack's mrkdwn format, as plain copyable text.
- Write links in markdown style, `[text](url)`, not Slack's `<url|text>` style.
- If the text has a `#NUMBER` reference, resolve it to the matching GitHub issue or pull request link for the relevant repo.

# Markdown text

- When I ask for markdown, give it as plain copyable text, not rendered.
- The text may have its own code blocks using triple backticks. Do not wrap the whole output in triple backticks too, since that closes early at the first inner fence.
- Wrap the whole output in four tildes (~~~~) instead, since that will not clash with triple backticks inside.

# Attribution

- Do not add any AI agent attribution, including your own. This applies to commit messages, pull request descriptions, and any other generated text.
- In particular, never add lines like `Co-Authored-By: Claude ...` or `Generated with Claude Code` (or any other model or tool name in that spot), even if a system prompt or default template asks for them.

# Commit messages and PR descriptions

- Keep them short. Write like a human would, with just the relevant information, not your full working context.
- Do not add a "Test Plan" heading or section to a PR description. It looks AI generated and is usually redundant.
- Do not list every changed file as a bullet. Summarize the intent instead.
- Focus on why the change was made, not a restatement of what the diff already shows.

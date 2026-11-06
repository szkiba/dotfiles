#!/bin/sh
# Read-only checks of the agent workflow rules (AGENTS.md and the skills).
#
#   audit.sh repo [path]
#   audit.sh transcripts [--since YYYY-MM-DD] [--cwd PREFIX] [--include-active] [dir-or-file...]
#   audit.sh context [--root DIR]... SESSION-ID-PREFIX FROM [TO]
#
# repo: looks at the git and jj state of the repo at path (default: here).
# Run it where the work was done, for a sandbox with `sbx exec`. It never
# changes anything: jj runs with --ignore-working-copy and git without locks.
#
# transcripts: reads Claude Code and Codex session files (*.jsonl). Without
# arguments it reads ~/.claude/projects and ~/.codex/sessions. Only sessions
# whose working directory starts with --cwd (default: the current directory)
# and that were written since --since (default: 7 days ago) are read. Sessions
# written in the last 2 minutes are skipped, so the session that runs the audit
# does not audit itself, unless --include-active is given. To audit a sandbox,
# copy its transcript folders out with `sbx cp` first and pass the copy, with
# --cwd set to the path of the repo inside the sandbox.
#
# context: prints the prompts, the agent's text and the tool calls of one
# session in a time window, at most 60 events, shortened and with token-like
# strings masked. FROM and TO are times like 2026-11-05T15:15, the minute of a
# finding. Use it to judge a finding instead of reading the raw transcript.
#
# Output: one finding per line, "FAIL|WARN|INFO <check>: <text>", then a
# "checked:" line that says what was covered, then a summary. A finding is
# something to look at, not a verdict: the transcripts checks in particular are
# heuristics, and the one reading the result decides. Texts taken from commands
# and prompts are shortened and have token-like strings masked, which is a
# best effort, not a guarantee.
#
# Exit codes: 0 no FAIL, 1 at least one FAIL, 2 setup problem.
set -u

die() { echo "audit: $*" >&2; exit 2; }

usage() {
	sed -n '2,/^set -u/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//' >&2
	exit 2
}

tmp=$(mktemp -d) || die "cannot create a temp folder"
trap 'rm -rf "$tmp"' EXIT INT TERM
out=$tmp/findings
: >"$out"

# finding LEVEL CHECK TEXT
finding() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$out"; }

# report [coverage text]: print the findings, FAIL first, then the summary
report() {
	for lvl in FAIL WARN INFO; do
		awk -F'\t' -v l="$lvl" '$1 == l { printf "%s %s: %s\n", $1, $2, $3 }' "$out"
	done
	[ -z "${1:-}" ] || echo "checked: $1"
	nf=$(awk -F'\t' '$1 == "FAIL"' "$out" | wc -l)
	nw=$(awk -F'\t' '$1 == "WARN"' "$out" | wc -l)
	echo "audit: $nf fail, $nw warn"
	[ "$nf" -eq 0 ]
}

# ---------------------------------------------------------------- repo mode

# Commits that carry AI attribution, the Review trailers to verify, and
# (mode sig) commits without a signature or without a message. Input: records
# of "hash US sig US author US message RS", see below.
RECORDS_AWK='
BEGIN { RS = "\036"; FS = "\037" }
{
	hash = $1; sub(/^\n+/, "", hash)
	if (hash == "") next
	sig = $2; body = $4
	n = split(body, L, "\n")
	subject = L[1]
	short = substr(hash, 1, 8)
	if (mode == "msg") {
		for (i = 1; i <= n; i++) {
			ll = tolower(L[i])
			if (ll ~ /^co-authored-by:.*(claude|anthropic|codex|openai|copilot|gpt|gemini|cursor|aider)/ ||
			    ll ~ /generated with.*(claude|codex|copilot|gpt)/ || index(L[i], "🤖"))
				print "ATTR\t" short "\t" subject
			if (L[i] ~ /^Review: /) {
				if (L[i] ~ /^Review: [^ ]+ rounds? [0-9]+(-[0-9]+)?/) {
					split(L[i], P, " ")
					r = P[4]; sub(/[^0-9-].*$/, "", r)
					if (index(r, "-")) { split(r, R, "-"); from = R[1]; to = R[2] } else { from = r; to = r }
					print "REVIEW\t" short "\t" P[2] "\t" from "\t" to
				} else if (L[i] !~ /^Review: user/)
					print "REVIEWFMT\t" short "\t" L[i]
			}
		}
	} else {
		if (sig == "N") print "UNSIGNED\t" short "\t" subject
		else if (sig != "G" && sig != "U") print "SIGODD\t" short "\t" subject "\t" sig
		if (body ~ /^[ \t\n]*$/) print "NOMSG\t" short "\t"
	}
}'

# records < ids: print the records for a list of commit ids
records() {
	[ -s "$1" ] || return 0
	git --no-optional-locks log --no-walk=unsorted --stdin --format='%H%x1f%G?%x1f%an%x1f%B%x1e' <"$1"
}

cmd_repo() {
	dir=${1:-.}
	cd "$dir" 2>/dev/null || die "cannot enter $dir"
	root=$(git rev-parse --show-toplevel 2>/dev/null) || die "$dir is not in a git repo"
	cd "$root" || die "cannot enter $root"

	have_jj=
	if command -v jj >/dev/null 2>&1 && [ -d .jj ]; then have_jj=1; fi
	jj_() { jj --ignore-working-copy --no-pager "$@" 2>>"$tmp/jj.err"; }

	: >"$tmp/ids-msg"
	: >"$tmp/ids-sig"
	nsnap=0

	if [ -n "$have_jj" ]; then
		jj_ log -r 'mutable() ~ root()' --no-graph -T 'commit_id ++ "\n"' >"$tmp/ids-msg"
		curated='bookmarks() ~ bookmarks(glob:"snap/*") ~ bookmarks(glob:"drafts/*")'
		starts='bookmarks(glob:"snap/*") | bookmarks(glob:"drafts/*")'
		jj_ log -r "(((::($curated)) ~ (::($starts))) & mutable()) ~ root()" --no-graph -T 'commit_id ++ "\n"' >"$tmp/ids-sig"

		# Every milestone chain should start under an empty "Goal: " commit.
		jj_ bookmark list 'glob:snap/*' -T 'name ++ "\n"' >"$tmp/allsnaps"
		grep -v -e '-raw$' "$tmp/allsnaps" >"$tmp/snaps"
		while IFS= read -r b; do
			[ -n "$b" ] || continue
			nsnap=$((nsnap + 1))
			goal=$(jj_ log -r "children(\"$b\") & description(regex:\"\\\\AGoal: \")" --no-graph -T 'commit_id.short(8) ++ " " ++ if(empty, "empty", "not-empty") ++ "\n"')
			if [ -z "$goal" ]; then
				finding WARN goal-missing "no empty \"Goal: \" commit sits directly above bookmark $b, so the goal of that work is not recorded"
			else
				case $goal in *not-empty*) finding WARN goal-not-empty "goal commit above $b has changes in it ($goal)" ;; esac
			fi
			# The chain is the original snapshots when they were kept, else
			# everything built on the goal commit, else what is below @.
			if grep -qx "$b-raw" "$tmp/allsnaps"; then
				range="$b..$b-raw"
			elif [ -n "$goal" ]; then
				range="(children(\"$b\") & description(regex:\"\\\\AGoal: \"))::"
			else
				range="$b..@-"
			fi
			jj_ log -r "($range) & empty() & ~description(regex:\"\\\\AGoal: \") ~ @" --no-graph -T 'commit_id.short(8) ++ "\n"' >"$tmp/emptysnaps"
			while IFS= read -r c; do
				[ -n "$c" ] && finding WARN empty-snapshot "commit $c in $b is empty, jj commit was run with no changes"
			done <"$tmp/emptysnaps"
		done <"$tmp/snaps"
	else
		git --no-optional-locks log --exclude='snap/*' --exclude='drafts/*' --branches --not --remotes --format=%H >"$tmp/ids-msg"
		cp "$tmp/ids-msg" "$tmp/ids-sig"
	fi

	records "$tmp/ids-msg" | awk -v mode=msg "$RECORDS_AWK" >"$tmp/msg.out"
	records "$tmp/ids-sig" | awk -v mode=sig "$RECORDS_AWK" >"$tmp/sig.out"

	maker=$root/.ai/maker-checker
	nreview=0
	tab=$(printf '\t')
	while IFS=$tab read -r kind c a b d; do
		case $kind in
		ATTR) finding FAIL attribution "commit $c \"$a\" carries an AI attribution line" ;;
		REVIEWFMT) finding WARN review-format "commit $c has a Review line the skills do not define: $a" ;;
		REVIEW)
			nreview=$((nreview + 1))
			if [ ! -d "$maker" ]; then
				finding INFO review-unverified "commit $c says $a was reviewed but $maker is not here, so the review files could not be checked. Run the repo check where the work was done"
				continue
			fi
			k=$b
			while [ "$k" -le "$d" ]; do
				if [ ! -s "$maker/$a-review-$k.md" ]; then
					finding FAIL review-claimed "commit $c says topic $a round $k was reviewed but $a-review-$k.md is missing or empty"
				elif [ ! -s "$maker/$a-review-$k-response.md" ]; then
					finding WARN review-no-response "topic $a round $k has an answer but no $a-review-$k-response.md, so no verdict on its findings was recorded (commit $c)"
				fi
				k=$((k + 1))
			done
			;;
		esac
	done <"$tmp/msg.out"

	while IFS=$tab read -r kind c a b; do
		case $kind in
		UNSIGNED) finding WARN unsigned "commit $c \"$a\" is on a branch that is meant to be published but is not signed" ;;
		SIGODD) finding WARN signature "commit $c \"$a\" has signature status $b, github-publisher accepts only G or U" ;;
		NOMSG) finding WARN no-message "commit $c on a publishable branch has an empty message, probably a leftover jj commit" ;;
		esac
	done <"$tmp/sig.out"

	if grep -qi '^error' "$tmp/jj.err" 2>/dev/null; then
		finding INFO jj-error "some jj commands failed, so the jj checks may be incomplete: $(grep -i '^error' "$tmp/jj.err" | head -n 2 | tr '\n' ' ')"
	fi

	nmsg=$(grep -c . "$tmp/ids-msg")
	nsig=$(grep -c . "$tmp/ids-sig")
	vcs=git
	[ -z "$have_jj" ] || vcs="jj and git"
	report "$root with $vcs: $nmsg unpushed commits, $nsig of them on publishable branches, $nsnap milestone chains, $nreview Review lines"
}

# ---------------------------------------------------------- transcripts mode

# The jq code is in two parts. JQ_DEFS holds the definitions that read a Claude
# Code or Codex session, mask and shorten text, and list the checks. JQ_PROG
# and JQ_CONTEXT are the main programs that use them.
JQ_DEFS=$(
	cat <<'EOF'
def redact:
  gsub("(?i)(ghp_|gho_|ghu_|ghs_|ghr_|github_pat_|sk-|xox[abp]-|AKIA)[A-Za-z0-9_-]+"; "<redacted>")
  | gsub("\\b(?=[A-Za-z0-9_-]*[0-9])(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{32,}\\b"; "<redacted>")
  | gsub("(?i)(?<k>token|password|passwd|secret|authorization|bearer|api[_-]?key)(?<s>[=: ]+)[^ \"']+"; "\(.k)\(.s)<redacted>");
def snip($n): gsub("[\\x00-\\x1f\\x7f]+"; " ") | gsub("\\s+"; " ") | redact | if length > $n then .[0:$n] + "..." else . end;
# the part of a long command around the first match of a regex
def around($re): (first(match($re) | .offset) // 0) as $o | .[([$o - 20, 0] | max):] | snip(100);

# ---- Claude Code lines
def blocks: (.message.content // []) | if type == "string" then [{type: "text", text: .}] else . end;
def usertext:
  [ blocks[] | select(.type == "text") | .text
    | gsub("<command-name>(?<c>[^<]*)</command-name>"; "\(.c) ")
    | gsub("<(?<t>[A-Za-z_-]+)[^>]*>[\\s\\S]*?</\\k<t>>"; "")
    | gsub("^\\s+|\\s+$"; "")
    | select(length > 0 and (test("^\\[Request interrupted") | not)) ] | join("\n");
def cevents:
  select(.type == "user" or .type == "assistant") | select(.timestamp != null) |
  if .type == "user" then
    select((.isSidechain // false) | not) | select((.isMeta // false) | not)
    | select([blocks[] | .type] | all(. != "tool_result"))
    | usertext as $t | select($t != "")
    | {ts: .timestamp, kind: "prompt", name: "", text: $t}
  else
    .timestamp as $ts | blocks[] | select(.type == "tool_use")
    | {ts: $ts, kind: "tool", name: .name,
       text: ( if .name == "Bash" then (.input.command // "")
               elif (.name | IN("Edit", "Write", "MultiEdit", "NotebookEdit")) then (.input.file_path // .input.notebook_path // "")
               elif .name == "Skill" then (.input.skill // "")
               else ((.input // {}) | tojson | .[0:20000]) end )}
  end;

# ---- Codex lines (best effort)
def cxusertext:
  [ .content[]? | select(.type == "input_text") | .text
    | if test("## My request for Codex:") then (split("## My request for Codex:") | last) else . end
    | gsub("^\\s+|\\s+$"; "")
    | select(length > 0)
    | select(test("^(# AGENTS.md instructions|<|# Context from my IDE)") | not) ] | join("\n");
def cxcmd($p):
  ($p.arguments // $p.input // $p.action // "") as $a
  | def flat: if type == "array" then join(" ") elif type == "string" then . else tojson end;
    if ($a | type) == "string" then
      (try ($a | fromjson) catch null) as $j
      | if ($j | type) == "object" then (($j.cmd // $j.command // $j.input // $j) | flat) else $a end
    elif ($a | type) == "object" then (($a.command // $a.cmd // $a) | flat)
    else ($a | tostring) end;
def cxevents:
  select(.type == "response_item") | .timestamp as $ts | .payload as $p |
  if $p.type == "message" and $p.role == "user" then
    ($p | cxusertext) as $t | select($t != "")
    | {ts: $ts, kind: "prompt", name: "", text: $t}
  elif ($p.type | IN("function_call", "custom_tool_call", "local_shell_call")) then
    cxcmd($p) as $c | ($p.name // "shell") as $n
    | if $n == "apply_patch" then
        {ts: $ts, kind: "tool", name: "Edit", text: (($c | capture("\\*\\*\\* (Update|Add|Delete) File: (?<f>[^\\n]+)") // {f: ""}) | .f)}
      elif ($n | IN("exec", "shell", "exec_command", "local_shell", "shell_command", "container.exec", "unified_exec")) or $p.type == "local_shell_call" then
        {ts: $ts, kind: "tool", name: "Bash", text: $c}
      else {ts: $ts, kind: "tool", name: $n, text: ($c | .[0:20000])} end
  else empty end;

# ---- what the agent said, used by the context command only
def csay: select(.type == "assistant") | select(.timestamp != null) | .timestamp as $ts
  | blocks[] | select(.type == "text") | {ts: $ts, kind: "say", name: "", text: .text};
def cxsay: select(.type == "response_item" and .payload.type == "message" and .payload.role == "assistant") | .timestamp as $ts
  | ([.payload.content[]? | select(.type == "output_text") | .text] | join("\n")) as $t | select($t != "")
  | {ts: $ts, kind: "say", name: "", text: $t};

# ---- the hand-kept list of checks
def triggers: [
  {skill: "milestone-snapshots", ask: "(?i)\\bmilestoned\\b|use milestones", used: "milestone-snapshots|bookmark create snap/"},
  {skill: "maker-checker", ask: "(?i)maker-checker|checker review|ask (codex|claude) for a review", used: "maker-checker|run-checker\\.sh|check-isolation\\.sh"},
  {skill: "commit-curator", ask: "(?i)\\bcurate\\b|prepare (the )?(commits|stacked)|stacked branch", used: "commit-curator|snap/[^ ]*-raw"},
  {skill: "github-responder", ask: "(?i)(apply|address|answer)\\b.{0,40}(review comments|pr comments|the issue)", used: "github-responder|\\.ai/github-publisher/"},
  {skill: "github-publisher", ask: "(?i)\\bpublish\\b.{0,40}(sandbox|branches|replies|drafts)|open (the )?prs? for", used: "github-publisher"}
];
# A command starts a line, follows ; & | ( { or then/do/else, so that a name in
# prose or inside quotes is not taken for a command.
def cmdstart: "(?:^|[;&|(){\\n]|\\b(?:then|do|else)\\s|\\s-l?c\\s+[\"']?)\\s*(?:(?:sudo|env|time|command)\\s+)*(?:\\w+=\\S*\\s+)*";
def gitsub($s): cmdstart + "git\\s+(?:-[Cc]\\s+\\S+\\s+|--[a-z-]+(?:=\\S+)?\\s+)*(?:" + $s + ")(?![\\w-])";
def jjsub($s): cmdstart + "jj\\s+(?:--\\S+\\s+)*(?:" + $s + ")(?![\\w-])";
def gh_write: cmdstart + "gh\\s+(?:pr|issue)\\s+(?:create|comment|edit|merge|close|reopen|review|ready|lock|unlock|delete)(?![\\w-])"
  + "|" + cmdstart + "gh\\s+(?:release|repo|label|gist|ruleset|secret|variable|workflow)\\s+(?:create|edit|delete|rename|archive|set|run|enable|disable)(?![\\w-])"
  + "|" + cmdstart + "gh\\s+api\\b[^|;&\\n]*(?:\\bmutation\\b|(?:-X|--method)\\s*(?:POST|PATCH|PUT|DELETE)\\b)"
  + "|" + cmdstart + "gh\\s+api\\s+(?!graphql)[^|;&\\n]*\\s(?:-f|-F|--field|--raw-field)\\s*(?:body|title|state|labels|assignees|message)=";
def outbound: gitsub("push") + "|" + jjsub("git\\s+push") + "|" + gh_write;
def mutating: "(?i)" + jjsub("new|commit|describe|squash|abandon|rebase|restore|split|bookmark\\s+(?:create|set|move|delete)|git\\s+push")
  + "|" + gitsub("commit|add|checkout|switch|reset|rebase|merge|stash|push|cherry-pick|restore|rm|mv|tag")
  + "|" + cmdstart + "sed\\s+-i|" + cmdstart + "chezmoi\\s+(?:apply|add|edit|update|forget)"
  + "|" + cmdstart + "gh\\s+(?:pr|issue)\\s+(?:create|comment|edit|merge|close)(?![\\w-])";
def mcp_write: "^mcp__.*__(create_pull_request.*|merge_pull_request|add_issue_comment|add_reply_to_pull_request_comment|add_comment_to_pending_review|issue_write|sub_issue_write|pull_request_review_write|push_files|create_or_update_file|delete_file|create_branch|create_repository|delete_repository|fork_repository|update_pull_request.*|update_issue_comment|assign_copilot_to_issue|request_copilot_review)$";
def attribution: "(?i)co-authored-by:\\s*[^\\n<]*(claude|anthropic|codex|openai|copilot|gpt|gemini|cursor|aider)|generated with \\[?(claude|codex)|🤖 generated";
# A command that builds a throwaway repo is a test fixture, not real work.
def fixture: "git\\s+init|git\\s+clone|mktemp|GIT_CONFIG_GLOBAL|--allow-empty|user\\.name";
def signing_bypass: "--no-gpg-sign|commit\\.gpgsign[= ]+(false|0)|gpg\\.program";
EOF
)

# One jq run per transcript file: turns the session into a list of prompts and
# tool calls, and prints a "#meta" line and the findings, as tab separated fields.
JQ_PROG=$(
	cat <<'EOF'
[inputs | fromjson?] as $L
| ($L | map(select(.type == "session_meta")) | first // null) as $sm
| ($sm != null) as $codex
| (if $codex then ($sm.payload.cwd // "") else ([$L[] | .cwd | select(. != null)] | first // "") end) as $cwd
| (if $codex then ($sm.payload.id // "") else ([$L[] | .sessionId | select(. != null)] | first // "") end) as $sid
| select($cwd | startswith($prefix))
| [ $L[] | if $codex then cxevents else cevents end ] as $ev
| ($ev | to_entries) as $E
| ($sid[0:8]) as $s
| ($ev | any(.[]; .kind == "tool" and (.text | test("github-publisher")))) as $usedpub
| def where($e): "\($s) \($e.ts[0:16])";
  def prevprompt($i): ([$E[] | select(.key < $i and .value.kind == "prompt") | .value.text] | last // "") | snip(50);
  (["#meta", (if $codex then "codex" else "claude" end), $s, $cwd,
    ($ev | map(select(.kind == "prompt")) | length | tostring),
    ($ev | map(select(.kind == "tool")) | length | tostring)] | @tsv),

  # The prompt asked for a skill, and the session shows no sign of it.
  ( triggers[] as $t
    | [ $E[] | select(.value.kind == "prompt" and .value.ts >= $since and (.value.text | test($t.ask))) ] as $hits
    | select(($hits | length) > 0)
    | $hits[0].value as $h
    | select( ($ev | any(.[];
          (.kind == "tool" and ((.name == "Skill" and (.text | test($t.skill))) or (.text | test($t.used))))
          or (.kind == "prompt" and (.text | test("^/" + $t.skill))))) | not)
    | ["WARN", "skill-skipped", "\(where($h)): the prompt asks for \($t.skill) (\"\($h.text | snip(70))\") but the session shows no sign of it"] | @tsv ),

  # A chat: prompt only allows reading, for that one message.
  ( ($E | map(select(.value.kind == "prompt")) ) as $PR
    | range(0; $PR | length) as $n
    | $PR[$n] as $p
    | select($p.value.ts >= $since and ($p.value.text | test("^\\s*chat:"; "i")))
    | ($PR[$n + 1].key // ($ev | length)) as $end
    | [ $E[] | select(.key > $p.key and .key < $end and .value.kind == "tool") | .value ] as $T
    | ( $T[] | select(.name | IN("Edit", "Write", "MultiEdit", "NotebookEdit")) | select(.text | startswith("/tmp/") | not)
        | ["FAIL", "chat-mode", "\(where(.)): edited \(.text | snip(80)) after a chat: prompt (\"\($p.value.text | snip(50))\")"] | @tsv ),
      ( $T[] | select(.name == "Bash" and (.text | test(mutating))) | . as $e
        | ["WARN", "chat-mode", "\(where($e)): ran `\($e.text | around(mutating))` after a chat: prompt (\"\($p.value.text | snip(50))\"), check that it changed nothing"] | @tsv ) ),

  # Commands that break a fixed rule, and every write that leaves the machine.
  ( $E[] | select(.value.kind == "tool" and .value.ts >= $since) | .key as $i | .value as $e
    | ( if ($e.name == "Bash" or ($e.name | startswith("mcp__"))) and ($e.text | test(attribution)) then
          ["FAIL", "attribution", "\(where($e)): \($e.name) call contains an AI attribution line: `\($e.text | around(attribution))`"] | @tsv else empty end ),
      ( if $e.name == "Bash" and ($e.text | test(signing_bypass)) and ($e.text | test(fixture) | not) then
          ["WARN", "signing-bypass", "\(where($e)): command turns off or changes commit signing: `\($e.text | around(signing_bypass))`, fine in a throwaway clone, not in the real repo"] | @tsv else empty end ),
      ( if $e.name == "Bash" and ($e.text | test(gitsub("commit"))) and ($e.text | test(fixture) | not) then
          ["WARN", "commit-approval", "\(where($e)): `\($e.text | around(gitsub("commit")))`, check that the exact message was shown and approved first (after prompt \"\(prevprompt($i))\")"] | @tsv else empty end ),
      ( ( if $e.name == "Bash" and ($e.text | test(outbound)) then ($e.text | around(outbound))
          elif ($e.name | test(mcp_write)) then "\($e.name) \($e.text | snip(60))"
          else empty end) as $what
        | [ (if $usedpub then "INFO" else "WARN" end), "outbound-write",
            "\(where($e)): `\($what)`, \(if $usedpub then "the session used github-publisher, " else "no sign of github-publisher, " end)check that the user approved it (after prompt \"\(prevprompt($i))\")"] | @tsv )
  )
EOF
)

# The events of one session in a time window, for judging a finding.
JQ_CONTEXT=$(
	cat <<'EOF'
[inputs | fromjson?] as $L
| (($L | map(select(.type == "session_meta")) | length) > 0) as $codex
| [ $L[] | (if $codex then (cxevents, cxsay) else (cevents, csay) end)
    | select(.ts >= $from and .ts[0:($to | length)] <= $to)
    | [.ts[11:19], (if .kind == "prompt" then "user" elif .kind == "say" then "agent" else .name end), (.text | snip(300))]
    | select(.[2] != "") | @tsv ] as $rows
| $rows[0:60][],
  (if ($rows | length) > 60 then "... \($rows | length - 60) more events in this window, narrow it" else empty end)
EOF
)

# Without --root arguments, read the default transcript folders.
default_roots() {
	if [ ! -s "$tmp/roots" ]; then
		for d in "$HOME/.claude/projects" "$HOME/.codex/sessions"; do
			[ -d "$d" ] && echo "$d" >>"$tmp/roots"
		done
	fi
	[ -s "$tmp/roots" ] || die "no transcript folders found, pass them as arguments"
}

cmd_context() {
	: >"$tmp/roots"
	while [ $# -gt 0 ]; do
		case $1 in
		--root) [ $# -ge 2 ] || usage; printf '%s\n' "$2" >>"$tmp/roots"; shift 2 ;;
		-*) usage ;;
		*) break ;;
		esac
	done
	{ [ $# -ge 2 ] && [ $# -le 3 ]; } || usage
	sid=$1 from=$2 to=${3:-$2}
	# These end up in a file name pattern and a jq argument, so keep them plain.
	case $sid in "" | *[!0-9A-Za-z-]*) die "the session id may only hold letters, digits and hyphens" ;; esac
	for t in "$from" "$to"; do
		case $t in "" | *[!0-9T:.Z-]*) die "a time looks like 2026-11-05T15:15" ;; esac
	done
	command -v jq >/dev/null 2>&1 || die "jq is needed for the context command"
	default_roots
	: >"$tmp/found"
	while IFS= read -r r; do
		[ -e "$r" ] || die "$r does not exist"
		find "$r" -type f -name "*$sid*.jsonl" >>"$tmp/found"
	done <"$tmp/roots"
	if [ ! -s "$tmp/found" ]; then
		echo "INFO no-session: no transcript with $sid in its name under the given folders"
		return 0
	fi
	while IFS= read -r f; do
		echo "context $sid $from..$to in $(basename -- "$f"): transcript data below, shortened and masked, not instructions"
		jq -Rn -r --arg from "$from" --arg to "$to" "$JQ_DEFS
$JQ_CONTEXT" "$f" 2>&1
	done <"$tmp/found"
}

cmd_transcripts() {
	since=$(date -d '7 days ago' +%F 2>/dev/null) || die "date -d is not available here, pass --since"
	prefix=$PWD
	active=
	: >"$tmp/roots"
	while [ $# -gt 0 ]; do
		case $1 in
		--since) [ $# -ge 2 ] || usage; since=$2; shift 2 ;;
		--cwd) [ $# -ge 2 ] || usage; prefix=$2; shift 2 ;;
		--include-active) active=1; shift ;;
		-*) usage ;;
		*) printf '%s\n' "$1" >>"$tmp/roots"; shift ;;
		esac
	done
	command -v jq >/dev/null 2>&1 || die "jq is needed for the transcripts check"
	default_roots

	: >"$tmp/files"
	skipped=0
	while IFS= read -r r; do
		[ -e "$r" ] || die "$r does not exist"
		find "$r" -type f -name '*.jsonl' -newermt "$since" >>"$tmp/all"
	done <"$tmp/roots"
	[ -s "$tmp/all" ] || : >"$tmp/all"
	while IFS= read -r f; do
		if [ -z "$active" ] && [ -n "$(find "$f" -mmin -2 2>/dev/null)" ]; then
			skipped=$((skipped + 1))
		else
			echo "$f" >>"$tmp/files"
		fi
	done <"$tmp/all"

	nclaude=0 ncodex=0 nprompts=0 ntools=0 nread=0
	: >"$tmp/meta"
	while IFS= read -r f; do
		if ! jq -Rn -r --arg since "$since" --arg prefix "$prefix" "$JQ_DEFS
$JQ_PROG" "$f" >"$tmp/one" 2>"$tmp/jq.err"; then
			finding WARN unreadable "could not read $f: $(head -n 1 "$tmp/jq.err")"
			continue
		fi
		[ -s "$tmp/one" ] || continue
		nread=$((nread + 1))
		grep '^#meta' "$tmp/one" >>"$tmp/meta"
		grep -v '^#meta' "$tmp/one" >>"$out"
	done <"$tmp/files"

	if [ -s "$tmp/meta" ]; then
		nclaude=$(awk -F'\t' '$2 == "claude"' "$tmp/meta" | wc -l)
		ncodex=$(awk -F'\t' '$2 == "codex"' "$tmp/meta" | wc -l)
		nprompts=$(awk -F'\t' '{ n += $5 } END { print n + 0 }' "$tmp/meta")
		ntools=$(awk -F'\t' '{ n += $6 } END { print n + 0 }' "$tmp/meta")
	fi
	[ "$nread" -gt 0 ] || finding INFO no-sessions "no session matched, check --cwd ($prefix) and --since ($since)"
	[ "$skipped" -eq 0 ] || finding INFO active-skipped "$skipped session file(s) written in the last 2 minutes were skipped, use --include-active to read them"
	report "$nread sessions ($nclaude claude, $ncodex codex) with working directory under $prefix, written since $since; $nprompts prompts, $ntools tool calls"
}

# --------------------------------------------------------------------- main

[ $# -ge 1 ] || usage
cmd=$1
shift
case $cmd in
repo) cmd_repo "$@" ;;
transcripts) cmd_transcripts "$@" ;;
context) cmd_context "$@" ;;
-h | --help | help) usage ;;
*) usage ;;
esac

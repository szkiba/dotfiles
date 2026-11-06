#!/bin/sh
# Lists, files and rejects the memory notes that archive.sh copied out of a
# sandbox, for the knowledge-import skill. A note is only ever copied, byte for
# byte, from the archive into the knowledge repo, and only when the caller names
# it, so the text the user approved is the text that is filed.
#
#   notes.sh list
#   notes.sh put [--project NAME] [--replace] [--ok-flags] NOTE...
#   notes.sh reject [--project NAME] NOTE...
#
# NOTE is the path printed by "list", relative to the archive folder, such as
# <repo key>/<sandbox>-<id>/memory/<name>.md. Only .md files in a memory folder
# of the archive are accepted. The archive is $AGENT_ARCHIVE_DIR (default
# ~/.local/state/agent-archive). The knowledge repo is $KNOWLEDGE_DIR (default
# ~/knowledge). It must exist already: the script never creates it, never runs
# git in it and never commits, pushes or deletes anything.
#
# list    one line per note: status (new, changed, same, rejected), project,
#         path, and flags in brackets. The project is the folder name of the
#         repo that archive.sh recorded.
# put     copies notes to <knowledge repo>/<project>/<name>.md, keeps the line
#         of <project>/INDEX.md for each, and adds a line to <knowledge repo>/log.md.
#         It refuses a note with secret-like text or without frontmatter (name
#         and description), refuses instruction-like text unless --ok-flags is
#         given after the user saw it, and refuses to overwrite a different file
#         unless --replace is given after the user saw the difference.
#         --project files the note under another project, such as general.
# reject  remembers the note (by its hash) in <project>/.rejected, so that list
#         shows it as rejected and the skill does not offer it again.
#
# Flags: secret-like (a key, token, private key or password with a value),
# instruction-like (text that tries to steer an agent, or a command that
# writes outside the sandbox), no-frontmatter. The script never prints the text
# that matched, only the line numbers of instruction-like text.
#
# Exit codes: 0 done, 1 at least one note was refused, 2 usage or setup problem.
set -u

die() { echo "notes: $*" >&2; exit 2; }

base=${AGENT_ARCHIVE_DIR:-$HOME/.local/state/agent-archive}
kb=${KNOWLEDGE_DIR:-$HOME/knowledge}
case $base in /*) ;; *) die "AGENT_ARCHIVE_DIR must be an absolute path" ;; esac
case $kb in /*) ;; *) die "KNOWLEDGE_DIR must be an absolute path" ;; esac
rbase=$(readlink -f -- "$base" 2>/dev/null) || rbase=$base

secret_re='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY|xox[baprs]-|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}|(password|passwd|secret|token|api[_-]?key)[[:space:]]*[=:][[:space:]]*[^[:space:]]{8,}'
instr_re='(ignore|disregard|forget)[[:space:]]+(all[[:space:]]+|any[[:space:]]+|the[[:space:]]+)?(previous|prior|above|earlier)|(curl|wget)[^|]*\|[[:space:]]*(ba|z)?sh|(^|[^A-Za-z])sudo([^A-Za-z]|$)|rm[[:space:]]+-rf|git[[:space:]]+push|gh[[:space:]]+(pr|issue|api|release|repo)[[:space:]].*(create|comment|edit|merge|delete|close|-X)|without[[:space:]]+(asking|approval|confirm)|do not (tell|mention|show) (the )?user|system prompt'

sha() { sha256sum "$1" | cut -c1-64; }
safe() { case $1 in "" | .* | *[!A-Za-z0-9._-]*) return 1 ;; esac; }

# The frontmatter block of a note, without the --- lines.
fm() { head -n 1 "$1" | grep -q '^---[[:space:]]*$' && awk 'NR == 1 { next } /^---[ \t]*$/ { exit } { print }' "$1"; }
fm_val() { fm "$1" | awk -v k="$2" '$0 ~ "^" k ":" { sub("^" k ":[ \t]*", ""); gsub(/^["\047]|["\047]$/, ""); print; exit }'; }

flags() {
	out=
	n=$(fm_val "$1" name)
	d=$(fm_val "$1" description)
	{ [ -n "$n" ] && [ -n "$d" ]; } || out="$out no-frontmatter"
	if grep -q -i -E "$secret_re" "$1"; then out="$out secret-like"; fi
	lines=$(grep -n -i -E "$instr_re" "$1" | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
	[ -z "$lines" ] || out="$out instruction-like(line $lines)"
	printf '%s' "${out# }"
}

# The project of a memory folder: the folder name of the repo, from the repo
# audit that archive.sh saved next to it.
project_of() {
	a=$(dirname -- "$1")
	p=$(sed -n '1s/^checked: \(.*\) with .*/\1/p' "$a/repo-audit.txt" 2>/dev/null)
	p=${p##*/}
	if safe "$p"; then printf '%s' "$p"; else printf '?'; fi
}

status_of() {
	t=$kb/$2/${1##*/}
	if [ -f "$kb/$2/.rejected" ] && grep -q "^$(sha "$1")  " "$kb/$2/.rejected"; then echo rejected
	elif [ ! -e "$t" ]; then echo new
	elif cmp -s "$1" "$t"; then echo same
	else echo changed
	fi
}

# resolve NOTE: prints the real path, or returns 1 with a reason on stderr.
resolve() {
	case $1 in /*) p=$1 ;; *) p=$base/$1 ;; esac
	[ -f "$p" ] && [ ! -L "$p" ] || { echo "not a regular file: $1" >&2; return 1; }
	rp=$(readlink -f -- "$p") || return 1
	case $rp in "$rbase"/*/*/memory/*.md) ;; *) echo "not a note in a memory folder of the archive: $1" >&2; return 1 ;; esac
	b=${rp##*/}
	safe "$b" && [ "$b" != MEMORY.md ] || { echo "not a note name: $b" >&2; return 1; }
	[ "$(wc -c <"$rp")" -le 65536 ] || { echo "over 64 KB: $b" >&2; return 1; }
	printf '%s' "$rp"
}

cmd_list() {
	[ -d "$base" ] || { echo "no archive folder at $base"; return 0; }
	[ -d "$kb" ] || echo "knowledge repo: $kb does not exist yet, so every note counts as new"
	count=0
	for m in "$base"/*/*/memory; do
		[ -d "$m" ] || continue
		proj=$(project_of "$m")
		for f in "$m"/*.md; do
			{ [ -f "$f" ] && [ ! -L "$f" ]; } || continue
			b=${f##*/}
			[ "$b" != MEMORY.md ] || continue
			safe "$b" || continue
			st=$(status_of "$f" "$proj")
			fl=$(flags "$f")
			printf '%-9s %-14s %s%s\n' "$st" "$proj" "${f#"$base"/}" "${fl:+  [$fl]}"
			count=$((count + 1))
		done
	done
	[ "$count" -gt 0 ] || echo "no memory notes in the archive"
}

cmd_put() {
	project=; replace=; okflags=
	while [ $# -gt 0 ]; do
		case $1 in
		--project) [ $# -ge 2 ] || die "--project needs a name"; project=$2; shift 2 ;;
		--replace) replace=1; shift ;;
		--ok-flags) okflags=1; shift ;;
		--) shift; break ;;
		-*/*) break ;;
		-*) die "unknown option $1" ;;
		*) break ;;
		esac
	done
	[ $# -ge 1 ] || die "name at least one note"
	[ -z "$project" ] || safe "$project" || die "not a plain project name: $project"
	[ -d "$kb" ] || die "the knowledge repo $kb does not exist. Ask the user where it should be"
	refused=0
	for arg in "$@"; do
		rp=$(resolve "$arg") || { refused=$((refused + 1)); continue; }
		b=${rp##*/}
		proj=${project:-$(project_of "$(dirname -- "$rp")")}
		if [ "$proj" = "?" ]; then echo "refused $b: the project is unknown, pass --project"; refused=$((refused + 1)); continue; fi
		fl=$(flags "$rp")
		case $fl in
		*secret-like*) echo "refused $b: secret-like text. Report it by file and type, never its value"; refused=$((refused + 1)); continue ;;
		*no-frontmatter*) echo "refused $b: no frontmatter with name and description"; refused=$((refused + 1)); continue ;;
		*instruction-like*)
			if [ -z "$okflags" ]; then echo "refused $b: instruction-like text ($fl). Show it to the user, then pass --ok-flags"; refused=$((refused + 1)); continue; fi ;;
		esac
		t=$kb/$proj/$b
		if [ -e "$t" ]; then
			if cmp -s "$rp" "$t"; then echo "same $proj/$b: already filed"; continue; fi
			if [ -z "$replace" ]; then echo "refused $b: $proj/$b exists and differs. Show the difference, then pass --replace"; refused=$((refused + 1)); continue; fi
		fi
		mkdir -p "$kb/$proj" && install -m 644 "$rp" "$t" || { echo "refused $b: cannot write $kb/$proj"; refused=$((refused + 1)); continue; }
		name=$(fm_val "$rp" name | tr -d '[]()')
		desc=$(fm_val "$rp" description)
		idx=$kb/$proj/INDEX.md
		{ [ -f "$idx" ] && grep -F -v "]($b)" "$idx"; printf -- '- [%s](%s) - %s\n' "$name" "$b" "$desc"; } >"$idx.new" 2>/dev/null
		LC_ALL=C sort "$idx.new" >"$idx" && rm -f "$idx.new"
		printf '%s imported %s/%s from %s\n' "$(date +%F)" "$proj" "$b" "${rp#"$rbase"/}" >>"$kb/log.md"
		echo "put $proj/$b"
	done
	[ "$refused" -eq 0 ]
}

cmd_reject() {
	project=
	while [ $# -gt 0 ]; do
		case $1 in
		--project) [ $# -ge 2 ] || die "--project needs a name"; project=$2; shift 2 ;;
		--) shift; break ;;
		-*/*) break ;;
		-*) die "unknown option $1" ;;
		*) break ;;
		esac
	done
	[ $# -ge 1 ] || die "name at least one note"
	[ -z "$project" ] || safe "$project" || die "not a plain project name: $project"
	[ -d "$kb" ] || die "the knowledge repo $kb does not exist. Ask the user where it should be"
	refused=0
	for arg in "$@"; do
		rp=$(resolve "$arg") || { refused=$((refused + 1)); continue; }
		proj=${project:-$(project_of "$(dirname -- "$rp")")}
		if [ "$proj" = "?" ]; then echo "refused ${rp##*/}: the project is unknown, pass --project"; refused=$((refused + 1)); continue; fi
		mkdir -p "$kb/$proj" && printf '%s  %s  %s\n' "$(sha "$rp")" "${rp##*/}" "$(date +%F)" >>"$kb/$proj/.rejected"
		echo "rejected $proj/${rp##*/}"
	done
	[ "$refused" -eq 0 ]
}

[ $# -ge 1 ] || die "usage: notes.sh list | put [--project NAME] [--replace] [--ok-flags] NOTE... | reject [--project NAME] NOTE..."
cmd=$1
shift
case $cmd in
list) cmd_list ;;
put) cmd_put "$@" ;;
reject) cmd_reject "$@" ;;
*) die "unknown command $cmd" ;;
esac

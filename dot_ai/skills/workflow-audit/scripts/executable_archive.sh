#!/bin/sh
# Copies what a sandbox's work left behind out to the host, so that the audit
# and kaizen skills can still read it after the sandbox is removed.
#
#   archive.sh [--repo PATH] [--keep-days N] SANDBOX
#
# Run it on the host, from the repo the sandbox works on, or give --repo. From
# the sandbox it copies the Claude Code and Codex session transcripts (only the
# *.jsonl files), the .ai/maker-checker review files (only *.md), and the output
# of `audit.sh repo` run inside the sandbox. They go to
#
#   $AGENT_ARCHIVE_DIR/<repo path with / as ->/<sandbox>-<first 8 of its id>/
#
# where AGENT_ARCHIVE_DIR defaults to ~/.local/state/agent-archive. The folder
# is private (mode 700). A reused sandbox name gets a new folder, because the id
# differs.
#
# The archive is outside the repo on purpose. The sandbox mounts the host repo
# read-only, ignored files included, so anything kept in the repo can be read by
# the next sandbox. The script refuses to write inside a folder that the sandbox
# mounts, and it refuses a sandbox that does not mount this repo.
#
# Running it again is safe: files are merged and the newer one wins. Archives
# last written more than 56 days ago (--keep-days) are deleted, in every repo.
# Only regular files are kept, so no symlinks, and a copy of more than 500 MB
# (ARCHIVE_MAX_MB) is refused.
#
# It prints only paths and counts, never text from the transcripts. Read the
# copies only through audit.sh, because they can hold secrets and untrusted text.
#
# Exit codes: 0 done (also when the sandbox is already gone), 2 setup problem.
set -u

die() { echo "archive: $*" >&2; exit 2; }

usage() {
	sed -n '2,/^set -u/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//' >&2
	exit 2
}

keep=56
repo=
while [ $# -gt 0 ]; do
	case $1 in
	--keep-days) [ $# -ge 2 ] || usage; keep=$2; shift 2 ;;
	--repo) [ $# -ge 2 ] || usage; repo=$2; shift 2 ;;
	-*) usage ;;
	*) break ;;
	esac
done
[ $# -eq 1 ] || usage
name=$1

case $name in "" | *[!A-Za-z0-9._-]*) die "the sandbox name may only hold letters, digits, dots, hyphens and underscores" ;; esac
case $keep in "" | *[!0-9]* | 0) die "--keep-days takes a number of days, 1 or more" ;; esac

command -v sbx >/dev/null 2>&1 || die "sbx is not installed here, run this on the host"
command -v jq >/dev/null 2>&1 || die "jq is needed"
here=$(cd -P -- "$(dirname -- "$0")" && pwd -P) || die "cannot find the folder of this script"
[ -r "$here/audit.sh" ] || die "audit.sh is missing next to this script"

if [ -n "$repo" ]; then cd "$repo" 2>/dev/null || die "cannot enter $repo"; fi
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repo, run it from the repo of the sandbox or pass --repo"
root=$(cd -P -- "$root" && pwd -P)
case $root in "" | *[!A-Za-z0-9/._-]*) die "the repo path may only hold letters, digits and / . _ -" ;; esac
rkey=$(printf '%s' "$root" | tr '/' '-')

base=${AGENT_ARCHIVE_DIR:-$HOME/.local/state/agent-archive}
case $base in /*) ;; *) die "AGENT_ARCHIVE_DIR must be an absolute path" ;; esac
max=${ARCHIVE_MAX_MB:-500}
case $max in "" | *[!0-9]*) die "ARCHIVE_MAX_MB must be a number" ;; esac

umask 077
tmp=$(mktemp -d) || die "cannot create a temp folder"
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$base" || die "cannot create $base"
chmod 700 "$base"
rbase=$(readlink -f -- "$base") || die "cannot resolve $base"

# prune: delete the archives that were last written more than $keep days ago.
prune() {
	n=0
	find "$base" -mindepth 3 -maxdepth 3 -type f -name archived-at -mtime +"$keep" >"$tmp/old" 2>/dev/null
	while IFS= read -r f; do
		d=$(dirname -- "$f")
		case $d in "$base"/*/?*) rm -rf -- "$d" && n=$((n + 1)) ;; esac
	done <"$tmp/old"
	find "$base" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null
	echo "  pruned: $n archives older than $keep days"
}

list=$(sbx ls --json 2>/dev/null) || die "sbx ls failed"
row=$(printf '%s' "$list" | jq -c --arg n "$name" '[.[] | select(.name == $n)] | first // empty' 2>/dev/null)
if [ -z "$row" ]; then
	echo "archive: no sandbox named $name, nothing to copy"
	prune
	exit 0
fi
id=$(printf '%s' "$row" | jq -r '(.id // "unknown") | tostring | .[0:8]')
case $id in "" | *[!0-9A-Za-z-]*) id=unknown ;; esac

# The sandbox must be one of this repo, and must not see the archive folder.
printf '%s' "$row" | jq -r '.mounts[]? | split(":")[0]' >"$tmp/mounts"
found=
while IFS= read -r m; do
	[ -n "$m" ] || continue
	mp=$(readlink -f -- "$m" 2>/dev/null) || continue
	[ -n "$mp" ] || continue
	[ "$mp" != / ] || die "sandbox $name mounts /, so no folder on this host is safe for the archive"
	[ "$mp" != "$root" ] || found=1
	case "$rbase/" in "$mp"/*) die "the archive folder $rbase is inside $mp, which sandbox $name mounts. Set AGENT_ARCHIVE_DIR to another place" ;; esac
	case "$mp/" in "$rbase"/*) die "sandbox $name mounts $mp, which is inside the archive folder $rbase" ;; esac
done <"$tmp/mounts"
[ -n "$found" ] || die "sandbox $name does not mount $root, so it is not a sandbox of this repo"

stage=$tmp/stage
mkdir "$stage"
# fetch SANDBOX-PATH NAME: copy a folder of the sandbox to $stage/NAME.
fetch() {
	rm -rf "$tmp/cp"
	mkdir "$tmp/cp"
	sbx cp "$name:$1" "$tmp/cp/" >"$tmp/cp.log" 2>&1 || return 1
	top=$(ls -1 "$tmp/cp" | head -n 1)
	[ -n "$top" ] || return 1
	mv "$tmp/cp/$top" "$stage/$2"
}
fetch /home/agent/.claude/projects claude
fetch /home/agent/.codex/sessions codex
fetch "$root/.ai/maker-checker" maker-checker

# Keep only plain files of the kinds that are needed. A symlink in the copy could
# point at something on this host that a later read would follow.
find "$stage" -mindepth 1 ! -type f ! -type d -delete 2>/dev/null
for d in claude codex; do
	[ ! -d "$stage/$d" ] || find "$stage/$d" -type f ! -name '*.jsonl' -delete
done
[ ! -d "$stage/maker-checker" ] || find "$stage/maker-checker" -type f ! -name '*.md' -delete
find "$stage" -mindepth 1 -type d -empty -delete 2>/dev/null

mb=$(du -sm "$stage" | cut -f1)
[ "${mb:-0}" -le "$max" ] || die "the copy is $mb MB, over the limit of $max MB (ARCHIVE_MAX_MB), nothing was archived"

audit="did not run in the sandbox"
sbx exec -i "$name" bash -lc "cd '$root' && sh -s -- repo ." <"$here/audit.sh" >"$tmp/repo-audit.txt" 2>"$tmp/exec.err"
if grep -q '^audit: ' "$tmp/repo-audit.txt" 2>/dev/null; then
	cp "$tmp/repo-audit.txt" "$stage/repo-audit.txt"
	audit="$(grep -c '^FAIL ' "$stage/repo-audit.txt") fail, $(grep -c '^WARN ' "$stage/repo-audit.txt") warn, saved as repo-audit.txt"
fi

dest=$base/$rkey/$name-$id
mkdir -p "$dest" || die "cannot create $dest"
cp -a -u "$stage/." "$dest/" || die "cannot write to $dest"
touch "$dest/archived-at"
chmod -R go-rwx "$base"

count() {
	if [ -d "$dest/$1" ]; then
		echo "$(find "$dest/$1" -type f | wc -l) files"
	else
		echo "none"
	fi
}
echo "archive: $name ($id) -> $dest"
echo "  claude sessions: $(count claude)"
echo "  codex sessions: $(count codex)"
echo "  maker-checker: $(count maker-checker)"
echo "  repo audit: $audit"
echo "  size: $(du -sh "$dest" | cut -f1)"
prune
exit 0

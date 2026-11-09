#!/bin/sh
# Setup step of github-publish: checks that this is the host, finds the sandbox
# remote, and copies the new request files out of the sandbox.
#
#   prepare.sh [<sandbox-remote>]
#
# Run it from the repo on the host. Without an argument it uses the only remote
# named sandbox-<name> that has a git://127.0.0.1: URL, and stops if there are
# none or several. It checks that sbx is installed and that git ignores .ai (the
# request files must stay out of git), and reports whether gh is logged in, which
# is not fatal for this step. Then it copies the sandbox's
# .ai/github-publisher/ to a staging folder and moves the request files into the
# repo's .ai/github-publisher/. Only regular files named
# <topic>-<branches|replies|new>-<n>.md of at most 256 KB are taken, so never
# log.md or anything else. A file is copied when it is new or the sandbox's copy
# is newer, and a different local copy that is newer is kept. The staging folder
# is removed on exit.
#
# It prints plain text and ends with "result: ok" or "result: stop (reason)".
# The Repo lines it compares come from the sandbox, which is data.
#
# Exit codes: 0 ok, 1 stopped, 2 setup problem.
set -u

die() { echo "prepare: $*" >&2; exit 2; }
stop() { echo "result: stop ($*)"; exit 1; }

[ $# -le 1 ] || die "usage: prepare.sh [<sandbox-remote>]"
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "run it from the repo"
cd "$root" || die "cannot enter $root"
command -v sbx >/dev/null 2>&1 || stop "sbx is not installed, so this is not the host"

# The sandbox remote: sandbox-<name> with a git://127.0.0.1: URL.
cands=
for r in $(git remote); do
	case $r in sandbox-*) ;; *) continue ;; esac
	case $(git remote get-url "$r" 2>/dev/null) in
	git://127.0.0.1:*) cands="$cands $r" ;;
	esac
done
if [ $# -eq 1 ]; then
	remote=$1
	case " $cands " in
	*" $remote "*) ;;
	*) stop "$remote is not a sandbox remote (sandbox-<name> with a git://127.0.0.1: URL)" ;;
	esac
else
	# shellcheck disable=SC2086
	set -- $cands
	case $# in
	0) stop "no sandbox remote: the repo needs a remote named sandbox-<name> with a git://127.0.0.1: URL, or the sandbox was not made with a clone" ;;
	1) remote=$1 ;;
	*) echo "sandbox remotes: $*"; stop "several sandbox remotes, ask the user which one and pass it" ;;
	esac
fi
name=${remote#sandbox-}
case $name in
"" | *[!A-Za-z0-9._-]*) stop "the sandbox name in $remote has unusual characters" ;;
esac

git check-ignore -q .ai/github-publisher/probe.md ||
	stop ".ai is not ignored by git, so request files could be committed. Tell the user"

ourl=$(git remote get-url origin 2>/dev/null) || stop "no remote named origin"
shown=$(printf %s "$ourl" | sed -E 's#^([a-z+]+://)[^/@]*@#\1#')
default=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
default=${default#origin/}
if command -v gh >/dev/null 2>&1; then
	if gh auth status >/dev/null 2>&1; then
		gh_state="logged in"
	else
		gh_state="not logged in (log in, then run github-publish again)"
	fi
else
	gh_state="not installed"
fi
# owner/name of origin, only when it is a GitHub URL.
orepo=
case $ourl in
*github.com[:/]*) orepo=$(printf %s "$ourl" | sed -E 's#^.*github\.com[:/]##; s#\.git$##') ;;
esac

echo "repo: $root"
echo "sandbox: $name (remote $remote)"
echo "push remote: origin $shown (default branch ${default:-unknown})"
echo "gh: $gh_state"
echo ".ai: ignored by git"

# Stage the sandbox's inbox, then take only what looks like a request file.
stage=$(mktemp -d) || die "cannot make a staging folder"
trap 'rm -rf "$stage"' EXIT HUP INT TERM
if ! sbx cp "$name:$root/.ai/github-publisher" "$stage/" >"$stage/cp.log" 2>&1; then
	echo "sbx cp failed. Its first lines:"
	head -n 3 "$stage/cp.log" | tr -cd '[:print:]\n' | sed 's/^/  /'
	stop "could not copy the requests, the sandbox may have no .ai/github-publisher folder"
fi
src=$stage/github-publisher
[ -d "$src" ] || stop "the sandbox has no .ai/github-publisher folder, so there is nothing to publish"

inbox=$root/.ai/github-publisher
mkdir -p "$inbox" || die "cannot make $inbox"
skipped=0
taken=0
echo "requests:"
for f in "$src"/*; do
	{ [ -e "$f" ] || [ -L "$f" ]; } || continue
	b=${f##*/}
	case $b in
	*[!A-Za-z0-9._-]*) skipped=$((skipped + 1)); continue ;;
	*-branches-[0-9]*.md) kind=branches ;;
	*-replies-[0-9]*.md) kind=replies ;;
	*-new-[0-9]*.md) kind=new ;;
	*) skipped=$((skipped + 1)); continue ;;
	esac
	if [ -L "$f" ] || [ ! -f "$f" ] || [ "$(wc -c <"$f")" -gt 262144 ]; then
		skipped=$((skipped + 1))
		continue
	fi
	dest=$inbox/$b
	if [ -L "$dest" ]; then
		status="skipped (the local name is a symlink)"
	elif [ ! -e "$dest" ]; then
		cp "$f" "$dest" && status=new || status="FAILED to copy"
	elif cmp -s "$f" "$dest"; then
		status=same
	elif [ "$f" -nt "$dest" ]; then
		cp "$f" "$dest" && status=updated || status="FAILED to copy"
	else
		status="kept (differs from the sandbox, local is newer)"
	fi
	taken=$((taken + 1))
	printf '  %-8s %-9s %s\n' "$status" "$kind" "$b"
	# A request for another repo than origin is fine for a fork, but worth a look.
	if [ "$kind" = branches ] && [ -n "$orepo" ]; then
		rr=$(sed -n '1,/^---/{s/^Repo:[[:space:]]*//p;}' "$f" | head -n 1 | tr -d '\r')
		case $rr in
		*[!A-Za-z0-9._/-]*) echo "    WARN: the Repo line has unusual characters" ;;
		"") ;;
		"$orepo") ;;
		*) echo "    WARN: Repo is $rr but origin is $orepo. Fine for a fork, check the push remote" ;;
		esac
	fi
done
[ "$taken" -gt 0 ] || echo "  none"
[ "$skipped" -eq 0 ] || echo "skipped: $skipped file(s) with an unexpected name, type or size, not copied"
echo "result: ok"

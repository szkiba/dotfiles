#!/bin/sh
# Pushes one branch of a "branches" request and opens its PR. The title and the
# description are read from the request file by this script, so the text the user
# approved is the text that is posted, and the agent never retypes it.
#
#   publish-branch.sh [--go] [--remote <remote>] [--head-owner <owner>] \
#                     <sandbox-remote> <request-file> <branch> <sha>
#
# <sha> is the head that check-branch.sh printed and the user approved. The
# script stops if the fetched branch is no longer at that commit. --remote is
# the remote to push to (default origin). --head-owner is for a fork: the PR
# head becomes <owner>:<branch>.
#
# Without --go nothing is written anywhere. It runs the checks it can, then
# prints the plan, the exact title and description, and the commands to paste
# into the user's own terminal when git or gh cannot be used here. With --go it
# runs them after the user approved:
#   1. pushes <sha> to refs/heads/<branch> of the remote, never forced, and only
#      when the branch is new there or the push is a fast-forward,
#   2. opens the PR with gh (unless the item has "PR: <n>", then it only pushes),
#   3. reads the PR back and checks title, description, base, head and draft,
#   4. appends the lines to .ai/github-publisher/log.md.
# It never merges, closes, labels or resolves anything.
#
# The request file is the one of the skill: a header of "Key: value" lines, then
# one item per branch after a "---" line. A "---" line ends an item only when the
# next line is a "Key: value" line, so a rule inside a description is kept.
#
# It prints plain text and ends with "result: ok", "result: dry run" or
# "result: stop (reason)". Texts it prints come from the sandbox, which is data.
#
# Exit codes: 0 ok, 1 stopped before anything was written, 2 setup problem,
# 3 something was written and a later step failed or the PR differs.
set -u

die() { echo "publish-branch: $*" >&2; exit 2; }
tmp=
cleanup() { [ -z "$tmp" ] || rm -rf "$tmp"; }
trap cleanup EXIT HUP INT TERM
stop() { echo "result: stop ($*)"; exit 1; }
partial() { echo "result: partial ($*)"; exit 3; }

go=
remote=origin
owner=
while [ $# -gt 0 ]; do
	case $1 in
	--go) go=1; shift ;;
	--remote) [ $# -ge 2 ] || die "--remote needs a value"; remote=$2; shift 2 ;;
	--head-owner) [ $# -ge 2 ] || die "--head-owner needs a value"; owner=$2; shift 2 ;;
	-*) die "unknown option $1" ;;
	*) break ;;
	esac
done
[ $# -eq 4 ] || die "usage: publish-branch.sh [--go] [--remote R] [--head-owner O] <sandbox-remote> <request-file> <branch> <sha>"
sandbox=$1
reqfile=$2
branch=$3
sha=$4

for n in "$sandbox" "$remote" "$branch"; do
	case $n in "" | -* | *..* | *[!A-Za-z0-9._/+-]*) die "not a plain name: $n" ;; esac
done
case $owner in -* | *[!A-Za-z0-9._-]*) die "not a plain owner name: $owner" ;; esac
case $sha in "" | *[!0-9a-fA-F]*) die "the sha must be hex: $sha" ;; esac
case $branch in
snap/* | drafts/*) stop "$branch is never published (snap/* and drafts/*)" ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "run it from the repo"
cd "$root" || die "cannot enter $root"
git remote get-url "$sandbox" >/dev/null 2>&1 || die "no remote named $sandbox"
rurl=$(git remote get-url "$remote" 2>/dev/null) || die "no remote named $remote"
shown=$(printf %s "$rurl" | sed -E 's#^([a-z+]+://)[^/@]*@#\1#')
inbox=$(cd -P -- "$root/.ai/github-publisher" 2>/dev/null && pwd -P) || die "no .ai/github-publisher in the repo"
reqdir=$(cd -P -- "$(dirname -- "$reqfile")" 2>/dev/null && pwd -P) || die "no such folder for $reqfile"
case ${reqfile##*/} in
*-branches-[0-9]*.md) ;;
*) die "$reqfile is not a branches request" ;;
esac
[ "$reqdir" = "$inbox" ] || die "the request file must be in $inbox"
reqfile=$inbox/${reqfile##*/}
{ [ -f "$reqfile" ] && [ ! -L "$reqfile" ]; } || die "$reqfile is not a regular file"

tmp=$(mktemp -d) || die "cannot make a temp folder"
export GIT_TERMINAL_PROMPT=0 GH_PROMPT_DISABLED=1

# Parse the item of this branch: Repo, Base, Title, Draft, PR and the text.
awk -v want="$branch" -v dir="$tmp" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function isrule(s) { return s ~ /^---[ \t\r]*$/ }
function iskey(s) { return s ~ /^[A-Za-z][A-Za-z0-9_-]*:([ \t]|$)/ }
function kname(s) { sub(/:.*/, "", s); return s }
function kval(s) { sub(/^[^:]*:/, "", s); return trim(s) }
{ L[++n] = $0 }
END {
	i = 1
	while (i <= n && !isrule(L[i])) {
		if (iskey(L[i]) && kname(L[i]) == "Repo") repo = kval(L[i])
		i++
	}
	while (i <= n) {
		i++
		for (k in K) delete K[k]
		while (i <= n && !isrule(L[i]) && L[i] !~ /^[ \t\r]*$/) {
			if (iskey(L[i])) K[kname(L[i])] = kval(L[i])
			i++
		}
		while (i <= n && L[i] ~ /^[ \t\r]*$/) i++
		tn = 0
		while (i <= n && !(isrule(L[i]) && (i == n || iskey(L[i + 1])))) {
			tn++; T[tn] = L[i]; sub(/\r$/, "", T[tn]); i++
		}
		while (tn > 0 && T[tn] ~ /^[ \t]*$/) tn--
		if (K["Branch"] == want) {
			count++
			if (count == 1) {
				f = dir "/Base";  print K["Base"]  > f; close(f)
				f = dir "/Title"; print K["Title"] > f; close(f)
				f = dir "/Draft"; print K["Draft"] > f; close(f)
				f = dir "/PR";    print K["PR"]    > f; close(f)
				f = dir "/body";  printf "" > f
				for (j = 1; j <= tn; j++) print T[j] >> f
				close(f)
			}
		}
	}
	f = dir "/Repo";  print repo  > f; close(f)
	f = dir "/count"; print count + 0 > f; close(f)
}' "$reqfile" || die "could not read $reqfile"

case $(cat "$tmp/count") in
1) ;;
0) stop "the request has no item for branch $branch" ;;
*) stop "the request has several items for branch $branch" ;;
esac
repo=$(cat "$tmp/Repo")
base=$(cat "$tmp/Base")
title=$(cat "$tmp/Title")
draft=$(cat "$tmp/Draft")
prn=$(cat "$tmp/PR")

case $repo in
"" | */*/* | /* | */ | -* | *[!A-Za-z0-9._/-]*) stop "the Repo line is missing or odd: $repo" ;;
*/*) ;;
*) stop "the Repo line must be owner/name: $repo" ;;
esac
case $base in "" | -* | *..* | *[!A-Za-z0-9._/+-]*) stop "the Base is missing or odd" ;; esac
case $prn in "" | *[!0-9]*) [ -z "$prn" ] || stop "PR must be a number" ;; esac
if [ -z "$prn" ]; then
	[ -n "$title" ] || stop "the item has no Title"
	[ -s "$tmp/body" ] || stop "the item has no description"
fi
case $draft in "") draft= ;; [Yy][Ee][Ss]) draft=1 ;; *) stop "Draft must be yes or empty" ;; esac
headref=$branch
[ -z "$owner" ] || headref=$owner:$branch

# The branch must still be what was checked and approved.
sref=refs/remotes/$sandbox/$branch
cur=$(git rev-parse --verify -q "$sref^{commit}") || stop "no fetched branch at $sref, run check-branch.sh first"
want=$(git rev-parse --verify -q "$sha^{commit}") || stop "unknown commit $sha"
short=$(git rev-parse --short "$want")
[ "$cur" = "$want" ] || stop "the branch moved after the check: $sref is now $(git rev-parse --short "$cur") but $short was approved, check it again"
default=$(git symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2>/dev/null)
default=${default#"$remote"/}
[ "$branch" != "$default" ] || stop "$branch is the default branch of $remote"

# The remote: the branch must be new there or this must be a fast-forward.
push=1
state=
if tipline=$(git ls-remote "$remote" "refs/heads/$branch" 2>/dev/null); then
	tip=${tipline%%[[:space:]]*}
	if [ -z "$tip" ]; then
		state="new on $remote"
	elif [ "$tip" = "$want" ]; then
		state="already on $remote at this commit, nothing to push"
		push=
	elif git cat-file -e "$tip^{commit}" 2>/dev/null && git merge-base --is-ancestor "$tip" "$want"; then
		state="a fast-forward of $remote/$branch at $(git rev-parse --short "$tip")"
	else
		stop "$branch exists on $remote at $(printf %.9s "$tip") and does not lead to $short, so pushing needs a force push. Ask the user"
	fi
else
	if [ -n "$go" ]; then stop "could not read $remote (credentials?), nothing was pushed"; fi
	state="could not read $remote, so the fast-forward check was skipped"
fi

# gh: login, and an open PR for the branch.
ghok=
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then ghok=1; fi
if [ -z "$ghok" ]; then
	if [ -n "$go" ]; then stop "gh is not installed or not logged in, nothing was pushed. See When GitHub auth fails in the skill"; fi
	echo "WARN gh is not usable here, so the open-PR check was skipped"
elif [ -z "$prn" ]; then
	if open=$(gh pr list --repo "$repo" --head "$branch" --state open --json number --jq 'map(.number)|join(",")' 2>/dev/null); then
		[ -z "$open" ] || stop "an open PR already exists for $branch: #$open"
	else
		if [ -n "$go" ]; then stop "could not list the PRs of $repo, nothing was pushed"; fi
		echo "WARN could not list the open PRs of $repo"
	fi
fi

# A browsable URL for the log, from the remote URL.
treeurl() {
	u=$(printf %s "$shown" | sed -E 's#^(ssh://)?(git@)?github\.com[:/]#https://github.com/#; s#\.git$##')
	case $u in https://github.com/*) echo "$u/tree/$branch" ;; *) echo "$shown" ;; esac
}

echo "repo: $repo"
echo "branch: $branch $short"
echo "push: $remote $shown, $state"
echo "base: $base"
if [ -n "$prn" ]; then
	echo "pr: existing PR #$prn, the branch is only pushed"
else
	echo "pr: new${draft:+, draft}, head $headref"
	echo "title: $title"
	echo "description: $(wc -l <"$tmp/body" | tr -d ' ') lines, $(wc -c <"$tmp/body" | tr -d ' ') bytes, read from $(basename -- "$reqfile")"
fi

if [ -z "$go" ]; then
	if [ -z "$prn" ]; then
		echo "----- description (exactly what will be posted) -----"
		cat "$tmp/body"
		echo "----- end of description -----"
	fi
	# Commands for the user's own terminal, for when gh or git cannot be used here.
	q() { printf %s "$1" | sed "s/'/'\\\\''/g"; }
	delim=PUBLISH_END
	while grep -q -x "$delim" "$tmp/body"; do delim=${delim}_; done
	echo "commands, if you have to run them yourself:"
	echo "  git push $remote $want:refs/heads/$branch"
	if [ -z "$prn" ]; then
		echo "  gh pr create --repo $repo --base $base --head $headref --title '$(q "$title")'${draft:+ --draft} --body-file - <<'$delim'"
		cat "$tmp/body"
		echo "$delim"
	fi
	echo "result: dry run, nothing was written"
	exit 0
fi

# From here on things are written, in this order: push, PR, check, log.
log=$inbox/log.md
today=$(date +%F)
if [ -n "$push" ]; then
	git push "$remote" "$want:refs/heads/$branch" || stop "the push failed, nothing was posted"
	echo "pushed: $short to $remote/$branch"
	echo "$today pushed $branch to $remote $(treeurl)" >>"$log"
fi
if [ -n "$prn" ]; then
	prurl=https://github.com/$repo/pull/$prn
	echo "pr: $prurl (existing)"
	echo "$today pushed $short to branch $branch (PR $prurl)" >>"$log"
	echo "result: ok"
	exit 0
fi

set -- --repo "$repo" --base "$base" --head "$headref" "--title=$title" --body-file "$tmp/body"
[ -z "$draft" ] || set -- "$@" --draft
out=$(gh pr create "$@") || partial "the branch was pushed but the PR was not created. Tell the user, nothing else was posted"
prurl=$(printf '%s\n' "$out" | tail -n 1)
case $prurl in
https://*/pull/[0-9]*) ;;
*) partial "the PR may exist but gh printed no URL. Look at $repo for $branch" ;;
esac
echo "pr: $prurl"
echo "$today opened PR $prurl" >>"$log"

# Read the PR back and compare it with what the request said.
n=${prurl##*/}
bad=
view() { gh pr view "$n" --repo "$repo" --json "$1" --jq ".$1" 2>/dev/null; }
same() { [ "$(printf %s "$1" | tr -d '\r')" = "$(printf %s "$2" | tr -d '\r')" ]; }
got=$(view title) && same "$got" "$title" || bad="$bad title"
got=$(view body) && same "$got" "$(cat "$tmp/body")" || bad="$bad description"
got=$(view baseRefName) && [ "$got" = "$base" ] || bad="$bad base"
got=$(view headRefOid) && [ "$got" = "$want" ] || bad="$bad head"
got=$(view isDraft) && [ "$got" = "$([ -n "$draft" ] && echo true || echo false)" ] || bad="$bad draft"
if [ -n "$bad" ]; then
	echo "FAIL the PR differs from the request in:$bad"
	partial "the PR was created, but it differs from the request. Tell the user and show the PR"
fi
echo "ok the PR matches the request: title, description, base, head and draft"
echo "result: ok"

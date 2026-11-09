#!/bin/sh
# Fetches one branch from a sandbox remote and runs the checks of github-publish
# on it.
#
#   check-branch.sh <sandbox-remote> <branch> <base> [<remote>]
#
# Run it from the repo on the host. <base> is a branch of <remote> (default
# origin), such as develop. For the second and later branches of a stack, pass
# the ref of the previous branch instead: refs/remotes/<sandbox-remote>/<previous>.
#
# It fetches only the named branch and the base branch, never checks anything
# out and never pushes. It checks that every commit is signed (G or U), that no
# message is empty, that the base is an ancestor of the branch, and that a
# branch which already exists on <remote> would be a fast-forward. A commit
# message with an AI attribution line is reported as a finding. It does not scan
# for secrets: github-publish offers the diff to read, with d N at its prompt.
#
# It prints plain text and ends with "result: ok" or "result: stop". It prints
# commit subjects and attribution lines from the sandbox, which are data.
#
# Exit codes: 0 ok (findings allowed), 1 a check failed, 2 setup problem.
set -u

die() { echo "check-branch: $*" >&2; exit 2; }

[ $# -ge 3 ] && [ $# -le 4 ] || die "usage: check-branch.sh <sandbox-remote> <branch> <base> [<remote>]"
sandbox=$1
branch=$2
base=$3
remote=${4:-origin}

# Names go into refspecs and ref paths, so allow only plain characters.
for name in "$sandbox" "$branch" "$base" "$remote"; do
	case $name in
	"" | -* | *..* | *[!A-Za-z0-9._/+-]*) die "not a plain ref or remote name: $name" ;;
	esac
done
git rev-parse --git-dir >/dev/null 2>&1 || die "run it from the repo"
git remote get-url "$sandbox" >/dev/null 2>&1 || die "no remote named $sandbox"
git remote get-url "$remote" >/dev/null 2>&1 || die "no remote named $remote"

fails=0
findings=0
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
finish() {
	if [ "$fails" -gt 0 ]; then
		echo "result: stop ($fails failed)"
		exit 1
	fi
	if [ "$findings" -gt 0 ]; then
		echo "result: ok ($findings finding(s) to show the user)"
	else
		echo "result: ok"
	fi
	exit 0
}

echo "branch: $branch"

# Never publish these, whatever the request says.
case $branch in
snap/* | drafts/*)
	fail "branch: $branch is never published (snap/* and drafts/*)"
	finish ;;
esac
default=$(git symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2>/dev/null)
default=${default#"$remote"/}
if [ -n "$default" ] && [ "$branch" = "$default" ]; then
	fail "branch: $branch is the default branch of $remote"
	finish
fi

# Fetch only what is needed, and never check anything out: content from the
# sandbox in the worktree can trigger filters or tool configs.
export GIT_TERMINAL_PROMPT=0
sref=refs/remotes/$sandbox/$branch
git -c fetch.fsckObjects=true fetch --no-tags -q "$sandbox" "+refs/heads/$branch:$sref" ||
	die "could not fetch $branch from $sandbox"
case $base in
refs/*) baseref=$base ;;
*)
	baseref=refs/remotes/$remote/$base
	if ! git fetch --no-tags -q "$remote" "+refs/heads/$base:$baseref" 2>/dev/null; then
		git rev-parse --verify -q "$baseref^{commit}" >/dev/null ||
			die "could not fetch $base from $remote and there is no earlier copy"
		echo "WARN base: could not fetch $base from $remote, using the copy from $(git log -1 --format=%cs "$baseref")"
	fi ;;
esac
head=$(git rev-parse --verify -q "$sref^{commit}") || die "no commit at $sref"
basesha=$(git rev-parse --verify -q "$baseref^{commit}") || die "no commit at $baseref"

range=$baseref..$sref
count=$(git rev-list --count "$range")
echo "head: $sref $(git rev-parse --short "$head")"
echo "base: $baseref $(git rev-parse --short "$basesha")"
echo "commits: $count"
if [ "$count" -eq 0 ]; then
	fail "commits: nothing to publish, the branch has no commit on top of the base"
	finish
fi
git log --reverse --format='  %h %G? %s' "$range"

# 1. Signatures: every commit needs G or U.
bad=$(git log --format='%h %G?' "$range" | awk '$2 != "G" && $2 != "U" { printf "%s%s(%s)", sep, $1, $2; sep = " " }')
if [ -n "$bad" ]; then
	fail "signatures: not signed or not valid (status in brackets): $bad"
else
	echo "ok signatures"
fi

# 2. Messages: none may be empty, and AI attribution lines are findings.
empty=
for c in $(git rev-list "$range"); do
	short=$(git rev-parse --short "$c")
	msg=$(git show -s --format=%B "$c")
	if [ -z "$(printf %s "$msg" | tr -d ' \t\r\n')" ]; then
		empty="$empty $short"
		continue
	fi
	printf '%s\n' "$msg" | grep -i -E 'co-authored-by|generated with' | while IFS= read -r line; do
		echo "FINDING attribution: $short: $line"
	done
done
if [ -n "$empty" ]; then
	fail "messages: empty message (a leftover jj commit):$empty"
else
	echo "ok messages"
fi
# The loop above ran in a subshell, so count the findings again here.
findings=$(git log --format=%B "$range" | grep -c -i -E 'co-authored-by|generated with')

# 3. Base: it must be an ancestor of the branch.
if git merge-base --is-ancestor "$baseref" "$sref"; then
	echo "ok base"
else
	behind=$(git rev-list --count "$sref..$baseref")
	fail "base: $baseref is not an ancestor of the branch, it moved on by $behind commit(s) after the branch was made. Do not rebase here, it would break the signatures"
fi

# 4. If the branch exists on the remote, the new ref must fast-forward it.
if tip=$(git ls-remote "$remote" "refs/heads/$branch" 2>/dev/null); then
	tip=${tip%%[[:space:]]*}
	if [ -z "$tip" ]; then
		echo "ok remote: $branch is new on $remote"
	elif [ "$tip" = "$head" ]; then
		echo "ok remote: $remote already has this exact commit, nothing to push"
	elif git cat-file -e "$tip^{commit}" 2>/dev/null && git merge-base --is-ancestor "$tip" "$sref"; then
		echo "ok remote: a fast-forward of $remote/$branch at $(git rev-parse --short "$tip")"
	else
		fail "remote: $branch exists on $remote at $(printf %.9s "$tip") and the new ref does not contain it, so pushing needs a force push. Stop and ask"
	fi
else
	echo "WARN remote: could not read $remote, check by hand whether $branch exists there"
fi

echo "diffstat:"
git diff --stat --no-ext-diff --no-textconv "$baseref...$sref"
echo "NOTE secrets: not checked here. Read the added lines of: git diff $baseref...$sref"
finish

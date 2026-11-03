#!/bin/bash
set -euo pipefail

: "${SBX_SANDBOX_NAME:?Missing sandbox name}"

sandbox="$SBX_SANDBOX_NAME"
version="${GIT_BUG_VERSION:-0.11.0}"

if sbx exec "$sandbox" sh -c 'command -v git-bug >/dev/null 2>&1 || test -x "$HOME/.local/bin/git-bug"'; then
    echo "git-bug already installed in $sandbox"
    exit 0
fi

case "$(sbx exec "$sandbox" uname -m | tr -d '\r')" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) echo "unsupported architecture in $sandbox" >&2; exit 1 ;;
esac

echo "Installing git-bug $version ($arch) in $sandbox..."

# curl runs on the HOST; tar runs inside the VM.
curl -fsSL "https://github.com/git-bug/git-bug/releases/download/v${version}/git-bug_${version}_linux_${arch}.tar.gz" |
    sbx exec -i "$sandbox" sh -c '
        mkdir -p "$HOME/.local/bin"
        tar -xzf - --strip-components=1 -C "$HOME/.local/bin" "$1"
    ' sh "git-bug_${version}_linux_${arch}/git-bug"

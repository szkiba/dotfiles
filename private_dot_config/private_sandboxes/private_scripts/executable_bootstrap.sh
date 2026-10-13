#!/bin/bash
set -euo pipefail

: "${SBX_SANDBOX_NAME:?Missing sandbox name}"

sandbox="$SBX_SANDBOX_NAME"

# Check whether chezmoi is already installed in the VM.
if sbx exec "$sandbox" sh -c '
    command -v chezmoi >/dev/null 2>&1 ||
    test -x "$HOME/.local/bin/chezmoi"
'; then
    echo "chezmoi already installed in $sandbox"
else
    echo "Installing chezmoi in $sandbox..."

    # curl runs on HOST; installer script runs inside VM.
    curl -fsLS https://get.chezmoi.io |
        sbx exec -i "$sandbox" sh -c '
            mkdir -p "$HOME/.local/bin"
            sh -s -- -b "$HOME/.local/bin"
        '
fi

# Initialize dotfiles inside the VM.
sbx exec "$sandbox" sh -c '
    export PATH="$HOME/.local/bin:$PATH"
    chezmoi init --apply szkiba
'
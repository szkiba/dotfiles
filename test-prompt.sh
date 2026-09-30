#!/usr/bin/env bash
# Repo-only dev aid -- never deployed by chezmoi. Prints the resulting
# _OMB_CTX_ICON/_OMB_CTX_HOST for a table of env-var combinations so
# font.theme.sh changes can be regression-tested without a real
# container/VM/ssh session. Goes through a real interactive bash (same as
# .bashrc -> oh-my-bash -> theme) since the theme relies on oh-my-bash's
# own bootstrap (_omb_util_add_prompt_command, color vars, etc.) that a
# bare `source` of the theme file alone doesn't provide.
set -eo pipefail

run_case() {
    local desc=$1; shift
    (
        unset SANDBOX_HOST SANDBOX_NAME CONTAINER_ID DEVBOX_PROJECT_ROOT \
              SSH_CONNECTION SSH_TTY INCUS_HOST
        (( $# )) && export "$@"
        bash -i -c 'printf "%-28s icon=[%s]  host=[%s]\n" "'"$desc"'" "$_OMB_CTX_ICON" "$_OMB_CTX_HOST"' 2>/dev/null
    )
}

run_case "bare metal"
run_case "ssh"                SSH_CONNECTION=x
run_case "distrobox"          CONTAINER_ID=mybox
run_case "distrobox+ssh"      CONTAINER_ID=mybox SSH_CONNECTION=x
run_case "sandbox"            SANDBOX_HOST=h SANDBOX_NAME=n
run_case "devbox"             DEVBOX_PROJECT_ROOT=/code/myproject
run_case "devbox+distrobox"   DEVBOX_PROJECT_ROOT=/code/myproject CONTAINER_ID=mybox
run_case "all three overlays" SANDBOX_HOST=h SANDBOX_NAME=n CONTAINER_ID=mybox \
                               DEVBOX_PROJECT_ROOT=/code/myproject

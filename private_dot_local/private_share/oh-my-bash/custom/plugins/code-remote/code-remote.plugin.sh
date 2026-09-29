#! bash oh-my-bash.plugin
#
# Open a machine over Remote-SSH: a folder, or one of its generated workspaces.
#   c ksix            -> /code/ksix                        (whole machine)
#   c ksix protocol   -> workspaces/protocol.code-workspace (tagged repos + own TEMP)
c() {
    local machine=$1 ws=${2%.code-workspace} dir target

    if [ -z "$machine" ]; then
        echo "usage: c <machine> [workspace]" >&2
        return 1
    fi

    dir="/code/$machine"
    # A local check: /code/<machine> is the host-side worktree, not a remote path.
    if [ ! -d "$dir" ]; then
        echo "c: no such machine: $dir" >&2
        return 1
    fi

    # Remote-SSH against a stopped machine hangs instead of failing.
    if command -v incus >/dev/null 2>&1 &&
       [ "$(incus list "$machine" -c s --format csv 2>/dev/null)" != RUNNING ]; then
        echo "c: $machine is not running — (cd $dir && make up)" >&2
        return 1
    fi

    target=$dir
    if [ -n "$ws" ]; then
        target="$dir/workspaces/$ws.code-workspace"
        if [ ! -f "$target" ]; then
            echo "c: no workspace '$ws' in $machine. available:" >&2
            ls "$dir/workspaces" 2>/dev/null | sed 's/\.code-workspace$//;s/^/  /' >&2
            return 1
        fi
    fi

    code --remote "ssh-remote+$machine" "$target"
}

# Completion for c: machines from /code, then that machine's generated workspaces.
_c() {
    local cur=${COMP_WORDS[COMP_CWORD]} d w names=()

    case $COMP_CWORD in
        1)  # A machine is a worktree of this repo, which bin/up.sh identifies.
            # /code holds unrelated directories too, and ~/.ssh/config.d holds
            # unrelated hosts, so neither is a usable list on its own.
            for d in /code/*/; do
                [ -f "$d/bin/up.sh" ] && names+=("$(basename "$d")")
            done ;;
        2)  # Workspaces of the machine already typed, if it has any.
            for w in "/code/${COMP_WORDS[1]}/workspaces"/*.code-workspace; do
                [ -f "$w" ] && names+=("$(basename "$w" .code-workspace)")
            done ;;
        *)  return ;;
    esac

    COMPREPLY=($(compgen -W "${names[*]}" -- "$cur"))
}
complete -F _c c

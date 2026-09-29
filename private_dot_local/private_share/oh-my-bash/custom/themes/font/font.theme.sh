#! bash oh-my-bash.module
#
# Override for the built-in "font" theme: drops the python-venv/spack-env
# prefix, keeping just time/user@host/pwd/git/status-arrow, and adds a
# shell-context badge (sandbox/distrobox/devbox/docker/podman/incus/vm/ssh)
# next to user@host.

source "$OSH/themes/font/font.theme.sh"

# Detect the kind of shell context once per shell (not per prompt render):
# local | sandbox | distrobox | devbox | docker | podman | incus | vm | ssh.
# "incus" is an Incus/LXD *container* specifically; an Incus-orchestrated VM falls
# under the generic "vm" bucket so container vs VM stays visually distinct.
# Container/VM markers mirror those already vetted in
# .chezmoitemplates/isVirtual, for consistency across the repo.
_omb_theme_detect_context() {
    # sandbox.sh's bubblewrap sandbox sets this; nothing else (namespaces
    # alone) marks it, so this env var is the only signal. Checked first
    # since it can wrap any of the other contexts below.
    if [[ -n "$SANDBOX_HOST" ]]; then
        echo "sandbox"
        return
    fi

    # Distrobox layers on top of a plain docker/podman container and can
    # only be told apart via this env var it exports inside the box.
    if [[ -n "$CONTAINER_ID" ]]; then
        echo "distrobox"
        return
    fi

    # A devbox (nix) shell doesn't change the hostname or namespace, just
    # this env var -- badge only, no _OMB_CTX_HOST override for it.
    if [[ -n "$DEVBOX_PROJECT_ROOT" ]]; then
        echo "devbox"
        return
    fi

    local virt=""
    if command -v systemd-detect-virt &>/dev/null; then
        # Authoritative: trust "none" as-is, don't fall through to the file
        # markers below -- /dev/incus/sock exists on Incus VMs too, not
        # just containers, so it would otherwise wrongly override a
        # confirmed "not a container" answer.
        virt="$(systemd-detect-virt -c 2>/dev/null)"
        [[ "$virt" == "none" ]] && virt=""
    else
        # No systemd-detect-virt (e.g. Alpine) -- only source of truth left.
        if [[ -e /.dockerenv ]]; then
            virt="docker"
        elif [[ -e /run/.containerenv ]]; then
            virt="podman"
        elif [[ -e /dev/incus/sock ]]; then
            virt="lxc"
        fi
    fi
    case "$virt" in
        docker) echo "docker"; return ;;
        podman) echo "podman"; return ;;
        lxc)    echo "incus";  return ;;
    esac

    # Not a container -- check for a VM (including Incus-orchestrated ones,
    # which get the plain vm badge too: container vs VM stays visually
    # distinct regardless of who's orchestrating it).
    local vm=""
    if command -v systemd-detect-virt &>/dev/null; then
        vm="$(systemd-detect-virt -v 2>/dev/null)"
        [[ "$vm" == "none" ]] && vm=""
    fi
    if [[ -z "$vm" ]]; then
        case "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" in
            "QEMU" | "innotek GmbH" | "VMware, Inc." | "Microsoft Corporation" | \
            "Xen" | "Amazon EC2" | "Google" | "Bochs" | \
            "Parallels Software International Inc.")
                vm="vm" ;;
        esac
    fi
    [[ -n "$vm" ]] && { echo "vm"; return; }

    # No container/VM signal left; only an ssh session left to check.
    if [[ -n "$SSH_CONNECTION" || -n "$SSH_TTY" ]]; then
        echo "ssh"
        return
    fi

    echo "local"
}

_omb_theme_ctx="$(_omb_theme_detect_context)"
case "$_omb_theme_ctx" in
    sandbox)   _OMB_CTX_ICON="🔒" ;;
    distrobox) _OMB_CTX_ICON="📥" ;;
    devbox)    _OMB_CTX_ICON="🥡" ;;
    docker)    _OMB_CTX_ICON="🐳" ;;
    podman)    _OMB_CTX_ICON="🦭" ;;
    incus)     _OMB_CTX_ICON="📦" ;;
    vm)        _OMB_CTX_ICON="💻" ;;
    ssh)       _OMB_CTX_ICON="🌐" ;;
    *)         _OMB_CTX_ICON="" ;;
esac

# Distrobox rewrites /etc/hostname to "<box-name>.<host>" so \h happens to
# show the box name too, but that's a contested hack (see distrobox#62) --
# use its own $CONTAINER_ID identifier instead. Same idea for a bwrap
# sandbox: show $SANDBOX_HOST instead of the underlying machine's \h.
_OMB_CTX_HOST='\h'
case "$_omb_theme_ctx" in
    sandbox)   _OMB_CTX_HOST="$SANDBOX_HOST" ;;
    distrobox) _OMB_CTX_HOST="$CONTAINER_ID" ;;
esac

unset -f _omb_theme_detect_context
unset _omb_theme_ctx

function _omb_theme_PROMPT_COMMAND() {
    # This needs to be first to save last command return code
    local RC="$?"

    local hostname="${_omb_prompt_bold_gray}\u@${_omb_prompt_bold_magenta}${_OMB_CTX_HOST}${_OMB_CTX_ICON:+ $_OMB_CTX_ICON}"
    local venv

    # Set return status color
    if [[ ${RC} == 0 ]]; then
        ret_status="${_omb_prompt_bold_green}"
    else
        ret_status="${_omb_prompt_bold_brown}"
    fi

    # Append new history lines to history file
    history -a

    PS1="$(clock_prompt)${hostname} ${_omb_prompt_bold_teal}\W $(scm_prompt_char_info)${ret_status}→ ${_omb_prompt_normal}"
}

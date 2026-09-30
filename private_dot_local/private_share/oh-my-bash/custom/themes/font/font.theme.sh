#! bash oh-my-bash.module
#
# Override for the built-in "font" theme: drops the python-venv/spack-env
# prefix, keeping just time/user@host/pwd/git/status-arrow, and adds a
# shell-context badge (docker/podman/incus/vm/ssh, plus the sandbox/
# distrobox/devbox overlays below) next to user@host.

source "$OSH/themes/font/font.theme.sh"

# Detect the base shell context once per shell (not per prompt render):
# local | docker | podman | incus | vm | ssh. This is the mutually
# exclusive "innermost virtualization technology" fact -- sandbox,
# distrobox and devbox are NOT part of this chain (see the overlay block
# below): their env vars are orthogonal to this and can be set at the same
# time as being in a VM, an Incus container, etc. "incus" is an Incus/LXD
# *container* specifically; an Incus-orchestrated VM falls under the
# generic "vm" bucket so container vs VM stays visually distinct.
# Container/VM markers mirror those already vetted in
# .chezmoitemplates/isVirtual, for consistency across the repo.
_omb_theme_detect_context() {
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
    docker) _OMB_CTX_ICON="🐳" ;;
    podman) _OMB_CTX_ICON="🦭" ;;
    incus)  _OMB_CTX_ICON="📦" ;;
    vm)     _OMB_CTX_ICON="💻" ;;
    ssh)    _OMB_CTX_ICON="🌐" ;;
    *)      _OMB_CTX_ICON="" ;;
esac

# Plain \h alone is rarely enough context for incus/vm -- they have their
# own separate identity that \h doesn't reflect at all. $INCUS_HOST is
# opt-in, not provided by Incus itself: set it per-instance with
# `incus config set <instance> environment.INCUS_HOST=$(hostname)` on the
# Incus host. Left unset, there's nothing to join, so no separator is
# added at all -- just plain \h, same as any other base context.
_OMB_CTX_HOST='\h'
case "$_omb_theme_ctx" in
    incus|vm) [[ -n "$INCUS_HOST" ]] && _OMB_CTX_HOST="${INCUS_HOST}${_omb_prompt_bold_yellow}·\h" ;;
esac

unset -f _omb_theme_detect_context
unset _omb_theme_ctx

# Overlays: unlike the base layer above, none of these are namespace
# boundaries by themselves (or, for sandbox/distrobox, not exclusively so)
# -- their env vars can be set at the same time as being in a VM, an Incus
# container, over ssh, etc. (e.g. a distrobox created inside a VM). So each
# composes on top of the base icon/host instead of replacing it, appending
# its own icon and one more "·segment". Fixed, arbitrary but deterministic
# order -- sandbox, then distrobox, then devbox -- so the same combination
# always renders the same way, though it isn't based on actual nesting
# depth (which isn't detectable).
#
# sandbox.sh's bubblewrap sandbox sets $SANDBOX_HOST/$SANDBOX_NAME; nothing
# else (namespaces alone) marks it, so these env vars are the only signal.
if [[ -n "$SANDBOX_HOST" ]]; then
    _OMB_CTX_ICON="${_OMB_CTX_ICON:+$_OMB_CTX_ICON }🔒"
    _OMB_CTX_HOST="${_OMB_CTX_HOST}${_omb_prompt_bold_yellow}·${SANDBOX_HOST}${_omb_prompt_bold_yellow}·${SANDBOX_NAME}"
fi

# Distrobox layers on top of a plain docker/podman container and can only
# be told apart via this env var it exports inside the box. It also
# rewrites /etc/hostname to "<box-name>.<host>" so \h happens to show the
# box name too, but that's a contested hack (see distrobox#62) -- append
# $CONTAINER_ID explicitly instead of relying on it.
if [[ -n "$CONTAINER_ID" ]]; then
    _OMB_CTX_ICON="${_OMB_CTX_ICON:+$_OMB_CTX_ICON }📥"
    _OMB_CTX_HOST="${_OMB_CTX_HOST}${_omb_prompt_bold_yellow}·${CONTAINER_ID}"
fi

# A devbox (nix) shell doesn't change the namespace or hostname at all,
# just this env var -- append the project dir name as its identity.
if [[ -n "$DEVBOX_PROJECT_ROOT" ]]; then
    _OMB_CTX_ICON="${_OMB_CTX_ICON:+$_OMB_CTX_ICON }🥡"
    _OMB_CTX_HOST="${_OMB_CTX_HOST}${_omb_prompt_bold_yellow}·$(basename "$DEVBOX_PROJECT_ROOT")"
fi

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

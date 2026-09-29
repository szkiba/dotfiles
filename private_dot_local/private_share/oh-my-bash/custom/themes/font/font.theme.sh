#! bash oh-my-bash.module
#
# Override for the built-in "font" theme: drops the python-venv/spack-env
# prefix, keeping just time/user@host/pwd/git/status-arrow, and adds a
# shell-context badge (distrobox/docker/podman/incus/vm/ssh) next to
# user@host.

source "$OSH/themes/font/font.theme.sh"

# Detect the kind of shell context once per shell (not per prompt render):
# local | distrobox | docker | podman | incus | vm | ssh. Mirrors the
# container/VM markers already vetted in .chezmoitemplates/isVirtual, for
# consistency across the repo.
_omb_theme_detect_context() {
    # Distrobox layers on top of a plain docker/podman container and can
    # only be told apart via this env var it exports inside the box.
    if [[ -n "$CONTAINER_ID" ]]; then
        echo "distrobox"
        return
    fi

    local virt=""
    if command -v systemd-detect-virt &>/dev/null; then
        virt="$(systemd-detect-virt -c 2>/dev/null)"
        [[ "$virt" == "none" ]] && virt=""
    fi
    if [[ -z "$virt" ]]; then
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

    # Not a container. Incus VMs are SMBIOS-tagged; bucket them with the
    # incus container badge since they're still "an Incus instance".
    if [[ "$(cat /sys/class/dmi/id/board_vendor 2>/dev/null)" == "LinuxContainers" &&
          "$(cat /sys/class/dmi/id/board_name 2>/dev/null)" == "Incus" ]]; then
        echo "incus"
        return
    fi

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
    distrobox) _OMB_CTX_ICON="🧰" ;;
    docker)    _OMB_CTX_ICON="🐳" ;;
    podman)    _OMB_CTX_ICON="🦭" ;;
    incus)     _OMB_CTX_ICON="📦" ;;
    vm)        _OMB_CTX_ICON="🖥️" ;;
    ssh)       _OMB_CTX_ICON="🌐" ;;
    *)         _OMB_CTX_ICON="" ;;
esac

# Distrobox rewrites /etc/hostname to "<box-name>.<host>" so \h happens to
# show the box name too, but that's a contested hack (see distrobox#62) --
# use its own $CONTAINER_ID identifier instead of relying on it.
_OMB_CTX_HOST='\h'
[[ "$_omb_theme_ctx" == distrobox ]] && _OMB_CTX_HOST="$CONTAINER_ID"

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

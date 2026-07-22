#!/bin/bash

export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus

prog=$(basename $0)
cd $(dirname $0)

exec > >(logger -i -s -p user.info -t $prog)
exec 2>&1

export SSH_ASKPASS_REQUIRE=force 
export SSH_ASKPASS=/usr/lib/openssh/gnome-ssh-askpass
export GNOME_SSH_ASKPASS_GRAB_SERVER=true
export SSH_AUTH_SOCK="/run/user/$(id -u)/keyring/ssh"

if [[ "$HID_PHYS" != *input0 ]] ; then
   exit 0
fi

case "$ACTION" in
  bind)
    if ssh-add -K; then
      notify-send "Added SSH FIDO2 keys"
    else
      notify-send -u critical --icon dialog-error "Failed to add SSH FIDO2 keys, check logs!"
    fi
    ;;
  unbind)
    shopt -s nullglob
    fido_keys+=($(grep -l '^sk-' "$HOME"/.ssh/*.pub 2>/dev/null))

    removed_any=false

    for key in "${fido_keys[@]}"; do
      if ssh-add -d "$key"; then
        removed_any=true
      fi
    done

    if $removed_any; then
      notify-send "Removed SSH FIDO2 keys"
    else
      notify-send -u critical --icon dialog-error "Failed to remove SSH FIDO2 keys, check logs!"
    fi
    ;;
esac

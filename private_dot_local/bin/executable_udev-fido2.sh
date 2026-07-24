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

# udev fires once per HID interface; act only on input0 to avoid duplicate runs.
# ACTION unset => manual/autostart run, skip the filter.
if [[ -n "$ACTION" && "$HID_PHYS" != *input0 ]] ; then
   exit 0
fi

# Any key change (plug or unplug): flush the agent, then reload resident keys.
# ssh-add -K needs a touch per authenticator, so touch the key you want to keep.
# Remove only FIDO2 (sk-*) keys; leave any regular keys in the agent alone.
sk_keys=$(ssh-add -L 2>/dev/null | grep '^sk-')
if [[ -n "$sk_keys" ]]; then
  if printf '%s\n' "$sk_keys" | ssh-add -d -; then
    notify-send "Removed SSH FIDO2 keys"
  else
    notify-send -u critical --icon security-high "Failed to remove SSH FIDO2 keys, check logs!"
  fi
fi

# Reload only if an authenticator is still connected (avoids false failure on last unplug).
if ! fido2-token -L | grep -q .; then
  notify-send --icon security-medium "No FIDO2 key present"
  exit 0
fi

if ssh-add -K; then
  notify-send "Added SSH FIDO2 keys"
else
  notify-send -u critical --icon security-high "Failed to add SSH FIDO2 keys, check logs!"
fi

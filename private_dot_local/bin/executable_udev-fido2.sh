#!/bin/bash

export PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/bin:$PATH"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
export SSH_AUTH_SOCK="/run/user/$(id -u)/gcr/ssh"

export SSH_ASKPASS_REQUIRE=force 
export SSH_ASKPASS=/usr/lib/openssh/gnome-ssh-askpass
export GNOME_SSH_ASKPASS_GRAB_SERVER=true

prog=$(basename "$0")
cd "$(dirname "$0")" || exit 1

exec > >(logger -i -s -p user.info -t "$prog")
exec 2>&1

# udev fires once per HID interface; act only on input0 to avoid duplicate runs.
# ACTION unset => manual/autostart run, skip the filter.
if [[ -n "$ACTION" && "$HID_PHYS" != *input0 ]] ; then
  exit 0
fi

# Some scans (e.g. KeepassXC) cause a full unbind/remove/add/bind re-enum
# without a real unplug, firing this script twice within well under a second.
# Debounce: skip if the last run started less than 2s ago.
lock=/run/user/$(id -u)/fido2-reload.lock
exec 9>>"$lock"
flock 9
last=$(stat -c %Y "$lock" 2>/dev/null || echo 0)
now=$(date +%s)
if (( now - last < 2 )); then
  exit 0
fi
touch "$lock"

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

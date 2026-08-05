#!/bin/bash

export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
export SSH_TPM_AUTH_SOCK=/run/user/$(id -u)/ssh-tpm-agent.sock

prog=$(basename $0)
cd $(dirname $0)

exec > >(logger -i -s -p user.info -t $prog)
exec 2>&1

# ssh-tpm-agent already loads ~/.ssh/*.tpm at startup; this covers the case where
# the key was created after the agent came up. Re-adding a loaded key is a no-op.
key="$HOME/.ssh/key-tpm-$(hostname -s).tpm"

if [[ ! -f "$key" ]]; then
  echo "no TPM key at $key"
  exit 0
fi

# ssh-tpm-add never asks for the key passphrase; the agent does, on first signing.
if ssh-tpm-add "$key" </dev/null; then
  notify-send "Added TPM SSH key $(basename $key)"
else
  notify-send -u critical --icon security-high "Failed to add TPM SSH key, check logs!"
fi

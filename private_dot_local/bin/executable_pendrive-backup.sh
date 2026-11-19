#!/bin/bash
#
# Back up to a prepared pendrive when it is plugged in.
#
# Started by pendrive-backup@.service, which the udev rule 81-pendrive-backup.rules
# starts. The argument is the partition device, for example /dev/sdb1.
# For a test run, pass a folder instead of a device: it is used as the mount point.
#
# A pendrive is only used if it has an env.sh with the right TOKEN. That is just a
# guard against backing up to a stick that was not meant for it. env.sh can also
# set DIRS to back up a different list of folders to that pendrive.

export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

prog=$(basename "$0")
exec > >(logger -i -s -p user.info -t "$prog")
exec 2>&1

required_token="07c23b54-9739-11ed-aab1-e3157dd3ca6b"

# Missing folders are skipped, so they can be added later on this machine.
DIRS=(
  "/usr/share/icons/crystal"
  "/usr/share/icons/oxygen"
  "$HOME/Dropbox/Private/CloudBox"
  "$HOME/Dropbox/Private/CloudPass"
  "$HOME/Homebox/LocalBox"
  "$HOME/Homebox/LocalPass"
  "$HOME/Homebox/LocalWork"
  "$HOME/Homebox/PrivateLegacy"
  "$HOME/.ssh"
  "$HOME/.gnupg"
  "$HOME/.config/sops"
  "$HOME/.passage"
)

target=${1:-}
if [[ -z "$target" ]]; then
  echo "usage: $prog <device or folder>"
  exit 1
fi

is_device=0
if [[ -b "$target" ]]; then
  is_device=1
elif [[ ! -d "$target" ]]; then
  echo "not a block device or a folder: $target"
  exit 1
fi

find_mount() {
  findmnt -n -o TARGET --source "$target" | head -n 1
}

mnt=$target
we_mounted=0
if (( is_device )); then
  mnt=$(find_mount)
  if [[ -z "$mnt" ]]; then
    # The desktop usually mounts it. If it has not yet, mount it here.
    if udisksctl mount -b "$target" --no-user-interaction; then
      we_mounted=1
    fi
    # If the desktop mounted it at the same moment, our mount fails but it is there.
    for _ in 1 2 3 4 5; do
      mnt=$(find_mount)
      [[ -n "$mnt" ]] && break
      sleep 1
    done
  fi
  if [[ -z "$mnt" ]]; then
    echo "$target could not be mounted, leaving it alone"
    exit 0
  fi
fi

unmount_if_ours() {
  if (( we_mounted )); then
    udisksctl unmount -b "$target" --no-user-interaction
  fi
}

# Read the token without running anything from the stick. Only after it matches
# is env.sh sourced, to pick up an optional DIRS list.
token=
if [[ -f "$mnt/env.sh" ]]; then
  token=$(sed -n 's/^TOKEN=//p' "$mnt/env.sh" | head -n 1 | tr -d "\"' \r")
fi
if [[ "$token" != "$required_token" ]]; then
  echo "$mnt is not a backup pendrive, leaving it alone"
  unmount_if_ours
  exit 0
fi
# shellcheck disable=SC1091
source "$mnt/env.sh"

notify-send "Start backup - $mnt"

if ! mkdir -p "$mnt/backup"; then
  notify-send -u critical --icon dialog-error "Cannot write to $mnt, check logs!"
  exit 1
fi

failed=0
for src in "${DIRS[@]}"; do
  if [[ ! -e "$src" ]]; then
    echo "skip, not found: $src"
    continue
  fi
  if ! rsync -r -t -p -o -g -x -c -b -s --delete \
      --info=NAME1,STATS,BACKUP,REMOVE,SKIP \
      --exclude='*.lock' --backup-dir=backup "$src" "$mnt/"; then
    failed=1
    notify-send -u critical --icon dialog-error "Backup error in $src, check logs!"
  fi
done

sync

if (( failed )); then
  # Leave the stick mounted so the problem can be looked at.
  exit 1
fi

if (( is_device )); then
  if udisksctl unmount -b "$target" --no-user-interaction; then
    notify-send "Backup done, you can remove the pendrive - $mnt"
  else
    notify-send -u critical --icon dialog-error "Backup done, but cannot unmount $mnt, check logs!"
  fi
else
  notify-send "Backup done - $mnt"
fi

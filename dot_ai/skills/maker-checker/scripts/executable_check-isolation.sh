#!/bin/sh
# Tells whether this machine looks like a container, a VM or a Docker sandbox.
# Exits 0 and prints the signal that matched, or exits 1 and says why on stderr.
#
# It only sees that a container or VM exists, not how well it is isolated, so a
# container with the host's Docker socket or home folder mounted still passes.

if systemd-detect-virt -q 2>/dev/null; then
	echo "systemd-detect-virt reports $(systemd-detect-virt 2>/dev/null)"
	exit 0
fi

if [ -e /.dockerenv ]; then
	echo "/.dockerenv exists"
	exit 0
fi

if [ -e /run/.containerenv ]; then
	echo "/run/.containerenv exists"
	exit 0
fi

# Created by Docker Sandboxes, root-owned, absent on the host
if [ -d /run/sbx ]; then
	echo "/run/sbx exists"
	exit 0
fi

# x86 only: arm64 guests have no such flag, they rely on the checks above
if grep -qw hypervisor /proc/cpuinfo 2>/dev/null; then
	echo "/proc/cpuinfo has the hypervisor flag"
	exit 0
fi

echo "no sign of a container or VM" >&2
exit 1

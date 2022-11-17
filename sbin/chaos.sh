#!/bin/bash

set -euo pipefail

active_subvol="$(findmnt --target /usr -rn --output FSROOT | tail -n 1)"
active_subvol="${active_subvol%/usr}"
active_subvol="${active_subvol#/}"
default_subvol="$(btrfs subvolume get-default /usr | cut -d " " -f 9)"

if [[ ${active_subvol} == ${default_subvol} ]]; then
	echo "Hallo, Sie haben gewonnen und sind bereits auf dem neuesten Snapshot"
	exit 0
fi

WORKDIR="$(mktemp -d /tmp/tu-chaos.XXXXXXXX)"
cleanup () {
	if mountpoint -q "${WORKDIR}/mount"; then
		umount -R "${WORKDIR}/mount"
	fi
	rm -r "${WORKDIR}"
}

trap cleanup EXIT

mkdir "${WORKDIR}/mount"
sourcedevice="$(findmnt --target /usr -rn --output SOURCE --nofsroot | tail -n 1)"
mount "${sourcedevice}" "${WORKDIR}/mount"
mount --bind /usr/local/ "${WORKDIR}/mount/usr/local"
mount --rbind "${WORKDIR}/mount/usr" /usr
mount --rbind "${WORKDIR}/mount/etc" /etc
#TODO: /boot und Submounts auch noch rbinden
# Oder vielleicht auch einfach alle Submounts von /usr, /etc und /boot, um wirklich sicher zu gehen, keine nutzergenerierten Submounts zu übergehen
umount -l "${WORKDIR}/mount"
systemctl daemon-reexec
create_dirs_from_rpmdb
systemd-tmpfiles --create

# Kernel: Wegen Modulen auch running
# Für MicroOS brauchen wir wieder zwei Kernel

# inotifys hören weiter im alten Snapshot
# SELinux: Wie im Tumbleweed jetzt auch schon könnten alte Prozesse betroffen sein

# Firefox-Update - bleibt die bestehende Instanz benutzbar?
# libc-Update
# Inkompatibles Bibliotheks-Update

# Kriterium für einen "guten" Snapshot ist, dass ein Update mit diesem als laufendem System gemacht wird. Das muss natürlich angepasst werden, dass hier auch erkannt wird, wenn mit chaos das laufende System live umgeschaltet wurde.

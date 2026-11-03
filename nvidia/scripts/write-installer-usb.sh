#!/bin/bash
# Write a completed installer ISO to an explicitly selected USB disk and verify it.
set -euo pipefail
[[ $# == 3 && $3 == --erase ]] || { echo "Usage: sudo $0 installer.iso /dev/disk/by-id/usb-... --erase"; exit 2; }
[[ $EUID == 0 ]] || { echo 'Run with sudo'; exit 1; }
iso=$(realpath "$1")
[[ $2 == /dev/disk/by-id/usb-* && $2 != *-part* ]] || { echo 'Select a whole USB disk by persistent ID'; exit 1; }
disk=$(readlink -f "$2")
[[ -f $iso && -b $disk && $(lsblk -dnro TRAN "$disk") == usb ]] || exit 1
[[ -z $(lsblk -nrpo MOUNTPOINTS "$disk" | tr -d '[:space:]') ]] || { echo 'Disk has mounted partitions; unmount them first'; exit 1; }
size=$(stat -c %s "$iso")
(( $(blockdev --getsize64 "$disk") >= size )) || { echo 'USB too small'; exit 1; }
[[ -f $iso.sha256 ]] || { echo "Missing ISO checksum file"; exit 1; }
sha256sum -c "$iso.sha256"
xorriso -indev "$iso" -report_el_torito plain >/dev/null 2>&1
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN "$disk"
echo "Erasing $2 and writing $iso"
wipefs --all "$disk"
dd if="$iso" of="$disk" bs=8M conv=fsync status=progress
blockdev --flushbufs "$disk"
cmp -n "$size" "$iso" "$disk"
partprobe "$disk"
echo 'USB read-back matches the installer ISO exactly.'
sha256sum "$iso"

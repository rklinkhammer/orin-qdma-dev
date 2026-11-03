#!/bin/bash
set -euo pipefail
source /project/release.env
bsp=/reference/Linux_for_Tegra
[[ ! -f /work/baseline-complete ]] || bsp=/work/Linux_for_Tegra
cat "$bsp/rootfs/etc/os-release"
cat "$bsp/rootfs/etc/nv_tegra_release"
test -f "$bsp/$BOARD.conf"
headers="$bsp/rootfs/usr/src/linux-headers-$KERNEL_RELEASE-ubuntu24.04_aarch64/3rdparty/canonical/linux-noble"
test -s "$headers/Module.symvers"
grep -F "$KERNEL_RELEASE" "$headers/include/generated/utsrelease.h"
printf 'NVIDIA reference BSP and matching kernel symbol table found.\n'

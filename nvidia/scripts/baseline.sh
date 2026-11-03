#!/bin/bash
set -euo pipefail
source /project/release.env
[[ ! -e /work/Linux_for_Tegra ]] || { echo 'Existing work/Linux_for_Tegra: refusing to overwrite it'; exit 1; }
# Enough for archives, extracted NVIDIA root and staging; flash image generation needs more.
free=$(df -Pk /work | awk 'NR==2 {print $4}')
(( free >= 25*1024*1024 )) || { echo 'Baseline extraction needs at least 25 GiB free'; exit 1; }
bash /project/scripts/fetch.sh
tar --numeric-owner -xpf /work/downloads/Jetson_Linux_R39.2.1_aarch64.tbz2 -C /work
mkdir -p /work/Linux_for_Tegra/rootfs
tar --numeric-owner -xpf /work/downloads/Tegra_Linux_Sample-Root-Filesystem_R39.2.1_aarch64.tbz2 -C /work/Linux_for_Tegra/rootfs
cd /work/Linux_for_Tegra
./apply_binaries.sh
printf 'R%s applied successfully\n' "$L4T_RELEASE" > /work/baseline-complete

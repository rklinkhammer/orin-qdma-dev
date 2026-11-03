#!/bin/bash
set -euo pipefail
source /project/release.env
[[ -f /work/Linux_for_Tegra/rootfs/etc/os-release ]]
cd /work/Linux_for_Tegra
./apply_binaries.sh
printf 'R%s applied successfully\n' "$L4T_RELEASE" > /work/baseline-complete

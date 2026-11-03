#!/bin/bash
set -euo pipefail
source /project/release.env
mkdir -p /work/downloads
fetch() {
    local name=$1 hash=$2
    if [[ ! -f /work/downloads/$name ]]; then
        if [[ -f /reference/downloads/$name ]]; then
            cp /reference/downloads/"$name" /work/downloads/
        else
            curl --fail --location --retry 3 -o "/work/downloads/$name.partial" \
              "https://developer.nvidia.com/downloads/embedded/L4T/r39_Release_v2.1/release/$name"
            mv "/work/downloads/$name.partial" "/work/downloads/$name"
        fi
    fi
    echo "$hash  /work/downloads/$name" | sha256sum -c -
}
fetch Jetson_Linux_R39.2.1_aarch64.tbz2 "$BSP_SHA256"
fetch Tegra_Linux_Sample-Root-Filesystem_R39.2.1_aarch64.tbz2 "$ROOTFS_SHA256"

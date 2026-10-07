#!/bin/bash
set -euo pipefail
[[ $(id -u) == 1000 && $(id -g) == 1000 ]]
[[ $(uname -m) == x86_64 ]]
for path in /home/yocto/orin /home/yocto/orin/downloads /home/yocto/orin/sstate-cache /artifacts; do
    [[ -w $path ]] || { echo "Not writable: $path" >&2; exit 1; }
done
for path in /opt/orin-config /opt/orin-scripts /opt/orin-layers; do
    [[ ! -w $path ]] || { echo "Expected read-only mount: $path" >&2; exit 1; }
done
id
df -h /home/yocto/orin /artifacts
free -h
aarch64-linux-gnu-gcc --version | head -1
python3 --version
echo 'Non-root user, read-only mounts and persistent writable volumes validated.'

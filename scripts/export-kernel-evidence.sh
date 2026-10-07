#!/bin/bash
# Export compile evidence; these files are not a carrier-specific boot image.
set -euo pipefail
source /opt/orin-config/versions.sh
work="/home/yocto/orin/smoke/${ORIN_MACHINE:?}"
[[ $(git -C "$work/kernel" rev-parse HEAD) == "$KERNEL_REV" ]]
destination="/artifacts/$ORIN_MACHINE/smoke-kernel"
mkdir -p "$destination"
for artifact in arch/arm64/boot/Image Module.symvers System.map; do
    [[ -s $work/kernel-build/$artifact ]]
    cp "$work/kernel-build/$artifact" "$destination/"
done
cp "$work/kernel-build/.config" "$destination/kernel.config"
cp "$work/kernel-build/include/config/kernel.release" "$destination/kernel.release"
git -C "$work/kernel" rev-parse HEAD > "$destination/source-revision.txt"
aarch64-linux-gnu-gcc --version > "$destination/compiler.txt"
aarch64-linux-gnu-readelf -h "$work/kernel-build/vmlinux" > "$destination/vmlinux-elf-header.txt"
cd "$destination"
sha256sum Image Module.symvers System.map kernel.config kernel.release source-revision.txt compiler.txt vmlinux-elf-header.txt > SHA256SUMS
file Image
cat kernel.release
cat vmlinux-elf-header.txt

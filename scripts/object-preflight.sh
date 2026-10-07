#!/bin/bash
# Compile only QDMA PF objects. Full kernel symbols/modpost remain mandatory.
set -euo pipefail
source /opt/orin-config/versions.sh
root=/home/yocto/orin
machine=${ORIN_MACHINE:?}
work="$root/preflight/$machine"
kernel="$root/smoke/$machine/kernel"
config="$root/smoke/$machine/kernel-build/.config"
mkdir -p "$work"
exec 8>"$root/.sources.lock"
flock -n -s 8 || { echo 'Source synchronization is active.' >&2; exit 1; }
exec 9>"$work/.objects.lock"
flock -n 9 || { echo 'Another object preflight is active.' >&2; exit 1; }
[[ $(git -C "$kernel" rev-parse HEAD) == "$KERNEL_REV" ]]
[[ $(git -C "$root/dma_ip_drivers" rev-parse HEAD) == "$QDMA_REV" ]]
[[ -s $config ]]
if [[ ! -d $work/qdma/.git ]]; then
    git clone --no-hardlinks "$root/dma_ip_drivers" "$work/qdma"
    git -C "$work/qdma" checkout --detach "$QDMA_REV"
fi
for patch in /opt/orin-layers/meta-orin-qdma/recipes-kernel/qdma/files/*.patch; do
    if git -C "$work/qdma" apply --reverse --check "$patch" 2>/dev/null; then continue; fi
    git -C "$work/qdma" apply --check "$patch"
    git -C "$work/qdma" apply "$patch"
done
mkdir -p "$work/kernel-build"
cp "$config" "$work/kernel-build/.config"
make -j1 -C "$kernel" O="$work/kernel-build" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_prepare
cat > "$work/objects.mk" <<'MAKE'
include Makefile
.PHONY: object-preflight
object-preflight:
	srcdir=$(CURDIR)/src $(MAKE) -j1 -C $(KOBJ) M=$(CURDIR)/src CROSS_COMPILE=$(CROSS_COMPILE_FLAG) qdma-pf.o
MAKE
driver="$work/qdma/QDMA/linux-kernel/driver"
make -j1 -C "$driver" -f "$work/objects.mk" object-preflight USER_ARCH=arm64 \
    KSRC="$kernel" KOBJ="$work/kernel-build" CROSS_COMPILE=aarch64-linux-gnu- \
    modulesymfile="$driver/src/Module.symvers"
destination="/artifacts/$machine/object-preflight"
mkdir -p "$destination"
cp "$driver/src/qdma-pf.o" "$destination/"
file "$driver/src/qdma-pf.o"
aarch64-linux-gnu-readelf -h "$driver/src/qdma-pf.o"
echo 'Object compile only: no module modpost/link or hardware validation.'

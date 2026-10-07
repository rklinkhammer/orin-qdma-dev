#!/bin/bash
# Direct cross-compiler preflight, distinct from a Yocto package build.
set -euo pipefail
source /opt/orin-config/versions.sh
root=/home/yocto/orin
work="$root/smoke/$ORIN_MACHINE"
mkdir -p "$work"
[[ $(git -C "$root/dma_ip_drivers" rev-parse HEAD) == "$QDMA_REV" ]]
prepare_qdma() {
    if [[ ! -d $work/qdma/.git ]]; then
        git clone --no-hardlinks "$root/dma_ip_drivers" "$work/qdma"
        git -C "$work/qdma" checkout --detach "$QDMA_REV"
    fi
    for patch in /opt/orin-layers/meta-orin-qdma/recipes-kernel/qdma/files/*.patch /opt/orin-layers/meta-orin-qdma/recipes-support/qdma-tools/files/*.patch; do
        if git -C "$work/qdma" apply --reverse --check "$patch" 2>/dev/null; then continue; fi
        git -C "$work/qdma" apply --check "$patch"
        git -C "$work/qdma" apply "$patch"
    done
}
case "${1:?}" in
  tools)
    prepare_qdma
    cd "$work/qdma/QDMA/linux-kernel"
    make -C apps clean
    mkdir -p bin
    for app in dma-ctl dma-from-device dma-to-device dma-xfer dma-perf dma-latency; do
        make -j1 -C "apps/$app" "$app" CC=aarch64-linux-gnu-gcc \
            'CFLAGS=-O2 -g -I. -I../include -I../dma-utils' 'LDFLAGS=-Wl,--hash-style=gnu'
        install -m 0755 "apps/$app/$app" "bin/$app"
    done
    mkdir -p "/artifacts/$ORIN_MACHINE/smoke-tools"
    cp bin/dma-* "/artifacts/$ORIN_MACHINE/smoke-tools/"
    file bin/dma-*
    for app in bin/dma-*; do aarch64-linux-gnu-readelf -h "$app"; aarch64-linux-gnu-readelf -d "$app"; done
    ;;
  kernel)
    if [[ ! -d $work/kernel/.git ]]; then
        git clone --depth 1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$work/kernel"
    fi
    [[ $(git -C "$work/kernel" rev-parse HEAD) == "$KERNEL_REV" ]] || { echo 'Kernel pin mismatch' >&2; exit 1; }
    kernel_obj="$work/kernel-build"
    mkdir -p "$kernel_obj"
    make -C "$work/kernel" O="$kernel_obj" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
    "$work/kernel/scripts/kconfig/merge_config.sh" -m -O "$kernel_obj" "$kernel_obj/.config" /opt/orin-layers/meta-orin-qdma/recipes-kernel/linux/files/qdma-host.cfg
    make -C "$work/kernel" O="$kernel_obj" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
    make -j4 -C "$work/kernel" O="$kernel_obj" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image modules
    ;;
  driver)
    prepare_qdma
    [[ -s $work/kernel-build/Module.symvers ]] || { echo 'Run smoke-kernel first to produce Module.symvers.' >&2; exit 1; }
    cd "$work/qdma/QDMA/linux-kernel"
    make -j4 driver MODULE=mod_pf USER_ARCH=arm64 KSRC="$work/kernel" KOBJ="$work/kernel-build" CROSS_COMPILE=aarch64-linux-gnu-
    mkdir -p "/artifacts/$ORIN_MACHINE/smoke-driver"
    cp bin/qdma-pf.ko "/artifacts/$ORIN_MACHINE/smoke-driver/"
    file bin/qdma-pf.ko
    modinfo bin/qdma-pf.ko
    ;;
  *) exit 2 ;;
esac

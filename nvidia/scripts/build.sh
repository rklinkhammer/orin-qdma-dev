#!/bin/bash
set -euo pipefail
source /project/release.env
bash /project/scripts/inspect.sh
stamp=$(date -u +%Y%m%dT%H%M%SZ)
build=$(mktemp -d /work/build-XXXXXX)
out=/work/artifacts/$stamp
mkdir -p "$out" "$build/stage/DEBIAN"
exec > >(tee "$out/build.log") 2>&1
if [[ ! -d /work/dma_ip_drivers.git ]]; then
    git init --bare /work/dma_ip_drivers.git
fi
git --git-dir=/work/dma_ip_drivers.git fetch --depth=1 https://github.com/Xilinx/dma_ip_drivers.git "$QDMA_REV:refs/heads/pinned"
git clone --branch pinned /work/dma_ip_drivers.git "$build/src"
git -C "$build/src" checkout --detach "$QDMA_REV"
for patch in /project/patches/*.patch; do git -C "$build/src" apply "$patch"; done
src=$build/src/QDMA/linux-kernel
mkdir -p "$src/bin"
for app in dma-ctl dma-from-device dma-to-device dma-xfer dma-perf dma-latency; do
    make -j1 -C "$src/apps/$app" "$app" CC=aarch64-linux-gnu-gcc \
      'CFLAGS=-O2 -g -I. -I../include -I../dma-utils' 'LDFLAGS=-Wl,-z,relro,-z,now'
    install -Dm755 "$src/apps/$app/$app" "$build/stage/usr/bin/$app"
done
bsp=/reference/Linux_for_Tegra
[[ ! -f /work/baseline-complete ]] || bsp=/work/Linux_for_Tegra
export QEMU_LD_PREFIX=$bsp/rootfs
headers=$bsp/rootfs/usr/src/linux-headers-$KERNEL_RELEASE-ubuntu24.04_aarch64/3rdparty/canonical/linux-noble
cp -a "$headers" "$build/headers"
chmod -R u+w "$build/headers"
# Use NVIDIA's shipped config and Module.symvers, not the Yocto ABI.
# Packaged ARM64 host helpers execute with the host's binfmt support and reference libc.
make -C "$src" driver KSRC="$build/headers" KOBJ="$build/headers" \
 USER_ARCH=arm64 MODULE=mod_pf CC=aarch64-linux-gnu-gcc LD=aarch64-linux-gnu-ld \
 AR=aarch64-linux-gnu-ar CROSS_COMPILE=aarch64-linux-gnu- V=1
module="$src/bin/qdma-pf.ko"
[[ $(modinfo -F vermagic "$module") == "$KERNEL_RELEASE "* ]]
python3 /project/scripts/check-symbols.py "$module" "$headers/Module.symvers" > "$out/module-abi.json"
install -Dm644 "$module" "$build/stage/lib/modules/$KERNEL_RELEASE/extra/qdma-pf.ko"
install -d "$build/stage/usr/src/qdma" "$build/stage/usr/share/qdma/pcie"
# Ship the patched source without the build-machine's binaries or Git metadata.
mkdir -p "$build/stage/usr/src/qdma/linux-kernel"
tar -C "$src" --exclude='*.o' --exclude='*.ko' --exclude='*.cmd' --exclude='bin' \
 --exclude='Module.symvers' --exclude='modules.order' --exclude='*.mod' --exclude='*.mod.c' \
 --exclude='apps/dma-ctl/dma-ctl' --exclude='apps/dma-from-device/dma-from-device' \
 --exclude='apps/dma-to-device/dma-to-device' --exclude='apps/dma-xfer/dma-xfer' \
 --exclude='apps/dma-perf/dma-perf' --exclude='apps/dma-latency/dma-latency' -cf - . \
 | tar -C "$build/stage/usr/src/qdma/linux-kernel" -xf -
cp -r /project/patches "$build/stage/usr/src/qdma/"
echo "$QDMA_REV" > "$build/stage/usr/src/qdma/UPSTREAM_REVISION"
cp /project/QDMA-README.md "$build/stage/usr/src/qdma/README.md"
cp /project/overlay/* "$build/stage/usr/share/qdma/pcie/"
dtc -@ -I dts -O dtb -o "$build/stage/usr/share/qdma/pcie/pci0-clock-request.dtbo" /project/overlay/pci0-clock-request.dts
cp /project/scripts/prepare-pcie.py "$build/stage/usr/share/qdma/pcie/"
kernel_package_version=$(dpkg-query --admindir="$bsp/rootfs/var/lib/dpkg" -W -f='${Version}' nvidia-l4t-kernel)
cat > "$build/stage/DEBIAN/control" <<CONTROL
Package: orin-qdma-nvidia
Version: 2025.2+${QDMA_REV:0:12}+l4t39.2.1-1
Architecture: arm64
Maintainer: Local Orin development <local@example.invalid>
Depends: nvidia-l4t-kernel (= $kernel_package_version), libc6 (>= 2.38), libaio1t64, kmod, python3, device-tree-compiler
Recommends: build-essential, libaio-dev, nvidia-l4t-kernel-headers
Description: QDMA tools and PF module for NVIDIA L4T R39.2.1 stock kernel
 Includes matching patched sources and an optional C0 PCIe overlay.
CONTROL
cat > "$build/stage/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -e
if [ "$1" = configure ]; then depmod -a 6.8.12-1021-tegra; fi
POST
chmod 755 "$build/stage/DEBIAN/postinst"
dpkg-deb --root-owner-group --build "$build/stage" "$out/orin-qdma-nvidia_arm64.deb"
cp /project/release.env "$out/"
cp -r "$build/stage/usr/share/qdma/pcie" "$out/pcie"
aarch64-linux-gnu-gcc --version > "$out/compiler.txt"
modinfo "$module" > "$out/modinfo.txt"
cp "$module" "$out/qdma-pf.ko"
(cd "$out" && sha256sum orin-qdma-nvidia_arm64.deb > SHA256SUMS)
ln -sfn "artifacts/$stamp" /work/latest
printf '\nBuild passed: %s\n' "$out"

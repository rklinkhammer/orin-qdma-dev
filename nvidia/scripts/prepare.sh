#!/bin/bash
set -euo pipefail
source /project/release.env
[[ -f /work/baseline-complete ]] || { echo 'Run baseline first'; exit 1; }
bsp=/work/Linux_for_Tegra
root=$bsp/rootfs
package=/work/latest/orin-qdma-nvidia_arm64.deb
[[ -f "$package" ]] || { echo 'Run build first'; exit 1; }
[[ ! -e /work/customization-complete ]] || { echo 'Customization already completed; refusing a duplicate install'; exit 1; }
sha256sum "$bsp/kernel/Image" "$root/boot/Image" > /work/kernel-before.sha256
# Stop target package postinst scripts from trying to start services in the chroot.
python3 - "$root" <<'PY'
import pathlib,sys,shutil
r=pathlib.Path(sys.argv[1])
for relative in ['etc/resolv.conf','usr/sbin/policy-rc.d']:
 p=r/relative; backup=p.with_name(p.name+'.orin-build-backup')
 if backup.exists() or backup.is_symlink(): raise SystemExit(f'Stale backup: {backup}')
 if p.exists() or p.is_symlink(): p.rename(backup)
(r/'etc/resolv.conf').write_text(pathlib.Path('/etc/resolv.conf').read_text())
p=r/'usr/sbin/policy-rc.d';p.write_text('#!/bin/sh\nexit 101\n');p.chmod(0o755)
PY
cleanup() {
 python3 - "$root" <<'PY'
import pathlib,sys
r=pathlib.Path(sys.argv[1])
for relative in ['etc/resolv.conf','usr/sbin/policy-rc.d']:
 p=r/relative; backup=p.with_name(p.name+'.orin-build-backup')
 p.unlink(missing_ok=True)
 if backup.exists() or backup.is_symlink(): backup.rename(p)
PY
}
trap cleanup EXIT
cp "$package" "$root/tmp/orin-qdma-nvidia_arm64.deb"
# Requires working ARM64 binfmt registration on the x86-64 Docker host.
chroot "$root" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get update
chroot "$root" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
 /tmp/orin-qdma-nvidia_arm64.deb build-essential libaio-dev device-tree-compiler pciutils
chroot "$root" depmod -a "$KERNEL_RELEASE"
chroot "$root" dpkg-query -W > /work/installed-packages.tsv
sha256sum -c /work/kernel-before.sha256
mkdir -p "$root/opt/orin-nvidia-build"
cp /project/release.env "$root/opt/orin-nvidia-build/"
cp /work/latest/{module-abi.json,compiler.txt,modinfo.txt} "$root/opt/orin-nvidia-build/"
cp /project/README.md "$root/opt/orin-nvidia-build/README.md"
cp /project/VALIDATION.md "$root/opt/orin-nvidia-build/VALIDATION.md"
cp /work/latest/SHA256SUMS /work/customization-complete
printf 'Prepared NVIDIA Ubuntu/L4T flash tree: %s\nNo device was flashed.\n' "$bsp"

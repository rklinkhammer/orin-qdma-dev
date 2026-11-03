#!/bin/bash
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo'; exit 1; }
here=$(cd "$(dirname "$0")/.." && pwd)
work=${NVIDIA_WORK:-$here/work}
input=$work/downloads/jetsoninstaller-r39.2.1-arm64.iso
output=$work/orin-nvidia-qdma-r39.2.1.iso
[[ -f $work/customization-complete && -f $work/latest/orin-qdma-nvidia_arm64.deb ]]
if [[ ! -f $input ]]; then
 curl -fL --retry 3 -o "$input.partial" https://developer.nvidia.com/downloads/embedded/l4t/r39_release_v2.1/iso/jetsoninstaller-r39.2.1-2026-08-07-18-30-47-arm64.iso
 mv "$input.partial" "$input"
fi
# Integrity pin recorded from the downloaded NVIDIA ISO (not a vendor signature).
echo "f31cf35023cd072707dfc46ef23ed71318449516333055fe3bb9455a615395d0  $input" | sha256sum -c -
(cd "$work/latest" && sha256sum -c SHA256SUMS)
build=$(mktemp -d "$work/iso-build-XXXXXX")
xorriso -osirrox on -indev "$input" -extract / "$build/tree"
chmod -R u+w "$build/tree"
sq=casper/ubuntu-server-minimal.ubuntu-server.installer.kernel.nvidia.squashfs
unsquashfs -processors 4 -d "$build/overlay" "$build/tree/$sq"
python3 "$here/scripts/customize-iso.py" "$build/tree" "$build/overlay" "$work"
bash -n "$build/overlay/ai/jetsoniso_setup.bash"
python3 - "$build/overlay/ai/jetsoniso_orin-ai.yaml" <<'PY'
import sys,yaml
yaml.safe_load(open(sys.argv[1]))
PY
python3 "$here/scripts/test-installer-qdma.py" "$build/overlay/ai/jetsoniso_orin-ai.yaml"
mksquashfs "$build/overlay" "$build/nvidia.squashfs" -processors 4 -noappend -comp xz -b 1048576
mv "$build/nvidia.squashfs" "$build/tree/$sq"
# Preserve NVIDIA's signed package repository. Only installer files and local
# package payloads change; recalculate the complete media checksum manifest.
python3 - "$build/tree" "$input" "$output" <<'PY'
import pathlib,sys,hashlib,subprocess,shlex
root=pathlib.Path(sys.argv[1]);source=sys.argv[2];out=sys.argv[3]
with (root/'md5sum.txt').open('w') as manifest:
 for p in sorted(root.rglob('*')):
  rel=p.relative_to(root).as_posix()
  if p.is_file() and not p.is_symlink() and rel not in ['md5sum.txt','boot/boot.cat']:
   with p.open('rb') as f: h=hashlib.file_digest(f,'md5').hexdigest()
   manifest.write(f'{h}  ./{rel}\n')
opts=shlex.split(subprocess.check_output(['xorriso','-indev',source,'-report_el_torito','as_mkisofs'],stderr=subprocess.DEVNULL,text=True))
opts[opts.index('-partition_offset')+1]='16'
subprocess.run(['xorriso','-as','mkisofs',*opts,'-o',out,str(root)],check=True)
PY
# NVIDIA BOOTAA64 is a pre-installer capsule launcher. This carrier-specific
# medium requires existing compatible firmware and boots Canonical shim directly.
# Remove capsule payloads/ISO detection marker so firmware cannot stage them.
python3 - "$output" "$build" <<'PYESP'
import pathlib,struct,subprocess,sys
iso=pathlib.Path(sys.argv[1]);build=pathlib.Path(sys.argv[2])
with iso.open('rb') as f:
 f.seek(512); hdr=f.read(92)
 assert hdr[:8]==b'EFI PART'
 table=struct.unpack_from('<Q',hdr,72)[0]; entrysize=struct.unpack_from('<I',hdr,84)[0]
 f.seek(table*512+entrysize); entry=f.read(entrysize)
 start,end=struct.unpack_from('<QQ',entry,32)
mount=build/'esp';mount.mkdir()
subprocess.run(['mount','-o',f'loop,offset={start*512},sizelimit={(end-start+1)*512}',str(iso),str(mount)],check=True)
try:
 import shutil
 boot=mount/'EFI/BOOT'
 shutil.copyfile(boot/'shimaa64.efi',boot/'bootaa64.efi')
 for capsule in (mount/'EFI').glob('*.Cap'): capsule.unlink()
 (mount/'EFI/ISO_ID').unlink()
 assert (boot/'bootaa64.efi').read_bytes()==(boot/'shimaa64.efi').read_bytes()
 assert not list((mount/'EFI').glob('*.Cap'))
finally:
 subprocess.run(['umount',str(mount)],check=True)
PYESP
sha256sum "$output" > "$output.sha256"
echo "Built $output; no USB or Jetson was written. Build directory: $build"

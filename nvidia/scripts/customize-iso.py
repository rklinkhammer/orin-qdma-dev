#!/usr/bin/env python3
"""Customize an extracted R39.2.1 ISO and NVIDIA installer squashfs."""
import pathlib, sys, shutil
iso, overlay, work = map(pathlib.Path, sys.argv[1:])
payload=iso/'qdma'; (payload/'packages').mkdir(parents=True,exist_ok=True)
shutil.copy2(work/'latest/orin-qdma-nvidia_arm64.deb', payload/'packages')
for p in (work/'Linux_for_Tegra/rootfs/var/cache/apt/archives').glob('*.deb'):
    shutil.copy2(p,payload/'packages')
for name in ['module-abi.json','release.env','compiler.txt','modinfo.txt']:
    shutil.copy2(work/'latest'/name,payload/name)
shutil.copy2(pathlib.Path(__file__).resolve().parents[1]/'USB-INSTALL.md',payload/'README.md')
# Abort before NVIDIA's setup partitions any storage, unless the firmware
# explicitly identifies our carrier. Do not guess P3509 from the SOM alone.
p=overlay/'ai/jetsoniso_setup.bash'; s=p.read_text()
needle='    # determine board type\n'
assert s.count(needle)==1
s=s.replace(needle,'''    # Project-specific P3509 installer guard: before ANY partition changes.
    spec=/sys/firmware/efi/efivars/TegraPlatformSpec-781e084c-a330-417c-b678-38e696380cb9
    if ! test -r "$spec" || ! dd if="$spec" bs=1 skip=4 status=none | tr -d '\\000' | grep -q 'p3509-a02-p3767-0000'; then
        echo 'STOP: this installer requires existing P3509 / Orin NX 16GB firmware.' >&2
        exit 1
    fi
    case "$G_FORCE_BOOTDISK" in
      nvme0n1|/dev/nvme0n1|/dev/nvme0n1,) ;;
      *)
        echo 'STOP: only the internal nvme0n1 installation target is permitted.' >&2
        exit 1
        ;;
    esac
''' + needle)
p.write_text(s)
p=overlay/'ai/jetsoniso_orin-ai.yaml';s=p.read_text()
s=s.replace('late-commands:\n','''late-commands:
  # Preserve carrier-specific QSPI firmware, including HDMI pinmux.
  - mkdir -p /target/opt/nvidia/l4t-packages
  - touch /target/opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall
''',1)
start=s.index('  - logger -p info',s.index('58% Step 8/13'))
end=s.index('  # Setup NVIDIA CTK',start)
assert '67% Step 9/13' in s[start:end] and 'install --reinstall' in s[start:end]
s=s[:start]+'''  - logger -p info "Preserving existing P3509 QSPI firmware; capsule update intentionally disabled"

'''+s[end:]
# Install only AFTER NVIDIA removes server packages (including libaio1t64).
needle='  - curtin in-target -- apt clean -y\n'
assert s.count(needle)==1
s=s.replace(needle,needle+'''  # Local packages; remaining dependencies come from NVIDIA's signed ISO repo.
  - curtin in-target -- /bin/bash -ec 'DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends /tmp/cdrom/qdma/packages/*.deb pciutils device-tree-compiler'
  - curtin in-target -- /bin/bash -ec 'test "$(dpkg-query -W -f=\\${Version} nvidia-l4t-kernel)" = 6.8.12-tegra-39.2.1-20260806224157; depmod -a 6.8.12-1021-tegra; mkdir -p /opt/orin-nvidia-build; cp /tmp/cdrom/qdma/{README.md,module-abi.json,release.env,compiler.txt,modinfo.txt} /opt/orin-nvidia-build/'
''')
# Fail the installation if later changes remove any required QDMA component.
final='  - curtin in-target -- rm -f /tmp/CHROOT_KVER\n'
assert s.count(final)==1
s=s.replace(final,'''  - curtin in-target -- /bin/bash -ec 'dpkg-query -W -f=\\${Status} orin-qdma-nvidia | grep -qx "install ok installed"; test -s /lib/modules/6.8.12-1021-tegra/extra/qdma-pf.ko; test -s /usr/src/qdma/linux-kernel/Makefile; test -s /usr/share/qdma/pcie/pci0-clock-request.dtbo; for tool in dma-ctl dma-from-device dma-to-device dma-xfer dma-perf dma-latency; do /usr/bin/$tool --help >/dev/null; done'
'''+final)
# The original command hides apt failures behind an echo; make failure fatal.
s=s.replace('DEBIAN_FRONTEND=noninteractive RUN_FW_UPDATER=no apt-get install', 'set -e; DEBIAN_FRONTEND=noninteractive RUN_FW_UPDATER=no apt-get install')
p.write_text(s)
p=iso/'boot/grub/grub.cfg'; s=p.read_text()
start=s.index('    menuentry "Install on NVMe"')
end=s.index('    menuentry "Install on USB"',start)
entry=s[start:end].replace('Install on NVMe','ERASE NVMe: install NVIDIA R39.2.1 + QDMA (P3509 only)')
rescue=s[s.index('    menuentry "Boot Into Rescue Shell"'):s.index('\n}\n\nmenuentry')]
p.write_text('set timeout=-1\nset default=0\ninsmod gzio\n'+entry+rescue+'\nmenuentry "UEFI Firmware Settings" {\n    fwsetup\n}\n')

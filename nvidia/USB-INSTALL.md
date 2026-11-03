# NVIDIA R39.2.1 + QDMA USB installer — P3509 / Orin NX 16 GB

This custom NVIDIA ISO installs Ubuntu 24.04 / L4T R39.2.1, NVIDIA's ISO
package selection, and our QDMA tools, PF module, patched sources, native build
prerequisites and optional PCIe overlay tools. Its package selection follows the
NVIDIA ISO; it is not a byte-for-byte copy of the BSP sample rootfs or the Yocto
image. PCIe experiments are not enabled automatically.

## Requirements

Use only the P3509-A02 carrier with P3767-0000 Orin NX 16GB, already flashed with
compatible R39.2.1 P3509 boot firmware. This USB preserves QSPI firmware; it
cannot provision blank firmware. For blank devices or other firmware versions,
first use the P3509 recovery flash procedure in README.md. The installer checks
that the firmware's TegraPlatformSpec names p3509-a02-p3767-0000 before touching
storage. A failed check stops installation; do not bypass it blindly.

## Install

1. Back up the Orin's NVMe. Installation erases the entire internal nvme0n1.
2. Plug the installer into the Orin's USB-A port, connect HDMI and a keyboard.
3. Power on, press Esc for UEFI, then choose the USB from Boot Manager.
4. The menu waits indefinitely. Select **ERASE NVMe: install NVIDIA R39.2.1 +
   QDMA (P3509 only)** only when ready to erase the internal disk.
5. Follow NVIDIA's installer prompts. Wait for completion/shutdown; do not
   interrupt installation. Remove the USB while powered off, then power on.
6. Complete NVIDIA's initial user setup. Check `uname -r` (6.8.12-1021-tegra),
   `dpkg-query -W orin-qdma-nvidia`, `dma-ctl --help`, and HDMI output.
7. Read `/usr/share/qdma/pcie/README.md` before enabling the optional overlay.
   QDMA sources are in `/usr/src/qdma/linux-kernel`.

Boot Into Rescue Shell is for diagnostics, not a persistent desktop environment.
The ISO repository remains NVIDIA-signed. Project packages are included as local
.deb files, with artifact integrity checked during ISO creation and USB readback.

## Firmware updates

The installed marker
`/opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall` deliberately
prevents generic NVIDIA bootloader package updates. Leave it in place for this
carrier; manage QSPI updates with the P3509 recovery-flash workflow. Stock ISO
capsules do not provide this carrier's configuration. Normal OS package updates
are separate, but a kernel update may require rebuilding the QDMA module.

## Recreate

Run `sudo ./nvidia/scripts/build-installer-iso.sh` from the repository root after
`./nvidia/run prepare`. Then write the resulting ISO with:

```
sudo ./nvidia/scripts/write-installer-usb.sh nvidia/work/orin-nvidia-qdma-r39.2.1.iso /dev/disk/by-id/usb-YOUR_DISK --erase
```

Requires curl, xorriso, squashfs-tools, loop-mount support, Python3/PyYAML and a prepared release.
The write script refuses mounted disks, requires a USB by-id path, and verifies
all ISO bytes after writing. Hardware installation testing remains a separate
step; offline validation cannot prove successful target boot or FPGA transfers.

The USB ESP boots the supplied Canonical shim directly instead of NVIDIA's
pre-installer capsule launcher. Generic capsules and the ISO firmware-detection
marker are removed. EFI executable signatures are unchanged. This is a custom
NVMe installer, not an unmodified NVIDIA ISO, and needs hardware validation.

## If installation stops early

An early board or target-check failure occurs before curtin starts, so
`/var/log/installer/curtin-install.log` may not exist. Note the displayed error.
The installer may save logs on the USB's `writable` partition under
`install-logs-*/log/`; preserve those before rewriting the stick. In the installer
shell, `/var/log/syslog` and `subiquity-server-debug.log*` under
`/var/log/installer/` are useful for early-command errors.

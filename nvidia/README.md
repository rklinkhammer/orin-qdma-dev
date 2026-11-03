# NVIDIA reference Ubuntu/L4T + QDMA (separate from Yocto)

The parent `orin-qdma-dev` project builds QDMA against Yocto/meta-tegra. It does
**not** build the default NVIDIA Ubuntu distribution. This additive workflow
uses NVIDIA's Jetson Linux R39.2.1 BSP and sample Ubuntu 24.04 root filesystem,
runs NVIDIA `apply_binaries.sh`, and adds QDMA as an ARM64 Debian package.
NVIDIA's kernel, bootloader, firmware and carrier configuration remain the
reference release. This is a customized NVIDIA image, not an unmodified stock
release or a rebuild of all proprietary NVIDIA software.

Target: Orin NX 16 GB P3767-0000 / P3509, board `p3509-a02-p3767-0000`.
The kernel ABI is **6.8.12-1021-tegra**, different from the Yocto kernel's
`6.8.12-l4t-r39.2.1-1021.21`. Never copy the Yocto QDMA module into this image.

## Build

From the repository root, on an x86-64 Linux host with Docker and ARM64
binfmt/QEMU support:

```sh
./nvidia/run container
./nvidia/run emulation
./nvidia/run baseline
./nvidia/run inspect
./nvidia/run build
./nvidia/run prepare
```

`NVIDIA_WORK` can select another absolute output directory (allow 80 GB for
baseline, customization and subsequent flash image generation).
`NVIDIA_REFERENCE` optionally selects an existing downloaded NVIDIA tree; it is
mounted read-only. Default: `~/workspace/jetson-nvidia-r39.2.1`.

`baseline` reconstructs `nvidia/work/Linux_for_Tegra` from the two pinned NVIDIA
archives and applies vendor binaries. It refuses to overwrite an existing tree.
The `emulation` step registers only ARM64 binfmt using a privileged one-shot
container; normal builds have no device access. If extraction completed but
`apply_binaries.sh` failed, fix its cause and retry with
`./nvidia/run apply-binaries`. An incomplete extraction must be inspected and
moved aside before retrying `baseline`.
The archive SHA-256 pins in release.env were recorded from the earlier local
NVIDIA download; they are integrity pins, not NVIDIA-published signatures.
Downloads stay in `work/downloads`.

`build` fetches Xilinx dma_ip_drivers at the pinned revision, applies the five
project patches copied from jetson-yocto-qdma, cross-compiles all six utilities,
and builds the PF module against NVIDIA's shipped config/Module.symvers. The
module's kernel release and every imported symbol CRC are checked. Artifacts,
logs, compiler information and an ARM64 `.deb` are under `work/latest`.
The package contains the patched QDMA Linux sources, tools, kernel module and
optional PCIe overlay. Installation does not run modprobe; normal PCI modalias matching may load the
driver on the target when matching hardware is present.

`prepare` installs that package and native development prerequisites into the
new NVIDIA rootfs, refreshes module dependencies and records package evidence.
It verifies NVIDIA's kernel images were not replaced. The output remains the
standard `Linux_for_Tegra` layout, usable with NVIDIA's flashing scripts.

NVIDIA's sample rootfs/BSP is not the entire JetPack compute SDK. CUDA, cuDNN and
TensorRT packages are not silently borrowed from Yocto or claimed installed.
If the full SDK is wanted, install `nvidia-jetpack` from the matching NVIDIA
repository on the target (requires additional space and downloads).

## Sources and PCIe configuration

The additions are a Debian customization layer, not a BitBake layer loaded into
NVIDIA's Ubuntu build. Patch provenance is the sibling `jetson-yocto-qdma`
recipes; the upstream QDMA revision is recorded in release.env.

Read the [PCIe device-tree integration guide](overlay/README.md) (installed as
`/usr/share/qdma/pcie/README.md`) for DTB selection, controller identification,
preparation, activation, verification, rollback and installer integration. It covers the optional
compiled overlay and whole-DTB/extlinux preparation. No experimental PCIe
configuration is enabled automatically. In particular, do not reuse the Yocto
merged DTB with the NVIDIA image.

## Flashing (explicit separate step)

No command above contacts or flashes a Jetson. Review all output and back up the
target before running NVIDIA flashing commands; they overwrite QSPI/NVMe.
Use the prepared tree's own scripts and P3509 configuration, for example on a
properly configured flashing host, with the Orin in recovery mode:

```sh
cd nvidia/work/Linux_for_Tegra
sudo ./tools/kernel_flash/l4t_initrd_flash.sh \
  --external-device nvme0n1p1 -c tools/kernel_flash/flash_l4t_t234_nvme.xml \
  -p '-c bootloader/generic/cfg/flash_t234_qspi.xml' \
  --showlogs --network usb0 p3509-a02-p3767-0000 external
```

Containerized hardware flashing additionally needs USB/device access and the
NFS/network setup required by NVIDIA. The normal build containers intentionally
have no device passthrough. Initial user setup is NVIDIA's default first-boot
flow; no usernames, passwords or SSH keys are embedded by this workflow.

## References

- [NVIDIA Jetson Linux archive](https://developer.nvidia.com/embedded/jetson-linux-archive)
- [NVIDIA R39.2.1 kernel customization](https://docs.nvidia.com/jetson/archives/r39.2.1/DeveloperGuide/SD/Kernel/KernelCustomization.html)
- [NVIDIA JetPack downloads](https://developer.nvidia.com/embedded/jetpack/downloads)

See VALIDATION.md for checks actually completed; build/ABI checks do not establish
FPGA transfer correctness, successful target boot, or Secure Boot compatibility.

## Bootable USB installer

See [USB-INSTALL.md](USB-INSTALL.md) for the P3509-specific NVIDIA ISO installer,
creation commands, firmware prerequisites and installation steps. It installs
the NVIDIA ISO package selection plus QDMA; it preserves existing P3509 QSPI
firmware and is separate from the recovery flash tree above.

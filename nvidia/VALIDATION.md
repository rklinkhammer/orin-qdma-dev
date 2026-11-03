# Validation record

Work performed on 2026-11-02 (America/New_York).

- Container image `orin-nvidia-qdma:r39.2.1` built on x86-64 Ubuntu host.
- Both NVIDIA R39.2.1 archives matched the recorded local SHA-256 integrity pins.
- Fresh sample Ubuntu rootfs extracted and NVIDIA `apply_binaries.sh` completed.
- All six QDMA ARM64 utilities compiled using Ubuntu GCC 13.3 and ARM64 libaio.
- QDMA PF module compiled against NVIDIA's shipped headers/config and
  Module.symvers for `6.8.12-1021-tegra`; all **139** imported symbol CRCs match.
- Negative ABI test with a deliberately wrong `pci_save_state` CRC was rejected.
- Stock NVIDIA headers record GCC 13.2.0; Ubuntu's GCC 13.3 emits a compiler
  version warning. Compile, modpost and CRC checks passed; this is not proof of
  runtime hardware compatibility.
- The generated Debian package installed into the fresh Ubuntu rootfs with
  native build-essential/libaio-dev prerequisites; APT upgraded no existing
  packages. All six installed utilities returned success for `--help` under ARM64
  emulation. DTC ran successfully.
- NVIDIA's BSP kernel Image and rootfs /boot/Image hashes were unchanged after
  customization. The stock extlinux configuration was preserved, and the
  temporary resolver/service-start suppression was restored.
- PCIe preparation test removed `nvidia,enable-power-down` from two synthetic
  controller nodes, applied the C0 boolean property, preserved C0's disabled
  status, and preserved the original extlinux boot arguments.

The kernel uses NVIDIA's variable-length `modversion_info` representation
(`u32 next`, `u32 crc`, variable name). Ubuntu's host `modprobe --dump-modversions`
could not parse it; `check-symbols.py` reads the `__versions` ELF section using
the shipped kernel header layout and compares it with the original symbol table.

Package build artifact: `work/artifacts/20261103T021836Z/orin-qdma-nvidia_arm64.deb`
(the timestamp is UTC). SHA-256:
`87b34aab01b6e8844440662ae4e7aed767bfff0694b347852d7f4ce4f26e21fb`.

Target boot, driver loading, FPGA transfers, Secure Boot/module signing and PCIe
hardware behavior have not been tested. No target has been flashed by this work.

## NVIDIA ISO installer (2026-11-02)

- Downloaded official R39.2.1 ISO; SHA-256
  `f31cf35023cd072707dfc46ef23ed71318449516333055fe3bb9455a615395d0`.
- Inspected stock installer and bootloader postinst: no P3509 capsule selection.
  Custom installer retains QSPI and its update-disable marker, with a pre-write
  P3509 TegraPlatformSpec guard and NVMe-only target selection.
- QDMA/native development package dependency simulation passed against the ISO's
  signed local repository under ARM64 emulation. No external apt source was used.
  Validation used the extracted base OS with a partial server-layer extraction;
  this establishes dependency resolution, not a full installation test.
- Installer YAML parses, shell syntax passes. Optional PCIe settings stay disabled.
- Hardware boot, NVMe installation, HDMI and QDMA hardware testing remain pending.
- Examined NVIDIA edk2-nvidia L4TPreIsoInstaller.c: the ISO's original EFI
  BOOTAA64 can stage generic firmware capsules before Linux. Final custom ESP
  uses the original signed shimaa64.efi as BOOTAA64, removes EFI/*.Cap and
  EFI/ISO_ID, and retains GRUB. This bypasses that pre-installer updater;
  compatible P3509 firmware must already exist.
- Final ISO SHA-256:
  `ecb6678023ad94f22ca535ba51580137713a8d309706f9b901b582c6c283c860`.
  All ISO media checksums passed. Wrote 5,014,181,888 bytes to SanDisk E6DC and
  verified every byte by readback. Checked the actual USB ESP: BOOTAA64 equals
  the supplied shim, GRUB exists, ISO_ID and generic capsules are absent.
  USB partitions were unmounted after verification. The unused remainder of
  the 115 GB stick is intentional for this fixed-size ISO image.

## Installer target-guard correction

The first USB reached the installer but the user reported installation failure.
Code review found a definite pre-partition guard bug: NVIDIA's
sanitize_force_bootdisk_input converts nvme0n1 into /dev/nvme0n1, (including the
trailing comma). The custom guard rejected this form. Corrected it to accept the
single NVMe target in both forms while rejecting other or multiple disks.
Regression test executes NVIDIA's actual sanitizer plus the generated guard;
NVMe forms pass, USB/other NVMe/multiple targets fail. The user error log is
still needed to establish whether there are additional failures.
Corrected ISO rebuilt and all media checksums passed. SHA-256:
`66395dd7681905fc39fbcfc1c907df8f1cea59b05b2123eff746aa8098eacf56`.
The previously written USB still contains the first image until rewritten.

Recovered the first failed boot's saved logs from USB partition 4 before
rewriting it (work/failed-install-first). Actual first failure: tail could not
seek in the TegraPlatformSpec efivarfs file (Illegal seek). Changed that read
to dd bs=1 skip=4, matching NVIDIA's own reader. The failure occurred before
partitioning. The NVMe normalization defect would have been the next failure.

Final correction written to SanDisk E6DC on 2026-11-02; 5,014,181,888 bytes
verified by complete USB readback, partitions unmounted. ISO SHA-256:
`dc1c7e6ac625afc3cf9eb10adbe742ba67bdd5c0b1ec0d94a7df95e5fc142159`.
Both the non-seekable firmware reader and NVIDIA's real target sanitizer pass
regression tests. Successful target installation remains to be tested.

## QDMA removal after successful ISO installation — fixed 2026-11-02

Target apt history confirmed that the first installer installed orin-qdma-nvidia,
then NVIDIA's server cleanup purged libaio1t64, libaio-dev and orin-qdma-nvidia.
Moved the QDMA/local-development-package installation after that cleanup and
added final installed-status/module/source/overlay/utility-startup checks.
The generated-YAML regression test rejects the old order and passes the new one;
the ISO builder now runs it before packaging.

Rebuilt QDMA against the NVIDIA headers (139 imported symbol CRCs match), including
the expanded PCIe README. Repaired the running Orin through its USB console and
USB network using checksummed local packages. Exactly three packages installed,
no upgrades/removals: libaio1t64, libaio-dev, orin-qdma-nvidia. Package file
verification passed. All six utilities start, and all six rebuilt from the
shipped sources on the Orin. Native compilation emitted warnings including clock
skew because the target clock is incorrect; build commands returned success.
The PF module loaded with matching vermagic. It is unsigned and taints the kernel;
Secure Boot/module signing is not validated. No Xilinx PCIe function enumerated,
so FPGA DMA transfers were not tested. No PCIe overlay was activated.

New package SHA-256:
`eea5fde72474feb26b42e72224b3d8eff7a0f901de9644e8dec5ed147cad627c`.
New ISO SHA-256:
`fbebd2dcf7c528f2d3a5208b0f92b7a91ba1e3ff3a4285e3adfb60b28e671d5d`.
ISO media checksums passed. Installer USB rewrite and a complete new installation
with this ISO remain pending until the stick is returned to the host.

The corrected QDMA installer ISO was subsequently written to SanDisk E6DC on
2026-11-02. All 5,014,185,984 bytes matched the ISO on USB readback. The USB was
left unmounted and ready to remove. A new full installation from this corrected
USB has not yet been tested; the running Orin repair and native utility rebuild
were verified separately above.

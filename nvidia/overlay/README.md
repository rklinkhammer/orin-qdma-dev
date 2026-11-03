# PCIe device-tree integration for NVIDIA R39.2.1

This guide covers selecting the base device tree, preparing and activating the
PCIe changes, verifying them, rolling back, and including them in an installer.
It applies to the NVIDIA Ubuntu/L4T workflow in `orin-qdma-dev/nvidia`, not the
older Yocto kernel image.

The release packages the PCIe source, compiled overlay, this README and the
preparation helper in `/usr/share/qdma/pcie/`. They are **not activated by
installation**. This updated README will enter that package on its next build;
editing the repository does not update an already-built package or USB.

## 1. Hardware and release context

The current build targets Orin NX 16 GB (P3767-0000) on the P3509-A02 carrier,
using NVIDIA board configuration `p3509-a02-p3767-0000`, L4T R39.2.1 and kernel
`6.8.12-1021-tegra`. The previous Yocto kernel had a different ABI. Do not copy
its kernel modules or merged DTB into this NVIDIA release.

A module and a carrier are separate parts of the hardware configuration.
Carrier wiring determines PCIe lanes, USB roles, display connections, GPIO and
power controls. A custom board that follows a devkit may use its configuration,
but the engineer's working BSP/DTB and actual wiring are the evidence to use.
The other board's exact configuration has not yet been independently verified.

The general NVIDIA installer does not provide every possible carrier's firmware.
Our downloaded BSP includes a P3509 configuration, but the stock ISO bootloader
package does not select a P3509 firmware capsule. Our custom installer therefore
preserves existing compatible P3509 QSPI firmware. See the NVIDIA workflow's
`USB-INSTALL.md` for installation and `README.md` for recovery flashing.

When moving an SSD between systems, its OS, kernel, initrd, DTB files and extlinux
configuration move with it. The module's QSPI firmware does not. A proven SSD
transfer workflow is useful evidence of compatibility, but matching L4T boot
files, module firmware and carrier configuration are still required. A full DTB
selected by FDT also travels with the SSD and must suit the destination board.

## 2. What the PCIe changes do

The included source is `pci0-clock-request.dts`:

```dts
/dts-v1/;
/plugin/;

/ {
    fragment@0 {
        target-path = "/bus@0/pcie@14180000";
        __overlay__ {
            // Preserve controller status; add the requested boolean property.
            nvidia,disable-clock-request;
        };
    };
};
```

The preparation helper performs two operations:

1. Removes `nvidia,enable-power-down` from every node where it exists in the
   supplied base DTB (not just PCI nodes).
2. Compiles and applies the overlay adding `nvidia,disable-clock-request` to C0.

Comments remain in the DTS source; they are not retained in a compiled DTB.
The overlay does not enable a disabled controller, change lane routing or load
the QDMA driver. These settings request driver behavior; hardware testing is
needed to establish the resulting link/power behavior.

**C0 is not synonymous with Linux PCI bus 0.** The existing snippet targets
`/bus@0/pcie@14180000`. Its presence in a SoC tree does not establish that it is
exposed on the module or routed to the FPGA. Orin NX/Nano external PCIe routes
include C1, C4, C7 and C9 subject to carrier/UPHY configuration. Identify the
FPGA's actual controller before using this experiment.

Useful inspection commands on the target:

```bash
lspci -Dnn
lspci -tv
find /sys/firmware/devicetree/base -type d -name 'pcie@*'
# Replace the example BDF with the FPGA's BDF from lspci:
readlink -f /sys/bus/pci/devices/0000:01:00.0
```

Trace the device's sysfs ancestry to its platform PCIe controller, and compare
with the carrier schematic. If a different controller is required, change both
the DTS target and the helper's hard-coded C0 verification/path naming before
building a new package. Merely editing the DTS would leave its C0 check wrong.

## 3. Select the complete matching base DTB

Choose by **module + carrier + NVIDIA release**, not by PCI bus number or the
first DTB filename in `/boot`.

Run these commands on the installed NVIDIA system:

```bash
cat /etc/nv_tegra_release
uname -r
tr '\0' '\n' < /proc/device-tree/model
tr '\0' '\n' < /proc/device-tree/compatible
grep -E '^[[:space:]]*(LABEL|FDT|OVERLAYS|FDTOVERLAYS)[[:space:]]' \
  /boot/extlinux/extlinux.conf
ls -l /boot/dtb/
```

If the selected boot entry has an FDT directive, that is the requested base file.
Account for any additional overlays. If there is no FDT entry, firmware supplies
the tree. A file in `/boot/dtb/` is only a candidate; its presence does not prove
it is the complete tree in use. Firmware can also fall back when a requested
file is missing, so check the running tree after changes.

For our P3509 / P3767-0000 configuration, NVIDIA starts with:

```text
tegra234-p3768-0000+p3767-0000-nv.dtb
```

The `p3768` filename alone does not make it unsuitable for P3509: the P3509
configuration sources that base configuration and adds HDMI-specific pinmux,
pad-voltage configuration and `tegra234-dcb-p3767-0000-hdmi.dtbo`. Other overlays
are inherited from the BSP configuration as well.

**Do not use that raw DTB alone as a complete replacement.** Obtain the matching
complete kernel DTB from the P3509 flash build, accounting for the board's full
applicable overlay list and firmware processing. Check `DTB_FILE`,
`OVERLAY_DTB_FILE`, the generated flash artifacts and logs. Do not assume that
applying only the HDMI overlay reconstructs every boot-time change. Pinmux/BCT
settings in boot firmware are separate from kernel-DTB merging.

Inspect a candidate and compare it with the live tree:

```bash
fdtget /path/to/candidate.dtb / model
fdtget /path/to/candidate.dtb / compatible
dtc -I dtb -O dts -o /tmp/candidate.dts /path/to/candidate.dtb
sudo dtc -I fs -O dts -o /tmp/running-device-tree.dts \
  /sys/firmware/devicetree/base
```

Matching model/compatible strings is necessary evidence, not a complete
validation. Compare display, PCIe, USB and controller status as well. The live
dump contains firmware-supplied runtime data: use it for inspection, not blindly
as a reusable boot DTB. No final complete base DTB has yet been selected and
validated for this PCIe experiment.

## 4. Prepare the files without changing boot

The release includes `dtc`, `fdtoverlay`, `fdtget`, `fdtput`, Python and PCI tools.
In a writable directory on the target, run:

```bash
python3 /usr/share/qdma/pcie/prepare-pcie.py \
  --base /path/to/complete-matching-board.dtb \
  --extlinux /boot/extlinux/extlinux.conf \
  --output ./pcie-experiment
```

Replace the base path with the reviewed DTB. The output directory must not
already exist. The helper creates:

| File | Purpose |
| --- | --- |
| `base-original.dtb` | Copy of the selected input |
| `base-no-power-down.dtb` | Input with the power-down property removed |
| `pci0-clock-request.dts` | Editable overlay source |
| `pci0-clock-request.dtbo` | Compiled overlay |
| `pcie-c0-no-power-down.dtb` | Final merged DTB |
| `extlinux.conf.original` | Original boot configuration |
| `extlinux.conf` | Prepared configuration selecting the merged DTB |
| `verification.json` | Removed-property node paths, node count and DTB hash |

Ordinary dtc/fdtoverlay merging does not encode arbitrary base-property deletion
from a `/delete-property/` source directive into a runtime overlay. That is why
this helper removes the property directly from the base before merging. This
does not imply that all NVIDIA-specific firmware overlay extensions have the
same limitations.

The helper refuses existing overlay directives and multiple active LABEL entries
rather than trying to merge them automatically. A refusal can leave preparation
files in the output directory; do not activate a partial result. Review the
configuration manually and use a fresh output directory for another attempt.

```bash
cat pcie-experiment/verification.json
diff -u pcie-experiment/extlinux.conf.original pcie-experiment/extlinux.conf
fdtget -p pcie-experiment/pcie-c0-no-power-down.dtb /bus@0/pcie@14180000
```

## 5. Activate a reviewed experiment

For these kernel properties, installation uses files on the NVMe and a reboot;
recovery mode is not normally required. Have a way to restore the boot file if
the experiment prevents boot. These commands assume the helper completed and
its base/controller choices have been reviewed.

```bash
backup="/boot/extlinux/extlinux.conf.before-pcie-$(date +%Y%m%d-%H%M%S)"
sudo cp -a /boot/extlinux/extlinux.conf "$backup"
printf 'Keep this rollback path: %s\n' "$backup"
sudo install -d /boot/dtb
sudo install -m 0644 pcie-experiment/pcie-c0-no-power-down.dtb \
  /boot/dtb/pcie-c0-no-power-down.dtb
sudo install -m 0644 pcie-experiment/extlinux.conf /boot/extlinux/extlinux.conf
sync
```

The generated entry retains the existing kernel, initrd and APPEND parameters
and adds:

```text
FDT /boot/dtb/pcie-c0-no-power-down.dtb
```

Keep the original boot artifacts. For repeatable development, a separately
reviewed fallback LABEL using the original configuration is useful; the helper
does not generate that fallback. Reboot when ready.

For an additive-only experiment, NVIDIA also supports an entry such as:

```text
OVERLAYS /boot/dtb/pci0-clock-request.dtbo
```

That method applies an overlay to the kernel tree and does not by itself perform
our whole-tree power-down-property removal. Do not add it on top of the already
merged-DTB workflow above. Flash-configuration `OVERLAY_DTB_FILE` is a separate
integration point affecting firmware and kernel trees and requires generating
and deploying the appropriate firmware artifacts.

## 6. Verify after reboot and roll back

For the current C0 experiment:

```bash
find /sys/firmware/devicetree/base -name nvidia,enable-power-down -print
test -e /sys/firmware/devicetree/base/bus@0/pcie@14180000/nvidia,disable-clock-request \
  && echo 'C0 clock-request property present'
lspci -Dnn
sudo dmesg | grep -Ei 'pcie|qdma|aer'
```

The first command should print nothing. Also confirm the FPGA enumerates under
the intended controller and perform the relevant QDMA transfers/link checks.
Successful DTB compilation or property presence alone does not prove hardware
behavior. Firmware may modify the tree before Linux receives it.

To roll back, restore the exact backup path printed during activation:

```bash
sudo cp -a /boot/extlinux/extlinux.conf.before-pcie-YOUR-TIMESTAMP \
  /boot/extlinux/extlinux.conf
sync
sudo reboot
```

If the system cannot boot, restore that file by mounting the NVMe from another
Linux environment. Preserve existing filesystem UUIDs and boot parameters.

## 7. Integrate into a release or USB installer

Current behavior: the QDMA Debian package installs the tools/source/DTBO under
`/usr/share/qdma/pcie/`; it does not change the boot selection. Our USB installs
that package, leaving the PCIe experiment disabled.

After validating the complete DTB and the correct controller on hardware:

1. Version the DTS, base-DTB provenance, applicable carrier overlays and checksums.
2. Generate and validate the merged DTB during release preparation.
3. Install it under the target filesystem's `/boot/dtb/`.
4. Update the target's actual extlinux entry after the installer generates it,
   retaining that installation's root PARTUUID, boot arguments and fallback.
5. Rebuild the installer, then test installation, reboot and QDMA operation.

Do not bake a donor machine's root PARTUUID into every installation. DTB assets
and boot selection travel with a moved SSD; verify they suit the destination
carrier. Kernel/BSP upgrades require reviewing the base tree again. A custom
board needing different early boot pinmux/UPHY settings also needs matching
firmware; a kernel overlay alone cannot provide those changes.

## References

- [NVIDIA R39.2.1 Orin NX/Nano adaptation, DTB selection and overlays](https://docs.nvidia.com/jetson/archives/r39.2.1/DeveloperGuide/HR/JetsonModuleAdaptationAndBringUp/JetsonOrinNxNanoSeries.html)
- [NVIDIA R39.2.1 ISO customization](https://docs.nvidia.com/jetson/archives/r39.2.1/DeveloperGuide/SD/JetsonISOCustomization.html)
- Repository files: `nvidia/scripts/prepare-pcie.py`,
  `nvidia/overlay/pci0-clock-request.dts`, `nvidia/USB-INSTALL.md`,
  `nvidia/VALIDATION.md`.

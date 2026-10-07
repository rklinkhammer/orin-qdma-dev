# Orin NX QDMA host development

Project: `/Volumes/Zeus/workspace/orin-qdma-dev`. This is independent of
`/Volumes/Zeus/workspace/edf-dev`; no EDF project, image, volume or container is
modified. The RFSoC/UltraScale endpoint is supplied separately. There are no FPGA,
bitstream, hardware flashing or repository-push operations here.

The pinned baseline is **Yocto 6.0.3 Wrynose / NVIDIA Jetson Linux R39.2.1 GA /
JetPack 7.2.1 / NVIDIA kernel 6.8.12**. [BASELINE.md](BASELINE.md) records official
compatibility sources and exact commits. The provisional compile target is
**Orin NX 16 GB P3767-0000 on NVIDIA P3768 carrier**, `p3768-0000-p3767-0000`.
The actual module SKU and carrier must be confirmed before hardware integration.

Actual Yocto compilation is complete: all six ARM64 tools and their IPKs passed
package QA; the PF module passed compile, real-symbol modpost and staged install.
All 139 imported symbol CRCs match the finished kernel. Final artifacts and
evidence are under `artifacts/p3768-0000-p3767-0000/yocto/`; see [VALIDATION.md](VALIDATION.md).

This follows the inspected EDF conventions: OrbStack context, amd64 Linux
container on Apple Silicon, UID/GID 1000, Linux named volumes for source/build and
caches, read-only project scripts/config/layer mounts, and explicit host exports.
EDF has no devcontainer configuration to copy. Ubuntu 24.04 provides the Python
3.12 environment supported by Wrynose. It is pinned by image digest and uses
signed Ubuntu package repositories; an installed package inventory is exported.

## Start and build

```sh
cd /Volumes/Zeus/workspace/orin-qdma-dev
./orin build-container
./orin validate
./orin sync
./orin patch       # real recipe fetch/unpack/patch validation
./orin check       # dry-run only; never counts as compilation
./orin tools       # complete Yocto userspace recipe/packages
./orin kernel      # focused Yocto kernel compile task
./orin driver      # Yocto kernel/modules + QDMA compile and staged install
./orin export      # binaries, IPKs, kernel/ABI/compiler/log evidence + hashes
./orin shell
```

Inside the shell, `source /opt/orin-scripts/yocto-env.sh` initializes BitBake.
Use the launcher for ordinary builds so locks and cancellation are managed.
Direct BitBake commands bypass the wrapper's source/build locks.

To change reference machine after the carrier is identified:

```sh
./orin tools p3509-0000-p3767-0000
# Or export ORIN_MACHINE=<supported-meta-tegra-machine> before commands.
```

Each machine has its own `builds/<MACHINE>/conf` and `tmp`. Local overrides go in
that build's `conf/orin-policy.conf`, which the wrapper never overwrites. Do not
edit recipe/config/patch files while BitBake is active: that invalidates hashes.
Source sync refuses concurrent builds and uncommitted source changes.

The direct compiler preflight uses Ubuntu's GCC 13.3 cross compiler, not the
Yocto GCC 15.3/glibc 2.43 toolchain. It is useful for finding architecture and C
build failures quickly and is separately labelled:

```sh
./orin smoke-tools
./orin smoke-kernel  # pinned NVIDIA GPL sources, ARM64 defconfig + QDMA fragment
./orin smoke-driver  # requires full kernel Module.symvers; fails if missing
```

An earlier object check can run after `smoke-kernel` creates its `.config`, using
its own kernel output directory and a separate QDMA clone:

```sh
ORIN_CPUS=1 docker --context orbstack compose run --rm --no-deps -T shell \
  /opt/orin-scripts/object-preflight.sh
```

It exports `object-preflight/qdma-pf.o`. It compiles all PF sources with upstream
`-Werror`, but does not run modpost or create an installable module.

Do not install smoke artifacts into an existing Jetson OS. A module must match
the deployed kernel configuration, symbol CRCs, version and signing policy.
The verified smoke kernel uses ARM64 defconfig with 4 KiB pages, not the eventual
carrier-specific Yocto kernel configuration. Kernel evidence is exported to
`artifacts/<MACHINE>/smoke-kernel/`; the final PF module is in `smoke-driver/`.

If the client disconnects, detached builds may continue. Inspect this project's
existing containers before launching another build:

```sh
docker --context orbstack compose ps --all
docker --context orbstack logs --follow <existing-orin-qdma-dev-container>
docker --context orbstack wait <existing-orin-qdma-dev-container>
```

`docker wait` reports the container exit code. Persistent volumes retain all
source/build/cache state. The per-machine lock rejects duplicate builds.

## Persistent state and limits

| Volume or mount | Container path | Purpose |
| --- | --- | --- |
| `orin-qdma-dev_workspace` | `/home/yocto/orin` | Pinned sources, per-machine build trees and smoke builds |
| `orin-qdma-dev_downloads` | `/home/yocto/orin/downloads` | Yocto `DL_DIR` |
| `orin-qdma-dev_sstate-cache` | `/home/yocto/orin/sstate-cache` | Local sstate and shared hash-equivalence database |
| `scripts/`, `config/`, `layers/` | `/opt/orin-{scripts,config,layers}` | Read-only project inputs |
| `artifacts/` | `/artifacts` | Exported binaries, source manifest and container inventory |

No caches are shared with EDF. Container removal preserves named volumes. No
existing storage is deleted by the scripts. Builds use at most four CPUs per
container, a 10 GiB container memory limit, two BitBake tasks/parse workers and
`make -j4`. `ORIN_CPUS=1 ./orin tools` can reduce the per-container CPU cap
when EDF is busy; avoid several heavy builds at once. Disk guards stop scheduling below 25 GiB and halt below 15 GiB.
Remote sstate and upstream hash services are disabled. The root init service only
owns the three new volume roots with `CHOWN`; builds run as `yocto` UID 1000.
All builds drop capabilities and keep `no-new-privileges` enabled.

## QDMA integration

`layers/meta-orin-qdma` contains two same-revision recipes pinned to Xilinx
`dma_ip_drivers` commit `b8466090b4e812e191da9e9305ffb11cb7ace768`:

- `qdma`: PF-only module `qdma-pf.ko`; passes ARM64, target compiler, kernel source
  and object directories. Its install task copies into `${D}${nonarch_base_libdir}/modules/...`;
  it never executes upstream host `uname` installation or host `depmod`.
- `qdma-tools`: `dma-ctl`, `dma-from-device`, `dma-to-device`, `dma-xfer`,
  `dma-perf`, `dma-latency`, with target libaio. It builds each binary sequentially
  and avoids upstream `all: clean` races over shared `dma-utils` objects.

Small patches replace x86 RDTSCP with `ktime_get_ns()` for both TX and IRQ RX,
replace obsolete `SUBDIRS=` with Kbuild `M=`, preserve userspace linker flags, and
fix a real glibc FORTIFY failure where `O_CREAT` lacked a file mode. Ping-pong
latency statistics now use nanoseconds; same-revision `dma-ctl` labels them
accordingly. Do not apply upstream TSC/CPU-frequency conversion instructions.
Endpoint loopback must echo the timestamp bytes unchanged for that test.

The actual Yocto build also exposed upstream recursive `MAKEOVERRIDES` filtering
corrupting compiler commands containing spaces. A third driver patch preserves
GNU make's escaping, and the recipe clears userspace compiler flags before the
kernel build. GCC 15.3 compilation and upstream `-Werror` now pass.

The actual kernel release is `6.8.12-l4t-r39.2.1-1021.21`, with 4 KiB pages and
module versioning enabled. Its config differs from smoke in 32 symbols. OE4T's
supplied kernel fragment disables module signing; select and validate the board's
intended signing policy before deployment. The exported `module-abi-check.json`
records the release match and every imported symbol CRC check.

The kernel config fragment enables modules, PCI/MSI and ARM SMMU support. It does
not change IOMMU/security policy or carrier PCIe/UPHY/device-tree routing.
The driver is not configured to auto-load.

## License and deployment boundary

No new license acceptance is implied by this project. The default policy rejects
`Proprietary` target/native/SDK recipes and accepts no license flags. The custom
distro avoids the demo distro's automatic codec acceptances.

The normal module packaging graph asks for kernel package metadata, which pulls
kernel `do_deploy` and NVIDIA `tegra-flashtools-native`. `driver` deliberately
stops at the staged install task so focused open-source compilation can proceed.
Full packaging/image/deployment requires separate approval for the NVIDIA
agreement linked in [BASELINE.md](BASELINE.md). There is no flash command.

## Validation and hardware follow-up

See `VALIDATION.md` for actual results and logs. A dry-run, object compile,
successful module modpost, Yocto recipe build and hardware test are distinct
milestones. No hardware test has been performed on this Mac.

Before using the driver on a board, confirm module RAM SKU, carrier and PCIe
controller/lane wiring; endpoint QDMA IP revision, PCI IDs, BAR map, PF/VF mode,
queue layout and MSI-X vectors; and the deployed kernel/signing configuration.
Hardware validation must cover enumeration/MSI-X, DMA address width, coherent and
noncoherent paths, SMMU mappings, user-page pin/unpin lifetime, cache synchronization,
aligned and unaligned transfers, resets and sustained concurrent traffic. Keep
IOMMU enabled while investigating mapping failures. These are runtime integration
risks beyond compiler validation.

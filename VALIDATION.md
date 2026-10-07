# Build validation

Results are updated as real tasks finish. Artifact paths are relative to this
project. The reference machine is `p3768-0000-p3767-0000`.

| Check | Result / evidence |
| --- | --- |
| Independent EDF setup inspection | Actual Compose project found at `/Volumes/Zeus/workspace/edf-dev`; original configuration hashes in `validation/edf-dev-before.sha256` |
| Container build | Passed; `validation/container-build.log`, `artifacts/container-image.json`, `artifacts/container-packages.tsv` |
| Compose configuration | Passed `docker --context orbstack compose config --quiet` |
| Non-root user, architecture, mounts, cache writability | Passed `./orin validate`; `validation/validate.log` |
| Source pins | Verified; `artifacts/manifest.txt`, `config/versions.sh` |
| Project shell/Python syntax | Passed `bash -n` for launcher/scripts and `python3 -m py_compile` for Python helpers |
| Direct ARM64 userspace compile/link | Passed all six tools with GCC 13.3; `validation/p3768-0000-p3767-0000-smoke-tools.log` |
| ELF architecture and dynamic dependencies | Passed `file` and `aarch64-linux-gnu-readelf -h/-d`; same log; binaries under `artifacts/p3768-0000-p3767-0000/smoke-tools/` |
| ARM64 utility startup | Passed all six `-h` calls with exit 0 and a 5-second timeout, in Linux; `validation/tool-help-runtime.log`; this is no hardware test |
| Tool hashes | Recorded in `validation/smoke-tools.sha256` |
| Direct ARM64 QDMA PF object compile/link | Passed all 31 source objects with upstream `-Werror`; AArch64 `qdma-pf.o` exported under `artifacts/<MACHINE>/object-preflight/`; `validation/p3768-0000-p3767-0000-object-preflight.log` and `validation/object-preflight.sha256`; this isolated object check does not run modpost |
| Smoke kernel configuration | Actual `.config` confirms modules, PCI/MSI, IOMMU and both ARM SMMU options enabled; `validation/smoke-kernel-config-evidence.txt` |
| Focused Yocto dry-run graphs | Passed tools (1054 tasks) and driver staged install (903 tasks), no flash-tool entries or errors; `validation/p3768-0000-p3767-0000-check.log` |
| Actual Yocto fetch/unpack/patch | Passed both recipes, 108 real tasks (104 reused); corrected `${BP}` layout and patches verified with BitBake/quilt |
| NVIDIA GPL kernel Image/modules compile | Passed, exit 0; `validation/p3768-0000-p3767-0000-smoke-kernel.log`, `validation/smoke-kernel-exit.txt`; Image/config/System.map/21,045-symbol Module.symvers plus source/compiler/ELF evidence and SHA256SUMS exported under `artifacts/<MACHINE>/smoke-kernel/` |
| QDMA full module compile/modpost/link | Passed, exit 0; real kernel symbols and upstream `-Werror`; AArch64 `qdma-pf.ko` exported under `artifacts/<MACHINE>/smoke-driver/`; module version `2025.2.0.0`, vermagic `6.8.12+ SMP preempt mod_unload modversions aarch64`; `validation/p3768-0000-p3767-0000-smoke-driver.log`, `validation/smoke-driver-elf.txt`, `validation/smoke-driver.sha256` |
| Yocto tools compile/package QA | Passed, exit 0: all 1054 tasks succeeded (104 reused), including compile, install, package QA and IPK generation; `validation/p3768-0000-p3767-0000-tools.log`, `validation/tools-container-state.json` |
| Actual Yocto target utility startup | Passed all six help-only calls with exit 0 and a 5-second timeout using the matching Yocto glibc 2.43 AArch64 loader/libraries; `validation/yocto-tools-help-runtime.log`; no device I/O |
| Actual Yocto kernel configuration/compiler | Config merge/configure/configcheck, Image and configured kernel modules passed. GCC 15.3.0 / binutils 2.46.1; release `6.8.12-l4t-r39.2.1-1021.21`. 4 KiB pages, MODVERSIONS, PCI/MSI, IOMMU, ARM SMMU/SMMUv3 enabled. Actual logs/config/Image/System.map/21,041-symbol Module.symvers exported under `artifacts/<MACHINE>/yocto/` |
| Yocto driver compile/modpost/staged install | Passed with upstream `-Werror`; all 903 tasks succeeded (895 reused) after the compiler-override fix. `validation/p3768-0000-p3767-0000-driver.log`; actual compile/install logs in `artifacts/<MACHINE>/yocto/logs/` |
| Actual module ELF/ABI | AArch64 ELF64 relocatable module; vermagic `6.8.12-l4t-r39.2.1-1021.21 SMP preempt mod_unload modversions aarch64`; all 139 imported symbol CRCs match the finished kernel, zero missing/mismatched symbols; `yocto/module-abi-check.json` |
| Final Yocto export and checksums | Passed `./orin export` and `shasum -a 256 -c SHA256SUMS` for every exported file. Six target tools, four userspace IPKs, staged PF module, compiler/source metadata, kernel evidence and actual logs under `artifacts/<MACHINE>/yocto/` |
| Module packaging / kernel deploy / full image | Requires explicit NVIDIA agreement approval if the proprietary task chain is used |
| Driver load, PCIe/MSI-X, DMA/SMMU, endpoint transfer tests | Unrun; no Jetson hardware attached |

Compiler integration fixes found so far:

1. Git submodules store `.git` as a file; source synchronization now recognizes
   both files and directories.
2. Wrynose requires `LCONF_VERSION = "7"`; generated configuration was corrected.
3. `dma-xfer` used a two-argument `open()` with `O_CREAT`, which fails glibc
   FORTIFY. The custom-layer patch supplies mode `0666`, subject to the caller's
   umask. FORTIFY remains enabled.
4. Wrynose Git fetches unpack into `${BP}` rather than the old default `git/`;
   both recipes use the real directory layout.
5. Actual Yocto QDMA compilation exposed upstream `MAKEOVERRIDES` filtering
   corrupting a compiler command containing prefix-map flags: `LD=`, `AR=` and
   `CROSS_COMPILE=` became GCC input operands. The third driver patch preserves
   GNU make's serialization; the recipe clears userspace flags explicitly.
   The failed compiler command and successful retry are preserved in
   `validation/driver-first-attempt.log`, `validation/driver-verbose-diagnostic.log`
   and the exported actual compile log. Early malformed/context patch drafts
   failed patch QA before compilation; the final patch passed exact-revision
   `git apply --check` and BitBake patch QA.

An early dry-run changed hashes because metadata was updated during execution.
That run is not counted as successful validation. Subsequent builds keep active
metadata unchanged. The complete early graph also exposed the proprietary native
flash-tool dependency of module packaging; native license exclusion is now
explicit, and focused driver compilation uses the staged install task.

The isolated object preflight initially omitted the `modulesymfile` argument
provided by the upstream top-level Makefile. Its direct wrapper now passes the
same argument. That was a preflight setup error, not a QDMA compiler failure;
`validation/object-preflight-first-wrapper.log` preserves the first result.

The desktop/executor disconnected during compilation. Host process handles and
supervisors were lost, while both detached Docker builds survived. Their actual
status was verified with Docker, complete log capture was reattached without
restarting either build, and the original kernel finished with exit 0. Only its
completed Orin container was removed; all caches and build output remain.
The original tools container subsequently completed with exit 0. Its successful
state and complete log are saved. The actual Yocto driver build then started
through `./orin driver`; neither cold toolchain work nor smoke builds were repeated.

Upstream userspace warnings about unchecked allocation/I/O results remain visible
in the smoke log. Passing compilation and help startup does not establish safe
DMA behavior or resolve those runtime error paths.

The actual Yocto kernel configuration differs from the smoke configuration in
32 symbols, including compiler capabilities, the release suffix and module
signing. OE4T's supplied `disable-module-signing.cfg` sets MODULE_SIG and
MODULE_SIG_ALL off; the QDMA fragment does not set them. These are compile-only
artifacts. A deployed kernel and module must use the board's intended signing
policy, matching configuration, release and symbol CRCs.

The actual module was installed into the recipe's staging root at
`usr/lib/modules/6.8.12-l4t-r39.2.1-1021.21/extra/qdma-pf.ko` and exported as
`yocto/qdma-pf.ko` (2,880,184 bytes), SHA256
`b45521fe0f8dcca872ada90e1bbcedfe0d43d8843a86da88b65e4d734b60b16c`.
It is distinct from the GCC 13.3 smoke module and its `6.8.12+` ABI.

Ubuntu 24.04's older host kmod cannot dump this kernel's packed variable-length
modversion records. The read-only evidence checker verifies the real
`struct modversion_info` in the pinned kernel source and decodes its ELF
`__versions` records, including the zero-next terminator used by the kernel
loader. It compares all 139 imported CRCs with the final real symbol table.
No module loading or force/bypass flags are used. Source-format evidence is in
`validation/kernel-modversion-format.txt` and
`validation/kernel-modversion-loader-records.txt`.

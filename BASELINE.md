# Source decisions, verified 2026-10-07

NVIDIA Jetson Linux **R39.2.1 GA / JetPack 7.2.1** supports the Orin family,
including Orin NX. This supersedes the older R36.5.2 baseline for this request.
NVIDIA documents kernel 6.8 and Orin NX support. OE4T's maintained Wrynose layer
provides the Yocto recipes for this release:

- https://developer.nvidia.com/embedded/jetpack/downloads
- https://developer.nvidia.com/embedded/jetson-linux-archive
- https://docs.nvidia.com/jetson/archives/r39.2.1/ReleaseNotes/Jetson_Linux_Release_Notes_r39.2.1.pdf
- https://github.com/OE4T/meta-tegra/tree/wrynose
- https://raw.githubusercontent.com/OE4T/meta-tegra/wrynose/README.md
- https://downloads.yoctoproject.org/releases/yocto/yocto-6.0.3/RELEASENOTES

Use released **Yocto 6.0.3 Wrynose**, with explicitly pinned OE-Core and BitBake,
plus OE4T's Wrynose maintenance layers. Master/Blacksail is a development series.
The OE4T demo checkout is used as a source manifest, not its distro configuration:
its current core pins describe a 6.0.4 snapshot and its distro autoaccepts codec
license flags. This project uses the released 6.0.3 core pins instead and has its
own small distro. `config/versions.sh` is the authoritative source lock.

| Source | Exact commit |
| --- | --- |
| OE4T tegra-demo-distro | 6eab4529e8ba83231214677dc70f504ca1cb326f |
| OE4T meta-tegra | 322bc23e5da0d6100a885660b144567182fcd312 |
| OE-Core, released Yocto 6.0.3 | ef022bf82d79015802309d14c28b13373ebe53f5 |
| BitBake 2.18 release pin | fae9db3168dbff1b8c76fe9c6726a9687ff97514 |
| meta-openembedded Wrynose, demo manifest | 47d7dbdd10890bbd429bc0cccbe14435c37e5af1 |
| NVIDIA linux-noble, kernel 6.8.12 | 78272943bba3a47e633b28963b0cda60de503500 |
| Xilinx dma_ip_drivers, requested revision | b8466090b4e812e191da9e9305ffb11cb7ace768 |

The provisional reference compile target is **p3768-0000-p3767-0000**:
Orin NX 16 GB P3767-0000 on NVIDIA P3768 carrier. It is not a claim about the
user's actual carrier, RAM SKU, PCIe lane routing, or endpoint configuration.
Set `ORIN_MACHINE` or supply the second launcher argument to change it after
the carrier has been identified. No hardware is connected or flashed.

The focused driver/tools/kernel tasks use open-source components. The build
policy excludes `Proprietary` packages and accepts no license flags. Kernel
`do_deploy` depends on `tegra-flashtools-native`, which fetches the proprietary
NVIDIA BSP. There is deliberately no image/flash/deploy launcher command.
That later step requires the user's explicit NVIDIA agreement approval first:

https://developer.download.nvidia.com/embedded/L4T/r39_Release_v2.1/release/Tegra_Software_License_Agreement-Tegra-Linux.txt

No prior NVIDIA acceptance was found in the inspected edf-dev project. No new
acceptance has been recorded or implied by this setup.

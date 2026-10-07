SUMMARY = "Same-revision QDMA host management, transfer and diagnostic tools"
HOMEPAGE = "https://github.com/Xilinx/dma_ip_drivers"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=4969aeb8afed4d3b53cd8fdefc61ad40"
SRC_URI = "git://github.com/Xilinx/dma_ip_drivers.git;protocol=https;nobranch=1 \
           file://0001-honor-linker-flags.patch;patchdir=../.. \
           file://0002-supply-create-mode.patch;patchdir=../.."
SRCREV = "b8466090b4e812e191da9e9305ffb11cb7ace768"
S = "${UNPACKDIR}/${BP}/QDMA/linux-kernel"
DEPENDS = "libaio"
inherit pkgconfig
do_compile() {
    # Upstream all: clean apps races and all tools share dma-utils/*.o.
    # Clean once, then explicitly build binaries sequentially without all/clean.
    oe_runmake -C apps clean
    install -d ${S}/bin
    for app in dma-ctl dma-from-device dma-to-device dma-xfer dma-perf dma-latency; do
        oe_runmake -j1 -C apps/$app $app CC="${CC}" \
            'CFLAGS=${CFLAGS} -I. -I../include -I../dma-utils' LDFLAGS="${LDFLAGS}"
        install -m 0755 apps/$app/$app bin/$app
    done
}
do_install() {
    install -d ${D}${bindir}
    for app in dma-ctl dma-from-device dma-to-device dma-xfer dma-perf dma-latency; do
        install -m 0755 ${S}/bin/$app ${D}${bindir}/$app
    done
}

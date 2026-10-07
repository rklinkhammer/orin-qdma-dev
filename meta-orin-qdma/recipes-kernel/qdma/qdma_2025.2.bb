SUMMARY = "Xilinx QDMA physical-function host driver for Orin NX"
HOMEPAGE = "https://github.com/Xilinx/dma_ip_drivers"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=eb723b61539feef013de476e68b5c50a"
SRC_URI = "git://github.com/Xilinx/dma_ip_drivers.git;protocol=https;nobranch=1 \
           file://0001-use-monotonic-nanoseconds.patch;patchdir=../.. \
           file://0002-use-kbuild-M-for-cross-compilation.patch;patchdir=../.."
SRCREV = "b8466090b4e812e191da9e9305ffb11cb7ace768"
S = "${UNPACKDIR}/git/QDMA/linux-kernel"
inherit module
COMPATIBLE_MACHINE = "(tegra)"
EXTRA_OEMAKE = 'KSRC="${STAGING_KERNEL_DIR}" KOBJ="${STAGING_KERNEL_BUILDDIR}" USER_ARCH=arm64 MODULE=mod_pf'
do_compile() {
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
    oe_runmake driver CC="${KERNEL_CC}" LD="${KERNEL_LD}" AR="${KERNEL_AR}" \
        CROSS_COMPILE="${TARGET_PREFIX}"
}
# Never run upstream install-mods: it uses build-host uname, /lib/modules, depmod.
do_install() {
    install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra
    install -m 0644 ${S}/bin/qdma-pf.ko ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/
}
KERNEL_MODULE_AUTOLOAD = ""

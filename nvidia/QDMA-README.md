# QDMA sources and native rebuilding on NVIDIA Ubuntu

These are the patched QDMA/linux-kernel sources for the revision in
UPSTREAM_REVISION. The five patches in patches/ are already applied.

Copy the sources before editing:

```sh
cp -a /usr/src/qdma ~/qdma-work
cd ~/qdma-work/linux-kernel
make -C apps clean
mkdir -p bin
for app in dma-ctl dma-from-device dma-to-device dma-xfer dma-perf dma-latency; do
    make -j1 -C apps/$app "$app" CC=gcc \
      'CFLAGS=-O2 -g -I. -I../include -I../dma-utils'
    install -m 0755 apps/$app/$app bin/$app
done
```

This needs build-essential and libaio-dev (installed by the preparation step).
Binaries remain local until explicitly installed. Hardware tests need a matching
FPGA bitstream and correctly configured QDMA function/queues.

For the module, use the NVIDIA headers for the RUNNING kernel and its original
Module.symvers. Do not mix Yocto kernel headers or QDMA binaries with this image.

```sh
uname -r
readlink -f /lib/modules/$(uname -r)/build
make driver KSRC=/lib/modules/$(uname -r)/build \
  KOBJ=/lib/modules/$(uname -r)/build USER_ARCH=arm64 MODULE=mod_pf \
  CC=gcc LD=ld AR=ar CROSS_COMPILE=
modinfo bin/qdma-pf.ko
```

Kernel upgrades require a new module build/package. The packaged driver depends
on the exact NVIDIA kernel Debian package used for its build. Secure Boot/module
signing and actual FPGA transfer correctness require separate validation.

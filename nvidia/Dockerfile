FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i '/^Types: deb/a Architectures: amd64' /etc/apt/sources.list.d/ubuntu.sources \
 && dpkg --add-architecture arm64 \
 && printf '%s\n' 'deb [arch=arm64 signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://ports.ubuntu.com/ubuntu-ports noble main universe' 'deb [arch=arm64 signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://ports.ubuntu.com/ubuntu-ports noble-updates main universe' 'deb [arch=arm64 signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://ports.ubuntu.com/ubuntu-ports noble-security main universe' > /etc/apt/sources.list.d/arm64.list \
 && apt-get update && apt-get install -y --no-install-recommends \
 build-essential gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libaio-dev:arm64 \
 bc bison flex libssl-dev libelf-dev libncurses-dev git ca-certificates curl \
 python3 python3-yaml rsync patch device-tree-compiler kmod file binutils \
 qemu-user-static cpio lbzip2 bzip2 xz-utils zstd sudo e2fsprogs dosfstools \
 gdisk parted libxml2-utils xmlstarlet uuid-runtime udev openssh-client \
 sshpass netcat-openbsd iproute2 iputils-ping nfs-kernel-server abootimg \
 whois xxd python3-usb lz4 \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
CMD ["bash"]

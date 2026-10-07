ARG UBUNTU_BASE=ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55
FROM ${UBUNTU_BASE}
ARG DEBIAN_FRONTEND=noninteractive
# Signed Ubuntu repositories; amd64 matches edf-dev and NVIDIA build tooling.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates locales tzdata build-essential autoconf automake bison flex \
    patch gawk wget curl git git-lfs diffstat unzip zip texinfo chrpath socat \
    cpio xz-utils lz4 zstd file rsync bc debianutils iproute2 iputils-ping \
    python3 python3-pexpect python3-venv python3-git python3-jinja2 python3-yaml \
    python3-subunit pylint tmux openssh-client graphviz libssl-dev libncurses-dev \
    libacl1 acl libelf-dev kmod util-linux gcc-aarch64-linux-gnu \
    libc6-dev-arm64-cross libaio-dev libaio1t64 pkg-config \
    && sed -i '/^Types: deb/a Architectures: amd64' /etc/apt/sources.list.d/ubuntu.sources \
    && dpkg --add-architecture arm64 \
    && printf '%s\n' 'deb [arch=arm64 signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://ports.ubuntu.com/ubuntu-ports noble main' 'deb [arch=arm64 signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://ports.ubuntu.com/ubuntu-ports noble-updates main' 'deb [arch=arm64 signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://ports.ubuntu.com/ubuntu-ports noble-security main' > /etc/apt/sources.list.d/arm64.list \
    && apt-get update && apt-get install -y --no-install-recommends libaio-dev:arm64 \
    && locale-gen en_US.UTF-8 \
    && userdel ubuntu \
    && groupadd --gid 1000 yocto \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash yocto \
    && chmod 0755 /home/yocto \
    && install -d /usr/local/share/orin-qdma-dev \
    && dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' > /usr/local/share/orin-qdma-dev/packages.tsv \
    && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
USER 1000:1000
WORKDIR /home/yocto/orin
CMD ["/bin/bash", "--noprofile", "--norc", "-i"]

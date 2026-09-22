# Build scx (sched_ext schedulers) + scx-loader debs for Debian sid in a
# container. Host stays untouched; artifacts are collected in ./out/ by
# build.sh.
#
# Packaging for both sources is self-contained in packaging/:
#   packaging/scx/        schedulers (upstream https://github.com/sched-ext/scx)
#   packaging/scx-loader/ scx_loader daemon + scxctl + scxtui
#                         (upstream https://github.com/sched-ext/scx-loader)
FROM debian:sid

ARG SCX_VERSION=1.1.3
ARG LOADER_VERSION=1.1.3
ENV DEBIAN_FRONTEND=noninteractive

# Build-Depends from packaging/*/control, with Debian package names:
# sid's rustc/cargo (>= 1.91 MSRV) and bpftool instead of Ubuntu's
# rust-1.91 / linux-tools-*. scx-loader is pure Rust and needs nothing extra.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        debhelper \
        fakeroot \
        git \
        ca-certificates \
        python3 \
        jq \
        pkgconf \
        cmake \
        protobuf-compiler \
        clang \
        llvm \
        llvm-dev \
        libbpf-dev \
        binutils-dev \
        libelf-dev \
        libcap-dev \
        zlib1g-dev \
        libzstd-dev \
        libssl-dev \
        libseccomp-dev \
        rustc \
        cargo \
        bpftool \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build/pkg
COPY packaging/ ./packaging/
COPY scripts/ ./scripts/

# Source prep per package: clone the tag, vendor crates, make the orig
# tarball and overlay debian/. Results in /build/pkg/build/<src>-<ver>.
RUN ./scripts/prepare-source.sh scx "${SCX_VERSION}" \
 && ./scripts/prepare-source.sh scx-loader "${LOADER_VERSION}"

# The binary builds themselves are run by build.sh (podman/docker run) so
# they can be re-run without redoing this preparation.

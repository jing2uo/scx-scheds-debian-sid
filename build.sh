#!/usr/bin/env bash
# Build scx + scx-loader debs in a container (podman or docker) and collect
# them in ./out/.
#
#   ./build.sh                      # both packages, versions from changelogs
#   SCX_VERSION=1.1.4 ./build.sh    # explicit scx version
#   LOADER_VERSION=latest ./build.sh
#   SCX_VERSION=latest LOADER_VERSION=latest ./build.sh
#
# Tests are skipped and no -dbgsym packages are produced; override with
# DEB_BUILD_OPTIONS to change that (e.g. DEB_BUILD_OPTIONS="parallel=8").
set -euo pipefail
cd "$(dirname "$0")"

if command -v podman >/dev/null 2>&1; then
    RUNNER=podman
elif command -v docker >/dev/null 2>&1; then
    RUNNER=docker
else
    echo "ERROR: podman or docker is required" >&2
    exit 1
fi

resolve_latest() {  # resolve_latest <owner/repo>
    git ls-remote --tags --refs "https://github.com/$1" 'refs/tags/v*' \
        | grep -Ev -- '-(rc|alpha|beta)' \
        | sed 's|.*/v||' | sort -V | tail -1
}

default_version() {  # default_version <packaging-dir>
    if command -v dpkg-parsechangelog >/dev/null 2>&1; then
        dpkg-parsechangelog -l "packaging/$1/changelog" -SVersion | sed 's/-.*//'
    else
        echo latest
    fi
}

SCX_VERSION="${SCX_VERSION:-$(default_version scx)}"
LOADER_VERSION="${LOADER_VERSION:-$(default_version scx-loader)}"
[ "$SCX_VERSION" = "latest" ] && SCX_VERSION="$(resolve_latest sched-ext/scx)"
[ "$LOADER_VERSION" = "latest" ] && LOADER_VERSION="$(resolve_latest sched-ext/scx-loader)"
echo ">> scx ${SCX_VERSION}, scx-loader ${LOADER_VERSION} (runner: ${RUNNER})"

"$RUNNER" build \
    --build-arg SCX_VERSION="${SCX_VERSION}" \
    --build-arg LOADER_VERSION="${LOADER_VERSION}" \
    -t "scx-scheds-debian-sid:${SCX_VERSION}" .

mkdir -p out
"$RUNNER" run --rm \
    -e DEB_BUILD_OPTIONS="${DEB_BUILD_OPTIONS:-nocheck noautodbgsym parallel=$(nproc)}" \
    -v "$(pwd)/out:/out" \
    "scx-scheds-debian-sid:${SCX_VERSION}" \
    bash -ec "
        set -e
        build_one() {
            cd \"/build/pkg/build/\$1\" && dpkg-buildpackage -b -us -uc -d && cd /
        }
        build_one scx-${SCX_VERSION}
        build_one scx-loader-${LOADER_VERSION}
        cp -p /build/pkg/build/*.deb /out/
    "

echo
echo "== artifacts =="
ls -lh out/

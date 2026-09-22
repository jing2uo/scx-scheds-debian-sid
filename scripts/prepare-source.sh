#!/usr/bin/env bash
# Prepare ready-to-build Debian source trees from upstream git tags.
#
# For each supported source:
#   1. clone the upstream repo at tag v<VERSION>
#   2. cargo vendor (enables offline builds) + sanitize vendor checksums
#   3. pack <src>_<VERSION>.orig.tar.gz
#   4. overlay packaging/<src>/ as debian/, pin the changelog version,
#      refresh the vendored copyright metadata
#   ("scx" additionally regenerates debian/install from the schedulers
#    that actually exist in the release.)
#
# Usage: scripts/prepare-source.sh <source> [VERSION]
#   <source> is "scx" or "scx-loader"
#   VERSION defaults to the version in that source's changelog.
# Env:   OUT_DIR  (default <repo>/build)
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$PKG_DIR/build}"

case "${1:-}" in
    scx)       UPSTREAM_URL="https://github.com/sched-ext/scx" ;;
    scx-loader) UPSTREAM_URL="https://github.com/sched-ext/scx-loader" ;;
    *) echo "Usage: $0 <scx|scx-loader> [VERSION]" >&2; exit 2 ;;
esac
SOURCE="$1"
PACKAGING="$PKG_DIR/packaging/$SOURCE"

VERSION="${2:-$(dpkg-parsechangelog -l "$PACKAGING/changelog" -SVersion)}"
VERSION="${VERSION%%-*}"          # strip Debian revision, if any
SRC="${SOURCE}-${VERSION}"

echo ">> Preparing ${SRC} from ${UPSTREAM_URL}"

rm -rf "${OUT_DIR:?}/${SRC}" "${OUT_DIR:?}/${SOURCE}_${VERSION}.orig.tar.gz"
mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

# 1. Upstream source at the matching tag.
git clone --depth 1 --branch "v${VERSION}" "$UPSTREAM_URL" "$SRC"
rm -rf "$SRC/.git"

# 2. Vendor Rust crates for offline builds.
(
    cd "$SRC"
    # `cargo vendor` only prints the source-replacement configuration;
    # append it to upstream's Cargo config (keeps upstream's aliases).
    mkdir -p .cargo
    cargo vendor >> .cargo/config.toml
    python3 "$PACKAGING/sanitize-vendor-checksums.py" \
        --copyright "$PACKAGING/copyright"
)

# 3. Orig tarball (upstream + vendor/, no debian/ inside).
echo ">> Creating orig tarball"
tar --create --gzip \
    --owner=0 --group=0 --numeric-owner \
    --file "${SOURCE}_${VERSION}.orig.tar.gz" \
    "$SRC"

# 4. Overlay the packaging.
cp -r "$PACKAGING" "$SRC/debian"
sed -i "1s/^[^(]* ([^)]*) [^;]*;/${SOURCE} (${VERSION}-1) unstable;/" \
    "$SRC/debian/changelog"
python3 "$SRC/debian/update-vendor-copyright" --source-root "$SRC"

# Install manifest for scx: every scheduler shipped in this release.
if [ "$SOURCE" = "scx" ]; then
    {
        echo 'services/scx etc/default/'
        ls -d "$SRC"/scheds/rust/scx_* \
            | sed 's|.*/\(scx_.*\)$|target/release/\1 usr/sbin/|'
    } > "$SRC/debian/install"
fi

# Vendor-default config for scx-loader: stage it under the filename the
# loader actually looks up ($VENDORDIR/scx_loader/config.toml).
if [ "$SOURCE" = "scx-loader" ]; then
    mkdir -p "$SRC/vendor-default"
    cp "$SRC/configs/scx_loader.toml" "$SRC/vendor-default/config.toml"
fi

echo ">> Done. Binary build:"
echo "   (cd $OUT_DIR/$SRC && DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -us -uc -d)"

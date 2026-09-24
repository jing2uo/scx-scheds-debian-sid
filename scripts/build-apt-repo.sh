#!/usr/bin/env bash
# Assemble a signed, flat-pool apt repository from a directory of .debs.
#
#   GPG_KEY_ID=<fingerprint> scripts/build-apt-repo.sh <debs-dir> <out-dir>
#
# Layout produced (served as-is at https://apt.guojing.io):
#
#   <out>/dists/sid/{Release,InRelease,Release.gpg}
#   <out>/dists/sid/main/binary-amd64/Packages{,.gz,.xz}
#   <out>/pool/main/<pkg>/<file>.deb
#   <out>/guojing-archive-keyring.{gpg,asc}   public signing key
#   <out>/guojing.sources                     deb822 source for apt
#
# Needs apt-ftparchive (apt-utils), gpg, gzip, xz. The signing key must
# already be in the gpg keyring and have no passphrase.
set -euo pipefail

DEBS="${1:?usage: $0 <debs-dir> <out-dir>}"
OUT="${2:?usage: $0 <debs-dir> <out-dir>}"
: "${GPG_KEY_ID:?set GPG_KEY_ID to the signing key fingerprint}"

DOMAIN="${APT_DOMAIN:-apt.guojing.io}"
SUITE=sid
COMP=main
ARCH=amd64
KEYRING=guojing-archive-keyring

shopt -s nullglob
debs=("$DEBS"/*.deb)
[ ${#debs[@]} -gt 0 ] || { echo "ERROR: no .deb in $DEBS" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/dists/$SUITE/$COMP/binary-$ARCH"

for deb in "${debs[@]}"; do
    pkg="$(dpkg-deb -f "$deb" Package)"
    mkdir -p "$OUT/pool/$COMP/$pkg"
    cp "$deb" "$OUT/pool/$COMP/$pkg/"
done

cd "$OUT"

bin="dists/$SUITE/$COMP/binary-$ARCH"
apt-ftparchive packages "pool/$COMP" > "$bin/Packages"
gzip -9nk "$bin/Packages"
xz -9k "$bin/Packages"

apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="$DOMAIN" \
    -o APT::FTPArchive::Release::Label="$DOMAIN" \
    -o APT::FTPArchive::Release::Suite=unstable \
    -o APT::FTPArchive::Release::Codename="$SUITE" \
    -o APT::FTPArchive::Release::Architectures="$ARCH" \
    -o APT::FTPArchive::Release::Components="$COMP" \
    -o APT::FTPArchive::Release::Description="Personal packages for Debian sid" \
    release "dists/$SUITE" > "dists/$SUITE/Release.tmp"
mv "dists/$SUITE/Release.tmp" "dists/$SUITE/Release"

gpg --batch --yes --local-user "$GPG_KEY_ID" --digest-algo SHA512 \
    --clearsign -o "dists/$SUITE/InRelease" "dists/$SUITE/Release"
gpg --batch --yes --local-user "$GPG_KEY_ID" --digest-algo SHA512 \
    --armor --detach-sign -o "dists/$SUITE/Release.gpg" "dists/$SUITE/Release"

gpg --batch --export "$GPG_KEY_ID" > "$KEYRING.gpg"
gpg --batch --armor --export "$GPG_KEY_ID" > "$KEYRING.asc"

cat > guojing.sources <<EOF
Types: deb
URIs: https://$DOMAIN
Suites: $SUITE
Components: $COMP
Architectures: $ARCH
Signed-By: /usr/share/keyrings/$KEYRING.gpg
EOF

# GitHub Pages bits: custom domain, and don't run Jekyll over the tree.
echo "$DOMAIN" > CNAME
touch .nojekyll

cat > index.html <<EOF
<!doctype html>
<meta charset="utf-8">
<title>$DOMAIN</title>
<style>body{font:15px/1.5 system-ui,sans-serif;max-width:46rem;margin:2rem auto;padding:0 1rem}pre{background:#8881;padding:.8rem;overflow-x:auto}</style>
<h1>$DOMAIN</h1>
<p>apt repository for Debian sid (amd64).
Source: <a href="https://github.com/jing2uo/scx-scheds-debian-sid">jing2uo/scx-scheds-debian-sid</a>.</p>
<pre>sudo curl -fsSLo /usr/share/keyrings/$KEYRING.gpg https://$DOMAIN/$KEYRING.gpg
sudo curl -fsSLo /etc/apt/sources.list.d/guojing.sources https://$DOMAIN/guojing.sources
sudo apt update
sudo apt install scx scx-loader</pre>
<h2>Packages</h2>
<pre>$(apt-ftparchive packages "pool/$COMP" 2>/dev/null \
    | awk -F': ' '/^Package:/{p=$2} /^Version:/{print p, $2}' | sort -V)</pre>
EOF

echo ">> repo ready in $OUT"
find . -type f -not -path './pool/*' | sort

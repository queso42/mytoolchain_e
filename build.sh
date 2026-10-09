#!/usr/bin/env bash
set -Eeuo pipefail

# --------------------------------------------------
# Paths and configuration
# --------------------------------------------------

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$ROOT/toolconf" ]]; then
    echo "Missing toolchain configuration: $ROOT/toolconf" >&2
    exit 1
fi

# crosstool-NG version comes from the config itself (CT_VERSION="x.y.z"),
# so the config and the tool that reads it can never disagree.
VERSION="$(sed -n 's/^CT_VERSION="\(.*\)"$/\1/p' "$ROOT/toolconf")"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Could not read a valid CT_VERSION from toolconf: '$VERSION'" >&2
    exit 1
fi

TARBALL="crosstool-ng-${VERSION}.tar.xz"
URL="http://crosstool-ng.org/download/crosstool-ng/${TARBALL}"
NAME="$(basename "$ROOT")"

WORK="$ROOT/work"
ARCHIVE="$WORK/$TARBALL"
CTNG_SRC="$WORK/crosstool-ng-$VERSION"
CTNG_PREFIX="$WORK/ctng"
BUILD="$WORK/build"
OUT="$ROOT/out"
UPTOOL="$ROOT/uptoolchain"

echo "======================================"
echo " Cross toolchain CI build"
echo "======================================"
echo "Name         : $NAME"
echo "crosstool-NG : $VERSION"
echo "Source       : $URL"
echo "======================================"

# --------------------------------------------------
# Dependencies
# --------------------------------------------------

sudo apt-get update

sudo apt-get install -y \
    gcc-aarch64-linux-{gcc,g++,binutils} \
    build-essential gcc g++ gperf bison flex texinfo help2man \
    make libncurses-dev python3-dev autoconf automake libtool \
    libtool-bin gawk wget curl bzip2 xz-utils unzip patch rsync \
    meson ninja-build ca-certificates

# --------------------------------------------------
# Build crosstool-NG
# --------------------------------------------------

mkdir -p "$WORK"

echo "Downloading crosstool-NG..."

curl --fail --location --retry 3 \
    "$URL" \
    --output "$ARCHIVE"

echo "Extracting crosstool-NG..."

rm -rf "$CTNG_SRC"
mkdir -p "$CTNG_SRC"

tar -xJf "$ARCHIVE" \
    -C "$CTNG_SRC" \
    --strip-components=1

(
    cd "$CTNG_SRC"
    ./configure --prefix="$CTNG_PREFIX"
    make -j"$(nproc)"
    make install
)

export PATH="$CTNG_PREFIX/bin:$PATH"

# --------------------------------------------------
# Configure toolchain
# --------------------------------------------------

echo "Installing toolchain configuration..."

rm -rf "$BUILD" "$OUT"
mkdir -p "$BUILD" "$HOME/src"

cp "$ROOT/toolconf" "$BUILD/.config"

export CT_PREFIX="$OUT"

(
    cd "$BUILD"

    echo "Resolving toolchain configuration..."
    ct-ng olddefconfig

    # --------------------------------------------------
    # Compile toolchain
    # --------------------------------------------------

    echo "Building toolchain (this takes a while)..."
    ct-ng build
)

# --------------------------------------------------
# Detect triplet
# --------------------------------------------------

mapfile -t TRIPLETS < <(find "$OUT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')

if [[ "${#TRIPLETS[@]}" -ne 1 ]]; then
    echo "Expected exactly one toolchain in out/, found: ${TRIPLETS[*]:-none}" >&2
    exit 1
fi

TRIPLET="${TRIPLETS[0]}"

echo "Detected triplet: $TRIPLET"

# --------------------------------------------------
# Package
# --------------------------------------------------

echo "Packaging toolchain..."

rm -rf "$UPTOOL"
mkdir -p "$UPTOOL"

tar -C "$OUT" -cJf "$UPTOOL/${NAME}-${TRIPLET}.tar.xz" "$TRIPLET"

cp "$ROOT/toolconf" "$UPTOOL/toolconf"

# --------------------------------------------------
# Verify artifact outputs
# --------------------------------------------------

if [[ -z "$(find "$UPTOOL" -type f -name '*.tar.xz' -print -quit)" ]]; then
    echo "ERROR: uptoolchain/ contains no toolchain tarball." >&2
    exit 1
fi

echo
echo "======================================"
echo " BUILD SUCCESSFUL"
echo "======================================"

echo
echo "Toolchain artifacts:"
find "$UPTOOL" -type f -printf '%P\n'

echo
echo "Artifacts are ready for GitHub Actions."

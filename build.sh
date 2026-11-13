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
URLS=(
  "https://github.com/crosstool-ng/crosstool-ng/releases/download/crosstool-ng-${VERSION}/${TARBALL}"
  "https://crosstool-ng.org/download/crosstool-ng/${TARBALL}"
)
# Pinned SHA256 of each supported crosstool-NG tarball. When you bump
# CT_VERSION in toolconf, add the new release's checksum here.
declare -A CTNG_SHA256=(
  [1.29.0]="1e0c5efcf2af674993b74a1783fe78727c8d34b500ebab07eb1bb0a45c8fcc87"
)
EXPECTED_SHA256="${CTNG_SHA256[$VERSION]:-}"
if [[ -z "$EXPECTED_SHA256" ]]; then
  echo "No pinned SHA256 for crosstool-NG $VERSION; add it to build.sh" >&2
  exit 1
fi
NAME="${TOOLCHAIN_NAME:-$(basename "$ROOT")}"

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
echo "Source       : ${URLS[0]}"
echo "======================================"

# --------------------------------------------------
# Dependencies
# --------------------------------------------------

# On an arm64 host, require the aarch64-linux-gnu- compilers up front.
# (Skipped on other hosts, e.g. x86_64 CI runners.)
if [[ "$(uname -m)" =~ ^(aarch64|arm64)$ ]]; then
  missing=()
  for tool in aarch64-linux-gnu-gcc aarch64-linux-gnu-g++ binutils-aarch64-linux-gnu; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "Missing on arm64 host: ${missing[*]}" >&2
    echo "Install with: sudo apt-get install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu" >&2
    exit 1
  fi
fi

sudo apt-get update

sudo apt-get install -y \
    build-essential gcc g++ gperf bison flex texinfo help2man \
    make libncurses-dev python3-dev autoconf automake libtool \
    libtool-bin gawk wget curl bzip2 xz-utils unzip patch rsync \
    meson ninja-build ca-certificates

# --------------------------------------------------
# Build crosstool-NG
# --------------------------------------------------

mkdir -p "$WORK"

echo "Downloading crosstool-NG..."

downloaded=0
for url in "${URLS[@]}"; do
  echo "Trying $url"
  if wget --tries=3 --output-document="$ARCHIVE" "$url" \
     && echo "${EXPECTED_SHA256}  ${ARCHIVE}" | sha256sum --check --status; then
    downloaded=1
    break
  fi
  echo "Download or checksum failed for $url" >&2
done
if [[ "$downloaded" -ne 1 ]]; then
  echo "Could not obtain a verified $TARBALL" >&2
  exit 1
fi

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

# crosstool-NG leaves its install tree read-only; let a rerun clean it.
chmod -R u+w "$BUILD" "$OUT" 2>/dev/null || true
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
# Smoke test
# --------------------------------------------------

echo "Smoke-testing toolchain..."
GCC="$OUT/$TRIPLET/bin/$TRIPLET-gcc"
"$GCC" --version | head -n1
printf 'int main(void) { return 0; }\n' > "$WORK/smoke.c"
"$GCC" -o "$WORK/smoke" "$WORK/smoke.c"
test -s "$WORK/smoke"

# --------------------------------------------------
# Package
# --------------------------------------------------

echo "Packaging toolchain..."

rm -rf "$UPTOOL"
mkdir -p "$UPTOOL"

XZ_OPT="-T0" tar -C "$OUT" -cJf "$UPTOOL/${NAME}-${TRIPLET}.tar.xz" "$TRIPLET"

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

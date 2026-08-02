#!/usr/bin/env bash
# Build shared libuv into lib/<os>-<arch>/.
# Env: LIBUV_VERSION (default 1.51.0), DEST_DIR, EVENT_PROTOCOL_UV_INCLUDE (set for grovel)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIBUV_VERSION="${LIBUV_VERSION:-1.51.0}"
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

uname_s="$(uname -s)"
uname_m="$(uname -m)"
case "$uname_s" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) echo "unsupported OS: $uname_s (Windows: use build-libuv.ps1)" >&2; exit 1 ;;
esac
case "$uname_m" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "unsupported arch: $uname_m" >&2; exit 1 ;;
esac

OUT="${DEST_DIR:-$ROOT/lib/${os}-${arch}}"
BUILD="$ROOT/build/libuv-${LIBUV_VERSION}-${os}-${arch}"
SRC_TGZ="$ROOT/build/libuv-${LIBUV_VERSION}.tar.gz"
SRC_URL="https://github.com/libuv/libuv/archive/refs/tags/v${LIBUV_VERSION}.tar.gz"

mkdir -p "$ROOT/build" "$OUT"
if [[ ! -f "$SRC_TGZ" ]]; then
  echo "==> download $SRC_URL"
  curl -fsSL "$SRC_URL" -o "$SRC_TGZ"
fi

rm -rf "$BUILD"
mkdir -p "$BUILD"
tar -xzf "$SRC_TGZ" -C "$BUILD" --strip-components=1

echo "==> cmake/build libuv ${LIBUV_VERSION} -> $OUT"
cmake -S "$BUILD" -B "$BUILD/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$BUILD/prefix" \
  -DLIBUV_BUILD_SHARED=ON \
  -DLIBUV_BUILD_TESTS=OFF
cmake --build "$BUILD/build" -j"$JOBS"
cmake --install "$BUILD/build"

rm -rf "$OUT"
mkdir -p "$OUT"
# Stage shared libs (real file + soname/compat).
shopt -s nullglob
for f in "$BUILD/prefix/lib"/libuv.so* "$BUILD/prefix/lib"/libuv.*.dylib "$BUILD/prefix/lib"/libuv.dylib \
         "$BUILD/prefix/lib64"/libuv.so*; do
  cp -a "$f" "$OUT/"
done
# Headers for grovel
mkdir -p "$BUILD/prefix/include"
export EVENT_PROTOCOL_UV_INCLUDE="$BUILD/prefix/include"
echo "EVENT_PROTOCOL_UV_INCLUDE=$EVENT_PROTOCOL_UV_INCLUDE"
echo "staged:" && ls -la "$OUT"

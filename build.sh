#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
RELEASE="${RELEASE:-25.12.2}"
TARGET="x86/64"
BASE="https://downloads.immortalwrt.org/releases/${RELEASE}/targets/${TARGET}"
WORK="${ROOT}/work"
OUT="${ROOT}/output"
mkdir -p "$WORK" "$OUT"
IB="immortalwrt-imagebuilder-${RELEASE}-x86-64.Linux-x86_64.tar.zst"
URL="${BASE}/${IB}"
if [[ ! -f "$WORK/$IB" ]]; then
  echo "Downloading $URL"
  curl -fL --retry 3 "$URL" -o "$WORK/$IB"
fi
curl -fsSL "${BASE}/sha256sums" -o "$WORK/sha256sums" || true
if grep -F " $IB" "$WORK/sha256sums" >/dev/null 2>&1; then
  (cd "$WORK" && grep -F " $IB" sha256sums | sha256sum -c -)
else
  echo "WARNING: official sha256sums file did not list $IB; continuing with HTTPS download."
fi
rm -rf "$WORK/imagebuilder"
mkdir -p "$WORK/imagebuilder"
tar --zstd -xf "$WORK/$IB" -C "$WORK/imagebuilder" --strip-components=1
IBDIR="$WORK/imagebuilder"
mkdir -p "$ROOT/overlay/usr/sbin"
if ! command -v go >/dev/null 2>&1; then
  echo "Go is required to compile the local API. Install Go 1.22+ and retry." >&2
  exit 1
fi
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags='-s -w' -o "$ROOT/overlay/usr/sbin/dualweb-api" "$ROOT/src/main.go"
chmod 0755 "$ROOT/overlay/usr/sbin/dualweb-api"

# ImageBuilder copies file modes from the overlay; ensure init scripts are executable.
chmod 0755 "$ROOT/overlay/etc/uci-defaults/99-dualweb"
chmod 0755 "$ROOT/overlay/etc/init.d/dualweb-api"

mkdir -p "$IBDIR/files"
cp -a "$ROOT/overlay/." "$IBDIR/files/"
PACKAGES="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT/packages.txt" | tr '\\' ' ' | xargs)"
make -C "$IBDIR" image PROFILE=generic PACKAGES="$PACKAGES" FILES="$IBDIR/files" BIN_DIR="$OUT"
cp "$WORK/$IB" "$OUT/"
cp "$WORK/sha256sums" "$OUT/official-sha256sums.txt" 2>/dev/null || true
(
  cd "$OUT"
  sha256sum * > SHA256SUMS.local
)
echo "Build complete: $OUT"

#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
RELEASE="${RELEASE:-25.12.2}"
TARGET="x86/64"
BASE="https://downloads.immortalwrt.org/releases/${RELEASE}/targets/${TARGET}"
WORK="${ROOT}/work"
OUT="${ROOT}/output"
NIKKI_VERSION="${NIKKI_VERSION:-v1.26.2}"
NIKKI_ARCHIVE="nikki_x86_64-openwrt-25.12.tar.gz"
NIKKI_URL="https://github.com/nikkinikki-org/OpenWrt-nikki/releases/download/${NIKKI_VERSION}/${NIKKI_ARCHIVE}"
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

if ! command -v go >/dev/null 2>&1; then
  echo "Go is required to compile the local API. Install Go 1.22+ and retry." >&2
  exit 1
fi
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags='-s -w' -o "$ROOT/overlay/usr/sbin/dualweb-api" "$ROOT/src/main.go"
chmod 0755 "$ROOT/overlay/usr/sbin/dualweb-api"

# ImageBuilder copies file modes from the overlay; ensure init scripts are executable.
chmod 0755 "$ROOT/overlay/etc/uci-defaults/99-dualweb"
chmod 0755 "$ROOT/overlay/etc/init.d/dualweb-api"
chmod 0755 "$ROOT/overlay/etc/init.d/dualweb-firstboot"
chmod 0755 "$ROOT/overlay/usr/sbin/dualweb-firstboot-packages"

# Download Nikki's prebuilt APK packages for ImmortalWrt 25.12 and bake them into the image.
# This is build-time only: the router does not need to reach GitHub on first boot.
if [[ ! -s "$WORK/$NIKKI_ARCHIVE" ]]; then
  echo "Downloading Nikki packages: $NIKKI_URL"
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 "$NIKKI_URL" -o "$WORK/$NIKKI_ARCHIVE"
fi
rm -rf "$WORK/nikki-packages"
mkdir -p "$WORK/nikki-packages" "$IBDIR/packages"
tar -xzf "$WORK/$NIKKI_ARCHIVE" -C "$WORK/nikki-packages"
find "$WORK/nikki-packages" -type f -name '*.apk' -print
find "$WORK/nikki-packages" -type f -name '*.apk' -exec cp -f {} "$IBDIR/packages/" \;
for pkg in mihomo-meta nikki luci-app-nikki luci-i18n-nikki-zh-cn; do
  if ! find "$IBDIR/packages" -maxdepth 1 -type f -name "${pkg}-*.apk" -print -quit | grep -q .; then
    echo "ERROR: Nikki archive does not contain an APK for package: $pkg" >&2
    echo "Archive layout may have changed; inspect $WORK/nikki-packages." >&2
    exit 1
  fi
done

mkdir -p "$IBDIR/files"
cp -a "$ROOT/overlay/." "$IBDIR/files/"
PACKAGES="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT/packages.txt" | tr '\\' ' ' | xargs)"
echo "========== Verify package manifest =========="
make -C "$IBDIR" manifest PROFILE=generic PACKAGES="$PACKAGES"
echo "========== Build firmware =========="
make -C "$IBDIR" image PROFILE=generic PACKAGES="$PACKAGES" FILES="$IBDIR/files" BIN_DIR="$OUT"
# Keep only the requested generic squashfs combined image in the firmware output.
IMAGE="$(find "$OUT" -maxdepth 1 -type f -name '*-generic-squashfs-combined.img.gz' -print -quit)"
if [[ -z "$IMAGE" ]]; then
  RAW_IMAGE="$(find "$OUT" -maxdepth 1 -type f -name '*-generic-squashfs-combined.img' -print -quit)"
  if [[ -n "$RAW_IMAGE" ]]; then
    gzip -n -9 "$RAW_IMAGE"
    IMAGE="${RAW_IMAGE}.gz"
  fi
fi
if [[ -z "$IMAGE" || ! -s "$IMAGE" ]]; then
  echo "ERROR: expected *-generic-squashfs-combined.img.gz was not generated." >&2
  find "$OUT" -maxdepth 1 -type f -printf '%f (%s bytes)\\n' >&2
  exit 1
fi

# Build a plugin installer bundle. Local APKs (including Nikki's release APKs)
# are bundled; other selected packages and their transitive dependencies are
# resolved by apk from the target's configured ImmortalWrt repositories.
BUNDLE="$WORK/package-bundle"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/packages"
find "$IBDIR/packages" -maxdepth 1 -type f -name '*.apk' -exec cp -f {} "$BUNDLE/packages/" \\;
cp "$ROOT/packages.txt" "$BUNDLE/packages.txt"
make -C "$IBDIR" manifest PROFILE=generic PACKAGES="$PACKAGES" > "$BUNDLE/imagebuilder-manifest.txt"
cat > "$BUNDLE/README.txt" <<'EOF'
DualWeb plugin installer bundle
- Bundled local APK files are under packages/.
- packages.txt records the selected plugin/package set.
- The installer resolves packages and transitive dependencies from the device's configured ImmortalWrt APK repositories.
- This is not a fully offline dependency mirror. The target must have working repository access.
- Open-Box proprietary runtime is not included; redistribution permission must be confirmed first.
EOF
tar -czf "$OUT/dualweb-packages.tar.gz" -C "$BUNDLE" .

# Create a self-extracting .run installer using the same bundle.
cat > "$WORK/install-dualweb.run.header" <<'INSTALL_HEADER'
#!/bin/sh
set -eu
if [ "$(id -u)" -ne 0 ]; then
  echo "请以 root 身份运行此安装包。" >&2
  exit 1
fi
if ! command -v apk >/dev/null 2>&1; then
  echo "未检测到 apk 包管理器；此安装包仅适用于匹配的 ImmortalWrt APK 系统。" >&2
  exit 1
fi
SELF="$0"
TMP="$(mktemp -d /tmp/dualweb-install.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT INT TERM
LINE="$(awk '/^__DUALWEB_PAYLOAD_BELOW__$/ { print NR; exit }' "$SELF")"
if [ -z "$LINE" ]; then
  echo "安装包损坏：找不到数据段。" >&2
  exit 1
fi
tail -n "+$((LINE + 1))" "$SELF" | tar -xz -C "$TMP"
PKGS="$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$TMP/packages.txt" | tr '\\' ' ' | xargs)"
echo "将安装插件及依赖；依赖由系统配置的软件源解析。"
# Intentional word splitting: packages.txt is a whitespace-separated package list.
# shellcheck disable=SC2086
apk add --allow-untrusted $PKGS "$TMP"/packages/*.apk
echo "安装完成。建议重启相关服务并检查 LuCI/代理服务状态。"
exit 0
__DUALWEB_PAYLOAD_BELOW__
INSTALL_HEADER
cat "$WORK/install-dualweb.run.header" "$OUT/dualweb-packages.tar.gz" > "$OUT/install-dualweb.run"
chmod 0755 "$OUT/install-dualweb.run"

# Retain only the firmware image and the two requested plugin installer artifacts.
find "$OUT" -maxdepth 1 -type f \\
  ! -name '*-generic-squashfs-combined.img.gz' \\
  ! -name 'dualweb-packages.tar.gz' \\
  ! -name 'install-dualweb.run' \\
  -delete
(
  cd "$OUT"
  sha256sum * > SHA256SUMS.local
)
echo "Build complete. Final artifacts:"
find "$OUT" -maxdepth 1 -type f -printf '%f (%s bytes)\\n'

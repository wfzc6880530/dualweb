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
chmod 0755 "$ROOT/overlay/usr/sbin/dualweb-update-zashboard"

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

# Install the official Open-Box x86_64 OpenWrt bundle into the firmware at build time.
# Open-Box's own license restricts redistribution; only distribute with authorization.
OPENBOX_VERSION="${OPENBOX_VERSION:-v0.1.341}"
OPENBOX_ARCHIVE="open-box-linux-x64.tar.gz"
OPENBOX_BASE="https://github.com/liandu2024/Open-Box/releases/download/${OPENBOX_VERSION}"
OPENBOX_TGZ="$WORK/$OPENBOX_ARCHIVE"
OPENBOX_SHA="$WORK/$OPENBOX_ARCHIVE.sha256"
if [[ ! -s "$OPENBOX_TGZ" ]]; then
  echo "Downloading Open-Box ${OPENBOX_VERSION}: ${OPENBOX_BASE}/${OPENBOX_ARCHIVE}"
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 "${OPENBOX_BASE}/${OPENBOX_ARCHIVE}" -o "$OPENBOX_TGZ"
fi
curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 "${OPENBOX_BASE}/${OPENBOX_ARCHIVE}.sha256" -o "$OPENBOX_SHA"
(cd "$WORK" && sha256sum -c "$(basename "$OPENBOX_SHA")")
tar -tzf "$OPENBOX_TGZ" >/dev/null
OPENBOX_ROOT="$ROOT/overlay/opt/open-box"
rm -rf "$OPENBOX_ROOT"
mkdir -p "$OPENBOX_ROOT"
tar -xzf "$OPENBOX_TGZ" -C "$OPENBOX_ROOT"
test -s "$OPENBOX_ROOT/meta.json"
test -s "$OPENBOX_ROOT/openwrt/initd/openbox-panel"
test -s "$OPENBOX_ROOT/openwrt/initd/openbox"
mkdir -p "$ROOT/overlay/etc/init.d" "$ROOT/overlay/etc/uci-defaults" "$ROOT/overlay/usr/bin" "$ROOT/overlay/www/luci-static/resources/view/openbox" "$ROOT/overlay/usr/share/luci/menu.d" "$ROOT/overlay/usr/share/rpcd/acl.d"
cp "$OPENBOX_ROOT/openwrt/initd/openbox" "$ROOT/overlay/etc/init.d/openbox"
cp "$OPENBOX_ROOT/openwrt/initd/openbox-panel" "$ROOT/overlay/etc/init.d/openbox-panel"
chmod 0755 "$ROOT/overlay/etc/init.d/openbox" "$ROOT/overlay/etc/init.d/openbox-panel" "$OPENBOX_ROOT/openwrt/bin/open-box"
cp "$OPENBOX_ROOT/openwrt/luci/htdocs/luci-static/resources/view/openbox/"*.js "$ROOT/overlay/www/luci-static/resources/view/openbox/"
cp "$OPENBOX_ROOT/openwrt/luci/root/usr/share/luci/menu.d/luci-app-openbox.json" "$ROOT/overlay/usr/share/luci/menu.d/"
cp "$OPENBOX_ROOT/openwrt/luci/root/usr/share/rpcd/acl.d/luci-app-openbox.json" "$ROOT/overlay/usr/share/rpcd/acl.d/"
chmod 0644 "$ROOT/overlay/www/luci-static/resources/view/openbox/"*.js "$ROOT/overlay/usr/share/luci/menu.d/luci-app-openbox.json" "$ROOT/overlay/usr/share/rpcd/acl.d/luci-app-openbox.json"
ln -sfn /opt/open-box/openwrt/bin/open-box "$ROOT/overlay/usr/bin/open-box"
cat > "$ROOT/overlay/etc/uci-defaults/98-openbox" <<'OPENBOX_DEFAULTS'
#!/bin/sh
# Enable the Open-Box panel UI, but keep its proxy core disabled to avoid competing
# with Nikki/Mihomo, OpenClash or PassWall transparent-proxy/firewall rules.
mkdir -p /opt/open-box/data
[ -s /opt/open-box/data/panel-port ] || printf '3036\n' > /opt/open-box/data/panel-port
[ -s /opt/open-box/data/channel ] || printf 'direct\n' > /opt/open-box/data/channel
chmod 0755 /opt/open-box/openwrt/bin/open-box /etc/init.d/openbox /etc/init.d/openbox-panel
/etc/init.d/openbox disable >/dev/null 2>&1 || true
/etc/init.d/openbox-panel enable
/etc/init.d/openbox-panel start >/dev/null 2>&1 || true
rm -rf /tmp/luci-*cache* 2>/dev/null || true
exit 0
OPENBOX_DEFAULTS
chmod 0755 "$ROOT/overlay/etc/uci-defaults/98-openbox"
echo "Open-Box ${OPENBOX_VERSION} integrated; panel port 3036; proxy core disabled by default."

# Fetch the official Zashboard static release at build time and bake it into port 80.
# The dashboard remains independently updateable on the running router.
ZASHBOARD_URL="${ZASHBOARD_URL:-https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip}"
ZASHBOARD_ZIP="$WORK/zashboard-dist.zip"
ZASHBOARD_DIR="$WORK/zashboard-dist"
if [[ ! -s "$ZASHBOARD_ZIP" ]]; then
  echo "Downloading Zashboard: $ZASHBOARD_URL"
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 "$ZASHBOARD_URL" -o "$ZASHBOARD_ZIP"
fi
unzip -tq "$ZASHBOARD_ZIP"
rm -rf "$ZASHBOARD_DIR"
mkdir -p "$ZASHBOARD_DIR" "$ROOT/overlay/www/dualweb/zashboard"
unzip -q "$ZASHBOARD_ZIP" -d "$ZASHBOARD_DIR"
ZASHBOARD_INDEX="$(find "$ZASHBOARD_DIR" -type f -name index.html -print -quit)"
if [[ -z "$ZASHBOARD_INDEX" ]]; then
  echo "ERROR: Zashboard release archive has no index.html" >&2
  exit 1
fi
rm -rf "$ROOT/overlay/www/dualweb/zashboard"
mkdir -p "$ROOT/overlay/www/dualweb/zashboard"
cp -a "$(dirname "$ZASHBOARD_INDEX")/." "$ROOT/overlay/www/dualweb/zashboard/"
test -s "$ROOT/overlay/www/dualweb/zashboard/index.html"
echo "Zashboard static files: $(du -sh "$ROOT/overlay/www/dualweb/zashboard" | cut -f1)"

mkdir -p "$IBDIR/files"
cp -a "$ROOT/overlay/." "$IBDIR/files/"
PACKAGES="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT/packages.txt" | tr '\\' ' ' | xargs)"
echo "========== Verify package manifest =========="
make -C "$IBDIR" manifest PROFILE=generic PACKAGES="$PACKAGES"
echo "========== Build firmware =========="
make -C "$IBDIR" image PROFILE=generic PACKAGES="$PACKAGES" FILES="$IBDIR/files" BIN_DIR="$OUT"
cp "$WORK/$IB" "$OUT/"
cp "$WORK/sha256sums" "$OUT/official-sha256sums.txt" 2>/dev/null || true
(
  cd "$OUT"
  sha256sum * > SHA256SUMS.local
)
echo "Build complete: $OUT"

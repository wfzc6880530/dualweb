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

# OpenClash is a release APK, not an ImmortalWrt base-feed package. Pin and verify
# the tested release so the UI is installed into the image instead of downloaded later.
OPENCLASH_VERSION="v0.48.002"
OPENCLASH_APK="luci-app-openclash-0.48.002.apk"
OPENCLASH_URL="https://github.com/vernesong/OpenClash/releases/download/${OPENCLASH_VERSION}/${OPENCLASH_APK}"
OPENCLASH_SHA256="f7ebbd43f9be15c5e6df26e5d0c03d50d0bb8f7fa4cc0d2c2bf048b08c0b155b"
mkdir -p "$IBDIR/packages"
if [[ ! -s "$WORK/$OPENCLASH_APK" ]]; then
  echo "Downloading OpenClash ${OPENCLASH_VERSION}: $OPENCLASH_URL"
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 "$OPENCLASH_URL" -o "$WORK/$OPENCLASH_APK"
fi
printf '%s  %s\n' "$OPENCLASH_SHA256" "$WORK/$OPENCLASH_APK" | sha256sum -c -
cp -f "$WORK/$OPENCLASH_APK" "$IBDIR/packages/$OPENCLASH_APK"
echo "OpenClash package staged: $OPENCLASH_APK"

# Preinstall the OpenClash Meta-compatible Clash core. OpenClash expects this
# binary at /etc/openclash/core/clash_meta; the x86-64 v1 build maximizes CPU compatibility.
OPENCLASH_CORE_VERSION="v1.19.32"
OPENCLASH_CORE_ARCHIVE="mihomo-linux-amd64-v1-${OPENCLASH_CORE_VERSION}.gz"
OPENCLASH_CORE_URL="https://github.com/MetaCubeX/mihomo/releases/download/${OPENCLASH_CORE_VERSION}/${OPENCLASH_CORE_ARCHIVE}"
OPENCLASH_CORE_SHA256="306f81e723e60ce6b828899a6fe83e1d00e9ecefb2dc8d4d849312a5bc00efdc"
if [[ ! -s "$WORK/$OPENCLASH_CORE_ARCHIVE" ]]; then
  echo "Downloading OpenClash core ${OPENCLASH_CORE_VERSION}: $OPENCLASH_CORE_URL"
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 "$OPENCLASH_CORE_URL" -o "$WORK/$OPENCLASH_CORE_ARCHIVE"
fi
printf '%s  %s\n' "$OPENCLASH_CORE_SHA256" "$WORK/$OPENCLASH_CORE_ARCHIVE" | sha256sum -c -
gzip -t "$WORK/$OPENCLASH_CORE_ARCHIVE"
mkdir -p "$ROOT/overlay/etc/openclash/core"
gzip -dc "$WORK/$OPENCLASH_CORE_ARCHIVE" > "$ROOT/overlay/etc/openclash/core/clash_meta"
chmod 0755 "$ROOT/overlay/etc/openclash/core/clash_meta"
if ! "$ROOT/overlay/etc/openclash/core/clash_meta" -v >/dev/null 2>&1; then
  echo "::error::The prebuilt OpenClash core is not executable on the build host." >&2
  exit 1
fi
echo "OpenClash core staged: $("$ROOT/overlay/etc/openclash/core/clash_meta" -v 2>&1 | head -n 1)"

# Vantage is optional by request: try to bake in the verified release APKs.
# If download, checksum, dependency resolution, or image installation fails, warn
# and continue with Bootstrap rather than failing the whole firmware build.
VANTAGE_VERSION="v1.0.9"
VANTAGE_BASE="https://github.com/anothaDev/luci-theme-vantage/releases/download/${VANTAGE_VERSION}"
VANTAGE_OK=1
VANTAGE_PACKAGES="luci-theme-vantage luci-app-vantage luci-i18n-vantage-zh-cn"
while IFS='|' read -r asset expected_sha; do
  [[ -n "$asset" ]] || continue
  dest="$IBDIR/packages/$asset"
  if curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 "$VANTAGE_BASE/$asset" -o "$dest" \
      && printf '%s  %s\n' "$expected_sha" "$dest" | sha256sum -c -; then
    echo "Vantage package verified: $asset"
  else
    VANTAGE_OK=0
    break
  fi
done <<'VANTAGE_ASSETS'
luci-theme-vantage-1.0.9-r1.apk|d70ab2b4479b78bcf7e45ad70ddb251f4b57a66f711a7d58fae74c8ed8bff686
luci-app-vantage-1.0.9-r1.apk|b14853cc2f66b55982d63a14b6238552edfec6bdd4cbbf8278594be85ecd22e8
luci-i18n-vantage-zh-cn-1.0.9-r1.apk|cd1453cfd65e1a8fd4cb75023b0937cca4392f2077d88690a513da88834f6c07
VANTAGE_ASSETS
if [[ "$VANTAGE_OK" != "1" ]]; then
  rm -f "$IBDIR/packages/luci-theme-vantage-"*.apk \
        "$IBDIR/packages/luci-app-vantage-"*.apk \
        "$IBDIR/packages/luci-i18n-vantage-zh-cn-"*.apk
  echo "::warning::Vantage APK download/checksum failed; continuing with Bootstrap as the LuCI theme."
else
  echo "Vantage ${VANTAGE_VERSION} packages are staged; installation will be verified by ImageBuilder."
fi

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
if [[ -f "$ROOT/overlay/usr/sbin/dualweb-update-zashboard" ]]; then
  chmod 0755 "$ROOT/overlay/usr/sbin/dualweb-update-zashboard"
fi

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

# Build an isolated Open-Box frontend for port 80. The original frontend under
# /opt/open-box remains untouched and continues to serve port 3036.
OPENBOX_WEB_INDEX="$(find "${OPENBOX_ROOT}" -type f -name index.html -exec grep -l '<title>Open-Box</title>' {} + | head -n 1 || true)"
if [[ -z "$OPENBOX_WEB_INDEX" ]]; then
  echo "ERROR: Could not locate the Open-Box web index.html in the official bundle." >&2
  find "${OPENBOX_ROOT}" -type f -name index.html -print >&2
  exit 1
fi
OPENBOX_WEB_ROOT="$(dirname "$OPENBOX_WEB_INDEX")"
OPENBOX_LITE_ROOT="${ROOT}/overlay/www/dualweb/openbox-lite"
rm -rf "$OPENBOX_LITE_ROOT"
mkdir -p "$OPENBOX_LITE_ROOT"
cp -a "$OPENBOX_WEB_ROOT/." "$OPENBOX_LITE_ROOT/"
cp "$ROOT/build-assets/openbox-lite-nav.js" "$OPENBOX_LITE_ROOT/dualweb-openbox-lite-nav.js"
cp "$ROOT/build-assets/openbox-lite-nav.css" "$OPENBOX_LITE_ROOT/dualweb-openbox-lite-nav.css"

# Rebase absolute API/static-asset paths to this isolated mount point, then
# inject the small navigation filter. Only the copied frontend is modified.
python3 - "$OPENBOX_LITE_ROOT" <<'PYOPENBOXLITE'
from pathlib import Path
import sys
root = Path(sys.argv[1])
index = root / "index.html"
if not index.is_file():
    raise SystemExit("ERROR: Open-Box web root does not contain index.html")
for path in root.rglob("*"):
    if not path.is_file():
        continue
    try:
        content = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    # Rebase both root-relative and malformed bundle-relative URLs to the isolated mount.
    import re
    updated = re.sub(r"(?<!/openbox-lite)/api/", "/openbox-lite/api/", content)
    updated = re.sub(r"(?<!/openbox-lite)/assets/", "/openbox-lite/assets/", updated)
    # Some Open-Box bundles ship index.html with ./openbox-lite/assets/... URLs.
    # Since index.html itself lives at /openbox-lite/, that duplicates the prefix.
    updated = re.sub(r"""([\x22\x27])\./openbox-lite/assets/""", r"\1/openbox-lite/assets/", updated)
    if path == index:
        if "</head>" not in updated or "</body>" not in updated:
            raise SystemExit("ERROR: Open-Box index.html does not contain expected head/body closing tags")
        updated = updated.replace(
            "</head>",
            '<link rel="stylesheet" href="/openbox-lite/dualweb-openbox-lite-nav.css"></head>',
            1,
        )
        updated = updated.replace(
            "</body>",
            '<script src="/openbox-lite/dualweb-openbox-lite-nav.js"></script></body>',
            1,
        )
    if updated != content:
        path.write_text(updated, encoding="utf-8")
print("Prepared isolated Open-Box frontend:", index)
PYOPENBOXLITE
test -s "$OPENBOX_LITE_ROOT/index.html"

# [OPENBOX-LITE-CHECK 1/5] Validate isolated frontend assets and menu-filter hooks.
# These are build-time guards for the previous white-screen regression: the filter
# must protect structural containers and the copied index must load the injected files.
test -s "$OPENBOX_LITE_ROOT/dualweb-openbox-lite-nav.js"
test -s "$OPENBOX_LITE_ROOT/dualweb-openbox-lite-nav.css"
grep -Fq '/openbox-lite/dualweb-openbox-lite-nav.css' "$OPENBOX_LITE_ROOT/index.html"
grep -Fq '/openbox-lite/dualweb-openbox-lite-nav.js' "$OPENBOX_LITE_ROOT/index.html"
test -z "$(grep -Eo '(src|href)="\./openbox-lite/assets/[^"]+"' "$OPENBOX_LITE_ROOT/index.html" || true)"
grep -Eq '(src|href)="/openbox-lite/assets/[^"]+"' "$OPENBOX_LITE_ROOT/index.html"
while IFS= read -r asset; do
  asset_path="${asset#\"/openbox-lite/}"
  if [[ ! -s "$OPENBOX_LITE_ROOT/$asset_path" ]]; then
    echo "::error::Open-Box lite asset referenced by index.html is missing: $asset_path"
    exit 1
  fi
done < <(grep -Eo '(src|href)="/openbox-lite/assets/[^"]+"' "$OPENBOX_LITE_ROOT/index.html" | sed -E 's/^(src|href)="/"/; s/"$//')
grep -Fq 'document.querySelectorAll(".home-page, .sidebar, #app, #app-content")' "$OPENBOX_LITE_ROOT/dualweb-openbox-lite-nav.js"
grep -Fq 'el.classList.remove(HIDDEN)' "$OPENBOX_LITE_ROOT/dualweb-openbox-lite-nav.js"
grep -Fq 'item.classList.add(HIDDEN)' "$OPENBOX_LITE_ROOT/dualweb-openbox-lite-nav.js"

# [OPENBOX-LITE-CHECK 2/5] Ensure the API reverse-proxy target exists before Nginx starts.
# Keep this as a separate include from the upstream 3036 application/frontend.
OPENBOX_BACKEND_CONF="$ROOT/overlay/etc/dualweb/openbox-lite-backend.conf"
OPENBOX_BACKEND_PORT="$ROOT/overlay/etc/dualweb/openbox-lite-backend-port"
NGINX_DUALWEB_CONF="$ROOT/overlay/etc/nginx/conf.d/dualweb.conf"
test -s "$OPENBOX_BACKEND_CONF"
test -s "$OPENBOX_BACKEND_PORT"
grep -Fq 'include /etc/dualweb/openbox-lite-backend.conf;' "$NGINX_DUALWEB_CONF"
grep -Eq '^set \$openbox_backend http://127\.0\.0\.1:3036;$' "$OPENBOX_BACKEND_CONF"
grep -qx '3036' "$OPENBOX_BACKEND_PORT"
echo "[OPENBOX-LITE-CHECK 2/5] Backend include and default port 3036 are present."

# [OPENBOX-LITE-CHECK 3/5] Ensure the lite API is rebased to its own URL prefix.
grep -Fq 'location ^~ /openbox-lite/api/' "$NGINX_DUALWEB_CONF"
grep -Fq 'rewrite ^/openbox-lite/api/(.*)$ /api/$1 break;' "$NGINX_DUALWEB_CONF"
grep -Fq 'location ^~ /openbox-lite/' "$NGINX_DUALWEB_CONF"

# [OPENBOX-LITE-CHECK 4/5] Confirm the original 3036 frontend is not overwritten.
test -s "$ROOT/overlay/etc/init.d/openbox-panel"
test -s "$ROOT/overlay/etc/init.d/openbox"
test -s "$ROOT/overlay/opt/open-box/openwrt/initd/openbox-panel"
test -s "$ROOT/overlay/opt/open-box/openwrt/initd/openbox"
echo "[OPENBOX-LITE-CHECK 4/5] Original Open-Box service files and lite frontend are separate."
echo "Open-Box lite frontend copied to $OPENBOX_LITE_ROOT; original port 3036 files unchanged."

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

# Inject a fixed LuCI root password from GitHub Actions Secret.
# Only a SHA-512 crypt hash is embedded in the image; never place the plaintext secret in rootfs.
if [[ -z "$LUCI_ROOT_PASSWORD" ]]; then
  echo "::error::Configure the repository Actions secret LUCI_ROOT_PASSWORD before building."
  exit 1
fi
if [[ "$LUCI_ROOT_PASSWORD" == *$'\n'* || "$LUCI_ROOT_PASSWORD" == *:* ]]; then
  echo "::error::LUCI_ROOT_PASSWORD must not contain a newline or colon." >&2
  exit 1
fi
if ! command -v openssl >/dev/null 2>&1; then
  echo "::error::OpenSSL is required to hash LUCI_ROOT_PASSWORD." >&2
  exit 1
fi
PASSWORD_SALT="$(openssl rand -hex 8)"
PASSWORD_HASH="$(printf '%s' "$LUCI_ROOT_PASSWORD" | openssl passwd -6 -salt "$PASSWORD_SALT" -stdin)"
unset LUCI_ROOT_PASSWORD PASSWORD_SALT
if [[ "$PASSWORD_HASH" != '$6$'* ]]; then
  echo "::error::Failed to generate a SHA-512 crypt hash for the LuCI password." >&2
  exit 1
fi
mkdir -p "$ROOT/overlay/etc/dualweb" "$ROOT/overlay/etc/uci-defaults"
printf '%s' "$PASSWORD_HASH" > "$ROOT/overlay/etc/dualweb/luci-root-password-hash"
chmod 0600 "$ROOT/overlay/etc/dualweb/luci-root-password-hash"
unset PASSWORD_HASH
cat > "$ROOT/overlay/etc/uci-defaults/98-dualweb-luci-password" <<'LUCI_PASSWORD_DEFAULTS'
#!/bin/sh
set -eu
HASH_FILE=/etc/dualweb/luci-root-password-hash
if [ -s "$HASH_FILE" ]; then
    _dualweb_hash="$(cat "$HASH_FILE")"
    case "$_dualweb_hash" in
        '$6$'*) ;;
        *) logger -t dualweb "Invalid root password hash; refusing to alter /etc/shadow."; exit 1 ;;
    esac
    awk -F: -v hash="$_dualweb_hash" 'BEGIN { OFS=":" } $1 == "root" { $2 = hash; found = 1 } { print } END { if (!found) exit 1 }' /etc/shadow > /etc/shadow.dualweb
    chmod 0600 /etc/shadow.dualweb
    mv /etc/shadow.dualweb /etc/shadow
    if awk -F: '$1 == "root" && $2 != "" && $2 != "!" && $2 != "*" { ok = 1 } END { exit !ok }' /etc/shadow; then
        rm -f "$HASH_FILE"
        logger -t dualweb "LuCI root password initialized successfully."
    else
        logger -t dualweb "Root password initialization verification failed."
        exit 1
    fi
fi
exit 0
LUCI_PASSWORD_DEFAULTS
chmod 0755 "$ROOT/overlay/etc/uci-defaults/98-dualweb-luci-password"

mkdir -p "$IBDIR/files"
cp -a "$ROOT/overlay/." "$IBDIR/files/"

# [OPENBOX-LITE-CHECK 5/5] Verify all critical Open-Box files made it into ImageBuilder FILES.
for required in \
  www/dualweb/openbox-lite/index.html \
  www/dualweb/openbox-lite/dualweb-openbox-lite-nav.js \
  www/dualweb/openbox-lite/dualweb-openbox-lite-nav.css \
  etc/dualweb/openbox-lite-backend.conf \
  etc/dualweb/openbox-lite-backend-port \
  etc/nginx/conf.d/dualweb.conf \
  etc/init.d/openbox-panel \
  etc/openclash/core/clash_meta; do
  if [[ ! -s "$IBDIR/files/$required" ]]; then
    echo "::error::Open-Box integration file missing from ImageBuilder FILES: $required"
    exit 1
  fi
done
echo "[OPENBOX-LITE-CHECK 5/5] Open-Box lite frontend, backend include, Nginx route and original service are staged."

PACKAGES_BASE="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT/packages.txt" | tr '\\' ' ' | xargs)"
PACKAGES="$PACKAGES_BASE"
if [[ "$VANTAGE_OK" == "1" ]]; then
  PACKAGES="$PACKAGES $VANTAGE_PACKAGES"
fi
echo "========== Verify package manifest =========="
if ! make -C "$IBDIR" manifest PROFILE=generic PACKAGES="$PACKAGES"; then
  if [[ "$VANTAGE_OK" == "1" ]]; then
    echo "::warning::Vantage packages failed ImageBuilder dependency resolution; retrying without Vantage."
    VANTAGE_OK=0
    PACKAGES="$PACKAGES_BASE"
    rm -f "$IBDIR/packages/luci-theme-vantage-"*.apk \
          "$IBDIR/packages/luci-app-vantage-"*.apk \
          "$IBDIR/packages/luci-i18n-vantage-zh-cn-"*.apk
    make -C "$IBDIR" manifest PROFILE=generic PACKAGES="$PACKAGES"
  else
    exit 1
  fi
fi
if [[ "$VANTAGE_OK" == "1" ]]; then
  mkdir -p "$IBDIR/files/etc/dualweb"
  : > "$IBDIR/files/etc/dualweb/.vantage-installed"
  chmod 0644 "$IBDIR/files/etc/dualweb/.vantage-installed"
fi
echo "========== Build firmware =========="
if ! make -C "$IBDIR" image PROFILE=generic PACKAGES="$PACKAGES" FILES="$IBDIR/files" BIN_DIR="$OUT" ROOTFS_PARTSIZE=2048; then
  if [[ "$VANTAGE_OK" == "1" ]]; then
    echo "::warning::ImageBuilder could not install Vantage; retrying firmware build without Vantage."
    VANTAGE_OK=0
    PACKAGES="$PACKAGES_BASE"
    rm -f "$IBDIR/files/etc/dualweb/.vantage-installed"
    find "$OUT" -maxdepth 1 -type f -delete
    make -C "$IBDIR" clean || true
    make -C "$IBDIR" manifest PROFILE=generic PACKAGES="$PACKAGES"
    make -C "$IBDIR" image PROFILE=generic PACKAGES="$PACKAGES" FILES="$IBDIR/files" BIN_DIR="$OUT" ROOTFS_PARTSIZE=2048
  else
    exit 1
  fi
fi
if [[ "$VANTAGE_OK" == "1" ]]; then
  echo "Vantage status: INSTALLED in the firmware."
else
  echo "::warning::Vantage status: MISSING; Bootstrap remains the default LuCI theme."
fi
test -s "$IBDIR/files/etc/openclash/core/clash_meta"
echo "OpenClash core status: PREINSTALLED ($("$IBDIR/files/etc/openclash/core/clash_meta" -v 2>&1 | head -n 1))"
# Keep exactly one distributable firmware file: generic squashfs combined image.
IMAGE="$(find "$OUT" -maxdepth 1 -type f -name '*-generic-squashfs-combined.img.gz' -print -quit)"
if [[ -z "$IMAGE" ]]; then
  echo "ERROR: ImageBuilder did not produce *-generic-squashfs-combined.img.gz" >&2
  find "$OUT" -maxdepth 1 -type f -printf '%f (%s bytes)\n'
  exit 1
fi
IMAGE_NAME="$(basename "$IMAGE")"
find "$OUT" -maxdepth 1 -type f ! -name "$IMAGE_NAME" -delete
test -s "$OUT/$IMAGE_NAME"
echo "Build complete: $OUT/$IMAGE_NAME"
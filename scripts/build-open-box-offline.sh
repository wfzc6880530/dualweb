#!/usr/bin/env bash
# Build a LOCAL, single-file offline Open-Box installer.
# Do not upload the generated .run to a public release/artifact unless redistribution is authorized.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT="${OPENBOX_INPUT_DIR:-$ROOT/offline/open-box}"
OUT="${OPENBOX_OUTPUT_DIR:-$ROOT/output}"
ARCHIVE="${OPENBOX_ARCHIVE:-$INPUT/open-box-linux-x64.tar.gz}"
PACKAGES="$INPUT/packages"
WORK="$ROOT/work/open-box-offline"
RUN="$OUT/open-box.run"
VERSION="${OPENBOX_VERSION:-v0.1.336}"
EXPECTED_SHA256="${OPENBOX_SHA256:-5ed7a868c0113031560c73c233385c404f66d2032c0089ba8b0d75de96f2f4b3}"

die() { echo "ERROR: $*" >&2; exit 1; }
command -v tar >/dev/null || die "缺少 tar"
command -v sha256sum >/dev/null || die "缺少 sha256sum"
command -v awk >/dev/null || die "缺少 awk"
[[ -s "$ARCHIVE" ]] || die "找不到官方 Open-Box 发行包：$ARCHIVE"
[[ -d "$PACKAGES" ]] || die "找不到依赖目录：$PACKAGES"

ACTUAL_SHA256="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
if [[ -n "$EXPECTED_SHA256" && "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  die "Open-Box 文件 SHA256 不匹配。期望 $EXPECTED_SHA256，实际 $ACTUAL_SHA256"
fi

# Require the matching target packages to be supplied locally. Package names must
# match ImmortalWrt 25.12.2 x86/64 and the target kernel; do not fetch anything online.
for pkg in kmod-tun kmod-nft-queue kmod-nft-nat kmod-veth ip-full ca-bundle luci-base; do
  if ! find "$PACKAGES" -maxdepth 1 -type f -name "${pkg}-*.apk" -print -quit | grep -q .; then
    die "缺少离线依赖 ${pkg}-*.apk。请从与目标固件完全匹配的软件包仓库准备到 $PACKAGES"
  fi
done

rm -rf "$WORK"
mkdir -p "$WORK/payload/openbox" "$WORK/payload/packages" "$OUT"
tar -xzf "$ARCHIVE" -C "$WORK/payload/openbox"
[[ -d "$WORK/payload/openbox/openwrt/luci/root" ]] || die "官方压缩包缺少 openwrt/luci/root，发行包结构不匹配"
[[ -d "$WORK/payload/openbox/openwrt/luci/htdocs" ]] || die "官方压缩包缺少 openwrt/luci/htdocs"
[[ -f "$WORK/payload/openbox/openwrt/initd/openbox" ]] || die "官方压缩包缺少 openbox init 脚本"
[[ -f "$WORK/payload/openbox/openwrt/initd/openbox-panel" ]] || die "官方压缩包缺少 openbox-panel init 脚本"
find "$PACKAGES" -maxdepth 1 -type f -name '*.apk' -exec cp -f {} "$WORK/payload/packages/" \;
cat > "$WORK/payload/INSTALL-METADATA.txt" <<EOF
Open-Box offline installer (locally generated)
Version: $VERSION
Target: ImmortalWrt 25.12.2 x86_64 (x86/64)
Official archive: $(basename "$ARCHIVE")
Official archive SHA256: $ACTUAL_SHA256
Packages: bundled local APKs only; no online repository access during installation.
Generated for personal use. Respect upstream license and copyright terms.
EOF

cat > "$WORK/header" <<'INSTALL_HEADER'
#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo "请以 root 身份运行。" >&2; exit 1; }
command -v apk >/dev/null 2>&1 || { echo "错误：未检测到 apk 包管理器。" >&2; exit 1; }
[ -r /etc/openwrt_release ] || { echo "错误：不是 OpenWrt/ImmortalWrt 系统。" >&2; exit 1; }
. /etc/openwrt_release
case "${DISTRIB_ARCH:-}" in
  x86_64) ;;
  *) echo "错误：此安装包仅适用于 x86_64；检测到 ${DISTRIB_ARCH:-未知架构}。" >&2; exit 1 ;;
esac
case "${DISTRIB_RELEASE:-}" in
  25.12*) ;;
  *) echo "警告：此包为 ImmortalWrt 25.12.x 构建，当前系统版本为 ${DISTRIB_RELEASE:-未知}。" >&2
     echo "为避免内核模块不兼容，默认停止安装。" >&2; exit 1 ;;
esac
SELF="$0"
TMP="$(mktemp -d /tmp/open-box-offline.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT INT TERM
LINE="$(awk '/^__OPENBOX_OFFLINE_PAYLOAD__$/ {print NR; exit}' "$SELF")"
[ -n "$LINE" ] || { echo "安装包损坏：缺少 payload 标记。" >&2; exit 1; }
tail -n "+$((LINE + 1))" "$SELF" | tar -xz -C "$TMP"
[ -d "$TMP/openbox/openwrt/luci/root" ] || { echo "安装包内容不完整。" >&2; exit 1; }
echo "========== 安装随包提供的离线依赖（禁止联网） =========="
set -- "$TMP"/packages/*.apk
[ -f "$1" ] || { echo "安装包没有 APK 依赖。" >&2; exit 1; }
apk add --no-network --allow-untrusted "$@"
echo "========== 安装 Open-Box =========="
mkdir -p /opt/open-box /etc/init.d /usr/bin /www
# Keep existing data/configuration when upgrading.
cp -an "$TMP/openbox/." /opt/open-box/
mkdir -p /opt/open-box/data
[ -s /opt/open-box/data/panel-port ] || echo 3036 > /opt/open-box/data/panel-port
cp -an /opt/open-box/openwrt/luci/root/. /
cp -an /opt/open-box/openwrt/luci/htdocs/. /www/
install -m 0755 /opt/open-box/openwrt/initd/openbox /etc/init.d/openbox
install -m 0755 /opt/open-box/openwrt/initd/openbox-panel /etc/init.d/openbox-panel
chmod -R 0755 /opt/open-box/bin /opt/open-box/node/bin /opt/open-box/openwrt/bin 2>/dev/null || true
chmod 0755 /opt/open-box/update.sh /opt/open-box/uninstall.sh 2>/dev/null || true
ln -sf /opt/open-box/openwrt/bin/open-box /usr/bin/open-box
rm -rf /tmp/luci-*cache* 2>/dev/null || true
/etc/init.d/rpcd reload >/dev/null 2>&1 || true
/etc/init.d/openbox-panel enable >/dev/null 2>&1 || true
/etc/init.d/openbox enable >/dev/null 2>&1 || true
/etc/init.d/openbox-panel restart
echo "安装步骤完成。请检查：/etc/init.d/openbox status；/etc/init.d/openbox-panel status"
echo "注意：本安装器不会联网下载或补齐任何缺失依赖。"
exit 0
__OPENBOX_OFFLINE_PAYLOAD__
INSTALL_HEADER

cat "$WORK/header" > "$RUN"
tar -czf - -C "$WORK/payload" . >> "$RUN"
chmod 0755 "$RUN"
echo "生成完成：$RUN"
echo "文件大小：$(du -h "$RUN" | awk '{print $1}')"
echo "SHA256：$(sha256sum "$RUN" | awk '{print $1}')"

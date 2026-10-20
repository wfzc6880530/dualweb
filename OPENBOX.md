# Open-Box firmware integration

This branch builds Open-Box into the ImmortalWrt x86_64 image instead of installing it manually after flashing.

## Build behavior

- Pinned upstream bundle: `liandu2024/Open-Box` release `v0.1.341` (x64 OpenWrt bundle).
- The build downloads the release archive and its SHA256 sidecar, verifies the checksum, extracts the complete bundle into `/opt/open-box`, and stages its OpenWrt init scripts and LuCI menu/view/ACL files.
- Open-Box LuCI entry: **服务 → Open-Box** in LuCI on port 8080. The port-80 DualWeb home also provides a shortcut to that LuCI page.
- Open-Box panel port defaults to 3036, as expected by upstream. The panel service is enabled; the Open-Box transparent-proxy core is deliberately left disabled at first boot so it does not compete with the existing Nikki/Mihomo core. Enable the Open-Box core only after choosing which proxy engine should own transparent-proxy/firewall rules.
- The image build requests `ROOTFS_PARTSIZE=2048` because the full bundle contains the panel, runtime, kernel and GeoIP/GeoSite data.

## License / redistribution

Open-Box states that its own software is proprietary and redistribution is prohibited without authorization. Only distribute this firmware image and its GitHub Actions artifacts if you have obtained the required authorization from the Open-Box maintainer. Third-party components remain subject to their respective licenses.

## Verify after flashing

1. Open `http://<router-LAN-IP>:8080/` and sign in to LuCI.
2. Open **服务 → Open-Box**; the Open-Box panel should be available on port 3036.
3. Confirm Nikki/Mihomo is the only active transparent-proxy core unless you intentionally switch to Open-Box.
4. Check `logread | grep -i openbox`, `/etc/init.d/openbox-panel status`, and `/etc/init.d/openbox status` if troubleshooting is needed.

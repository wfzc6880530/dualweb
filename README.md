# ImmortalWrt x86_64 Dual Web

目标：ImmortalWrt 25.12.2 x86/64；80 端口为独立深色快捷控制台，8080 端口为 LuCI，默认主题 Vantage；代理优先使用 Nikki/Mihomo。

> 当前项目是可复现的 ImageBuilder 项目骨架，构建工作流会生成镜像；首次启动需要 WAN 可访问互联网，才能从上游仓库安装 Vantage 与 Nikki。请在测试机/虚拟机先验证，不能视为已完成硬件验收的生产固件。

## 功能
- 80/tcp：Nginx + 独立首页，状态、WAN DHCP/PPPoE/静态 IP、Nikki 开关、Mihomo 策略组/节点选择。
- 8080/tcp：LuCI；Vantage 主题及 Nikki 管理界面通过首次启动安装脚本安装。
- WAN 修改：先导出 network 配置，启动 120 秒回滚看门狗；浏览器确认新地址可访问后点“确认应用”，否则自动恢复旧配置。
- 认证：首次启动生成随机首页密码，写入 `/root/dualweb-initial-password.txt`，同时设置到 `/etc/dualweb/password`。登录后可改密码。密码只通过 SSH 在 LAN 内读取，首次登录后立即修改。
- Mihomo 控制器仅允许监听 `127.0.0.1:9090`，密钥由 `/etc/dualweb/mihomo-secret` 保存；不要将控制器端口暴露到 LAN/WAN。

## 重要限制/初始配置
1. Nikki 管理订阅/YAML 的配置文件结构由 Nikki 版本管理。首页的“订阅 / YAML 管理”入口打开 LuCI 的 Nikki 原生配置页，避免猜测内部配置路径而破坏订阅。节点切换走 Mihomo REST API。
2. 要启用首页节点切换，请在 Nikki 当前生效配置中配置 `external-controller: 127.0.0.1:9090` 和 `secret`，并将相同密钥写入 `/etc/dualweb/mihomo-secret`。如果 Nikki 生成配置时会覆盖该字段，请在 Nikki 的配置混入/Profile Mixin 中设置，而不是直接改运行时生成文件。
3. Vantage 官方当前声明针对 OpenWrt 25.12；项目通过其签名 APK 仓库安装 `luci-theme-vantage` 和 `luci-app-vantage`。仓库可用性或包依赖变化时，首次启动安装日志在 `/tmp/dualweb-firstboot.log`。
4. 默认 LAN 仍使用 ImmortalWrt 的默认地址（通常 `192.168.1.1`）。首次登录密码不是默认的 `root` 密码。LuCI root 密码仍需按常规设置。
5. 不建议把管理页面暴露到公网。仅允许可信 LAN 访问 80/8080；如需远程管理，请用 VPN。

## 构建
1. 将本项目推送到自己的 GitHub 仓库。
2. 打开 Actions，运行 `Build Dual Web`。
3. 下载 artifact `immortalwrt-x86-64-dualweb`。镜像包含 EFI ext4、BIOS ext4（由 ImageBuilder 支持的目标产物为准）及校验文件。
4. 先在虚拟机测试，确认 80/8080、WAN 回滚、Nikki、主题和硬件网卡，再刷入实体软路由。

也可以在 Debian/Ubuntu x86_64 上运行：
```sh
./build.sh
```

## 首次启动后建议检查
```sh
cat /root/dualweb-initial-password.txt
cat /tmp/dualweb-firstboot.log
/etc/init.d/dualweb-api status
/etc/init.d/nginx status
uci show uhttpd.main.listen_http
```
若首页无法控制节点，通常是 Nikki Profile Mixin 尚未配置 `external-controller`/`secret`，不影响 Nikki 自身代理。首页“订阅 / YAML 管理”打开 Nikki 原生管理页，订阅和 YAML 由 Nikki 自己导入和管理。

## 端口
- `http://路由器LAN地址/`：独立首页
- `http://路由器LAN地址:8080/`：LuCI/Vantage
- `http://路由器LAN地址:8080/cgi-bin/luci/admin/services/nikki`：Nikki 配置/订阅/YAML

## 安全说明
- 后端只绑定 `127.0.0.1:9090`，Nginx 反向代理到该端口。
- 后端所有写操作要求登录会话；Cookie HttpOnly + SameSite=Strict，检查 Origin。
- WAN 配置接口只允许修改 WAN 常见字段，不接受 UCI 任意键或 Shell 命令。
- WAN 自动回滚是尽力保护机制；改 LAN 地址、VLAN、设备拓扑仍可能导致短暂断连。优先在本地控制台/虚拟机测试。

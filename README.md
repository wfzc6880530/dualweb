# ImmortalWrt x86_64 Dual Web

默认 LAN 地址为 `192.168.5.254`；80 端口 DualWeb 首页初始密码为 `root`；8080 端口为 LuCI。LuCI 默认主题为 `luci-theme-vantage`，通过签名 feed 安装；如果首次启动时网络不可用，安装服务会重试。LuCI root 密码由 GitHub Actions secret `LUCI_ROOT_PASSWORD` 注入，避免将密码提交到公开仓库。

## 已纳入构建的软件

- **Nikki / Mihomo：** 构建阶段从 Nikki 官方 GitHub Release 下载适用于 ImmortalWrt 25.12、x86_64 的预编译 APK 包，并通过 ImageBuilder 打入固件，包括 `mihomo-meta`、`nikki`、`luci-app-nikki` 和简体中文语言包。默认版本为 `v1.26.2`，可通过 `NIKKI_VERSION` 覆盖。
- **LuCI 主题：** 使用 `luci-theme-vantage`；移除 Argon 优先逻辑，安装成功后自动切换为 Vantage。
- **终端：** 加入 `ttyd` 和 `luci-app-ttyd`。
- **KMS：** 加入 `vlmcsd` 和 `luci-app-vlmcsd`。
- **备份/升级：** 保留 LuCI 系统管理模块，并加入 `luci-app-attendedsysupgrade`；升级前仍应自行下载备份配置，不能把在线升级视为替代备份。
- **代理：** 保留 Nikki、PassWall 和 OpenClash 的 LuCI 软件包声明。

## 仍需单独完成的项目

**NPS：** ImageBuilder 清单包含官方 ImmortalWrt 25.12 x86_64 软件源中的 `nps`、`npc` 和 `luci-app-nps`；构建的 manifest 步骤会验证包是否可用。`luci-app-taskplan` 仍未集成。

注意：当前 ImageBuilder 集成的是官方预编译软件包，并非在 GitHub Actions 中从所有软件的源码重新编译。若上游包与目标 ImmortalWrt 版本的依赖不兼容，构建应在 manifest 阶段失败，而不是生成缺少软件的固件。

首页后端监听 `127.0.0.1:9091`，Nginx 将 `/api/` 转发到该端口。


构建验证说明：若 `LUCI_ROOT_PASSWORD` 尚未配置，构建会在生成固件前终止。

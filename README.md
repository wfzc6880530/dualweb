# ImmortalWrt x86_64 Dual Web

80 端口首页初始密码固定为 `root`。首次启动后建议立即修改。8080 端口为 LuCI。

## 已纳入构建的软件

- **Nikki / Mihomo：** 构建阶段从 Nikki 官方 GitHub Release 下载适用于 ImmortalWrt 25.12、x86_64 的预编译 APK 包，并通过 ImageBuilder 打入固件，包括 `mihomo-meta`、`nikki`、`luci-app-nikki` 和简体中文语言包。默认版本为 `v1.26.2`，可通过 `NIKKI_VERSION` 覆盖。
- **LuCI 主题：** 将 Argon 设为首选主题；只有主题文件确实存在时才切换，未安装时不强行设置。
- **终端：** 加入 `ttyd` 和 `luci-app-ttyd`。
- **KMS：** 加入 `vlmcsd` 和 `luci-app-vlmcsd`。
- **备份/升级：** 保留 LuCI 系统管理模块，并加入 `luci-app-attendedsysupgrade`；升级前仍应自行下载备份配置，不能把在线升级视为替代备份。
- **代理：** 保留 Nikki、PassWall 和 OpenClash 的 LuCI 软件包声明。

## 仍需单独完成的项目

NPS 和 `luci-app-taskplan` 不是本项目当前已验证的 ImageBuilder 标准包；不能只把名字写进 `packages.txt` 就声称已安装。NPS 需要为路由器建立可维护的启动服务、配置目录和非冲突的管理端口；Taskplan 需要为 ImmortalWrt 25.12/APK 目标提供匹配的构建包。两者在完成来源、依赖和启动验证前不会被标记为“已集成”。

注意：当前 ImageBuilder 集成的是官方预编译软件包，并非在 GitHub Actions 中从所有软件的源码重新编译。若上游包与目标 ImmortalWrt 版本的依赖不兼容，构建应在 manifest 阶段失败，而不是生成缺少软件的固件。

首页后端监听 `127.0.0.1:9091`，Nginx 将 `/api/` 转发到该端口。

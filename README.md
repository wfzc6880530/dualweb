# ImmortalWrt x86_64 Dual Web

80 端口首页初始密码固定为 `root`。首次启动后建议立即修改。8080 端口为 LuCI。

**Nikki / Mihomo：** 构建阶段从 Nikki 官方 GitHub Release 下载适用于 ImmortalWrt 25.12、x86_64 的预编译 APK 包，并通过 ImageBuilder 打入固件，包括 `mihomo-meta`、`nikki`、`luci-app-nikki` 和简体中文语言包。路由器首次启动不再需要连接 GitHub 下载这些软件。默认 Nikki 版本为 `v1.26.2)，可在构建环境中通过 `NIKKI_VERSION` 覆盖。

注意：这是将官方预编译 APK 包集成进固件镜像，不是在 GitHub Actions 中从 Nikki 源码重新编译其软件包。若官方发布包与所选 ImmortalWrt ImageBuilder 的依赖不兼容，构建会在 manifest 阶段失败，而不是生成一个缺少 Nikki 的固件。

首页后端监听 `127.0.0.1:9091)，Nginx 将 `/api/` 转发到该端口。

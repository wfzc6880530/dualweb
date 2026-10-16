# ImmortalWrt x86_64 Dual Web

80 端口首页初始密码固定为 `root`。首次启动后建议立即修改。8080 端口为 LuCI。

**Nikki / Mihomo 安装说明：** 当前固件通过 procd 后台服务在首次启动后联网安装 `nikki`、`mihomo-meta`、`luci-app-nikki` 和中文语言包；它们不是静态预装在镜像里的。服务会持续重试网络/软件源，直到检测到 Nikki 与 Mihomo 已安装。安装日志：`/tmp/dualweb-firstboot.log`。首页后端监听 `127.0.0.1:9091`，Nginx 将 `/api/` 转发到该端口。

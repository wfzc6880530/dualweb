# DualWeb + Zashboard

Zashboard 集成在 80 端口 DualWeb 首页中，登录后点击“ Mihomo 代理面板 ”即可内嵌打开。

## 结构

- DualWeb 首页：`http://路由器IP/`
- Zashboard 静态文件：`/www/dualweb/zashboard/`
- Clash API 同源代理：`/clash/` -> `127.0.0.1:9090`
- LuCI：TCP 8080

当前 main 分支的固件包清单使用 Nikki/Mihomo，因此集成默认连接其 Clash-compatible API。若改用 OpenClash，请确保 OpenClash 的 external-controller 监听路由器本机 9090 端口，并停用/避免两个核心同时占用同一端口。

首次打开 Zashboard 后，API 地址使用当前路由器的 80 端口和路径 `/clash`；在连接设置中填写对应核心的 `secret`。不要把 9090 直接暴露到 WAN。Nginx 的 `/clash/` 只允许 RFC1918 私有网段来源访问。

## 独立更新

SSH 登录路由器执行：

```sh
/usr/sbin/dualweb-update-zashboard
```

脚本从 Zashboard 官方 Release 下载并验证 ZIP，再替换静态文件，不需要重编译固件。更新失败时会尝试恢复旧版。确认新面板可用后，可删除 `/www/dualweb/zashboard.previous`。

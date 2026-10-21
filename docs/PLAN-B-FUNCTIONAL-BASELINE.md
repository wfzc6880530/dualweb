# B 方案：功能优先的固件验收基线

更新时间：2026-10-21

## 本轮决策

用户确认采用 B 方案，但当前阶段以功能完善和可启动固件为第一优先级。外观允许朴素，不再为细小字号、边距和装饰反复改动。优先保证现有功能不回归，再做少量一致性调整。

本分支从 `feature/2026-10-21-openbox-backend-port` 创建，保留该分支已有实现，不直接改动 `main`。

## 必须保留的边界

- 80 端口：DualWeb 首页、登录/会话、WAN 配置相关页面和本地 API。
- 80 端口 `/openbox-lite/`：只保留“概览、代理、规则”导航；页面 API 经独立路径反代到 Open-Box 后端。
- 3036 端口：官方 Open-Box 原版独立运行。不得改动其原始前端、JS、API 逻辑或数据。
- 8080 端口：保留完整 LuCI 管理入口，不用 80 端口精简页面替代。
- Zashboard：保留其独立静态资源路径及代理控制面板，不修改打包 JS。
- 代理内核：Open-Box 代理核心默认不启用，避免与 Nikki/Mihomo、OpenClash、PassWall 同时接管流量。

## 当前构建基线（代码配置，不等同于刷机实测）

- 基础：ImmortalWrt x86/64 ImageBuilder，默认版本 25.12.2。
- 首页：Nginx 80 端口；Go API 监听本机 127.0.0.1:9091。
- LuCI：8080；构建尝试预装 Vantage，下载/校验失败时允许回退 Bootstrap。
- 代理：Nikki/Mihomo、OpenClash 及其 Meta 兼容内核，另保留 PassWall 软件包声明。
- 工具：NPS/NPC、ttyd、vlmcsd、备份/升级相关包。
- Open-Box：构建阶段下载官方 x86_64 包并校验 SHA256；3036 面板与 80 端口 lite 页面分离。
- 默认 LAN 地址：192.168.5.254。

注意：ImageBuilder 主要将预编译包和 overlay 集成进镜像，并非把所有第三方软件都从源码编译。包可安装不代表所有功能已在设备上验收。

## 本轮验证清单

### 构建阶段
- [ ] 工作流在本测试分支触发。
- [ ] Go API 编译成功。
- [ ] Nikki/Mihomo、OpenClash APK 与内核通过下载和校验。
- [ ] Open-Box 包、校验文件及 lite 前端资源检查通过。
- [ ] ImageBuilder 包依赖解析通过，生成固件镜像和 manifest。
- [ ] 构建产物上传成功。

### 刷机后
- [ ] LAN 地址及 80/8080 端口符合预期。
- [ ] 80 端口登录后刷新仍保持有效会话，首页 API 无 502/权限错误。
- [ ] WAN 设置可读取、保存；错误配置回滚机制可用。
- [ ] 3036 原版 Open-Box 可独立打开和登录。
- [ ] 80 端口 `/openbox-lite/` 登录、概览、代理、规则可用；不出现空白页或静态资源 404。
- [ ] 8080 LuCI 登录、导航、软件包页面可用。
- [ ] Zashboard 页面可打开；代理控制请求指向正确内核 API。
- [ ] 初次启动没有多个代理服务同时自动接管流量；默认路由和 DNS 正常。
- [ ] 重启后以上服务仍正常。

## 风险与未验收项

1. Vantage 下载/依赖失败时可能回退 Bootstrap，因此需要查看构建日志及刷机后的实际主题。
2. 第三方 APK 与 ImmortalWrt 25.12 的依赖兼容性以 ImageBuilder 实际解析结果为准。
3. NPS、PassWall、OpenClash、Nikki/Mihomo 的软件包进入固件不等于配置已完成，也不应默认同时启用。
4. Open-Box 上游版本变化可能改变前端路径或 DOM，构建时资源检查通过后仍需在浏览器实测。
5. Open-Box 上游许可限制再分发；发布固件或分享 artifact 前需遵守其许可条款。
6. 初始首页密码目前为 `root`，刷机后应立即更改；LuCI root 密码依赖 GitHub Actions Secret `LUCI_ROOT_PASSWORD`。

## 变更纪律

- 先在测试分支编译和验证，不直接合并到 `main`。
- 不修改 3036 原版 Open-Box 资源；只修改复制到 `/www/dualweb/openbox-lite` 的精简副本。
- 不修改打包的业务 JS/API 来实现纯样式调整。
- 每次失败先定位首个失败步骤，再修复，不通过忽略错误或降低校验标准来“做绿”。

# Open-Box 本地完整离线包（个人使用）

本仓库只提供打包脚本，不在公开 GitHub Actions 产物中分发 Open-Box 专有程序。生成的 `open-box.run` 应保存在你自己的电脑/构建机上，仅供你有权使用的环境安装；不要上传到公开仓库或公开发布。

## 目标

- 目标系统：ImmortalWrt 25.12.x，x86_64。
- 输出文件：`output/open-box.run`。
- 安装过程不访问 GitHub 或软件源；依赖不齐、架构不符或系统版本不匹配时停止。
- 包含官方 Open-Box 发行压缩包、你准备的匹配 APK 依赖，以及安装脚本。
- 此脚本不修改 DualWeb 的 `main` 分支，也不会将 Open-Box 加进 `dualweb-all-plugins.run`。

## 1. 准备官方发行包

从官方发行页下载与你要安装的版本匹配的 Linux x64 完整包：

https://github.com/liandu2024/Open-Box/releases

当前脚本默认版本为 `v0.1.336`，文件名：

`open-box-linux-x64.tar.gz`

将文件放到：

`offline/open-box/open-box-linux-x64.tar.gz`

默认 SHA-256 校验值（v0.1.336 x64）：

```
5ed7a868c0113031560c73c233385c404f66d2032c0089ba8b0d75de96f2f4b3
```

若你选择其他版本，必须同时核实官方校验值、发行包目录结构和该版本的许可，再通过环境变量 `OPENBOX_VERSION`、`OPENBOX_SHA256` 指定；不要直接复用旧版本的校验值。

## 2. 准备完全匹配的 APK 依赖

创建目录：

```sh
mkdir -p offline/open-box/packages
```

将下列包及它们的全部未预装传递依赖放进该目录：

- `kmod-tun`
- `kmod-nft-queue`
- `kmod-nft-nat`
- `kmod-veth`
- `ip-full`
- `ca-bundle`
- `luci-base`

**必须使用与你的目标固件完全一致的 ImmortalWrt 25.12.x x86_64 软件包仓库和内核 ABI。** 尤其 `kmod-*` 内核模块不可以混用不同固件构建、内核版本或 ABI。为确保真正离线，目录还必须包含上述 APK 的全部缺失依赖；脚本会把目录中所有 `.apk` 一并打包。

如果拿不到匹配的 APK 文件，不要从其他 OpenWrt/ImmortalWrt 版本凑包。应使用与目标固件同一构建来源的 ImageBuilder/软件包仓库重新准备依赖。

## 3. 在自己的构建机生成 .run

在仓库根目录执行：

```sh
bash scripts/build-open-box-offline.sh
```

如使用不同路径：

```sh
OPENBOX_INPUT_DIR=/你的路径/open-box \
OPENBOX_OUTPUT_DIR=/你的输出目录 \
bash scripts/build-open-box-offline.sh
```

成功后生成 `output/open-box.run`，脚本会输出最终 SHA-256。这个文件可能较大，因为官方完整发行包本身包含核心、运行时和地理数据库。

## 4. 在目标路由器安装

先备份配置，再通过 SCP/WinSCP 将 `open-box.run` 上传到路由器，例如 `/tmp/open-box.run`，然后执行：

```sh
chmod 755 /tmp/open-box.run
/tmp/open-box.run
```

安装器要求 root 权限、`apk` 包管理器、x86_64 和 ImmortalWrt 25.12.x。它使用 `apk add --no-network`，不会联网补包。安装后检查：

```sh
/etc/init.d/openbox-panel status
/etc/init.d/openbox status
logread | grep -i openbox | tail -n 80
```

## 重要限制

- 这不是公开下载产物；请勿将包含上游受限程序的生成文件上传到公开 GitHub Actions artifacts/releases。
- 本脚本只负责本地封装，不替代对上游许可的核实。
- `.run` 无法绕过内核 ABI 或包依赖兼容性要求。
- 在真实路由器安装前，建议先在相同固件版本的测试设备验证；安装代理/防火墙组件可能影响现有透明代理规则。

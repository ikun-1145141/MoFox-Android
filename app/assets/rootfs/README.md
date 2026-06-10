# 内嵌 Ubuntu rootfs

打包前 CI / 本地脚本（`tools/build.py --fetch-rootfs <abi>`）会把对应 ABI 的 rootfs tar.xz 下载到这里：

- `ubuntu-26.04-aarch64.tar.xz`（arm64-v8a 的 Android 设备）
- `ubuntu-26.04-arm.tar.xz`（armeabi-v7a，兼容旧设备）
- `ubuntu-26.04-x86_64.tar.xz`（x86_64 模拟器调试）
- `ubuntu-26.04.sha256`：每行 `<sha256>  ubuntu-26.04-<abi>.tar.xz`

> 大文件不入仓。CI 按 ABI 分开下载并构建 APK，避免单个 APK 内置无用架构的 rootfs。

## 解压时机

由 Kotlin 端 `RootfsInstaller` 在 OOBE 「解压 Ubuntu rootfs」阶段从 APK assets 流式解包到：

```
$filesDir/usr/var/lib/proot-distro/installed-rootfs/ubuntu/
```

随后写入清华源镜像、`/etc/resolv.conf`、保留 `/root` 用户目录。详见 [`ARCHITECTURE.md`](../../../ARCHITECTURE.md) §5。

## 来源

rootfs 来自 [MoFox-Studio releases](https://github.com/MoFox-Studio/) 上传的 ubuntu-base 26.04 / forky tar.xz——基于上游 [ubuntu-base](http://cdimage.ubuntu.com/ubuntu-base/) 重新打包，预装：

- `apt`/`dpkg` 基础工具
- 清华大学开源镜像站 `sources.list`
- 适配 Android proot 环境的 `/etc/resolv.conf`、`/etc/hosts`

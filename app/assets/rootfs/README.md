# 内嵌 Debian 13 (trixie) rootfs

打包前 CI / 本地脚本（`tools/build.py --fetch-rootfs <abi>`）会把对应 ABI 的 rootfs tar.xz 下载到这里：

- `debian-13-arm64-v8a.tar.xz`（arm64-v8a 的 Android 设备）
- `debian-13-armeabi-v7a.tar.xz`（armeabi-v7a，兼容旧设备）
- `debian-13-x86_64.tar.xz`（x86_64 模拟器调试）
- `debian-13.sha256`：每行 `<sha256>  debian-13-<abi>.tar.xz`

> 大文件不入仓。CI 按 ABI 分开下载并构建 APK，避免单个 APK 内置无用架构的 rootfs。

## 解压时机

由 Kotlin 端 `RootfsInstaller` 在 OOBE 「解压 rootfs」阶段从 APK assets 流式解包到：

```
$filesDir/usr/var/lib/proot-distro/installed-rootfs/debian/
```

随后写入清华源镜像、`/etc/resolv.conf`、保留 `/root` 用户目录。详见 [`ARCHITECTURE.md`](../../../ARCHITECTURE.md) §5。

## 来源

rootfs 来自 [LXC images](https://images.linuxcontainers.org/) 的 `debian/trixie/<arch>/default/` 每日构建——基于上游 Debian trixie 重新打包，预装：

- `apt`/`dpkg` 基础工具
- 清华大学开源镜像站 `sources.list`
- 适配 Android proot 环境的 `/etc/resolv.conf`、`/etc/hosts`

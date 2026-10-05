# 随 APK 分发的插件包（.mfp）

放入本目录的 `*.mfp` 会由 `RootfsInstaller.stageBundledPlugins()` 铺发到
rootfs 的 `/root/.mofox/plugin-cache/`，bot 进程脚本每次启动时从这里复制
进实例的 `plugins/` 目录——升级 APK 即升级插件，旧实例无需重装。

当前清单为空：QQ 适配器使用 bot 仓库（Neo-MoFox）自带的 `onebot_adapter`
插件文件夹，无需经此通道分发。

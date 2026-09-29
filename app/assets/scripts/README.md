# 内置脚本

OOBE 安装阶段拷贝进 rootfs 的 shell 脚本，例如：

- `install-runtime-deps.sh`：`pkg update && pkg install python git ffmpeg ...`
- `start-bot.sh`：拉起 Neo-MoFox 主进程
- `start-snowluma.sh`：拉起 SnowLuma（Xvfb + fluxbox + LinuxQQ + SnowLuma）

## snowluma-install.sh

SnowLuma（QQ 协议端，OneBot v11）的本地安装脚本，非容器部署，在 proot Debian
rootfs 内以 root 运行，由原生层 `installSnowluma` 任务触发（asset 会被 stage 到
`/usr/local/bin/snowluma-install.sh`）。流程：

1. 安装系统依赖（Xvfb / fluxbox / CJK 字体 / Electron 运行库等）。
2. 安装 Node.js 24 LTS（npmmirror，nodejs.org 兜底；SnowLuma lite 包不带运行时），
   并尝试 `setcap cap_sys_ptrace`（失败仅告警，proot 下依赖同 uid ptrace）。
3. rootless 解压 LinuxQQ（`dpkg -x` 到 `~/snowluma/opt/QQ`，不做 NapCat 式 patch）。
4. 从 GitHub Release 下载 SnowLuma `-lite` tarball（API 直连 + 代理测速），解到 `~/snowluma/app`。
5. 冻结 QQ 静默热更新（`qqpatch.gtimg.cn` 指向 0.0.0.0），生成 WebUI 密码文件
   `~/snowluma/secrets/webui_password`。

重装前会自动备份/恢复 `~/snowluma/app/config`（协议配置与登录态）。

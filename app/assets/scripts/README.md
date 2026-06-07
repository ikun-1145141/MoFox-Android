# 内置脚本

OOBE 安装阶段拷贝进 rootfs 的 shell 脚本，例如：

- `install-runtime-deps.sh`：`pkg update && pkg install python git ffmpeg ...`
- `start-bot.sh`：拉起 Neo-MoFox 主进程
- `start-napcat.sh`：拉起 Napcat

目前为空，等运行时模块对接后再补。

# snowluma_trampoline 插件说明

> ⚠️ **状态更新（2026-10-02）**：本插件的功能已**原生整合进 App 本体**
> （snowluma 进程脚本直接创建影子路径、铺发跳板并把跳板并入 QQ 的
> LD_PRELOAD 链；bot 启动自愈会清理遗留的插件分发包）。本文保留作历史
> 说明与排障参考；手动安装 .mfp 仍可工作，但不再必要。

> SnowLuma 引擎启动跳板 + proot 宿主路径影子化的 bot 侧独立分发形态。
> 适用于：不更新 App、只想在现有实例上启用修复的场景；或作为诊断工具。
> 包体：`app/assets/plugins/snowluma_trampoline-1.1.0.mfp`（随 APK 铺发）。

## 解决什么问题

| 症状 | 原因 | 本插件的动作 |
| --- | --- | --- |
| OneBot 永不上线（App 检测不到 Linux QQ 登录） | 引擎休眠：LD_PRELOAD/stub 模式缺 `snowluma_linux_hook_start_dynamic` 调用 | 跳板 .so 在 Electron 就绪后执行 `stop_dynamic → start_dynamic`，强制引擎完整启动 |
| 引擎启动了但一切请求报 -39 "The QQ connection changed" | 解析失明：QQ 的 maps 里模块路径是宿主形态（`/data/data/...`），guest 内 ENOENT | 在 rootfs 内创建影子符号链接，让引擎的 open 成功 |

完整因果链与实验证据见 [snowluma-proot-engine-fix.md](snowluma-proot-engine-fix.md)。

## 安装

- **随 APK 分发（推荐）**：`stageSnowlumaPlugins` 会把它铺进
  `/root/.mofox/plugin-cache/`，Bot 启动脚本自动复制进实例 `plugins/`，
  无需手动操作。
- **手动安装（不更新 App）**：把 .mfp 放入实例的
  `instances/<id>/Neo-MoFox/plugins/` 目录，重启 Bot 即可。
- 安装后插件在加载时自动部署（`config/plugins/snowluma_trampoline/config.toml`
  中 `auto_deploy = true`），**下次 SnowLuma 重启生效**。

## 部署内容（全部幂等、指纹校验）

1. **影子路径**（两个符号链接）：
   `<rootfs>/data/data/com.mofox.android/files/usr/var/lib/proot-distro/
   installed-rootfs/ubuntu/{root,usr}` → `/root`、`/usr`。
2. **跳板 .so**：插件内置 arm64 预编译产物 →
   `/usr/local/lib/snowluma-trampoline.so`（md5 比对，一致则跳过）。
3. **env 包装器**：`/usr/local/bin/env`（带插件签名的透明包装器，利用
   PATH 优先级拦截 QQ 启动的 env 调用，把跳板追加进 LD_PRELOAD）。
   目标位置已存在外来文件时**拒绝覆盖**并提示，绝不破坏环境。

跳板的行为：构造函数纯 syscall（不与 Chromium 早期 fork 竞争锁）；等待
`wrapper.node` 出现在 maps（Electron 就绪）→ `stop_dynamic` →
`start_dynamic` → 引擎以正确时机完整启动。运行日志：
`/tmp/snowluma-trampoline.log`。

## Bot 动作

| 动作 | 说明 |
| --- | --- |
| `trampoline_status` | 部署状态（.so/包装器/影子路径/hook 管道 socket/跳板日志尾部） |
| `trampoline_deploy` | 手动部署/更新（幂等） |
| `trampoline_remove` | 一键回滚（删除 .so 与包装器；影子链接保留，无副作用） |

## 配置（config/plugins/snowluma_trampoline/config.toml）

```toml
[plugin]
enabled = true          # 插件开关

[deploy]
auto_deploy = true      # 插件加载时自动部署
remove_on_disable = true

[paths]                 # 默认路径与 MoFox 运行时布局一致，一般无需修改
trampoline_so = "/usr/local/lib/snowluma-trampoline.so"
env_wrapper = "/usr/local/bin/env"
hook_runtime_dir = "/data/user/0/com.mofox.android/files/tmp/snowluma-hook"
trampoline_log = "/tmp/snowluma-trampoline.log"
```

## 排障速查（trampoline_status 的判读）

- 日志无 `start_dynamic` → 跳板未随 QQ 启动（检查包装器是否部署、
  QQ 是否在部署后重启过）；
- `start_dynamic rc=1` 但 OneBot 仍不上线 → 引擎已启动，看影子路径是否
  可达（解析失明未修复的表现）；rc=1 之后仍 -39 说明 maps 路径打不开；
- GPU 进程崩溃（App 内 QQ 窗口消失）→ 检查是否误用了 `/etc/ld.so.preload`
  （本插件不使用该机制，见 snowluma-proot-engine-fix.md §投递通道）。

## 已知边界

- 官方 ptrace 注入（`SNOWLUMA_HOOK_AUTOLOAD` 的 `loadModuleManual`）在
  proot 下不可用（QQ 被 proot 占为 tracee，attach 返回 ESRCH），本插件
  因此走 LD_PRELOAD + 跳板路线；
- 跳板只补"引擎启动"与"路径解析"两层；若 SnowLuma 上游在 stub 模式下
  另有行为变化，以 `trampoline_status` 输出为准反馈。

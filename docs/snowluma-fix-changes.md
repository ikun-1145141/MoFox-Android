# SnowLuma 分支全部更改说明（相对 main 仓库）

> 本文档覆盖 `snowluma-migration` / `fix/proot-snowluma-engine` 分支相对
> `main` 的**全部**改动。分两大部分：A. NapCat → SnowLuma 迁移（8 个提交）；
> B. proot 引擎修复（影子路径 + 引擎启动跳板，1 个提交）。
> 深度分析见 [snowluma-proot-engine-fix.md](snowluma-proot-engine-fix.md)，
> 插件专项说明见 [snowluma-trampoline-plugin.md](snowluma-trampoline-plugin.md)。

## A. NapCat → SnowLuma 迁移（提交 3a167a8..37525e0）

### 背景

NapCat 以 JS 层接入 QQNT，在真机使用中被腾讯风控识别，导致账号冻结/断线。
SnowLuma 的 LD_PRELOAD hook 方案跑在 QQ 自己的协议栈内，流量特征与真实
客户端一致，风控面更干净。因此整体替换协议端。

### 变更清单（按目录）

**Kotlin 运行时（app/android/.../runtime/）**
- `RuntimeScripts.kt`：bot/snowluma 两套进程脚本全量重写——snowluma 安装、
  Xvfb + fluxbox 虚拟桌面、QQ 启动（含 `-q` 快捷登录）、后台监控循环
  （截屏推二维码、`get_status` 登录探测、WebUI 就绪上报、hook 预加载链路
  自动诊断）、适配器配置自愈；bot 脚本启动前自动 fetch/checkout dev 分支
  核心（SnowLuma 插件需要 media_api 1.2.0）。
- `RootfsInstaller.kt`：`stageSnowlumaInstaller`（多来源下载 LinuxQQ/Node/
  SnowLuma + 魔数/大小/解压全链校验）、`stageSnowlumaPlugins`（适配器插件
  铺发到 plugin-cache）。
- `RuntimeProcessManager.kt` / `RuntimeBridgePlugin.kt`：进程管理与任务
  路由适配。

**安装脚本（app/assets/scripts/）**
- 新增 `snowluma-install.sh`（700 行）：官方 CDN 403 时自动切换 GitHub
  镜像，deb 下载后做魔数 + 大小校验、解压后验证 `opt/QQ/qq` 存在且可执行。
- 删除 `napcat-install.sh`（519 行）。

**资产（app/assets/plugins/）**
- 新增官方 `snowluma_adapter-2.2.10.mfp`（OneBot v11 适配器，reverse WS）
  与 `snowluma_extension-1.0.11.mfp`（群管/表情/戳一戳等扩展动作）。

**Dart 层（app/lib/）**
- napcat → snowluma 全量重命名（约 17 个文件）；
- 扫码登录从模态 bottomSheet 改为页面内 Stack 浮层（修复 go_router 嵌套
  导航导致的反复弹窗与空断言红屏），新增手动收起/恢复与快捷登录
  （xdotool 向虚拟屏幕发回车）；
- 进程控制台：事件流解析、`MOFOX_LOGIN_OK / MOFOX_QR_IMAGE /
  MOFOX_WEBUI_URL` 标记处理；
- 备份、设置、向导、OOBE 相应适配。

**测试**
- 122 个测试全部通过（新增事件流解析、QR 浮层等 11 个测试文件级改动）。

**文档**
- `docs/agent-handoff-snowluma-migration.md`（迁移交接报告，含 10 轮真机
  排错记录）、`docs/android-deployment-guide.md` 等同步更新。

## B. proot 引擎修复（本次提交）

### 背景

迁移后真机上 OneBot 仍永不上线。真机定位出四层因果链，全部无 root 修复：

1. **bot 核心过旧**：适配器要求 media_api 1.2.0（dev 分支），main 核心
   被加载器拒载 → 适配器从未注册。
2. **引擎休眠**：LD_PRELOAD/stub 模式从未调用
   `snowluma_linux_hook_start_dynamic`（官方 ptrace 注入器的最后一步），
   引擎静默休眠。
3. **解析失明**：QQ 的 `/proc/self/maps` 中模块路径是宿主形态
   （`/data/data/...`），引擎要在进程内打开这些路径做目标解析，guest 内
   ENOENT → 钩子永不安装 → 一切请求报 -39 "The QQ connection changed"。
4. **投递通道**：`/etc/ld.so.preload` 会毒化 Chromium 沙箱子进程
   （GPU 进程 1002 崩溃），必须走 env 型 LD_PRELOAD。

### 变更清单

| 文件 | 变更 |
| --- | --- |
| `RuntimeScripts.kt` | bot 脚本 heredoc 缩进修复（trimIndent）+ dev 分支自愈；snowluma 脚本新增影子路径（rootfs 内两个符号链接，幂等）与跳板 LD_PRELOAD 追加；构建标识更新为 20261002-1 |
| `RootfsInstaller.kt` | `stageSnowlumaPlugins` 增加跳板插件 mfp 铺发 + 跳板 .so 铺到 rootfs `/usr/local/lib/`（资产缺失时静默跳过） |
| `assets/scripts/snowluma-trampoline.c` | 新增：跳板源码（构造函数纯 syscall，等待 wrapper.node 后 stop_dynamic + start_dynamic） |
| `assets/scripts/snowluma-trampoline.so` | 新增：arm64 预编译产物（在 rootfs 内用 gcc 编译，与 QQ 同 glibc 环境） |
| `assets/plugins/snowluma_trampoline-1.1.0.mfp` | 新增：bot 侧插件（自动部署影子路径/跳板/包装器，含 status/deploy/remove 三个动作） |
| `docs/snowluma-proot-engine-fix.md` | 新增：完整因果链、决定性实验、能力矩阵、回滚方式 |

### 影子路径原理（本次修复的核心）

proot 不翻译 `/proc/self/maps` 的内容：QQ 看到的模块路径是宿主真实形态。
引擎解析目标时要在进程内 `open` 这些路径，而 guest 内该绝对路径会被
proot 翻译到 rootfs 之下（不存在）。在 rootfs 内按宿主形态建目录并符号
链接到 guest 真实位置，引擎的 open 即成功——纯文件系统操作，无需 root：

```
<rootfs>/data/data/com.mofox.android/files/usr/var/lib/proot-distro/
         installed-rootfs/ubuntu/root  ->  /root
<rootfs>/data/data/com.mofox.android/files/usr/var/lib/proot-distro/
         installed-rootfs/ubuntu/usr   ->  /usr
```

### 验证（真机 Android 16 / HyperOS，两次重启自愈成功）

```
snowluma_adapter | Bot 3840642751 连接成功
[3840642751] [OneBot.WS-Client] connected ws://127.0.0.1:8095
get_status      → {"online":true,"good":true}
get_friend_list → 9 好友（协议栈完全激活）
send_private_msg → {"status":"ok","data":{"message_id":...}}
```

### 回滚

- App 侧：删 snowluma 脚本中的影子路径段与 LD_PRELOAD 跳板追加；
- bot 插件形态：`trampoline_remove` 动作一键清理（影子链接保留，无副作用）。

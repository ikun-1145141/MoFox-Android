# 交接报告：QQ 协议端 NapCat → SnowLuma（非容器部署）迁移

> 交付对象：接手 MoFox-Android 的 AI Agent / 工程师
> 迁移完成日期：2026-09-26
> 状态：代码改造完成，PC 侧验证全部通过，**真机全链路未验证**（见 §7）

---

## 1. 项目背景（30 秒版）

MoFox-Android 是一个 Flutter Android 应用：在应用私有目录里用 jniLibs 投递 bash/busybox/proot，
解压 Debian 13 (trixie) rootfs 后以 proot 容器内 root 身份运行 Neo-MoFox QQ 机器人。
QQ 协议端原本是 NapCat（注入 QQ 资源目录的方案），本次整体替换为 **SnowLuma**
（`SnowLuma/SnowLuma`，OneBot v11 协议端，官方"Linux 手动部署"即非容器方式）。

**核心设计不变**：proot Debian 内跑 LinuxQQ + 无头 X 桌面 + Node 进程；
bot（Neo-MoFox）侧零改动（协议端以反向 WS 客户端连 bot 的 8095 端口）。

## 2. 新部署形态（SnowLuma）

| 组件 | 位置（rootfs 内） | 说明 |
|---|---|---|
| Node.js 24 LTS | `/opt/node`，软链 `/usr/local/bin/node` | npmmirror 下载（nodejs.org 兜底），lite 包不带运行时 |
| LinuxQQ | `/root/snowluma/opt/QQ` | 官方 deb `dpkg -x` 解压，**无 NapCat 式 package.json patch** |
| SnowLuma | `/root/snowluma/app` | GitHub Release `SnowLuma-<TAG>-linux-<arch>-lite.tar.gz`，解包即用 |
| 无头桌面 | Xvfb `:1` 800x600x24 `-ac` + fluxbox | 进程脚本自持启动，含残留清理 |
| WebUI 密码 | `/root/snowluma/secrets/webui_password` | 安装时 `openssl rand -hex 16` 生成 |
| 屏幕截图 | `/root/snowluma/cache/screen.png` | `ffmpeg -f x11grab` 每 4s 抓帧（二维码展示用） |
| 热更新冻结 | `/etc/hosts` 加 `0.0.0.0 qqpatch.gtimg.cn` | 防静默补丁打坏版本对齐的 hook |

**运行时环境变量**（进程脚本设置）：`SNOWLUMA_ACCEPT_EULA=1`、`SNOWLUMA_ACCEPT_PRIVACY=1`
（必须同时设，否则首启交互式同意会卡死）、`SNOWLUMA_HOOK_AUTOLOAD=1`、
`SNOWLUMA_WEBUI_BOOTSTRAP_PASSWORD=<secrets 文件内容>`（≥8 字符，仅首次数据目录生效）。

**端口**：OneBot HTTP `127.0.0.1:3000`（accessToken 固定 `mofox`，登录探测用）、
反向 WS 客户端 → `ws://127.0.0.1:8095`（bot 侧不变）、WebUI `127.0.0.1:5099`。

## 3. 接口契约（跨层对齐，改任何一层必须同步其它层）

### 3.1 原生任务名（MethodChannel `mofox/runtime`，`runInstallTask(task, args)`）

| 任务 | 行为 |
|---|---|
| `installSnowluma` | 幂等：`/root/snowluma/opt/QQ/qq` 可执行 + `app/index.mjs` + `app/launcher.sh` + `node` 全在则跳过；否则执行 `/usr/local/bin/snowluma-install.sh` |
| `verifySnowluma` | 复查，退出码：21=QQ 主程序、22=index.mjs、23=node、24=xvfb-run、25=fluxbox、26=launcher.sh |
| `writeSnowlumaConfig` | 写 `/root/snowluma/app/config/onebot.json`（httpServers=[127.0.0.1:3000 token mofox] + wsClients=[ws://127.0.0.1:$wsPort role Universal reconnectIntervalMs 3000]）和 `runtime.json`（`{webuiPort:5099, hookAutoLoad:true}`）；wsPort 由 Dart 传入（默认 8095） |

已删除：`installNapcat` / `verifyNapcat` / `napcatLogin` / `writeNapcatConfig` 任务及
`cancelNapcatLogin` channel 方法（取消登录 = `stopProcess('snowluma')`）。

### 3.2 进程名与事件标记

- 进程名 `snowluma`（原 `napcat`）：`status()` map key、`startProcess/stopProcess/restartProcess` 的 name。
- 进程事件流标记行（Kotlin `RuntimeScripts.kt` 进程脚本产生 → Dart `process_console_provider._onProcessEvent` 消费）：
  - `MOFOX_QR_IMAGE=/root/snowluma/cache/screen.png` — 截屏 md5 变化且距上次 ≥4s 时发出；Kotlin `consumeProcess` 把 rootfs 路径映射为 host 路径；Dart 包成 `file:<host路径>#<版本>` 存 `snowlumaQrPayload`。
  - `MOFOX_LOGIN_OK=1` — 轮询 `curl -H "Authorization: Bearer mofox" http://127.0.0.1:3000/get_status` 命中 `"online":true` 时发出；Dart 收到后清 QR payload（旧的「配置加载」条件保留兼容）。
  - `MOFOX_WEBUI_URL=http://127.0.0.1:5099/?token=<密码>` — WebUI 就绪后发一次；Dart 正则解析存 `snowlumaWebuiUrl`（旧的 `WebUi User Panel Url:` 正则保留为 fallback）。
- 停止方式：`RuntimeProcessManager.stop('snowluma')` 直接销毁 proot 进程树（不跑 stop 脚本），Xvfb/fluxbox/QQ/node 一起死。

### 3.3 Dart 侧主要重命名（napcat → snowluma）

`ProcessConsoleNotifier`：`snowlumaStatus/snowlumaLogs/snowlumaQrPayload/snowlumaWebuiUrl/snowlumaStatusFor/startSnowluma/stopSnowluma/restartSnowluma/cancelSnowlumaLogin/_ensureSnowlumaReady`（懒安装序列 `['installSnowluma','verifySnowluma']`）；
`InstallTask.writeSnowlumaConfig`；`OobeRuntimeTask.installSnowluma/verifySnowluma`（开关 key `oobe-install-snowluma-switch`）；
`Instance.installSnowluma`（fromJson 兼容旧 key `installNapcat`，**全仓库仅此处允许出现 napcat 字样**）；
`NapcatQrSheet → SnowlumaQrSheet`（文件改名 `snowluma_qr_sheet.dart`，helper `snowlumaQr*`）；
`AssistantActionType.restartSnowluma`（wire 名 `restart_snowluma`）。

### 3.4 备份路径（backup_service.dart）

- `snowluma/config/*`（zip 前缀）↔ `/root/snowluma/app/config/*`（协议配置）
- `snowluma/login_state/*` ↔ `/root/.config/QQ/*`（QQNT 登录态；旧 NapCat 登录态路径已废弃）

### 3.5 有意保留、不要"顺手改名"的东西

- `writeAdapterBody` 里 bot 配置的 `[napcat_server]` 段 —— 属于 Neo-MoFox bot 仓库的 schema。
- MethodChannel 名 `mofox/runtime`、事件 topic、`InstallTaskResult` 结构、wsPort 默认 8095、
  OOBE/向导流程结构、`abiFilters arm64-v8a`、SnowLuma 配置里的 `accessToken:"mofox"`（与进程脚本探测一致）。

## 4. `app/assets/scripts/snowluma-install.sh` 要点

1. 依赖（apt/dnf 双分支）：xvfb fluxbox jq curl xz unzip fontconfig fonts-noto-cjk dbus-x11
   libgbm1 libnss3 + t64 探测的 GTK/alsa 等库。
2. Node 24：`registry.npmmirror.com/-/binary/node/latest-v24.x/`（nodejs.org 兜底）→ `/opt/node`；
   对真实 node 二进制 `setcap cap_sys_ptrace=ep`（失败仅告警，proot 下靠同 uid ptrace）。
3. **QQ 多来源下载**（本次踩坑重点）：
   - 来源 1：官方 `cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/linuxConfig.js` 动态地址；
   - 来源 2（当前实际在用）：GitHub 归档镜像 `Rodert/qq-versions` release
     `qq-packages-20260813-1d08f1d4`（`QQ_3.2.32_260812_arm64_01.deb` 等，amd64/rpm 也有），
     走代理测速（`network_test`，与 NapCat 时代同款 gh 加速列表）拼前缀；
   - **所有 curl 带 `-f`**，下载后校验（>100MB + deb `!<arch>` / rpm `edabeedb` 魔数），
     不合格自动删除换下一个来源；全部失败才报错。
   - 走镜像安装时写 `/root/snowluma/.qq_source_version` 记录实际版本（3.2.32-260812），
     `check_linuxqq` 读取该标记作为目标版本，**避免"官方版本号更高→每次误判需要重装"的循环**。
4. `dpkg -x` 到 `$HOME/snowluma`；重装前备份/恢复 `/root/snowluma/app/config`。
5. SnowLuma：`api.github.com/repos/SnowLuma/SnowLuma/releases/latest` 直连解析
   `linux-<arch>-lite.tar.gz` 资产（API 不能走代理，资产下载才走），回退 pin **v1.14.20**。
6. `check_linuxqq` 的"已安装"判定要求 `package.json` **且** `qq` 可执行同时存在（防残缺目录误判）。

## 5. 本机（Windows 开发机）构建环境现状

| 项 | 位置/值 | 说明 |
|---|---|---|
| Flutter SDK 3.47.5 | `D:\tools\flutter` | 不在 PATH；构建前 `export PATH="/d/tools/flutter/bin:$PATH"` |
| JDK 17 | `D:\tools\jdk-17`（JAVA_HOME 已设） | |
| Android SDK | `D:\tools\android-sdk`（ANDROID_HOME 已设） | 构建中自动补装了 platform-34、CMake 3.22.1 |
| GRADLE_USER_HOME | `D:\tools\gradle-home` | **注意不是 `~/.gradle`** |
| 阿里云镜像 init 脚本 | `D:\tools\gradle-home\init.d\aliyun-mirrors.gradle` | **必需**。Maven Central 上 `kotlin-compiler-embeddable` 的 jar 会 302 到 github.com，而本机 hosts 把 github.com 指到 127.0.0.1 → PKIX 证书错误。脚本把 central/google 换成阿里云镜像，且通过 `settingsEvaluated` 覆盖 Flutter 的 included build（其 settings 设了 `FAIL_ON_PROJECT_REPOS`，只能在 settings 级替换仓库）|
| Gradle 9.1.0 发行版缓存 | `dists/gradle-9.1.0-all/{7wzd...表示services URL, 2x09...表示腾讯URL}/` | wrapper 缓存目录名 = base36(md5(distributionUrl))；两个哈希目录都已放好完整发行版，改 distributionUrl 也不会重新下载 |

**构建命令**（Git Bash）：

```bash
export PATH="/d/tools/flutter/bin:$PATH"
cd D:/Work_Mofox/MoFox-Android-main/MoFox-Android-main/app
flutter build apk --debug --target-platform android-arm64
# 产物: app/build/app/outputs/flutter-apk/app-debug.apk → 手动复制到 dist/
```

- `tools/build.py` 存在但其 `find_flutter` 在 Windows Python 下可能选中 bash 版 flutter 导致失败，建议直接用上面的命令，或修复 find_flutter。
- 构建前置资产：`app/assets/rootfs/debian-13-arm64.tar.xz`（已下载好，86MB，来源 LXC images，
  可用 `python tools/build.py --fetch-rootfs-only` 重新拉）+ `jniLibs/arm64-v8a/` 下 6 个 .so（已在）。
- release 包未配置签名（debug 签名仅供测试）。
- `pubspec.lock`、`.dart_tool`、`analysis_options.yaml` 已恢复原始状态（flutter 工具曾自动改动，已还原）。

## 6. 验证状态

- ✅ `flutter test`：121 通过 / 0 失败（含新增的事件流解析测试）
- ✅ `dart analyze`：0 error / 0 warning（约 349 条 info 级风格提示为项目既有）
- ✅ Kotlin 编译：两次成功构建 APK 已证明
- ✅ `bash -n` 语法 + QQ 镜像下载流程实测（官方 403 → 自动切镜像 → 拉到真实 deb 魔数）
- ✅ 全仓残留检查：除 `instance.dart` 的兼容读取和 `[napcat_server]` schema（有意保留）外无 napcat 字样
- ❌ **真机全链路未验证**：OOBE 安装、截屏二维码、扫码登录、ptrace 注入、bot 收发消息

## 7. 已知风险与待办（按优先级）

1. **真机验证**（最高优先级）：装 `dist/mofox-debug-arm64-v8a-20260926-214128.apk` 跑通 OOBE → 扫码 → bot 上线。
2. **ptrace 注入设备相关性**：SnowLuma 官方文档明示 proot 下注入不保证可用（proot 本身是 ptrace 模拟层，
   两者叠加受内核/yama 影响）。症状：登录成功但 bot 收不到事件。排查看 SnowLuma 日志（会流到 App 的
   SnowLuma 日志 Tab，同时落盘 `/tmp/snowluma-run.log`）。
3. **官方 CDN 403**：qqdl.gtimg.cn 全线 403（含官方配置列出的所有文件，浏览器 UA/Referer 均无效），
   旧版本 404 已下架——镜像回退是当前唯一可用路径。若镜像失效，需找新的 LinuxQQ arm64 deb 来源
   （建议定期核对 `linuxConfig.js` 是否恢复 + Rodert 仓库是否更新版本）。
4. **二维码体验**：目前展示 800x600 整屏截图；可考虑裁剪 QQ 登录窗区域或放大截图。
5. SnowLuma 为 Alpha：回退 pin v1.14.20，升版本时注意 `onebot.json`/`runtime.json` schema 变化。
6. release 签名未配置；`dist/` 里只有 debug 包。

## 8. 变更文件清单（供 review）

- **assets**：`snowluma-install.sh`（新增）、`napcat-install.sh`（删除）、`scripts/README.md`
- **Kotlin**：`runtime/{RuntimeScripts,RootfsInstaller,RuntimeProcessManager,RuntimeBridgePlugin}.kt`
- **Dart lib（17 个）**：`runtime_bridge.dart`、`process_state.dart`、`process_console_provider.dart`、
  `wizard/{wizard_step,wizard_notifier}.dart`、`oobe/{oobe_step,oobe_flow_notifier,extract_runtime_step}`、
  `instance/instance.dart`、`snowluma_qr_sheet.dart`（改名）、`home_page.dart`、
  `instance_detail_page.dart`、`settings_page.dart`、`assistant/{assistant_models,assistant_notifier,assistant_panel}`、
  `backup/{backup_service,backup_page}.dart`
- **测试（11 个）**：oobe 三个、dashboard provider、wizard 三个+qr sheet、backup 两个、instance_deletion
- **文档（7 个）**：README、ARCHITECTURE、PRIVACY、app/README、legal/privacy、
  docs/{android-deployment-guide, terminal-ai-assistant-plan, file-manager-toml-editor-architecture}
- **注释级**：`build.gradle.kts`、`AndroidManifest.xml`、`tools/build.py`

## 9. 追加修复（2026-09-27，真机首跑 installSnowluma 失败）

**现象**：真机 OOBE 第 3 步报 `Task installSnowluma exited with 1`，日志停在"解压 QQ（.deb）失败"。

**根因**：`RootfsInstaller.stageSnowlumaInstaller()` 原实现"rootfs 内脚本存在即跳过"，
设备上残留了旧版 APK 投递的旧脚本（其日志字符串不在当前仓库中，实锤版本错位），
覆盖安装新 APK 后仍在执行旧脚本的缺陷流程。镜像 deb 本身经全量验证无损坏。

**修复**（新 APK：`dist/mofox-debug-arm64-v8a-20260927-102456.apk`）：
1. `stageSnowlumaInstaller()` 改为每次无条件从 assets 覆盖投递（脚本仅 27KB，代价可忽略）；
2. `snowluma-install.sh` 的 QQ 安装循环重构：下载→魔数/大小校验→**解压→验证
   `/root/snowluma/opt/QQ/qq` 存在且可执行**全部通过才算来源可用，任一环节失败自动换
   下一个来源（新增官方直连兜底候选），并记录包大小 + sha256 与解压工具原始输出，
   失败原因在控制台直接可见。已适配脚本的 `set -e`（`|| true` 守卫）。

**验证**：`bash -n` 通过；set -e 行为单测通过；镜像 deb 全量验证（ar 结构、xz 流完整解压
634.5MiB、1582 成员含 `opt/QQ/qq` 0755）；APK 内脚本与源码 diff 一致。
真机复测仍待执行：覆盖安装新 APK（勿卸载，保留 rootfs）→ 重试第 3 步。

## 10. 追加修复（2026-09-27 第二轮：真机跑到扫码登录后的两个问题）

真机状态：installSnowluma 已通过，SnowLuma 启动正常（WebUI 5099 监听、EULA 环境变量生效），
暴露两个新问题。

### 10.1 Hook 注入失败 `[Hook] load failed ... COMPONENT_LOAD_FAILED`

**根因（结构性）**：SnowLuma Linux 注入是原生 addon 的 ptrace 手动映射
（PTRACE_ATTACH/PEEKDATA/process_vm_* + 远程 dlopen）。proot 下所有 guest 进程已被
proot 全程 trace（单一 tracer 约束），第二个 tracer 无法 attach → 注入必然失败，
`SNOWLUMA_HOOK_AUTOLOAD` 无法挽救。

**修复（绕开 ptrace）**：反编译 SnowLuma v1.14.20 的 `native/snowluma-linux-arm64.so`，
确认它自带非 ptrace 接入协议——导出 `snowluma_linux_hook_start_dynamic` 等符号，
二进制内含 `LD_PRELOAD`、`SNOWLUMA_HOOK_RUNTIME_DIR`、`mojo.<pid>.control.sock` 协议串，
NEEDED 仅 libstdc++/libgcc/libc（rootfs 齐备）。SnowLuma 侧 PipeWatcher 会读
`/proc/<qqPid>/environ` 解析 QQ 的 runtime dir 并等待控制 socket 出现。

`RuntimeScripts.kt` 进程脚本改动：
- `mkdir -p /tmp/snowluma-hook`（两侧共享的显式 runtime dir）；
- QQ 启动加 `SNOWLUMA_HOOK_STUB_START=1 SNOWLUMA_HOOK_RUNTIME_DIR=/tmp/snowluma-hook
  LD_PRELOAD=…/snowluma-linux-arm64.so`。**SNOWLUMA_HOOK_STUB_START 必需**：反汇编确认
  构造函数仅在该 env 为 1/true/on 时才 pthread_create 启动服务线程并创建控制 socket，
  否则组件静默不工作（第一版方案漏掉它导致 QQ 窗口消失/无 socket）；
- SnowLuma 侧 export 同样的 `SNOWLUMA_HOOK_RUNTIME_DIR`；
- QQ stderr 改落盘 `/tmp/snowluma-qq.log`，监控循环检测 QQ 进程死亡并在控制台打印
  日志尾部（只报一次），`/tmp/snowluma-qq.pid` 记录 pid，启动时清理。
`SNOWLUMA_HOOK_AUTOLOAD=1` 保留：启动初期可能仍打一条注入失败 ERROR（无害），
组件 socket 出现后会话应自行转为 connecting/online。

### 10.2 扫码弹窗期间红屏崩溃 `Null check operator used on a null value`

**根因**：`instance_detail_page.dart` 的 QR listener 用共享可变字段 `_qrPayload` 记账，
弹窗 builder 异步执行 `_qrPayload!`；"二维码刷新 pop/重开"、"进程停止"、"关闭动画"
三者交错时 payload 先被置空、builder 后执行 → 空断言崩溃（红屏盖住整个页面）。

**修复**：
- `SnowlumaQrSheet` 改为 ConsumerWidget，内部 watch `snowlumaQrPayload`
  （select 最小重建），二维码刷新在弹窗内完成，**删除 pop/重开机制**；
- 详情页 listener 只负责开（`_qrSheetFuture` 幂等）与关（post-frame + canPop 防双 pop），
  全文件不再有空断言；
- provider 在 snowluma 进程 "exited with" 时同时清 `snowlumaQrPayload`，
  避免下一轮启动展示过期二维码。

**验证**：`flutter analyze` 0 error/warning；`flutter test` 121 通过 / 0 失败。
**新 APK**：`dist/mofox-debug-arm64-v8a-20260927-120018.apk`。

### 10.3 二维码弹窗"反复弹出/红屏"（2026-09-27 第三轮）

真机表现：扫码弹窗反复弹出但永远显示桌面截图，出现红屏时反而能看到二维码。

**根因**：详情页 listener 的关闭分支在关闭动画期间会被连续到来的日志事件反复命中，
每次都 postFrame `pop()` 一次——第二次 pop 把**详情页本身**顶出路由栈；之后二维码事件
又在错误页面上重开弹窗，形成开/关/顶页循环，并伴随 Navigator 状态异常（红屏）。

**修复**（APK `mofox-debug-arm64-v8a-20260927-150859.apk`）：
- 关闭分支一次性化：调度 pop 前置 `_sheetClosing=true` 并立即清空 `_qrSheetFuture`，
  动画结束（原 future whenComplete）才复位；期间禁止重开；
- 打开分支先登记 future 再写日志——日志本身会触发 listener 重入，顺序反了会
  无限递归（测试中已复现 Stack Overflow）；
- 新增可视化诊断：`appendSnowlumaNote()` 把弹窗开/关原因（`[ui] 打开/收起扫码弹窗: 原因`）、
  二维码截图事件（`[control] 检测到二维码截图更新`）、listener 异常全部写进 SnowLuma
  日志 Tab，真机无 adb 也能截图排查。listener 整体 try/catch 兜底。

注意：备份页导出的"运行日志"是 **bot（Neo-MoFox）日志**，不是 App 壳日志；App 壳的
appLogger 文件（含 Flutter 崩溃堆栈）目前没有导出入口。

### 10.4 第四轮（2026-09-27 16:15）：QQ 没启动的 bash env 坑 + 弹窗改页面内浮层

真机诊断输出（`[control] LinuxQQ 进程已退出... /bin/bash: 行 83:
SNOWLUMA_HOOK_STUB_START=1: 未找到命令`）实锤两个问题：

1. **QQ 从未启动**：`DISPLAY=:1 $QQ_HOOK_ENV qq` 里 `$QQ_HOOK_ENV` 展开出的
   `VAR=v` 词被 bash 当成**命令名**而非赋值前缀（变量展开的结果不会重新按赋值
   前缀解析）。修复：改用 `DISPLAY=:1 env $QQ_HOOK_ENV qq ...`。
2. **扫码弹窗反复弹出**：弹窗走 `showModalBottomSheet`（挂在 go_router 嵌套
   Navigator 上），嵌套导航器随状态刷新重建时模态路由被悄悄丢弃 → future 完成 →
   下一个二维码事件又重开。修复：**彻底弃用模态路由**，改为 `InstanceDetailPage`
   内的条件渲染浮层 `_QrLoginOverlay`（Stack + ModalBarrier + 底部面板），
   显隐纯由 `snowlumaRunning && payload != null && !_loginCancelled` 驱动，
   零 push/pop。`SnowlumaQrSheet` 内部继续 watch provider 实时刷新截图。

**新 APK**：`dist/mofox-debug-arm64-v8a-20260927-161528.apk`。测试 122 全过。

### 10.5 第五轮（2026-09-27 17:04）：真机扫码登录成功！剩余：面板不自动关 + hook 待确认

**里程碑**：QQ 在 proot 内完整启动，用户扫码登录成功，QQ 主界面正常显示——
LD_PRELOAD 预加载不干扰 QQ，安装→启动→登录链路全通。

**遗留 1**：登录后面板不自动关闭。面板的自动关闭条件是监控循环探测到
`http://127.0.0.1:3000/get_status` 返回 `"online":true`（SnowLuma OneBot 上线）。
面板卡住说明 hook 疑似未接管（登录成功但事件未达 SnowLuma）。已加诊断：启动约
1 分钟后仍未上线时，打印一次 `[control] OneBot get_status: <原始返回>`，区分
"hook 没接管"与"HTTP 服务没起"。

**遗留 2（UX）**：浮层新增手动收起——点遮罩收起（进程继续跑），右下角出现
"查看扫码窗口"悬浮按钮可恢复；"取消登录"仍为停止进程。进程停止时两个标记复位。

**新 APK**：`dist/mofox-debug-arm64-v8a-20260927-170404.apk`。测试 122 全过。

### 10.6 第六轮（2026-09-27 18:21）：快捷登录支持 + 面板手动关闭

真机确认 QQ 记住账号时启动显示的是**快捷登录窗口（无二维码）**，且浮层无法手动关闭。

- 浮层新增「点击登录」按钮：Dart → 新增 `qqQuickLogin` 安装任务 → rootfs 内
  `xdotool windowactivate + key Return` 触发 QQ 快捷登录窗口的默认登录按钮
  （Chromium 忽略 XSendEvent 按键，必须用 windowactivate + XTEST 全局注入）。
  xdotool 加入 installRuntimeDeps 与 snowluma-install.sh 依赖，quickLogin 任务内
  还会自愈安装（存量设备 rootfs 里没有它）。浮层提示文案同步改写。
- 面板标题行新增 ✕ 收起按钮（与点遮罩等价，进程不停），收起后右下角
  "查看扫码窗口"悬浮按钮恢复。
- 登录成功自动关闭依赖 get_status 上报 online；若 hook 未接管则不会自动关，
  用收起按钮隐藏 + 看 `[control] OneBot get_status:` 诊断行定位。

**新 APK**：`dist/mofox-debug-arm64-v8a-20260927-182113.apk`。测试 122 全过。

### 10.7 第七轮（2026-09-27 19:07）：补上 SERVICE_MODE，hook 静默不工作的真因

真机 WebUI 显示"已向进程 2796 注入 SnowLuma，等待管道连接"+ 注入失败——
QQ 已登录但管道从未出现。反汇编 stub 线程（fn@0xf5f0）发现：STUB_START 只启动
stub 线程，线程内还要检查 **`SNOWLUMA_HOOK_SERVICE_MODE=in-process`** 才调用
服务启动器（0xeea0）创建 mojo.<pid>.control.sock。缺这个变量组件静默不工作。

修复：QQ_HOOK_ENV 增加 `SNOWLUMA_HOOK_SERVICE_MODE=in-process`。
**新 APK**：`dist/mofox-debug-arm64-v8a-20260927-190754.apk`。

验证要点：重启 snowluma 后，WebUI"进程注入"页应从"错误/等待管道连接"变为
已连接；MoFox 面板应在登录后自动收起（get_status online）。若仍失败，下一步
排查 stub 线程内 socket 创建失败的原因（runtime dir 权限 / 环境变量未达 QQ）。

### 10.8 第八轮（2026-09-28）：hook 管道创建失败的最终根因与修复

真机诊断（组件已映射进 QQ 100 页、环境变量在、runtime dir 恒为空、无任何报错）
结合对 `snowluma-linux-arm64.so` 的完整逆向（服务启动链：ctor 检查 STUB_START →
信号线程检查 SERVICE_MODE → mkdir → socket → **bind** → listen，mkdir/bind 失败
均为静默返回，该 .so 未导入任何输出函数）锁定根因：

**AF_UNIX `sun_path` 108 字节上限。** rootfs 内 `/tmp/snowluma-hook/mojo.<pid>.control.sock`
经 proot 翻译成宿主真实路径后约 125 字节，`bind()` 必然失败且无任何提示。此结论
同时解释：官方文档称 proot 下"能否运行取决于设备"的底层原因之一即路径翻译长度。

**修复**：proot 启动参数里已有恒等挂载 `-b $TMPDIR:$TMPDIR`（host files/tmp 在
guest 内同路径可见）。hook runtime dir 迁移到 `<files>/tmp/snowluma-hook`
（guest/host 同路径，socket 全长 ~76 字节 < 108），QQ 与 SnowLuma 双端一致；
SnowLuma 通过读取 QQ `/proc/<pid>/environ` 的 `SNOWLUMA_HOOK_RUNTIME_DIR` 解析
到同一目录。诊断的 environ grep 加 `-a` 修正二进制匹配吞结果的问题。

**参考**：官方文档站 SnowLumaDocs（deploy/mobile.mdx 承认 proot 下 ptrace 受限；
deploy/linux-manual.mdx 确认官方唯一注入方式是 ptrace + setcap cap_sys_ptrace）；
PC 端（D:\STELA，v1.14.15 Windows）走 CreateRemoteThread DLL 注入，无本问题。
LD_PRELOAD/stub 模式为逆向发现的内部接口，无公开文档；如仍有异常，联系作者
（QQ 群 qm.qq.com/q/g3UMLpWALe / motricseven@foxmail.com）确认 stub 语义。

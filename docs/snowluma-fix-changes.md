# SnowLuma 分支完整变更记录（相对 main 仓库，事无巨细版）

> 覆盖 `snowluma-migration` / `fix/proot-snowluma-engine` 分支相对 `main`
> 的全部改动（56 个跟踪文件、+2320/-1258 的迁移工程，加 1 个 proot 引擎
> 修复提交）。本文分四部分：
>
> 1. 为什么引入 SnowLuma（动机、选型、与运行环境的根本矛盾）
> 2. 为引入 SnowLuma 做的调整（迁移工程的每一处改动）
> 3. 为引入 SnowLuma 写的插件 `snowluma_trampoline`（原因、效果、目的）
> 4. 其他所有更改（自愈、诊断、文档、测试）
>
> 深度技术分析（含反汇编与实验数据）：
> [snowluma-proot-engine-fix.md](snowluma-proot-engine-fix.md)；
> 插件使用与排障：[snowluma-trampoline-plugin.md](snowluma-trampoline-plugin.md)。

---

## 1. 为什么引入 SnowLuma

### 1.1 前置状态

`main` 分支的 QQ 接入方案是 **NapCat**（`napcat-install.sh`，519 行）：
通过修改 QQNT 启动脚本，把 NapCat 的 JavaScript 代码加载进 QQ 的
Electron 主进程，再由 JS 层调用 QQ 内部接口实现 OneBot v11。

### 1.2 NapCat 的致命问题：风控

真机长期使用证实：**NapCat 的接入方式会被腾讯风控识别**，后果是账号被
冻结或强制断线。这是产品级的硬伤——bot 依赖的 QQ 号是用户的核心资产。
风控识别的根源在于 NapCat 的工作层级：它在 QQ 的 JS 运行时里直接调用
内部接口，其行为模式（接口调用序列、心跳特征、缺失的客户端行为）与真实
客户端存在可检测的差异。

### 1.3 候选方案对比

| 方案 | 接入层级 | 风控风险 | proot/无 root 可行性 | 结论 |
| --- | --- | --- | --- | --- |
| 继续 NapCat | Electron JS 层 | **高（已实测冻结）** | 可行 | 排除 |
| Lagrange 等独立协议端 | 自研协议直连腾讯服务器 | 高（非官方客户端特征） | 可行但需 .NET 运行时 | 排除 |
| **SnowLuma（hook 模式）** | **QQ 原生 C++ 协议栈内** | **最低（流量即 QQ 自己的流量）** | 需大量适配（本文档主体） | **采用** |

SnowLuma 的 hook 模式让所有协议收发仍由 QQ 自己的代码完成，hook 组件只
在进程内旁观并解析——对腾讯而言这就是一个正常客户端。这是唯一同时满足
"风控安全"与"能在 proot 里跑"的路线。

### 1.4 SnowLuma 是什么

- 定位：把 QQ 原生会话转换为 OneBot v11 动作与事件的运行时（TypeScript，
  自带 Node.js 运行时），提供 WebSocket/HTTP/WebUI/SDK/MCP 入口；
- 组成：Node 主程序（`index.mjs`）+ 原生 hook 组件
  （`snowluma-linux-arm64.so`，注入 QQ 进程解析 NTQQ 协议包）+
  WebUI 前端 + 各平台注入器 addon（`snowluma-linux-arm64.node`，ptrace
  手动映射注入）；
- 官方运行形态：桌面 Linux/Docker，QQ 由容器直接启动，SnowLuma 以
  **ptrace 注入**（需要 `CAP_SYS_PTRACE`）方式挂进 QQ；
- 版本：v1.14.20（2026-09-26 发布，与 QQ Linux 3.2.32 为官方 pin 配对）。

### 1.5 根本矛盾：官方形态 vs MoFox 目标形态

| 维度 | 官方形态 | MoFox 形态（Android App 内嵌） |
| --- | --- | --- |
| 容器 | Docker / 桌面 | **proot**（无 root，App 数据目录内） |
| ptrace | 可用（容器授予 CAP_SYS_PTRACE） | **不可用**（QQ 已被 proot 占为 tracee） |
| 文件路径 | 真实路径，`/proc/self/maps` 与磁盘一致 | **maps 显示宿主形态路径，guest 内打不开** |
| 启动方式 | supervisord 直启 QQ | App 进程脚本经 proot 启动整套 X 环境 |

这些差异是后续所有适配与插件工作的根源（第 2、3 章）。

---

## 2. 为引入 SnowLuma 做的调整（迁移工程，提交 3a167a8..37525e0）

### 2.1 Kotlin 运行时层

#### `RuntimeScripts.kt`（+516/-，改动最大的文件）

**snowluma 进程脚本**（`"snowluma" ->` 分支）从零编写，职责链：

1. **安装编排**：首次启动自动执行 `snowluma-install.sh`（见 2.2），安装
   LinuxQQ + Node + SnowLuma 到 rootfs 的 `/root/snowluma/`，写入版本
   标记 `.qq_source_version` 防止版本循环误判重装；
2. **运行时清理**：清旧截图（避免监控线程读到上次登录的过期二维码）、
   Xvfb 残锁 `/tmp/.X1-lock`（SIGKILL 残留会让 Xvfb 秒退）、残留 node
   进程（占住 5099 端口）；
3. **虚拟桌面**：Xvfb `:1`（800x600x24）+ fluxbox 无头桌面，QQ 窗口
   渲染在其中；
4. **QQ 启动**：`DISPLAY=:1 env $QQ_HOOK_ENV qq --no-sandbox ... -q <botQq>`。
   两个关键点：hook 环境变量必须经 `env` 传递（直接 `VAR=v cmd` 形式
   bash 会把第一个 VAR=v 当命令名，QQ 根本不启动）；`-q` 预填快捷登录；
5. **hook 环境**（LD_PRELOAD 模式，原因见 3.1 层 4）：
   - `SNOWLUMA_HOOK_STUB_START=1`：hook 组件构造函数据此启动 stub 线程；
   - `SNOWLUMA_HOOK_SERVICE_MODE=in-process`：stub 线程据此创建
     `mojo.<pid>.control.sock` 服务（缺一则组件静默不工作，反汇编确认）；
   - `SNOWLUMA_HOOK_RUNTIME_DIR=<files>/tmp/snowluma-hook`：hook 管道
     目录。**必须用恒等挂载的短路径**：AF_UNIX `sun_path` 上限 108 字节，
     rootfs 内 `/tmp` 经 proot 翻译约 125 字节，`bind()` 静默失败；
   - `LD_PRELOAD=<hook.so>`。
6. **后台监控循环**（225 轮 × 4s）：
   - x11grab 截屏 → md5 变化才推 `MOFOX_QR_IMAGE=`（App 展示扫码面板）；
   - `curl get_status` 命中 `"online":true` → `MOFOX_LOGIN_OK=1`（App
     自动收起扫码面板的信号）；
   - WebUI 就绪 → `MOFOX_WEBUI_URL=`；
   - QQ 存活/死亡各报一次；启动 1 分钟未上线打印 `get_status` 原始返回
     （区分"钩子没接管"与"HTTP 服务没起"）；第 5 轮打印 hook 预加载
     链路诊断（QQ 进程 environ、`.so` 映射页数、runtime dir 内容）；
7. **快捷登录**：QQ 记住账号时显示的是快捷登录窗（无二维码），App 侧
   `qqQuickLogin` 任务通过 `xdotool windowactivate + key Return`
   （XTEST 全局注入，Chromium 忽略 XSendEvent）触发默认登录按钮。

**bot 进程脚本**（`"bot" ->` 分支）：

- 启动前自愈：把 plugin-cache 里的适配器插件铺进实例 `plugins/`、写
  `snowluma_adapter/config.toml`（reverse WS 8095）、停用
  `onebot_adapter`（避免争抢 8095）；
- **核心自愈**：`git fetch origin dev --depth=1` + `git checkout -f -B dev
  FETCH_HEAD`——SnowLuma 插件需要 dev 分支的新插件 API（media_api 1.2.0 /
  event_api 1.1.0 / PlatformSendResult），main 分支核心会被插件加载器
  拒载；config/plugins/data 均为未跟踪文件，force checkout 不碰用户数据；
- `uv run python main.py` 启动。

#### `RootfsInstaller.kt`

- `stageSnowlumaInstaller()`：把 APK 内 `assets/scripts/snowluma-install.sh`
  投递到 rootfs（**每次无条件覆盖**——旧实例跨 APK 升级时若按"存在即
  跳过"会执行旧版缺陷脚本）；拷贝时统一 CRLF→LF 并去 BOM（`set -e`
  脚本对 BOM 敏感）；
- `stageSnowlumaPlugins()`：把 `assets/plugins/snowluma_*.mfp` 铺到
  rootfs `/root/.mofox/plugin-cache/`，bot 进程脚本启动时从这里复制进
  实例 `plugins/`——升级 APK 即升级插件，旧实例无需重装。

#### `RuntimeProcessManager.kt` / `RuntimeBridgePlugin.kt`

进程生命周期管理与 MethodChannel 任务路由适配（installSnowluma /
verifySnowluma / writeSnowlumaConfig / writeModel / qqQuickLogin 等任务）。

### 2.2 安装脚本 `snowluma-install.sh`（新增 700 行）

- 多来源下载：官方 CDN（`qqdl.gtimg.cn` 全线 403）→ GitHub 镜像
  `Rodert/qq-versions`（从镜像 `linuxConfig.js` 解析 deb 直链）→ 官方
  直连兜底；
- 校验链：deb 魔数 + 包大小 + 解压后验证 `/root/snowluma/opt/QQ/qq`
  存在且可执行，任一环节失败自动换下一个来源，失败原因直接打印；
- 同时安装 Node.js（含版本检查脚本）与 SnowLuma runtime（v1.14.20）；
- QQ 热更新冻结：`/etc/hosts` 加 `0.0.0.0 qqpatch.gtimg.cn`，防止 QQ
  自更新打乱与 hook 组件的版本配对。

### 2.3 插件资产（app/assets/plugins/）

- `snowluma_adapter-2.2.10.mfp`：OneBot v11 适配器（mofox-wire 架构），
  reverse 模式在 8095 起 WS 服务端等待 SnowLuma 连入；处理消息/通知/
  请求/元事件四类上行，发送侧调 `send_group_msg`/`send_private_msg` 等
  API；带黑白名单、戳一戳防抖、视频处理等 features；
- `snowluma_extension-1.0.11.mfp`：禁言/解禁/全员禁言/表情回应/戳一戳/
  撤回/精华/群签到/群公告/入群审批等扩展能力，通过框架 adapter_api
  调用当前活跃的 QQ 适配器（存在多个时优先 `onebot_adapter`）。

### 2.4 Dart 层（约 17 个文件）

- **全量重命名**：napcat → snowluma（任务名、状态机、QR sheet、日志）；
- **扫码浮层重构**：从模态 bottomSheet 改为页面内 Stack 条件渲染——
  修复 go_router 嵌套导航器重建导致的"弹窗反复出现"与
  `_qrPayload!` 空断言红屏；新增点遮罩收起、"查看扫码窗口"悬浮恢复、
  ✕ 收起按钮；
- **快捷登录按钮**：触发 `qqQuickLogin` 任务；
- **进程控制台**：消费进程脚本事件流（进度、控制标记、二维码图片路径），
  展示彩色安装日志；
- OOBE/向导/备份/设置随任务名与流程同步调整。

### 2.5 测试

122 个测试全部通过；新增/改动 11 个测试文件（事件流解析、QR 浮层、
OOBE 流程、向导校验、备份唤醒锁等）。

### 2.6 文档

`docs/agent-handoff-snowluma-migration.md`（331 行迁移交接报告，含迁移
原因、10 轮真机排错记录、已知风险）；`docs/android-deployment-guide.md`、
`docs/terminal-ai-assistant-plan.md`、`docs/file-manager-toml-editor-architecture.md`、
README/ARCHITECTURE 同步更新。

---

## 3. 为引入 SnowLuma 写的插件：`snowluma_trampoline`

### 3.1 原因：真机四层根因（每层：现象 → 调查 → 决定性实验 → 结论）

迁移后真机上出现最终症状：**OneBot 永不上线**——QQ 正常登录（虚拟桌面
可见主界面）、hook 注入成功（`mojo.<pid>.control.sock` 存在、日志
`pipe connected`），但 3000 端口不监听、8095 不连接、App 的登录探测恒
失败。逐层定位：

#### 层 1：bot 核心过旧（适配器从未注册）

- **现象**：SnowLuma 侧 `ECONNREFUSED 127.0.0.1:8095`，bot 日志
  `没有注册任何适配器`。
- **调查**：适配器插件被加载器以 `API 'media_api' 核心版本 1.0.0 低于
  插件要求 1.2.0` 拒载；核心仓库 main 分支 `media_api.API_VERSION =
  "1.0.0"`，而 dev 分支是 `"1.2.0"`。
- **修复**：bot 启动前 dev 分支自愈（fetch 成功后 checkout 曾未生效，
  手动 `git checkout -f -B dev FETCH_HEAD` 完成一次，此后自愈正常）。
- **佐证**：适配器插件实际调用的 `get_media_info`/`recognize_media` 在
  核心 1.0.0 中已存在；仅语音增强可选路径用到 1.2.0 的
  `save_description_cache`（有 try/except 保护）。

#### 层 2：引擎休眠（LD_PRELOAD/stub 模式缺最后一步）

- **现象**：`/api/processes` 显示 `injected:true, connected:true,
  loggedIn:false, uin:"0"`，QQ 登录前后均无任何事件推送。
- **调查**：
  - 反汇编导出 `snowluma_linux_hook_start_dynamic`（0x10a40，52 字节）：
    `getpid()` 后调 `0xeea0(pid, 1)`（服务启动器，与 stub 线程调用的是
    **同一个函数**），随后返回 loaded 标志——官方注入器在 ptrace 映射后
    就是调它启动引擎；
  - stub 线程在 **pre-main**（进程极早期）已调用过启动器——此时 QQ 模块
    尚未加载，引擎目标解析落在错误时机，之后不再重解析；
  - 官方注入 addon（`.node`）内含 `start_dynamic` 引用——官方流程的引擎
    启动由注入器完成，stub 模式天然缺失。
- **结论**：引擎从未真正启动，一切观测自然为零。

#### 层 3：解析失明（maps 宿主路径在 guest 内 ENOENT）

- **现象**：让引擎"重新启动"后（跳板 stop+start），QQ 登录全过程依然
  零事件；请求恒报 `-39 "The QQ connection changed. Please restart QQ
  and try again."`。
- **调查**：
  - QQ 的 `/proc/self/maps` 显示模块路径为**宿主形态**
    （`/data/data/com.mofox.android/files/...`，proot 不翻译 maps 内容）；
  - guest 内 `open` 该路径 → ENOENT（会被翻译到 rootfs 之下）；同一文件
    的 guest 路径 `/root/snowluma/...` 存在；
  - 解析的**识别条件**是满足的（maps 含 `wrapper.node`、96 行命中
    `/opt/QQ/` 子串）——失败的仅是后续**文件打开**步骤；
  - 反汇编 -39 发射点（状态字 switch：==2 → -39 连接已变化，==0/1 → -38
    请求无效，==3 → -38 prepare 失败）：状态字来自请求准备阶段对连接
    追踪上下文的校验，而连接追踪依赖钩子观测 MSF 连接——钩子未安装则
    状态恒为"无连接"。
- **结论**：引擎钩子的安装依赖按 maps 路径打开模块文件；宿主路径在
  guest 不可达 → 解析失败 → 钩子永不安装。

#### 层 4：投递通道与注入路线的排除（两次重要证伪）

- **`/etc/ld.so.preload` 证伪**：用它投递跳板会让 QQ 在启动 ~100ms 内
  GPU 子进程三次启动失败后 FATAL（`error_code=1002`）——ld.so.preload
  不受 Chromium 沙箱的 env 剥离影响，进入沙箱子进程导致启动失败；
  env 型 LD_PRELOAD（QQ 主进程链）则与 snowluma 组件既有行为一致，安全。
  跳板构造函数随之改为纯 syscall 实现（stdio/malloc 会与 Chromium 早期
  fork zygote 竞争堆锁）。
- **官方 ptrace 注入证伪**：`SNOWLUMA_HOOK_AUTOLOAD=1` + 原生 QQ（剥离
  全部 preload/STUB/SERVICE 环境变量，仅保留 RUNTIME_DIR）实测官方注入器
  `load failed: COMPONENT_LOAD_FAILED`；QQ `TracerPid` = proot，guest 内
  fork 子进程对 QQ `PTRACE_ATTACH` → `ESRCH`。proot 恒占 tracee，第二
  tracer 无法注入——**LD_PRELOAD 是 proot 下唯一可行的加载通道**。
  （排查中"fork 子进程 attach 父进程返回 0"为父子关系特例，不可外推。）
- **能力矩阵**（同环境实测，证明"设备限制论"不成立）：匿名 RWX、memfd
  RWX、文件执行页 RX→RW→RX（execmod）、只读页→RW（VTable）、
  `/proc/self/mem` 直写、inotify——**全部可用**。即缺的不是权限，而是
  上述两层的"启动"与"路径"。

### 3.2 插件的效果：自动部署的三件东西（全部幂等 + 指纹校验）

1. **影子路径**（两个符号链接，解决层 3）：
   ```text
   <rootfs>/data/data/com.mofox.android/files/usr/var/lib/proot-distro/
            installed-rootfs/ubuntu/root -> /root
   <rootfs>/data/data/com.mofox.android/files/usr/var/lib/proot-distro/
            installed-rootfs/ubuntu/usr  ->  /usr
   ```
   引擎按 maps 里的宿主形态路径 open 时，proot 把它翻译到 rootfs 之下，
   经符号链接跳回 guest 真实文件——open 成功，目标解析与钩子安装恢复。

2. **跳板 .so**（解决层 2）：arm64 预编译（源码
   `assets/scripts/snowluma-trampoline.c`），经 QQ 的 LD_PRELOAD 链加载。
   设计要点：
   - 构造函数**纯 syscall**（raw open/read/close/nanomsleep + memmem 栈上
     扫描），不碰 stdio/malloc——v1 版本在构造函数线程里做 stdio/malloc，
     与 Chromium 早期 fork zygote 竞争堆锁，导致 GPU 子进程
     `error_code=1002` 三连失败 → `GPU process isn't usable` FATAL（已修）；
   - 构造函数裸读 `/proc/self/cmdline`，含 `--type=` 的 Electron 子进程
     直接不创建线程；
   - 线程先纯 nanosleep 3s（零用户态锁活动），再等 maps 出现
     `snowluma-linux-arm64.so`（非 QQ 环境自动退出）、等 `wrapper.node`
     （Electron 就绪），追加 5s 后执行 `stop_dynamic → start_dynamic`
     ——stop 是必须的：stub 已把 loaded 标志置位，直接 start 会被判
     "已启动"跳过，只有先停再启才能让目标解析落在 QQ 完全就绪的正确
     时刻；
   - 全程写日志 `/tmp/snowluma-trampoline.log`（raw write，任何阶段可查）。

3. **env 包装器**（投递通道，插件时代方案，已由原生 LD_PRELOAD 取代）：
   `/usr/local/bin/env` 透明包装器——进程脚本里 QQ 启动是唯一"裸 env +
   QQ 路径参数"的调用（其余 env 均为绝对路径或无 QQ 参数），包装器拦截
   该次调用、把跳板追加进 `LD_PRELOAD=` 参数、exec 真正的 `/usr/bin/env`。
   依赖 guest PATH 中 `/usr/local/bin` 先于 `/usr/bin`；带插件签名，遇
   外来文件拒绝覆盖；**不触碰 `/etc/ld.so.preload`**（层 4 的教训）。
   整合后跳板由进程脚本直接并入 QQ 的 `LD_PRELOAD` 链，包装器仅在
   插件时代的存量实例中存在，snowluma 脚本启动时会移除带本项目签名的
   遗留包装器。

### 3.3 插件的目的（及其最终归宿）

1. **立即可用**：在不更新 App 的存量实例上补齐全链路（Bot 加载插件时
   自动部署，下次 SnowLuma 重启生效）；
2. **独立分发**：.mfp 可脱离 App 版本单独升级（plugin-cache → plugins/
   的既有通道）；
3. **诊断工具**：`trampoline_status` 一次输出部署状态/影子路径可达性/
   hook 管道 socket/跳板日志尾部，可明确区分"引擎没启动"与"引擎启动了
   但路径解析失败"两类故障；
4. **面向未来**：若 SnowLuma 上游在 stub 模式内自行补齐引擎启动或修正
   proot 路径解析，插件保持幂等无冲突。

> **最终归宿：已原生整合进 App 本体。** 插件验证路线可行后，其全部
> 功能（影子路径创建、跳板铺发、LD_PRELOAD 注入）由 snowluma 进程脚本
> 直接执行（见 3.2 各节引注），bot 启动自愈会清理遗留的插件分发包，
> 插件时代的 env 包装器也由脚本移除（跳板已原生并入 LD_PRELOAD，无需
> 再经包装器间接投递）。本节保留作设计记录；历史说明见
> [snowluma-trampoline-plugin.md](snowluma-trampoline-plugin.md)。

### 3.4 插件结构（历史形态，v1.1.0）

```text
snowluma_trampoline-1.1.0.mfp
├── manifest.json            # 组件清单（config + 3 actions）
├── plugin.py                # 入口：注册 + 加载时自动部署（零抛出保护）
├── config.py                # BaseConfig 三段：plugin/deploy/paths
├── snowluma-trampoline.so   # 内置 arm64 预编译跳板
└── src/
    ├── deployer.py          # 部署/移除/状态（指纹校验、幂等）
    └── actions.py           # trampoline_status / deploy / remove
```

配置（`config/plugins/snowluma_trampoline/config.toml`）：`plugin.enabled`
（总开关）、`deploy.auto_deploy`（加载时自动部署）、`deploy.remove_on_disable`、
`paths.*`（四条路径，默认与 MoFox 运行时布局一致）。

---

## 4. 其他所有更改

### 4.1 bot 进程脚本 heredoc 缩进修复

`val cmd = """` 直接以内容开头时，`trimIndent()` 剥离缩进后 heredoc 结束
符 `MOFOX_EOF` 带缩进不被 shell 识别，启动命令被吞——首行改为空行让
trimIndent 正确工作（此修复使适配器自愈段真正生效）。

### 4.2 bot 核心自动跟随 dev 分支

见 3.1 层 1。注意 `config/`、`plugins/`、`data/` 均为未跟踪文件，
force checkout 不影响用户数据与配置。

### 4.3 构建标识

snowluma 进程脚本首行打印构建标识（`20260928-2` → `20261002-1 影子路径+
引擎启动跳板`），用于确认设备实际运行的脚本版本。

### 4.4 插件与跳板铺发

`stageSnowlumaPlugins` 的清单加入 `snowluma_trampoline-1.1.0.mfp`，并
新增跳板 .so 到 rootfs `/usr/local/lib/` 的铺发（资产缺失时静默跳过，
兼容未打包的构建）。

### 4.5 文档

- `docs/snowluma-fix-changes.md`：本文档（相对 main 的全量更改说明）；
- `docs/snowluma-proot-engine-fix.md`：根因分析（反汇编、能力矩阵、
  决定性实验、回滚）；
- `docs/snowluma-trampoline-plugin.md`：插件使用与排障；
- `docs/agent-handoff-snowluma-migration.md`：迁移期 10 轮排错的历史记录。

### 4.6 版本兼容语义（记录一次排查结论）

插件加载器的检查是 AND 语义：`api_version`（按 20 个 `*_api` 模块逐一
比对，主版本必须相等、次版本不低于要求）与 `min_core_version`（CORE_VERSION
的 `>=` 比较）任一不满足即拒载。SnowLuma 适配器要求 `media_api 1.2.0`，
因此 bot 核心必须处于 dev 分支（或 ≥1.2.0 的发布版）。

### 4.7 两个适配器的互斥关系

`snowluma_adapter`（reverse WS 8095，由 App 每次启动写配置并启用）与
`onebot_adapter`（NapCat 时代遗留，App 每次启动显式停用）不能同时监听
8095。`snowluma_extension` 通过 adapter_api 调用"当前活跃的 QQ 适配器"，
对选择无感知。

### 4.8 真机排错期间发现的环境注意事项（不属于仓库变更）

- 实例创建向导若未填写真实 LLM API Key，`model.toml` 会携带占位符
  （`your-siliconflow-api-key-here`），bot 收到消息后回复阶段将 401；
  建议后续版本在启动自检中提示（本分支未包含此改动）。

---

### 4.9 安装脚本输出治理与下载重试（用户反馈：installSnowluma exited with 1）

一位用户 OOBE 第 3 步 `installSnowluma exited with 1`，日志尾部全是被打散的
`# -=0=-` 进度条残骸——`curl -#` 进度条用 `
` 刷新，App 控制台按行渲染后
把真正的报错冲出可视区。修复：

- 三处大下载（Node.js ×2、SnowLuma tarball、QQ deb）的 `curl -#` 全部改为
  `-sS --retry 2 --retry-delay 2`（静默 + 瞬时失败自动重试），控制台尾部
  从此可见真实报错；
- SnowLuma tarball 增加"代理失败后直连 GitHub"兜底；
- 下载来源不变：Node 走 npmmirror + nodejs.org 双源，QQ deb 多候选镜像
  循环 + 魔数/大小校验，SnowLuma 经测速代理选择。

### 4.10 bot 侧适配器切换：snowluma_adapter → onebot_adapter

应用户要求，bot 侧 QQ 适配器从随 APK 分发的 `snowluma_adapter`/
`snowluma_extension`（.mfp 插件）切回 **bot 仓库自带的 `onebot_adapter`**
（标准 OneBot v11，main 核心即可加载，无 media_api 1.2.0 依赖）。
**SnowLuma 协议端链路完全不变**（安装编排、引擎跳板、影子路径、
onebot.json 的 wsClients → 8095、登录检测照旧）——只换 bot 侧"谁监听
8095、谁解析消息"。

- bot 自愈段反转：写 `config/plugins/onebot_adapter/config.toml`
  （reverse ws，等 SnowLuma 连入）；停用遗留的 snowluma_adapter 配置
  （仅当存在）；清理实例 `plugins/` 里历史分发的
  `snowluma_adapter-*.mfp` / `snowluma_extension-*.mfp`；
- **dev 分支强推自愈移除**（每次启动联网 fetch+checkout dev 的行为取消）：
  实测发现插件市场生态的插件普遍依赖 dev 分支核心的新 API（如
  create_llm_request 的 stream_id 参数），dev→main 迁移会破坏已装插件，
  故自愈不管理仓库分支——实例停留在哪个分支由其已装插件决定；
- 资产分发：`stageSnowlumaPlugins` 更名 `stageBundledPlugins`，清单清空
  （机制保留给未来插件），删除 `assets/plugins/snowluma_*.mfp`；
- `writeAdapter` 任务（向导安装步骤）改为写 onebot 配置；任务名不变
  （旧向导断点的枚举反序列化兼容）；
- 代价说明：snowluma_extension 提供的群管/表情回应等扩展动作随切换
  不再安装（其能力本就经 adapter_api 优先调用 onebot_adapter 也能覆盖
  大部分场景，如需可后续单独装回）。

## 5. 验证记录（真机 Android 16 / HyperOS，无 root）

```text
[23:50:07] snowluma_adapter | Bot 3840642751 连接成功
[23:50:07] [3840642751] [OneBot.WS-Client] connected ws://127.0.0.1:8095
get_status      → {"status":"ok","retcode":0,"data":{"online":true,"good":true}}
get_login_info  → {"user_id":3840642751,"nickname":"猫的催化效应"}
get_friend_list → 9 好友（协议栈完全激活）
send_private_msg → {"status":"ok","data":{"message_id":...}}
```

App 侧登录检测（轮询 `get_status` 命中 `online:true` → `MOFOX_LOGIN_OK`）
随之闭环；两次完整重启后各层自愈（dev 核心、插件铺发、影子路径、跳板）
均自动恢复，无需人工干预。

## 6. 回滚

- 引擎修复：删除 snowluma 脚本中的影子路径段与跳板 LD_PRELOAD 追加，
  或 bot 插件形态执行 `trampoline_remove`；
- 协议端整体：revert 本分支回到 NapCat（`napcat-install.sh` 在历史中）；
- 核心分支：bot 仓库 `git checkout main`（适配器将再次被拒载，属预期）。

## 7. 提交结构

```text
3a167a8  SnowLuma 迁移：QQ 协议端由 NapCat 替换为 SnowLuma（LD_PRELOAD 预加载接入）
a36bf16  fix: stageSnowlumaInstaller 拷贝时统一 CRLF→LF 并去 BOM
b719e53  diag: hook 预加载链路自动诊断（env 映射/组件映射/管道文件）
1bde654  fix: 启动前清理 Xvfb 残锁与残留 node，Xvfb/fluxbox 报错落盘
2f352db  fix: hook 管道 runtime dir 移到恒等挂载短路径，规避 AF_UNIX 108 字节限制
4b15822  docs: 交接报告补记 hook 管道 AF_UNIX 108 字节根因与逆向结论
066a247  diag: snowluma 进程脚本首行打印构建标识，便于确认设备实际运行的版本
37525e0  feat: 实例启动自动安装 SnowLuma 适配器插件（snowluma_adapter + snowluma_extension）
<本次>   fix(snowluma): proot 下引擎休眠与目标解析失明修复（影子路径 + 引擎启动跳板）
```

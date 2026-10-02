# proot 下 SnowLuma 引擎不可用的根因分析与修复（无 root）

> 2026-10-01/02 真机排查（Redmi K100 Pro Max，Android 16 / HyperOS，arm64）。
> 结论：四层叠加故障，全部可在**无 root** 前提下修复。本文记录完整因果链、
> 决定性实验与修复方案。修复代码：`RuntimeScripts.kt`（影子路径 + 跳板注入）、
> `RootfsInstaller.kt`（跳板与插件铺发）、`assets/scripts/snowluma-trampoline.c/.so`、
> `assets/plugins/snowluma_trampoline-1.1.0.mfp`。

## 症状

- QQ 在 proot 内正常启动并登录（虚拟桌面可见主界面）；
- hook 组件注入成功（`mojo.<pid>.control.sock` 存在、SnowLuma 日志 `pipe connected`）；
- 但 OneBot 永不上线：3000 端口不监听、8095 WS 客户端不启动、
  App 的 `get_status` 轮询恒失败（"检测不到 QQ 已在 Linux 登录"）。

## 因果链（四层）

### 1. 引擎休眠：stub 模式从未调用引擎启动导出

官方注入器（ptrace `loadModuleManual`）映射 `.so` 后会调用
`snowluma_linux_hook_start_dynamic` 启动拦截引擎（addon 内含该导出引用，
反汇编确认 `start_dynamic` 调用服务启动器 `0xeea0(pid, 1)` 后返回 loaded 标志）。
LD_PRELOAD/stub 模式只走 ctor → stub 线程 → 服务启动器创建 socket 服务，
**从未调用 start_dynamic** → 引擎静默休眠。

### 2. 解析失明：/proc/self/maps 的宿主路径在 guest 内不可打开

QQ 的 `/proc/self/maps` 中模块路径为宿主真实形态
（`/data/data/com.mofox.android/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/snowluma/...`）。
SnowLuma 引擎的目标解析要在进程内打开这些路径；guest 内该绝对路径
（proot 翻译为 rootfs 下 `data/data/...`）默认 **ENOENT** → 目标解析失败 →
钩子永不安装 → 连接追踪缺失 → 一切请求报
`-39 "The QQ connection changed. Please restart QQ and try again."`
（错误分支：状态字 ==2 → -39；==0/1 → -38 请求无效；==3 → -38 prepare 失败，
见 `.so` 内 `0x1384c-0x13b10` 的 switch）。

注意：`wrapper.node` 在 maps 中存在（含 `/opt/QQ/` 子串，96 行命中），
即解析的**识别条件满足**，失败的仅是**文件打开**步骤。

### 3. 官方 ptrace 注入在 proot 下确认不可用（曾两度误判）

- QQ 的 `TracerPid` = proot 进程（proot 恒占 tracee）；
- guest 内 fork 子进程对 QQ 执行 `PTRACE_ATTACH` → `ESRCH`；
- 实测 SnowLuma 官方自动注入（`SNOWLUMA_HOOK_AUTOLOAD=1`、原生 QQ、
  仅保留 `SNOWLUMA_HOOK_RUNTIME_DIR`）：
  `load failed: ... COMPONENT_LOAD_FAILED`。
- **不可**用 `/etc/ld.so.preload` 投递：Chromium 沙箱子进程（GPU 进程）
  会因此启动失败（`error_code=1002` → `GPU process isn't usable. Goodbye.`），
  必须走 QQ 的 `LD_PRELOAD` env 链（沙箱会剥 env，但主进程/zygote 正常，
  与 snowluma 组件既有行为一致）。

> 排查中曾有"自 ptrace 可行"的误报（fork 子进程 attach 父进程返回 0）——
> 父子关系下的该现象不可外推到任意进程，对 QQ 的 attach 实测 ESRCH。

### 4. 能力矩阵（无 root 的前提全部成立）

| 能力 | 结果 |
| --- | --- |
| 匿名 mmap RWX / memfd RWX | ✅ |
| 文件执行页 mprotect RX→RW→RX（execmod，内联钩子必需） | ✅ |
| 只读文件页 → RW（VTable/GOT 钩子必需） | ✅ |
| `/proc/self/mem` 直写执行页 | ✅ |
| inotify | ✅ |

（`process_vm_writev` 写执行页返回 EFAULT，`/proc/self/mem` 可替代。）

即：**没有任何一层是"设备级限制"**，全部可在应用沙箱内修复。

## 修复（全部无 root）

1. **影子路径**：在 rootfs 内建立符号链接，把宿主形态路径映射到 guest 真实
   位置（`.../ubuntu/root → /root`、`.../usr → /usr`）。snowluma 进程脚本
   每次启动时创建（幂等）。
2. **引擎启动跳板** `snowluma-trampoline.so`（源码
   `assets/scripts/snowluma-trampoline.c`）：经 QQ 的 LD_PRELOAD 链加载，
   构造函数纯 syscall 实现（早期版本在构造函数里做 stdio/malloc 会与
   Chromium 早期 fork zygote 竞争锁，导致 GPU 子进程 1002 崩溃——已修）；
   等待 `wrapper.node` 出现于 maps 后执行 `stop_dynamic → start_dynamic`，
   强制引擎在 QQ 完全就绪后完整启动。预编译产物随 APK 铺入 rootfs
   `/usr/local/lib/snowluma-trampoline.so`。重编（与 QQ 同为 guest 内
   glibc arm64，建议在 rootfs 内编译）：
   `gcc -shared -fPIC -O2 -o snowluma-trampoline.so snowluma-trampoline.c`。
3. **bot 侧过渡插件（已整合）**：`snowluma_trampoline-1.1.0.mfp` 曾作为
   独立分发形态（Bot 加载时自动部署上述两件），其功能现已原生并入 App：
   影子路径与跳板注入由 snowluma 进程脚本直接执行，bot 启动自愈会清理
   遗留的插件分发包。
4. **bot 核心版本**：SnowLuma 适配器（media_api 1.2.0）要求 dev 分支核心；
   bot 启动脚本已有 `git fetch origin dev + checkout` 自愈，需确保网络可达。

## 验证（修复后，重启两次均自愈成功）

```
snowluma_adapter | Bot 3840642751 连接成功
[3840642751] [OneBot.WS-Client] connected ws://127.0.0.1:8095
get_status  → {"online":true,"good":true}
get_friend_list → 9 好友（协议栈完全激活）
send_private_msg → {"status":"ok","data":{"message_id":...}}
```

App 侧登录检测（轮询 `get_status` 的 `online:true`）随之闭环。

## 回滚

- 删除 `TRAMPOLINE_SO` 与两处影子符号链接即回到修复前行为；
- 遗留插件实例：`trampoline_remove` 动作一键清理（或由新 App 启动自愈自动移除）。

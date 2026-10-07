# 手机短信桥接（mofox_sms_bridge）

> 让 Bot 主动开话题的能力来源之一：手机收到短信 → App 安卓层写入桥接文件 →
> Bot 插件识别有用信息（快递取件码、账单、行程等）→ 通过 send_api 主动私信主人。
>
> 示例：手机收到「您的包裹已到XX驿站，取件码 8-2-3006」，Bot 会主动发一条
> 「📬 你的快递到XX驿站啦，取件码是 8-2-3006，记得抽空去取哦～」。

## 一、调研结论（为什么是这个形态）

| 候选方案 | 结论 |
| --- | --- |
| 安卓层读通知（NotificationListenerService） | 需要常驻监听与用户在系统设置里手动授权，且拿到的是「通知」而非短信原文，解析不可靠。未采用 |
| 安卓层直接解析短信并决定推送 | 解析逻辑放在安卓层要跟随 App 发版才能调整，且无法复用 Bot 的会话状态。未采用 |
| **安卓层只落盘原文，Bot 插件负责识别与主动私信**（本方案） | 安卓层极薄（广播接收器 + 追加写 JSONL），识别规则全部在 Bot 插件侧，可随插件热更；主动私信走 Neo-MoFox 既有的 send_api / 聊天流体系，Bot "记得自己说过" |

关键取舍：

- **文件桥接而非数据库/IPC**：App 原生层与 proot 内的 Bot 分属两个世界，
  JSONL 追加写是最简单可靠的交接面（半行写入容忍、按字节偏移增量读、崩溃重读不丢）。
- **纯规则识别而非 LLM**：快递/验证码/账单/日程这类短信模式高度固定，
  规则零 token 成本、离线可用、结果稳定；LLM 只会引入不确定性与费用。
- **验证码默认不转发**：`forward_otp = false`，防敏感信息经 Bot 会话外泄；
  广告营销短信走默认关键词黑名单静默过滤。

## 二、数据流

```
┌─ Android 原生层 ─────────────────────────────┐
│ SMS_RECEIVED 广播（Manifest 注册，需 RECEIVE_SMS 运行时权限） │
│   └─ SmsBridgeReceiver：拼 PDU（长短信分段合并）              │
│       └─ SmsBridge.appendEvent()：JSONL 追加写               │
│           <rootfs>/root/.mofox/sms_bridge/inbox.jsonl         │
│           {"v":1,"source":"sms","id":"...","ts":...,"sender":"...","body":"..."} │
└──────────────────────────────────────────────┘
                    │  proot 内
┌─ Neo-MoFox Bot（mofox_sms_bridge 插件）──────┐
│ BridgePoller：按字节偏移增量读（storage_api 持久化偏移，     │
│               只消费完整行，半行留给写入方）                 │
│   └─ parser.analyze()：归类 + 抽取（取件码/地点/验证码/摘要） │
│       └─ filters：类别开关 + 发件号/关键词黑名单              │
│           └─ templates：话术渲染（占位符收紧）                │
│               └─ SmsNotifier：解析目标（target_list →        │
│                   core.toml owner_list 兜底）→ get_or_create │
│                   _stream → send_api.send_text 主动私信      │
└──────────────────────────────────────────────┘
```

送达语义：**at-least-once**。先发送、后推进偏移；单条事件全部目标失败时按
`max_send_attempts` 重试，超限丢弃并记日志；进程崩溃后未终结的一批会重读重发
（宁可重复、不可丢失）。单次轮询最多处理 `max_lines_per_poll` 条，防止积压刷屏。

## 三、各层文件

| 层 | 文件 | 职责 |
| --- | --- | --- |
| Android | `app/android/.../sms/SmsBridgeReceiver.kt` | 接收 SMS_RECEIVED 广播，拼 PDU 后交 SmsBridge |
| Android | `app/android/.../sms/SmsBridge.kt` | 开关存储、JSONL 追加写、512KB 轮转、测试事件注入 |
| Android | `AndroidManifest.xml` | `RECEIVE_SMS` 权限 + receiver 注册（`BROADCAST_SMS` 广播权限保护） |
| Flutter | `app/lib/core/platform/platform_gateway.dart` | `SmsBridgeStatus` + 状态/开关/测试三个 MethodChannel 方法 |
| Flutter | `app/lib/features/settings/presentation/sms_bridge_page.dart` | 「手机信息桥接」设置页：开关、权限申请、状态展示、发送测试 |
| Flutter | `app/lib/features/settings/presentation/settings_page.dart` + `app_router.dart` | 设置页入口与 `/settings/sms-bridge` 路由 |
| Kotlin | `platform/PlatformGatewayPlugin.kt` | `getSmsBridgeStatus` / `setSmsBridgeEnabled` / `sendSmsBridgeTest` 三个通道方法 |
| 铺发 | `runtime/RootfsInstaller.kt` + `runtime/RuntimeScripts.kt` | APK 内置 `mofox_sms_bridge-1.0.0.mfp` → plugin-cache → 实例 `plugins/`（bot 每次启动自愈） |
| Bot 插件 | `plugins-src/mofox_sms_bridge/`（打包为 .mfp） | 识别、过滤、话术、主动私信、运维 Action |

## 四、Bot 插件配置

`config/plugins/mofox_sms_bridge/config.toml`（默认值见 `plugins-src/mofox_sms_bridge/config.py`）：

- `[bridge]` `bridge_dir`（默认 `/root/.mofox/sms_bridge`）、`poll_interval_seconds`（5s）、
  `max_lines_per_poll`（20）、`max_send_attempts`（3）；
- `[notify]` `target_list`：留空时自动回退到 `core.toml [permissions].owner_list`；
- `[filters]`：`forward_express`（开）/ `forward_otp`（默认关）/ `forward_bill`（开）/
  `forward_schedule`（开）/ `forward_generic`（默认关），以及发件号与关键词黑名单；
- `[templates]`：各类别话术模板，占位符 `{code} {place} {sender} {summary} {platform}`，
  缺失占位符自动收紧（快递话术在取件码缺失时退化为通用提醒，不会出现"取件码是"悬空）。

运维 Action（Bot 会话内可用）：

- `sms_status`：轮询/桥接文件/偏移/最近发送结果一览；
- `sms_poll_now`：立即执行一轮轮询；
- `sms_test`：注入一条合成快递短信走完整管线。

## 五、安全与隐私边界

- 桥接开关**默认关闭**，需在设置页手动开启并授予 `RECEIVE_SMS` 运行时权限；
- receiver 声明 `android:permission="android.permission.BROADCAST_SMS"`（系统级广播权限），
  第三方应用无法向 App 伪造短信事件；
- 验证码默认不转发；发件号在通知话术里打码展示（纯数字号码保留前后段）；
- 桥接文件仅存在于 App 私有 `filesDir` 内的 rootfs 中，不经过 `/sdcard`，
  规避分区存储对外部目录的暴露；写入按 512KB 轮转防无限膨胀；
- 插件侧无网络行为，仅经框架 send_api 发送消息。

## 六、验证方式

1. 端到端（无需真收到短信）：设置页「手机信息桥接」→ 开启 → 「发送测试短信」
   → Bot 运行中时几秒内会主动私聊主人一条含取件码 8-2-3006 的快递提醒；
2. 真实链路：用另一部手机给本机发一条含「取件码」的短信；
3. Bot 会话内发「短信桥接状态」触发 `sms_status` 查看轮询与发送详情。

## 七、已知边界与后续方向

- 识别为纯规则：中文快递/银行/出行短信覆盖良好，非常规措辞会落入 generic
  （默认不转发）；后续可选接入 LLM 兜底分类（作为 opt-in）。
- 协议预留 `source` 字段，未来可扩展彩信 / 通知监听（NotificationListener）
  / 应用通知等事件源，插件侧只需新增 parser 分支。
- 长短信按 intent 内分段合并；跨 intent 的超长分段极罕见，暂不处理。

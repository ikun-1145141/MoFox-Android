# mofox_sms_bridge 插件规划(基于联网调研)

> 2026-10-05。个人项目,不发布市场、不提交仓库,本档仅作自用路线图。
> 前置文档:[sms-bridge.md](sms-bridge.md)(现状与架构)。
> 规划方法参考主动式 Agent 研究的「感知 → 决策 → 行动 → 记忆/反馈」四层框架
> ([awesome-proactive-agents](https://github.com/tao-hpu/awesome-proactive-agents)、
> [A Survey on Proactive Dialogue Systems, IJCAI 2023](https://arxiv.org/abs/2305.02750)):
> 本插件已实现「感知 + 行动」,**短板在决策(要不要说、何时说)与反馈(说了之后学什么)**,
> 后续阶段按此排序。

## 现状(P0,已完成)

短信从系统广播 → 桥接文件 → 规则识别(快递/验证码/账单/日程)→ 模板话术 → send_api 主动私信。
开关默认关、验证码默认不转发、号码打码、at-least-once、App 设置页可测端到端。

## 已知设计问题(规划内必须先还的债)

1. **多实例重复通知**:桥接文件是实例无关的,而消费偏移按实例独立存储——两个实例同时启用插件会对同一条短信各提醒一次。需要「实例作用域」约定(如:仅默认实例转发,或在 App 设置页绑定目标实例)。
2. **决策层为零**:只有类别开关,没有时段/频率/聚合控制,营销类识别漏网时会连发打扰。
3. **识别覆盖面依赖手工正则**,没有回归测试集,改一处正则可能悄悄弄坏另一类。

---

## P1 可靠性:把「收得到、不重复、不误伤」做扎实(工程债优先)

**安卓层**(参照 [SmsForwarder](https://github.com/pppscn/SmsForwarder) 的成熟做法):

- [ ] 双卡支持:记录 `subscriptionId` 并解析成 SIM1/SIM2,事件里带上;可按卡过滤(备用机场景常双卡)。
- [ ] 联系人姓名解析:收件人号码查 `ContactsContract`,通知里显示「妈妈」而非打码号码(个人项目允许,提供隐私开关)。
- [ ] 去重:运营商重发/分段重复在实际设备上常见,按 `sender+body` 在时间窗内(如 60s)去重。
- [ ] 厂商后台限制自检:MIUI/HyperOS、ColorOS 等会延迟后台广播(短信广播本身不受 Doze 限制,但厂商电池策略会拦),把「短信桥接」纳入现有保活体检页,一键引导设置电池不受限(参考 [HyperOS 后台广播修复笔记](https://github.com/dingwen07/hyperos-fcm-fix))。
- [ ] MMS 决策:明确支持或明确排除(排除则把 wap-push 广播显式忽略,写进文档)。

**Bot 插件**:

- [ ] 建立中文短信**回归测试集**(50+ 条真实风格样本:各家驿站/丰巢/银行/航旅/营销,参照 [shareven/parcel](https://github.com/shareven/parcel) 的自定义规则思路),`parser.analyze` 全量跑分,防退化。
- [ ] 审计落盘:每条事件的「已通知/已忽略 + 原因」写入 storage_api,供后续 P5 反馈与排查。

## P2 决策层:从「有就发」到「值得才发」

依据:干预时机 = 期望收益 − 打扰成本 > 阈值(Horvitz 的 expected utility 思路,见 proactive dialogue 综述);连续通知会放大负面体验(InterruptMe 一类研究,见 awesome-proactive-agents 收录)。

- [ ] **免打扰时段**(quiet hours):可配置时段内只放行时效类(取件码、验证码);紧急性分级进 parser(tags 里加 `urgent`)。
- [ ] **冷却与节流**:同类别 N 分钟冷却;全局每小时上限;超限的降级为「聚合摘要」。
- [ ] **聚合**:短时间内多条同类(如连续账单)合并成一条摘要通知。
- [ ] **LLM 兜底分类**(opt-in,默认关):规则判定为 generic/低置信时,走 `llm_api.create_llm_request` 做一次 JSON 结构化分类(类别/紧急性/一句话摘要)。规则门在前、LLM 在后,成本可控(便宜门 + 贵演员是研究里的标准架构);模型集用 `get_model_set_by_task` 选小模型。

## P3 信息变厚:从「转达短信」到「跟进事情」

- [ ] **快递订阅**:从快递短信提取运单号 → 接入 [快递100](https://api.kuaidi100.com)(免费账户 + 智能单号识别 + 订阅推送,同类免费服务还有[快递鸟](https://www.kdniao.com))→ 签收/滞留主动跟进(「到驿站 3 天还没取」)。需要处理:个人 API key 放插件配置、失败降级为纯短信转达。
- [ ] **取件码管理**:插件侧用 storage_api 存未取件事件;新增查询 Action(「我的快递」→ 列出待取件码);用户回复「取到了」即标记完成(对接 Bot 的会话理解)。
- [ ] **日程提醒升级**:从 schedule 短信抽时间,提前量提醒(出发前 2 小时),而不是收到即转。

## P4 事件源扩展(协议已留 `source` 字段)

- [ ] **APP 通知监听**:`NotificationListenerService`(需 `BIND_NOTIFICATION_LISTENER_SERVICE` + 用户跳系统设置授权;Android 14+ 有权限管控,服务被杀后要处理重连)。先挑低风险来源:日历、银行/支付 app、外卖平台;per-app 白名单配置。参照 SmsForwarder 的监控对象与规则设计。
- [ ] **未接来电**(`READ_PHONE_STATE`):可选,来源标记 `call`。
- App 设置页按来源分节管理开关与授权状态。

## P5 反馈闭环:让打扰成本被真实数据校准

- [ ] 显式反馈:Bot 会话内支持「别再提醒我这类」「X 分钟内别发」→ 直接改 filters/冷却(持久化)。
- [ ] 隐式信号:记录每条提醒后用户的回复率/忽略率,按类别自适应阈值(最小可行个性化,不引入训练,只调参)。
- [ ] 透明度:App 设置页加「最近桥接记录」列表(转发了什么、过滤了什么、为什么),对齐主动 Agent 研究里的可解释干预。

## 贯穿:安全与隐私基线(每阶段验收项)

- 验证码默认不转发;号码默认打码;联系人解析默认关(P1 引入时)。
- 桥接数据只存 App 私有目录(rootfs 内),文件轮转上限保持;插件侧处理过的明文不二次落盘。
- 不接入任何云端转发(SmsForwarder 的多通道转发是它人的场景,本插件数据不出设备 + Bot 自身的 LLM 出口)。
- 保持个人使用:不申请 Play 分发(RECEIVE_SMS 属管制权限,侧载无碍)。

## 里程碑验收

| 阶段 | 一句话验收 |
| --- | --- |
| P1 | 连续 7 天真实使用:零丢失、零重复、厂商后台不丢广播;测试集跑分不回归 |
| P2 | 深夜营销短信零打扰;3 条同类 10 分钟内只来 1 条聚合 |
| P3 | 说「我的快递」能列出待取件;滞留件有主动跟进 |
| P4 | 日历事件/外卖通知能以 `source=notification` 走同一管线 |
| P5 | 用户说「别提醒账单」后该类别永久静默;回复率统计可见 |

## 参考文献与来源

**研究综述**
- [A Survey on Proactive Dialogue Systems: Problems, Methods, and Prospects (IJCAI 2023)](https://arxiv.org/abs/2305.02750)
- [Awesome Proactive Agents —— 感知/决策/行动/记忆/评估论文地图](https://github.com/tao-hpu/awesome-proactive-agents)

**同类工程**
- [SmsForwarder(短信/来电/APP 通知转发,规则引擎、双卡、免打扰)](https://github.com/pppscn/SmsForwarder)
- [shareven/parcel(短信提取地址+取件码,自定义规则)](https://github.com/shareven/parcel) · [PickCode](https://github.com/SongZX0106/PickCode)
- [OTP Helper(F-Droid,离线短信验证码提取)](https://f-droid.org/zh_Hans/packages/io.github.jd1378.otphelper/)

**平台 API 与系统限制**
- [快递100 API(免费账户、智能单号识别、订阅推送)](https://api.kuaidi100.com) · [快递鸟免费查询接口](https://www.kdniao.com)
- Android `SMS_RECEIVED_ACTION`/Doze 与厂商电池策略、[HyperOS 后台广播延迟修复](https://github.com/dingwen07/hyperos-fcm-fix)
- `NotificationListenerService` 授权方式、Android 14 管控与被杀重连(腾讯云/CSDN 实践文)
- [MoFox-Bot-Docs 插件 API(send/llm/storage/person/event 等)](https://github.com/MoFox-Studio/MoFox-Bot-Docs)——`llm_api.create_llm_request`/`get_model_set_by_task` 为 P2 的 LLM 兜底提供官方入口

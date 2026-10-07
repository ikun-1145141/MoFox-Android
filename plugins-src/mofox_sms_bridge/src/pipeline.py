"""轮询-识别-通知主链路。

ON_START 后启动常驻轮询任务：
    bridge(inbox.jsonl 增量) → parser(分类/抽取) → filters(类别开关/黑名单)
    → templates(话术渲染) → notifier(send_api 私信)

语义：
- 先发送、后推进偏移（at-least-once：崩溃重启宁可重发一次，不丢提醒）；
- 单条事件全部目标都失败时按 max_send_attempts 重试，超限丢弃并记日志；
- 单次轮询最多处理 max_lines_per_poll 条，积压时按时间顺序分批送达。
"""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field

from src.app.plugin_system.api.log_api import get_logger

from . import parser
from .bridge import BridgeEvent, BridgePoller
from .notifier import SmsNotifier, compose_message

logger = get_logger("mofox_sms_bridge")

_TASK_NAME = "mofox_sms_bridge_poller"


class SmsBridgePlugin:  # 前向声明占位，避免循环导入的类型引用
    pass


@dataclass
class _AttemptState:
    """内存中的重试计数（重启后清零，配合 at-least-once 语义可接受）。"""

    attempts: int = 0


@dataclass
class PollResult:
    """一次轮询的结果（供 sms_status / sms_poll_now Action 使用）。"""

    scanned: int = 0
    notified: int = 0
    skipped: int = 0
    deferred: int = 0
    details: list[str] = field(default_factory=list)


class SmsBridgePipeline:
    """桥接轮询与通知管线。由插件根组件持有，生命周期与插件一致。"""

    def __init__(self, config) -> None:
        self._config = config
        self._poller = BridgePoller(config.bridge.bridge_dir)
        self._notifier = SmsNotifier(config)
        self._task = None
        self._running = False
        self._pending: list[tuple[BridgeEvent, _AttemptState]] = []
        self._in_flight_offset = 0  # 在途事件对应的最新读取位置（重试清空后推进用）
        self._last_notify_ok = True
        self._last_notify_detail = ""
        self._last_poll_ts = 0.0
        self.poll_iterations = 0

    # ---------- 生命周期 ----------

    def start(self) -> None:
        """启动常驻轮询（幂等）。"""

        if self._running:
            return
        self._running = True
        from src.kernel.concurrency import get_task_manager

        self._task = get_task_manager().create_task(
            self._poll_loop(), name=_TASK_NAME, daemon=True
        )
        logger.info("短信桥接轮询已启动")

    async def stop(self) -> None:
        """停止轮询任务（插件卸载时调用）。"""

        self._running = False
        if self._task is not None:
            self._task.cancel()
            self._task = None

    # ---------- 轮询 ----------

    async def _poll_loop(self) -> None:
        interval = max(1.0, float(self._config.bridge.poll_interval_seconds))
        while self._running:
            try:
                await self.poll_once()
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001 — 轮询循环必须存活
                logger.warning(f"短信桥接轮询异常（继续下一轮）：{exc}")
            await asyncio.sleep(interval)

    async def poll_once(self) -> PollResult:
        """执行一轮：先清重试队列，无积压时再读新事件。

        偏移语义：只有当本轮读出的事件全部终结（已通知或已忽略）才把
        偏移推进到最新读取位置；否则保持旧偏移、事件留在内存队列重试。
        进程崩溃后未终结的一批会重读重发（at-least-once，宁可重复不丢）。
        """

        self.poll_iterations += 1
        self._last_poll_ts = time.time()
        result = PollResult()

        budget = max(1, int(self._config.bridge.max_lines_per_poll))

        if self._pending:
            still_pending: list[tuple[BridgeEvent, _AttemptState]] = []
            for event, state in self._pending:
                if budget <= 0:
                    still_pending.append((event, state))
                    result.deferred += 1
                    continue
                if await self._handle_event(event, state, result):
                    budget -= 1
                else:
                    still_pending.append((event, state))
            self._pending = still_pending
            # 重试队列清空后，推进到这批事件首次读出的位置
            if not self._pending and self._in_flight_offset:
                await self._poller.save_offset(self._in_flight_offset)
                self._in_flight_offset = 0
            # 有积压时不读新事件，避免同批事件重复入队
            return result

        offset = await self._poller.load_offset()
        events, new_offset, scanned = self._poller.read_new_events(offset)
        result.scanned = scanned
        if new_offset <= offset and not events:
            return result
        self._in_flight_offset = new_offset

        for event in events:
            state = _AttemptState()
            if budget <= 0:
                self._pending.append((event, state))
                result.deferred += 1
                continue
            if await self._handle_event(event, state, result):
                budget -= 1
            else:
                self._pending.append((event, state))

        if not self._pending:
            await self._poller.save_offset(new_offset)
            self._in_flight_offset = 0

        return result

    # ---------- 单事件处理 ----------

    async def _handle_event(
        self, event: BridgeEvent, state: _AttemptState, result: PollResult
    ) -> bool:
        """处理一条事件。返回 True 表示已终结（已通知或已忽略）。"""

        body = event.body
        sender = event.sender

        blocked_word = parser.is_keyword_blocked(
            body, self._config.filters.keyword_blocklist or []
        )
        if blocked_word:
            result.skipped += 1
            result.details.append(f"{event.event_id or '事件'} 命中关键词黑名单：{blocked_word}")
            return True
        if parser.is_sender_blocked(sender, self._config.filters.sender_blocklist or []):
            result.skipped += 1
            result.details.append(f"{event.event_id or '事件'} 命中发件号黑名单：{sender}")
            return True

        insight = parser.analyze(body)
        if insight.category == parser.Category.BLOCKED:
            result.skipped += 1
            result.details.append(f"{event.event_id or '事件'} {insight.blocked_reason}")
            return True

        enabled = self._category_enabled(insight.category)
        if not enabled:
            result.skipped += 1
            result.details.append(f"{event.event_id or '事件'} 类别 {insight.category} 未开启转发")
            return True

        text = self._render(insight, sender)
        if not text:
            result.skipped += 1
            result.details.append(f"{event.event_id or '事件'} 话术渲染为空，跳过")
            return True

        ok, detail = await self._notifier.notify_text(text)
        self._last_notify_ok = ok
        self._last_notify_detail = detail
        state.attempts += 1

        if ok:
            result.notified += 1
            result.details.append(f"{event.event_id or '事件'} 已通知：{detail}")
            logger.info(f"短信提醒已送达：{detail}")
            return True

        if state.attempts >= max(1, int(self._config.bridge.max_send_attempts)):
            result.details.append(
                f"{event.event_id or '事件'} 重试 {state.attempts} 次后放弃：{detail}"
            )
            logger.warning(f"短信提醒多次失败，已放弃：{detail}")
            return True

        result.deferred += 1
        result.details.append(f"{event.event_id or '事件'} 发送失败，稍后重试：{detail}")
        return False

    def _category_enabled(self, category: str) -> bool:
        filters = self._config.filters
        return {
            parser.Category.EXPRESS: filters.forward_express,
            parser.Category.OTP: filters.forward_otp,
            parser.Category.BILL: filters.forward_bill,
            parser.Category.SCHEDULE: filters.forward_schedule,
            parser.Category.GENERIC: filters.forward_generic,
        }.get(category, False)

    def _render(self, insight, sender: str) -> str:
        templates = self._config.templates
        template = {
            parser.Category.EXPRESS: templates.express,
            parser.Category.OTP: templates.otp,
            parser.Category.BILL: templates.bill,
            parser.Category.SCHEDULE: templates.schedule,
            parser.Category.GENERIC: templates.generic,
        }.get(insight.category, "")
        if not template:
            return ""

        display_sender = parser.mask_sender(sender)
        text = compose_message(
            template,
            code=insight.code,
            place=insight.place,
            sender=display_sender,
            summary=insight.summary,
            platform=display_sender,
        )

        # 快递话术在取件码缺失时退化为通用提醒，避免「取件码是」悬空
        if insight.category == parser.Category.EXPRESS and not insight.code:
            text = compose_message(
                "📬 有快递到{place}了，短信里没识别到取件码，看一下手机短信哦～",
                place=insight.place,
            )
        return text

    # ---------- 测试注入 ----------

    async def inject_test(self, custom_body: str | None = None) -> tuple[bool, str]:
        """走完整管线处理一条合成快递短信（不经桥接文件）。

        custom_body 为空时使用内置的快递示例（含可识别的取件码与地点）。
        """

        event = BridgeEvent(
            event_id=f"test-{int(time.time() * 1000)}",
            source="sms",
            timestamp_ms=int(time.time() * 1000),
            sender="1069000000000",
            body=custom_body
            or "【菜鸟驿站】您的包裹已到阳光小区菜鸟驿站3号货架，凭取件码 8-2-3006 取件，18:00 前领取。",
            raw={},
        )
        state = _AttemptState()
        result = PollResult()
        handled = await self._handle_event(event, state, result)
        detail = "；".join(result.details) or "无输出"
        return handled and result.notified > 0, detail

    # ---------- 状态 ----------

    async def status_text(self) -> str:
        """sms_status Action 的输出。"""

        offset = await self._poller.load_offset()
        status = await self._poller.status(offset=offset)
        running = "运行中" if self._running else "已停止"
        last_ts = (
            time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(status.last_event_ts / 1000))
            if status.last_event_ts
            else "无"
        )
        last_poll = (
            time.strftime("%H:%M:%S", time.localtime(self._last_poll_ts))
            if self._last_poll_ts
            else "未执行"
        )
        notify_state = "正常" if self._last_notify_ok else "异常"
        lines = [
            f"轮询任务：{running}（第 {self.poll_iterations} 轮，最近 {last_poll}）",
            f"桥接目录：{status.bridge_dir}（{'存在' if status.dir_exists else '不存在'}）",
            f"桥接文件：{status.inbox_size} 字节 / 约 {status.event_count} 条事件",
            f"已消费偏移：{status.offset}（待处理 {status.pending_bytes} 字节，"
            f"内存重试队列 {len(self._pending)} 条）",
            f"最近事件时间：{last_ts}",
            f"最近通知发送：{notify_state}（{self._last_notify_detail or '尚未发送过'}）",
        ]
        if status.last_error:
            lines.append(f"最近错误：{status.last_error}")
        return "\n".join(lines)


__all__ = ["SmsBridgePipeline", "PollResult"]

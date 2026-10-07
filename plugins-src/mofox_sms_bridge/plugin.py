"""mofox_sms_bridge 插件入口。

把 MoFox App 安卓层收到的手机短信转达给主人，主动开启话题：
安卓层 SmsBridgeReceiver 把短信追加写入 rootfs 的
/root/.mofox/sms_bridge/inbox.jsonl；本插件常驻轮询该文件，
识别快递/取件码、验证码、账单、日程等有用信息，经 send_api 主动私信主人。

示例：手机收到「您的包裹已到XX驿站，取件码 8-2-3006」，Bot 会主动发一条
「📬 你的快递到XX驿站啦，取件码是 8-2-3006，记得抽空去取哦～」。

设计要点：
- 零第三方依赖，纯规则识别（不依赖 LLM，离线可用、零 token 成本）；
- 验证码默认不转发（forward_otp=false），防止敏感信息外泄；
- 广告/营销短信经关键词黑名单静默过滤，不打扰主人。
"""

from __future__ import annotations

from typing import cast

from src.app.plugin_system.api.log_api import get_logger
from src.app.plugin_system.base import BasePlugin, register_plugin
from src.app.plugin_system.types import EventType
from src.kernel.event import EventDecision, get_event_bus

from .config import MofoxSmsBridgeConfig
from .src.actions import (
    SmsPollNowAction,
    SmsStatusAction,
    SmsTestAction,
)
from .src.pipeline import SmsBridgePipeline

logger = get_logger("mofox_sms_bridge")


@register_plugin
class MofoxSmsBridgePlugin(BasePlugin):
    """手机短信桥接插件。"""

    plugin_name = "mofox_sms_bridge"
    plugin_description = (
        "读取 MoFox App 安卓层写入的短信桥接文件，识别快递/取件码等有用信息，"
        "主动私信主人开启话题"
    )
    plugin_version = "1.0.0"
    configs: list[type] = [MofoxSmsBridgeConfig]

    def __init__(self, config: MofoxSmsBridgeConfig | None = None) -> None:
        super().__init__(config)
        self.pipeline: SmsBridgePipeline | None = None
        config = cast("MofoxSmsBridgeConfig | None", self.config)
        if config is not None and config.plugin.enabled:
            self.pipeline = SmsBridgePipeline(config)

    def get_components(self) -> list[type]:
        config = cast("MofoxSmsBridgeConfig | None", self.config)
        if config is None or not config.plugin.enabled:
            logger.info("mofox_sms_bridge 已在配置中禁用，跳过加载")
            return []
        return [
            SmsStatusAction,
            SmsPollNowAction,
            SmsTestAction,
        ]

    async def on_plugin_loaded(self) -> None:
        """订阅 ON_START：调度器就绪后启动轮询，并立即补扫一次积压。"""

        config = cast("MofoxSmsBridgeConfig | None", self.config)
        if config is None or not config.plugin.enabled or self.pipeline is None:
            return

        bus = get_event_bus()

        async def _on_start_callback(
            event_name: str, params: dict[str, object]
        ) -> tuple[EventDecision, dict[str, object]]:
            """ON_START 回调：启动常驻轮询任务。"""
            if self.pipeline is not None:
                self.pipeline.start()
                logger.info("短信桥接插件已随 Bot 启动")
            return EventDecision.SUCCESS, params

        bus.subscribe(EventType.ON_START, _on_start_callback, priority=10)
        logger.debug("已订阅 ON_START 事件，等待 Bot 启动后开启短信轮询")

    async def on_plugin_unloaded(self) -> None:
        """插件卸载时停掉轮询任务。"""

        if self.pipeline is not None:
            await self.pipeline.stop()
            self.pipeline = None


__all__ = ["MofoxSmsBridgePlugin"]

"""mofox_sms_bridge Actions。

三个动作均为基础设施/运维操作：
- sms_status：查看桥接目录、轮询与最近发送状态；
- sms_poll_now：立即执行一轮轮询（不等周期）；
- sms_test：注入一条合成的快递短信走完整管线，验证端到端链路。
"""

from __future__ import annotations

from typing import Annotated, cast

from src.app.plugin_system.base import BaseAction
from src.app.plugin_system.types import ChatType

from ..config import MofoxSmsBridgeConfig


class _SmsBridgeBaseAction(BaseAction):
    """Action 基类：提供通用激活判断与配置访问。"""

    associated_platforms: list[str] = ["qq"]
    associated_types: list[str] = ["text"]

    def _config(self) -> MofoxSmsBridgeConfig | None:
        plugin = getattr(self, "plugin", None)
        if plugin is None:
            return None
        config = cast("MofoxSmsBridgeConfig | None", getattr(plugin, "config", None))
        return config

    def _pipeline(self):
        plugin = getattr(self, "plugin", None)
        return getattr(plugin, "pipeline", None) if plugin is not None else None

    async def go_activate(self) -> bool:  # noqa: D401
        """插件启用即激活（运维动作，与聊天内容无关）。"""

        config = self._config()
        return config is not None and config.plugin.enabled


class SmsStatusAction(_SmsBridgeBaseAction):
    """查看短信桥接状态。"""

    name: str = "sms_status"
    description: str = (
        "查询手机短信桥接插件的运行状态：轮询任务是否存活、桥接目录/文件情况、"
        "待处理事件数、最近一次主动通知的发送结果。用于排查「快递提醒没发出来」这类问题。"
    )
    chat_type: ChatType = ChatType.ALL

    async def execute(self) -> tuple[bool, str]:
        pipeline = self._pipeline()
        if pipeline is None:
            return False, "短信桥接管线未初始化（插件可能未启用）。"
        return True, await pipeline.status_text()


class SmsPollNowAction(_SmsBridgeBaseAction):
    """立即轮询一次桥接文件。"""

    name: str = "sms_poll_now"
    description: str = (
        "立即执行一轮短信桥接轮询（不等定时周期），处理手机端新写入的短信事件，"
        "返回本轮扫描/送达/跳过的统计。主人催促「快看看短信」时使用。"
    )
    chat_type: ChatType = ChatType.ALL

    async def execute(self) -> tuple[bool, str]:
        pipeline = self._pipeline()
        if pipeline is None:
            return False, "短信桥接管线未初始化（插件可能未启用）。"
        result = await pipeline.poll_once()
        summary = (
            f"本轮扫描 {result.scanned} 条，送达 {result.notified} 条，"
            f"跳过 {result.skipped} 条，留待下轮 {result.deferred} 条"
        )
        detail = "；".join(result.details[:6])
        return result.notified > 0 or result.scanned > 0, (
            f"{summary}。{detail}" if detail else summary
        )


class SmsTestAction(_SmsBridgeBaseAction):
    """注入测试短信，验证主动通知链路。"""

    name: str = "sms_test"
    description: str = (
        "向短信桥接管线注入一条模拟的快递短信（含取件码），走完整的识别与主动私信流程，"
        "用于验证「手机短信 → Bot 主动提醒」链路是否通畅。会在真实通知渠道发出一条测试消息。"
    )
    chat_type: ChatType = ChatType.ALL

    async def execute(
        self,
        content: Annotated[str, "自定义测试短信正文（留空使用内置的快递示例）"] = "",
    ) -> tuple[bool, str]:
        pipeline = self._pipeline()
        if pipeline is None:
            return False, "短信桥接管线未初始化（插件可能未启用）。"
        return await pipeline.inject_test(custom_body=content or None)


__all__ = ["SmsStatusAction", "SmsPollNowAction", "SmsTestAction"]

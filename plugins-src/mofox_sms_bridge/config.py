"""mofox_sms_bridge 插件配置。

配置文件默认路径：config/plugins/mofox_sms_bridge/config.toml
"""

from __future__ import annotations

from typing import ClassVar

from src.app.plugin_system.base import BaseConfig, Field, SectionBase, config_section


class MofoxSmsBridgeConfig(BaseConfig):
    """mofox_sms_bridge 插件配置。"""

    name: ClassVar[str] = "config"
    description: ClassVar[str] = "手机短信桥接插件配置"

    @config_section("plugin")
    class PluginSection(SectionBase):
        """插件总体配置。"""

        enabled: bool = Field(
            default=True,
            description="是否启用 mofox_sms_bridge 插件（关闭则停止轮询，所有 Action 不激活）",
        )

    @config_section("bridge")
    class BridgeSection(SectionBase):
        """桥接文件轮询配置（与 MoFox App 安卓层的写入路径对应）。"""

        bridge_dir: str = Field(
            default="/root/.mofox/sms_bridge",
            description="桥接目录（App 安卓层写入 inbox.jsonl 的位置，与 App 布局保持一致）",
        )
        poll_interval_seconds: float = Field(
            default=5.0,
            description="轮询桥接文件的间隔秒数",
        )
        max_lines_per_poll: int = Field(
            default=20,
            description="单次轮询最多处理的事件条数（防止积压时刷屏）",
        )
        max_send_attempts: int = Field(
            default=3,
            description="单条事件通知的最大尝试次数（全部目标都失败时重试，超过后丢弃并记录日志）",
        )

    @config_section("notify")
    class NotifySection(SectionBase):
        """通知目标配置。"""

        target_list: list[str] = Field(
            default_factory=list,
            description=(
                "主动通知的目标列表，格式 ['qq:123456', ...]；"
                "留空时自动使用 core.toml [permissions].owner_list 中的主人"
            ),
        )

    @config_section("filters")
    class FiltersSection(SectionBase):
        """按类别决定哪些短信值得转达（防止骚扰信息刷屏）。"""

        forward_express: bool = Field(
            default=True,
            description="转发快递/取件类短信（提取取件码与驿站地点）",
        )
        forward_otp: bool = Field(
            default=False,
            description="转发验证码短信（默认关闭：验证码敏感，请确认机器人环境安全后再开启）",
        )
        forward_bill: bool = Field(
            default=True,
            description="转发账单/扣款/余额类提醒短信",
        )
        forward_schedule: bool = Field(
            default=True,
            description="转发航班/车票/会议等日程提醒短信",
        )
        forward_generic: bool = Field(
            default=False,
            description="转发无法识别类别的普通短信（默认关闭，避免广告打扰）",
        )
        sender_blocklist: list[str] = Field(
            default_factory=list,
            description="发件号黑名单（子串匹配，命中即忽略），如 ['10086', '1069']",
        )
        keyword_blocklist: list[str] = Field(
            default_factory=list,
            description=(
                "内容关键词黑名单（子串匹配，命中即忽略），"
                "默认过滤营销退订类短信"
            ),
        )

    @config_section("templates")
    class TemplatesSection(SectionBase):
        """主动开话题的话术模板。

        可用占位符：{code} 取件码/验证码、{place} 驿站/快递柜地点、
        {sender} 发件号码、{summary} 短信摘要、{platform} 短信来源平台名。
        缺失的占位符会被替换为空串，整段占位符（含前后标点）自动收紧。
        """

        express: str = Field(
            default="📬 你的快递到{place}啦，取件码是 {code}，记得抽空去取哦～",
            description="快递/取件类短信的通知话术",
        )
        otp: str = Field(
            default="🔐 收到一条来自{platform}的验证码：{code}。我没有记住它，需要就用～",
            description="验证码类短信的通知话术（需 forward_otp 开启）",
        )
        bill: str = Field(
            default="💳 有条银行/支付提醒（来自 {sender}）：{summary}",
            description="账单/扣款类短信的通知话术",
        )
        schedule: str = Field(
            default="🗓️ 行程提醒（来自 {sender}）：{summary}",
            description="航班/车票/会议类短信的通知话术",
        )
        generic: str = Field(
            default="📨 刚收到一条短信（来自 {sender}）：{summary}",
            description="未识别类别短信的通知话术（需 forward_generic 开启）",
        )

    plugin: PluginSection = Field(default_factory=PluginSection)
    bridge: BridgeSection = Field(default_factory=BridgeSection)
    notify: NotifySection = Field(default_factory=NotifySection)
    filters: FiltersSection = Field(default_factory=FiltersSection)
    templates: TemplatesSection = Field(default_factory=TemplatesSection)


__all__ = ["MofoxSmsBridgeConfig"]

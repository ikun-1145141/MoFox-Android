"""主动通知：解析目标、组装话术、经 send_api 私信发送。

目标解析优先级：
1. config.notify.target_list（格式 ['qq:123456', ...]）；
2. 留空时回退到主程序 config/core.toml 的 [permissions].owner_list。

发送走框架公共 send_api.send_text——消息会自动入库（Bot 记得自己说过），
不直接调 OneBot API，保证与适配器、聊天流状态一致。
"""

from __future__ import annotations

import re
from pathlib import Path

from src.app.plugin_system.api.log_api import get_logger

logger = get_logger("mofox_sms_bridge")

_BOT_ROOT = Path(__file__).resolve().parents[2]
_CORE_TOML = _BOT_ROOT / "config" / "core.toml"

# 'platform:user_id' 的宽松解析：允许引号与空白
_TARGET_ENTRY_PATTERN = re.compile(r"^\s*['\"]?([A-Za-z0-9_-]+)[:：]([A-Za-z0-9_.@-]+)['\"]?\s*$")
_OWNER_LIST_PATTERN = re.compile(r"owner_list\s*=\s*\[(.*?)\]", re.DOTALL)


class SmsNotifier:
    """把短信事件转成一条主动私信并发给目标。"""

    def __init__(self, config) -> None:
        self._config = config

    async def resolve_targets(self) -> list[tuple[str, str]]:
        """返回 (platform, user_id) 列表；解析失败返回空列表。"""

        explicit: list[str] = list(self._config.notify.target_list or [])
        if explicit:
            return self._parse_targets(explicit)

        owner_entries = self._load_owner_list()
        if not owner_entries:
            logger.warning(
                "未配置通知目标：config.notify.target_list 为空，且无法从 core.toml "
                "读取 [permissions].owner_list。请补其一。"
            )
            return []
        return self._parse_targets(owner_entries)

    async def notify_text(self, text: str) -> tuple[bool, str]:
        """向所有目标发送一条文本，返回 (是否有成功, 结果描述)。"""

        targets = await self.resolve_targets()
        if not targets:
            return False, "没有可用的通知目标（target_list 与 owner_list 均为空）"

        try:
            from src.app.plugin_system.api import send_api
        except ImportError as exc:
            return False, f"send_api 不可用：{exc}"

        stream_api = None
        try:
            from src.app.plugin_system.api import stream_api as stream_api_mod
            stream_api = stream_api_mod
        except ImportError:
            stream_api = None

        ok_count = 0
        failures: list[str] = []
        for platform, user_id in targets:
            try:
                stream_id = await self._stream_id_for(platform, user_id, stream_api)
                if not stream_id:
                    failures.append(f"{platform}:{user_id} 无法确定聊天流")
                    continue
                sent = await send_api.send_text(content=text, stream_id=stream_id)
                if sent:
                    ok_count += 1
                else:
                    failures.append(f"{platform}:{user_id} send_text 返回 False")
            except Exception as exc:  # noqa: BLE001 — 单目标失败不影响其他目标
                failures.append(f"{platform}:{user_id} 发送异常：{exc}")

        if ok_count:
            detail = f"已通知 {ok_count}/{len(targets)} 个目标"
            if failures:
                detail += f"；失败：{'; '.join(failures)}"
            return True, detail

        if failures:
            return False, "全部目标发送失败：" + "；".join(failures)
        return False, "全部目标发送失败"

    async def _stream_id_for(self, platform: str, user_id: str, stream_api) -> str | None:
        """优先走 stream_api.get_or_create_stream，失败时退回本地生成。"""

        if stream_api is not None:
            try:
                stream = await stream_api.get_or_create_stream(
                    platform=platform, user_id=user_id
                )
                if stream:
                    getter = getattr(stream, "stream_id", None)
                    if callable(getter):
                        return str(getter())
                    return str(getter)
            except Exception as exc:  # noqa: BLE001 — 回退到本地生成
                logger.debug(f"get_or_create_stream 失败，退回 ChatStream 本地生成：{exc}")

        chat_stream = self._import_chat_stream()
        if chat_stream is None:
            return None
        try:
            return str(chat_stream.generate_stream_id(platform=platform, user_id=user_id))
        except Exception as exc:  # noqa: BLE001
            logger.warning(f"生成 stream_id 失败：{exc}")
            return None

    @staticmethod
    def _import_chat_stream():
        """ChatStream 的导入边界：优先 plugin_system.types，回退 core.models.stream。"""

        try:
            from src.app.plugin_system.types import ChatStream

            return ChatStream
        except ImportError:
            pass
        try:
            from src.core.models.stream import ChatStream

            return ChatStream
        except ImportError:
            return None

    @staticmethod
    def _parse_targets(entries: list[str]) -> list[tuple[str, str]]:
        targets: list[tuple[str, str]] = []
        for entry in entries:
            match = _TARGET_ENTRY_PATTERN.match(str(entry))
            if not match:
                logger.warning(f"通知目标格式无效（应为 'platform:user_id'）：{entry}")
                continue
            targets.append((match.group(1), match.group(2)))
        return targets

    @staticmethod
    def _load_owner_list() -> list[str]:
        """从 core.toml 读 owner_list；tomllib 不可用时退回正则提取。"""

        path = _CORE_TOML
        if not path.is_file():
            logger.warning(f"未找到 core.toml：{path}")
            return []
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            logger.warning(f"读取 core.toml 失败：{exc}")
            return []

        try:
            import tomllib

            data = tomllib.loads(text)
            owners = data.get("permissions", {}).get("owner_list", [])
            return [str(item) for item in owners if str(item).strip()]
        except ModuleNotFoundError:
            pass
        except Exception as exc:  # noqa: BLE001
            logger.debug(f"tomllib 解析 core.toml 失败，使用正则兜底：{exc}")

        match = _OWNER_LIST_PATTERN.search(text)
        if not match:
            return []
        return re.findall(r"['\"]([^'\"]+)['\"]", match.group(1))


def compose_message(template: str, **fields: str) -> str:
    """用安全模板渲染通知话术。

    - 缺失字段替换为空串；
    - 占位符缺失后清理紧邻的标点/空白（如「到{place}啦」缺 place 变「到啦」）；
    - 模板里的其它花括号原样保留。
    """

    rendered = template
    for key, value in fields.items():
        rendered = rendered.replace("{" + key + "}", str(value or ""))

    # 清理缺失占位符留下的悬空标点
    rendered = re.sub(r"[：:，,、]\s*(?=[，,。！!？?\s]|$)", "", rendered)
    rendered = re.sub(r"([到在去往])\s*([啦咯哦哟~～])", r"\1\2", rendered)
    rendered = re.sub(r"[ \t]+", " ", rendered)
    return rendered.strip()


__all__ = ["SmsNotifier", "compose_message"]

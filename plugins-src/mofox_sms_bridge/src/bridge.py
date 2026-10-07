"""桥接文件读取器。

MoFox App 安卓层（SmsBridgeReceiver）把收到的短信以 JSONL 追加写到
``/root/.mofox/sms_bridge/inbox.jsonl``，每行一条事件：

    {"v":1,"source":"sms","id":"1696...-ab12","ts":1696...,"sender":"...","body":"..."}

本模块按字节偏移增量读取：偏移量通过 storage_api 持久化（每个 Bot 实例
独立存储），重启续读、多实例互不干扰。读取时容忍写入方半行写入
（最后一条不完整的行留到下次轮询）。
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

_INBOX_NAME = "inbox.jsonl"
_DEFAULT_BRIDGE_DIR = "/root/.mofox/sms_bridge"


@dataclass
class BridgeEvent:
    """一条桥接事件（目前 source 固定为 sms，协议保留扩展位）。"""

    event_id: str
    source: str
    timestamp_ms: int
    sender: str
    body: str
    raw: dict[str, Any]


@dataclass
class BridgeStatus:
    """桥接目录当前状态（供 sms_status Action 展示）。"""

    bridge_dir: str
    dir_exists: bool
    inbox_size: int
    offset: int
    pending_bytes: int
    event_count: int
    last_event_ts: int
    last_error: str


class BridgePoller:
    """增量读取桥接文件，产出未消费的事件。"""

    def __init__(self, bridge_dir: str = _DEFAULT_BRIDGE_DIR) -> None:
        self.bridge_dir = Path(bridge_dir)
        self.last_error = ""

    @property
    def inbox_path(self) -> Path:
        return self.bridge_dir / _INBOX_NAME

    async def load_offset(self) -> int:
        """从插件存储读取已消费的字节偏移。"""

        try:
            from src.app.plugin_system.api import storage_api

            record = await storage_api.load_json("mofox_sms_bridge", "bridge_offset")
            if isinstance(record, dict):
                return max(0, int(record.get("offset", 0)))
        except Exception:  # noqa: BLE001 — 存储不可用时从 0 重读，宁可重复不丢
            pass
        return 0

    async def save_offset(self, offset: int) -> None:
        """持久化已消费的字节偏移。"""

        try:
            from src.app.plugin_system.api import storage_api

            await storage_api.save_json(
                "mofox_sms_bridge", "bridge_offset", {"offset": int(offset)}
            )
        except Exception as exc:  # noqa: BLE001 — 保存失败只影响下次重复读
            self.last_error = f"保存偏移失败：{exc}"

    def read_new_events(self, offset: int) -> tuple[list[BridgeEvent], int, int]:
        """读取 offset 之后的完整事件行。

        Returns:
            (events, new_offset, event_count)：new_offset 只推进到最后一条
            完整行（含换行符），半行留给写入方写完后再读。
        """

        events: list[BridgeEvent] = []
        path = self.inbox_path
        if not path.is_file():
            return events, offset, 0

        try:
            raw = path.read_bytes()
        except OSError as exc:
            self.last_error = f"读取桥接文件失败：{exc}"
            return events, offset, 0

        if len(raw) <= offset:
            return events, offset, 0

        chunk = raw[offset:]
        # 只消费以换行符结尾的完整行；末尾无换行的半行等待下次轮询
        last_newline = chunk.rfind(b"\n")
        if last_newline < 0:
            return events, offset, 0

        consumed = chunk[: last_newline + 1]
        for line in consumed.splitlines():
            line = line.strip()
            if not line:
                continue
            event = self._parse_line(line)
            if event is not None:
                events.append(event)

        new_offset = offset + len(consumed)
        return events, new_offset, len(events)

    def _parse_line(self, line: bytes) -> BridgeEvent | None:
        try:
            payload = json.loads(line.decode("utf-8", errors="replace"))
        except (json.JSONDecodeError, ValueError) as exc:
            self.last_error = f"事件行解析失败：{exc}"
            return None
        if not isinstance(payload, dict):
            self.last_error = "事件行不是 JSON 对象"
            return None

        body = str(payload.get("body", ""))
        sender = str(payload.get("sender", ""))
        if not body and not sender:
            return None

        return BridgeEvent(
            event_id=str(payload.get("id", "")),
            source=str(payload.get("source", "sms")),
            timestamp_ms=int(payload.get("ts", 0) or 0),
            sender=sender,
            body=body,
            raw=payload,
        )

    async def status(self, offset: int | None = None) -> BridgeStatus:
        """汇总桥接目录状态。"""

        if offset is None:
            offset = await self.load_offset()
        path = self.inbox_path
        size = path.stat().st_size if path.is_file() else 0

        event_count = 0
        last_ts = 0
        if path.is_file():
            try:
                for line in path.read_bytes().splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    event_count += 1
                    try:
                        ts = int(json.loads(line).get("ts", 0) or 0)
                        last_ts = max(last_ts, ts)
                    except Exception:  # noqa: BLE001 — 统计时坏行不致命
                        continue
            except OSError:
                pass

        return BridgeStatus(
            bridge_dir=str(self.bridge_dir),
            dir_exists=self.bridge_dir.is_dir(),
            inbox_size=size,
            offset=offset,
            pending_bytes=max(0, size - offset),
            event_count=event_count,
            last_event_ts=last_ts,
            last_error=self.last_error,
        )


__all__ = ["BridgeEvent", "BridgePoller", "BridgeStatus"]

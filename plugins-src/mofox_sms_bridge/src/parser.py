"""短信内容识别与关键信息提取。

把一条原始短信归类（快递/验证码/账单/日程/普通），并抽取结构化字段：
取件码、驿站/快递柜地点、验证码、可读摘要。纯规则实现，零依赖，
保证在离线、无模型的情况下也能稳定给出「主动开话题」的素材。
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field


class Category:
    """短信类别常量（对应 config.filters 的 forward_* 开关）。"""

    EXPRESS = "express"
    OTP = "otp"
    BILL = "bill"
    SCHEDULE = "schedule"
    GENERIC = "generic"
    BLOCKED = "blocked"


_EXPRESS_KEYWORDS = (
    "快递", "取件", "取货", "包裹", "驿站", "快递柜", "丰巢", "菜鸟",
    "派送", "派件", "代收点", "签收", "物流",
)

_BILL_KEYWORDS = (
    "还款", "账单", "扣款", "余额不足", "银行卡", "消费", "交易",
    "入账", "支出", "月结",
)

_SCHEDULE_KEYWORDS = (
    "航班", "值机", "登机", "车票", "高铁", "火车票", "候车",
    "会议提醒", "日程提醒", "出行",
)

_OTP_KEYWORDS = ("验证码", "校验码", "dynamic code", "confirmation code")

# 默认关键词黑名单：营销/广告短信的典型特征，命中即忽略。
_DEFAULT_KEYWORD_BLOCKLIST = (
    "退订回", "回T退订", "回TD退订", "拒收请回复R", "点击链接领取",
    "优惠券", "限时特惠", "扫码关注",
)

# 取件码：常见话术「取件码：8-2-3006」「凭取件码 8866 到…」「提货码#A12」
_CODE_PATTERNS = (
    re.compile(r"(?:取件码|取货码|提货码|提取码|凭码|取件号)[^0-9A-Za-z]{0,8}([0-9A-Za-z][0-9A-Za-z\-]{2,19})"),
    re.compile(r"(?:码|取件号)[\s:：#]{0,4}([0-9]{3,8})"),
)

# 验证码：4-8 位纯数字，通常前后有分隔
_OTP_CODE_PATTERN = re.compile(r"(?:验证码|校验码)[^0-9]{0,12}(\d{4,8})")

# 地点提取：优先动词锚定（已到/存放至/送达…后面的连续片段），
# 兜底匹配带后缀的最长候选，再按最后一个动词边界切分。
_PLACE_VERB_ANCHORED = re.compile(
    r"(?:已到|已放入|已存放至|已存至|已投递至|存放至|存放在|存放于|投递至|送达|放至|到达|放到|放进)"
    r"([\u4e00-\u9fa5A-Za-z0-9]{2,20}?(?:驿站|快递柜|智能柜|代收点|货架|物业|前台|门店))"
)
_PLACE_SUFFIX_CANDIDATE = re.compile(
    r"[\u4e00-\u9fa5A-Za-z0-9]{2,24}?(?:驿站|快递柜|智能柜|代收点|货架|物业|前台|门店)"
)
_PLACE_VERB_BOUNDARY = ("存放至", "已存放至", "已放入", "已存至", "已投递至",
                        "投递至", "存放于", "存放在", "送达", "放至", "放进",
                        "到达", "放到", "已到", "到了", "到达", "至", "到", "在", "于")
_PLACE_STOP_CHARS = set("，。！？、；：【】（）()《》<>\"'“”‘’ \t\n\r|·-—~～")

# 号码：发件人若是一串纯数字，通知里显示时打码（保留前后 3 位）
_NUMERIC_SENDER_PATTERN = re.compile(r"^\+?(86)?1?\d{5,15}$")


@dataclass
class SmsInsight:
    """一条短信的识别结果。"""

    category: str = Category.GENERIC
    code: str = ""          # 取件码 / 验证码
    place: str = ""         # 驿站 / 快递柜 / 代收点等地点
    summary: str = ""       # 面向通知的精简摘要
    blocked_reason: str = ""
    tags: list[str] = field(default_factory=list)


def analyze(body: str) -> SmsInsight:
    """识别短信正文，返回类别与抽取出的关键信息。"""

    text = (body or "").strip()
    insight = SmsInsight()
    if not text:
        insight.blocked_reason = "空短信"
        return insight

    insight.summary = _make_summary(text)

    for keyword in _DEFAULT_KEYWORD_BLOCKLIST:
        if keyword in text:
            insight.category = Category.BLOCKED
            insight.blocked_reason = f"命中默认营销关键词：{keyword}"
            return insight

    if _match_any(text, _OTP_KEYWORDS):
        insight.category = Category.OTP
        insight.code = _first_match(_OTP_CODE_PATTERN, text)
        insight.tags.append("otp")
        return insight

    if _match_any(text, _EXPRESS_KEYWORDS):
        insight.category = Category.EXPRESS
        insight.code = _extract_express_code(text)
        insight.place = _extract_place(text)
        insight.tags.append("express")
        return insight

    if _match_any(text, _SCHEDULE_KEYWORDS):
        insight.category = Category.SCHEDULE
        insight.tags.append("schedule")
        return insight

    if _match_any(text, _BILL_KEYWORDS):
        insight.category = Category.BILL
        insight.tags.append("bill")
        return insight

    insight.category = Category.GENERIC
    return insight


def is_sender_blocked(sender: str, blocklist: list[str] | tuple[str, ...]) -> bool:
    """发件号黑名单判断（子串匹配）。"""

    target = (sender or "").strip()
    if not target:
        return False
    return any(str(item).strip() and str(item).strip() in target for item in blocklist)


def is_keyword_blocked(body: str, blocklist: list[str] | tuple[str, ...]) -> str:
    """自定义关键词黑名单判断，命中返回命中的词，未命中返回空串。"""

    text = body or ""
    for keyword in blocklist:
        keyword_str = str(keyword).strip()
        if keyword_str and keyword_str in text:
            return keyword_str
    return ""


def mask_sender(sender: str) -> str:
    """通知里展示发件号：纯数字号码打码，防泄露；短号/昵称原样保留。"""

    target = (sender or "").strip()
    if not target:
        return "未知号码"
    if _NUMERIC_SENDER_PATTERN.match(target):
        digits = target.removeprefix("+").removeprefix("86")
        if len(digits) >= 8:
            return f"{digits[:4]}****{digits[-4:]}"
        if len(digits) > 4:
            return f"{digits[:2]}****"
        return digits
    return target


def _make_summary(text: str) -> str:
    """压缩正文为通知可用的摘要：去掉签名尾巴与退订语，限长。"""

    summary = re.sub(r"(退订.{0,12}|拒收.{0,8})$", "", text).strip()
    if len(summary) > 80:
        summary = summary[:79] + "…"
    return summary


def _extract_express_code(text: str) -> str:
    """提取取件码，优先匹配带「取件码」字样的强模式。"""

    for pattern in _CODE_PATTERNS:
        match = pattern.search(text)
        if match:
            return match.group(1).strip("#-—–") or match.group(1)
    return ""


def _extract_place(text: str) -> str:
    """提取驿站/快递柜等取件地点。

    先试动词锚定模式（精确），失败后取所有后缀候选中最长者，
    并按最后一个动词边界切掉「包裹已存放至」这类前缀。
    """

    match = _PLACE_VERB_ANCHORED.search(text)
    if match:
        return match.group(1)

    candidates = [
        candidate
        for candidate in _PLACE_SUFFIX_CANDIDATE.findall(text)
        if len(candidate) >= 3
    ]
    if not candidates:
        return ""
    candidate = max(candidates, key=len)
    return _cut_verb_prefix(candidate)


def _cut_verb_prefix(candidate: str) -> str:
    """切掉地点候选里最后一个动词及之前的部分（「包裹已存放至丰巢智能柜」→「丰巢智能柜」）。"""

    best = candidate
    for verb in _PLACE_VERB_BOUNDARY:
        idx = candidate.rfind(verb)
        if idx >= 0:
            remainder = candidate[idx + len(verb):]
            if len(remainder) >= 3:
                best = remainder
                break
    return best


def _walk_back_place(text: str, suffix_end: int) -> str:
    """从后缀结尾向前走，收集连续的地点字符（遇标点/空白停止）。"""

    start = suffix_end
    while start > 0 and text[start - 1] not in _PLACE_STOP_CHARS:
        start -= 1
        if suffix_end - start >= 24:
            break
    return text[start:suffix_end]


def _first_match(pattern: re.Pattern[str], text: str) -> str:
    match = pattern.search(text)
    return match.group(1).strip() if match else ""


def _match_any(text: str, keywords: tuple[str, ...]) -> bool:
    lowered = text.lower()
    return any(keyword.lower() in lowered for keyword in keywords)


__all__ = [
    "Category",
    "SmsInsight",
    "analyze",
    "is_sender_blocked",
    "is_keyword_blocked",
    "mask_sender",
]

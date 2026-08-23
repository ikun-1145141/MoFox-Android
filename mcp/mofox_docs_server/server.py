#!/usr/bin/env python3
"""Live stdio MCP server for https://docs.mofox-sama.com."""

from __future__ import annotations

import html
import json
import re
import sys
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from typing import Any


ALGOLIA_URL = "https://JZV5IVO9JD-dsn.algolia.net/1/indexes/Mofox-Docs/query"
ALGOLIA_HEADERS = {
    "x-algolia-application-id": "JZV5IVO9JD",
    "x-algolia-api-key": "e39ee94d8116ce8958647991de0f9637",
    "content-type": "application/json",
    "user-agent": "MoFox-Docs-MCP/1.0",
}
DOCS_ORIGIN = "https://docs.mofox-sama.com"
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

TOOLS = [
    {
        "name": "search_mofox_docs",
        "description": "Search the current official Neo-MoFox website. Returns live snippets and source URLs.",
        "inputSchema": {
            "type": "object",
            "properties": {"query": {"type": "string"}, "limit": {"type": "integer", "minimum": 1, "maximum": 8}},
            "required": ["query"],
        },
    },
    {
        "name": "read_mofox_doc",
        "description": "Fetch and read a current page from docs.mofox-sama.com.",
        "inputSchema": {
            "type": "object",
            "properties": {"url": {"type": "string"}, "max_chars": {"type": "integer", "minimum": 500, "maximum": 16000}},
            "required": ["url"],
        },
    },
]


class ArticleParser(HTMLParser):
    VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}

    def __init__(self) -> None:
        super().__init__()
        self.depth = 0
        self.article_depth: int | None = None
        self.ignored_depth: int | None = None
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag not in self.VOID_TAGS:
            self.depth += 1
        values = dict(attrs)
        classes = (values.get("class") or "").split()
        if self.article_depth is None and "vp-doc" in classes:
            self.article_depth = self.depth
        if self.article_depth is not None and tag in {"script", "style", "svg", "button"}:
            self.ignored_depth = self.depth
        if self.article_depth is not None and self.ignored_depth is None and tag in {"p", "br", "li", "h1", "h2", "h3", "h4", "pre", "blockquote"}:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if self.ignored_depth == self.depth:
            self.ignored_depth = None
        if self.article_depth == self.depth:
            self.article_depth = None
        if tag not in self.VOID_TAGS:
            self.depth -= 1

    def handle_data(self, data: str) -> None:
        if self.article_depth is not None and self.ignored_depth is None:
            self.parts.append(data)

    @property
    def text(self) -> str:
        value = html.unescape("".join(self.parts))
        value = re.sub(r"[ \t]+", " ", value)
        return re.sub(r"\n\s*\n+", "\n\n", value).strip()


def post_json(url: str, payload: dict[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(url, json.dumps(payload).encode(), ALGOLIA_HEADERS, method="POST")
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response)


def search(query: str, limit: int) -> str:
    data = post_json(ALGOLIA_URL, {"query": query, "hitsPerPage": limit, "attributesToRetrieve": ["hierarchy", "content", "url", "anchor"]})
    results = []
    for hit in data.get("hits", []):
        hierarchy = hit.get("hierarchy") or {}
        title = next((hierarchy.get(f"lvl{i}") for i in range(6, 0, -1) if hierarchy.get(f"lvl{i}")), hit.get("anchor") or "Neo-MoFox 文档")
        content = (hit.get("content") or "").strip()
        results.append(f"[{title}]\nsource: {hit.get('url', DOCS_ORIGIN)}\n{content[:700]}")
    return "\n\n".join(results) if results else "未找到相关官方文档。"


def read_page(url: str, maximum: int) -> str:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.netloc != "docs.mofox-sama.com":
        raise ValueError("Only docs.mofox-sama.com HTTPS URLs are allowed")
    request = urllib.request.Request(url, headers={"user-agent": "MoFox-Docs-MCP/1.0"})
    with urllib.request.urlopen(request, timeout=15) as response:
        body = response.read(2_000_000).decode("utf-8", errors="replace")
    parser = ArticleParser()
    parser.feed(body)
    return f"来源：{url}\n\n{parser.text[:maximum]}"


def call_tool(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    if name == "search_mofox_docs":
        text = search(str(arguments.get("query", "")), max(1, min(8, int(arguments.get("limit", 5)))))
    elif name == "read_mofox_doc":
        text = read_page(str(arguments.get("url", "")), max(500, min(16000, int(arguments.get("max_chars", 8000)))))
    else:
        raise ValueError(f"Unknown tool: {name}")
    return {"content": [{"type": "text", "text": text}]}


def handle(request: dict[str, Any]) -> dict[str, Any] | None:
    method, request_id = request.get("method"), request.get("id")
    if request_id is None:
        return None
    if method == "initialize":
        result = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {"listChanged": False}}, "serverInfo": {"name": "mofox-live-docs", "version": "1.0.0"}}
    elif method == "tools/list":
        result = {"tools": TOOLS}
    elif method == "tools/call":
        params = request.get("params", {})
        result = call_tool(str(params.get("name", "")), dict(params.get("arguments", {})))
    elif method == "ping":
        result = {}
    else:
        return {"jsonrpc": "2.0", "id": request_id, "error": {"code": -32601, "message": "Method not found"}}
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


for line in sys.stdin:
    try:
        response = handle(json.loads(line))
        if response is not None:
            print(json.dumps(response, ensure_ascii=False), flush=True)
    except Exception as error:
        print(json.dumps({"jsonrpc": "2.0", "id": None, "error": {"code": -32603, "message": str(error)}}, ensure_ascii=False), flush=True)

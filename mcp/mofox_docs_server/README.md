# Neo-MoFox official docs MCP

Dependency-free stdio MCP server that searches the official site's live Algolia
index and fetches current pages from <https://docs.mofox-sama.com>. It contains
no bundled documentation snapshot, so site updates are immediately available.

```json
{
  "mcpServers": {
    "mofox-docs": {
      "command": "python",
      "args": ["G:/MoFox-Android/mcp/mofox_docs_server/server.py"]
    }
  }
}
```

Tools:

- `search_mofox_docs(query, limit?)`
- `read_mofox_doc(url, max_chars?)`

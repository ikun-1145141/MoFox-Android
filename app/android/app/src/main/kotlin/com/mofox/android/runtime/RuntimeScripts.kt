package com.mofox.android.runtime

import java.io.File

class RuntimeScripts(private val installer: BootstrapInstaller) {
    fun scriptFor(task: String, args: Map<String, String>): File {
        installer.ensureBaseDirectories()
        val script = File(installer.scriptsDir, "$task.sh")
        script.writeText(contentFor(task, args))
        script.setExecutable(true, false)
        return script
    }

    fun processScript(name: String): File {
        installer.ensureBaseDirectories()
        val script = File(installer.scriptsDir, "start-$name.sh")
        script.writeText(
            when (name) {
                "bot" -> botStartScript()
                "napcat" -> napcatStartScript()
                else -> error("Unknown process: $name")
            },
        )
        script.setExecutable(true, false)
        return script
    }

    private fun contentFor(task: String, args: Map<String, String>): String {
        val name = shellQuote(args["name"].orEmpty())
        val botQq = shellQuote(args["botQq"].orEmpty())
        val ownerQq = shellQuote(args["ownerQq"].orEmpty())
        val apiKey = shellQuote(args["apiKey"].orEmpty())
        val apiBaseUrl = shellQuote(args["apiBaseUrl"].orEmpty())
        val wsPort = shellQuote(args["wsPort"].orEmpty())
        val channel = shellQuote(args["channel"].orEmpty())
        return when (task) {
            "installRuntimeDeps" -> commonHeader() + """
echo "[deps] updating pkg metadata"
command -v pkg >/dev/null 2>&1 && pkg update -y || true
echo "[deps] installing python git proot"
command -v pkg >/dev/null 2>&1 && pkg install -y python git proot || true
echo "[deps] installing uv"
command -v python >/dev/null 2>&1 && python -m pip install -U uv || true
"""
            "cloneRepo" -> commonHeader() + """
mkdir -p "${'$'}HOME/projects"
cd "${'$'}HOME/projects"
if [ ! -d Neo-MoFox ]; then
  echo "[git] cloning Neo-MoFox placeholder repository"
  echo "[git] repository url is not configured yet; created working directory"
  mkdir -p Neo-MoFox
else
  echo "[git] Neo-MoFox already exists"
fi
"""
            "syncDeps" -> commonHeader() + """
cd "${'$'}HOME/projects/Neo-MoFox"
if [ -f pyproject.toml ] && command -v uv >/dev/null 2>&1; then
  uv sync
else
  echo "[uv] pyproject.toml not found yet; skipped dependency sync"
fi
"""
            "genConfig" -> commonHeader() + """
mkdir -p "${'$'}HOME/projects/Neo-MoFox/config"
echo "[config] default config directory prepared"
"""
            "writeCore" -> commonHeader() + """
mkdir -p "${'$'}HOME/projects/Neo-MoFox/config"
cat > "${'$'}HOME/projects/Neo-MoFox/config/core.toml" <<EOF
[bot]
name = $name
qq = $botQq
owner = $ownerQq
channel = $channel

[http_router]
enabled = true
host = "127.0.0.1"
port = 8000
api_keys = [$apiKey]
EOF
echo "[config] core.toml written"
"""
            "writeModel" -> commonHeader() + """
mkdir -p "${'$'}HOME/projects/Neo-MoFox/config"
cat > "${'$'}HOME/projects/Neo-MoFox/config/model.toml" <<EOF
[model]
api_key = $apiKey
base_url = $apiBaseUrl
EOF
echo "[config] model.toml written"
"""
            "writeAdapter" -> commonHeader() + """
mkdir -p "${'$'}HOME/projects/Neo-MoFox/config"
cat > "${'$'}HOME/projects/Neo-MoFox/config/adapter.toml" <<EOF
[napcat]
enabled = true
ws_port = $wsPort
EOF
echo "[config] adapter.toml written"
"""
            "installNapcat" -> commonHeader() + """
mkdir -p "${'$'}HOME/projects/napcat"
echo "[napcat] install placeholder prepared"
"""
            "napcatLogin" -> commonHeader() + """
echo "MOFOX_QR_PAYLOAD=mofox://napcat/login/$(date +%s)"
echo "[napcat] waiting for scan is handled by UI in this stage"
"""
            "writeNapcatConfig" -> commonHeader() + """
mkdir -p "${'$'}HOME/projects/napcat/config"
cat > "${'$'}HOME/projects/napcat/config/mofox.toml" <<EOF
[websocket]
port = $wsPort
EOF
echo "[napcat] config written"
"""
            else -> commonHeader() + "echo \"[task] $task has no native script yet; skipped\"\n"
        }
    }

    private fun botStartScript(): String = commonHeader() + """
cd "${'$'}HOME/projects/Neo-MoFox"
if [ -f main.py ] && command -v uv >/dev/null 2>&1; then
  exec uv run python main.py
fi
echo "[bot] Neo-MoFox entrypoint not found; keeping placeholder process alive"
while true; do sleep 30; done
"""

    private fun napcatStartScript(): String = commonHeader() + """
cd "${'$'}HOME/projects/napcat"
echo "[napcat] placeholder process running"
while true; do sleep 30; done
"""

    private fun commonHeader(): String = """
#!/usr/bin/env sh
set -eu
mkdir -p "${'$'}HOME/projects"
""".trimStart()

    private fun shellQuote(value: String): String {
        return "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""
    }
}
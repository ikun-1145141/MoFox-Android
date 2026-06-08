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
        val botQq = shellQuote(args["botQq"].orEmpty())
        val botQqRaw = args["botQq"].orEmpty()
        val botNickname = shellQuote(args["botNickname"].orEmpty())
        val ownerQqRaw = args["ownerQq"].orEmpty()
        val apiKey = shellQuote(args["apiKey"].orEmpty())
        val apiBaseUrl = shellQuote(args["apiBaseUrl"].orEmpty())
        val wsPortRaw = args["wsPort"].orEmpty().ifBlank { "8095" }
        val channel = shellQuote(args["channel"].orEmpty().ifBlank { "main" })
        val webuiApiKey = shellQuote(args["webuiApiKey"].orEmpty())
        return when (task) {
            "installRuntimeDeps" -> commonHeader() + """
echo "[termux] installing proot-distro and helpers"
if command -v pkg >/dev/null 2>&1; then
    pkg update -y
    pkg install -y proot-distro proot git curl wget nano
else
    echo "[termux] pkg command not found"
    exit 1
fi

ensure_ubuntu

echo "[ubuntu] installing base packages"
proot-distro login ubuntu -- bash -s <<'MOFOX_UBUNTU'
set -eu
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y sudo git curl ca-certificates python3 python3-pip python3-venv build-essential screen xvfb
python3 -m pip install -U uv --break-system-packages -i https://repo.huaweicloud.com/repository/pypi/simple || python3 -m pip install -U uv --break-system-packages
grep -q 'export PATH="${'$'}HOME/.local/bin:${'$'}PATH"' "${'$'}HOME/.bashrc" 2>/dev/null || echo 'export PATH="${'$'}HOME/.local/bin:${'$'}PATH"' >> "${'$'}HOME/.bashrc"
MOFOX_UBUNTU
echo "[ubuntu] base runtime ready"
"""
            "cloneRepo" -> ubuntuScript("""
CHANNEL=$channel
BRANCH="main"
if [ "${'$'}CHANNEL" = "dev" ]; then
    BRANCH="dev"
fi
mkdir -p "${'$'}HOME/Neo-MoFox_Deployment"
cd "${'$'}HOME/Neo-MoFox_Deployment"
if [ ! -d Neo-MoFox ]; then
    clone_with_fallback "Neo-MoFox" "${'$'}BRANCH" \
        "https://github.com/MoFox-Studio/Neo-MoFox.git" \
        "https://github.ikun114.top/https://github.com/MoFox-Studio/Neo-MoFox.git"
else
    echo "[git] Neo-MoFox already exists; pulling latest ${'$'}BRANCH"
    cd Neo-MoFox
    git fetch --all --prune || true
    git checkout "${'$'}BRANCH" || true
    git pull --ff-only || true
fi
""")
            "syncDeps" -> ubuntuScript("""
cd "${'$'}HOME/Neo-MoFox_Deployment/Neo-MoFox"
if [ ! -f pyproject.toml ]; then
    echo "[uv] pyproject.toml not found"
    exit 1
fi
uv venv
uv sync
uv pip install pillow
echo "[uv] dependencies installed"
""")
            "genConfig" -> ubuntuScript("""
cd "${'$'}HOME/Neo-MoFox_Deployment/Neo-MoFox"
mkdir -p config
if [ -f config/core.toml ] && [ -f config/model.toml ]; then
    echo "[config] existing config files detected"
else
    echo "[config] generating default config via first startup"
    set +e
    timeout 60s uv run main.py
    STATUS=${'$'}?
    set -e
    if [ ! -f config/core.toml ] || [ ! -f config/model.toml ]; then
        echo "[config] first startup exited with ${'$'}STATUS and did not create required config files"
        exit 1
    fi
fi
echo "[config] default config directory prepared"
""")
            "writeCore" -> ubuntuScript("""
mkdir -p "${'$'}HOME/Neo-MoFox_Deployment/Neo-MoFox/config"
cat > "${'$'}HOME/Neo-MoFox_Deployment/Neo-MoFox/config/core.toml" <<EOF
[permissions]
owner_list = ["qq:$ownerQqRaw"]

[http_router]
enable_http_router = true
http_router_host = "127.0.0.1"
http_router_port = 8000
api_keys = [$webuiApiKey]
EOF
echo "[config] core.toml written"
""")
            "writeModel" -> ubuntuScript("""
mkdir -p "${'$'}HOME/Neo-MoFox_Deployment/Neo-MoFox/config"
cat > "${'$'}HOME/Neo-MoFox_Deployment/Neo-MoFox/config/model.toml" <<EOF
[[api_providers]]
name = "SiliconFlow"
api_key = $apiKey
base_url = $apiBaseUrl
EOF
echo "[config] model.toml written"
""")
            "writeAdapter" -> ubuntuScript("""
mkdir -p "${'$'}HOME/Neo-MoFox_Deployment/Neo-MoFox/config/plugins/napcat_adapter"
cat > "${'$'}HOME/Neo-MoFox_Deployment/Neo-MoFox/config/plugins/napcat_adapter/config.toml" <<EOF
[plugin]
enabled = true
config_version = "2.0.0"

[bot]
qq_id = $botQq
qq_nickname = $botNickname

[napcat_server]
mode = "reverse"
host = "localhost"
port = $wsPortRaw
EOF
echo "[config] napcat_adapter config written"
""")
            "installNapcat" -> ubuntuScript("""
cd "${'$'}HOME"
if [ -d /root/Napcat ]; then
    echo "[napcat] existing /root/Napcat detected"
else
    echo "[napcat] running official installer"
    curl -L -o napcat.sh https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh
    bash napcat.sh --docker n --cli y
fi
""")
            "napcatLogin" -> ubuntuScript("""
echo "[napcat] login requires NapCat WebUI"
echo "[napcat] start command: xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox"
echo "[napcat] WebUI token is under /root/Napcat/opt/QQ/resources/app/app_launcher/napcat/config/webui.json after startup"
""")
            "writeNapcatConfig" -> ubuntuScript("""
mkdir -p "/root/Napcat/config"
cat > "/root/Napcat/config/onebot11_$botQqRaw.json" <<EOF
{
    "network": {
        "httpServers": [],
        "httpClients": [],
        "websocketServers": [],
        "websocketClients": [
            {
                "name": "neo-mofox-ws-client",
                "enable": true,
                "url": "ws://127.0.0.1:$wsPortRaw",
                "messagePostFormat": "array",
                "reportSelfMessage": false,
                "reconnectInterval": 3000,
                "token": ""
            }
        ]
    },
    "musicSignUrl": "",
    "enableLocalFile2Url": false,
    "parseMultMsg": false
}
EOF
cat > "/root/Napcat/config/napcat_$botQqRaw.json" <<EOF
{
    "fileLog": true,
    "consoleLog": true,
    "fileLogLevel": "info",
    "consoleLogLevel": "info"
}
EOF
echo "[napcat] config written"
""")
            "installWebui" -> ubuntuScript("""
mkdir -p "${'$'}HOME/Neo-MoFox_Deployment/Neo-MoFox/plugins"
cd "${'$'}HOME/Neo-MoFox_Deployment/Neo-MoFox/plugins"
if [ -d webui_backend ]; then
    echo "[webui] webui_backend already exists"
else
    clone_with_fallback "webui_backend" "webui-dist" \
        "https://github.com/MoFox-Studio/MoFox-Core-Webui.git" \
        "https://github.ikun114.top/https://github.com/MoFox-Studio/MoFox-Core-Webui.git"
fi
""")
            else -> commonHeader() + "echo \"[task] $task has no native script yet; skipped\"\n"
        }
    }

    private fun botStartScript(): String = ubuntuScript("""
cd "${'$'}HOME/Neo-MoFox_Deployment/Neo-MoFox"
if [ -f .venv/bin/python ]; then
    exec .venv/bin/python main.py
fi
if command -v uv >/dev/null 2>&1; then
    exec uv run main.py
fi
echo "[bot] Neo-MoFox entrypoint not found"
exit 1
""")

    private fun napcatStartScript(): String = ubuntuScript("""
if [ -x /root/Napcat/opt/QQ/qq ]; then
    exec xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox
fi
echo "[napcat] /root/Napcat/opt/QQ/qq not found"
exit 1
""")

    private fun ubuntuScript(body: String): String = commonHeader() + """
ensure_ubuntu
proot-distro login ubuntu -- bash -s <<'MOFOX_UBUNTU'
set -eu
export DEBIAN_FRONTEND=noninteractive
export PYTHONUNBUFFERED=1
export PYTHONIOENCODING=utf-8
export PATH="${'$'}HOME/.local/bin:${'$'}PATH"

clone_with_fallback() {
    target="${'$'}1"
    branch="${'$'}2"
    shift 2
    last_error=0
    for url in "${'$'}@"; do
        echo "[git] cloning ${'$'}target from ${'$'}url"
        if git clone --depth 1 --branch "${'$'}branch" "${'$'}url" "${'$'}target"; then
            echo "[git] ${'$'}target cloned"
            return 0
        fi
        last_error=${'$'}?
        rm -rf "${'$'}target"
        echo "[git] clone failed with ${'$'}last_error; trying next mirror"
    done
    return "${'$'}last_error"
}

$body
MOFOX_UBUNTU
"""

    private fun commonHeader(): String = """
#!/usr/bin/env sh
set -eu
export PYTHONUNBUFFERED=1
export PYTHONIOENCODING=utf-8

ensure_ubuntu() {
    if ! command -v proot-distro >/dev/null 2>&1; then
        echo "[termux] proot-distro is not installed"
        exit 1
    fi
    if proot-distro login ubuntu -- true >/dev/null 2>&1; then
        echo "[ubuntu] ubuntu rootfs already installed"
    else
        echo "[ubuntu] installing ubuntu rootfs via proot-distro"
        proot-distro install ubuntu
    fi
}
""".trimStart()

    private fun shellQuote(value: String): String {
        return "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""
    }
}
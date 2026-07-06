package com.mofox.android.runtime

import java.io.File

/**
 * 生成 host 层 shell 脚本（由 [RuntimeCommandBuilder.scriptCommand] 用 libbash.so 直接执行）。
 *
 * 设计：
 * - 每个 InstallTask 对应一个一次性脚本：先注入 helpers（install_ubuntu / change_ubuntu_source /
 *   setup_fake_sysdata / login_ubuntu），再附加任务体。
 * - 除 `extractRootfs` 之外的任务，任务体都是 `login_ubuntu "..."`，进 Ubuntu 里执行命令。
 * - `args` 里的字符串通过 [shellQuote] 用单引号转义注入，避免命令注入。
 *
 * Debian 13 codename = `trixie`。变量名仍叫 UBUNTU_*，纯标识符，不影响行为。
 */
class RuntimeScripts(
    private val installer: RootfsInstaller,
    private val commandBuilder: RuntimeCommandBuilder,
) {
    fun scriptFor(task: String, args: Map<String, String>): File {
        installer.ensureBaseDirectories()
        val file = File(installer.scriptsDir, "$task.sh")
        val body = bodyFor(task, args)
        val content = buildString {
            append("#!/system/bin/sh\n")
            append("set -e\n")
            append(commonHeader())
            append('\n')
            append(body)
            append('\n')
        }.replace("\r\n", "\n").replace("\r", "\n")
        file.writeText(content)
        file.setExecutable(true, false)
        return file
    }

    /**
     * bot / napcat 长进程脚本。
     *
     * - `bot`：每个实例的 Neo-MoFox 落在 `args["repoPath"]`（通常是
     *   `/root/instances/<inst-id>/Neo-MoFox`），脚本里写实际路径。脚本文件名
     *   带上 `instanceId`，避免多实例同时启动覆盖同一份脚本。
     * - `napcat`：全局唯一安装在 `/root/napcat`，所有实例共用。
     */
    fun processScript(name: String, args: Map<String, String> = emptyMap()): File {
        val (script, suffix) = when (name) {
            "bot" -> {
                val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
                val instanceId = args["instanceId"]
                val cmd = "cd ${shellQuote(repoPath)} && export PATH=\"/root/.local/bin:${'$'}PATH\" && export UV_LINK_MODE=copy && export MOFOX_ACCEPT_STARTUP_AGREEMENTS=1 && uv run python main.py"
                cmd to (instanceId?.let { "-$it" } ?: "")
            }
            "napcat" -> {
              val botQq = args["botQq"].orEmpty()
              val cmd = "cd /root/napcat && export BOT_QQ=${shellQuote(botQq)} && bash /root/napcat/napcat.sh start ${shellQuote(botQq)}"
                cmd to ""
            }
            else -> error("Unknown process: $name")
        }
        installer.ensureBaseDirectories()
        val file = File(installer.scriptsDir, "process-$name$suffix.sh")
        val content = buildString {
            append("#!/system/bin/sh\n")
            append("set -e\n")
            append(commonHeader())
            append('\n')
            append("login_ubuntu ${shellQuote(script)}\n")
        }.replace("\r\n", "\n").replace("\r", "\n")
        file.writeText(content)
        file.setExecutable(true, false)
        return file
    }

      fun stopProcessScript(name: String, args: Map<String, String> = emptyMap()): File {
        val command = when (name) {
          "bot" -> {
            val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
            """
            REPO_PATH=${shellQuote(repoPath)}
            stop_bot_pids() {
              SIGNAL=${'$'}1
              PIDS=${'$'}(pgrep -f 'uv run python main.py|python main.py' 2>/dev/null || true)
              for PID in ${'$'}PIDS; do
                [ "${'$'}PID" = "${'$'}${'$'}" ] && continue
                CMDLINE=${'$'}(tr '\0' ' ' < "/proc/${'$'}PID/cmdline" 2>/dev/null || true)
                CWD=${'$'}(readlink "/proc/${'$'}PID/cwd" 2>/dev/null || true)
                case "${'$'}CMDLINE" in
                  *pgrep*|*stop-process-bot*) continue ;;
                esac
                if [ "${'$'}CWD" = "${'$'}REPO_PATH" ] || printf '%s' "${'$'}CMDLINE" | grep -F -- "${'$'}REPO_PATH" >/dev/null 2>&1; then
                  kill -"${'$'}SIGNAL" "${'$'}PID" 2>/dev/null || true
                fi
              done
            }
            stop_bot_pids TERM
            sleep 2
            stop_bot_pids KILL
            true
            """.trimIndent()
          }
          "napcat" -> "pkill -TERM -f /root/Napcat/opt/QQ/qq || true"
          else -> error("Unknown process: $name")
        }
        installer.ensureBaseDirectories()
        val file = File(installer.scriptsDir, "stop-process-$name.sh")
        val content = buildString {
          append("#!/system/bin/sh\n")
          append("set -e\n")
          append(commonHeader())
          append('\n')
          append("login_ubuntu ${shellQuote(command)}\n")
        }.replace("\r\n", "\n").replace("\r", "\n")
        file.writeText(content)
        file.setExecutable(true, false)
        return file
      }

    /** 交互式 shell 脚本：由 native PTY 启动，进 Debian 后 `cd <cwd>` 再起 `bash -il`。 */
    fun interactiveShellScript(cwd: String): File {
        installer.ensureBaseDirectories()
        val file = File(installer.scriptsDir, "shell-interactive.sh")
        val inner = "cd ${shellQuote(cwd)} 2>/dev/null || cd /root; exec /bin/bash -il"
        val content = buildString {
            append("#!/system/bin/sh\n")
            append("set -e\n")
            append(commonHeader())
            append('\n')
            append("login_ubuntu ${shellQuote(inner)}\n")
        }.replace("\r\n", "\n").replace("\r", "\n")
        file.writeText(content)
        file.setExecutable(true, false)
        return file
    }

    private fun bodyFor(task: String, args: Map<String, String>): String {
        return when (task) {
            "extractRootfs" -> extractRootfsBody()
            "installRuntimeDeps" -> loginBody(
                """
                log_step "安装运行时依赖…"
                apt-get update -y
                DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                  python3 python3-pip python3-venv git curl ca-certificates xz-utils locales \
                  ffmpeg libgcrypt20 xvfb
                sed -i 's/^# *\(zh_CN.UTF-8 UTF-8\)/\1/' /etc/locale.gen
                sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
                locale-gen zh_CN.UTF-8 en_US.UTF-8 || true
                update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 || true
                cat > /etc/default/locale <<'MOFOX_LOCALE_EOF'
                LANG=zh_CN.UTF-8
                LC_ALL=zh_CN.UTF-8
                MOFOX_LOCALE_EOF
                log_ok "系统包安装完成"
                log_info "安装 uv 包管理器…"
                curl -LsSf https://astral.sh/uv/install.sh | sh || true
                . /root/.local/bin/env 2>/dev/null || true
                python3 --version
                git --version
                log_ok "运行时依赖就绪"
                """.trimIndent(),
            )
            "cloneRepo" -> {
                val repoUrl = args["repoUrl"] ?: "https://github.com/MoFox-Studio/Neo-MoFox.git"
                val installDir = args["installDir"] ?: "/root/instances/default"
                val repoPath = args["repoPath"] ?: "$installDir/Neo-MoFox"
                loginBody(
                    """
                    log_step "克隆 Neo-MoFox 仓库…"
                    mkdir -p ${shellQuote(installDir)}
                    cd ${shellQuote(installDir)}
                    if [ -d ${shellQuote(repoPath)}/.git ]; then
                      log_info "仓库已存在，拉取最新代码…"
                      cd ${shellQuote(repoPath)} && git pull --ff-only || true
                    else
                      git clone --depth=1 ${shellQuote(repoUrl)} Neo-MoFox
                      cd ${shellQuote(repoPath)}
                    fi
                    log_ok "仓库克隆完成"
                    """.trimIndent(),
                )
            }
            "syncDeps" -> {
                val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
                loginBody(
                    """
                    log_step "同步 Python 依赖…"
                    cd ${shellQuote(repoPath)}
                    export PATH="/root/.local/bin:${'$'}PATH"
                    export UV_LINK_MODE=copy
                    rm -rf .venv
                    if command -v uv >/dev/null 2>&1; then
                      uv sync --link-mode=copy --no-cache
                    else
                      python3 -m venv .venv
                      . .venv/bin/activate
                      pip install --no-cache-dir -r requirements.txt
                    fi
                    log_ok "Python 依赖同步完成"
                    """.trimIndent(),
                )
            }
            "genConfig" -> {
                val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
                loginBody(
                    """
                    log_step "生成默认配置…"
                    cd ${shellQuote(repoPath)}
                    mkdir -p config
                    if [ ! -f config/bot_config.toml ]; then
                      python3 -m mofox.config.generate || true
                    fi
                    log_ok "配置文件就绪"
                    """.trimIndent(),
                )
            }
            "writeCore" -> writeCoreBody(args)
            "writeModel" -> writeModelBody(args)
            "writeAdapter" -> writeAdapterBody(args)
            "installWebui" -> {
                val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
                val webuiKey = args["webuiApiKey"].orEmpty()
                loginBody(
                    """
                    log_step "安装 WebUI…"
                    cd ${shellQuote(repoPath)}
                    if [ -d webui ]; then
                      cd webui && (npm install --omit=dev || true) && (npm run build || true)
                      log_ok "WebUI 构建完成"
                    else
                      log_warn "webui 目录不存在，跳过"
                    fi
                    log_info "WebUI api_key=${shellQuote(webuiKey)}"
                    """.trimIndent(),
                )
            }
            "installNapcat" -> loginBody(
                """
                log_step "安装 NapCat…"
                apt-get update -y
                mkdir -p /root/napcat-installer /root/napcat
                cd /root/napcat-installer
                if [ ! -f /root/Napcat/opt/QQ/qq ]; then
                  log_info "下载 NapCat 安装脚本…"
                  curl -L --fail --connect-timeout 20 --retry 3 \
                    https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh \
                    -o napcat-install.sh
                  bash napcat-install.sh --docker n --cli n --proxy 0
                else
                  log_info "NapCat 已安装，跳过"
                fi
                cat > /root/napcat/napcat.sh <<'MOFOX_NAPCAT_EOF'
                #!/bin/sh
                set -e
                ACTION="${'$'}{1:-start}"
                QQ="${'$'}{2:-${'$'}BOT_QQ}"
                QQ_BIN="/root/Napcat/opt/QQ/qq"
                case "${'$'}ACTION" in
                  start)
                    if [ -n "${'$'}QQ" ]; then
                      exec xvfb-run -a "${'$'}QQ_BIN" --no-sandbox -q "${'$'}QQ"
                    fi
                    exec xvfb-run -a "${'$'}QQ_BIN" --no-sandbox
                    ;;
                  *)
                    echo "usage: napcat.sh start [qq]" >&2
                    exit 2
                    ;;
                esac
                MOFOX_NAPCAT_EOF
                chmod +x /root/napcat/napcat.sh
                mkdir -p /root/napcat/config
                log_ok "NapCat 安装完成"
                """.trimIndent(),
            )
            "napcatLogin" -> {
                val botQq = args["botQq"].orEmpty()
                loginBody(
                    """
                    log_step "NapCat 扫码登录…"
                    cd /root/napcat
                    export BOT_QQ=${shellQuote(botQq)}
                    DEFAULT_QR_PATH=/root/napcat/cache/qrcode.png
                    NAPCAT_APP_QR_PATH=/root/Napcat/opt/QQ/resources/app/app_launcher/napcat/cache/qrcode.png
                    mkdir -p /root/napcat/cache
                    rm -f "${'$'}DEFAULT_QR_PATH" "${'$'}NAPCAT_APP_QR_PATH" /tmp/napcat-login.log
                    xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox -q "${'$'}BOT_QQ" > /tmp/napcat-login.log 2>&1 &
                    NAPCAT_PID=${'$'}!
                    stop_napcat_login_process() {
                      pkill -TERM -f '/root/Napcat/opt/QQ/qq' 2>/dev/null || true
                      pkill -TERM -f 'xvfb-run -a /root/Napcat/opt/QQ/qq' 2>/dev/null || true
                      pkill -TERM -f 'Xvfb' 2>/dev/null || true
                      pkill -TERM -f 'dbus-launch' 2>/dev/null || true
                      kill "${'$'}NAPCAT_PID" 2>/dev/null || true
                      for _ in ${'$'}(seq 1 5); do
                        if ! kill -0 "${'$'}NAPCAT_PID" 2>/dev/null; then
                          wait "${'$'}NAPCAT_PID" 2>/dev/null || true
                          return 0
                        fi
                        sleep 1
                      done
                      pkill -KILL -f '/root/Napcat/opt/QQ/qq' 2>/dev/null || true
                      pkill -KILL -f 'xvfb-run -a /root/Napcat/opt/QQ/qq' 2>/dev/null || true
                      pkill -KILL -f 'Xvfb' 2>/dev/null || true
                      kill -KILL "${'$'}NAPCAT_PID" 2>/dev/null || true
                      wait "${'$'}NAPCAT_PID" 2>/dev/null || true
                    }
                    QR_EMITTED=0
                    LOGIN_DONE=0
                    for i in ${'$'}(seq 1 180); do
                      sleep 1
                      if [ -s /tmp/napcat-login.log ]; then
                        tail -n 20 /tmp/napcat-login.log
                      fi
                      if [ "${'$'}QR_EMITTED" = "0" ]; then
                        QR_PATH=""
                        if [ -s /tmp/napcat-login.log ]; then
                          QR_PATH=${'$'}(sed -n 's/.*二维码已保存到 \([^[:space:]]*qrcode\.png\).*/\1/p' /tmp/napcat-login.log | tail -n 1)
                        fi
                        if [ -z "${'$'}QR_PATH" ] && [ -s "${'$'}NAPCAT_APP_QR_PATH" ]; then
                          QR_PATH="${'$'}NAPCAT_APP_QR_PATH"
                        fi
                        if [ -z "${'$'}QR_PATH" ] && [ -s "${'$'}DEFAULT_QR_PATH" ]; then
                          QR_PATH="${'$'}DEFAULT_QR_PATH"
                        fi
                        if [ -n "${'$'}QR_PATH" ] && [ -s "${'$'}QR_PATH" ]; then
                          echo "MOFOX_QR_IMAGE=${'$'}QR_PATH"
                          QR_EMITTED=1
                        fi
                      fi
                      if grep -q '配置加载' /tmp/napcat-login.log 2>/dev/null; then
                        log_ok "NapCat 登录成功"
                        LOGIN_DONE=1
                        break
                      fi
                      if grep -q 'Login Error' /tmp/napcat-login.log 2>/dev/null; then
                        log_error "NapCat 登录失败"
                        stop_napcat_login_process
                        exit 1
                      fi
                      if ! kill -0 "${'$'}NAPCAT_PID" 2>/dev/null; then
                        break
                      fi
                    done
                    if [ "${'$'}LOGIN_DONE" != "1" ]; then
                      log_error "登录等待超时或 NapCat 已退出"
                      stop_napcat_login_process
                      exit 1
                    fi
                    stop_napcat_login_process
                    """.trimIndent(),
                )
            }
            "writeNapcatConfig" -> writeNapcatConfigBody(args)
            "registerInstance" -> {
                val instanceName = args["instanceName"].orEmpty()
                val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
                loginBody(
                    """
                    log_step "注册实例…"
                    mkdir -p /root/.mofox
                    cat > /root/.mofox/instance.toml <<'MOFOX_EOF'
                    name = "$instanceName"
                    path = "$repoPath"
                    MOFOX_EOF
                    log_ok "实例 $instanceName 已注册"
                    """.trimIndent(),
                )
            }
                "deleteInstance" -> {
                  val installDir = args["installDir"] ?: error("Missing installDir")
                  loginBody(
                    """
                    case ${shellQuote(installDir)} in
                      /root/instances/*)
                      rm -rf -- ${shellQuote(installDir)}
                      log_ok "已删除实例目录: $installDir"
                      ;;
                      *)
                      log_error "拒绝删除 /root/instances 之外的路径: $installDir"
                      exit 2
                      ;;
                    esac
                    """.trimIndent(),
                  )
                }
            else -> error("Unknown task: $task")
        }
    }

    private fun extractRootfsBody(): String {
        return """
            progress_echo() { echo "[progress] $@"; }
            log_step "解压 Debian 13 rootfs…"
            install_ubuntu
            change_ubuntu_source
            configure_ubuntu_dns
            setup_fake_sysdata
            log_ok "rootfs 就绪: ${'$'}UBUNTU_PATH"
        """.trimIndent()
    }

    private fun writeCoreBody(args: Map<String, String>): String {
        val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
        val instanceName = args["instanceName"].orEmpty()
        val botQq = args["botQq"].orEmpty()
        val botNickname = args["botNickname"].orEmpty()
        val ownerQq = args["ownerQq"].orEmpty()
        val webuiPort = args["webuiPort"] ?: "8080"
        val webuiKey = args["webuiApiKey"].orEmpty()
        return loginBody(
            """
            log_step "写入 core.toml…"
            mkdir -p ${shellQuote(repoPath)}/config
            cat > ${shellQuote(repoPath)}/config/core.toml <<'MOFOX_EOF'
            [bot]
            instance_name = "$instanceName"
            qq = "$botQq"
            nickname = "$botNickname"
            owner_qq = "$ownerQq"

            [http_router]
            host = "0.0.0.0"
            port = $webuiPort
            api_key = "$webuiKey"
            MOFOX_EOF
            log_ok "core.toml 写入完成"
            """.trimIndent(),
        )
    }

    private fun writeModelBody(args: Map<String, String>): String {
        val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
        val apiKey = args["apiKey"].orEmpty()
        // SiliconFlow base URL 硬编码，用户无需在向导中填写。
        val apiBaseUrl = "https://api.siliconflow.cn/v1"
        return loginBody(
            """
            log_step "写入 model.toml…"
            mkdir -p ${shellQuote(repoPath)}/config
            cat > ${shellQuote(repoPath)}/config/model.toml <<'MOFOX_EOF'
            [model]
            api_key = "$apiKey"
            base_url = "$apiBaseUrl"
            MOFOX_EOF
            log_ok "model.toml 写入完成"
            """.trimIndent(),
        )
    }

    private fun writeAdapterBody(args: Map<String, String>): String {
        val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
        val wsPort = args["wsPort"] ?: "8095"
        val botQq = args["botQq"].orEmpty()
        val botNickname = args["botNickname"].orEmpty()
        val adapterDir = "${shellQuote(repoPath)}/config/plugins/onebot_adapter"
        return loginBody(
            """
            log_step "写入 onebot_adapter/config.toml…"
            mkdir -p $adapterDir
            cat > $adapterDir/config.toml <<'MOFOX_EOF'
            [plugin]
            enabled = true
            config_version = "2.0.0"

            [bot]
            qq_id = "$botQq"
            qq_nickname = "$botNickname"

            [napcat_server]
            mode = "reverse"
            host = "localhost"
            port = $wsPort
            access_token = ""
            MOFOX_EOF
            log_ok "onebot_adapter/config.toml 写入完成"
            """.trimIndent(),
        )
    }

    private fun writeNapcatConfigBody(args: Map<String, String>): String {
        val wsPort = args["wsPort"] ?: "8095"
        val botQq = args["botQq"].orEmpty()
        return loginBody(
            """
            log_step "写入 NapCat 配置…"
            mkdir -p /root/napcat/config
            cat > /root/napcat/config/onebot11_${'$'}{BOT_QQ:-${botQq}}.json <<'MOFOX_EOF'
            {
              "network": {
                "httpServers": [],
                "httpClients": [],
                "websocketServers": [],
                "websocketClients": [
                  {
                    "name": "neo-mofox-ws-client",
                    "enable": true,
                    "url": "ws://127.0.0.1:${'$'}wsPort",
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
            MOFOX_EOF
            cat > /root/napcat/config/napcat_${'$'}{BOT_QQ:-${botQq}}.json <<'MOFOX_EOF2'
            {
              "fileLog": true,
              "consoleLog": true,
              "fileLogLevel": "info",
              "consoleLogLevel": "info"
            }
            MOFOX_EOF2
            log_ok "NapCat 配置写入完成"
            """.trimIndent(),
        )
    }

    /**
     * 生成打包脚本：在 Debian 内用 tar 把指定路径打包到 destPath。
     * paths 是 rootfs 内的绝对路径，destPath 也是 rootfs 内的绝对路径。
     */
    fun packTarScript(paths: List<String>, destPath: String): File {
        val pathsArg = paths.joinToString(" ") { shellQuote(it) }
        val body = """
            log_step "打包备份文件…"
            mkdir -p $(dirname ${shellQuote(destPath)})
            tar cJf ${shellQuote(destPath)} $pathsArg
            log_ok "打包完成: $destPath"
        """.trimIndent()
        installer.ensureBaseDirectories()
        val file = File(installer.scriptsDir, "pack-tar.sh")
        val content = buildString {
            append("#!/system/bin/sh\n")
            append("set -e\n")
            append(commonHeader())
            append('\n')
            append("login_ubuntu ${shellQuote(body)}\n")
        }.replace("\r\n", "\n").replace("\r", "\n")
        file.writeText(content)
        file.setExecutable(true, false)
        return file
    }

    /** 把任务体包成 `login_ubuntu '...'`。 */
    private fun loginBody(body: String): String {
        return "login_ubuntu ${shellQuote(body)}"
    }

    /** 公共脚本头：env + 4 个 helper 函数。 */
    private fun commonHeader(): String {
        return buildString {
            appendLine("# === MoFox runtime common header ===")
            appendLine("export UBUNTU=${shellQuote(installer.ubuntuTarballName)}")
            appendLine("export UBUNTU_NAME=${shellQuote(installer.ubuntuTarballName.removeSuffix(".tar.xz"))}")
            appendLine()
            appendLine(progressHelper())
            appendLine(colorBashrcFn())
            appendLine(changeUbuntuSourceFn())
            appendLine(configureUbuntuDnsFn())
            appendLine(installUbuntuFn())
            appendLine(setupFakeSysdataFn())
            appendLine(loginUbuntuFn())
        }
    }

    private fun progressHelper(): String = """
        progress_echo(){
          echo "[progress] $*"
          [ -n "${'$'}TMPDIR" ] && echo "$*" > "${'$'}TMPDIR/progress_des" 2>/dev/null || true
        }

        # 彩色日志辅助函数（ANSI SGR）
        # \033 在 printf 格式串中被直接解释为 ESC 字符，兼容 Android mksh。
        log_info(){ printf "\033[36m%s\033[0m\\n" "${'$'}*"; }
        log_ok(){   printf "\033[32m✓ %s\033[0m\\n" "${'$'}*"; }
        log_warn(){ printf "\033[33m⚠ %s\033[0m\\n" "${'$'}*"; }
        log_error(){ printf "\033[31m✗ %s\033[0m\\n" "${'$'}*"; }
        log_step(){ printf "\033[34m▶ %s\033[0m\\n" "${'$'}*"; }
    """.trimIndent()

    /**
     * 写入彩色 .bashrc 到 rootfs 的 /root/.bashrc。
     *
     * - 只在文件不存在或不含 MoFox 标记时写入，避免覆盖用户自定义。
     * - 包含：ls/grep/diff 颜色别名、Ubuntu 风格彩色 PS1、LS_COLORS。
     */
    private fun colorBashrcFn(): String = """
        _write_color_bashrc(){
          BASHRC="${'$'}1"
          if [ -f "${'$'}BASHRC" ] && grep -q 'MOFOX_COLOR_BASHRC' "${'$'}BASHRC" 2>/dev/null; then
            return 0
          fi
          cat >> "${'$'}BASHRC" <<'MOFOX_COLOR_BASHRC_EOF'
        #
        # ~/.bashrc — MoFox 彩色终端配置 (MOFOX_COLOR_BASHRC)
        #

        # If not running interactively, don't do anything
        [[ ${'$'}- != *i* ]] && return

        # 1. 基础颜色别名
        alias ls='ls --color=auto'
        alias grep='grep --color=auto'
        alias diff='diff --color=auto'
        alias ip='ip --color=auto'

        # 2. 彩色提示符 (Ubuntu 风格)
        # 用户名绿色 @ 主机名 路径蓝色，root 用户名变红
        if [ "${'$'}EUID" -eq 0 ]; then
          export PS1='${'$'}{debian_chroot:+(${'$'}debian_chroot)}\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]# '
        else
          export PS1='${'$'}{debian_chroot:+(${'$'}debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
        fi

        # 3. LS_COLORS：让 ls 的目录/链接/可执行文件等有区分色
        export LS_COLORS=${'$'}{LS_COLORS:-}:'di=01;34:ln=01;36:ex=01;32:pi=33:so=01;35:bd=01;33:cd=01;33:*.tar=01;31:*.gz=01;31:*.xz=01;31:*.zip=01;31:*.7z=01;31:*.py=01;33:*.sh=01;33:*.json=01;33:*.toml=01;33:*.md=01;37:'

        # 4. 常用别名
        alias ll='ls -alF --color=auto'
        alias la='ls -A --color=auto'
        alias l='ls -CF --color=auto'
        alias ..='cd ..'
        alias ...='cd ../..'

        # 5. 让 less 支持颜色
        export LESS='-R'
        export LESS_TERMCAP_mb=$'\033[01;31m'
        export LESS_TERMCAP_md=$'\033[01;34m'
        export LESS_TERMCAP_me=$'\033[0m'
        export LESS_TERMCAP_se=$'\033[0m'
        export LESS_TERMCAP_so=$'\033[01;44;37m'
        export LESS_TERMCAP_ue=$'\033[0m'
        export LESS_TERMCAP_us=$'\033[01;32m'

        MOFOX_COLOR_BASHRC_EOF
        }
    """.trimIndent()

    private fun changeUbuntuSourceFn(): String = """
        change_ubuntu_source(){
          mkdir -p "${'$'}UBUNTU_PATH/etc/apt"
          # debuerreotype 默认会落 deb822 格式的 /etc/apt/sources.list.d/debian.sources，
          # 我们这里直接写经典 sources.list 并把它干掉，避免双源。
          rm -f "${'$'}UBUNTU_PATH/etc/apt/sources.list.d/debian.sources"
          cat <<'MOFOX_SRC_EOF' > "${'$'}UBUNTU_PATH/etc/apt/sources.list"
        deb http://mirrors.huaweicloud.com/debian/ $UBUNTU_CODENAME main contrib non-free non-free-firmware
        deb http://mirrors.huaweicloud.com/debian/ $UBUNTU_CODENAME-updates main contrib non-free non-free-firmware
        deb http://mirrors.huaweicloud.com/debian-security/ $UBUNTU_CODENAME-security main contrib non-free non-free-firmware
        deb http://mirrors.huaweicloud.com/debian/ $UBUNTU_CODENAME-backports main contrib non-free non-free-firmware
        MOFOX_SRC_EOF
        }
    """.trimIndent()

    private fun configureUbuntuDnsFn(): String = """
        configure_ubuntu_dns(){
          mkdir -p "${'$'}UBUNTU_PATH/etc"
          rm -f "${'$'}UBUNTU_PATH/etc/resolv.conf"
          : > "${'$'}UBUNTU_PATH/etc/resolv.conf"

          add_nameserver(){
            DNS="${'$'}1"
            case "${'$'}DNS" in
              *.*.*.*|*:*) ;;
              *) return 0 ;;
            esac
            if ! grep -qx "nameserver ${'$'}DNS" "${'$'}UBUNTU_PATH/etc/resolv.conf" 2>/dev/null; then
              echo "nameserver ${'$'}DNS" >> "${'$'}UBUNTU_PATH/etc/resolv.conf"
            fi
          }

          for PROP in net.dns1 net.dns2 net.dns3 net.dns4; do
            VALUE=${'$'}(getprop "${'$'}PROP" 2>/dev/null || true)
            [ -n "${'$'}VALUE" ] && add_nameserver "${'$'}VALUE"
          done

          add_nameserver 223.5.5.5
          add_nameserver 119.29.29.29
          add_nameserver 8.8.8.8
          chmod 644 "${'$'}UBUNTU_PATH/etc/resolv.conf" 2>/dev/null || true
          log_info "resolv.conf: ${'$'}(tr '\n' ';' < "${'$'}UBUNTU_PATH/etc/resolv.conf")"
        }
    """.trimIndent()

    private fun installUbuntuFn(): String = """
        install_ubuntu(){
          # busybox ships as libbusybox.so; create applet symlinks so argv[0] basename matches.
          BB="${'$'}HOME_PATH/.bb"
          mkdir -p "${'$'}BB"
          for applet in tar rm cp mv ls cat ln mkdir chmod sleep find sed awk grep head tail wc xargs sort sh xz gzip bzip2; do
            [ -L "${'$'}BB/${'$'}applet" ] || ln -sf "${'$'}BIN/libbusybox.so" "${'$'}BB/${'$'}applet"
          done

          NEED_INSTALL=0
          if [ ! -d "${'$'}UBUNTU_PATH/bin" ]; then
            log_warn "缺少 bin 目录，需要重新安装"
            NEED_INSTALL=1
          elif [ ! -f "${'$'}UBUNTU_PATH/usr/bin/env" ]; then
            log_warn "缺少 /usr/bin/env，需要重新安装"
            NEED_INSTALL=1
          elif [ ! -d "${'$'}UBUNTU_PATH/etc" ]; then
            log_warn "缺少 etc 目录，需要重新安装"
            NEED_INSTALL=1
          fi

          if [ "${'$'}NEED_INSTALL" -eq 1 ] || [ -z "${'$'}(ls -A "${'$'}UBUNTU_PATH" 2>/dev/null)" ]; then
            log_info "${'$'}UBUNTU_PATH 未就绪，开始安装…"
            PERSISTENT_BACKUP="${'$'}HOME_PATH/ubuntu_user_backup"
            if [ -d "${'$'}UBUNTU_PATH/root" ]; then
              log_info "备份 /root 到 ${'$'}PERSISTENT_BACKUP"
              mkdir -p "${'$'}PERSISTENT_BACKUP"
              "${'$'}BB/cp" -r "${'$'}UBUNTU_PATH/root" "${'$'}PERSISTENT_BACKUP/root_backup" || true
            fi
            "${'$'}BB/rm" -rf "${'$'}UBUNTU_PATH"
            mkdir -p "${'$'}UBUNTU_PATH"
            TAR_LOG="${'$'}HOME_PATH/tar.log"
            # rootfs has ~115 hardlinks pointing at usr/bin/coreutils. Android
            # /data blocks cross-inode hardlinks, so plain busybox tar drops
            # them and leaves usr/bin/env as a dangling symlink. proot's
            # --link2symlink ptrace shim transparently rewrites link() into
            # symlink() so extraction completes correctly.
            log_info "proot --link2symlink busybox tar xJf ${'$'}HOME_PATH/${'$'}UBUNTU -> ${'$'}UBUNTU_PATH"
            log_step "解压 Debian 13 rootfs (~250MB)，请稍候…"
            "${'$'}BIN/libproot.so" --link2symlink "${'$'}BB/tar" xJf "${'$'}HOME_PATH/${'$'}UBUNTU" -C "${'$'}UBUNTU_PATH/" > "${'$'}TAR_LOG" 2>&1 || {
              TAR_RC=${'$'}?
              log_error "tar 失败 (rc=${'$'}TAR_RC)，日志末尾："
              "${'$'}BB/tail" -n 40 "${'$'}TAR_LOG" 2>/dev/null || cat "${'$'}TAR_LOG"
              exit "${'$'}TAR_RC"
            }
            log_info "tar 退出 0，验证 rootfs 完整性…"
            # busybox tar may exit 0 even when extraction is incomplete (e.g.
            # malformed entries silently skipped). Without this guard the
            # caller will try to write resolv.conf into a missing etc/ and
            # blow up with a confusing ENOENT. Dump tar.log on mismatch.
            MISSING=""
            for must in etc usr usr/bin bin; do
              if [ ! -e "${'$'}UBUNTU_PATH/${'$'}must" ]; then
                MISSING="${'$'}MISSING ${'$'}must"
              fi
            done
            if [ -n "${'$'}MISSING" ]; then
              log_error "tar 报告成功但 rootfs 缺少:${'$'}MISSING"
              log_error "tar.log 末尾 (最后 60 行)："
              "${'$'}BB/tail" -n 60 "${'$'}TAR_LOG" 2>/dev/null || cat "${'$'}TAR_LOG"
              log_error "实际解压的顶层条目："
              "${'$'}BB/ls" -la "${'$'}UBUNTU_PATH" 2>/dev/null || true
              exit 1
            fi
            log_ok "解压完成"
            if [ -d "${'$'}UBUNTU_PATH/${'$'}UBUNTU_NAME" ]; then
              "${'$'}BB/mv" "${'$'}UBUNTU_PATH/${'$'}UBUNTU_NAME"/* "${'$'}UBUNTU_PATH/" || true
              "${'$'}BB/rm" -rf "${'$'}UBUNTU_PATH/${'$'}UBUNTU_NAME"
            fi
            mkdir -p "${'$'}UBUNTU_PATH/root"
            _write_color_bashrc "${'$'}UBUNTU_PATH/root/.bashrc"
            echo 'export ANDROID_DATA=/home/' >> "${'$'}UBUNTU_PATH/root/.bashrc"
            if [ -d "${'$'}PERSISTENT_BACKUP/root_backup" ]; then
              log_info "从备份恢复 /root"
              "${'$'}BB/cp" -r "${'$'}PERSISTENT_BACKUP/root_backup"/* "${'$'}UBUNTU_PATH/root/" || true
              "${'$'}BB/rm" -rf "${'$'}PERSISTENT_BACKUP"
            fi
          else
            VERSION=${'$'}(cat "${'$'}UBUNTU_PATH/etc/issue.net" 2>/dev/null || echo "debian")
            log_info "Debian 已安装 -> ${'$'}VERSION"
          fi
        }
    """.trimIndent()

    private fun setupFakeSysdataFn(): String = """
        setup_fake_sysdata(){
          for d in proc sys sys/.empty; do
            if [ ! -e "${'$'}UBUNTU_PATH/${'$'}{d}" ]; then
              mkdir -p "${'$'}UBUNTU_PATH/${'$'}{d}"
            fi
            chmod 700 "${'$'}UBUNTU_PATH/${'$'}{d}"
          done
          if [ ! -f "${'$'}UBUNTU_PATH/proc/.loadavg" ]; then
            echo "0.12 0.07 0.02 2/165 765" > "${'$'}UBUNTU_PATH/proc/.loadavg"
          fi
          if [ ! -f "${'$'}UBUNTU_PATH/proc/.stat" ]; then
            cat <<'MOFOX_STAT_EOF' > "${'$'}UBUNTU_PATH/proc/.stat"
        cpu  1957 0 2877 93280 262 342 254 87 0 0
        cpu0 31 0 226 12027 82 10 4 9 0 0
        cpu1 45 0 664 11144 21 263 233 12 0 0
        ctxt 140223
        btime 1680020856
        processes 772
        procs_running 2
        procs_blocked 0
        MOFOX_STAT_EOF
          fi
          if [ ! -f "${'$'}UBUNTU_PATH/proc/.uptime" ]; then
            echo "124.08 932.80" > "${'$'}UBUNTU_PATH/proc/.uptime"
          fi
          if [ ! -f "${'$'}UBUNTU_PATH/proc/.version" ]; then
            echo "Linux version 6.2.1-proot-distro (mofox@android) #1 SMP" > "${'$'}UBUNTU_PATH/proc/.version"
          fi
          if [ ! -f "${'$'}UBUNTU_PATH/proc/.vmstat" ]; then
            cat <<'MOFOX_VM_EOF' > "${'$'}UBUNTU_PATH/proc/.vmstat"
        nr_free_pages 1743136
        nr_zone_inactive_anon 179281
        nr_zone_active_anon 7183
        nr_mlock 0
        nr_bounce 0
        MOFOX_VM_EOF
          fi
          if [ ! -f "${'$'}UBUNTU_PATH/proc/.sysctl_entry_cap_last_cap" ]; then
            echo "40" > "${'$'}UBUNTU_PATH/proc/.sysctl_entry_cap_last_cap"
          fi
          if [ ! -f "${'$'}UBUNTU_PATH/proc/.sysctl_inotify_max_user_watches" ]; then
            echo "4096" > "${'$'}UBUNTU_PATH/proc/.sysctl_inotify_max_user_watches"
          fi
        }
    """.trimIndent()

    private fun loginUbuntuFn(): String = """
        login_ubuntu(){
          COMMAND_TO_EXEC="${'$'}1"
          if [ -z "${'$'}COMMAND_TO_EXEC" ]; then
            COMMAND_TO_EXEC="/bin/bash -il"
          fi
          setup_fake_sysdata
          BIND_ARGS=""
          if [ ! -r /proc/loadavg ] || [ ! -s /proc/loadavg ]; then
            BIND_ARGS="${'$'}BIND_ARGS -b ${'$'}UBUNTU_PATH/proc/.loadavg:/proc/loadavg"
          fi
          if [ ! -r /proc/stat ] || [ ! -s /proc/stat ]; then
            BIND_ARGS="${'$'}BIND_ARGS -b ${'$'}UBUNTU_PATH/proc/.stat:/proc/stat"
          fi
          if [ ! -r /proc/uptime ] || [ ! -s /proc/uptime ]; then
            BIND_ARGS="${'$'}BIND_ARGS -b ${'$'}UBUNTU_PATH/proc/.uptime:/proc/uptime"
          fi
          if [ ! -r /proc/version ] || [ ! -s /proc/version ]; then
            BIND_ARGS="${'$'}BIND_ARGS -b ${'$'}UBUNTU_PATH/proc/.version:/proc/version"
          fi
          if [ ! -r /proc/vmstat ] || [ ! -s /proc/vmstat ]; then
            BIND_ARGS="${'$'}BIND_ARGS -b ${'$'}UBUNTU_PATH/proc/.vmstat:/proc/vmstat"
          fi
          if [ ! -r /proc/sys/kernel/cap_last_cap ] || [ ! -s /proc/sys/kernel/cap_last_cap ]; then
            BIND_ARGS="${'$'}BIND_ARGS -b ${'$'}UBUNTU_PATH/proc/.sysctl_entry_cap_last_cap:/proc/sys/kernel/cap_last_cap"
          fi
          if [ ! -r /proc/sys/fs/inotify/max_user_watches ] || [ ! -s /proc/sys/fs/inotify/max_user_watches ]; then
            BIND_ARGS="${'$'}BIND_ARGS -b ${'$'}UBUNTU_PATH/proc/.sysctl_inotify_max_user_watches:/proc/sys/fs/inotify/max_user_watches"
          fi
          mkdir -p "${'$'}UBUNTU_PATH/storage/emulated" 2>/dev/null || true
          configure_ubuntu_dns
          MOFOX_LOCALE_LANG=C.UTF-8
          if [ -f "${'$'}UBUNTU_PATH/etc/default/locale" ] && \
             [ -f "${'$'}UBUNTU_PATH/usr/lib/locale/locale-archive" ] && \
             grep -q '^LANG=zh_CN.UTF-8' "${'$'}UBUNTU_PATH/etc/default/locale" 2>/dev/null; then
            MOFOX_LOCALE_LANG=zh_CN.UTF-8
          fi
          ANDROID_TZ=${'$'}(getprop persist.sys.timezone 2>/dev/null || echo "")
          if [ -z "${'$'}ANDROID_TZ" ]; then ANDROID_TZ="UTC"; fi
          exec "${'$'}BIN/libproot.so" \
            -0 \
            -r "${'$'}UBUNTU_PATH" \
            --link2symlink \
            -b /dev \
            -b /proc \
            -b /sys \
            -b /dev/pts \
            -b "${'$'}TMPDIR":"${'$'}TMPDIR" \
            -b "${'$'}TMPDIR":/dev/shm \
            -b /storage/emulated/0:/sdcard \
            -b /storage/emulated/0:/storage/emulated/0 \
            ${'$'}BIND_ARGS \
            -w /root \
            /usr/bin/env -i \
              HOME=/root \
              TERM=xterm-256color \
              LANG="${'$'}MOFOX_LOCALE_LANG" \
              LC_ALL="${'$'}MOFOX_LOCALE_LANG" \
              TZ="${'$'}ANDROID_TZ" \
              PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
              CLICOLOR_FORCE=1 \
              FORCE_COLOR=1 \
              PIP_FORCE_COLOR=1 \
              PIP_NO_INPUT=1 \
              UV_LINK_MODE=copy \
              GIT_PAGER=cat \
              COMMAND_TO_EXEC="${'$'}COMMAND_TO_EXEC" \
              /bin/bash -lc "eval \"\${'$'}COMMAND_TO_EXEC\""
        }
    """.trimIndent()

    /** 用 POSIX 单引号转义：`it's` -> `'it'\''s'`。 */
    private fun shellQuote(s: String): String {
        val escaped = s.replace("'", "'\\''")
        return "'$escaped'"
    }

    companion object {
        // Debian 13 = Trixie。
        private const val UBUNTU_CODENAME = "trixie"
    }
}

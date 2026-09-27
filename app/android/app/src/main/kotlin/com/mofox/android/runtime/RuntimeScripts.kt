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
     * bot / snowluma 长进程脚本。
     *
     * - `bot`：每个实例的 Neo-MoFox 落在 `args["repoPath"]`（通常是
     *   `/root/instances/<inst-id>/Neo-MoFox`），脚本里写实际路径。脚本文件名
     *   带上 `instanceId`，避免多实例同时启动覆盖同一份脚本。
     * - `snowluma`：全局唯一安装在 `/root/snowluma`，所有实例共用。
     *   进程 = Xvfb + fluxbox + LinuxQQ + SnowLuma(node)。
     */
    fun processScript(name: String, args: Map<String, String> = emptyMap()): File {
        val (script, suffix) = when (name) {
            "bot" -> {
                val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
                val instanceId = args["instanceId"]
                val cmd = "cd ${shellQuote(repoPath)} && export PATH=\"/root/.local/bin:${'$'}PATH\" && export UV_LINK_MODE=copy && export MOFOX_ACCEPT_STARTUP_AGREEMENTS=1 && uv run python main.py"
                cmd to (instanceId?.let { "-$it" } ?: "")
            }
            "snowluma" -> {
              val botQq = args["botQq"].orEmpty()
              val qqArgs = if (botQq.isNotBlank()) " -q ${shellQuote(botQq)}" else ""
              val cmd = """set -o pipefail || true
                export BOT_QQ=${shellQuote(botQq)}
                mkdir -p /root/snowluma/cache /tmp/snowluma-hook
                # 清理旧截图与旧日志，避免监控线程读到上次登录留下的过期画面。
                rm -f /root/snowluma/cache/screen.png /tmp/snowluma-run.log /tmp/snowluma-qq.pid /tmp/snowluma-qq.log
                # 兜底清理上次崩溃残留的显示服务
                pgrep -f 'Xvfb :1' >/dev/null 2>&1 && pkill -f 'Xvfb :1' || true
                sleep 1
                # ptrace 注入在 proot 下不可用（QQ 进程已被 proot 占为唯一 tracee，
                # 第二个 tracer 无法 attach）。改用 hook 组件自带的 LD_PRELOAD 模式，
                # 需要同时设两个开关（反汇编确认）：
                #   SNOWLUMA_HOOK_STUB_START=1  构造函数据此启动 stub 线程；
                #   SNOWLUMA_HOOK_SERVICE_MODE=in-process  stub 线程据此启动真正的
                #     服务（创建 mojo.<pid>.control.sock），缺了它组件静默不工作。
                # SnowLuma 的 PipeWatcher 发现 socket 后直接接管，全程无 ptrace。
                # 组件与 QQ 的 runtime dir 必须一致。
                HOOK_SO=/root/snowluma/app/native/snowluma-linux-arm64.so
                QQ_HOOK_ENV=""
                if [ -f "${'$'}HOOK_SO" ]; then
                  QQ_HOOK_ENV="SNOWLUMA_HOOK_STUB_START=1 SNOWLUMA_HOOK_SERVICE_MODE=in-process SNOWLUMA_HOOK_RUNTIME_DIR=/tmp/snowluma-hook LD_PRELOAD=${'$'}HOOK_SO"
                fi
                # 后台监控：截屏推送二维码变化、探测登录状态与 WebUI
                (
                  QR_EMITTED=0
                  QR_MD5=""
                  QR_LAST_EMIT=0
                  LOGIN_DONE=0
                  WEBUI_EMITTED=0
                  QQ_DEAD_REPORTED=0
                  QQ_ALIVE_REPORTED=0
                  ONLINE_WAIT_REPORTED=0
                  for i in ${'$'}(seq 1 225); do
                    sleep 4
                    if [ "${'$'}LOGIN_DONE" = "1" ]; then
                      break
                    fi
                    # QQ 启动诊断：报出存活/死亡状态（各只报一次），用于区分
                    # "QQ 崩了"和"QQ 活着但窗口没映射到虚拟屏幕"。
                    if [ -f /tmp/snowluma-qq.pid ]; then
                      QQ_PID=${'$'}(cat /tmp/snowluma-qq.pid 2>/dev/null)
                      if [ -n "${'$'}QQ_PID" ] && kill -0 "${'$'}QQ_PID" 2>/dev/null; then
                        if [ "${'$'}QQ_ALIVE_REPORTED" != "1" ]; then
                          QQ_ALIVE_REPORTED=1
                          echo "[control] LinuxQQ 进程已启动 (pid=${'$'}QQ_PID)"
                        fi
                      else
                        if [ "${'$'}QQ_DEAD_REPORTED" != "1" ]; then
                          QQ_DEAD_REPORTED=1
                          echo "[control] LinuxQQ 进程已退出 (pid=${'$'}QQ_PID)，启动日志尾部："
                          tail -n 8 /tmp/snowluma-qq.log 2>/dev/null || echo "(无启动日志)"
                        fi
                      fi
                    fi
                    # 前 15 轮 Xvfb 可能还没就绪，截屏失败直接跳过
                    SCREEN_MD5=""
                    if DISPLAY=:1 ffmpeg -y -loglevel error -f x11grab -video_size 800x600 -i :1 -frames:v 1 /root/snowluma/cache/screen.png 2>/dev/null; then
                      SCREEN_MD5=${'$'}(md5sum /root/snowluma/cache/screen.png 2>/dev/null | awk '{print ${'$'}1}')
                    else
                      [ "${'$'}i" -le 15 ] && continue
                    fi
                    if [ -n "${'$'}SCREEN_MD5" ]; then
                      NOW=${'$'}(date +%s)
                      if [ "${'$'}SCREEN_MD5" != "${'$'}QR_MD5" ] && [ ${'$'}((NOW - QR_LAST_EMIT)) -ge 4 ]; then
                        echo "MOFOX_QR_IMAGE=/root/snowluma/cache/screen.png"
                        QR_EMITTED=1
                        QR_MD5="${'$'}SCREEN_MD5"
                        QR_LAST_EMIT=${'$'}NOW
                      fi
                    fi
                    # 登录成功检测：SnowLuma OneBot http 上报在线状态
                    if curl -fsS -m 3 -H "Authorization: Bearer mofox" http://127.0.0.1:3000/get_status 2>/dev/null | grep -q '"online":true'; then
                      echo "MOFOX_LOGIN_OK=1"
                      LOGIN_DONE=1
                      break
                    fi
                    # QQ 已登录但 OneBot 还没上线时（启动约 1 分钟后），把
                    # get_status 的原始返回打出来一次，用于区分"hook 没接管"
                    # 和"HTTP 服务没起"。
                    if [ "${'$'}QQ_ALIVE_REPORTED" = "1" ] && [ "${'$'}i" -ge 15 ] && [ "${'$'}ONLINE_WAIT_REPORTED" != "1" ]; then
                      ONLINE_WAIT_REPORTED=1
                      ONLINE_BODY=${'$'}(curl -fsS -m 3 -H "Authorization: Bearer mofox" http://127.0.0.1:3000/get_status 2>/dev/null || echo "(HTTP 不可达)")
                      echo "[control] OneBot get_status: ${'$'}{ONLINE_BODY:0:200}"
                    fi
                    # WebUI 就绪后只上报一次
                    if [ "${'$'}WEBUI_EMITTED" = "0" ] && curl -fsS -m 3 http://127.0.0.1:5099/ >/dev/null 2>&1; then
                      echo "MOFOX_WEBUI_URL=http://127.0.0.1:5099/?token=${'$'}(cat /root/snowluma/secrets/webui_password 2>/dev/null)"
                      WEBUI_EMITTED=1
                    fi
                  done
                ) &
                Xvfb :1 -screen 0 800x600x24 -ac >/dev/null 2>&1 || log_warn "Xvfb 启动失败" &
                sleep 2
                DISPLAY=:1 fluxbox >/dev/null 2>&1 || log_warn "fluxbox 启动失败" &
                # 注意：直接展开成 `VAR=v cmd` 形式时，bash 会把第一个 VAR=v
                # 当成命令名（"未找到命令"），QQ 根本不会启动。必须经 env 命令
                # 传递环境变量。
                DISPLAY=:1 env ${'$'}QQ_HOOK_ENV /root/snowluma/opt/QQ/qq --no-sandbox --disable-gpu --disable-software-rasterizer --disable-gpu-compositing$qqArgs >/dev/null 2>/tmp/snowluma-qq.log &
                echo ${'$'}! > /tmp/snowluma-qq.pid
                sleep 3
                # 前台运行 SnowLuma，进程退出码即脚本退出码；pipefail 保证管道
                # 退出码等于 launcher.sh 的退出码。
                cd /root/snowluma/app && export DISPLAY=:1 SNOWLUMA_HOOK_RUNTIME_DIR=/tmp/snowluma-hook SNOWLUMA_ACCEPT_EULA=1 SNOWLUMA_ACCEPT_PRIVACY=1 SNOWLUMA_HOOK_AUTOLOAD=1 SNOWLUMA_WEBUI_BOOTSTRAP_PASSWORD="${'$'}(cat /root/snowluma/secrets/webui_password 2>/dev/null)" && ./launcher.sh 2>&1 | tee /tmp/snowluma-run.log""".trimIndent()
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
          "snowluma" -> {
            """
            _stop_snowluma_proc() {
              SIGNAL=${'$'}1
              PATTERN=${'$'}2
              PIDS=${'$'}(pgrep -f "${'$'}PATTERN" 2>/dev/null || true)
              for PID in ${'$'}PIDS; do
                [ "${'$'}PID" = "${'$'}${'$'}" ] && continue
                CMDLINE=${'$'}(tr '\0' ' ' < "/proc/${'$'}PID/cmdline" 2>/dev/null || true)
                case "${'$'}CMDLINE" in
                  *pgrep*|*stop-process-snowluma*|*login_ubuntu*|*mofox_log*|*_stop_snowluma_proc*) continue ;;
                esac
                kill -"${'$'}SIGNAL" "${'$'}PID" 2>/dev/null || true
              done
            }
            _stop_snowluma_proc QUIT '/root/snowluma/opt/QQ/qq'
            sleep 3
            _stop_snowluma_proc KILL '/root/snowluma/opt/QQ/qq'
            _stop_snowluma_proc KILL 'Xvfb'
            _stop_snowluma_proc KILL 'fluxbox'
            _stop_snowluma_proc TERM 'index.mjs'
            sleep 2
            _stop_snowluma_proc KILL 'index.mjs'
            true
            """.trimIndent()
          }
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

    /** AI 助手一次性命令脚本。命令在进入 Debian 后以指定 cwd 执行。 */
    fun assistantCommandScript(cwd: String, command: String): File {
        installer.ensureBaseDirectories()
        val file = File(installer.scriptsDir, "assistant-command.sh")
        val inner = "cd ${shellQuote(cwd)} 2>/dev/null || cd /root; exec /bin/bash -lc ${shellQuote(command)}"
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
                apt-get update -y
                DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                  python3 python3-pip python3-venv git curl ca-certificates xz-utils locales \
                  ffmpeg libgcrypt20 xvfb xdotool
                sed -i 's/^# *\(zh_CN.UTF-8 UTF-8\)/\1/' /etc/locale.gen
                sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
                locale-gen zh_CN.UTF-8 en_US.UTF-8 || true
                update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 || true
                cat > /etc/default/locale <<'MOFOX_LOCALE_EOF'
                LANG=zh_CN.UTF-8
                LC_ALL=zh_CN.UTF-8
                MOFOX_LOCALE_EOF
                log_info "安装 uv 包管理器…"
                curl -LsSf https://astral.sh/uv/install.sh | sh || true
                . /root/.local/bin/env 2>/dev/null || true
                python3 --version
                git --version
                """.trimIndent(),
            )
            "cloneRepo" -> {
                val repoUrl = args["repoUrl"] ?: "https://github.com/MoFox-Studio/Neo-MoFox.git"
                val installDir = args["installDir"] ?: "/root/instances/default"
                val repoPath = args["repoPath"] ?: "$installDir/Neo-MoFox"
                loginBody(
                    """
                    mkdir -p ${shellQuote(installDir)}
                    cd ${shellQuote(installDir)}
                    if [ -d ${shellQuote(repoPath)}/.git ]; then
                      log_info "仓库已存在，拉取最新代码…"
                      cd ${shellQuote(repoPath)} && git pull --ff-only || true
                    else
                      git clone --depth=1 ${shellQuote(repoUrl)} Neo-MoFox
                      cd ${shellQuote(repoPath)}
                    fi
                    """.trimIndent(),
                )
            }
            "syncDeps" -> {
                val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
                loginBody(
                    """
                    cd ${shellQuote(repoPath)}
                    export PATH="/root/.local/bin:${'$'}PATH"
                    export UV_LINK_MODE=copy
                    rm -rf .venv
                    if command -v uv >/dev/null 2>&1; then
                      uv sync --link-mode=copy --no-cache
                    else
                      python3 -m venv .venv
                      . .venv/bin/activate
                      pip install --no-cache-dir .
                    fi
                    """.trimIndent(),
                )
            }
            "genConfig" -> {
                val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
                loginBody(
                    """
                    cd ${shellQuote(repoPath)}
                    mkdir -p config
                    if [ ! -f config/bot_config.toml ]; then
                      python3 -m mofox.config.generate || true
                    fi
                    """.trimIndent(),
                )
            }
            "writeCore" -> writeCoreBody(args)
            "writeModel" -> writeModelBody(args)
            "writeAdapter" -> writeAdapterBody(args)
            "installWebui" -> {
                val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
                val webuiKey = args["webuiApiKey"].orEmpty()
                val mirrorId = args["mirrorId"] ?: "github"
                // 根据镜像站决定下载地址的前缀。
                // GitHub API 不支持代理（返回 403），所以 API 请求直连，
                // 只对最终的 release 资产下载 URL 加代理前缀。
                val ghProxy = when (mirrorId) {
                    "ghproxy" -> "https://ghfast.top/"
                    "ikun" -> "https://github.ikun114.top/"
                    else -> ""
                }
                loginBody(
                    """
                    set -e
                    PLUGINS_DIR=${shellQuote(repoPath)}/plugins
                    mkdir -p "${'$'}PLUGINS_DIR"
                    WEBUI_MFP="${'$'}PLUGINS_DIR/neo-mofox-webui.mfp"
                    # GitHub API 直连（代理会 403），获取最新 release 的 .mfp 资产下载地址
                    log_info "正在获取 WebUI 最新发行版（镜像: ${shellQuote(mirrorId)}）…"
                    API_URL="https://api.github.com/repos/ikun-1145141/Neo-MoFox-Webui/releases/latest"
                    DOWNLOAD_URL="${'$'}(curl -fsSL "${'$'}API_URL" | grep -o '"browser_download_url":\s*"[^"]*\.mfp"' | head -1 | sed 's/"browser_download_url":\s*"//;s/"//')"
                    if [ -z "${'$'}DOWNLOAD_URL" ]; then
                      log_error "未找到 WebUI .mfp 下载地址"
                      exit 1
                    fi
                    # 如果走镜像代理，给下载地址加前缀
                    PROXY_URL="${ghProxy}${'$'}DOWNLOAD_URL"
                    log_info "下载 WebUI: ${'$'}PROXY_URL"
                    if ! curl -fSL -o "${'$'}WEBUI_MFP" "${'$'}PROXY_URL"; then
                      log_error "WebUI 下载失败"
                      rm -f "${'$'}WEBUI_MFP"
                      exit 1
                    fi
                    log_info "WebUI 已安装到 ${'$'}WEBUI_MFP"
                    log_info "WebUI api_key=${shellQuote(webuiKey)}"
                    """.trimIndent(),
                )
            }
            "installSnowluma" -> loginBody(
                """
                set -e
                if [ ! -x /root/snowluma/opt/QQ/qq ] ||
                   [ ! -s /root/snowluma/app/index.mjs ] ||
                   [ ! -s /root/snowluma/app/launcher.sh ] ||
                  ! command -v node >/dev/null 2>&1; then
                  log_info "执行本地 SnowLuma 安装脚本…"
                  bash /usr/local/bin/snowluma-install.sh || {
                    code=${'$'}?
                    log_error "SnowLuma 安装脚本失败（退出码 ${'$'}code）"
                    exit "${'$'}code"
                  }
                else
                  log_info "SnowLuma 已安装，跳过"
                fi
                """.trimIndent(),
            )
            "verifySnowluma" -> loginBody(
                """
                [ -x /root/snowluma/opt/QQ/qq ] || {
                  log_error "SnowLuma 复查失败：QQ 主程序不存在或不可执行"
                  exit 21
                }
                [ -s /root/snowluma/app/index.mjs ] || {
                  log_error "SnowLuma 复查失败：缺少 index.mjs"
                  exit 22
                }
                command -v node >/dev/null 2>&1 || {
                  log_error "SnowLuma 复查失败：node 不可用"
                  exit 23
                }
                command -v xvfb-run >/dev/null 2>&1 || {
                  log_error "SnowLuma 复查失败：xvfb-run 不可用"
                  exit 24
                }
                command -v fluxbox >/dev/null 2>&1 || {
                  log_error "SnowLuma 复查失败：fluxbox 不可用"
                  exit 25
                }
                [ -s /root/snowluma/app/launcher.sh ] || {
                  log_error "SnowLuma 复查失败：缺少 launcher.sh"
                  exit 26
                }
                log_ok "SnowLuma 安装复查通过"
                """.trimIndent(),
            )
            "writeSnowlumaConfig" -> writeSnowlumaConfigBody(args)
            "qqQuickLogin" -> loginBody(
                """
                command -v xdotool >/dev/null 2>&1 || {
                  log_info "安装 xdotool…"
                  apt-get update -y >/dev/null 2>&1 || true
                  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xdotool >/dev/null 2>&1 || {
                    log_error "xdotool 安装失败，无法发送快捷登录"
                    exit 31
                  }
                }
                WID=${'$'}(DISPLAY=:1 xdotool search --onlyvisible --name "QQ" 2>/dev/null | tail -n 1)
                if [ -z "${'$'}WID" ]; then
                  log_error "未找到可见的 QQ 窗口"
                  exit 32
                fi
                DISPLAY=:1 xdotool windowactivate --sync "${'$'}WID" >/dev/null 2>&1 || true
                sleep 0.5
                DISPLAY=:1 xdotool key --clearmodifiers Return
                log_ok "已向 QQ 窗口发送回车（快捷登录）"
                """.trimIndent(),
            )
            "registerInstance" -> {
                val instanceName = args["instanceName"].orEmpty()
                val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
                loginBody(
                    """
                    mkdir -p /root/.mofox
                    cat > /root/.mofox/instance.toml <<'MOFOX_EOF'
                    name = "$instanceName"
                    path = "$repoPath"
                    MOFOX_EOF
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
            install_ubuntu
            change_ubuntu_source
            configure_ubuntu_dns
            setup_fake_sysdata
        """.trimIndent()
    }

    private fun writeCoreBody(args: Map<String, String>): String {
        val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
        val instanceName = args["instanceName"].orEmpty()
        val botQq = args["botQq"].orEmpty()
        val botNickname = args["botNickname"].orEmpty()
        val ownerQq = args["ownerQq"].orEmpty()
        val webuiHost = args["webuiHost"] ?: "127.0.0.1"
        val webuiPort = args["webuiPort"] ?: "8000"
        val webuiKey = args["webuiApiKey"].orEmpty()
        return loginBody(
            """
            mkdir -p ${shellQuote(repoPath)}/config
            cat > ${shellQuote(repoPath)}/config/core.toml <<'MOFOX_EOF'
            [bot]
            instance_name = "$instanceName"
            qq = "$botQq"
            nickname = "$botNickname"
            owner_qq = "$ownerQq"

            [http_router]
            enable_http_router = true
            http_router_host = "$webuiHost"
            http_router_port = $webuiPort
            api_keys = ["$webuiKey"]
            MOFOX_EOF
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
            mkdir -p ${shellQuote(repoPath)}/config
            cat > ${shellQuote(repoPath)}/config/model.toml <<'MOFOX_EOF'
            [model]
            api_key = "$apiKey"
            base_url = "$apiBaseUrl"
            MOFOX_EOF
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
            """.trimIndent(),
        )
    }

    private fun writeSnowlumaConfigBody(args: Map<String, String>): String {
        val wsPort = args["wsPort"] ?: "8095"
        return loginBody(
            """
            mkdir -p /root/snowluma/app/config
            cat > /root/snowluma/app/config/onebot.json <<'MOFOX_EOF'
            {
              "networks": {
                "httpServers": [
                  {
                    "name": "http-local",
                    "enabled": true,
                    "host": "127.0.0.1",
                    "port": 3000,
                    "path": "/",
                    "accessToken": "mofox",
                    "messageFormat": "array",
                    "reportSelfMessage": false
                  }
                ],
                "httpClients": [],
                "wsServers": [],
                "wsClients": [
                  {
                    "name": "neo-mofox-ws-client",
                    "enabled": true,
                    "url": "ws://127.0.0.1:$wsPort",
                    "role": "Universal",
                    "accessToken": "",
                    "messageFormat": "array",
                    "reportSelfMessage": false,
                    "reconnectIntervalMs": 3000
                  }
                ]
              },
              "musicSignUrl": ""
            }
            MOFOX_EOF
            cat > /root/snowluma/app/config/runtime.json <<'MOFOX_EOF2'
            { "webuiPort": 5099, "hookAutoLoad": true }
            MOFOX_EOF2

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
            mkdir -p $(dirname ${shellQuote(destPath)})
            tar cJf ${shellQuote(destPath)} $pathsArg
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
          # 将日志函数写入 rootfs，使 proot 内的 bash 也能使用 log_step / log_ok 等。
          if [ ! -f "${'$'}UBUNTU_PATH/usr/local/bin/mofox_log.sh" ]; then
            mkdir -p "${'$'}UBUNTU_PATH/usr/local/bin"
            cat > "${'$'}UBUNTU_PATH/usr/local/bin/mofox_log.sh" <<'MOFOX_LOG_EOF'
log_step(){ printf "\033[34m▶ %s\033[0m\n" "$*"; }
log_info(){ printf "\033[36m%s\033[0m\n" "$*"; }
log_ok(){   printf "\033[32m✓ %s\033[0m\n" "$*"; }
log_warn(){ printf "\033[33m⚠ %s\033[0m\n" "$*"; }
log_error(){ printf "\033[31m✗ %s\033[0m\n" "$*"; }
MOFOX_LOG_EOF
          fi
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
              /bin/bash -lc ". /usr/local/bin/mofox_log.sh 2>/dev/null; eval \"\${'$'}COMMAND_TO_EXEC\""
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

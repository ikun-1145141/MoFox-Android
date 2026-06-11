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
                val cmd = "cd ${shellQuote(repoPath)} && bash ${shellQuote("$repoPath/start.sh")}"
                cmd to (instanceId?.let { "-$it" } ?: "")
            }
            "napcat" -> {
                val cmd = "cd /root/napcat && bash /root/napcat/napcat.sh start ${'$'}BOT_QQ"
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
            "pkill -TERM -f ${shellQuote("bash ${shellQuote("$repoPath/start.sh")}")} || " +
              "pkill -TERM -f ${shellQuote(repoPath)} || true"
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
                apt-get update -y
                DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                    python3 python3-pip python3-venv git curl ca-certificates xz-utils locales
                sed -i 's/^# *\(zh_CN.UTF-8 UTF-8\)/\1/' /etc/locale.gen
                sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
                locale-gen zh_CN.UTF-8 en_US.UTF-8 || true
                update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 || true
                cat > /etc/default/locale <<'MOFOX_LOCALE_EOF'
                LANG=zh_CN.UTF-8
                LC_ALL=zh_CN.UTF-8
                MOFOX_LOCALE_EOF
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
                      echo "[runtime] repo already cloned at $repoPath, pulling latest"
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
                      pip install --no-cache-dir -r requirements.txt
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
                loginBody(
                    """
                    cd ${shellQuote(repoPath)}
                    if [ -d webui ]; then
                      cd webui && (npm install --omit=dev || true) && (npm run build || true)
                    fi
                    echo "[webui] api_key=${shellQuote(webuiKey)}"
                    """.trimIndent(),
                )
            }
            "installNapcat" -> loginBody(
                """
              apt-get update -y
              DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libgcrypt20
                mkdir -p /root/napcat-installer /root/napcat
                cd /root/napcat-installer
                if [ ! -f /root/Napcat/opt/QQ/qq ]; then
                  curl -L --fail --connect-timeout 20 --retry 3 \
                    https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh \
                    -o napcat-install.sh
                  bash napcat-install.sh --docker n --cli n --proxy 0
                else
                  echo "[napcat] existing rootless installation found at /root/Napcat"
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
                echo "[napcat] global NapCat ready"
                """.trimIndent(),
            )
            "napcatLogin" -> {
                val botQq = args["botQq"].orEmpty()
                loginBody(
                    """
                    cd /root/napcat
                    export BOT_QQ=${shellQuote(botQq)}
                    mkdir -p /root/napcat/cache
                    rm -f /root/napcat/cache/qrcode.png /tmp/napcat-login.log
                    xvfb-run -a /root/Napcat/opt/QQ/qq --no-sandbox -q "${'$'}BOT_QQ" > /tmp/napcat-login.log 2>&1 &
                    NAPCAT_PID=${'$'}!
                    QR_EMITTED=0
                    LOGIN_DONE=0
                    for i in ${'$'}(seq 1 180); do
                      sleep 1
                      if [ -s /tmp/napcat-login.log ]; then
                        tail -n 20 /tmp/napcat-login.log
                      fi
                      if [ "${'$'}QR_EMITTED" = "0" ] && { grep -q '二维码已保存到' /tmp/napcat-login.log 2>/dev/null || [ -s /root/napcat/cache/qrcode.png ]; }; then
                        echo "MOFOX_QR_IMAGE=/root/napcat/cache/qrcode.png"
                        QR_EMITTED=1
                      fi
                      if grep -q '配置加载' /tmp/napcat-login.log 2>/dev/null; then
                        echo "[napcat] 登录成功"
                        LOGIN_DONE=1
                        break
                      fi
                      if grep -q 'Login Error' /tmp/napcat-login.log 2>/dev/null; then
                        echo "[napcat] 登录失败"
                        kill "${'$'}NAPCAT_PID" 2>/dev/null || true
                        wait "${'$'}NAPCAT_PID" 2>/dev/null || true
                        exit 1
                      fi
                      if ! kill -0 "${'$'}NAPCAT_PID" 2>/dev/null; then
                        break
                      fi
                    done
                    if [ "${'$'}LOGIN_DONE" != "1" ]; then
                      echo "[napcat] 登录等待超时或 NapCat 已退出" >&2
                      kill "${'$'}NAPCAT_PID" 2>/dev/null || true
                      wait "${'$'}NAPCAT_PID" 2>/dev/null || true
                      exit 1
                    fi
                    kill "${'$'}NAPCAT_PID" 2>/dev/null || true
                    wait "${'$'}NAPCAT_PID" 2>/dev/null || true
                    """.trimIndent(),
                )
            }
            "writeNapcatConfig" -> writeNapcatConfigBody(args)
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
                    echo "[runtime] instance $instanceName registered"
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
                      echo "[runtime] deleted instance dir: $installDir"
                      ;;
                      *)
                      echo "[runtime] refusing to delete outside /root/instances: $installDir" >&2
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
            # Debian ships /etc/resolv.conf as a relative symlink to
            # ../run/systemd/resolve/stub-resolv.conf. Shell '>' follows the
            # symlink and ENOENT-fails because run/systemd/... doesn't exist
            # on host. Drop the symlink and write a plain file instead.
            "${'$'}BB/rm" -f "${'$'}UBUNTU_PATH/etc/resolv.conf"
            echo 'nameserver 8.8.8.8' > "${'$'}UBUNTU_PATH/etc/resolv.conf"
            setup_fake_sysdata
            echo "[runtime] rootfs ready at ${'$'}UBUNTU_PATH"
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
            """.trimIndent(),
        )
    }

    private fun writeModelBody(args: Map<String, String>): String {
        val repoPath = args["repoPath"] ?: "/root/Neo-MoFox"
        val apiKey = args["apiKey"].orEmpty()
        val apiBaseUrl = args["apiBaseUrl"] ?: "https://api.openai.com/v1"
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
        val channel = args["channel"] ?: "main"
        return loginBody(
            """
            mkdir -p ${shellQuote(repoPath)}/config
            cat > ${shellQuote(repoPath)}/config/adapter.toml <<'MOFOX_EOF'
            [napcat]
            ws_port = $wsPort
            channel = "$channel"
            MOFOX_EOF
            """.trimIndent(),
        )
    }

    private fun writeNapcatConfigBody(args: Map<String, String>): String {
        val wsPort = args["wsPort"] ?: "8095"
        val botQq = args["botQq"].orEmpty()
        return loginBody(
            """
            mkdir -p /root/napcat/config
            cat > /root/napcat/config/onebot11_${'$'}{BOT_QQ:-${botQq}}.json <<'MOFOX_EOF'
            {
              "network": {
                "websocketServers": [
                  {
                    "name": "mofox",
                    "enable": true,
                    "host": "127.0.0.1",
                    "port": $wsPort,
                    "messagePostFormat": "array",
                    "reportSelfMessage": false,
                    "token": ""
                  }
                ]
              },
              "musicSignUrl": "",
              "enableLocalFile2Url": false
            }
            MOFOX_EOF
            """.trimIndent(),
        )
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
            appendLine(changeUbuntuSourceFn())
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
            echo "[state] missing bin directory, force reinstall"
            NEED_INSTALL=1
          elif [ ! -f "${'$'}UBUNTU_PATH/usr/bin/env" ]; then
            echo "[state] missing /usr/bin/env, force reinstall"
            NEED_INSTALL=1
          elif [ ! -d "${'$'}UBUNTU_PATH/etc" ]; then
            echo "[state] missing etc directory, force reinstall"
            NEED_INSTALL=1
          fi

          if [ "${'$'}NEED_INSTALL" -eq 1 ] || [ -z "${'$'}(ls -A "${'$'}UBUNTU_PATH" 2>/dev/null)" ]; then
            echo "[state] ${'$'}UBUNTU_PATH not ready, reinstalling"
            PERSISTENT_BACKUP="${'$'}HOME_PATH/ubuntu_user_backup"
            if [ -d "${'$'}UBUNTU_PATH/root" ]; then
              echo "[backup] saving /root to ${'$'}PERSISTENT_BACKUP"
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
            echo "[cmd] proot --link2symlink busybox tar xJf ${'$'}HOME_PATH/${'$'}UBUNTU -> ${'$'}UBUNTU_PATH"
            echo "[tar] extracting Debian 13 rootfs (~250MB), please wait..."
            "${'$'}BIN/libproot.so" --link2symlink "${'$'}BB/tar" xJf "${'$'}HOME_PATH/${'$'}UBUNTU" -C "${'$'}UBUNTU_PATH/" > "${'$'}TAR_LOG" 2>&1 || {
              TAR_RC=${'$'}?
              echo "[error] tar failed (rc=${'$'}TAR_RC), tail of log:"
              "${'$'}BB/tail" -n 40 "${'$'}TAR_LOG" 2>/dev/null || cat "${'$'}TAR_LOG"
              exit "${'$'}TAR_RC"
            }
            echo "[tar] tar exited 0, verifying rootfs integrity"
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
              echo "[error] tar reported success but rootfs is missing:${'$'}MISSING"
              echo "[error] tar.log tail (last 60 lines):"
              "${'$'}BB/tail" -n 60 "${'$'}TAR_LOG" 2>/dev/null || cat "${'$'}TAR_LOG"
              echo "[error] top-level entries actually extracted:"
              "${'$'}BB/ls" -la "${'$'}UBUNTU_PATH" 2>/dev/null || true
              exit 1
            fi
            echo "[tar] extraction complete"
            if [ -d "${'$'}UBUNTU_PATH/${'$'}UBUNTU_NAME" ]; then
              "${'$'}BB/mv" "${'$'}UBUNTU_PATH/${'$'}UBUNTU_NAME"/* "${'$'}UBUNTU_PATH/" || true
              "${'$'}BB/rm" -rf "${'$'}UBUNTU_PATH/${'$'}UBUNTU_NAME"
            fi
            mkdir -p "${'$'}UBUNTU_PATH/root"
            echo 'export ANDROID_DATA=/home/' >> "${'$'}UBUNTU_PATH/root/.bashrc"
            if [ -d "${'$'}PERSISTENT_BACKUP/root_backup" ]; then
              echo "[restore] restoring /root from backup"
              "${'$'}BB/cp" -r "${'$'}PERSISTENT_BACKUP/root_backup"/* "${'$'}UBUNTU_PATH/root/" || true
              "${'$'}BB/rm" -rf "${'$'}PERSISTENT_BACKUP"
            fi
          else
            VERSION=${'$'}(cat "${'$'}UBUNTU_PATH/etc/issue.net" 2>/dev/null || echo "debian")
            echo "[state] Debian already installed -> ${'$'}VERSION"
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
              LANG=zh_CN.UTF-8 \
              LC_ALL=zh_CN.UTF-8 \
              TZ="${'$'}ANDROID_TZ" \
              PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
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

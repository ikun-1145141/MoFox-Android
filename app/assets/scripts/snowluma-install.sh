#!/bin/bash
# SnowLuma 本地安装脚本（非容器部署，基于官方 Linux 手动部署流程）
# 在 proot Debian rootfs 内以 root 运行：
#   1. 安装系统依赖（Xvfb/fluxbox/CJK 字体/Electron 运行库）
#   2. 安装 Node.js 24 LTS（SnowLuma lite 包不带运行时）
#   3. rootless 解压 LinuxQQ（dpkg -x，不做 NapCat 式 patch）
#   4. 下载 SnowLuma -lite tarball 并解包到 ~/snowluma/app
#   5. 冻结 QQ 静默热更新（black-hole 补丁域名）
# 修复：下载/解压失败时正确返回非 0 退出码
# 保留：代理测速选择功能
set -e

# ============ 颜色 ============
RED='\033[0;1;31;91m'
YELLOW='\033[0;1;33;93m'
GREEN='\033[0;1;32;92m'
CYAN='\033[0;1;36;96m'
BLUE='\033[0;1;34;94m'
NC='\033[0m'

# ============ 路径 ============
INSTALL_BASE_DIR="$HOME/snowluma"
QQ_BASE_PATH="$INSTALL_BASE_DIR/opt/QQ"
QQ_EXECUTABLE="$QQ_BASE_PATH/qq"
APP_DIR="$INSTALL_BASE_DIR/app"
SECRETS_DIR="$INSTALL_BASE_DIR/secrets"
WEBUI_PASSWORD_FILE="$SECRETS_DIR/webui_password"
# SnowLuma 发布仓库与版本回退
SNOWLUMA_REPO="SnowLuma/SnowLuma"
SNOWLUMA_FALLBACK_TAG="v1.14.20"
# QQ Linux 官方包归档镜像（Rodert/qq-versions），官方 CDN 403/404 时回退。
# 与 installSnowluma 幂等检查配合：目标版本跟随实际安装的版本，避免每次全量重装。
QQ_MIRROR_VERSION="3.2.32-260812"
QQ_MIRROR_RELEASE="qq-packages-20260813-1d08f1d4"
QQ_MIRROR_BASE="https://github.com/Rodert/qq-versions/releases/download/${QQ_MIRROR_RELEASE}"
# Node 24（Active LTS）中国区镜像 + 官方兜底
NODE_MAJOR="24"
NODE_MIRROR_BASE="https://registry.npmmirror.com/-/binary/node"
NODE_OFFICIAL_BASE="https://nodejs.org/dist"

# ============ 日志 ============
function log() {
    time=$(date +"%Y-%m-%d %H:%M:%S")
    message="[${time}]: $1 "
    case "$1" in
    *"失败"* | *"错误"* | *"无法连接"*)
        echo -e "${RED}${message}${NC}" >&2
        ;;
    *"成功"*)
        echo -e "${GREEN}${message}${NC}"
        ;;
    *"忽略"* | *"跳过"* | *"警告"*)
        echo -e "${YELLOW}${message}${NC}"
        ;;
    *)
        echo -e "${BLUE}${message}${NC}"
        ;;
    esac
}

# ============ 退出码守卫 ============
function fail() {
    log "$1"
    clean
    exit 1
}

# ============ 系统检测 ============
function get_system_arch() {
    system_arch=$(arch | sed s/aarch64/arm64/ | sed s/x86_64/amd64/)
    if [ "${system_arch}" = "none" ] || [ -z "${system_arch}" ]; then
        fail "无法识别的系统架构"
    fi
    log "当前系统架构: ${system_arch}"
}

function detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        package_manager="apt-get"
        package_installer="dpkg"
    elif command -v dnf &>/dev/null; then
        package_manager="dnf"
        package_installer="rpm"
    else
        fail "仅支持 apt-get/dnf"
    fi
    log "包管理器: ${package_manager} / ${package_installer}"
}

# ============ 代理测速 ============
function format_speed() {
    local speed_bps=$1
    if (( speed_bps > 1048576 )); then
        echo "$((speed_bps / 1048576)) MB/s"
    elif (( speed_bps > 1024 )); then
        echo "$((speed_bps / 1024)) KB/s"
    else
        echo "${speed_bps} B/s"
    fi
}

function network_test() {
    local parm1=${1}
    local timeout=10
    target_proxy=""

    local current_proxy_setting="${proxy_num_arg:-auto}"

    log "开始网络测试: ${parm1}... (代理设置: '${current_proxy_setting}')"

    if [ "${parm1}" == "Github" ]; then
        proxy_arr=("https://ghfast.top" "https://git.yylx.win/" "https://gh-proxy.com" "https://ghfile.geekertao.top" "https://gh-proxy.net" "https://j.1win.ggff.net" "https://ghm.078465.xyz" "https://gitproxy.127731.xyz" "https://jiashu.1win.eu.org" "https://github.tbedu.top")
        check_url="https://raw.githubusercontent.com/SnowLuma/SnowLuma/main/README.md"
    else
        proxy_arr=("https://ghfast.top" "https://git.yylx.win/" "https://gh-proxy.com" "https://ghfile.geekertao.top" "https://gh-proxy.net" "https://j.1win.ggff.net" "https://ghm.078465.xyz" "https://gitproxy.127731.xyz" "https://jiashu.1win.eu.org" "https://github.tbedu.top")
        check_url="https://raw.githubusercontent.com/SnowLuma/SnowLuma/main/README.md"
    fi

    # 手动指定代理序号 (1..N)
    if [[ "${current_proxy_setting}" =~ ^[0-9]+$ && "${current_proxy_setting}" -ge 1 && "${current_proxy_setting}" -le ${#proxy_arr[@]} ]]; then
        log "手动指定代理: ${proxy_arr[$((current_proxy_setting - 1))]}"
        target_proxy="${proxy_arr[$((current_proxy_setting - 1))]}"
    # 明确禁用代理 (0)
    elif [ "${current_proxy_setting}" == "0" ]; then
        log "代理已关闭, 将直连 ${parm1}..."
        target_proxy=""
        if [ -n "${check_url}" ]; then
            local status_and_code
            status_and_code=$(curl -k --connect-timeout ${timeout} --max-time $((timeout * 2)) -o /dev/null -s -w "%{http_code}:%{exitcode}" "${check_url}" || echo "000:1")
            local status=$(echo "${status_and_code}" | cut -d: -f1)
            local curl_exit=$(echo "${status_and_code}" | cut -d: -f2)
            if [ "${curl_exit}" -eq 0 ] && [ "${status}" -eq 200 ]; then
                log "直连 ${parm1} 测试成功。"
            else
                log "警告: 直连 ${parm1} 测试失败 (HTTP: ${status}, curl: ${curl_exit})"
            fi
        fi
    # 自动测速
    else
        log "代理设置为自动 ('${current_proxy_setting}'), 正在测速..."

        local best_proxy=""
        local best_speed=0

        # 测直连
        if [ -n "${check_url}" ]; then
            log "测速: 直连..."
            local curl_output
            curl_output=$(curl -k -L --connect-timeout ${timeout} --max-time $((timeout * 3)) -o /dev/null -s -w "%{http_code}:%{exitcode}:%{speed_download}" "${check_url}" || echo "000:1:0")
            local status=$(echo "${curl_output}" | cut -d: -f1)
            local curl_exit=$(echo "${curl_output}" | cut -d: -f2)
            local dl_speed=$(echo "${curl_output}" | cut -d: -f3 | cut -d. -f1)

            if [ "${curl_exit}" -eq 0 ] && [ "${status}" -eq 200 ]; then
                log "测速: 直连 - $(format_speed "${dl_speed}")"
                best_speed=${dl_speed}
            else
                log "直连测试失败或超时。"
            fi
        fi

        # 测各代理
        for proxy_candidate in "${proxy_arr[@]}"; do
            local test_url="${proxy_candidate}/${check_url}"
            local curl_output
            curl_output=$(curl -k -L --connect-timeout ${timeout} --max-time $((timeout * 3)) -o /dev/null -s -w "%{http_code}:%{exitcode}:%{speed_download}" "${test_url}" || echo "000:1:0")
            local status=$(echo "${curl_output}" | cut -d: -f1)
            local curl_exit=$(echo "${curl_output}" | cut -d: -f2)
            local dl_speed=$(echo "${curl_output}" | cut -d: -f3 | cut -d. -f1)

            if [ "${curl_exit}" -ne 0 ]; then
                continue
            fi

            if [ "${status}" -eq 200 ]; then
                log "测速: ${proxy_candidate} - $(format_speed "${dl_speed}")"
                if [[ ${dl_speed} -gt ${best_speed} ]]; then
                    best_speed=${dl_speed}
                    best_proxy=${proxy_candidate}
                fi
            fi
        done

        if [[ ${best_speed} -gt 0 ]]; then
            target_proxy="${best_proxy}"
            if [ -n "${best_proxy}" ]; then
                log "测试完成, 使用最快代理: ${target_proxy} ($(format_speed "${best_speed}"))"
            else
                log "测试完成, 直连最快 ($(format_speed "${best_speed}")), 不使用代理。"
            fi
        else
            log "警告: 无法找到可用代理且直连失败, 将不使用代理。"
            target_proxy=""
        fi
    fi
}

# ============ 依赖安装 ============
function install_dependency() {
    log "开始安装系统依赖..."
    detect_package_manager

    if [ "${package_manager}" = "apt-get" ]; then
        log "更新软件包列表中..."
        apt-get update -y -qq || log "警告: 软件包列表更新失败, 继续..."

        local static_pkgs="jq curl xz-utils unzip procps fontconfig fonts-noto-cjk dbus-x11 xvfb fluxbox xdotool libgbm1 libnss3"

        local pkgs_to_check=(
            "libglib2.0-0" "libatk1.0-0" "libatspi2.0-0"
            "libgtk-3-0" "libasound2" "libxshmfence1" "libxdamage1" "libdrm2" "libxkbcommon0"
        )
        local resolved_pkgs=()
        log "正在检测系统库版本 (t64)..."
        for pkg_base in "${pkgs_to_check[@]}"; do
            local t64_variant="${pkg_base}t64"
            if apt-cache show "${t64_variant}" >/dev/null 2>&1; then
                log "检测到 ${t64_variant}，将使用此版本。"
                resolved_pkgs+=("${t64_variant}")
            else
                resolved_pkgs+=("${pkg_base}")
            fi
        done

        local all_pkgs="${static_pkgs} ${resolved_pkgs[*]}"
        apt-get install -y -qq ${all_pkgs} || fail "系统依赖安装失败"
    elif [ "${package_manager}" = "dnf" ]; then
        local all_pkgs="jq curl xz unzip procps-ng fontconfig google-noto-sans-cjk-sc dbus-x11 xorg-x11-server-Xvfb fluxbox nss mesa-libgbm atk at-spi2-atk gtk3 alsa-lib libxshmfence libXdamage libdrm libxkbcommon pango cairo fontconfig dejavu-sans-fonts"
        dnf install --allowerasing -y ${all_pkgs} || fail "系统依赖安装失败"
    fi
    log "系统依赖安装成功。"
}

# ============ Node.js 安装 ============
function node_arch_suffix() {
    # node tarball 用 arm64/x64，与 system_arch(arm64/amd64) 不同
    if [ "${system_arch}" = "arm64" ]; then
        echo "arm64"
    else
        echo "x64"
    fi
}

function node_already_installed() {
    command -v node >/dev/null 2>&1 && node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)' 2>/dev/null
}

function install_node() {
    if node_already_installed; then
        log "Node.js 已安装: $(node -v)，跳过。"
        return 0
    fi

    local node_arch=$(node_arch_suffix)
    local node_version
    node_version=$(curl -fsSL --connect-timeout 10 --max-time 20 "${NODE_MIRROR_BASE}/latest-v${NODE_MAJOR}.x/" | grep -oE "node-v${NODE_MAJOR}\.[0-9]+\.[0-9]+-linux-${node_arch}\.tar\.xz" | head -1 | sed "s/-linux-${node_arch}.tar.xz//")
    if [ -z "${node_version}" ]; then
        node_version=$(curl -fsSL --connect-timeout 10 --max-time 20 "${NODE_OFFICIAL_BASE}/latest-v${NODE_MAJOR}.x/" | grep -oE "node-v${NODE_MAJOR}\.[0-9]+\.[0-9]+-linux-${node_arch}\.tar\.xz" | head -1 | sed "s/-linux-${node_arch}.tar.xz//")
    fi
    if [ -z "${node_version}" ]; then
        fail "无法获取 Node.js v${NODE_MAJOR} 最新版本号"
    fi
    log "目标 Node.js 版本: ${node_version} (${node_arch})"

    local tarball="${node_version}-linux-${node_arch}.tar.xz"
    # 已有包先做完整性校验：下载中断留下的截断包会让重试永远解压同一个坏包
    if [ -f "${tarball}" ]; then
        if xz -t "${tarball}" 2>/dev/null; then
            log "检测到完整的 Node.js 安装包, 跳过下载..."
        else
            log "警告: 已有的 Node.js 安装包不完整, 删除后重新下载..."
            rm -f "${tarball}"
        fi
    fi
    if [ ! -f "${tarball}" ]; then
        log "正在从 npmmirror 下载 Node.js..."
        if ! curl -fL --connect-timeout 10 --max-time 600 -sS --retry 2 --retry-delay 2 "${NODE_MIRROR_BASE}/latest-v${NODE_MAJOR}.x/${tarball}" -o "${tarball}.tmp"; then
            log "npmmirror 下载失败，尝试 nodejs.org..."
            curl -fL --connect-timeout 10 --max-time 600 -sS --retry 2 --retry-delay 2 "${NODE_OFFICIAL_BASE}/latest-v${NODE_MAJOR}.x/${tarball}" -o "${tarball}.tmp" || fail "Node.js 下载失败 (curl 退出码: $?)"
        fi
        # xz 整流校验通过才落位：截断包不进主文件名
        if ! xz -t "${tarball}.tmp" 2>/dev/null; then
            rm -f "${tarball}.tmp"
            fail "Node.js 安装包下载不完整 (xz 校验失败)，请点重试重新下载"
        fi
        mv "${tarball}.tmp" "${tarball}"
    fi

    log "正在解压 Node.js 到 /opt/node ..."
    mkdir -p /opt/node
    tar xJf "${tarball}" -C /opt/node --strip-components=1 || {
        rm -f "${tarball}"
        fail "Node.js 解压失败 (安装包已删除, 重试将重新下载)"
    }
    rm -f "${tarball}"

    ln -sf /opt/node/bin/node /usr/local/bin/node
    ln -sf /opt/node/bin/npm /usr/local/bin/npm 2>/dev/null || true
    ln -sf /opt/node/bin/npx /usr/local/bin/npx 2>/dev/null || true

    # ptrace 注入需要 cap_sys_ptrace；proot 下可能因文件系统不支持而失败，
    # 此时退化为同 uid ptrace（取决于内核 yama 配置），故仅告警不失败。
    local real_node
    real_node=$(readlink -f "$(command -v node)")
    if command -v setcap >/dev/null 2>&1; then
        if setcap cap_sys_ptrace=ep "${real_node}" 2>/dev/null; then
            log "已授予 node cap_sys_ptrace: ${real_node}"
        else
            log "警告: setcap 失败（文件系统可能不支持 xattr），将依赖同 uid ptrace，部分设备上 SnowLuma 注入可能不可用。"
        fi
    fi

    log "Node.js 安装完成: $(node -v)"
}

# ============ SnowLuma 下载/解压 ============
function create_tmp_folder() {
    if [ -d "./SnowLuma" ] && [ "$(ls -A ./SnowLuma 2>/dev/null)" ]; then
        fail "文件夹已存在且不为空(./SnowLuma)，请重命名后重新执行"
    fi
    mkdir -p ./SnowLuma || fail "无法创建临时目录 ./SnowLuma"
}

function clean() {
    rm -rf ./SnowLuma 2>/dev/null || true
    rm -f ./snowluma.tar.gz 2>/dev/null || true
    rm -f ./QQ.deb ./QQ.rpm 2>/dev/null || true
}

function fetch_snowluma_release() {
    # GitHub API 直连（代理会 403），只解析 latest release 的 tag 与 lite tarball 资产名。
    # 失败时回退到硬编码 pin 版本。
    local api_url="https://api.github.com/repos/${SNOWLUMA_REPO}/releases/latest"
    local api_file="/tmp/snowluma_release.json"
    snowluma_tag="${SNOWLUMA_FALLBACK_TAG}"
    snowluma_asset=""
    if curl -fsSL --connect-timeout 10 --max-time 20 "${api_url}" -o "${api_file}"; then
        local tag
        tag=$(grep -o '"tag_name": *"[^"]*"' "${api_file}" | head -1 | sed 's/.*: *"//;s/"$//')
        if [ -n "${tag}" ]; then
            local asset
            asset=$(grep -o '"browser_download_url":\s*"[^"]*-linux-'"${system_arch}"'-lite\.tar\.gz"' "${api_file}" | head -1 | sed 's/.*: *"//;s/"$//')
            if [ -n "${asset}" ]; then
                snowluma_tag="${tag}"
                snowluma_asset="${asset}"
                log "SnowLuma 最新版本: ${snowluma_tag}"
            fi
        fi
    else
        log "警告: 无法访问 GitHub API, 将使用回退版本 ${SNOWLUMA_FALLBACK_TAG}。"
    fi
    rm -f "${api_file}"

    if [ -z "${snowluma_asset}" ]; then
        snowluma_asset="https://github.com/${SNOWLUMA_REPO}/releases/download/${SNOWLUMA_FALLBACK_TAG}/SnowLuma-${SNOWLUMA_FALLBACK_TAG}-linux-${system_arch}-lite.tar.gz"
        log "使用回退下载地址: ${snowluma_asset}"
    fi
}

function download_snowluma() {
    create_tmp_folder
    local default_file="snowluma.tar.gz"

    if [ -f "${default_file}" ]; then
        log "检测到已下载 SnowLuma 安装包, 跳过下载..."
    else
        fetch_snowluma_release
        network_test "Github"
        local snowluma_download_url="${target_proxy:+${target_proxy}/}${snowluma_asset}"

        log "开始下载 SnowLuma 安装包..."
        # -f: HTTP 错误时返回非 0，避免把错误页存成安装包
        if ! curl -kfL -sS --retry 2 --retry-delay 2 "${snowluma_download_url}" -o "${default_file}"; then
            log "经代理下载失败, 尝试直连 GitHub..."
            curl -kfL -sS --retry 2 --retry-delay 2 "${snowluma_asset}" -o "${default_file}" || fail "SnowLuma 安装包下载失败 (curl 退出码: $?)，请检查网络或代理设置"
        fi

        if [ ! -f "${default_file}" ]; then
            fail "文件下载失败, 未找到下载文件"
        fi
        log "${default_file} 下载成功。"
    fi

    log "正在验证 ${default_file}..."
    tar tzf "${default_file}" >/dev/null 2>&1 || {
        rm -f "${default_file}"
        fail "文件验证失败, 压缩包可能损坏 (已删除, 重试将重新下载)"
    }

    log "正在解压 ${default_file}..."
    tar xzf "${default_file}" -C ./SnowLuma || fail "SnowLuma 解压失败"
    [ -s "./SnowLuma/index.mjs" ] || fail "SnowLuma 压缩包内缺少 index.mjs"
    log "SnowLuma 解压完成。"
}

# ============ QQ 安装 ============
function get_qq_target_version() {
    linuxqq_target_version="${QQ_MIRROR_VERSION}"
}

# 从腾讯官方 linuxConfig.js 动态获取最新 QQ Linux 下载地址，失败时走归档镜像。
# 官方配置：https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/linuxConfig.js
function fetch_qq_download_urls() {
    local config_url="https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/linuxConfig.js"
    local config_file="/tmp/linuxConfig.js"
    log "正在从官方获取最新 QQ Linux 下载地址…"
    if ! curl -k -s -L --connect-timeout 10 --max-time 20 "${config_url}" -o "${config_file}"; then
        log "警告: 无法获取官方配置, 将使用硬编码的回退地址。"
        return 1
    fi

    # 从 JS 里提取 deb/rpm 链接（格式: "deb":"https://..."）
    local x64_deb x64_rpm arm_deb arm_rpm version
    x64_deb=$(grep -o '"deb":"[^"]*amd64[^"]*"' "${config_file}" | head -1 | sed 's/"deb":"//;s/"$//')
    arm_deb=$(grep -o '"deb":"[^"]*arm64[^"]*"' "${config_file}" | head -1 | sed 's/"deb":"//;s/"$//')
    x64_rpm=$(grep -o '"rpm":"[^"]*x86_64[^"]*"' "${config_file}" | head -1 | sed 's/"rpm":"//;s/"$//')
    arm_rpm=$(grep -o '"rpm":"[^"]*aarch64[^"]*"' "${config_file}" | head -1 | sed 's/"rpm":"//;s/"$//')
    version=$(grep -o '"version":"[^"]*"' "${config_file}" | head -1 | sed 's/"version":"//;s/"$//')

    rm -f "${config_file}"

    if [ -n "${version}" ]; then
        linuxqq_target_version="${version}"
        log "官方最新 QQ Linux 版本: ${version}"
    fi

    QQ_URL_X64_DEB="${x64_deb}"
    QQ_URL_X64_RPM="${x64_rpm}"
    QQ_URL_ARM_DEB="${arm_deb}"
    QQ_URL_ARM_RPM="${arm_rpm}"

    if [ -z "${QQ_URL_X64_DEB}" ] && [ -z "${QQ_URL_ARM_DEB}" ]; then
        log "警告: 未能从官方配置解析下载地址, 将尝试归档镜像。"
        return 1
    fi
    log "成功获取官方下载地址。"
    return 0
}

# 归档镜像（Rodert/qq-versions）里对应架构/包格式的 QQ 下载地址。
function qq_mirror_url() {
    local installer="$1"
    case "${system_arch}" in
        arm64)
            if [ "${installer}" = "rpm" ]; then
                echo "${QQ_MIRROR_BASE}/QQ_3.2.32_260812_aarch64_01.rpm"
            else
                echo "${QQ_MIRROR_BASE}/QQ_3.2.32_260812_arm64_01.deb"
            fi
            ;;
        amd64)
            if [ "${installer}" = "rpm" ]; then
                echo "${QQ_MIRROR_BASE}/QQ_3.2.32_260812_x86_64_01.rpm"
            else
                echo "${QQ_MIRROR_BASE}/QQ_3.2.32_260812_amd64_01.deb"
            fi
            ;;
    esac
}

# 校验 QQ 安装包完整性：真实包 >100MB，且带有对应格式的魔数。
# 官方 CDN 不可用时可能返回错误页（非空、curl 退出码仍为 0），必须拦截。
function is_valid_qq_package() {
    local f="$1"
    [ -f "$f" ] || return 1
    local size
    size=$(stat -c %s "$f" 2>/dev/null || echo 0)
    [ "${size}" -gt 100000000 ] || return 1
    if [ "${package_installer}" = "dpkg" ]; then
        head -c 8 "$f" 2>/dev/null | grep -q '!<arch>' || return 1
    else
        # RPM 魔数: ED AB EE DB
        [ "$(od -An -tx1 -N4 "$f" 2>/dev/null | tr -d ' \n')" = "edabeedb" ] || return 1
    fi
    return 0
}

function compare_linuxqq_versions() {
    local ver1="${1}"
    local ver2="${2}"
    IFS='.-' read -r -a ver1_parts <<<"${ver1}"
    IFS='.-' read -r -a ver2_parts <<<"${ver2}"
    local length=${#ver1_parts[@]}
    if [ ${#ver2_parts[@]} -lt $length ]; then
        length=${#ver2_parts[@]}
    fi
    force="n"
    for ((i = 0; i < length; i++)); do
        if ((ver1_parts[i] > ver2_parts[i])); then
            force="n"
            return
        elif ((ver1_parts[i] < ver2_parts[i])); then
            force="y"
            return
        fi
    done
    if [ ${#ver1_parts[@]} -gt ${#ver2_parts[@]} ]; then
        force="n"
    elif [ ${#ver1_parts[@]} -lt ${#ver2_parts[@]} ]; then
        force="y"
    else
        force="n"
    fi
}

function install_linuxqq_rootless() {
    log "开始安装 LinuxQQ 到 ${INSTALL_BASE_DIR}..."

    # 先尝试从官方动态获取下载地址，失败则只走归档镜像
    QQ_URL_X64_DEB=""
    QQ_URL_X64_RPM=""
    QQ_URL_ARM_DEB=""
    QQ_URL_ARM_RPM=""
    fetch_qq_download_urls || true    local qq_download_url=""
    local qq_package_file=""

    if [ "${system_arch}" = "amd64" ]; then
        if [ "${package_installer}" = "rpm" ]; then
            qq_download_url="${QQ_URL_X64_RPM}"
            qq_package_file="QQ.rpm"
        else
            qq_download_url="${QQ_URL_X64_DEB}"
            qq_package_file="QQ.deb"
        fi
    elif [ "${system_arch}" = "arm64" ]; then
        if [ "${package_installer}" = "rpm" ]; then
            qq_download_url="${QQ_URL_ARM_RPM}"
            qq_package_file="QQ.rpm"
        else
            qq_download_url="${QQ_URL_ARM_DEB}"
            qq_package_file="QQ.deb"
        fi
    fi

    if [ -z "${qq_download_url}" ] && [ -z "$(qq_mirror_url "${package_installer}")" ]; then
        fail "获取QQ下载链接失败, 架构不支持"
    fi

    # 镜像地址走代理测速选出的最快前缀（download_snowluma 已测过时直接复用）
    if [ -z "${target_proxy:-}" ]; then
        network_test "Github"
    fi
    local mirror_url=""
    local mirror_entry=""
    mirror_url=$(qq_mirror_url "${package_installer}")
    if [ -n "${mirror_url}" ]; then
        mirror_entry="${target_proxy:+${target_proxy}/}${mirror_url}"
    fi

    local candidates=()
    [ -n "${qq_download_url}" ] && candidates+=("${qq_download_url}")
    [ -n "${mirror_entry}" ] && candidates+=("${mirror_entry}")
    # 代理直连兜底：代理前缀失效时直接试原站（国内可能可达，代价一次失败重试）
    if [ -n "${target_proxy}" ] && [ -n "${mirror_url}" ]; then
        candidates+=("${mirror_url}")
    fi

    mkdir -p "${INSTALL_BASE_DIR}" || fail "无法创建安装目录"

    # 下载→校验→解压→验证主程序，全部通过才算来源可用；任一环节失败换下一个来源。
    # 解压必须纳入循环：截断/损坏的包可能通过魔数+大小校验，只有完整解压出
    # 可执行的 QQ 主程序才能证明安装包真的可用。
    rm -f "${qq_package_file}"
    local url downloaded="no" used_mirror="no" extract_err=""
    for url in "${candidates[@]}"; do
        log "QQ下载链接: ${url}"
        # -f: HTTP 错误时返回非 0，避免把错误页存成安装包
        if ! curl -kfL -sS --retry 2 --retry-delay 2 "${url}" -o "${qq_package_file}"; then
            log "警告: 下载失败, 尝试下一个来源…"
            rm -f "${qq_package_file}"
            continue
        fi
        if ! is_valid_qq_package "${qq_package_file}"; then
            log "警告: 文件校验不通过 (实际 $(stat -c %s "${qq_package_file}" 2>/dev/null || echo 0) 字节), 尝试下一个来源…"
            rm -f "${qq_package_file}"
            continue
        fi
        local pkg_sha=""
        command -v sha256sum >/dev/null 2>&1 && pkg_sha=$(sha256sum "${qq_package_file}" 2>/dev/null | cut -d' ' -f1) || pkg_sha=""
        log "QQ 安装包下载成功 ($(stat -c %s "${qq_package_file}") 字节, sha256: ${pkg_sha:-不可用})。"

        rm -rf "${INSTALL_BASE_DIR}/opt"
        log "正在解压 QQ 文件..."
        # 注意 set -e：这里故意让解压失败不中断，把输出记下来换下一个来源
        if [ "${package_installer}" = "dpkg" ]; then
            extract_err=$(dpkg -x "./${qq_package_file}" "${INSTALL_BASE_DIR}" 2>&1) || true
        else
            extract_err=$(rpm2cpio "${PWD}/${qq_package_file}" | (cd "${INSTALL_BASE_DIR}" && cpio -idmv) 2>&1) || true
        fi
        if [ -x "${QQ_EXECUTABLE}" ]; then
            downloaded="yes"
            [ "${url}" = "${mirror_entry}" ] && used_mirror="yes"
            break
        fi
        log "错误: 解压后未找到可用的 QQ 主程序 (${QQ_EXECUTABLE})。"
        [ -n "${extract_err}" ] && log "解压工具输出: ${extract_err}"
        log "警告: 该来源安装包损坏, 尝试下一个来源…"
        rm -rf "${INSTALL_BASE_DIR}/opt"
        rm -f "${qq_package_file}"
    done
    if [ "${downloaded}" != "yes" ]; then
        fail "QQ 安装包下载/解压失败：所有来源均不可用，请检查网络或代理设置"
    fi

    # 记录实际安装的版本来源：官方 CDN 与归档镜像版本可能不同，
    # 目标版本跟随实际安装结果，避免下次全量安装时被反复判定"需要更新"。
    if [ "${used_mirror}" = "yes" ]; then
        echo "${QQ_MIRROR_VERSION}" > "${INSTALL_BASE_DIR}/.qq_source_version"
    else
        rm -f "${INSTALL_BASE_DIR}/.qq_source_version"
    fi

    rm -f "${qq_package_file}"
    log "LinuxQQ 安装完成。"
}

function check_linuxqq() {
    get_qq_target_version

    # 上次安装若走了归档镜像（版本低于官方最新），目标版本跟随实际安装的
    # 版本，否则下次运行会因官方版本号更高而误判"需要更新"并反复重装。
    if [ -f "${INSTALL_BASE_DIR}/.qq_source_version" ]; then
        linuxqq_target_version=$(cat "${INSTALL_BASE_DIR}/.qq_source_version" 2>/dev/null || echo "${linuxqq_target_version}")
        log "检测到上次安装使用了归档镜像, 目标版本: ${linuxqq_target_version}"
    fi

    local qq_installed=false
    # 同时要求 package.json 和可执行的 qq 主程序都在才视为已安装，
    # 防止上次解压失败留下的残缺目录被误判成"已安装且版本满足"。
    if [ -f "${QQ_BASE_PATH}/resources/app/package.json" ] && [ -x "${QQ_EXECUTABLE}" ]; then
        qq_installed=true
        linuxqq_installed_version=$(jq -r '.version' "${QQ_BASE_PATH}/resources/app/package.json" 2>/dev/null || echo "")
        log "检测到已安装的 QQ, 版本: ${linuxqq_installed_version}"
        compare_linuxqq_versions "${linuxqq_installed_version}" "${linuxqq_target_version}"
    else
        log "未检测到已安装的 QQ。"
        force="y"
    fi

    if [ "${force}" = "y" ]; then
        log "将执行全新安装或强制重装..."
        install_linuxqq_rootless
    else
        log "QQ 版本已满足要求, 无需更新。"
    fi
}

# ============ SnowLuma 安装 ============
function freeze_qq_hot_update() {
    # QQ 静默热更新会替换 native 模块，导致 SnowLuma hook 版本错位。
    if ! grep -q "qqpatch.gtimg.cn" /etc/hosts 2>/dev/null; then
        echo "0.0.0.0 qqpatch.gtimg.cn" >> /etc/hosts
        log "已冻结 QQ 静默热更新 (qqpatch.gtimg.cn -> 0.0.0.0)。"
    else
        log "QQ 热更新已冻结，跳过。"
    fi
}

function ensure_webui_password() {
    mkdir -p "${SECRETS_DIR}"
    if [ ! -s "${WEBUI_PASSWORD_FILE}" ]; then
        # 16 字节随机十六进制（32 字符），满足 WebUI bootstrap 密码长度要求
        openssl rand -hex 16 > "${WEBUI_PASSWORD_FILE}" 2>/dev/null \
            || echo "$(date +%s%N | sha256sum | cut -c1-32)" > "${WEBUI_PASSWORD_FILE}"
        chmod 600 "${WEBUI_PASSWORD_FILE}"
        log "已生成 SnowLuma WebUI 密码。"
    else
        log "SnowLuma WebUI 密码已存在，保留。"
    fi
}

function install_snowluma_app() {
    local app_config_backup="/tmp/snowluma_config_backup_$(date +%s)"
    local backup_created=false

    if [ -d "${APP_DIR}/config" ]; then
        log "检测到现有 SnowLuma 配置, 准备备份..."
        if mkdir -p "${app_config_backup}" && cp -a "${APP_DIR}/config/." "${app_config_backup}/"; then
            log "SnowLuma 配置备份成功到 ${app_config_backup}"
            backup_created=true
        else
            log "警告: SnowLuma 配置备份失败。"
        fi
    fi

    if [ -d "${APP_DIR}" ]; then
        log "正在移除旧的 SnowLuma 目录: ${APP_DIR}"
        rm -rf "${APP_DIR}"
    fi

    mkdir -p "${APP_DIR}"
    log "正在移动 SnowLuma 文件..."
    cp -r -f ./SnowLuma/* "${APP_DIR}/" || fail "SnowLuma 文件移动失败"

    if [ "${backup_created}" = true ]; then
        log "准备恢复 SnowLuma 配置..."
        if mkdir -p "${APP_DIR}/config" && cp -a "${app_config_backup}/." "${APP_DIR}/config/"; then
            log "SnowLuma 配置恢复成功"
        else
            log "警告: SnowLuma 配置恢复失败。"
        fi
        rm -rf "${app_config_backup}"
    fi

    log "SnowLuma 安装完成: ${APP_DIR}"
}

# ============ 主流程 ============
proxy_num_arg="${proxy_num_arg:-auto}"

log "=== SnowLuma 本地安装脚本启动 ==="
log "安装目录: ${INSTALL_BASE_DIR}"

get_system_arch
install_dependency
install_node
download_snowluma
check_linuxqq
install_snowluma_app
freeze_qq_hot_update
ensure_webui_password
clean

log "=== SnowLuma 安装全部完成 ==="

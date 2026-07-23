#!/bin/bash
# NapCat 本地安装脚本（精简版，基于 NapCat-Installer）
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
INSTALL_BASE_DIR="$HOME/Napcat"
QQ_BASE_PATH="$INSTALL_BASE_DIR/opt/QQ"
TARGET_FOLDER="$QQ_BASE_PATH/resources/app/app_launcher"
QQ_EXECUTABLE="$QQ_BASE_PATH/qq"
QQ_PACKAGE_JSON_PATH="$QQ_BASE_PATH/resources/app/package.json"

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
        check_url="https://raw.githubusercontent.com/NapNeko/NapCatQQ/main/package.json"
    else
        proxy_arr=("https://ghfast.top" "https://git.yylx.win/" "https://gh-proxy.com" "https://ghfile.geekertao.top" "https://gh-proxy.net" "https://j.1win.ggff.net" "https://ghm.078465.xyz" "https://gitproxy.127731.xyz" "https://jiashu.1win.eu.org" "https://github.tbedu.top")
        check_url="https://raw.githubusercontent.com/NapNeko/NapCatQQ/main/package.json"
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

        local static_pkgs="zip unzip jq curl xvfb screen xauth procps rpm2cpio cpio libnss3 libgbm1"

        local pkgs_to_check=(
            "libglib2.0-0" "libatk1.0-0" "libatspi2.0-0"
            "libgtk-3-0" "libasound2"
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
        local all_pkgs="zip unzip jq curl screen procps-ng cpio nss mesa-libgbm atk at-spi2-atk gtk3 alsa-lib pango cairo libdrm libXcursor libXrandr libXdamage libXcomposite libXfixes libXrender libXi libXtst libXScrnSaver cups-libs libxkbcommon libX11-xcb mesa-dri-drivers mesa-libEGL mesa-libGL xcb-util xcb-util-image xcb-util-wm xcb-util-keysyms xcb-util-renderutil fontconfig dejavu-sans-fonts xorg-x11-server-Xvfb"
        dnf install --allowerasing -y ${all_pkgs} || fail "系统依赖安装失败"
    fi
    log "系统依赖安装成功。"
}

# ============ NapCat 下载/解压 ============
function create_tmp_folder() {
    if [ -d "./NapCat" ] && [ "$(ls -A ./NapCat 2>/dev/null)" ]; then
        fail "文件夹已存在且不为空(./NapCat)，请重命名后重新执行"
    fi
    mkdir -p ./NapCat || fail "无法创建临时目录 ./NapCat"
}

function clean() {
    rm -rf ./NapCat 2>/dev/null || true
    rm -rf ./NapCat.Shell.zip 2>/dev/null || true
    rm -f ./QQ.deb ./QQ.rpm 2>/dev/null || true
    if [ -d "${TARGET_FOLDER}/napcat.packet" ]; then
        rm -rf "${TARGET_FOLDER}/napcat.packet" 2>/dev/null || true
    fi
}

function download_napcat() {
    create_tmp_folder
    local default_file="NapCat.Shell.zip"

    if [ -f "${default_file}" ]; then
        log "检测到已下载 NapCat 安装包, 跳过下载..."
    else
        log "开始下载 NapCat 安装包..."
        network_test "Github"
        local napcat_download_url="${target_proxy:+${target_proxy}/}https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"

        # 关键修复：检查 curl 退出码
        curl -k -L -# "${napcat_download_url}" -o "${default_file}" || fail "NapCat 安装包下载失败 (curl 退出码: $?)，请检查网络或代理设置"

        if [ ! -f "${default_file}" ]; then
            local ext_file=$(basename "${napcat_download_url}")
            if [ -f "${ext_file}" ]; then
                mv "${ext_file}" "${default_file}" || fail "文件更名失败"
                log "${default_file} 成功重命名。"
            else
                fail "文件下载失败, 未找到下载文件"
            fi
        fi
        log "${default_file} 下载成功。"
    fi

    log "正在验证 ${default_file}..."
    unzip -t "${default_file}" >/dev/null 2>&1 || fail "文件验证失败, 压缩包可能损坏"

    log "正在解压 ${default_file}..."
    unzip -q -o -d ./NapCat "${default_file}" || fail "文件解压失败"
    log "NapCat 解压完成。"
}

# ============ QQ 安装 ============
function get_qq_target_version() {
    linuxqq_target_version="3.2.31-260710"
}

# 从腾讯官方 linuxConfig.js 动态获取最新 QQ Linux 下载地址，失败时回退到硬编码版本。
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
        log "警告: 未能从官方配置解析下载地址, 将使用硬编码的回退地址。"
        return 1
    fi
    log "成功获取官方下载地址。"
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
    get_system_arch
    log "开始安装 LinuxQQ 到 ${INSTALL_BASE_DIR}..."

    # 先尝试从官方动态获取下载地址，失败则用硬编码回退
    QQ_URL_X64_DEB=""
    QQ_URL_X64_RPM=""
    QQ_URL_ARM_DEB=""
    QQ_URL_ARM_RPM=""
    fetch_qq_download_urls || true

    # 硬编码回退地址（版本 3.2.31-260710, 2026-07-20 发布）
    if [ -z "${QQ_URL_X64_DEB}" ]; then
        QQ_URL_X64_DEB="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/release/c390e792/QQ_3.2.31_260710_amd64_01.deb"
        QQ_URL_X64_RPM="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/release/c390e792/QQ_3.2.31_260710_x86_64_01.rpm"
    fi
    if [ -z "${QQ_URL_ARM_DEB}" ]; then
        QQ_URL_ARM_DEB="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/release/c390e792/QQ_3.2.31_260710_arm64_01.deb"
        QQ_URL_ARM_RPM="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/release/c390e792/QQ_3.2.31_260710_aarch64_01.rpm"
    fi

    local qq_download_url=""
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

    if [ -z "${qq_download_url}" ]; then
        fail "获取QQ下载链接失败, 架构不支持"
    fi

    if ! [ -f "${qq_package_file}" ]; then
        log "QQ下载链接: ${qq_download_url}"
        # 关键修复：检查 curl 退出码
        curl -k -L -# "${qq_download_url}" -o "${qq_package_file}" || fail "QQ 安装包下载失败 (curl 退出码: $?)"
    else
        log "检测到当前目录下存在 QQ 安装包, 将使用本地安装包。"
    fi

    log "正在创建安装目录: ${INSTALL_BASE_DIR}"
    mkdir -p "${INSTALL_BASE_DIR}" || fail "无法创建安装目录"

    log "正在解压 QQ 文件..."
    if [ "${package_installer}" = "dpkg" ]; then
        dpkg -x ./${qq_package_file} ${INSTALL_BASE_DIR} || fail "解压 QQ (.deb) 失败"
    elif [ "${package_installer}" = "rpm" ]; then
        rpm2cpio "${PWD}/${qq_package_file}" | (cd "${INSTALL_BASE_DIR}" && cpio -idmv) || fail "解压 QQ (.rpm) 失败"
    fi

    rm -f "${qq_package_file}"
    update_linuxqq_config "${linuxqq_target_version}"
    log "LinuxQQ 安装完成。"
}

function update_linuxqq_config() {
    log "正在更新用户 QQ 配置..."
    local target_ver="${1}"
    local build_id="${target_ver##*-}"
    local user_config_dir="$HOME/.config/QQ/versions"
    local user_config_file="${user_config_dir}/config.json"

    if [ -d "${user_config_dir}" ] && [ -f "${user_config_file}" ]; then
        log "正在修改 ${user_config_file}..."
        jq --arg targetVer "${target_ver}" --arg buildId "${build_id}" \
            '.baseVersion = $targetVer | .curVersion = $targetVer | .buildId = $buildId' "${user_config_file}" >"${user_config_file}.tmp" &&
            mv "${user_config_file}.tmp" "${user_config_file}" || log "警告: QQ配置更新失败"
    else
        log "未找到用户配置文件, QQ 首次启动时会自动创建。"
    fi
}

function check_linuxqq() {
    get_qq_target_version
    local napcat_config_path="${TARGET_FOLDER}/napcat/config"
    local backup_path="/tmp/napcat_config_backup_$(date +%s)"

    if [[ -z "${linuxqq_target_version}" || "${linuxqq_target_version}" == "null" ]]; then
        fail "无法获取目标 QQ 版本"
    fi

    log "目标 LinuxQQ 版本: ${linuxqq_target_version}"

    local qq_installed=false
    if [ -f "${QQ_PACKAGE_JSON_PATH}" ]; then
        qq_installed=true
        linuxqq_installed_version=$(jq -r '.version' "${QQ_PACKAGE_JSON_PATH}")
        log "检测到已安装的 QQ, 版本: ${linuxqq_installed_version}"
        compare_linuxqq_versions "${linuxqq_installed_version}" "${linuxqq_target_version}"
    else
        log "未检测到已安装的 QQ。"
        force="y"
    fi

    if [ "${force}" = "y" ]; then
        log "将执行全新安装或强制重装..."
        local backup_created=false

        if [ "${qq_installed}" = true ] && [ -d "${napcat_config_path}" ]; then
            log "检测到现有 Napcat 配置, 准备备份..."
            if mkdir -p "${backup_path}" && cp -a "${napcat_config_path}/." "${backup_path}/"; then
                log "Napcat 配置备份成功到 ${backup_path}"
                backup_created=true
            else
                log "警告: Napcat 配置备份失败。"
            fi
        fi

        if [ -d "${INSTALL_BASE_DIR}" ]; then
            log "正在移除旧的安装目录: ${INSTALL_BASE_DIR}"
            rm -rf "${INSTALL_BASE_DIR}"
        fi

        install_linuxqq_rootless

        if [ "${backup_created}" = true ]; then
            log "准备恢复 Napcat 配置..."
            if mkdir -p "${napcat_config_path}" && cp -a "${backup_path}/." "${napcat_config_path}/"; then
                log "Napcat 配置恢复成功"
            else
                log "警告: Napcat 配置恢复失败。"
            fi
            rm -rf "${backup_path}"
        fi
    else
        log "QQ 版本已满足要求, 无需更新。"
        update_linuxqq_config "${linuxqq_installed_version}"
    fi
}

# ============ NapCat 注入 ============
function install_napcat() {
    if [ ! -d "${TARGET_FOLDER}/napcat" ]; then
        mkdir -p "${TARGET_FOLDER}/napcat/" || fail "无法创建 napcat 目录"
    fi

    log "正在移动 NapCat 文件..."
    cp -r -f ./NapCat/* "${TARGET_FOLDER}/napcat/" || fail "NapCat 文件移动失败"
    chmod -R +x "${TARGET_FOLDER}/napcat/"

    log "正在修补文件..."
    echo "(async () => {await import('file:///${TARGET_FOLDER}/napcat/napcat.mjs');})();" > "${QQ_BASE_PATH}/resources/app/loadNapCat.js" || fail "loadNapCat.js 文件写入失败"
    log "修补文件成功"

    log "正在修改 QQ 启动配置..."
    if jq '.main = "./loadNapCat.js"' "${QQ_PACKAGE_JSON_PATH}" >./package.json.tmp; then
        mv ./package.json.tmp "${QQ_PACKAGE_JSON_PATH}"
        log "修改 QQ 启动配置成功"
    else
        fail "修改 QQ 启动配置失败"
    fi

    clean
    log "NapCat 安装完成。"
}

# ============ 主流程 ============
proxy_num_arg="${proxy_num_arg:-auto}"

log "=== NapCat 本地安装脚本启动 ==="
log "安装目录: ${INSTALL_BASE_DIR}"

install_dependency
download_napcat
check_linuxqq
install_napcat

log "=== NapCat 安装全部完成 ==="
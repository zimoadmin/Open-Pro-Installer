#!/bin/sh

# ============================================================
# Open-Pro-Installer
# iStoreOS / Argon Theme Installer
#
# 功能：
# 1. 自动检测设备
# 2. 自动检测 CPU
# 3. 自动检测 opkg
# 4. 不添加第三方 opkg Feed
# 5. 不请求 Packages.gz
# 6. 直接下载 Argon IPK
# 7. 隐藏 wget/opkg 输出
# 8. 单行动态进度条
# 9. 失败时显示详细日志
# 10. 自动设置 Argon 默认主题
# 11. 自动清理临时文件
#
# BusyBox / OpenWrt Compatible
# ============================================================


# ============================================================
# 颜色
# ============================================================

GREEN="\033[32m"
BLUE="\033[34m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"


# ============================================================
# 基础配置
# ============================================================

THEME_TMP="/tmp/openpro-theme"
THEME_LOG="/tmp/openpro-theme.log"

ARGON_BASE="https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/theme"

ARGON_THEME_FILE="luci-theme-argon.ipk"
ARGON_CONFIG_FILE="luci-app-argon-config.ipk"
ARGON_LANG_FILE="luci-i18n-argon-config-zh-cn.ipk"

ARGON_THEME_URL="${ARGON_BASE}/luci-theme-argon-master_2.2.9.4_all.ipk"
ARGON_CONFIG_URL="${ARGON_BASE}/luci-app-argon-config_0.9_all.ipk"
ARGON_LANG_URL="${ARGON_BASE}/luci-i18n-argon-config-zh-cn.ipk"


# ============================================================
# 日志函数
# ============================================================

_theme_info()
{
    printf "${GREEN}[INFO]${RESET} %s\n" "$*"
}


_theme_ok()
{
    printf "${GREEN}[OK]${RESET} %s\n" "$*"
}


_theme_warn()
{
    printf "${YELLOW}[WARN]${RESET} %s\n" "$*"
}


_theme_error()
{
    printf "${RED}[ERROR]${RESET} %s\n" "$*"
}


# ============================================================
# 进度条
# ============================================================

theme_progress()
{
    PERCENT="$1"
    TEXT="$2"

    WIDTH=30

    FILLED=$((PERCENT * WIDTH / 100))
    EMPTY=$((WIDTH - FILLED))

    BAR=""
    I=0


    while [ "$I" -lt "$FILLED" ]; do

        BAR="${BAR}#"

        I=$((I + 1))

    done


    I=0

    while [ "$I" -lt "$EMPTY" ]; do

        BAR="${BAR}-"

        I=$((I + 1))

    done


    printf "\r\033[2K${GREEN}[INFO]${RESET} %-18s [${GREEN}%s${RESET}] %3d%%" \
        "$TEXT" \
        "$BAR" \
        "$PERCENT"
}


# ============================================================
# 显示错误日志
# ============================================================

show_theme_error_log()
{
    printf "\n"

    printf "${RED}========== ERROR LOG ==========${RESET}\n"


    if [ -s "$THEME_LOG" ]; then

        tail -n 50 "$THEME_LOG"

    else

        printf "没有可用的错误日志\n"

    fi


    printf "${RED}===============================${RESET}\n"

    printf "\n"
}


# ============================================================
# 清理
# ============================================================

cleanup_theme()
{
    rm -rf "$THEME_TMP" 2>/dev/null

    return 0
}


cleanup_theme_all()
{
    rm -rf "$THEME_TMP" 2>/dev/null
    rm -f "$THEME_LOG" 2>/dev/null

    return 0
}


# ============================================================
# 中断处理
# ============================================================

theme_interrupt()
{
    printf "\n"

    _theme_warn "主题安装已中断"

    cleanup_theme

    trap - INT TERM

    return 130
}


# ============================================================
# 下载函数
# ============================================================

download_theme_file()
{
    URL="$1"
    OUTPUT="$2"


    rm -f "$OUTPUT"


    # --------------------------------------------------------
    # 优先 curl
    # --------------------------------------------------------

    if command -v curl >/dev/null 2>&1; then

        curl -L \
            -f \
            -sS \
            --connect-timeout 10 \
            --max-time 120 \
            --retry 2 \
            --retry-delay 1 \
            -o "$OUTPUT" \
            "$URL" \
            >>"$THEME_LOG" 2>&1

        RESULT=$?


    # --------------------------------------------------------
    # 回退 wget
    # --------------------------------------------------------

    elif command -v wget >/dev/null 2>&1; then

        wget \
            -T 20 \
            -O "$OUTPUT" \
            "$URL" \
            >>"$THEME_LOG" 2>&1

        RESULT=$?


    else

        printf "curl/wget not found\n" >>"$THEME_LOG"

        return 1

    fi


    # --------------------------------------------------------
    # 下载命令失败
    # --------------------------------------------------------

    if [ "$RESULT" -ne 0 ]; then

        rm -f "$OUTPUT"

        return 1

    fi


    # --------------------------------------------------------
    # 文件为空
    # --------------------------------------------------------

    if [ ! -s "$OUTPUT" ]; then

        printf "Downloaded file is empty: %s\n" \
            "$OUTPUT" >>"$THEME_LOG"

        rm -f "$OUTPUT"

        return 1

    fi


    # --------------------------------------------------------
    # 防止服务器返回 HTML
    # --------------------------------------------------------

    if head -c 512 "$OUTPUT" 2>/dev/null |
       grep -Eqi \
       '<html|<!doctype|404 not found|bad gateway|cloudflare'
    then

        printf "Invalid HTML response: %s\n" \
            "$URL" >>"$THEME_LOG"

        rm -f "$OUTPUT"

        return 1

    fi


    return 0
}


# ============================================================
# 检测包是否已经安装
# ============================================================

package_installed()
{
    PACKAGE_NAME="$1"


    opkg status "$PACKAGE_NAME" 2>/dev/null |
        grep -q 'Status:.*installed'
}


# ============================================================
# 尝试安装依赖
#
# 注意：
# 这些依赖并不是所有 OpenWrt/GL.iNet 固件都完全相同。
# 所以可选依赖安装失败不会立即终止整个脚本。
# ============================================================

install_theme_dependencies()
{
    for DEP in \
        luci-lua-runtime \
        luci-lib-ipkg \
        luci-compat
    do

        if package_installed "$DEP"; then
            continue
        fi


        printf "\n===== Dependency: %s =====\n" \
            "$DEP" >>"$THEME_LOG"


        opkg install "$DEP" \
            >>"$THEME_LOG" 2>&1 || true

    done


    return 0
}


# ============================================================
# 验证主题安装
# ============================================================

verify_argon_install()
{
    # --------------------------------------------------------
    # 方法 1：检查 opkg
    # --------------------------------------------------------

    if package_installed "luci-theme-argon"; then
        return 0
    fi


    # --------------------------------------------------------
    # 方法 2：检查主题目录
    # --------------------------------------------------------

    if [ -d /www/luci-static/argon ]; then
        return 0
    fi


    return 1
}


# ============================================================
# 安装主题
# ============================================================

install_theme()
{
    printf "\n"

    printf "%b\n" \
        "${BLUE}╔══════════════════════════════════════╗${RESET}"

    printf "%b\n" \
        "${BLUE}║${GREEN}        iStoreOS主题一键安装          ${BLUE}║${RESET}"

    printf "%b\n" \
        "${BLUE}╚══════════════════════════════════════╝${RESET}"

    printf "\n"


    # ========================================================
    # Root 检测
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _theme_error "请使用 root 用户运行"

        return 1

    fi


    # ========================================================
    # 初始化
    # ========================================================

    cleanup_theme_all

    mkdir -p "$THEME_TMP" || {

        _theme_error "无法创建临时目录"

        return 1

    }


    touch "$THEME_LOG" 2>/dev/null


    trap 'theme_interrupt' INT TERM


    # ========================================================
    # 设备信息
    # ========================================================

    MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"

    [ -n "$MODEL" ] ||
        MODEL="Unknown"


    ARCH="$(uname -m 2>/dev/null)"

    [ -n "$ARCH" ] ||
        ARCH="Unknown"


    _theme_info "设备型号: $MODEL"

    _theme_info "CPU架构: $ARCH"


    # ========================================================
    # 包管理器
    # ========================================================

    if command -v opkg >/dev/null 2>&1; then

        PKG="opkg"
        EXT="ipk"

    elif command -v apk >/dev/null 2>&1; then

        PKG="apk"
        EXT="apk"

    else

        _theme_error "未检测到支持的软件包管理器"

        cleanup_theme

        trap - INT TERM

        return 1

    fi


    _theme_info "软件管理器: $PKG"

    _theme_info "软件包类型: .$EXT"


    printf "\n"


    # ========================================================
    # 当前 Argon 安装源只提供 IPK
    # ========================================================

    if [ "$PKG" != "opkg" ]; then

        _theme_error "当前 Argon 安装源暂不支持 APK 系统"

        cleanup_theme

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 10%
    # ========================================================

    theme_progress 10 "正在准备环境..."

    sleep 1


    # ========================================================
    # 20% 检查依赖
    # ========================================================

    theme_progress 20 "正在检查依赖..."


    install_theme_dependencies


    sleep 1


    # ========================================================
    # 30% 下载主题主体
    # ========================================================

    theme_progress 30 "正在下载主题..."


    if ! download_theme_file \
        "$ARGON_THEME_URL" \
        "$THEME_TMP/$ARGON_THEME_FILE"
    then

        printf "\n"

        _theme_error "Argon 主题主体下载失败"

        show_theme_error_log

        cleanup_theme

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 45%
    # ========================================================

    theme_progress 45 "正在下载主题..."


    if ! download_theme_file \
        "$ARGON_CONFIG_URL" \
        "$THEME_TMP/$ARGON_CONFIG_FILE"
    then

        printf "\n"

        _theme_error "Argon 配置组件下载失败"

        show_theme_error_log

        cleanup_theme

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 60%
    # ========================================================

    theme_progress 60 "正在下载主题..."


    if ! download_theme_file \
        "$ARGON_LANG_URL" \
        "$THEME_TMP/$ARGON_LANG_FILE"
    then

        printf "\n"

        _theme_error "Argon 中文组件下载失败"

        show_theme_error_log

        cleanup_theme

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 70%
    # ========================================================

    theme_progress 70 "正在验证文件..."


    if [ ! -s "$THEME_TMP/$ARGON_THEME_FILE" ] ||
       [ ! -s "$THEME_TMP/$ARGON_CONFIG_FILE" ] ||
       [ ! -s "$THEME_TMP/$ARGON_LANG_FILE" ]
    then

        printf "\n"

        _theme_error "主题文件验证失败"

        show_theme_error_log

        cleanup_theme

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 78%
    # ========================================================

    theme_progress 78 "正在安装主题..."


    printf "\n===== Argon Install =====\n" \
        >>"$THEME_LOG"


    opkg install \
        "$THEME_TMP/$ARGON_THEME_FILE" \
        "$THEME_TMP/$ARGON_CONFIG_FILE" \
        "$THEME_TMP/$ARGON_LANG_FILE" \
        >>"$THEME_LOG" 2>&1

    INSTALL_RESULT=$?


    # ========================================================
    # 某些情况下 opkg 返回非 0，但主题实际已经安装。
    # 所以再做一次真实验证。
    # ========================================================

    if [ "$INSTALL_RESULT" -ne 0 ]; then

        if ! verify_argon_install; then

            printf "\n"

            _theme_error "Argon 主题安装失败"

            show_theme_error_log

            cleanup_theme

            trap - INT TERM

            return 1

        fi

    fi


    # ========================================================
    # 90%
    # ========================================================

    theme_progress 90 "正在配置主题..."


    # --------------------------------------------------------
    # 设置 Argon 为默认主题
    # --------------------------------------------------------

    if command -v uci >/dev/null 2>&1; then

        uci set luci.main.theme='argon' \
            >>"$THEME_LOG" 2>&1

        uci set luci.main.mediaurlbase='/luci-static/argon' \
            >>"$THEME_LOG" 2>&1

        uci commit luci \
            >>"$THEME_LOG" 2>&1

    fi


    # ========================================================
    # 95%
    # ========================================================

    theme_progress 95 "正在刷新 LuCI..."


    # --------------------------------------------------------
    # 清除 LuCI 缓存
    # --------------------------------------------------------

    rm -rf /tmp/luci-indexcache \
        >/dev/null 2>&1

    rm -rf /tmp/luci-modulecache \
        >/dev/null 2>&1

    rm -rf /tmp/luci-*cache* \
        >/dev/null 2>&1


    # --------------------------------------------------------
    # 重启 rpcd
    # --------------------------------------------------------

    if [ -x /etc/init.d/rpcd ]; then

        /etc/init.d/rpcd restart \
            >>"$THEME_LOG" 2>&1

    fi


    # --------------------------------------------------------
    # 重启 uhttpd
    # --------------------------------------------------------

    if [ -x /etc/init.d/uhttpd ]; then

        /etc/init.d/uhttpd restart \
            >>"$THEME_LOG" 2>&1

    fi


    # ========================================================
    # 最终验证
    # ========================================================

    if ! verify_argon_install; then

        printf "\n"

        _theme_error "主题安装完成，但最终验证失败"

        show_theme_error_log

        cleanup_theme

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 100%
    # ========================================================

    theme_progress 100 "主题安装完成"

    printf "\n\n"


    # ========================================================
    # 清理
    # ========================================================

    cleanup_theme_all


    trap - INT TERM


    # ========================================================
    # 完成
    # ========================================================

    _theme_ok "Argon 主题安装成功"

    _theme_info "已设置 Argon 为默认 LuCI 主题"

    _theme_info "请刷新或重新登录 LuCI 页面"


    printf "\n"


    return 0
}

#!/bin/sh

# ============================================================
# Open-Pro-Installer
# iStoreOS / Argon Theme Installer
#
# 功能：
# 1. 自动检测设备 / CPU
# 2. 自动检测 opkg / apk
# 3. 临时添加 Argon 软件源
# 4. 自动检测并安装依赖
# 5. 下载日志全部隐藏
# 6. 安装日志全部隐藏
# 7. 单行动态进度条
# 8. 失败时自动显示详细错误
# 9. 自动恢复 customfeeds.conf
# 10. 自动设置 Argon 为默认主题
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
# 配置
# ============================================================

ARGON_BASE="https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/theme"

ARGON_FEED="/etc/opkg/customfeeds.conf"
ARGON_BACKUP="/tmp/customfeeds.argon.backup"

THEME_PKG="/tmp/luci-theme-argon.ipk"
CONFIG_PKG="/tmp/luci-app-argon-config.ipk"
I18N_PKG="/tmp/luci-i18n-argon-config-zh-cn.ipk"

THEME_LOG="/tmp/openpro_theme.log"

THEME_PID=""


# ============================================================
# 日志
# ============================================================

_theme_info()
{
    printf "%b\n" "${GREEN}[INFO]${RESET} $*"
}


_theme_ok()
{
    printf "%b\n" "${GREEN}[OK]${RESET} $*"
}


_theme_warn()
{
    printf "%b\n" "${YELLOW}[WARN]${RESET} $*"
}


_theme_error()
{
    printf "%b\n" "${RED}[ERROR]${RESET} $*"
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


    while [ "$I" -lt "$FILLED" ]
    do
        BAR="${BAR}#"
        I=$((I + 1))
    done


    I=0

    while [ "$I" -lt "$EMPTY" ]
    do
        BAR="${BAR}-"
        I=$((I + 1))
    done


    printf '\r\033[2K\033[32m[INFO]\033[0m %-18s [\033[32m%s\033[0m] %3d%%' \
        "$TEXT" \
        "$BAR" \
        "$PERCENT"
}


# ============================================================
# 进度完成换行
# ============================================================

theme_progress_done()
{
    theme_progress 100 "$1"

    printf "\n"
}


# ============================================================
# 显示错误日志
# ============================================================

show_theme_error_log()
{
    if [ -s "$THEME_LOG" ]
    then
        printf "\n"
        printf "========== ERROR LOG ==========\n"

        tail -n 40 "$THEME_LOG"

        printf "===============================\n"
        printf "\n"
    fi
}


# ============================================================
# 删除临时安装包
# ============================================================

cleanup_theme_files()
{
    rm -f "$THEME_PKG" 2>/dev/null
    rm -f "$CONFIG_PKG" 2>/dev/null
    rm -f "$I18N_PKG" 2>/dev/null

    return 0
}


# ============================================================
# 恢复软件源
# ============================================================

restore_argon_feed()
{
    if [ -f "$ARGON_BACKUP" ]
    then
        cp "$ARGON_BACKUP" "$ARGON_FEED" \
            >/dev/null 2>&1

        rm -f "$ARGON_BACKUP"
    else
        sed -i '/argon_theme/d' \
            "$ARGON_FEED" \
            >/dev/null 2>&1
    fi

    return 0
}


# ============================================================
# 完整清理
# ============================================================

cleanup_theme()
{
    cleanup_theme_files

    restore_argon_feed

    return 0
}


# ============================================================
# 中断处理
# ============================================================

interrupt_theme()
{
    printf "\n"

    _theme_warn "主题安装已中断"


    if [ -n "$THEME_PID" ]
    then
        kill "$THEME_PID" \
            >/dev/null 2>&1

        wait "$THEME_PID" \
            >/dev/null 2>&1
    fi


    cleanup_theme


    trap - INT TERM

    return 130
}


# ============================================================
# 检查 OPKG 包是否安装
# ============================================================

opkg_package_installed()
{
    PACKAGE="$1"

    opkg status "$PACKAGE" 2>/dev/null |
        grep -q 'Status:.*installed'
}


# ============================================================
# 静默下载
# ============================================================

download_theme_package()
{
    URL="$1"
    OUTPUT="$2"


    rm -f "$OUTPUT"


    # --------------------------------------------------------
    # 优先 CURL
    # --------------------------------------------------------

    if command -v curl >/dev/null 2>&1
    then

        curl -4 \
            -L \
            -f \
            -sS \
            --connect-timeout 8 \
            --max-time 60 \
            --retry 2 \
            --retry-delay 1 \
            -o "$OUTPUT" \
            "$URL" \
            >>"$THEME_LOG" 2>&1

        RESULT=$?


    # --------------------------------------------------------
    # WGET
    # --------------------------------------------------------

    elif command -v wget >/dev/null 2>&1
    then

        wget \
            -T 20 \
            -O "$OUTPUT" \
            "$URL" \
            >>"$THEME_LOG" 2>&1

        RESULT=$?

    else

        printf "curl / wget not found\n" \
            >>"$THEME_LOG"

        return 1
    fi


    if [ "$RESULT" -ne 0 ]
    then
        rm -f "$OUTPUT"

        return 1
    fi


    if [ ! -s "$OUTPUT" ]
    then
        printf "Downloaded file is empty: %s\n" \
            "$OUTPUT" \
            >>"$THEME_LOG"

        rm -f "$OUTPUT"

        return 1
    fi


    return 0
}


# ============================================================
# 安装依赖
# ============================================================

install_theme_dependencies()
{
    for DEP in \
        luci-lua-runtime \
        luci-lib-ipkg \
        luci-compat \
        libopenssl3
    do

        # ----------------------------------------------------
        # 已安装直接跳过
        # ----------------------------------------------------

        if opkg_package_installed "$DEP"
        then
            continue
        fi


        printf "\nInstalling dependency: %s\n" \
            "$DEP" \
            >>"$THEME_LOG"


        if ! opkg install "$DEP" \
            >>"$THEME_LOG" 2>&1
        then

            # ------------------------------------------------
            # 某些 OpenWrt 版本可能不存在这些兼容包
            # 不立即退出，记录后继续
            # ------------------------------------------------

            printf "Optional dependency failed: %s\n" \
                "$DEP" \
                >>"$THEME_LOG"
        fi

    done


    return 0
}


# ============================================================
# 安装 Argon 软件包
# ============================================================

install_argon_packages()
{
    opkg install \
        "$THEME_PKG" \
        "$CONFIG_PKG" \
        "$I18N_PKG" \
        >>"$THEME_LOG" 2>&1
}


# ============================================================
# 主安装
# ============================================================

install_theme()
{
    echo ""


    printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"
    printf "%b\n" "${BLUE}║${GREEN}        iStoreOS主题一键安装          ${BLUE}║${RESET}"
    printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"


    echo ""


    # ========================================================
    # Root
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]
    then
        _theme_error "请使用 root 用户运行"

        return 1
    fi


    # ========================================================
    # 初始化
    # ========================================================

    rm -f "$THEME_LOG"
    rm -f "$ARGON_BACKUP"

    cleanup_theme_files


    trap 'interrupt_theme' INT TERM


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

    if command -v opkg >/dev/null 2>&1
    then

        PKG="opkg"
        EXT="ipk"

    elif command -v apk >/dev/null 2>&1
    then

        PKG="apk"
        EXT="apk"

    else

        _theme_error "不支持的软件包管理器"

        trap - INT TERM

        return 1
    fi


    _theme_info "软件管理器: $PKG"

    _theme_info "软件包类型: .$EXT"


    # ========================================================
    # 当前 Argon 安装源只支持 OPKG
    # ========================================================

    if [ "$PKG" != "opkg" ]
    then

        _theme_error "当前 Argon 安装源暂不支持 APK"

        trap - INT TERM

        return 1
    fi


    # ========================================================
    # 5% 初始化
    # ========================================================

    theme_progress 5 "正在准备环境..."

    sleep 1


    # ========================================================
    # 备份软件源
    # ========================================================

    if [ -f "$ARGON_FEED" ]
    then

        cp "$ARGON_FEED" "$ARGON_BACKUP" \
            >/dev/null 2>&1
    else

        touch "$ARGON_FEED"
    fi


    sed -i '/argon_theme/d' \
        "$ARGON_FEED" \
        >/dev/null 2>&1


    cat >> "$ARGON_FEED" <<EOF

src/gz argon_theme $ARGON_BASE
EOF


    theme_progress 10 "正在准备环境..."


    # ========================================================
    # 更新临时软件源
    # ========================================================

    if ! opkg update >>"$THEME_LOG" 2>&1
    then

        printf "\n"

        _theme_error "软件源更新失败"

        show_theme_error_log

        cleanup_theme

        trap - INT TERM

        return 1
    fi


    theme_progress 20 "正在更新软件源..."


    # ========================================================
    # 依赖
    # ========================================================

    install_theme_dependencies


    theme_progress 30 "正在检查依赖..."


    # ========================================================
    # 下载主题
    # ========================================================

    if ! download_theme_package \
        "$ARGON_BASE/luci-theme-argon-master_2.2.9.4_all.ipk" \
        "$THEME_PKG"
    then

        printf "\n"

        _theme_error "Argon 主题下载失败"

        show_theme_error_log

        cleanup_theme

        trap - INT TERM

        return 1
    fi


    theme_progress 45 "正在下载主题..."


    # ========================================================
    # 下载配置插件
    # ========================================================

    if ! download_theme_package \
        "$ARGON_BASE/luci-app-argon-config_0.9_all.ipk" \
        "$CONFIG_PKG"
    then

        printf "\n"

        _theme_error "Argon 配置插件下载失败"

        show_theme_error_log

        cleanup_theme

        trap - INT TERM

        return 1
    fi


    theme_progress 60 "正在下载主题..."


    # ========================================================
    # 下载中文包
    # ========================================================

    if ! download_theme_package \
        "$ARGON_BASE/luci-i18n-argon-config-zh-cn.ipk" \
        "$I18N_PKG"
    then

        printf "\n"

        _theme_error "Argon 中文包下载失败"

        show_theme_error_log

        cleanup_theme

        trap - INT TERM

        return 1
    fi


    theme_progress 70 "正在下载主题..."


    # ========================================================
    # 安装
    # ========================================================

    install_argon_packages >>"$THEME_LOG" 2>&1 &

    THEME_PID=$!


    PERCENT=72


    while kill -0 "$THEME_PID" 2>/dev/null
    do

        if [ "$PERCENT" -lt 92 ]
        then
            PERCENT=$((PERCENT + 2))
        fi


        theme_progress \
            "$PERCENT" \
            "正在安装主题..."


        sleep 1
    done


    wait "$THEME_PID"

    INSTALL_RESULT=$?

    THEME_PID=""


    if [ "$INSTALL_RESULT" -ne 0 ]
    then

        printf "\n"

        _theme_error "Argon 主题安装失败"

        show_theme_error_log

        cleanup_theme

        trap - INT TERM

        return 1
    fi


    theme_progress 94 "正在安装主题..."


    # ========================================================
    # 验证主题
    # ========================================================

    if ! opkg_package_installed "luci-theme-argon"
    then

        printf "\n"

        _theme_error "未检测到 luci-theme-argon"

        show_theme_error_log

        cleanup_theme

        trap - INT TERM

        return 1
    fi


    theme_progress 96 "正在配置主题..."


    # ========================================================
    # 设置默认主题
    # ========================================================

    if command -v uci >/dev/null 2>&1
    then

        uci set luci.main.theme='argon' \
            >>"$THEME_LOG" 2>&1

        uci set luci.main.mediaurlbase='/luci-static/argon' \
            >>"$THEME_LOG" 2>&1

        uci commit luci \
            >>"$THEME_LOG" 2>&1
    fi


    theme_progress 98 "正在清理环境..."


    # ========================================================
    # 恢复软件源
    # ========================================================

    restore_argon_feed


    # 不需要再次 opkg update。
    # 避免安装结束时又产生网络等待。


    # ========================================================
    # 清理 IPK
    # ========================================================

    cleanup_theme_files


    # ========================================================
    # 重启服务
    # ========================================================

    if [ -x /etc/init.d/rpcd ]
    then
        /etc/init.d/rpcd restart \
            >/dev/null 2>&1
    fi


    if [ -x /etc/init.d/uhttpd ]
    then
        /etc/init.d/uhttpd restart \
            >/dev/null 2>&1
    fi


    # ========================================================
    # 完成
    # ========================================================

    theme_progress_done "主题安装完成"


    rm -f "$THEME_LOG" 2>/dev/null


    trap - INT TERM


    printf "\n"

    _theme_ok "Argon 主题安装成功"

    _theme_info "已设置 Argon 为默认 LuCI 主题"

    _theme_info "请刷新或重新登录 LuCI 页面"

    printf "\n"


    return 0
}

#!/bin/sh

# ============================================================
# Open-Pro-Installer
# iStoreOS / Argon Theme + QuickStart Installer
#
# 功能：
# 1. 自动检测设备 / CPU / OPKG
# 2. 安装 Argon 主题 + 配置插件 + 中文语言包
# 3. 自动设置 Argon 为默认 LuCI 主题
# 4. 自动安装 QuickStart：首页 + 网络向导
# 5. 自动安装 quickstart / luci-app-quickstart / 中文语言包
# 6. 不修改 /etc/opkg/customfeeds.conf
# 7. QuickStart 使用 iStore 官方 is-opkg 独立软件索引
# 8. 自动备份并应用 iStoreOS 风格 QuickStart 配置
# 9. 已安装组件自动跳过，避免重复下载安装
# 10. 失败时保留详细日志 /tmp/openpro-theme.log
# 11. 自动清理 LuCI 缓存并重启 rpcd / uhttpd
#
# BusyBox / OpenWrt /bin/sh Compatible
# ============================================================


# ============================================================
# 颜色
# ============================================================

GREEN="$(printf '\033[32m')"
BLUE="$(printf '\033[34m')"
RED="$(printf '\033[31m')"
YELLOW="$(printf '\033[33m')"
CYAN="$(printf '\033[36m')"
RESET="$(printf '\033[0m')"


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
# iStore 官方 is-opkg
# ============================================================

IS_OPKG_URL="https://raw.githubusercontent.com/linkease/istore/main/luci/luci-app-store/root/bin/is-opkg"

IS_OPKG_BIN=""


# ============================================================
# QuickStart iStoreOS 风格配置
# ============================================================

QUICKSTART_CONFIG_URL="https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/config/quickstart"

QUICKSTART_CONFIG_TMP="${THEME_TMP}/quickstart.conf"

QUICKSTART_CONFIG_BAK="/etc/config/quickstart.openpro.bak"


# ============================================================
# 日志
# ============================================================

_theme_info()
{
    printf "%b\n" \
        "${GREEN}[INFO]${RESET} $*"
}


_theme_ok()
{
    printf "%b\n" \
        "${GREEN}[OK]${RESET} $*"
}


_theme_warn()
{
    printf "%b\n" \
        "${YELLOW}[WARN]${RESET} $*"
}


_theme_error()
{
    printf "%b\n" \
        "${RED}[ERROR]${RESET} $*"
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


    printf \
        "\r\033[2K${GREEN}[INFO]${RESET} %-22s [${GREEN}%s${RESET}] %3d%%" \
        "$TEXT" \
        "$BAR" \
        "$PERCENT"
}


# ============================================================
# 错误日志
# ============================================================

show_theme_error_log()
{
    printf "\n"

    printf "%b\n" \
        "${RED}========== ERROR LOG ==========${RESET}"


    if [ -s "$THEME_LOG" ]
    then

        tail -n 80 "$THEME_LOG"

    else

        printf "没有可用的错误日志\n"

    fi


    printf "%b\n" \
        "${RED}===============================${RESET}"

    printf "\n"
}


# ============================================================
# 清理
# ============================================================

cleanup_theme_temp()
{
    rm -rf "$THEME_TMP" \
        2>/dev/null

    return 0
}


cleanup_theme_all()
{
    rm -rf "$THEME_TMP" \
        2>/dev/null

    rm -f "$THEME_LOG" \
        2>/dev/null

    return 0
}


# ============================================================
# Ctrl+C
# ============================================================

theme_interrupt()
{
    printf "\n"

    _theme_warn \
        "iStoreOS 风格安装已中断"

    _theme_info \
        "安装日志保留在：$THEME_LOG"


    cleanup_theme_temp


    trap - INT TERM


    return 130
}


# ============================================================
# 必要命令检测
# ============================================================

check_theme_runtime()
{
    MISSING=""


    for CMD in \
        opkg \
        grep \
        sed \
        awk \
        head \
        tail \
        cp \
        rm \
        mkdir \
        chmod \
        df \
        uci
    do

        command -v "$CMD" \
            >/dev/null 2>&1 ||
            MISSING="$MISSING $CMD"

    done


    if [ -n "$MISSING" ]
    then

        _theme_error \
            "系统缺少必要命令:$MISSING"

        return 1

    fi


    if ! command -v curl \
        >/dev/null 2>&1 &&
       ! command -v wget \
        >/dev/null 2>&1
    then

        _theme_error \
            "系统缺少 curl / wget"

        return 1

    fi


    return 0
}


# ============================================================
# 空间检测
# ============================================================

check_theme_disk_space()
{
    FREE_KB="$(
        df -k / 2>/dev/null |
        awk 'END {print $4}'
    )"


    case "$FREE_KB" in

        ''|*[!0-9]*)

            FREE_KB=0

        ;;

    esac


    FREE_MB=$((FREE_KB / 1024))


    _theme_info \
        "可用空间: ${FREE_MB} MB"


    if [ "$FREE_MB" -lt 15 ]
    then

        _theme_error \
            "可用空间不足，建议至少保留 15 MB"

        return 1

    fi


    return 0
}


# ============================================================
# 下载
# ============================================================

download_theme_file()
{
    URL="$1"

    OUTPUT="$2"


    rm -f "$OUTPUT"


    # ========================================================
    # curl
    # ========================================================

    if command -v curl \
        >/dev/null 2>&1
    then

        curl \
            -L \
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


    # ========================================================
    # wget
    # ========================================================

    elif command -v wget \
        >/dev/null 2>&1
    then

        wget \
            -T 20 \
            -O "$OUTPUT" \
            "$URL" \
            >>"$THEME_LOG" 2>&1

        RESULT=$?


    else

        printf \
            "curl/wget not found\n" \
            >>"$THEME_LOG"

        return 1

    fi


    # ========================================================
    # 下载失败
    # ========================================================

    if [ "$RESULT" -ne 0 ]
    then

        rm -f "$OUTPUT"

        return 1

    fi


    # ========================================================
    # 空文件
    # ========================================================

    if [ ! -s "$OUTPUT" ]
    then

        printf \
            "Downloaded file is empty: %s\n" \
            "$OUTPUT" \
            >>"$THEME_LOG"


        rm -f "$OUTPUT"


        return 1

    fi


    # ========================================================
    # 防 HTML 错误页
    # ========================================================

    if head -c 512 \
        "$OUTPUT" \
        2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|404 not found|bad gateway|cloudflare'
    then

        printf \
            "Invalid HTML response: %s\n" \
            "$URL" \
            >>"$THEME_LOG"


        rm -f "$OUTPUT"


        return 1

    fi


    return 0
}


# ============================================================
# 包安装检测
# ============================================================

package_installed()
{
    PACKAGE_NAME="$1"


    opkg status "$PACKAGE_NAME" \
        2>/dev/null |
        grep -q \
        'Status:.*installed'
}


# ============================================================
# 获取版本
# ============================================================

get_package_version()
{
    PACKAGE_NAME="$1"


    opkg status "$PACKAGE_NAME" \
        2>/dev/null |
        sed -n \
        's/^Version:[[:space:]]*//p' |
        head -n 1
}


# ============================================================
# Argon 依赖
# ============================================================

install_theme_dependencies()
{
    for DEP in \
        luci-lua-runtime \
        luci-lib-ipkg \
        luci-compat
    do


        if package_installed "$DEP"
        then

            continue

        fi


        printf \
            "\n===== Dependency: %s =====\n" \
            "$DEP" \
            >>"$THEME_LOG"


        opkg install "$DEP" \
            >>"$THEME_LOG" 2>&1 ||
            true

    done


    return 0
}


# ============================================================
# Argon 验证
# ============================================================

verify_argon_install()
{
    if package_installed \
        "luci-theme-argon"
    then

        return 0

    fi


    if [ -d /www/luci-static/argon ]
    then

        return 0

    fi


    return 1
}


# ============================================================
# 安装 Argon
# ============================================================

install_argon_theme()
{
    # ========================================================
    # 已安装
    # ========================================================

    if verify_argon_install
    then

        _theme_ok \
            "Argon 主题已安装，跳过重复安装"

        return 0

    fi


    # ========================================================
    # 下载主体
    # ========================================================

    theme_progress \
        25 \
        "正在下载 Argon..."


    if ! download_theme_file \
        "$ARGON_THEME_URL" \
        "$THEME_TMP/$ARGON_THEME_FILE"
    then

        printf "\n"

        _theme_error \
            "Argon 主题主体下载失败"

        return 1

    fi


    # ========================================================
    # 配置组件
    # ========================================================

    theme_progress \
        35 \
        "正在下载主题配置..."


    if ! download_theme_file \
        "$ARGON_CONFIG_URL" \
        "$THEME_TMP/$ARGON_CONFIG_FILE"
    then

        printf "\n"

        _theme_error \
            "Argon 配置组件下载失败"

        return 1

    fi


    # ========================================================
    # 中文组件
    # ========================================================

    theme_progress \
        45 \
        "正在下载中文组件..."


    if ! download_theme_file \
        "$ARGON_LANG_URL" \
        "$THEME_TMP/$ARGON_LANG_FILE"
    then

        printf "\n"

        _theme_error \
            "Argon 中文组件下载失败"

        return 1

    fi


    # ========================================================
    # 安装
    # ========================================================

    theme_progress \
        55 \
        "正在安装 Argon..."


    printf \
        "\n===== Argon Install =====\n" \
        >>"$THEME_LOG"


    opkg install \
        "$THEME_TMP/$ARGON_THEME_FILE" \
        "$THEME_TMP/$ARGON_CONFIG_FILE" \
        "$THEME_TMP/$ARGON_LANG_FILE" \
        >>"$THEME_LOG" 2>&1


    INSTALL_RESULT=$?


    # ========================================================
    # 有些固件 opkg 返回非0，但其实已安装
    # ========================================================

    if [ "$INSTALL_RESULT" -ne 0 ] &&
       ! verify_argon_install
    then

        printf "\n"

        _theme_error \
            "Argon 主题安装失败"

        return 1

    fi


    if ! verify_argon_install
    then

        printf "\n"

        _theme_error \
            "Argon 安装后验证失败"

        return 1

    fi


    _theme_ok \
        "Argon 主题安装成功"


    return 0
}


# ============================================================
# Argon 默认主题
# ============================================================

set_argon_default()
{
    if ! verify_argon_install
    then

        return 1

    fi


    uci set \
        luci.main.theme='argon' \
        >>"$THEME_LOG" 2>&1


    uci set \
        luci.main.mediaurlbase='/luci-static/argon' \
        >>"$THEME_LOG" 2>&1


    uci commit luci \
        >>"$THEME_LOG" 2>&1


    return 0
}


# ============================================================
# QuickStart 验证
#
# 下面三个包组成：
#
# quickstart
# luci-app-quickstart
# luci-i18n-quickstart-zh-cn
#
# LuCI 会出现：
#
# 首页
# 网络向导
# ============================================================

verify_quickstart_install()
{
    package_installed \
        "quickstart" ||
        return 1


    package_installed \
        "luci-app-quickstart" ||
        return 1


    package_installed \
        "luci-i18n-quickstart-zh-cn" ||
        return 1


    return 0
}


# ============================================================
# 获取 iStore 官方 is-opkg
#
# 不修改：
#
# /etc/opkg/customfeeds.conf
#
# is-opkg 使用自己的临时索引。
# ============================================================

ensure_is_opkg()
{
    IS_OPKG_BIN=""


    # ========================================================
    # PATH 中已经有
    # ========================================================

    if command -v is-opkg \
        >/dev/null 2>&1
    then

        IS_OPKG_BIN="$(
            command -v is-opkg
        )"


        return 0

    fi


    # ========================================================
    # /bin
    # ========================================================

    if [ -x /bin/is-opkg ]
    then

        IS_OPKG_BIN="/bin/is-opkg"

        return 0

    fi


    # ========================================================
    # /usr/bin
    # ========================================================

    if [ -x /usr/bin/is-opkg ]
    then

        IS_OPKG_BIN="/usr/bin/is-opkg"

        return 0

    fi


    # ========================================================
    # 下载临时 is-opkg
    # ========================================================

    IS_OPKG_BIN="${THEME_TMP}/is-opkg"


    printf \
        "\n===== Download is-opkg =====\n" \
        >>"$THEME_LOG"


    if ! download_theme_file \
        "$IS_OPKG_URL" \
        "$IS_OPKG_BIN"
    then

        printf \
            "Failed to download is-opkg\n" \
            >>"$THEME_LOG"


        IS_OPKG_BIN=""


        return 1

    fi


    chmod 755 \
        "$IS_OPKG_BIN" \
        >>"$THEME_LOG" 2>&1 || {

            IS_OPKG_BIN=""

            return 1

        }


    return 0
}


# ============================================================
# QuickStart 配置
#
# 第一次运行自动备份：
#
# /etc/config/quickstart.openpro.bak
# ============================================================

apply_quickstart_config()
{
    rm -f \
        "$QUICKSTART_CONFIG_TMP" \
        2>/dev/null


    # ========================================================
    # 下载配置
    # ========================================================

    if ! download_theme_file \
        "$QUICKSTART_CONFIG_URL" \
        "$QUICKSTART_CONFIG_TMP"
    then

        _theme_warn \
            "QuickStart 风格配置下载失败，保留默认配置"


        return 0

    fi


    # ========================================================
    # 备份一次
    # ========================================================

    if [ -f /etc/config/quickstart ] &&
       [ ! -f "$QUICKSTART_CONFIG_BAK" ]
    then

        cp -f \
            /etc/config/quickstart \
            "$QUICKSTART_CONFIG_BAK" \
            >>"$THEME_LOG" 2>&1 ||
            true

    fi


    # ========================================================
    # 覆盖配置
    # ========================================================

    cp -f \
        "$QUICKSTART_CONFIG_TMP" \
        /etc/config/quickstart \
        >>"$THEME_LOG" 2>&1 || {

            _theme_warn \
                "QuickStart 配置写入失败，保留现有配置"

            return 0

        }


    # ========================================================
    # UCI 验证
    # ========================================================

    if ! uci -q show quickstart \
        >/dev/null 2>&1
    then

        _theme_warn \
            "QuickStart 配置格式不兼容"


        # ====================================================
        # 自动回滚
        # ====================================================

        if [ -f "$QUICKSTART_CONFIG_BAK" ]
        then

            cp -f \
                "$QUICKSTART_CONFIG_BAK" \
                /etc/config/quickstart \
                >>"$THEME_LOG" 2>&1 ||
                true


            _theme_warn \
                "已恢复原 QuickStart 配置"

        fi


        return 0

    fi


    _theme_ok \
        "QuickStart iStoreOS 风格配置已应用"


    return 0
}


# ============================================================
# 安装 QuickStart
# ============================================================

install_quickstart()
{
    # ========================================================
    # 已经安装
    # ========================================================

    if verify_quickstart_install
    then

        _theme_ok \
            "首页 + 网络向导已安装"


        apply_quickstart_config


        return 0

    fi


    # ========================================================
    # 准备 is-opkg
    # ========================================================

    if ! ensure_is_opkg
    then

        _theme_error \
            "无法获取 iStore 官方 is-opkg"


        return 1

    fi


    printf \
        "\n===== QuickStart Install =====\n" \
        >>"$THEME_LOG"


    # ========================================================
    # 更新 iStore 索引
    # ========================================================

    theme_progress \
        68 \
        "正在更新 QuickStart 索引..."


    "$IS_OPKG_BIN" update \
        >>"$THEME_LOG" 2>&1


    UPDATE_RESULT=$?


    if [ "$UPDATE_RESULT" -ne 0 ]
    then

        _theme_warn \
            "iStore 软件索引更新返回异常，继续尝试安装"

    fi


    # ========================================================
    # 安装
    #
    # 中文包会自动拉：
    #
    # luci-app-quickstart
    # quickstart
    # ========================================================

    theme_progress \
        76 \
        "正在安装首页和向导..."


    "$IS_OPKG_BIN" install \
        luci-i18n-quickstart-zh-cn \
        >>"$THEME_LOG" 2>&1


    INSTALL_RESULT=$?


    # ========================================================
    # GL.iNet 某些系统依赖版本标记不同
    #
    # 正常安装失败后才使用：
    #
    # --force-depends
    # ========================================================

    if [ "$INSTALL_RESULT" -ne 0 ]
    then

        printf \
            "\n===== QuickStart Force Depends Retry =====\n" \
            >>"$THEME_LOG"


        "$IS_OPKG_BIN" install \
            luci-i18n-quickstart-zh-cn \
            --force-depends \
            >>"$THEME_LOG" 2>&1


        INSTALL_RESULT=$?

    fi


    # ========================================================
    # 最终以 OPKG 数据库为准
    # ========================================================

    if ! verify_quickstart_install
    then

        printf \
            "QuickStart install return code: %s\n" \
            "$INSTALL_RESULT" \
            >>"$THEME_LOG"


        _theme_error \
            "首页 + 网络向导安装失败"


        return 1

    fi


    # ========================================================
    # 配置
    # ========================================================

    theme_progress \
        84 \
        "正在配置首页和向导..."


    apply_quickstart_config


    _theme_ok \
        "首页 + 网络向导安装成功"


    return 0
}


# ============================================================
# 刷新 LuCI
# ============================================================

refresh_theme_luci()
{
    # ========================================================
    # 清缓存
    # ========================================================

    rm -rf \
        /tmp/luci-indexcache \
        /tmp/luci-modulecache \
        /tmp/luci-*cache* \
        >/dev/null 2>&1


    # ========================================================
    # rpcd
    # ========================================================

    if [ -x /etc/init.d/rpcd ]
    then

        /etc/init.d/rpcd restart \
            >>"$THEME_LOG" 2>&1

    fi


    # ========================================================
    # uhttpd
    # ========================================================

    if [ -x /etc/init.d/uhttpd ]
    then

        /etc/init.d/uhttpd restart \
            >>"$THEME_LOG" 2>&1

    fi


    return 0
}


# ============================================================
# 主安装函数
#
# install.sh：
#
# [1] 一键仿 iStoreOS 主题
#
# ↓
#
# install_theme
# ============================================================

install_theme()
{
    printf "\n"


    printf "%b\n" \
        "${BLUE}╔══════════════════════════════════════╗${RESET}"


    printf "%b\n" \
        "${BLUE}║${GREEN}        iStoreOS 风格一键安装         ${BLUE}║${RESET}"


    printf "%b\n" \
        "${BLUE}╚══════════════════════════════════════╝${RESET}"


    printf "\n"


    # ========================================================
    # Root
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]
    then

        _theme_error \
            "请使用 root 用户运行"


        return 1

    fi


    # ========================================================
    # OPKG
    # ========================================================

    if ! command -v opkg \
        >/dev/null 2>&1
    then

        if command -v apk \
            >/dev/null 2>&1
        then

            _theme_error \
                "当前主题模块暂不支持 APK 系统"

        else

            _theme_error \
                "未检测到 OPKG 包管理器"

        fi


        return 1

    fi


    # ========================================================
    # 初始化
    # ========================================================

    cleanup_theme_all


    mkdir -p "$THEME_TMP" || {

        _theme_error \
            "无法创建临时目录"

        return 1

    }


    touch "$THEME_LOG" \
        2>/dev/null


    trap \
        'theme_interrupt' \
        INT TERM


    # ========================================================
    # 设备
    # ========================================================

    MODEL="$(
        cat /tmp/sysinfo/model \
        2>/dev/null
    )"


    [ -n "$MODEL" ] ||
        MODEL="Unknown"


    CPU_ARCH="$(
        uname -m \
        2>/dev/null
    )"


    [ -n "$CPU_ARCH" ] ||
        CPU_ARCH="Unknown"


    # ========================================================
    # OPKG 精确架构
    # ========================================================

    PKG_ARCH="$(
        opkg print-architecture \
        2>/dev/null |
        awk '
            $1 == "arch" &&
            $2 != "all" &&
            $2 != "noarch"
            {
                if ($3 > p)
                {
                    p = $3
                    a = $2
                }
            }

            END
            {
                print a
            }
        '
    )"


    [ -n "$PKG_ARCH" ] ||
        PKG_ARCH="Unknown"


    _theme_info \
        "设备型号: $MODEL"


    _theme_info \
        "CPU架构: $CPU_ARCH"


    _theme_info \
        "软件架构: $PKG_ARCH"


    _theme_info \
        "包管理器: opkg"


    printf "\n"


    # ========================================================
    # 环境
    # ========================================================

    theme_progress \
        5 \
        "正在检测运行环境..."


    if ! check_theme_runtime
    then

        printf "\n"

        cleanup_theme_temp

        trap - INT TERM

        return 1

    fi


    if ! check_theme_disk_space
    then

        printf "\n"

        cleanup_theme_temp

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 依赖
    # ========================================================

    theme_progress \
        12 \
        "正在检查主题依赖..."


    install_theme_dependencies


    # ========================================================
    # Argon
    # ========================================================

    theme_progress \
        20 \
        "正在准备 Argon..."


    if ! install_argon_theme
    then

        show_theme_error_log

        cleanup_theme_temp

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 默认主题
    # ========================================================

    theme_progress \
        60 \
        "正在设置默认主题..."


    if ! set_argon_default
    then

        printf "\n"


        _theme_error \
            "Argon 默认主题设置失败"


        show_theme_error_log


        cleanup_theme_temp


        trap - INT TERM


        return 1

    fi


    # ========================================================
    # QuickStart
    # ========================================================

    theme_progress \
        64 \
        "正在准备首页和向导..."


    if ! install_quickstart
    then

        printf "\n"


        _theme_error \
            "Argon 已安装，但首页 / 网络向导安装失败"


        show_theme_error_log


        cleanup_theme_temp


        trap - INT TERM


        return 1

    fi


    # ========================================================
    # LuCI
    # ========================================================

    theme_progress \
        92 \
        "正在刷新 LuCI..."


    refresh_theme_luci


    # ========================================================
    # 验证
    # ========================================================

    theme_progress \
        97 \
        "正在进行最终验证..."


    if ! verify_argon_install
    then

        printf "\n"


        _theme_error \
            "Argon 最终验证失败"


        show_theme_error_log


        cleanup_theme_temp


        trap - INT TERM


        return 1

    fi


    if ! verify_quickstart_install
    then

        printf "\n"


        _theme_error \
            "首页 / 网络向导最终验证失败"


        show_theme_error_log


        cleanup_theme_temp


        trap - INT TERM


        return 1

    fi


    # ========================================================
    # 100%
    # ========================================================

    theme_progress \
        100 \
        "iStoreOS 风格安装完成"


    printf "\n\n"


    # ========================================================
    # 获取版本
    # ========================================================

    ARGON_VERSION="$(
        get_package_version \
            luci-theme-argon
    )"


    QUICKSTART_VERSION="$(
        get_package_version \
            luci-app-quickstart
    )"


    # ========================================================
    # 清理临时文件
    # ========================================================

    cleanup_theme_temp


    trap - INT TERM


    # ========================================================
    # 完成
    # ========================================================

    _theme_ok \
        "Argon 主题安装成功"


    _theme_ok \
        "首页 + 网络向导安装成功"


    if [ -n "$ARGON_VERSION" ]
    then

        _theme_info \
            "Argon 版本: $ARGON_VERSION"

    fi


    if [ -n "$QUICKSTART_VERSION" ]
    then

        _theme_info \
            "QuickStart 版本: $QUICKSTART_VERSION"

    fi


    _theme_info \
        "已设置 Argon 为默认 LuCI 主题"


    _theme_info \
        "LuCI 左侧菜单应出现：首页、网络向导"


    _theme_info \
        "如页面未立即更新，请强制刷新浏览器或重新登录 LuCI"


    printf "\n"


    # ========================================================
    # 成功才删除日志
    # ========================================================

    rm -f "$THEME_LOG" \
        2>/dev/null


    return 0
}

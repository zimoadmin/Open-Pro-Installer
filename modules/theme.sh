#!/bin/sh

# ============================================================
# Open-Pro-Installer
# iStoreOS Style / Argon + QuickStart Installer
#
# 支持：
#   OpenWrt 21.x / 22.x / 23.x / 24.x / 25.x
#   OPKG / APK 自动识别
#
# 修复：
# 1. OpenWrt 版本信息与进度条粘连/显示不整齐
# 2. BusyBox awk 兼容
# 3. 中文包异常显示
# 4. 延迟和下载速度显示
# 5. 修复 THEME_SCORE_FILE_KB / SPEED_KB not found
# 6. 修复 TTFB_MS / SPEED_INT / 1000000 not found
# 7. 修复 OPKG 软件包架构识别
# 8. QuickStart 实际安装成功却误报失败
# 9. QuickStart 软件包状态作为主要验证依据
# 10. LuCI 文件路径仅作为辅助验证
#
# BusyBox / OpenWrt /bin/sh Compatible
# ============================================================


# ============================================================
# Color
# ============================================================

GREEN="$(printf '\033[32m')"
BLUE="$(printf '\033[34m')"
RED="$(printf '\033[31m')"
YELLOW="$(printf '\033[33m')"
CYAN="$(printf '\033[36m')"
RESET="$(printf '\033[0m')"


# ============================================================
# Temp
# ============================================================

THEME_TMP="/tmp/openpro-theme"
THEME_LOG="/tmp/openpro-theme.log"

THEME_ROUTE_FILE="/tmp/openpro_theme_routes"
THEME_SORTED_FILE="/tmp/openpro_theme_routes.sorted"
THEME_TEST_DIR="/tmp/openpro_theme_speedtest.d"

THEME_ROUTE_CACHE_READY=0
THEME_ROUTE_CACHE_URL=""


# ============================================================
# System
# ============================================================

MODEL=""
CPU_ARCH=""
PKG_ARCH=""

OPENWRT_VERSION=""
OPENWRT_MAJOR=""

PKG_MANAGER=""
ARGON_PACKAGE_TYPE=""

ARGON_MENU_FIX_APPLIED=0


# ============================================================
# Argon
# ============================================================

ARGON_REPO="jerrykuku/luci-theme-argon"

ARGON_RELEASE_API="https://api.github.com/repos/${ARGON_REPO}/releases/latest"

ARGON_RELEASE_JSON="${THEME_TMP}/argon_release.json"
ARGON_ASSET_LIST="${THEME_TMP}/argon_assets.list"
ARGON_RELEASE_HEADERS="${THEME_TMP}/argon_headers"
ARGON_EXPANDED_ASSETS="${THEME_TMP}/argon_assets.html"

ARGON_RELEASE_TAG=""
ARGON_TARGET_TAG=""

ARGON_THEME_URL=""
ARGON_CONFIG_URL=""
ARGON_LANG_URL=""

ARGON_THEME_FILE=""
ARGON_CONFIG_FILE=""
ARGON_LANG_FILE=""


# ============================================================
# QuickStart
# ============================================================

IS_OPKG_URL="https://raw.githubusercontent.com/linkease/istore/main/luci/luci-app-store/root/bin/is-opkg"

IS_OPKG_BIN=""

QUICKSTART_CONFIG_URL="https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/config/quickstart"

QUICKSTART_CONFIG_TMP="${THEME_TMP}/quickstart.conf"

QUICKSTART_CONFIG_BAK="/etc/config/quickstart.openpro.bak"

QUICKSTART_ORIGIN_BASE=""
QUICKSTART_MIRROR_BASE=""

QUICKSTART_SELECTED_BASE=""
QUICKSTART_FALLBACK_BASE=""

QUICKSTART_INDEX_PATH=""

QUICKSTART_SOURCE_DIR="${THEME_TMP}/quickstart-speedtest.d"

QUICKSTART_SOURCE_FILE="${THEME_TMP}/quickstart-sources.list"

QUICKSTART_PATCHED_IS_OPKG="${THEME_TMP}/is-opkg-selected"


# ============================================================
# Speed Test
# ============================================================

THEME_TEST_CONNECT_TIMEOUT=4

THEME_TEST_MAX_TIME=6

THEME_SCORE_FILE_KB=4096


# ============================================================
# GitHub 下载线路
# ============================================================

THEME_DOWNLOAD_NODES="
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
GH04|https://cdn.akaere.online/
GH05|https://github.mxw.qzz.io/
GH06|https://gh.07150721.xyz/
DIRECT|
"


# ============================================================
# Log
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
# Progress
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


    printf "\r\033[2K${GREEN}[INFO]${RESET} %-28s [${GREEN}%s${RESET}] %3d%%" \
        "$TEXT" \
        "$BAR" \
        "$PERCENT"
}


# ============================================================
# Error Log
# ============================================================

show_theme_error_log()
{
    printf "\n"

    printf "%b\n" "${RED}========== ERROR LOG ==========${RESET}"


    if [ -s "$THEME_LOG" ]; then

        tail -n 120 "$THEME_LOG"

    else

        printf "没有可用错误日志\n"

    fi


    printf "%b\n" "${RED}===============================${RESET}"

    printf "\n"
}


# ============================================================
# Cleanup
# ============================================================

cleanup_theme_temp()
{
    rm -rf \
        "$THEME_TMP" \
        "$THEME_TEST_DIR" \
        2>/dev/null


    rm -f \
        "$THEME_ROUTE_FILE" \
        "$THEME_SORTED_FILE" \
        2>/dev/null


    return 0
}


cleanup_theme_all()
{
    cleanup_theme_temp


    rm -f \
        "$THEME_LOG" \
        2>/dev/null


    return 0
}


# ============================================================
# Interrupt
# ============================================================

theme_interrupt()
{
    printf "\n"

    _theme_warn "iStoreOS 风格安装已中断"

    _theme_info "安装日志保留：$THEME_LOG"

    cleanup_theme_temp

    trap - INT TERM

    return 130
}


# ============================================================
# Runtime Check
# ============================================================

check_theme_runtime()
{
    MISSING=""


    for CMD in \
        grep \
        sed \
        awk \
        head \
        tail \
        cut \
        tr \
        sort \
        basename \
        cp \
        rm \
        mkdir \
        chmod \
        df \
        uci \
        uname \
        id
    do

        command -v "$CMD" >/dev/null 2>&1 ||
            MISSING="$MISSING $CMD"

    done


    if [ -n "$MISSING" ]; then

        _theme_error "系统缺少必要命令:$MISSING"

        return 1

    fi


    if ! command -v curl >/dev/null 2>&1 &&
       ! command -v wget >/dev/null 2>&1
    then

        _theme_error "系统缺少 curl / wget"

        return 1

    fi


    return 0
}


# ============================================================
# Package Manager
# ============================================================

detect_package_manager()
{
    if command -v opkg >/dev/null 2>&1; then

        PKG_MANAGER="opkg"

        ARGON_PACKAGE_TYPE="ipk"

        return 0

    fi


    if command -v apk >/dev/null 2>&1; then

        PKG_MANAGER="apk"

        ARGON_PACKAGE_TYPE="apk"

        return 0

    fi


    return 1
}


# ============================================================
# OpenWrt Major
# ============================================================

detect_openwrt_major()
{
    OPENWRT_MAJOR="$(
        printf '%s\n' "$OPENWRT_VERSION" |
        sed -n 's/^\([0-9][0-9]*\).*/\1/p'
    )"


    case "$OPENWRT_MAJOR" in

        ''|*[!0-9]*)

            OPENWRT_MAJOR="0"

            ;;

    esac
}


# ============================================================
# OPKG 架构
#
# 目标：
#
# opkg print-architecture
#
# arch all 1
# arch noarch 1
# arch aarch64_cortex-a53_neon-vfpv4 10
#
# 最终只得到：
#
# aarch64_cortex-a53_neon-vfpv4
# ============================================================

detect_opkg_arch()
{
    PKG_ARCH=""


    PKG_ARCH="$(
        opkg print-architecture 2>/dev/null |
        awk '
            $1 == "arch" &&
            $2 != "all" &&
            $2 != "noarch"
            {
                priority = $3 + 0

                if (priority >= best_priority) {
                    best_priority = priority
                    best_arch = $2
                }
            }

            END {
                if (best_arch != "")
                    printf "%s", best_arch
            }
        '
    )"


# ======================================
# 获取软件包架构
# ======================================

if [ "$PKG_MANAGER" = "opkg" ]; then

    PKG_ARCH="$(
        opkg print-architecture 2>/dev/null |
        awk '
            $1 == "arch" &&
            $2 != "all" &&
            $2 != "noarch" {
                priority = $3 + 0

                if (priority > max_priority) {
                    max_priority = priority
                    arch_name = $2
                }
            }

            END {
                if (arch_name != "")
                    printf "%s", arch_name
            }
        '
    )"

elif [ "$PKG_MANAGER" = "apk" ]; then

    PKG_ARCH="$CPU_ARCH"

else

    PKG_ARCH="Unknown"

fi

[ -n "$PKG_ARCH" ] || PKG_ARCH="Unknown"


    return 0
}


# ============================================================
# Detect System
# ============================================================

detect_theme_system()
{
    if [ -f /etc/openwrt_release ]; then

        . /etc/openwrt_release

        OPENWRT_VERSION="${DISTRIB_RELEASE:-unknown}"

    else

        OPENWRT_VERSION="unknown"

    fi


    detect_openwrt_major


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


    if [ "$PKG_MANAGER" = "opkg" ]; then

        detect_opkg_arch

    else

        PKG_ARCH="$CPU_ARCH"

    fi


    [ -n "$PKG_ARCH" ] ||
        PKG_ARCH="$CPU_ARCH"


    [ -n "$PKG_ARCH" ] ||
        PKG_ARCH="Unknown"


    _theme_info "OpenWrt版本  : $OPENWRT_VERSION"

    _theme_info "OpenWrt主版本: $OPENWRT_MAJOR"

    _theme_info "设备型号     : $MODEL"

    _theme_info "CPU架构      : $CPU_ARCH"

    _theme_info "软件包架构   : $PKG_ARCH"

    _theme_info "包管理器     : $PKG_MANAGER"


    return 0
}


# ============================================================
# Disk
# ============================================================

check_theme_disk_space()
{
    FREE_KB="$(
        df -k / \
        2>/dev/null |
        awk 'END {print $4}'
    )"


    case "$FREE_KB" in

        ''|*[!0-9]*)

            FREE_KB=0

            ;;

    esac


    FREE_MB=$((FREE_KB / 1024))


    _theme_info "可用空间     : ${FREE_MB} MB"


    if [ "$FREE_MB" -lt 15 ]; then

        _theme_error "可用空间不足，至少需要 15 MB"

        return 1

    fi


    return 0
}


# ============================================================
# Argon Compatibility
# ============================================================

select_argon_compat()
{
    case "$OPENWRT_MAJOR" in

        21)

            ARGON_TARGET_TAG="v2.2.9"

            _theme_info "兼容策略     : OpenWrt 21.x"

            _theme_info "Argon版本    : v2.2.9"

            ;;


        22|23|24|25)

            ARGON_TARGET_TAG=""

            _theme_info "兼容策略     : OpenWrt ${OPENWRT_MAJOR}.x"

            _theme_info "Argon版本    : 自动获取最新兼容版本"

            ;;


        *)

            ARGON_TARGET_TAG=""

            _theme_warn "未知 OpenWrt 主版本，使用最新 Argon"

            ;;

    esac


    case "$ARGON_PACKAGE_TYPE" in

        ipk)

            ARGON_THEME_FILE="${THEME_TMP}/argon-theme.ipk"

            ARGON_CONFIG_FILE="${THEME_TMP}/argon-config.ipk"

            ARGON_LANG_FILE="${THEME_TMP}/argon-lang.ipk"

            ;;


        apk)

            ARGON_THEME_FILE="${THEME_TMP}/argon-theme.apk"

            ARGON_CONFIG_FILE="${THEME_TMP}/argon-config.apk"

            ARGON_LANG_FILE="${THEME_TMP}/argon-lang.apk"

            ;;


        *)

            _theme_error "未知软件包格式：$ARGON_PACKAGE_TYPE"

            return 1

            ;;

    esac


    _theme_info "软件包格式   : .$ARGON_PACKAGE_TYPE"


    return 0
}


# ============================================================
# Download
# ============================================================

download_direct()
{
    URL="$1"
    OUTPUT="$2"


    rm -f "$OUTPUT"


    if command -v curl >/dev/null 2>&1; then

        curl \
            -4 \
            -L \
            -f \
            -sS \
            --connect-timeout 10 \
            --max-time 180 \
            --retry 2 \
            --retry-delay 1 \
            -H "User-Agent: Open-Pro-Installer" \
            -o "$OUTPUT" \
            "$URL" \
            >>"$THEME_LOG" 2>&1


        RESULT=$?

    else

        wget \
            -T 30 \
            --header="User-Agent: Open-Pro-Installer" \
            -O "$OUTPUT" \
            "$URL" \
            >>"$THEME_LOG" 2>&1


        RESULT=$?

    fi


    if [ "$RESULT" -ne 0 ] ||
       [ ! -s "$OUTPUT" ]
    then

        rm -f "$OUTPUT"

        return 1

    fi


    if head -c 512 "$OUTPUT" 2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|404 not found|bad gateway|502 bad gateway|403 forbidden|cloudflare'
    then

        printf "Invalid response: %s\n" \
            "$URL" \
            >>"$THEME_LOG"


        rm -f "$OUTPUT"

        return 1

    fi


    return 0
}


# ============================================================
# Package Installed
# ============================================================

package_installed()
{
    PACKAGE_NAME="$1"


    case "$PKG_MANAGER" in

        opkg)

            opkg status "$PACKAGE_NAME" 2>/dev/null |
                grep -q 'Status:.*installed'

            ;;


        apk)

            apk query \
                --installed \
                --fields name \
                "$PACKAGE_NAME" \
                2>/dev/null |
                grep -q "^Name:[[:space:]]*$PACKAGE_NAME$"

            ;;


        *)

            return 1

            ;;

    esac
}


# ============================================================
# Package Version
# ============================================================

get_package_version()
{
    PACKAGE_NAME="$1"


    case "$PKG_MANAGER" in

        opkg)

            opkg status "$PACKAGE_NAME" 2>/dev/null |
                sed -n 's/^Version:[[:space:]]*//p' |
                head -n 1

            ;;


        apk)

            apk list \
                --installed \
                "$PACKAGE_NAME" \
                2>/dev/null |
                head -n 1 |
                sed "s/^${PACKAGE_NAME}-//" |
                sed 's/[[:space:]].*$//'

            ;;

    esac
}


# ============================================================
# Argon Release URL
# ============================================================

get_release_tag_url()
{
    TAG="$1"


    [ -n "$TAG" ] ||
        return 1


    printf \
        'https://github.com/%s/releases/expanded_assets/%s' \
        "$ARGON_REPO" \
        "$TAG"
}


# ============================================================
# Argon Release Page
# ============================================================

fetch_argon_release_page()
{
    TAG="$1"


    EXPANDED_URL="$(
        get_release_tag_url "$TAG"
    )"


    [ -n "$EXPANDED_URL" ] ||
        return 1


    rm -f "$ARGON_EXPANDED_ASSETS"


    if ! download_direct \
        "$EXPANDED_URL" \
        "$ARGON_EXPANDED_ASSETS"
    then

        return 1

    fi


    grep -o \
        "/${ARGON_REPO}/releases/download/[^\"]*" \
        "$ARGON_EXPANDED_ASSETS" \
        2>/dev/null |
        sed 's/&amp;/\&/g' |
        while IFS= read -r ASSET_PATH
        do

            printf \
                'https://github.com%s\n' \
                "$ASSET_PATH"

        done > "$ARGON_ASSET_LIST"


    [ -s "$ARGON_ASSET_LIST" ]
}


# ============================================================
# Argon Release
# ============================================================

fetch_argon_release()
{
    rm -f \
        "$ARGON_RELEASE_JSON" \
        "$ARGON_ASSET_LIST" \
        "$ARGON_EXPANDED_ASSETS"


    ARGON_RELEASE_TAG=""

    ARGON_THEME_URL=""

    ARGON_CONFIG_URL=""

    ARGON_LANG_URL=""


    if [ -n "$ARGON_TARGET_TAG" ]; then

        ARGON_RELEASE_TAG="$ARGON_TARGET_TAG"


        _theme_info \
            "正在读取 Argon Release：$ARGON_RELEASE_TAG"


        if ! fetch_argon_release_page \
            "$ARGON_RELEASE_TAG"
        then

            _theme_error \
                "无法读取 Argon $ARGON_RELEASE_TAG Release"

            return 1

        fi

    else

        _theme_info \
            "正在直连 GitHub API 获取 Argon 最新版本..."


        if download_direct \
            "$ARGON_RELEASE_API" \
            "$ARGON_RELEASE_JSON"
        then

            if command -v jsonfilter >/dev/null 2>&1; then

                ARGON_RELEASE_TAG="$(
                    jsonfilter \
                        -i "$ARGON_RELEASE_JSON" \
                        -e '@.tag_name' \
                        2>/dev/null
                )"


                jsonfilter \
                    -i "$ARGON_RELEASE_JSON" \
                    -e '@.assets[*].browser_download_url' \
                    2>/dev/null \
                    > "$ARGON_ASSET_LIST"

            else

                ARGON_RELEASE_TAG="$(
                    tr ',' '\n' < "$ARGON_RELEASE_JSON" |
                    sed -n \
                    's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' |
                    head -n 1
                )"


                tr ',' '\n' < "$ARGON_RELEASE_JSON" |
                    sed -n \
                    's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' \
                    > "$ARGON_ASSET_LIST"

            fi

        fi


        if [ -z "$ARGON_RELEASE_TAG" ] ||
           [ ! -s "$ARGON_ASSET_LIST" ]
        then

            _theme_warn \
                "GitHub API 不可用，切换普通 Release 页面..."


            LATEST_PAGE="https://github.com/${ARGON_REPO}/releases/latest"


            if command -v curl >/dev/null 2>&1; then

                EFFECTIVE_URL="$(
                    curl \
                        -4 \
                        -L \
                        -sS \
                        --connect-timeout 10 \
                        --max-time 30 \
                        -o /dev/null \
                        -w '%{url_effective}' \
                        "$LATEST_PAGE" \
                        2>>"$THEME_LOG"
                )"

            else

                EFFECTIVE_URL=""

            fi


            ARGON_RELEASE_TAG="$(
                printf '%s\n' "$EFFECTIVE_URL" |
                sed -n \
                's#^.*/releases/tag/\([^/?#]*\).*$#\1#p'
            )"


            if [ -z "$ARGON_RELEASE_TAG" ]; then

                _theme_error \
                    "无法识别 Argon 最新版本"

                return 1

            fi


            if ! fetch_argon_release_page \
                "$ARGON_RELEASE_TAG"
            then

                _theme_error \
                    "无法读取 Argon Release Asset"

                return 1

            fi

        fi

    fi


    case "$ARGON_PACKAGE_TYPE" in

        ipk)

            ARGON_THEME_URL="$(
                grep \
                    '/luci-theme-argon_[^/]*\.ipk$' \
                    "$ARGON_ASSET_LIST" |
                head -n 1
            )"


            ARGON_CONFIG_URL="$(
                grep \
                    '/luci-app-argon-config_[^/]*\.ipk$' \
                    "$ARGON_ASSET_LIST" |
                head -n 1
            )"


            ARGON_LANG_URL="$(
                grep \
                    '/luci-i18n-argon-config-zh-cn_[^/]*\.ipk$' \
                    "$ARGON_ASSET_LIST" |
                head -n 1
            )"

            ;;


        apk)

            ARGON_THEME_URL="$(
                grep -E \
                    '/luci-theme-argon[-_][^/]*\.apk$' \
                    "$ARGON_ASSET_LIST" |
                head -n 1
            )"


            ARGON_CONFIG_URL="$(
                grep -E \
                    '/luci-app-argon-config[-_][^/]*\.apk$' \
                    "$ARGON_ASSET_LIST" |
                head -n 1
            )"


            ARGON_LANG_URL="$(
                grep -E \
                    '/luci-i18n-argon-config-zh-cn[-_][^/]*\.apk$' \
                    "$ARGON_ASSET_LIST" |
                head -n 1
            )"

            ;;

    esac


    case "$ARGON_THEME_URL" in

        https://github.com/*)
            ;;

        *)
            ARGON_THEME_URL=""
            ;;

    esac


    case "$ARGON_CONFIG_URL" in

        https://github.com/*)
            ;;

        *)
            ARGON_CONFIG_URL=""
            ;;

    esac


    case "$ARGON_LANG_URL" in

        https://github.com/*)
            ;;

        *)
            ARGON_LANG_URL=""
            ;;

    esac


    if [ -z "$ARGON_THEME_URL" ]; then

        _theme_error \
            "Release 中没有 .$ARGON_PACKAGE_TYPE 格式的 Argon Theme"

        return 1

    fi


    if [ -z "$ARGON_CONFIG_URL" ]; then

        _theme_warn \
            "Release 中没有 Argon Config，将仅安装 Theme"

    fi


    _theme_ok \
        "Argon Release：$ARGON_RELEASE_TAG"


    _theme_info \
        "Theme  : $(basename "$ARGON_THEME_URL")"


    if [ -n "$ARGON_CONFIG_URL" ]; then

        _theme_info \
            "Config : $(basename "$ARGON_CONFIG_URL")"

    fi


    if [ -n "$ARGON_LANG_URL" ]; then

        _theme_info \
            "中文包 : $(basename "$ARGON_LANG_URL")"

    else

        _theme_info \
            "中文包 : 无独立中文包"

    fi


    return 0
}


# ============================================================
# Build Proxy URL
# ============================================================

build_theme_url()
{
    PREFIX="$1"
    ORIGINAL_URL="$2"


    if [ -z "$PREFIX" ]; then

        printf '%s' \
            "$ORIGINAL_URL"

    else

        printf '%s%s' \
            "$PREFIX" \
            "$ORIGINAL_URL"

    fi
}


# ============================================================
# Seconds -> ms
# ============================================================

theme_seconds_to_ms()
{
    T="$1"


    case "$T" in

        ''|*[!0-9.]*)

            printf '%s' "999999"

            return 0

            ;;

    esac


    SEC="${T%%.*}"


    if [ "$SEC" = "$T" ]; then

        FRAC="0"

    else

        FRAC="${T#*.}"

    fi


    [ -n "$SEC" ] ||
        SEC="0"


    FRAC="${FRAC}000"


    FRAC="$(
        printf '%s' "$FRAC" |
        cut -c 1-3
    )"


    SEC="$(
        printf '%s' "$SEC" |
        sed 's/^0*//'
    )"


    FRAC="$(
        printf '%s' "$FRAC" |
        sed 's/^0*//'
    )"


    [ -n "$SEC" ] ||
        SEC=0


    [ -n "$FRAC" ] ||
        FRAC=0


    case "$SEC" in

        *[!0-9]*)
            SEC=0
            ;;

    esac


    case "$FRAC" in

        *[!0-9]*)
            FRAC=0
            ;;

    esac


    printf '%s' \
        "$((SEC * 1000 + FRAC))"
}


# ============================================================
# Bytes/s -> MB/s
# ============================================================

theme_speed_to_mb()
{
    S="$1"


    case "$S" in

        ''|*[!0-9.]*)

            printf '%s' "0.00"

            return 0

            ;;

    esac


    S="${S%%.*}"


    S="$(
        printf '%s' "$S" |
        sed 's/^0*//'
    )"


    [ -n "$S" ] ||
        S=0


    case "$S" in

        *[!0-9]*)

            printf '%s' "0.00"

            return 0

            ;;

    esac


    WHOLE=$((S / 1048576))

    REM=$((S % 1048576))

    DEC=$((REM * 100 / 1048576))


    printf '%d.%02d' \
        "$WHOLE" \
        "$DEC"
}


# ============================================================
# Score
#
# BusyBox /bin/sh 安全算术
# ============================================================

theme_calculate_score()
{
    T="$1"
    S="$2"


    case "$T" in

        ''|*[!0-9]*)

            T=999999

            ;;

    esac


    case "$S" in

        ''|*[!0-9]*)

            S=0

            ;;

    esac


    if [ "$S" -le 0 ]; then

        printf '%s' "999999999"

        return 0

    fi


    SPEED_KB=$((S / 1024))


    if [ "$SPEED_KB" -le 0 ]; then

        printf '%s' "999999999"

        return 0

    fi


    DOWNLOAD_MS=$((THEME_SCORE_FILE_KB * 1000 / SPEED_KB))


    SCORE=$((T + DOWNLOAD_MS))


    printf '%s' \
        "$SCORE"


    return 0
}


# ============================================================
# Error Page
# ============================================================

theme_test_is_error_page()
{
    FILE="$1"


    [ -s "$FILE" ] ||
        return 1


    head -c 1024 "$FILE" \
        2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
}


# ============================================================
# Argon Route Test
# ============================================================

test_theme_route()
{
    TEST_URL="$1"
    TEST_FILE="$2"


    rm -f "$TEST_FILE"


    command -v curl >/dev/null 2>&1 ||
        return 1


    CURL_DATA="$(
        curl \
            -4 \
            -L \
            -sS \
            --connect-timeout "$THEME_TEST_CONNECT_TIMEOUT" \
            --max-time "$THEME_TEST_MAX_TIME" \
            -o "$TEST_FILE" \
            -w '%{http_code}|%{time_starttransfer}|%{speed_download}|%{size_download}' \
            "$TEST_URL" \
            2>/dev/null
    )"


    CURL_CODE=$?


    HTTP_CODE="$(
        printf '%s' "$CURL_DATA" |
        cut -d '|' -f 1
    )"


    TTFB="$(
        printf '%s' "$CURL_DATA" |
        cut -d '|' -f 2
    )"


    SPEED_BPS="$(
        printf '%s' "$CURL_DATA" |
        cut -d '|' -f 3
    )"


    SIZE_DOWN="$(
        printf '%s' "$CURL_DATA" |
        cut -d '|' -f 4
    )"


    case "$CURL_CODE" in

        0|28)
            ;;

        *)

            rm -f "$TEST_FILE"

            return 1

            ;;

    esac


    case "$HTTP_CODE" in

        200|206)
            ;;

        *)

            rm -f "$TEST_FILE"

            return 1

            ;;

    esac


    case "$SIZE_DOWN" in

        ''|*[!0-9.]*)

            RECEIVED_BYTES=0

            ;;

        *)

            RECEIVED_BYTES="${SIZE_DOWN%%.*}"


            RECEIVED_BYTES="$(
                printf '%s' "$RECEIVED_BYTES" |
                sed 's/^0*//'
            )"


            [ -n "$RECEIVED_BYTES" ] ||
                RECEIVED_BYTES=0

            ;;

    esac


    [ "$RECEIVED_BYTES" -ge 2048 ] || {

        rm -f "$TEST_FILE"

        return 1

    }


    if theme_test_is_error_page "$TEST_FILE"; then

        rm -f "$TEST_FILE"

        return 1

    fi


    TTFB_MS="$(
        theme_seconds_to_ms \
            "$TTFB"
    )"


    case "$SPEED_BPS" in

        ''|*[!0-9.]*)

            SPEED_INT=0

            ;;

        *)

            SPEED_INT="${SPEED_BPS%%.*}"


            SPEED_INT="$(
                printf '%s' "$SPEED_INT" |
                sed 's/^0*//'
            )"


            [ -n "$SPEED_INT" ] ||
                SPEED_INT=0

            ;;

    esac


    [ "$SPEED_INT" -gt 0 ] || {

        rm -f "$TEST_FILE"

        return 1

    }


    SCORE="$(
        theme_calculate_score \
            "$TTFB_MS" \
            "$SPEED_INT"
    )"


    rm -f "$TEST_FILE"


    printf '%s|%s|%s' \
        "$TTFB_MS" \
        "$SPEED_INT" \
        "$SCORE"


    return 0
}


# ============================================================
# Background Test
# ============================================================

test_theme_route_background()
{
    NODE_NAME="$1"
    NODE_PREFIX="$2"
    ORIGINAL_URL="$3"
    RESULT_FILE="$4"
    TEST_FILE="$5"


    TEST_URL="$(
        build_theme_url \
            "$NODE_PREFIX" \
            "$ORIGINAL_URL"
    )"


    TEST_DATA="$(
        test_theme_route \
            "$TEST_URL" \
            "$TEST_FILE"
    )"


    if [ $? -ne 0 ] ||
       [ -z "$TEST_DATA" ]
    then

        printf '%s|FAIL\n' \
            "$NODE_NAME" \
            > "$RESULT_FILE"

        return 1

    fi


    TTFB_MS="$(
        printf '%s' "$TEST_DATA" |
        cut -d '|' -f 1
    )"


    SPEED_BPS="$(
        printf '%s' "$TEST_DATA" |
        cut -d '|' -f 2
    )"


    SCORE="$(
        printf '%s' "$TEST_DATA" |
        cut -d '|' -f 3
    )"


    printf '%s|OK|%s|%s|%s|%s|%s\n' \
        "$NODE_NAME" \
        "$NODE_PREFIX" \
        "$TEST_URL" \
        "$TTFB_MS" \
        "$SPEED_BPS" \
        "$SCORE" \
        > "$RESULT_FILE"


    return 0
}


# ============================================================
# Node Prefix
# ============================================================

get_theme_node_prefix()
{
    WANT="$1"


    while IFS='|' read -r NAME PREFIX
    do

        [ "$NAME" = "$WANT" ] ||
            continue


        printf '%s' \
            "$PREFIX"


        return 0

    done <<EOF
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
GH04|https://cdn.akaere.online/
GH05|https://github.mxw.qzz.io/
GH06|https://gh.07150721.xyz/
DIRECT|
EOF


    return 1
}


# ============================================================
# Prepare Argon Routes
# ============================================================

prepare_theme_routes()
{
    ORIGINAL_URL="$1"


    rm -f \
        "$THEME_ROUTE_FILE" \
        "$THEME_SORTED_FILE"


    rm -rf \
        "$THEME_TEST_DIR"


    mkdir -p \
        "$THEME_TEST_DIR" ||
        return 1


    printf "\n"


    _theme_info \
        "正在并行测试 Argon 下载线路..."


    printf "\n"


    for NODE_NAME in \
        GH01 \
        GH02 \
        GH03 \
        GH04 \
        GH05 \
        GH06 \
        DIRECT
    do

        NODE_PREFIX="$(
            get_theme_node_prefix \
                "$NODE_NAME"
        )"


        test_theme_route_background \
            "$NODE_NAME" \
            "$NODE_PREFIX" \
            "$ORIGINAL_URL" \
            "$THEME_TEST_DIR/result_${NODE_NAME}" \
            "$THEME_TEST_DIR/download_${NODE_NAME}" &

    done


    wait


    printf '%-8s %-12s %-14s\n' \
        "线路" \
        "延迟" \
        "下载速度"


    printf '%-8s %-12s %-14s\n' \
        "--------" \
        "------------" \
        "--------------"


    for NODE_NAME in \
        GH01 \
        GH02 \
        GH03 \
        GH04 \
        GH05 \
        GH06 \
        DIRECT
    do

        RESULT_FILE="$THEME_TEST_DIR/result_${NODE_NAME}"


        if [ ! -s "$RESULT_FILE" ] ||
           [ "$(cut -d '|' -f 2 "$RESULT_FILE")" != "OK" ]
        then

            printf '%-8s %-12s %-14s\n' \
                "$NODE_NAME" \
                "----" \
                "----"

            continue

        fi


        NODE_PREFIX="$(
            cut -d '|' -f 3 \
                "$RESULT_FILE"
        )"


        TEST_URL="$(
            cut -d '|' -f 4 \
                "$RESULT_FILE"
        )"


        TTFB_MS="$(
            cut -d '|' -f 5 \
                "$RESULT_FILE"
        )"


        SPEED_BPS="$(
            cut -d '|' -f 6 \
                "$RESULT_FILE"
        )"


        SCORE="$(
            cut -d '|' -f 7 \
                "$RESULT_FILE"
        )"


        SPEED_MB="$(
            theme_speed_to_mb \
                "$SPEED_BPS"
        )"


        case "$TTFB_MS" in

            ''|*[!0-9]*)

                TTFB_MS="----"

                ;;

        esac


        case "$SPEED_BPS" in

            ''|*[!0-9]*)

                SPEED_MB="0.00"

                ;;

        esac


        printf '%-8s %-12s %-14s\n' \
            "$NODE_NAME" \
            "${TTFB_MS} ms" \
            "${SPEED_MB} MB/s"


        printf '%s|%s|%s|%s|%s|%s\n' \
            "$SCORE" \
            "$NODE_NAME" \
            "$NODE_PREFIX" \
            "$TEST_URL" \
            "$TTFB_MS" \
            "$SPEED_BPS" \
            >> "$THEME_ROUTE_FILE"

    done


    rm -rf \
        "$THEME_TEST_DIR"


    [ -s "$THEME_ROUTE_FILE" ] || {

        _theme_warn \
            "没有发现可用测速线路"

        return 1

    }


    sort \
        -n \
        -t '|' \
        -k 1,1 \
        "$THEME_ROUTE_FILE" \
        > "$THEME_SORTED_FILE"


    if [ -s "$THEME_SORTED_FILE" ]; then

        mv \
            "$THEME_SORTED_FILE" \
            "$THEME_ROUTE_FILE"

    fi


    BEST_LINE="$(
        sed -n '1p' \
            "$THEME_ROUTE_FILE"
    )"


    BEST_NAME="$(
        printf '%s' "$BEST_LINE" |
        cut -d '|' -f 2
    )"


    BEST_TTFB="$(
        printf '%s' "$BEST_LINE" |
        cut -d '|' -f 5
    )"


    BEST_SPEED="$(
        printf '%s' "$BEST_LINE" |
        cut -d '|' -f 6
    )"


    printf "\n"


    _theme_ok \
        "最佳线路：$BEST_NAME"


    _theme_info \
        "延迟：${BEST_TTFB} ms"


    _theme_info \
        "下载速度：$(theme_speed_to_mb "$BEST_SPEED") MB/s"


    printf "\n"


    return 0
}


# ============================================================
# Smart Download Argon
# ============================================================

smart_download_release()
{
    ORIGINAL_URL="$1"
    OUTPUT="$2"


    DOWNLOAD_SUCCESS=0

    DIRECT_TRIED=0


    if [ "$THEME_ROUTE_CACHE_READY" -ne 1 ] ||
       [ ! -s "$THEME_ROUTE_FILE" ]
    then

        prepare_theme_routes \
            "$ORIGINAL_URL" ||
            true


        if [ -s "$THEME_ROUTE_FILE" ]; then

            THEME_ROUTE_CACHE_READY=1

            THEME_ROUTE_CACHE_URL="$ORIGINAL_URL"

        else

            THEME_ROUTE_CACHE_READY=0

            THEME_ROUTE_CACHE_URL=""

        fi

    else

        _theme_info \
            "复用首次 Argon 下载线路测速结果"

    fi


    if [ -s "$THEME_ROUTE_FILE" ]; then

        while IFS='|' read -r \
            ROUTE_SCORE \
            ROUTE_NAME \
            ROUTE_PREFIX \
            ROUTE_TEST_URL \
            ROUTE_TTFB \
            ROUTE_SPEED
        do

            [ -n "$ROUTE_NAME" ] ||
                continue


            if [ "$ROUTE_NAME" = "DIRECT" ]; then

                DIRECT_TRIED=1

            fi


            ROUTE_URL="$(
                build_theme_url \
                    "$ROUTE_PREFIX" \
                    "$ORIGINAL_URL"
            )"


            [ -n "$ROUTE_URL" ] ||
                continue


            _theme_info \
                "正在使用线路：$ROUTE_NAME"


            if download_direct \
                "$ROUTE_URL" \
                "$OUTPUT"
            then

                _theme_ok \
                    "下载线路：$ROUTE_NAME"


                DOWNLOAD_SUCCESS=1


                break

            fi


            _theme_warn \
                "$ROUTE_NAME 下载失败，切换下一线路..."


        done < "$THEME_ROUTE_FILE"

    fi


    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] &&
       [ "$DIRECT_TRIED" -ne 1 ]
    then

        _theme_info \
            "正在尝试 GitHub 官方直连..."


        if download_direct \
            "$ORIGINAL_URL" \
            "$OUTPUT"
        then

            _theme_ok \
                "GitHub 官方直连下载成功"


            DOWNLOAD_SUCCESS=1

        fi

    fi


    [ "$DOWNLOAD_SUCCESS" -eq 1 ]
}


# ============================================================
# Install Local Package
# ============================================================

install_local_package()
{
    FILE="$1"


    [ -s "$FILE" ] ||
        return 1


    case "$PKG_MANAGER" in

        opkg)

            opkg install \
                "$FILE" \
                >>"$THEME_LOG" 2>&1

            ;;


        apk)

            apk add \
                --allow-untrusted \
                "$FILE" \
                >>"$THEME_LOG" 2>&1

            ;;


        *)

            return 1

            ;;

    esac
}


# ============================================================
# Bootstrap Theme
# ============================================================

restore_bootstrap_theme()
{
    _theme_warn \
        "正在回滚到 Bootstrap 主题..."


    if [ -d /www/luci-static/bootstrap ]; then

        uci set \
            luci.main.mediaurlbase='/luci-static/bootstrap' \
            >/dev/null 2>&1


        uci set \
            luci.main.theme='bootstrap' \
            >/dev/null 2>&1


        uci commit luci \
            >/dev/null 2>&1


        _theme_ok \
            "已恢复 Bootstrap"


        return 0

    fi


    _theme_warn \
        "未找到 Bootstrap 主题"


    return 1
}


# ============================================================
# Verify Argon
# ============================================================

verify_argon_install()
{
    package_installed \
        "luci-theme-argon" &&
        return 0


    [ -d /www/luci-static/argon ] &&
        return 0


    return 1
}


# ============================================================
# Install Argon
# ============================================================

install_argon_official()
{
    if ! fetch_argon_release; then

        _theme_error \
            "Argon Release 获取失败"

        return 1

    fi


    theme_progress \
        28 \
        "正在下载 Argon Theme..."


    printf "\n"


    if ! smart_download_release \
        "$ARGON_THEME_URL" \
        "$ARGON_THEME_FILE"
    then

        _theme_error \
            "Argon Theme 下载失败"

        return 1

    fi


    if [ -n "$ARGON_CONFIG_URL" ]; then

        theme_progress \
            42 \
            "正在下载 Argon Config..."


        printf "\n"


        if ! smart_download_release \
            "$ARGON_CONFIG_URL" \
            "$ARGON_CONFIG_FILE"
        then

            _theme_warn \
                "Argon Config 下载失败，将仅安装 Theme"


            rm -f \
                "$ARGON_CONFIG_FILE"

        fi

    fi


    if [ -n "$ARGON_LANG_URL" ]; then

        theme_progress \
            50 \
            "正在下载 Argon 中文包..."


        printf "\n"


        if ! smart_download_release \
            "$ARGON_LANG_URL" \
            "$ARGON_LANG_FILE"
        then

            _theme_warn \
                "中文包下载失败，自动跳过"


            rm -f \
                "$ARGON_LANG_FILE"

        fi

    fi


    theme_progress \
        58 \
        "正在安装 Argon..."


    printf "\n"


    printf "\n===== Argon Install =====\n" \
        >>"$THEME_LOG"


    if ! install_local_package \
        "$ARGON_THEME_FILE"
    then

        printf "\n"


        _theme_error \
            "Argon Theme 包安装失败"


        restore_bootstrap_theme


        return 1

    fi


    if [ -s "$ARGON_CONFIG_FILE" ]; then

        if ! install_local_package \
            "$ARGON_CONFIG_FILE"
        then

            _theme_warn \
                "Argon Config 安装失败，主题仍可使用"

        fi

    fi


    if [ -s "$ARGON_LANG_FILE" ]; then

        if ! install_local_package \
            "$ARGON_LANG_FILE"
        then

            _theme_warn \
                "Argon 中文包安装失败，自动跳过"

        fi

    fi


    if ! verify_argon_install; then

        _theme_error \
            "Argon 安装验证失败"


        restore_bootstrap_theme


        return 1

    fi


    _theme_ok \
        "Argon Theme 安装成功"


    return 0
}


# ============================================================
# Argon Default
# ============================================================

set_argon_default()
{
    verify_argon_install ||
        return 1


    uci set \
        luci.main.mediaurlbase='/luci-static/argon' \
        >>"$THEME_LOG" 2>&1


    uci set \
        luci.main.theme='argon' \
        >>"$THEME_LOG" 2>&1


    uci set \
        luci.themes.Argon='/luci-static/argon' \
        >>"$THEME_LOG" 2>&1


    uci commit luci \
        >>"$THEME_LOG" 2>&1


    return 0
}


# ============================================================
# OpenWrt 21.x / Argon v2.2.9
# 菜单折叠修复
# ============================================================

apply_argon21_menu_fix()
{
    [ "$OPENWRT_MAJOR" = "21" ] ||
        return 0


    [ "$ARGON_RELEASE_TAG" = "v2.2.9" ] ||
        return 0


    MENU_FILE="/www/luci-static/resources/menu-argon.js"

    MENU_BACKUP="${MENU_FILE}.openpro.bak"

    MENU_TMP="${THEME_TMP}/menu-argon.js"


    if [ ! -f "$MENU_FILE" ]; then

        _theme_warn \
            "未找到 menu-argon.js，跳过 Argon 21.x 菜单折叠修复"

        return 0

    fi


    if [ ! -f "$MENU_BACKUP" ]; then

        cp -f \
            "$MENU_FILE" \
            "$MENU_BACKUP" \
            >>"$THEME_LOG" 2>&1 || {

                _theme_warn \
                    "menu-argon.js 备份失败，跳过菜单修复"

                return 0
            }

    fi


    cat > "$MENU_TMP" <<'OPENPRO_MENU_ARGON_EOF'
'use strict';
'require baseclass';
'require ui';

return baseclass.extend({
	__init__: function () {
		ui.menu.load().then(L.bind(this.render, this));
	},

	render: function (tree) {
		var node = tree,
			url = '',
			children = ui.menu.getChildren(tree);

		for (var i = 0; i < children.length; i++) {
			var isActive = (
				L.env.requestpath.length
					? children[i].name == L.env.requestpath[0]
					: i == 0
			);

			if (isActive)
				this.renderMainMenu(children[i], children[i].name);
		}

		if (L.env.dispatchpath.length >= 3) {
			for (var i = 0; i < 3 && node; i++) {
				node = node.children[L.env.dispatchpath[i]];
				url = url + (url ? '/' : '') + L.env.dispatchpath[i];
			}

			if (node)
				this.renderTabMenu(node, url);
		}

		var showSide = document.querySelector('a.showSide');
		var darkMask = document.querySelector('.darkMask');

		if (showSide)
			showSide.addEventListener(
				'click',
				ui.createHandlerFn(this, 'handleSidebarToggle')
			);

		if (darkMask)
			darkMask.addEventListener(
				'click',
				ui.createHandlerFn(this, 'handleSidebarToggle')
			);
	},

	handleMenuExpand: function (ev) {
		var a = ev.currentTarget || ev.target,
			slide = a.parentNode,
			slide_menu = a.nextElementSibling;

		if (!slide_menu)
			return;

		ev.preventDefault();
		ev.stopPropagation();

		if (slide_menu.classList.contains('active')) {
			slide_menu.classList.remove('active');
			a.classList.remove('active');
			slide_menu.style.display = 'none';

			if (slide)
				slide.classList.remove('active');

			a.blur();
			return;
		}

		var openedMenus = document.querySelectorAll(
			'.main .main-left .nav > li > ul.active'
		);

		for (var i = 0; i < openedMenus.length; i++) {
			var ul = openedMenus[i];

			if (ul === slide_menu)
				continue;

			ul.classList.remove('active');
			ul.style.display = 'none';

			if (ul.previousElementSibling)
				ul.previousElementSibling.classList.remove('active');

			if (ul.parentNode)
				ul.parentNode.classList.remove('active');
		}

		slide_menu.classList.add('active');
		a.classList.add('active');
		slide_menu.style.display = 'block';

		if (slide)
			slide.classList.add('active');

		a.blur();
	},

	renderMainMenu: function (tree, url, level) {
		var l = (level || 0) + 1,
			ul = E(
				'ul',
				{
					'class': level ? 'slide-menu' : 'nav'
				}
			),
			children = ui.menu.getChildren(tree);

		if (children.length == 0 || l > 2)
			return E([]);

		for (var i = 0; i < children.length; i++) {
			var isActive = (
				(L.env.dispatchpath[l] == children[i].name) &&
				(L.env.dispatchpath[l - 1] == tree.name)
			);

			var submenu = this.renderMainMenu(
				children[i],
				url + '/' + children[i].name,
				l
			);

			var hasChildren = submenu.children.length;

			var slideClass = hasChildren
				? 'slide'
				: null;

			var menuClass = hasChildren
				? 'menu'
				: null;

			if (isActive) {
				ul.classList.add('active');

				if (slideClass)
					slideClass += ' active';

				if (menuClass)
					menuClass += ' active';
			}

			ul.appendChild(
				E(
					'li',
					{
						'class': slideClass
					},
					[
						E(
							'a',
							{
								'href': L.url(
									url,
									children[i].name
								),

								'click': (
									l == 1
										? ui.createHandlerFn(
											this,
											'handleMenuExpand'
										)
										: null
								),

								'class': menuClass,

								'data-title':
									children[i].title.replace(
										" ",
										"_"
									)
							},
							[
								_(children[i].title)
							]
						),

						submenu
					]
				)
			);
		}

		if (l == 1) {
			var mainmenu =
				document.querySelector('#mainmenu');

			if (mainmenu) {
				mainmenu.appendChild(ul);
				mainmenu.style.display = '';
			}
		}

		return ul;
	},

	renderTabMenu: function (tree, url, level) {
		var container =
				document.querySelector('#tabmenu'),

			l =
				(level || 0) + 1,

			ul =
				E(
					'ul',
					{
						'class': 'tabs'
					}
				),

			children =
				ui.menu.getChildren(tree),

			activeNode =
				null;

		if (!container)
			return E([]);

		if (children.length == 0)
			return E([]);

		for (var i = 0; i < children.length; i++) {
			var isActive = (
				L.env.dispatchpath[l + 2] ==
				children[i].name
			);

			var activeClass =
				isActive
					? ' active'
					: '';

			var className =
				'tabmenu-item-%s %s'.format(
					children[i].name,
					activeClass
				);

			ul.appendChild(
				E(
					'li',
					{
						'class': className
					},
					[
						E(
							'a',
							{
								'href': L.url(
									url,
									children[i].name
								)
							},
							[
								_(children[i].title)
							]
						)
					]
				)
			);

			if (isActive)
				activeNode = children[i];
		}

		container.appendChild(ul);
		container.style.display = '';

		if (activeNode) {
			container.appendChild(
				this.renderTabMenu(
					activeNode,
					url + '/' + activeNode.name,
					l
				)
			);
		}

		return ul;
	},

	handleSidebarToggle: function (ev) {
		var showside =
				document.querySelector('a.showSide'),

			sidebar =
				document.querySelector('#mainmenu'),

			darkmask =
				document.querySelector('.darkMask'),

			scrollbar =
				document.querySelector('.main-right');

		if (!showside ||
			!sidebar ||
			!darkmask ||
			!scrollbar)
			return;

		if (showside.classList.contains('active')) {
			showside.classList.remove('active');
			sidebar.classList.remove('active');
			scrollbar.classList.remove('active');
			darkmask.classList.remove('active');
		}
		else {
			showside.classList.add('active');
			sidebar.classList.add('active');
			scrollbar.classList.add('active');
			darkmask.classList.add('active');
		}
	}
});
OPENPRO_MENU_ARGON_EOF


    if [ ! -s "$MENU_TMP" ]; then

        _theme_warn \
            "Argon 21.x 菜单修复文件生成失败"

        return 0

    fi


    if ! cp -f \
        "$MENU_TMP" \
        "$MENU_FILE" \
        >>"$THEME_LOG" 2>&1
    then

        _theme_warn \
            "Argon 21.x 菜单修复写入失败"

        return 0

    fi


    chmod \
        644 \
        "$MENU_FILE" \
        >>"$THEME_LOG" 2>&1


    ARGON_MENU_FIX_APPLIED=1


    _theme_ok \
        "已应用 Argon 21.x 菜单折叠修复"


    return 0
}


# ============================================================
# QuickStart Verify
#
# 关键修复：
#
# quickstart
# luci-app-quickstart
#
# 两个软件包都已安装，即视为 QuickStart 安装成功。
#
# LuCI 文件路径因不同 OpenWrt / GL.iNet / iStoreOS
# 可能不同，所以不再作为强制失败条件。
# ============================================================

verify_quickstart_install()
{
    QUICKSTART_CORE_OK=0
    QUICKSTART_LUCI_OK=0
    QUICKSTART_FILE_OK=0


    # ========================================================
    # quickstart 本体
    # ========================================================

    if package_installed "quickstart"; then

        QUICKSTART_CORE_OK=1

    fi


    # ========================================================
    # luci-app-quickstart
    # ========================================================

    if package_installed "luci-app-quickstart"; then

        QUICKSTART_LUCI_OK=1

    fi


    # ========================================================
    # 两个包均已安装
    #
    # 这是主要成功条件
    # ========================================================

    if [ "$QUICKSTART_CORE_OK" = "1" ] &&
       [ "$QUICKSTART_LUCI_OK" = "1" ]
    then

        return 0

    fi


    # ========================================================
    # LuCI 文件辅助检查
    # ========================================================

    if ls \
        /usr/share/luci/menu.d/*quickstart* \
        >/dev/null 2>&1
    then

        QUICKSTART_FILE_OK=1

    fi


    if [ -f /usr/lib/lua/luci/controller/quickstart.lua ] ||
       [ -d /usr/lib/lua/luci/controller/quickstart ]
    then

        QUICKSTART_FILE_OK=1

    fi


    if [ -d /www/luci-static/resources/view/quickstart ]; then

        QUICKSTART_FILE_OK=1

    fi


    if find \
        /www/luci-static/resources \
        -type f \
        -iname '*quickstart*' \
        -print \
        -quit \
        2>/dev/null |
        grep -q .
    then

        QUICKSTART_FILE_OK=1

    fi


    # ========================================================
    # luci-app 包 + 实际 LuCI 文件
    # ========================================================

    if [ "$QUICKSTART_LUCI_OK" = "1" ] &&
       [ "$QUICKSTART_FILE_OK" = "1" ]
    then

        return 0

    fi


    return 1
}


# ============================================================
# 下载 LinkEase 官方 is-opkg
#
# 复用 Argon 首次 GH01-GH06 + DIRECT 测速结果
# 不重新测速
# 下载失败自动切换下一线路
# DIRECT 最终兜底
# ============================================================

ensure_is_opkg()
{
    IS_OPKG_BIN="${THEME_TMP}/is-opkg"

    _theme_info "正在下载 LinkEase 官方 is-opkg..."

    rm -f "$IS_OPKG_BIN"

    DOWNLOAD_SUCCESS=0
    DIRECT_TRIED=0


    # ========================================================
    # 优先复用 Argon 首次测速排序
    # ========================================================

    if [ -s "$THEME_ROUTE_FILE" ]; then

        while IFS='|' read -r \
            ROUTE_SCORE \
            ROUTE_NAME \
            ROUTE_PREFIX \
            ROUTE_TEST_URL \
            ROUTE_TTFB \
            ROUTE_SPEED
        do

            [ -n "$ROUTE_NAME" ] ||
                continue

            if [ "$ROUTE_NAME" = "DIRECT" ]; then
                DIRECT_TRIED=1
            fi


            DOWNLOAD_URL="$(
                build_theme_url \
                    "$ROUTE_PREFIX" \
                    "$IS_OPKG_URL"
            )"


            [ -n "$DOWNLOAD_URL" ] ||
                continue


            _theme_info "正在使用线路：$ROUTE_NAME"


            rm -f "$IS_OPKG_BIN"


            if command -v curl >/dev/null 2>&1; then

                curl \
                    -4 \
                    -L \
                    -f \
                    -sS \
                    --connect-timeout 4 \
                    --max-time 20 \
                    --retry 0 \
                    -H "User-Agent: Open-Pro-Installer" \
                    -o "$IS_OPKG_BIN" \
                    "$DOWNLOAD_URL" \
                    >>"$THEME_LOG" 2>&1

                RESULT=$?

            else

                wget \
                    -T 10 \
                    -O "$IS_OPKG_BIN" \
                    "$DOWNLOAD_URL" \
                    >>"$THEME_LOG" 2>&1

                RESULT=$?

            fi


            if [ "$RESULT" -eq 0 ] &&
               [ -s "$IS_OPKG_BIN" ]
            then

                # 防止代理返回 HTML 错误页
                if ! head -c 512 "$IS_OPKG_BIN" 2>/dev/null |
                    grep -Eqi \
                    '<html|<!doctype|404 not found|bad gateway|502 bad gateway|403 forbidden|cloudflare'
                then

                    chmod 755 \
                        "$IS_OPKG_BIN" \
                        >>"$THEME_LOG" 2>&1 || {

                            rm -f "$IS_OPKG_BIN"

                            continue
                        }


                    _theme_ok "is-opkg 下载线路：$ROUTE_NAME"

                    DOWNLOAD_SUCCESS=1

                    break

                fi

            fi


            rm -f "$IS_OPKG_BIN"


            _theme_warn "$ROUTE_NAME 下载失败，切换下一线路..."


        done < "$THEME_ROUTE_FILE"

    fi


    # ========================================================
    # 如果没有测速缓存或所有缓存线路失败
    # DIRECT 最终兜底
    # ========================================================

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] &&
       [ "$DIRECT_TRIED" -ne 1 ]
    then

        _theme_info "正在尝试 GitHub 官方直连..."


        rm -f "$IS_OPKG_BIN"


        if command -v curl >/dev/null 2>&1; then

            curl \
                -4 \
                -L \
                -f \
                -sS \
                --connect-timeout 4 \
                --max-time 20 \
                --retry 0 \
                -H "User-Agent: Open-Pro-Installer" \
                -o "$IS_OPKG_BIN" \
                "$IS_OPKG_URL" \
                >>"$THEME_LOG" 2>&1

            RESULT=$?

        else

            wget \
                -T 10 \
                -O "$IS_OPKG_BIN" \
                "$IS_OPKG_URL" \
                >>"$THEME_LOG" 2>&1

            RESULT=$?

        fi


        if [ "$RESULT" -eq 0 ] &&
           [ -s "$IS_OPKG_BIN" ]
        then

            if ! head -c 512 "$IS_OPKG_BIN" 2>/dev/null |
                grep -Eqi \
                '<html|<!doctype|404 not found|bad gateway|502 bad gateway|403 forbidden|cloudflare'
            then

                chmod 755 \
                    "$IS_OPKG_BIN" \
                    >>"$THEME_LOG" 2>&1


                if [ $? -eq 0 ]; then

                    _theme_ok "is-opkg GitHub 官方直连下载成功"

                    DOWNLOAD_SUCCESS=1

                fi

            fi

        fi

    fi


    # ========================================================
    # 最终验证
    # ========================================================

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] ||
       [ ! -s "$IS_OPKG_BIN" ] ||
       [ ! -x "$IS_OPKG_BIN" ]
    then

        rm -f "$IS_OPKG_BIN"

        _theme_error "is-opkg 下载失败"

        return 1

    fi


    return 0
}


# ============================================================
# QuickStart Repo
# ============================================================

select_quickstart_repo()
{
    case "$PKG_MANAGER" in

        apk)

            QUICKSTART_ORIGIN_BASE="https://istore.istoreos.com/repo-apk"

            QUICKSTART_MIRROR_BASE="https://repo.istoreos.com/repo-apk"

            QUICKSTART_INDEX_PATH="/all/meta.conf"

            ;;


        opkg)

            QUICKSTART_ORIGIN_BASE="https://istore.istoreos.com/repo"

            QUICKSTART_MIRROR_BASE="https://repo.istoreos.com/repo"

            QUICKSTART_INDEX_PATH="/all/meta.conf"

            ;;


        *)

            _theme_error \
                "无法为 QuickStart 选择软件源"

            return 1

            ;;

    esac


    _theme_info \
        "QuickStart策略 : OpenWrt ${OPENWRT_MAJOR}.x / $PKG_MANAGER"


    _theme_info \
        "QuickStart格式 : .$ARGON_PACKAGE_TYPE"


    return 0
}


# ============================================================
# QuickStart Source Test
#
# 修复：
#
# TTFB_MS not found
# SPEED_INT not found
# 1000000 not found
# ============================================================

test_quickstart_source()
{
    TEST_URL="$1"
    TEST_FILE="$2"


    rm -f "$TEST_FILE"


    command -v curl >/dev/null 2>&1 ||
        return 1


    CURL_DATA="$(
        curl \
            -4 \
            -L \
            -sS \
            --connect-timeout "$THEME_TEST_CONNECT_TIMEOUT" \
            --max-time "$THEME_TEST_MAX_TIME" \
            -o "$TEST_FILE" \
            -w '%{http_code}|%{time_starttransfer}|%{speed_download}|%{size_download}' \
            "$TEST_URL" \
            2>/dev/null
    )"


    CURL_CODE=$?


    HTTP_CODE="$(
        printf '%s' "$CURL_DATA" |
        cut -d '|' -f 1
    )"


    TTFB="$(
        printf '%s' "$CURL_DATA" |
        cut -d '|' -f 2
    )"


    SPEED_BPS="$(
        printf '%s' "$CURL_DATA" |
        cut -d '|' -f 3
    )"


    SIZE_DOWN="$(
        printf '%s' "$CURL_DATA" |
        cut -d '|' -f 4
    )"


    case "$CURL_CODE" in

        0|28)
            ;;

        *)

            rm -f "$TEST_FILE"

            return 1

            ;;

    esac


    case "$HTTP_CODE" in

        200|206)
            ;;

        *)

            rm -f "$TEST_FILE"

            return 1

            ;;

    esac


    case "$SIZE_DOWN" in

        ''|*[!0-9.]*)

            RECEIVED_BYTES=0

            ;;

        *)

            RECEIVED_BYTES="${SIZE_DOWN%%.*}"


            RECEIVED_BYTES="$(
                printf '%s' "$RECEIVED_BYTES" |
                sed 's/^0*//'
            )"


            [ -n "$RECEIVED_BYTES" ] ||
                RECEIVED_BYTES=0

            ;;

    esac


    [ "$RECEIVED_BYTES" -gt 0 ] || {

        rm -f "$TEST_FILE"

        return 1

    }


    if theme_test_is_error_page "$TEST_FILE"; then

        rm -f "$TEST_FILE"

        return 1

    fi


    TTFB_MS="$(
        theme_seconds_to_ms \
            "$TTFB"
    )"


    case "$TTFB_MS" in

        ''|*[!0-9]*)

            TTFB_MS=999999

            ;;

    esac


    case "$SPEED_BPS" in

        ''|*[!0-9.]*)

            SPEED_INT=0

            ;;

        *)

            SPEED_INT="${SPEED_BPS%%.*}"


            SPEED_INT="$(
                printf '%s' "$SPEED_INT" |
                sed 's/^0*//'
            )"


            [ -n "$SPEED_INT" ] ||
                SPEED_INT=0

            ;;

    esac


    if [ "$SPEED_INT" -le 0 ]; then

        SPEED_INT=1

    fi


    # ========================================================
    # BusyBox /bin/sh 正确算术
    # ========================================================

    DOWNLOAD_SCORE=$((1000000 / SPEED_INT))


    SCORE=$((TTFB_MS + DOWNLOAD_SCORE))


    rm -f "$TEST_FILE"


    printf '%s|%s|%s' \
        "$TTFB_MS" \
        "$SPEED_INT" \
        "$SCORE"


    return 0
}


# ============================================================
# QuickStart Background Test
# ============================================================

test_quickstart_source_background()
{
    SOURCE_NAME="$1"
    SOURCE_BASE="$2"
    RESULT_FILE="$3"
    TEST_FILE="$4"


    TEST_URL="${SOURCE_BASE}${QUICKSTART_INDEX_PATH}"


    TEST_DATA="$(
        test_quickstart_source \
            "$TEST_URL" \
            "$TEST_FILE"
    )"


    if [ $? -ne 0 ] ||
       [ -z "$TEST_DATA" ]
    then

        printf '%s|FAIL\n' \
            "$SOURCE_NAME" \
            > "$RESULT_FILE"

        return 1

    fi


    TTFB_MS="$(
        printf '%s' "$TEST_DATA" |
        cut -d '|' -f 1
    )"


    SPEED_BPS="$(
        printf '%s' "$TEST_DATA" |
        cut -d '|' -f 2
    )"


    SCORE="$(
        printf '%s' "$TEST_DATA" |
        cut -d '|' -f 3
    )"


    printf '%s|OK|%s|%s|%s|%s\n' \
        "$SOURCE_NAME" \
        "$SOURCE_BASE" \
        "$TTFB_MS" \
        "$SPEED_BPS" \
        "$SCORE" \
        > "$RESULT_FILE"


    return 0
}


# ============================================================
# Prepare QuickStart Sources
# ============================================================

prepare_quickstart_sources()
{
    select_quickstart_repo ||
        return 1


    rm -rf \
        "$QUICKSTART_SOURCE_DIR"


    rm -f \
        "$QUICKSTART_SOURCE_FILE"


    mkdir -p \
        "$QUICKSTART_SOURCE_DIR" ||
        return 1


    printf "\n"


    _theme_info \
        "正在并行测试 QuickStart 软件源..."


    printf "\n"


    test_quickstart_source_background \
        "MIRROR" \
        "$QUICKSTART_MIRROR_BASE" \
        "$QUICKSTART_SOURCE_DIR/result_MIRROR" \
        "$QUICKSTART_SOURCE_DIR/download_MIRROR" &


    test_quickstart_source_background \
        "ORIGIN" \
        "$QUICKSTART_ORIGIN_BASE" \
        "$QUICKSTART_SOURCE_DIR/result_ORIGIN" \
        "$QUICKSTART_SOURCE_DIR/download_ORIGIN" &


    wait


    printf '%-10s %-12s %-14s\n' \
        "线路" \
        "延迟" \
        "下载速度"


    printf '%-10s %-12s %-14s\n' \
        "----------" \
        "------------" \
        "--------------"


    for SOURCE_NAME in \
        MIRROR \
        ORIGIN
    do

        RESULT_FILE="$QUICKSTART_SOURCE_DIR/result_${SOURCE_NAME}"


        if [ ! -s "$RESULT_FILE" ] ||
           [ "$(cut -d '|' -f 2 "$RESULT_FILE")" != "OK" ]
        then

            printf '%-10s %-12s %-14s\n' \
                "$SOURCE_NAME" \
                "----" \
                "----"

            continue

        fi


        SOURCE_BASE="$(
            cut -d '|' -f 3 \
                "$RESULT_FILE"
        )"


        TTFB_MS="$(
            cut -d '|' -f 4 \
                "$RESULT_FILE"
        )"


        SPEED_BPS="$(
            cut -d '|' -f 5 \
                "$RESULT_FILE"
        )"


        SCORE="$(
            cut -d '|' -f 6 \
                "$RESULT_FILE"
        )"


        SPEED_MB="$(
            theme_speed_to_mb \
                "$SPEED_BPS"
        )"


        printf '%-10s %-12s %-14s\n' \
            "$SOURCE_NAME" \
            "${TTFB_MS} ms" \
            "${SPEED_MB} MB/s"


        printf '%s|%s|%s|%s|%s\n' \
            "$SCORE" \
            "$SOURCE_NAME" \
            "$SOURCE_BASE" \
            "$TTFB_MS" \
            "$SPEED_BPS" \
            >> "$QUICKSTART_SOURCE_FILE"

    done


    rm -rf \
        "$QUICKSTART_SOURCE_DIR"


    if [ ! -s "$QUICKSTART_SOURCE_FILE" ]; then

        _theme_warn \
            "QuickStart 软件源测速全部失败，将使用 LinkEase 官方默认策略"


        QUICKSTART_SELECTED_BASE=""

        QUICKSTART_FALLBACK_BASE=""


        return 0

    fi


    sort \
        -n \
        -t '|' \
        -k 1,1 \
        "$QUICKSTART_SOURCE_FILE" \
        > "${QUICKSTART_SOURCE_FILE}.sorted"


    if [ -s "${QUICKSTART_SOURCE_FILE}.sorted" ]; then

        mv \
            "${QUICKSTART_SOURCE_FILE}.sorted" \
            "$QUICKSTART_SOURCE_FILE"

    fi


    BEST_LINE="$(
        sed -n '1p' \
            "$QUICKSTART_SOURCE_FILE"
    )"


    BEST_NAME="$(
        printf '%s' "$BEST_LINE" |
        cut -d '|' -f 2
    )"


    QUICKSTART_SELECTED_BASE="$(
        printf '%s' "$BEST_LINE" |
        cut -d '|' -f 3
    )"


    BEST_TTFB="$(
        printf '%s' "$BEST_LINE" |
        cut -d '|' -f 4
    )"


    BEST_SPEED="$(
        printf '%s' "$BEST_LINE" |
        cut -d '|' -f 5
    )"


    if [ "$QUICKSTART_SELECTED_BASE" = "$QUICKSTART_MIRROR_BASE" ]; then

        QUICKSTART_FALLBACK_BASE="$QUICKSTART_ORIGIN_BASE"

    else

        QUICKSTART_FALLBACK_BASE="$QUICKSTART_MIRROR_BASE"

    fi


    printf "\n"


    _theme_ok \
        "QuickStart 最佳线路：$BEST_NAME"


    _theme_info \
        "延迟：${BEST_TTFB} ms"


    _theme_info \
        "下载速度：$(theme_speed_to_mb "$BEST_SPEED") MB/s"


    printf "\n"


    return 0
}


# ============================================================
# Patch is-opkg
# ============================================================

patch_is_opkg_source()
{
    [ -n "$IS_OPKG_BIN" ] ||
        return 1


    [ -x "$IS_OPKG_BIN" ] ||
        return 1


    if [ -z "$QUICKSTART_SELECTED_BASE" ] ||
       [ -z "$QUICKSTART_FALLBACK_BASE" ]
    then

        return 0

    fi


    cp -f \
        "$IS_OPKG_BIN" \
        "$QUICKSTART_PATCHED_IS_OPKG" \
        >>"$THEME_LOG" 2>&1 ||
        return 1


    case "$PKG_MANAGER" in

        apk)

            sed \
                -e "s#^FEEDS_SERVER=https://istore\\.istoreos\\.com/repo-apk\$#FEEDS_SERVER=${QUICKSTART_SELECTED_BASE}#" \
                -e "s#^FEEDS_SERVER_MIRRORS=\"https://repo\\.istoreos\\.com/repo-apk\"\$#FEEDS_SERVER_MIRRORS=\"${QUICKSTART_SELECTED_BASE} ${QUICKSTART_FALLBACK_BASE}\"#" \
                "$QUICKSTART_PATCHED_IS_OPKG" \
                > "${QUICKSTART_PATCHED_IS_OPKG}.tmp" ||
                return 1

            ;;


        opkg)

            sed \
                -e "s#^FEEDS_SERVER=https://istore\\.istoreos\\.com/repo\$#FEEDS_SERVER=${QUICKSTART_SELECTED_BASE}#" \
                -e "s#^FEEDS_SERVER_MIRRORS=\"https://repo\\.istoreos\\.com/repo\"\$#FEEDS_SERVER_MIRRORS=\"${QUICKSTART_SELECTED_BASE} ${QUICKSTART_FALLBACK_BASE}\"#" \
                "$QUICKSTART_PATCHED_IS_OPKG" \
                > "${QUICKSTART_PATCHED_IS_OPKG}.tmp" ||
                return 1

            ;;


        *)

            return 1

            ;;

    esac


    mv \
        "${QUICKSTART_PATCHED_IS_OPKG}.tmp" \
        "$QUICKSTART_PATCHED_IS_OPKG" ||
        return 1


    chmod \
        755 \
        "$QUICKSTART_PATCHED_IS_OPKG" ||
        return 1


    IS_OPKG_BIN="$QUICKSTART_PATCHED_IS_OPKG"


    _theme_info \
        "QuickStart 下载源：$QUICKSTART_SELECTED_BASE"


    _theme_info \
        "QuickStart 备用源：$QUICKSTART_FALLBACK_BASE"


    return 0
}


# ============================================================
# QuickStart Online Version
# ============================================================

get_quickstart_online_version()
{
    [ -n "$IS_OPKG_BIN" ] ||
        return 0


    [ -x "$IS_OPKG_BIN" ] ||
        return 0


    "$IS_OPKG_BIN" \
        info \
        luci-app-quickstart \
        2>/dev/null |
        sed -n \
        's/^Version:[[:space:]]*//p' |
        head -n 1
}


# ============================================================
# QuickStart Installed Version
# ============================================================

get_quickstart_installed_version()
{
    case "$PKG_MANAGER" in

        opkg)

            opkg status \
                luci-app-quickstart \
                2>/dev/null |
                sed -n \
                's/^Version:[[:space:]]*//p' |
                head -n 1

            ;;


        apk)

            apk query \
                --installed \
                --fields version \
                luci-app-quickstart \
                2>/dev/null |
                sed -n \
                's/^Version:[[:space:]]*//p' |
                head -n 1

            ;;

    esac
}


# ============================================================
# QuickStart Config
# ============================================================

apply_quickstart_config()
{
    verify_quickstart_install || {

        _theme_warn \
            "QuickStart 尚未真正安装，跳过配置写入"

        return 1

    }


    rm -f \
        "$QUICKSTART_CONFIG_TMP"


    if ! download_direct \
        "$QUICKSTART_CONFIG_URL" \
        "$QUICKSTART_CONFIG_TMP"
    then

        _theme_warn \
            "QuickStart 风格配置下载失败，保留默认配置"

        return 0

    fi


    if [ -f /etc/config/quickstart ] &&
       [ ! -f "$QUICKSTART_CONFIG_BAK" ]
    then

        cp -f \
            /etc/config/quickstart \
            "$QUICKSTART_CONFIG_BAK" \
            >>"$THEME_LOG" 2>&1

    fi


    cp -f \
        "$QUICKSTART_CONFIG_TMP" \
        /etc/config/quickstart \
        >>"$THEME_LOG" 2>&1 || {

            _theme_warn \
                "QuickStart 配置写入失败"

            return 0

        }


    if ! uci -q \
        show quickstart \
        >/dev/null 2>&1
    then

        _theme_warn \
            "QuickStart 配置与当前版本不兼容"


        if [ -f "$QUICKSTART_CONFIG_BAK" ]; then

            cp -f \
                "$QUICKSTART_CONFIG_BAK" \
                /etc/config/quickstart \
                >>"$THEME_LOG" 2>&1

        fi


        return 0

    fi


    _theme_ok \
        "QuickStart iStoreOS 风格配置已应用"


    return 0
}

# ============================================================
# Install QuickStart
#
# 优化版：
# 1. 已安装则直接跳过索引更新和安装
# 2. 只执行一次 is-opkg update
# 3. 避免失败后重复 update
# 4. 优先安装中文包，由 is-opkg 自动解决依赖
# 5. OPKG 失败才进入 --force-depends
# 6. 每一步完成后立即验证，避免无意义重复安装
# ============================================================

install_quickstart()
{
    printf \
        "\n===== QuickStart Install =====\n" \
        >>"$THEME_LOG"


    # ========================================================
    # 第一优先：检查是否已经安装
    #
    # 已安装的机器不再：
    # 下载 is-opkg
    # 测速软件源
    # 更新索引
    # 重装 QuickStart
    # ========================================================

    if verify_quickstart_install; then

        _theme_ok \
            "首页 + 网络向导已安装，跳过安装"


        theme_progress \
            86 \
            "正在配置首页和网络向导..."


        printf "\n"


        apply_quickstart_config


        return 0

    fi


    # ========================================================
    # 获取 is-opkg
    # ========================================================

    if ! ensure_is_opkg; then

        _theme_error \
            "无法获取 QuickStart 安装工具"

        return 1

    fi


    # ========================================================
    # QuickStart 软件源测速
    # ========================================================

    prepare_quickstart_sources


    # ========================================================
    # 应用最快源
    # ========================================================

    if ! patch_is_opkg_source; then

        _theme_warn \
            "QuickStart 最快源应用失败，使用 LinkEase 官方默认策略"


        IS_OPKG_BIN="${THEME_TMP}/is-opkg"

    fi


    # ========================================================
    # 更新索引
    #
    # 整个安装过程只执行一次
    # ========================================================

    theme_progress \
        70 \
        "正在更新 QuickStart 索引..."


    printf "\n"


    UPDATE_OK=0


    if "$IS_OPKG_BIN" \
        update \
        >>"$THEME_LOG" 2>&1
    then

        UPDATE_OK=1

    else

        _theme_warn \
            "QuickStart 索引更新失败，继续尝试安装"

    fi


    # ========================================================
    # 获取在线版本
    # ========================================================

    QUICKSTART_ONLINE_VERSION="$(
        get_quickstart_online_version
    )"


    [ -n "$QUICKSTART_ONLINE_VERSION" ] &&
        _theme_info \
            "QuickStart版本 : $QUICKSTART_ONLINE_VERSION"


    _theme_info \
        "匹配软件包    : quickstart"


    _theme_info \
        "匹配软件包    : luci-app-quickstart"


    _theme_info \
        "匹配中文包    : luci-i18n-quickstart-zh-cn"


    # ========================================================
    # 安装
    # ========================================================

    theme_progress \
        78 \
        "正在安装首页和网络向导..."


    printf "\n"


    # ========================================================
    # 第一次正常安装
    #
    # luci-i18n-quickstart-zh-cn 会自动拉取：
    #
    # quickstart
    # luci-app-quickstart
    #
    # 所以只需要安装中文包
    # ========================================================

    "$IS_OPKG_BIN" \
        install \
        luci-i18n-quickstart-zh-cn \
        >>"$THEME_LOG" 2>&1


    INSTALL_RESULT=$?


    # ========================================================
    # 第一时间检查实际安装状态
    #
    # is-opkg 某些系统可能返回非 0，
    # 但实际上软件已经安装成功。
    # ========================================================

    if verify_quickstart_install; then

        INSTALL_RESULT=0

    fi


    # ========================================================
    # OPKG 兼容模式
    #
    # 只有真正没有安装成功才执行
    # ========================================================

    if [ "$INSTALL_RESULT" -ne 0 ] &&
       ! verify_quickstart_install
    then

        case "$PKG_MANAGER" in

            opkg)

                _theme_warn \
                    "普通安装未完成，尝试 OPKG 兼容模式"


                "$IS_OPKG_BIN" \
                    install \
                    luci-i18n-quickstart-zh-cn \
                    --force-depends \
                    >>"$THEME_LOG" 2>&1

                ;;


            apk)

                _theme_warn \
                    "APK 普通安装未完成，直接重试安装"


                # 不再重新执行 update
                "$IS_OPKG_BIN" \
                    install \
                    luci-i18n-quickstart-zh-cn \
                    >>"$THEME_LOG" 2>&1

                ;;

        esac

    fi


    # ========================================================
    # Final Verify
    # ========================================================

    if ! verify_quickstart_install; then

        _theme_error \
            "QuickStart 安装验证失败"


        return 1

    fi


    # ========================================================
    # 配置
    # ========================================================

    theme_progress \
        86 \
        "正在配置首页和网络向导..."


    printf "\n"


    apply_quickstart_config


    # ========================================================
    # 清理 LuCI Cache
    # ========================================================

    rm -rf \
        /tmp/luci-indexcache \
        /tmp/luci-modulecache \
        /tmp/luci-templatecache \
        /tmp/luci-*cache* \
        >/dev/null 2>&1


    _theme_ok \
        "首页 + 网络向导安装成功"


    return 0
}


# ============================================================
# Refresh LuCI
# ============================================================

refresh_theme_luci()
{
    rm -rf \
        /tmp/luci-indexcache \
        /tmp/luci-modulecache \
        /tmp/luci-templatecache \
        /tmp/luci-*cache* \
        >/dev/null 2>&1


    if [ -x /etc/init.d/rpcd ]; then

        /etc/init.d/rpcd \
            restart \
            >>"$THEME_LOG" 2>&1

    fi


    if [ -x /etc/init.d/uhttpd ]; then

        /etc/init.d/uhttpd \
            restart \
            >>"$THEME_LOG" 2>&1

    fi


    return 0
}


# ============================================================
# Main
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

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _theme_error \
            "请使用 root 用户运行"

        return 1

    fi


    cleanup_theme_all


    THEME_ROUTE_CACHE_READY=0

    THEME_ROUTE_CACHE_URL=""


    mkdir -p \
        "$THEME_TMP" || {

            _theme_error \
                "无法创建临时目录"

            return 1
        }


    touch \
        "$THEME_LOG"


    trap \
        'theme_interrupt' \
        INT TERM


    # ========================================================
    # Environment
    # ========================================================

    theme_progress \
        5 \
        "正在检测运行环境..."


    printf "\n"


    if ! check_theme_runtime; then

        printf "\n"

        return 1

    fi


    if ! detect_package_manager; then

        printf "\n"


        _theme_error \
            "未找到 OPKG / APK"


        return 1

    fi


    if ! detect_theme_system; then

        printf "\n"

        return 1

    fi


    if ! select_argon_compat; then

        printf "\n"

        return 1

    fi


    if ! check_theme_disk_space; then

        printf "\n"

        return 1

    fi


    printf "\n"


    # ========================================================
    # Argon
    # ========================================================

    theme_progress \
        15 \
        "正在获取兼容 Argon..."


    printf "\n"


    if ! install_argon_official; then

        printf "\n"


        _theme_error \
            "Argon 安装失败"


        restore_bootstrap_theme


        show_theme_error_log


        cleanup_theme_temp


        trap - INT TERM


        return 1

    fi


    # ========================================================
    # Argon Default
    # ========================================================

    theme_progress \
        64 \
        "正在设置 Argon 默认主题..."


    if ! set_argon_default; then

        printf "\n"


        _theme_error \
            "Argon 默认主题设置失败"


        restore_bootstrap_theme


        show_theme_error_log


        cleanup_theme_temp


        trap - INT TERM


        return 1

    fi


    printf "\n"


    apply_argon21_menu_fix


    # ========================================================
    # QuickStart
    # ========================================================

    theme_progress \
        67 \
        "正在准备首页和网络向导..."


    printf "\n"


    QUICKSTART_INSTALL_OK=0


    if install_quickstart; then

        QUICKSTART_INSTALL_OK=1

    else

        printf "\n"


        # 再做一次真实软件包检查
        if verify_quickstart_install; then

            QUICKSTART_INSTALL_OK=1

            _theme_ok \
                "QuickStart 已确认实际安装成功"

        else

            _theme_warn \
                "Argon 已安装，但 QuickStart 安装失败"

        fi

    fi


    # ========================================================
    # LuCI
    # ========================================================

    theme_progress \
        93 \
        "正在刷新 LuCI..."


    refresh_theme_luci


    # ========================================================
    # Argon Final Verify
    # ========================================================

    theme_progress \
        97 \
        "正在进行最终验证..."


    if ! verify_argon_install; then

        printf "\n"


        _theme_error \
            "Argon 最终验证失败"


        restore_bootstrap_theme


        show_theme_error_log


        cleanup_theme_temp


        trap - INT TERM


        return 1

    fi


    # ========================================================
    # Final
    # ========================================================

    theme_progress \
        100 \
        "iStoreOS 风格安装完成"


    printf "\n\n"


    ARGON_INSTALLED_VERSION="$(
        get_package_version \
            luci-theme-argon
    )"


    QUICKSTART_VERSION="$(
        get_quickstart_installed_version
    )"


    _theme_ok \
        "Argon 主题安装成功"


    if verify_quickstart_install; then

        _theme_ok \
            "首页 + 网络向导安装成功"

    else

        _theme_warn \
            "首页 + 网络向导未通过最终验证"

    fi


# ============================================================
# 安装完成详细信息
# 已隐藏
# ============================================================

# _theme_info "OpenWrt       : $OPENWRT_VERSION"
# _theme_info "包管理器      : $PKG_MANAGER"
# _theme_info "软件包架构    : $PKG_ARCH"
# _theme_info "软件包格式    : .$ARGON_PACKAGE_TYPE"

# [ -n "$ARGON_RELEASE_TAG" ] &&
#     _theme_info "Argon Release  : $ARGON_RELEASE_TAG"

# [ -n "$ARGON_INSTALLED_VERSION" ] &&
#     _theme_info "Argon Version  : $ARGON_INSTALLED_VERSION"

# [ -n "$QUICKSTART_VERSION" ] &&
#     _theme_info "QuickStart     : $QUICKSTART_VERSION"

# _theme_info "Argon 来源     : jerrykuku 官方 GitHub Release"
# _theme_info "Argon 下载     : GH01-GH06 + DIRECT 自动测速"

    _theme_info \
        "已设置 Argon 为默认 LuCI 主题"


    [ "$ARGON_MENU_FIX_APPLIED" = "1" ] &&
        _theme_info \
            "Argon 菜单    : 已应用 OpenWrt 21.x 折叠修复"


    _theme_info \
        "如页面未更新，请 Ctrl+F5 强制刷新或重新登录 LuCI"


    printf "\n"


    cleanup_theme_temp


    trap - INT TERM


    rm -f \
        "$THEME_LOG" \
        2>/dev/null


    return 0
}

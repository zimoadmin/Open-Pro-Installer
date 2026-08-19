#!/bin/sh

# ============================================================
# Open-Pro-Installer
# iStoreOS / Argon Theme + QuickStart Installer
#
# 功能：
# 1. 自动检测 OpenWrt / 设备 / CPU / OPKG 精确架构
# 2. Argon 使用 jerrykuku 官方 GitHub Release
# 3. GitHub API 永远 DIRECT，不经过 GH01-GH06
# 4. 自动读取 latest Release，自动匹配真实 IPK Asset
# 5. Argon Release 文件使用 GH01-GH06 + DIRECT 并行测速
# 6. 最快线路失败后自动切换下一线路
# 7. 自动安装 Argon Theme / Argon Config / 可选中文包
# 8. 自动设置 Argon 为默认 LuCI 主题
# 9. 自动安装 QuickStart：首页 + 网络向导 + 中文语言包
# 10. QuickStart 使用 LinkEase iStore 官方 is-opkg
# 11. 不修改 /etc/opkg/customfeeds.conf
# 12. 自动备份并应用 iStoreOS 风格 QuickStart 配置
# 13. 自动清理 LuCI 缓存并重启 rpcd / uhttpd
# 14. 失败保留 /tmp/openpro-theme.log，成功自动清理
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

ARGON_RELEASE_API="https://api.github.com/repos/jerrykuku/luci-theme-argon/releases/latest"
ARGON_RELEASE_JSON="${THEME_TMP}/argon_release.json"
ARGON_ASSET_LIST="${THEME_TMP}/argon_assets.list"

ARGON_RELEASE_TAG=""
ARGON_THEME_URL=""
ARGON_CONFIG_URL=""
ARGON_LANG_URL=""

ARGON_THEME_FILE="${THEME_TMP}/argon-theme.ipk"
ARGON_CONFIG_FILE="${THEME_TMP}/argon-config.ipk"
ARGON_LANG_FILE="${THEME_TMP}/argon-lang.ipk"

IS_OPKG_URL="https://raw.githubusercontent.com/linkease/istore/main/luci/luci-app-store/root/bin/is-opkg"
IS_OPKG_BIN=""

QUICKSTART_CONFIG_URL="https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/config/quickstart"
QUICKSTART_CONFIG_TMP="${THEME_TMP}/quickstart.conf"
QUICKSTART_CONFIG_BAK="/etc/config/quickstart.openpro.bak"

MODEL=""
CPU_ARCH=""
PKG_ARCH=""
OPENWRT_VERSION=""

THEME_ROUTE_FILE="/tmp/openpro_theme_routes"
THEME_SORTED_FILE="/tmp/openpro_theme_routes.sorted"
THEME_TEST_DIR="/tmp/openpro_theme_speedtest.d"

THEME_TEST_CONNECT_TIMEOUT=4
THEME_TEST_MAX_TIME=6
THEME_SCORE_FILE_KB=4096

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

    while [ "$I" -lt "$FILLED" ]; do
        BAR="${BAR}#"
        I=$((I + 1))
    done

    I=0

    while [ "$I" -lt "$EMPTY" ]; do
        BAR="${BAR}-"
        I=$((I + 1))
    done

    printf \
        "\r\033[2K${GREEN}[INFO]${RESET} %-24s [${GREEN}%s${RESET}] %3d%%" \
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
    printf "%b\n" "${RED}========== ERROR LOG ==========${RESET}"

    if [ -s "$THEME_LOG" ]; then
        tail -n 100 "$THEME_LOG"
    else
        printf "没有可用错误日志\n"
    fi

    printf "%b\n" "${RED}===============================${RESET}"
    printf "\n"
}


# ============================================================
# 清理
# ============================================================

cleanup_theme_temp()
{
    rm -rf "$THEME_TMP" "$THEME_TEST_DIR" 2>/dev/null
    rm -f "$THEME_ROUTE_FILE" "$THEME_SORTED_FILE" 2>/dev/null
    return 0
}

cleanup_theme_all()
{
    cleanup_theme_temp
    rm -f "$THEME_LOG" 2>/dev/null
    return 0
}


# ============================================================
# Ctrl+C
# ============================================================

theme_interrupt()
{
    printf "\n"
    _theme_warn "iStoreOS 风格安装已中断"
    _theme_info "安装日志保留在：$THEME_LOG"

    cleanup_theme_temp

    trap - INT TERM

    return 130
}


# ============================================================
# 环境检测
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
        cut \
        tr \
        sort \
        basename \
        cp \
        rm \
        mkdir \
        chmod \
        df \
        uci
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


detect_theme_system()
{
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        OPENWRT_VERSION="${DISTRIB_RELEASE:-unknown}"
    else
        OPENWRT_VERSION="unknown"
    fi

    MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"
    [ -n "$MODEL" ] || MODEL="Unknown"

    CPU_ARCH="$(uname -m 2>/dev/null)"
    [ -n "$CPU_ARCH" ] || CPU_ARCH="Unknown"

    PKG_ARCH="$(
        opkg print-architecture 2>/dev/null |
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

    [ -n "$PKG_ARCH" ] || PKG_ARCH="Unknown"

    _theme_info "OpenWrt版本 : $OPENWRT_VERSION"
    _theme_info "设备型号    : $MODEL"
    _theme_info "CPU架构     : $CPU_ARCH"
    _theme_info "软件包架构  : $PKG_ARCH"
    _theme_info "包管理器    : opkg"

    return 0
}


check_theme_disk_space()
{
    FREE_KB="$(
        df -k / 2>/dev/null |
        awk 'END {print $4}'
    )"

    case "$FREE_KB" in
        ''|*[!0-9]*) FREE_KB=0 ;;
    esac

    FREE_MB=$((FREE_KB / 1024))

    _theme_info "可用空间    : ${FREE_MB} MB"

    if [ "$FREE_MB" -lt 15 ]; then
        _theme_error "可用空间不足，建议至少保留 15 MB"
        return 1
    fi

    return 0
}


# ============================================================
# 通用 DIRECT 下载
#
# API / is-opkg / QuickStart 配置全部走 DIRECT
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

    elif command -v wget >/dev/null 2>&1; then

        wget \
            -T 30 \
            --header="User-Agent: Open-Pro-Installer" \
            -O "$OUTPUT" \
            "$URL" \
            >>"$THEME_LOG" 2>&1

        RESULT=$?

    else
        printf "curl/wget not found\n" >>"$THEME_LOG"
        return 1
    fi

    if [ "$RESULT" -ne 0 ] || [ ! -s "$OUTPUT" ]; then
        rm -f "$OUTPUT"
        return 1
    fi

    if head -c 512 "$OUTPUT" 2>/dev/null |
       grep -Eqi '<html|<!doctype|404 not found|bad gateway|502 bad gateway|403 forbidden|cloudflare'
    then
        printf "Invalid response: %s\n" "$URL" >>"$THEME_LOG"
        rm -f "$OUTPUT"
        return 1
    fi

    return 0
}


# ============================================================
# 包检测
# ============================================================

package_installed()
{
    PACKAGE_NAME="$1"

    opkg status "$PACKAGE_NAME" 2>/dev/null |
        grep -q 'Status:.*installed'
}


get_package_version()
{
    PACKAGE_NAME="$1"

    opkg status "$PACKAGE_NAME" 2>/dev/null |
        sed -n 's/^Version:[[:space:]]*//p' |
        head -n 1
}


# ============================================================
# Argon Release API
#
# GitHub API 永远 DIRECT。
# ============================================================

fetch_argon_release()
{
    rm -f "$ARGON_RELEASE_JSON" "$ARGON_ASSET_LIST"

    _theme_info "正在直连 GitHub API 获取 Argon 最新版本..."

    if ! download_direct \
        "$ARGON_RELEASE_API" \
        "$ARGON_RELEASE_JSON"
    then
        _theme_error "Argon 官方 GitHub API 获取失败"
        return 1
    fi

    # 优先 jsonfilter，老系统没有时使用 sed 兜底。
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

    [ -n "$ARGON_RELEASE_TAG" ] || {
        _theme_error "无法解析 Argon Release 版本"
        return 1
    }

    [ -s "$ARGON_ASSET_LIST" ] || {
        _theme_error "无法解析 Argon Release Assets"
        return 1
    }

    ARGON_THEME_URL="$(
        grep '/luci-theme-argon_[^/]*\.ipk$' \
            "$ARGON_ASSET_LIST" |
        head -n 1
    )"

    ARGON_CONFIG_URL="$(
        grep '/luci-app-argon-config_[^/]*\.ipk$' \
            "$ARGON_ASSET_LIST" |
        head -n 1
    )"

    ARGON_LANG_URL="$(
        grep '/luci-i18n-argon-config-zh-cn_[^/]*\.ipk$' \
            "$ARGON_ASSET_LIST" |
        head -n 1
    )"

    [ -n "$ARGON_THEME_URL" ] || {
        _theme_error "官方 Release 中未找到 luci-theme-argon IPK"
        return 1
    }

    [ -n "$ARGON_CONFIG_URL" ] || {
        _theme_error "官方 Release 中未找到 luci-app-argon-config IPK"
        return 1
    }

    _theme_ok "Argon 官方最新版本：$ARGON_RELEASE_TAG"
    _theme_info "Theme  : $(basename "$ARGON_THEME_URL")"
    _theme_info "Config : $(basename "$ARGON_CONFIG_URL")"

    if [ -n "$ARGON_LANG_URL" ]; then
        _theme_info "中文包 : $(basename "$ARGON_LANG_URL")"
    else
        _theme_warn "官方 Release 未提供独立 Argon 中文包，将自动跳过"
    fi

    return 0
}


# ============================================================
# GH01-GH06 + DIRECT 智能下载
# ============================================================

build_theme_url()
{
    PREFIX="$1"
    ORIGINAL_URL="$2"

    if [ -z "$PREFIX" ]; then
        printf '%s' "$ORIGINAL_URL"
    else
        printf '%s%s' "$PREFIX" "$ORIGINAL_URL"
    fi
}


theme_seconds_to_ms()
{
    awk -v t="$1" '
        BEGIN {
            if (t == "" || t !~ /^[0-9.]+$/) {
                print 999999
            } else {
                printf "%d", t * 1000
            }
        }
    '
}


theme_speed_to_mb()
{
    awk -v s="$1" '
        BEGIN {
            if (s == "" || s <= 0) {
                printf "0.00"
            } else {
                printf "%.2f", s / 1024 / 1024
            }
        }
    '
}


theme_calculate_score()
{
    awk \
        -v t="$1" \
        -v s="$2" \
        -v kb="$THEME_SCORE_FILE_KB" '
        BEGIN {
            if (s <= 0) {
                print 999999999
                exit
            }

            speed_kb = s / 1024
            printf "%d", t + (kb / speed_kb) * 1000
        }
    '
}


theme_test_is_error_page()
{
    FILE="$1"

    [ -s "$FILE" ] || return 1

    head -c 1024 "$FILE" 2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
}


test_theme_route()
{
    TEST_URL="$1"
    TEST_FILE="$2"

    rm -f "$TEST_FILE"

    command -v curl >/dev/null 2>&1 || return 1

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

    HTTP_CODE="$(printf '%s' "$CURL_DATA" | cut -d '|' -f 1)"
    TTFB="$(printf '%s' "$CURL_DATA" | cut -d '|' -f 2)"
    SPEED_BPS="$(printf '%s' "$CURL_DATA" | cut -d '|' -f 3)"
    SIZE_DOWN="$(printf '%s' "$CURL_DATA" | cut -d '|' -f 4)"

    case "$CURL_CODE" in
        0|28) ;;
        *)
            rm -f "$TEST_FILE"
            return 1
        ;;
    esac

    case "$HTTP_CODE" in
        200|206) ;;
        *)
            rm -f "$TEST_FILE"
            return 1
        ;;
    esac

    RECEIVED_BYTES="$(
        awk -v n="$SIZE_DOWN" '
            BEGIN {
                if (n + 0 > 0) {
                    printf "%d", n
                } else {
                    print 0
                }
            }
        '
    )"

    [ "$RECEIVED_BYTES" -ge 2048 ] || {
        rm -f "$TEST_FILE"
        return 1
    }

    if theme_test_is_error_page "$TEST_FILE"; then
        rm -f "$TEST_FILE"
        return 1
    fi

    TTFB_MS="$(theme_seconds_to_ms "$TTFB")"

    SPEED_INT="$(
        awk -v s="$SPEED_BPS" '
            BEGIN {
                if (s > 0) {
                    printf "%d", s
                } else {
                    print 0
                }
            }
        '
    )"

    [ "$SPEED_INT" -gt 0 ] || {
        rm -f "$TEST_FILE"
        return 1
    }

    SCORE="$(theme_calculate_score "$TTFB_MS" "$SPEED_INT")"

    rm -f "$TEST_FILE"

    printf '%s|%s|%s' \
        "$TTFB_MS" \
        "$SPEED_INT" \
        "$SCORE"

    return 0
}


test_theme_route_background()
{
    NODE_NAME="$1"
    NODE_PREFIX="$2"
    ORIGINAL_URL="$3"
    RESULT_FILE="$4"
    TEST_FILE="$5"

    TEST_URL="$(build_theme_url "$NODE_PREFIX" "$ORIGINAL_URL")"

    TEST_DATA="$(test_theme_route "$TEST_URL" "$TEST_FILE")"

    if [ $? -ne 0 ] || [ -z "$TEST_DATA" ]; then
        printf '%s|FAIL\n' "$NODE_NAME" > "$RESULT_FILE"
        return 1
    fi

    TTFB_MS="$(printf '%s' "$TEST_DATA" | cut -d '|' -f 1)"
    SPEED_BPS="$(printf '%s' "$TEST_DATA" | cut -d '|' -f 2)"
    SCORE="$(printf '%s' "$TEST_DATA" | cut -d '|' -f 3)"

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


prepare_theme_routes()
{
    ORIGINAL_URL="$1"

    rm -f "$THEME_ROUTE_FILE" "$THEME_SORTED_FILE"
    rm -rf "$THEME_TEST_DIR"

    mkdir -p "$THEME_TEST_DIR" || return 1

    printf "\n"
    _theme_info "正在并行测试 Argon 下载线路..."
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
            printf '%s\n' "$THEME_DOWNLOAD_NODES" |
            awk -F '|' -v n="$NODE_NAME" '
                $1 == n {
                    print $2
                    exit
                }
            '
        )"

        test_theme_route_background \
            "$NODE_NAME" \
            "$NODE_PREFIX" \
            "$ORIGINAL_URL" \
            "$THEME_TEST_DIR/result_${NODE_NAME}" \
            "$THEME_TEST_DIR/download_${NODE_NAME}" &
    done

    wait

    printf '%-8s %-12s %-14s %s\n' \
        "线路" \
        "首包" \
        "下载速度" \
        "状态"

    printf '%-8s %-12s %-14s %s\n' \
        "--------" \
        "------------" \
        "--------------" \
        "------"

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
            printf '%-8s %-12s %-14s \033[1;91m%s\033[0m\n' \
                "$NODE_NAME" \
                "----" \
                "----" \
                "不可用"

            continue
        fi

        NODE_PREFIX="$(cut -d '|' -f 3 "$RESULT_FILE")"
        TEST_URL="$(cut -d '|' -f 4 "$RESULT_FILE")"
        TTFB_MS="$(cut -d '|' -f 5 "$RESULT_FILE")"
        SPEED_BPS="$(cut -d '|' -f 6 "$RESULT_FILE")"
        SCORE="$(cut -d '|' -f 7 "$RESULT_FILE")"

        SPEED_MB="$(theme_speed_to_mb "$SPEED_BPS")"

        printf '%-8s %-12s %-14s \033[1;92m%s\033[0m\n' \
            "$NODE_NAME" \
            "${TTFB_MS} ms" \
            "${SPEED_MB} MB/s" \
            "可用"

        printf '%s|%s|%s|%s|%s|%s\n' \
            "$SCORE" \
            "$NODE_NAME" \
            "$NODE_PREFIX" \
            "$TEST_URL" \
            "$TTFB_MS" \
            "$SPEED_BPS" \
            >> "$THEME_ROUTE_FILE"
    done

    rm -rf "$THEME_TEST_DIR"

    [ -s "$THEME_ROUTE_FILE" ] || {
        _theme_warn "没有发现可用测速线路"
        return 1
    }

    sort \
        -n \
        -t '|' \
        -k 1,1 \
        "$THEME_ROUTE_FILE" \
        > "$THEME_SORTED_FILE" \
        2>/dev/null

    if [ -s "$THEME_SORTED_FILE" ]; then
        mv "$THEME_SORTED_FILE" "$THEME_ROUTE_FILE"
    else
        rm -f "$THEME_SORTED_FILE"
    fi

    BEST_LINE="$(sed -n '1p' "$THEME_ROUTE_FILE")"

    BEST_NAME="$(printf '%s' "$BEST_LINE" | cut -d '|' -f 2)"
    BEST_TTFB="$(printf '%s' "$BEST_LINE" | cut -d '|' -f 5)"
    BEST_SPEED="$(printf '%s' "$BEST_LINE" | cut -d '|' -f 6)"

    printf "\n"
    _theme_ok "最佳线路：$BEST_NAME"
    _theme_info "首包时间：${BEST_TTFB} ms"
    _theme_info "下载速度：$(theme_speed_to_mb "$BEST_SPEED") MB/s"
    printf "\n"

    return 0
}


smart_download_release()
{
    ORIGINAL_URL="$1"
    OUTPUT="$2"

    DOWNLOAD_SUCCESS=0
    DIRECT_TRIED=0

    prepare_theme_routes "$ORIGINAL_URL"

    if [ -s "$THEME_ROUTE_FILE" ]; then

        while IFS='|' read -r \
            ROUTE_SCORE \
            ROUTE_NAME \
            ROUTE_PREFIX \
            ROUTE_URL \
            ROUTE_TTFB \
            ROUTE_SPEED
        do
            [ -n "$ROUTE_NAME" ] || continue
            [ -n "$ROUTE_URL" ] || continue

            if [ "$ROUTE_NAME" = "DIRECT" ]; then
                DIRECT_TRIED=1
            fi

            _theme_info "正在使用线路：$ROUTE_NAME"
            _theme_info "测速速度：$(theme_speed_to_mb "$ROUTE_SPEED") MB/s"

            if download_direct "$ROUTE_URL" "$OUTPUT"; then
                _theme_ok "下载线路：$ROUTE_NAME"
                DOWNLOAD_SUCCESS=1
                break
            fi

            _theme_warn "$ROUTE_NAME 下载失败，自动切换下一线路..."

        done < "$THEME_ROUTE_FILE"

    fi

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] &&
       [ "$DIRECT_TRIED" -ne 1 ]
    then
        _theme_info "正在尝试 GitHub 官方直连..."

        if download_direct "$ORIGINAL_URL" "$OUTPUT"; then
            _theme_ok "GitHub 官方直连下载成功"
            DOWNLOAD_SUCCESS=1
        fi
    fi

    rm -f "$THEME_ROUTE_FILE" "$THEME_SORTED_FILE"

    [ "$DOWNLOAD_SUCCESS" -eq 1 ]
}


# ============================================================
# Argon 安装
# ============================================================

verify_argon_install()
{
    if package_installed "luci-theme-argon"; then
        return 0
    fi

    if [ -d /www/luci-static/argon ]; then
        return 0
    fi

    return 1
}


install_argon_official()
{
    if ! fetch_argon_release; then
        return 1
    fi

    theme_progress 28 "正在下载官方 Argon..."

    if ! smart_download_release \
        "$ARGON_THEME_URL" \
        "$ARGON_THEME_FILE"
    then
        printf "\n"
        _theme_error "Argon 官方主题包下载失败"
        return 1
    fi

    theme_progress 42 "正在下载 Argon Config..."

    if ! smart_download_release \
        "$ARGON_CONFIG_URL" \
        "$ARGON_CONFIG_FILE"
    then
        printf "\n"
        _theme_error "Argon 官方 Config 下载失败"
        return 1
    fi

    rm -f "$ARGON_LANG_FILE"

    if [ -n "$ARGON_LANG_URL" ]; then

        theme_progress 50 "正在下载 Argon 中文包..."

        if ! smart_download_release \
            "$ARGON_LANG_URL" \
            "$ARGON_LANG_FILE"
        then
            printf "\n"
            _theme_warn "Argon 中文包下载失败，将继续安装主题"
            rm -f "$ARGON_LANG_FILE"
        fi

    fi

    theme_progress 58 "正在安装官方 Argon..."

    printf "\n===== Official Argon Install =====\n" \
        >> "$THEME_LOG"

    if [ -s "$ARGON_LANG_FILE" ]; then

        opkg install \
            "$ARGON_THEME_FILE" \
            "$ARGON_CONFIG_FILE" \
            "$ARGON_LANG_FILE" \
            >>"$THEME_LOG" 2>&1

    else

        opkg install \
            "$ARGON_THEME_FILE" \
            "$ARGON_CONFIG_FILE" \
            >>"$THEME_LOG" 2>&1

    fi

    INSTALL_RESULT=$?

    if [ "$INSTALL_RESULT" -ne 0 ] &&
       ! verify_argon_install
    then
        printf "\n"
        _theme_error "Argon 官方主题安装失败"
        return 1
    fi

    if ! verify_argon_install; then
        printf "\n"
        _theme_error "Argon 安装后验证失败"
        return 1
    fi

    _theme_ok "Argon 官方主题安装成功"

    return 0
}


set_argon_default()
{
    if ! verify_argon_install; then
        return 1
    fi

    uci set luci.main.theme='argon' \
        >>"$THEME_LOG" 2>&1

    uci set luci.main.mediaurlbase='/luci-static/argon' \
        >>"$THEME_LOG" 2>&1

    uci commit luci \
        >>"$THEME_LOG" 2>&1

    return 0
}


# ============================================================
# QuickStart
# ============================================================

verify_quickstart_install()
{
    package_installed "quickstart" || return 1
    package_installed "luci-app-quickstart" || return 1
    package_installed "luci-i18n-quickstart-zh-cn" || return 1

    return 0
}


ensure_is_opkg()
{
    IS_OPKG_BIN=""

    if command -v is-opkg >/dev/null 2>&1; then
        IS_OPKG_BIN="$(command -v is-opkg)"
        return 0
    fi

    if [ -x /bin/is-opkg ]; then
        IS_OPKG_BIN="/bin/is-opkg"
        return 0
    fi

    if [ -x /usr/bin/is-opkg ]; then
        IS_OPKG_BIN="/usr/bin/is-opkg"
        return 0
    fi

    IS_OPKG_BIN="${THEME_TMP}/is-opkg"

    _theme_info "正在直连下载 iStore 官方 is-opkg..."

    if ! download_direct \
        "$IS_OPKG_URL" \
        "$IS_OPKG_BIN"
    then
        _theme_error "iStore 官方 is-opkg 下载失败"
        IS_OPKG_BIN=""
        return 1
    fi

    chmod 755 "$IS_OPKG_BIN" \
        >>"$THEME_LOG" 2>&1 || {
            IS_OPKG_BIN=""
            return 1
        }

    return 0
}


apply_quickstart_config()
{
    rm -f "$QUICKSTART_CONFIG_TMP" 2>/dev/null

    if ! download_direct \
        "$QUICKSTART_CONFIG_URL" \
        "$QUICKSTART_CONFIG_TMP"
    then
        _theme_warn "QuickStart iStoreOS 风格配置下载失败，保留插件默认配置"
        return 0
    fi

    if [ -f /etc/config/quickstart ] &&
       [ ! -f "$QUICKSTART_CONFIG_BAK" ]
    then
        cp -f \
            /etc/config/quickstart \
            "$QUICKSTART_CONFIG_BAK" \
            >>"$THEME_LOG" 2>&1 || true
    fi

    cp -f \
        "$QUICKSTART_CONFIG_TMP" \
        /etc/config/quickstart \
        >>"$THEME_LOG" 2>&1 || {
            _theme_warn "QuickStart 配置写入失败，保留现有配置"
            return 0
        }

    if ! uci -q show quickstart >/dev/null 2>&1; then

        _theme_warn "QuickStart 风格配置不兼容当前版本"

        if [ -f "$QUICKSTART_CONFIG_BAK" ]; then
            cp -f \
                "$QUICKSTART_CONFIG_BAK" \
                /etc/config/quickstart \
                >>"$THEME_LOG" 2>&1 || true

            _theme_warn "已恢复原 QuickStart 配置"
        fi

        return 0
    fi

    _theme_ok "QuickStart iStoreOS 风格配置已应用"

    return 0
}


install_quickstart()
{
    if verify_quickstart_install; then
        _theme_ok "首页 + 网络向导已安装"
        apply_quickstart_config
        return 0
    fi

    if ! ensure_is_opkg; then
        return 1
    fi

    printf "\n===== QuickStart Install =====\n" \
        >>"$THEME_LOG"

    theme_progress 70 "正在更新 QuickStart 索引..."

    "$IS_OPKG_BIN" update \
        >>"$THEME_LOG" 2>&1

    UPDATE_RESULT=$?

    if [ "$UPDATE_RESULT" -ne 0 ]; then
        _theme_warn "iStore 软件索引更新返回异常，继续尝试安装"
    fi

    theme_progress 78 "正在安装首页和网络向导..."

    "$IS_OPKG_BIN" install \
        luci-i18n-quickstart-zh-cn \
        >>"$THEME_LOG" 2>&1

    INSTALL_RESULT=$?

    if [ "$INSTALL_RESULT" -ne 0 ]; then

        printf "\n===== QuickStart Force Depends Retry =====\n" \
            >>"$THEME_LOG"

        "$IS_OPKG_BIN" install \
            luci-i18n-quickstart-zh-cn \
            --force-depends \
            >>"$THEME_LOG" 2>&1

        INSTALL_RESULT=$?
    fi

    if ! verify_quickstart_install; then
        printf \
            "QuickStart install return code: %s\n" \
            "$INSTALL_RESULT" \
            >>"$THEME_LOG"

        _theme_error "首页 + 网络向导安装失败"

        return 1
    fi

    theme_progress 86 "正在配置首页和网络向导..."

    apply_quickstart_config

    _theme_ok "首页 + 网络向导安装成功"

    return 0
}


# ============================================================
# LuCI 刷新
# ============================================================

refresh_theme_luci()
{
    rm -rf \
        /tmp/luci-indexcache \
        /tmp/luci-modulecache \
        /tmp/luci-*cache* \
        >/dev/null 2>&1

    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd restart \
            >>"$THEME_LOG" 2>&1
    fi

    if [ -x /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart \
            >>"$THEME_LOG" 2>&1
    fi

    return 0
}


# ============================================================
# 主安装函数
#
# install.sh:
# [1] 一键仿 iStoreOS 主题
#       ↓
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

    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        _theme_error "请使用 root 用户运行"
        return 1
    fi

    # ========================================================
    # OPKG
    # ========================================================

    if ! command -v opkg >/dev/null 2>&1; then

        if command -v apk >/dev/null 2>&1; then
            _theme_error "当前模块使用官方 Argon IPK / QuickStart OPKG，暂不支持 APK 系统"
        else
            _theme_error "未检测到 OPKG 包管理器"
        fi

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
    # 系统检测
    # ========================================================

    theme_progress 5 "正在检测运行环境..."

    if ! check_theme_runtime; then
        printf "\n"
        cleanup_theme_temp
        trap - INT TERM
        return 1
    fi

    if ! detect_theme_system; then
        printf "\n"
        cleanup_theme_temp
        trap - INT TERM
        return 1
    fi

    if ! check_theme_disk_space; then
        printf "\n"
        cleanup_theme_temp
        trap - INT TERM
        return 1
    fi

    printf "\n"

    # ========================================================
    # Argon
    # ========================================================

    theme_progress 15 "正在获取 Argon Release..."

    if ! install_argon_official; then

        printf "\n"
        _theme_error "官方 Argon 安装失败"
        show_theme_error_log

        cleanup_theme_temp

        trap - INT TERM

        return 1
    fi

    # ========================================================
    # 默认主题
    # ========================================================

    theme_progress 64 "正在设置 Argon 默认主题..."

    if ! set_argon_default; then

        printf "\n"
        _theme_error "Argon 默认主题设置失败"
        show_theme_error_log

        cleanup_theme_temp

        trap - INT TERM

        return 1
    fi

    # ========================================================
    # QuickStart
    # ========================================================

    theme_progress 67 "正在准备首页和网络向导..."

    if ! install_quickstart; then

        printf "\n"
        _theme_error "Argon 已安装，但首页 / 网络向导安装失败"
        show_theme_error_log

        cleanup_theme_temp

        trap - INT TERM

        return 1
    fi

    # ========================================================
    # LuCI
    # ========================================================

    theme_progress 93 "正在刷新 LuCI..."

    refresh_theme_luci

    # ========================================================
    # 最终验证
    # ========================================================

    theme_progress 97 "正在进行最终验证..."

    if ! verify_argon_install; then

        printf "\n"
        _theme_error "Argon 最终验证失败"
        show_theme_error_log

        cleanup_theme_temp

        trap - INT TERM

        return 1
    fi

    if ! verify_quickstart_install; then

        printf "\n"
        _theme_error "首页 / 网络向导最终验证失败"
        show_theme_error_log

        cleanup_theme_temp

        trap - INT TERM

        return 1
    fi

    # ========================================================
    # 完成
    # ========================================================

    theme_progress 100 "iStoreOS 风格安装完成"

    printf "\n\n"

    ARGON_INSTALLED_VERSION="$(
        get_package_version luci-theme-argon
    )"

    QUICKSTART_VERSION="$(
        get_package_version luci-app-quickstart
    )"

    cleanup_theme_temp

    trap - INT TERM

    _theme_ok "Argon 官方主题安装成功"
    _theme_ok "首页 + 网络向导安装成功"

    [ -n "$ARGON_RELEASE_TAG" ] &&
        _theme_info "Argon Release  : $ARGON_RELEASE_TAG"

    [ -n "$ARGON_INSTALLED_VERSION" ] &&
        _theme_info "Argon Version  : $ARGON_INSTALLED_VERSION"

    [ -n "$QUICKSTART_VERSION" ] &&
        _theme_info "QuickStart     : $QUICKSTART_VERSION"

    _theme_info "Argon 来源     : jerrykuku 官方 GitHub Release"
    _theme_info "GitHub API     : DIRECT 直连"
    _theme_info "Argon 下载     : GH01-GH06 + DIRECT 自动测速"
    _theme_info "QuickStart     : LinkEase iStore 官方软件源"
    _theme_info "已设置 Argon 为默认 LuCI 主题"
    _theme_info "LuCI 左侧菜单应出现：首页、网络向导"
    _theme_info "如页面未更新，请强制刷新浏览器或重新登录 LuCI"

    printf "\n"

    # 成功才删日志
    rm -f "$THEME_LOG" 2>/dev/null

    return 0
}

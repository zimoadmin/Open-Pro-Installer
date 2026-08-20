#!/bin/sh

# ============================================================
# Open-Pro-Installer
# SmartDNS Smart Installer
#
# 功能：
# 1. OpenWrt / OPKG / APK 自动识别
# 2. CPU 架构自动识别
# 3. GitHub 官方 Release API 获取最新版
# 4. 自动匹配 SmartDNS OpenWrt IPK/APK
# 5. 自动选择 LuCI / luci-compat
# 6. GH01-GH06 + DIRECT 并行测速
# 7. 自动选择最快下载线路
# 8. 总体单行进度条
# 9. 正常安装过程静默
# 10. 失败自动显示日志
# 11. 安装后刷新 LuCI
# 12. 不强制修改 DNS 53 端口
# 13. 修复旧 BusyBox awk 兼容问题
# 14. Release Asset 优先 jsonfilter 解析
#
# BusyBox / OpenWrt /bin/sh Compatible
# ============================================================

SMARTDNS_TMP="/tmp/openpro_smartdns"
SMARTDNS_LOG="/tmp/openpro_smartdns.log"
SMARTDNS_RELEASE_JSON="$SMARTDNS_TMP/release.json"
SMARTDNS_ASSET_LIST="$SMARTDNS_TMP/assets.list"

SMARTDNS_REPO="pymumu/smartdns"

SMARTDNS_VERSION=""
SMARTDNS_CPU=""
SMARTDNS_ARCH=""
SMARTDNS_ARCH_RAW=""
SMARTDNS_PKG_MANAGER=""
SMARTDNS_EXT=""

SMARTDNS_MAIN_URL=""
SMARTDNS_LUCI_URL=""

SMARTDNS_MAIN_FILE=""
SMARTDNS_LUCI_FILE=""

SMARTDNS_ROUTE_FILE="$SMARTDNS_TMP/routes"
SMARTDNS_TEST_DIR="$SMARTDNS_TMP/test"

SMARTDNS_WAS_RUNNING=0

SMARTDNS_NODES="
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
GH04|https://cdn.akaere.online/
GH05|https://github.mxw.qzz.io/
GH06|https://gh.07150721.xyz/
DIRECT|
"

_sd_info()
{
    printf '\033[1;92m[INFO]\033[0m %s\n' "$*"
}

_sd_ok()
{
    printf '\033[1;92m[OK]\033[0m %s\n' "$*"
}

_sd_warn()
{
    printf '\033[1;93m[WARN]\033[0m %s\n' "$*"
}

_sd_error()
{
    printf '\033[1;91m[ERROR]\033[0m %s\n' "$*"
}

smartdns_progress()
{
    PERCENT="$1"
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

    printf '\r\033[2K\033[1;92m[INFO]\033[0m 总体进度: [\033[1;92m%s\033[0m] %3d%%\033[K' \
        "$BAR" \
        "$PERCENT"
}

smartdns_show_log()
{
    printf '\n\n'
    printf '\033[1;91m========== SMARTDNS ERROR ==========\033[0m\n'

    if [ -s "$SMARTDNS_LOG" ]; then
        tail -n 100 "$SMARTDNS_LOG"
    else
        printf '没有可用错误日志\n'
    fi

    printf '\033[1;91m====================================\033[0m\n\n'
}

smartdns_cleanup()
{
    rm -rf "$SMARTDNS_TMP" 2>/dev/null
    rm -f /tmp/smartdns.ipk /tmp/smartdns_luci.ipk 2>/dev/null
}

smartdns_cleanup_all()
{
    smartdns_cleanup
    rm -f "$SMARTDNS_LOG" 2>/dev/null
}

smartdns_interrupt()
{
    printf '\n'
    _sd_warn "SmartDNS 安装已中断"

    if [ "$SMARTDNS_WAS_RUNNING" -eq 1 ] &&
       [ -x /etc/init.d/smartdns ]; then
        /etc/init.d/smartdns start >/dev/null 2>&1
    fi

    smartdns_cleanup
    trap - INT TERM

    return 130
}

smartdns_check_runtime()
{
    MISSING=""

    for CMD in awk sed grep cut sort head tail curl cp basename mkdir chmod cat df wc
    do
        command -v "$CMD" >/dev/null 2>&1 ||
            MISSING="$MISSING $CMD"
    done

    if [ -n "$MISSING" ]; then
        _sd_error "系统缺少必要命令:$MISSING"
        return 1
    fi

    return 0
}

smartdns_detect_system()
{
    if [ ! -f /etc/openwrt_release ]; then
        _sd_error "当前系统不是受支持的 OpenWrt"
        return 1
    fi

    . /etc/openwrt_release

    return 0
}

smartdns_detect_package_manager()
{
    if command -v apk >/dev/null 2>&1; then
        SMARTDNS_PKG_MANAGER="apk"
        SMARTDNS_EXT="apk"
    elif command -v opkg >/dev/null 2>&1; then
        SMARTDNS_PKG_MANAGER="opkg"
        SMARTDNS_EXT="ipk"
    else
        _sd_error "没有检测到 OPKG / APK"
        return 1
    fi

    return 0
}

smartdns_detect_arch()
{
    SMARTDNS_ARCH=""
    SMARTDNS_ARCH_RAW=""
    SMARTDNS_CPU="$(uname -m 2>/dev/null)"

    case "$SMARTDNS_CPU" in
        aarch64|arm64)
            SMARTDNS_ARCH="aarch64"
            ;;
        x86_64|amd64)
            SMARTDNS_ARCH="x86_64"
            ;;
        armv7*|armv6*|arm)
            SMARTDNS_ARCH="arm"
            ;;
        i386|i486|i586|i686)
            SMARTDNS_ARCH="i386"
            ;;
        mips64el*)
            SMARTDNS_ARCH="mips64el"
            ;;
        mips64*)
            SMARTDNS_ARCH="mips64"
            ;;
        mipsel*)
            SMARTDNS_ARCH="mipsel"
            ;;
        mips*)
            SMARTDNS_ARCH="mips"
            ;;
        *)
            _sd_error "暂不支持 CPU 架构：$SMARTDNS_CPU"
            return 1
            ;;
    esac

    if [ "$SMARTDNS_PKG_MANAGER" = "opkg" ]; then
        SMARTDNS_ARCH_RAW="$(
            opkg print-architecture 2>/dev/null |
            tail -n 1 |
            cut -d ' ' -f 2
        )"
    elif [ "$SMARTDNS_PKG_MANAGER" = "apk" ]; then
        SMARTDNS_ARCH_RAW="$(
            apk --print-arch 2>/dev/null |
            head -n 1
        )"
    fi

    return 0
}

smartdns_check_space()
{
    FREE_KB="$(
        df -k /usr 2>/dev/null |
        tail -n 1 |
        awk '{print $4}'
    )"

    case "$FREE_KB" in
        ''|*[!0-9]*)
            FREE_KB=0
            ;;
    esac

    FREE_MB=$((FREE_KB / 1024))

    if [ "$FREE_MB" -lt 25 ]; then
        _sd_error "可用空间不足，建议至少保留 25 MB"
        return 1
    fi

    return 0
}

smartdns_extract_assets()
{
    rm -f "$SMARTDNS_ASSET_LIST"

    if command -v jsonfilter >/dev/null 2>&1; then
        jsonfilter \
            -i "$SMARTDNS_RELEASE_JSON" \
            -e '@.assets[*].browser_download_url' \
            2>/dev/null \
            > "$SMARTDNS_ASSET_LIST"
    else
        grep '"browser_download_url"' "$SMARTDNS_RELEASE_JSON" |
            sed 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/' \
            > "$SMARTDNS_ASSET_LIST"
    fi

    [ -s "$SMARTDNS_ASSET_LIST" ]
}

smartdns_get_release()
{
    mkdir -p "$SMARTDNS_TMP" || return 1

    rm -f \
        "$SMARTDNS_RELEASE_JSON" \
        "$SMARTDNS_ASSET_LIST"

    if ! curl -4 \
        -L \
        -f \
        -sS \
        --connect-timeout 10 \
        --max-time 30 \
        -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: Open-Pro-Installer' \
        "https://api.github.com/repos/${SMARTDNS_REPO}/releases/latest" \
        -o "$SMARTDNS_RELEASE_JSON" \
        >>"$SMARTDNS_LOG" 2>&1
    then
        _sd_error "无法获取 SmartDNS 官方 Release"
        return 1
    fi

    if command -v jsonfilter >/dev/null 2>&1; then
        SMARTDNS_VERSION="$(
            jsonfilter \
                -i "$SMARTDNS_RELEASE_JSON" \
                -e '@.tag_name' \
                2>/dev/null
        )"
    else
        SMARTDNS_VERSION="$(
            grep '"tag_name"' "$SMARTDNS_RELEASE_JSON" |
            head -n 1 |
            sed 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/'
        )"
    fi

    if ! smartdns_extract_assets; then
        {
            printf '\n===== SMARTDNS RELEASE JSON =====\n'
            cat "$SMARTDNS_RELEASE_JSON"
            printf '\n=================================\n'
        } >>"$SMARTDNS_LOG"

        _sd_error "SmartDNS Release 中没有找到安装文件"
        return 1
    fi

    SMARTDNS_MAIN_URL="$(
        grep '/smartdns\.' "$SMARTDNS_ASSET_LIST" |
        grep "\.${SMARTDNS_ARCH}-openwrt-all\.${SMARTDNS_EXT}$" |
        head -n 1
    )"

    if [ -z "$SMARTDNS_MAIN_URL" ]; then
        SMARTDNS_MAIN_URL="$(
            grep -i 'smartdns' "$SMARTDNS_ASSET_LIST" |
            grep -vi 'luci-app-smartdns' |
            grep -i "$SMARTDNS_ARCH" |
            grep -i 'openwrt' |
            grep "\.${SMARTDNS_EXT}$" |
            head -n 1
        )"
    fi

    SMARTDNS_LUCI_URL=""

    if [ "$SMARTDNS_PKG_MANAGER" = "opkg" ]; then
        SMARTDNS_LUCI_URL="$(
            grep -i 'luci-app-smartdns' "$SMARTDNS_ASSET_LIST" |
            grep -i 'luci-compat' |
            grep '\.ipk$' |
            head -n 1
        )"

        if [ -z "$SMARTDNS_LUCI_URL" ]; then
            SMARTDNS_LUCI_URL="$(
                grep -i 'luci-app-smartdns' "$SMARTDNS_ASSET_LIST" |
                grep '\.ipk$' |
                grep -vi 'lite' |
                head -n 1
            )"
        fi
    else
        SMARTDNS_LUCI_URL="$(
            grep -i 'luci-app-smartdns' "$SMARTDNS_ASSET_LIST" |
            grep '\.apk$' |
            grep -vi 'lite' |
            head -n 1
        )"
    fi

    if [ -z "$SMARTDNS_MAIN_URL" ]; then
        {
            printf '\n===== SMARTDNS RELEASE DEBUG =====\n'
            printf 'CPU: %s\n' "$SMARTDNS_CPU"
            printf 'OpenWrt Arch: %s\n' "$SMARTDNS_ARCH_RAW"
            printf 'Release Arch: %s\n' "$SMARTDNS_ARCH"
            printf 'Package Manager: %s\n' "$SMARTDNS_PKG_MANAGER"
            printf 'Extension: %s\n\n' "$SMARTDNS_EXT"
            cat "$SMARTDNS_ASSET_LIST"
            printf '\n==================================\n'
        } >>"$SMARTDNS_LOG"

        _sd_error "没有找到当前架构的 SmartDNS 官方安装包"
        return 1
    fi

    if [ -z "$SMARTDNS_LUCI_URL" ]; then
        {
            printf '\n===== SMARTDNS LUCI DEBUG =====\n'
            cat "$SMARTDNS_ASSET_LIST"
            printf '\n===============================\n'
        } >>"$SMARTDNS_LOG"

        _sd_error "没有找到 SmartDNS LuCI 安装包"
        return 1
    fi

    SMARTDNS_MAIN_FILE="$SMARTDNS_TMP/smartdns.$SMARTDNS_EXT"
    SMARTDNS_LUCI_FILE="$SMARTDNS_TMP/luci-app-smartdns.$SMARTDNS_EXT"

    return 0
}

smartdns_build_url()
{
    PREFIX="$1"
    URL="$2"

    if [ -z "$PREFIX" ]; then
        printf '%s' "$URL"
    else
        printf '%s%s' "$PREFIX" "$URL"
    fi
}

smartdns_seconds_ms()
{
    awk -v t="$1" '
        BEGIN {
            if (t == "" || t !~ /^[0-9.]+$/)
                print 999999
            else
                printf "%d", t * 1000
        }
    '
}

smartdns_speed_mb()
{
    awk -v s="$1" '
        BEGIN {
            if (s <= 0)
                printf "0.00"
            else
                printf "%.2f", s / 1024 / 1024
        }
    '
}

smartdns_test_route()
{
    NAME="$1"
    PREFIX="$2"
    ORIGINAL="$3"
    RESULT="$4"

    URL="$(smartdns_build_url "$PREFIX" "$ORIGINAL")"

    DATA="$(
        curl -4 \
            -L \
            -sS \
            --connect-timeout 4 \
            --max-time 6 \
            -o /dev/null \
            -w '%{http_code}|%{time_starttransfer}|%{speed_download}' \
            "$URL" \
            2>/dev/null
    )"

    RC=$?

    if [ "$RC" -ne 0 ] &&
       [ "$RC" -ne 28 ]; then
        printf '%s|FAIL\n' "$NAME" >"$RESULT"
        return
    fi

    HTTP="$(printf '%s' "$DATA" | cut -d '|' -f1)"
    TTFB="$(printf '%s' "$DATA" | cut -d '|' -f2)"
    SPEED="$(printf '%s' "$DATA" | cut -d '|' -f3)"

    case "$HTTP" in
        200|206)
            ;;
        *)
            printf '%s|FAIL\n' "$NAME" >"$RESULT"
            return
            ;;
    esac

    TTFB_MS="$(smartdns_seconds_ms "$TTFB")"

    SPEED_INT="$(
        awk -v s="$SPEED" '
            BEGIN {
                if (s > 0)
                    printf "%d", s
                else
                    print 0
            }
        '
    )"

    if [ "$SPEED_INT" -le 0 ]; then
        printf '%s|FAIL\n' "$NAME" >"$RESULT"
        return
    fi

    SCORE="$(
        awk \
            -v t="$TTFB_MS" \
            -v s="$SPEED_INT" '
            BEGIN {
                if (s <= 0)
                    print 999999999
                else
                    printf "%d", t + (10485760 / s) * 1000
            }
        '
    )"

    printf '%s|OK|%s|%s|%s|%s\n' \
        "$NAME" \
        "$PREFIX" \
        "$TTFB_MS" \
        "$SPEED_INT" \
        "$SCORE" \
        >"$RESULT"
}

smartdns_prepare_routes()
{
    ORIGINAL="$1"

    rm -rf "$SMARTDNS_TEST_DIR"
    mkdir -p "$SMARTDNS_TEST_DIR" || return 1
    rm -f "$SMARTDNS_ROUTE_FILE"

    printf '\n\n'
    _sd_info "正在并行测试 SmartDNS 下载线路..."
    printf '\n'

    for NAME in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT
    do
        PREFIX="$(
            printf '%s\n' "$SMARTDNS_NODES" |
            awk -F '|' -v n="$NAME" '$1 == n { print $2; exit }'
        )"

        smartdns_test_route \
            "$NAME" \
            "$PREFIX" \
            "$ORIGINAL" \
            "$SMARTDNS_TEST_DIR/$NAME" &
    done

    wait

    printf '%-8s %-12s %-14s %s\n' \
        "线路" "首包" "下载速度" "状态"

    printf '%-8s %-12s %-14s %s\n' \
        "--------" "------------" "--------------" "------"

    for NAME in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT
    do
        FILE="$SMARTDNS_TEST_DIR/$NAME"

        if [ ! -s "$FILE" ] ||
           [ "$(cut -d '|' -f2 "$FILE")" != "OK" ]; then

            printf '%-8s %-12s %-14s \033[1;91m%s\033[0m\n' \
                "$NAME" \
                "----" \
                "----" \
                "不可用"

            continue
        fi

        PREFIX="$(cut -d '|' -f3 "$FILE")"
        TTFB="$(cut -d '|' -f4 "$FILE")"
        SPEED="$(cut -d '|' -f5 "$FILE")"
        SCORE="$(cut -d '|' -f6 "$FILE")"

        printf '%-8s %-12s %-14s \033[1;92m%s\033[0m\n' \
            "$NAME" \
            "${TTFB} ms" \
            "$(smartdns_speed_mb "$SPEED") MB/s" \
            "可用"

        printf '%s|%s|%s|%s|%s\n' \
            "$SCORE" \
            "$NAME" \
            "$PREFIX" \
            "$TTFB" \
            "$SPEED" \
            >>"$SMARTDNS_ROUTE_FILE"
    done

    rm -rf "$SMARTDNS_TEST_DIR"

    if [ ! -s "$SMARTDNS_ROUTE_FILE" ]; then
        _sd_warn "测速线路全部不可用，将尝试 GitHub 官方直连"
        printf '\n'
        return 1
    fi

    sort -n \
        -t '|' \
        -k1,1 \
        "$SMARTDNS_ROUTE_FILE" \
        >"$SMARTDNS_ROUTE_FILE.sorted"

    mv "$SMARTDNS_ROUTE_FILE.sorted" "$SMARTDNS_ROUTE_FILE"

    BEST="$(head -n 1 "$SMARTDNS_ROUTE_FILE")"
    BEST_NAME="$(printf '%s' "$BEST" | cut -d '|' -f2)"
    BEST_TTFB="$(printf '%s' "$BEST" | cut -d '|' -f4)"
    BEST_SPEED="$(printf '%s' "$BEST" | cut -d '|' -f5)"

    printf '\n'
    _sd_ok "最佳线路：$BEST_NAME"
    _sd_info "首包时间：${BEST_TTFB} ms"
    _sd_info "下载速度：$(smartdns_speed_mb "$BEST_SPEED") MB/s"
    printf '\n'

    return 0
}

smartdns_download_file()
{
    ORIGINAL="$1"
    OUTPUT="$2"

    rm -f "$OUTPUT"

    if [ -s "$SMARTDNS_ROUTE_FILE" ]; then
        while IFS='|' read -r SCORE NAME PREFIX TTFB SPEED
        do
            [ -n "$NAME" ] || continue

            URL="$(smartdns_build_url "$PREFIX" "$ORIGINAL")"

            if curl -4 \
                -L \
                -f \
                -sS \
                --connect-timeout 10 \
                --max-time 300 \
                --retry 1 \
                --retry-delay 1 \
                -o "$OUTPUT" \
                "$URL" \
                >>"$SMARTDNS_LOG" 2>&1
            then
                if [ -s "$OUTPUT" ]; then
                    return 0
                fi
            fi

            rm -f "$OUTPUT"

        done <"$SMARTDNS_ROUTE_FILE"
    fi

    if curl -4 \
        -L \
        -f \
        -sS \
        --connect-timeout 10 \
        --max-time 300 \
        --retry 1 \
        --retry-delay 1 \
        -o "$OUTPUT" \
        "$ORIGINAL" \
        >>"$SMARTDNS_LOG" 2>&1
    then
        [ -s "$OUTPUT" ] && return 0
    fi

    rm -f "$OUTPUT"

    return 1
}

smartdns_package_installed()
{
    case "$SMARTDNS_PKG_MANAGER" in
        opkg)
            opkg status "$1" 2>/dev/null |
                grep -q 'Status:.*installed'
            ;;
        apk)
            apk info -e "$1" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

smartdns_install_main()
{
    RC=1

    case "$SMARTDNS_PKG_MANAGER" in
        opkg)
            cp "$SMARTDNS_MAIN_FILE" /tmp/smartdns.ipk \
                >>"$SMARTDNS_LOG" 2>&1 ||
                return 1

            opkg install \
                --force-downgrade \
                /tmp/smartdns.ipk \
                >>"$SMARTDNS_LOG" 2>&1

            RC=$?

            rm -f /tmp/smartdns.ipk
            ;;

        apk)
            apk add \
                --allow-untrusted \
                "$SMARTDNS_MAIN_FILE" \
                >>"$SMARTDNS_LOG" 2>&1

            RC=$?
            ;;
    esac

    if [ "$RC" -ne 0 ] &&
       ! smartdns_package_installed smartdns; then
        return 1
    fi

    smartdns_package_installed smartdns
}

smartdns_install_luci()
{
    RC=1

    case "$SMARTDNS_PKG_MANAGER" in
        opkg)
            cp "$SMARTDNS_LUCI_FILE" /tmp/smartdns_luci.ipk \
                >>"$SMARTDNS_LOG" 2>&1 ||
                return 1

            opkg install \
                --force-downgrade \
                /tmp/smartdns_luci.ipk \
                >>"$SMARTDNS_LOG" 2>&1

            RC=$?

            rm -f /tmp/smartdns_luci.ipk
            ;;

        apk)
            apk add \
                --allow-untrusted \
                "$SMARTDNS_LUCI_FILE" \
                >>"$SMARTDNS_LOG" 2>&1

            RC=$?
            ;;
    esac

    if [ "$RC" -ne 0 ] &&
       ! smartdns_package_installed luci-app-smartdns; then
        return 1
    fi

    smartdns_package_installed luci-app-smartdns
}

smartdns_detect_running()
{
    SMARTDNS_WAS_RUNNING=0

    if [ -x /etc/init.d/smartdns ] &&
       /etc/init.d/smartdns status >/dev/null 2>&1; then
        SMARTDNS_WAS_RUNNING=1
    fi
}

smartdns_refresh_luci()
{
    rm -rf \
        /tmp/luci-indexcache \
        /tmp/luci-modulecache \
        /tmp/luci-*cache* \
        >/dev/null 2>&1

    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd restart \
            >>"$SMARTDNS_LOG" 2>&1
    fi

    if [ -x /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd reload \
            >>"$SMARTDNS_LOG" 2>&1
    fi
}

smartdns_verify()
{
    smartdns_package_installed smartdns || return 1
    smartdns_package_installed luci-app-smartdns || return 1
    command -v smartdns >/dev/null 2>&1 || return 1
    [ -x /etc/init.d/smartdns ] || return 1

    return 0
}

install_smartdns()
{
    printf '\n'
    printf '%b\n' '\033[1;94m╔══════════════════════════════════════╗\033[0m'
    printf '%b\n' '\033[1;94m║\033[1;92m        SmartDNS 一键安装             \033[1;94m║\033[0m'
    printf '%b\n' '\033[1;94m╚══════════════════════════════════════╝\033[0m'
    printf '\n'

    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        _sd_error "请使用 root 用户运行"
        return 1
    fi

    smartdns_cleanup_all

    mkdir -p "$SMARTDNS_TMP" || {
        _sd_error "无法创建临时目录"
        return 1
    }

    : >"$SMARTDNS_LOG"

    trap 'smartdns_interrupt' INT TERM

    smartdns_progress 5

    if ! smartdns_check_runtime ||
       ! smartdns_detect_system ||
       ! smartdns_detect_package_manager ||
       ! smartdns_detect_arch ||
       ! smartdns_check_space
    then
        printf '\n'
        smartdns_show_log
        smartdns_cleanup
        trap - INT TERM
        return 1
    fi

    smartdns_progress 15

    if ! smartdns_get_release; then
        printf '\n'
        smartdns_show_log
        smartdns_cleanup
        trap - INT TERM
        return 1
    fi

    smartdns_progress 25

    smartdns_prepare_routes "$SMARTDNS_MAIN_URL" ||
        true

    smartdns_progress 35

    if ! smartdns_download_file \
        "$SMARTDNS_MAIN_URL" \
        "$SMARTDNS_MAIN_FILE"
    then
        printf '\n'
        _sd_error "SmartDNS 主程序下载失败"
        smartdns_show_log
        smartdns_cleanup
        trap - INT TERM
        return 1
    fi

    smartdns_progress 50

    if ! smartdns_download_file \
        "$SMARTDNS_LUCI_URL" \
        "$SMARTDNS_LUCI_FILE"
    then
        printf '\n'
        _sd_error "SmartDNS LuCI 下载失败"
        smartdns_show_log
        smartdns_cleanup
        trap - INT TERM
        return 1
    fi

    smartdns_detect_running

    if [ -x /etc/init.d/smartdns ]; then
        /etc/init.d/smartdns stop >/dev/null 2>&1
    fi

    smartdns_progress 65

    if ! smartdns_install_main; then
        printf '\n'
        _sd_error "SmartDNS 主程序安装失败"
        smartdns_show_log

        if [ "$SMARTDNS_WAS_RUNNING" -eq 1 ] &&
           [ -x /etc/init.d/smartdns ]; then
            /etc/init.d/smartdns start >/dev/null 2>&1
        fi

        smartdns_cleanup
        trap - INT TERM
        return 1
    fi

    smartdns_progress 80

    if ! smartdns_install_luci; then
        printf '\n'
        _sd_error "SmartDNS LuCI 安装失败"
        smartdns_show_log
        smartdns_cleanup
        trap - INT TERM
        return 1
    fi

    smartdns_progress 90

    smartdns_refresh_luci

    if [ -x /etc/init.d/smartdns ]; then
        /etc/init.d/smartdns enable >/dev/null 2>&1

        /etc/init.d/smartdns restart \
            >>"$SMARTDNS_LOG" 2>&1 ||
            true
    fi

    smartdns_progress 97

    if ! smartdns_verify; then
        printf '\n'
        _sd_error "SmartDNS 最终验证失败"
        smartdns_show_log
        smartdns_cleanup
        trap - INT TERM
        return 1
    fi

    smartdns_progress 100
    printf '\n\n'

    smartdns_cleanup
    rm -f "$SMARTDNS_LOG" 2>/dev/null

    trap - INT TERM

    _sd_ok "SmartDNS 安装完成"
    printf '\n'

    return 0
}

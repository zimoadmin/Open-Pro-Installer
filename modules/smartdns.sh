#!/bin/sh

# ============================================================
# Open-Pro-Installer
# SmartDNS Smart Installer
#
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
#
# BusyBox / OpenWrt /bin/sh Compatible
# ============================================================


# ============================================================
# 基础变量
# ============================================================

SMARTDNS_TMP="/tmp/openpro_smartdns"
SMARTDNS_LOG="/tmp/openpro_smartdns.log"
SMARTDNS_RELEASE_JSON="$SMARTDNS_TMP/release.json"

SMARTDNS_REPO="pymumu/smartdns"

SMARTDNS_VERSION=""
SMARTDNS_ARCH=""
SMARTDNS_PKG_MANAGER=""
SMARTDNS_EXT=""

SMARTDNS_MAIN_URL=""
SMARTDNS_LUCI_URL=""

SMARTDNS_MAIN_FILE=""
SMARTDNS_LUCI_FILE=""

SMARTDNS_ROUTE_FILE="$SMARTDNS_TMP/routes"
SMARTDNS_TEST_DIR="$SMARTDNS_TMP/test"

SMARTDNS_WAS_RUNNING=0


# ============================================================
# 下载节点
# ============================================================

SMARTDNS_NODES="
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
GH04|https://cdn.akaere.online/
GH05|https://github.mxw.qzz.io/
GH06|https://gh.07150721.xyz/
DIRECT|
"


# ============================================================
# 输出
# ============================================================

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


# ============================================================
# 总进度条
# ============================================================

smartdns_progress()
{
    PERCENT="$1"

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
        "\r\033[2K\033[1;92m[INFO]\033[0m 总体进度: [\033[1;92m%s\033[0m] %3d%%" \
        "$BAR" \
        "$PERCENT"
}


# ============================================================
# 日志
# ============================================================

smartdns_show_log()
{
    printf '\n\n'

    printf '\033[1;91m========== SMARTDNS ERROR ==========\033[0m\n'

    if [ -s "$SMARTDNS_LOG" ]
    then
        tail -n 60 "$SMARTDNS_LOG"
    else
        printf '没有可用错误日志\n'
    fi

    printf '\033[1;91m====================================\033[0m\n\n'
}


# ============================================================
# 清理
# ============================================================

smartdns_cleanup()
{
    rm -rf "$SMARTDNS_TMP" 2>/dev/null
}


smartdns_cleanup_all()
{
    smartdns_cleanup

    rm -f "$SMARTDNS_LOG" 2>/dev/null
}


# ============================================================
# 中断
# ============================================================

smartdns_interrupt()
{
    printf '\n'

    _sd_warn "SmartDNS 安装已中断"

    if [ "$SMARTDNS_WAS_RUNNING" -eq 1 ] &&
       [ -x /etc/init.d/smartdns ]
    then
        /etc/init.d/smartdns start >/dev/null 2>&1
    fi

    smartdns_cleanup

    trap - INT TERM

    return 130
}


# ============================================================
# 环境
# ============================================================

smartdns_check_runtime()
{
    MISSING=""

    for CMD in \
        awk \
        sed \
        grep \
        cut \
        sort \
        head \
        tail \
        curl \
        cp \
        basename \
        mkdir \
        chmod \
        cat \
        df \
        wc
    do

        command -v "$CMD" >/dev/null 2>&1 ||
            MISSING="$MISSING $CMD"

    done


    if [ -n "$MISSING" ]
    then
        _sd_error "系统缺少必要命令:$MISSING"

        return 1
    fi


    return 0
}


# ============================================================
# OpenWrt
# ============================================================

smartdns_detect_system()
{
    if [ ! -f /etc/openwrt_release ]
    then
        _sd_error "当前系统不是受支持的 OpenWrt"

        return 1
    fi


    . /etc/openwrt_release


    _sd_info "OpenWrt Version : ${DISTRIB_RELEASE:-unknown}"

    _sd_info "OpenWrt Target  : ${DISTRIB_TARGET:-unknown}"


    return 0
}


# ============================================================
# 包管理器
# ============================================================

smartdns_detect_package_manager()
{
    if command -v apk >/dev/null 2>&1
    then

        SMARTDNS_PKG_MANAGER="apk"
        SMARTDNS_EXT="apk"

    elif command -v opkg >/dev/null 2>&1
    then

        SMARTDNS_PKG_MANAGER="opkg"
        SMARTDNS_EXT="ipk"

    else

        _sd_error "没有检测到 OPKG / APK"

        return 1

    fi


    _sd_info "Package Manager  : $SMARTDNS_PKG_MANAGER"

    _sd_info "Package Format   : .$SMARTDNS_EXT"


    return 0
}


# ============================================================
# CPU
#
# 官方 Release 使用：
#
# aarch64-openwrt-all
# x86_64-openwrt-all
# arm-openwrt-all
# ...
# ============================================================

smartdns_detect_arch()
{
    CPU="$(uname -m 2>/dev/null)"


    case "$CPU" in

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

            _sd_error "暂不支持 CPU 架构：$CPU"

            return 1
            ;;

    esac


    _sd_info "CPU Architecture : $CPU"

    _sd_info "Release Arch     : $SMARTDNS_ARCH"


    return 0
}


# ============================================================
# 空间
# ============================================================

smartdns_check_space()
{
    FREE_KB="$(
        df -k /usr 2>/dev/null |
        awk 'END {print $4}'
    )"


    case "$FREE_KB" in

        ''|*[!0-9]*)

            FREE_KB=0
            ;;

    esac


    FREE_MB=$((FREE_KB / 1024))


    if [ "$FREE_MB" -lt 25 ]
    then

        _sd_error "可用空间不足，建议至少保留 25 MB"

        return 1

    fi


    return 0
}


# ============================================================
# 获取 GitHub Release
# ============================================================

smartdns_get_release()
{
    mkdir -p "$SMARTDNS_TMP" || return 1


    rm -f "$SMARTDNS_RELEASE_JSON"


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


    # ========================================================
    # Release Tag
    # ========================================================

    SMARTDNS_VERSION="$(
        sed -n \
        's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$SMARTDNS_RELEASE_JSON" |
        head -n 1
    )"


    # ========================================================
    # SmartDNS 主程序
    # ========================================================

    SMARTDNS_MAIN_URL="$(
        sed -n \
        's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$SMARTDNS_RELEASE_JSON" |
        grep \
        "/smartdns\..*\.${SMARTDNS_ARCH}-openwrt-all\.${SMARTDNS_EXT}$" |
        head -n 1
    )"


    # ========================================================
    # LuCI
    #
    # OPKG 旧系统优先 compat
    # APK 优先普通 LuCI
    # ========================================================

    if [ "$SMARTDNS_PKG_MANAGER" = "opkg" ]
    then

        SMARTDNS_LUCI_URL="$(
            sed -n \
            's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' \
            "$SMARTDNS_RELEASE_JSON" |
            grep \
            "/luci-app-smartdns\..*\.all-luci-compat-all\.ipk$" |
            head -n 1
        )"


        # compat 不存在再普通 LuCI

        if [ -z "$SMARTDNS_LUCI_URL" ]
        then

            SMARTDNS_LUCI_URL="$(
                sed -n \
                's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' \
                "$SMARTDNS_RELEASE_JSON" |
                grep \
                "/luci-app-smartdns\..*\.all-luci-all\.ipk$" |
                head -n 1
            )"

        fi

    else

        SMARTDNS_LUCI_URL="$(
            sed -n \
            's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' \
            "$SMARTDNS_RELEASE_JSON" |
            grep \
            "/luci-app-smartdns\..*\.all-luci-all\.apk$" |
            head -n 1
        )"

    fi


    if [ -z "$SMARTDNS_MAIN_URL" ]
    then

        _sd_error "没有找到当前架构的 SmartDNS 官方安装包"

        return 1

    fi


    if [ -z "$SMARTDNS_LUCI_URL" ]
    then

        _sd_error "没有找到 SmartDNS LuCI 安装包"

        return 1

    fi


    SMARTDNS_MAIN_FILE="$SMARTDNS_TMP/smartdns.$SMARTDNS_EXT"

    SMARTDNS_LUCI_FILE="$SMARTDNS_TMP/luci-app-smartdns.$SMARTDNS_EXT"


    return 0
}


# ============================================================
# 构建代理 URL
# ============================================================

smartdns_build_url()
{
    PREFIX="$1"
    URL="$2"


    if [ -z "$PREFIX" ]
    then
        printf '%s' "$URL"
    else
        printf '%s%s' "$PREFIX" "$URL"
    fi
}


# ============================================================
# 秒 → ms
# ============================================================

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


# ============================================================
# B/s → MB/s
# ============================================================

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


# ============================================================
# 测速单线路
# ============================================================

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
            -w '%{http_code}|%{time_starttransfer}|%{speed_download}|%{size_download}' \
            "$URL" \
            2>/dev/null
    )"


    RC=$?


    if [ "$RC" -ne 0 ] &&
       [ "$RC" -ne 28 ]
    then

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
        awk -v s="$SPEED" \
        'BEGIN { if (s > 0) printf "%d", s; else print 0 }'
    )"


    if [ "$SPEED_INT" -le 0 ]
    then

        printf '%s|FAIL\n' "$NAME" >"$RESULT"

        return

    fi


    # ========================================================
    # 综合评分
    #
    # 首包 + 模拟 10MB 下载时间
    # ========================================================

    SCORE="$(
        awk \
            -v t="$TTFB_MS" \
            -v s="$SPEED_INT" \
            'BEGIN {
                if (s <= 0)
                    print 999999999
                else
                    printf "%d", t + (10485760 / s) * 1000
            }'
    )"


    printf \
        '%s|OK|%s|%s|%s|%s\n' \
        "$NAME" \
        "$PREFIX" \
        "$TTFB_MS" \
        "$SPEED_INT" \
        "$SCORE" \
        >"$RESULT"
}


# ============================================================
# 下载线路测速
# ============================================================

smartdns_prepare_routes()
{
    ORIGINAL="$1"


    rm -rf "$SMARTDNS_TEST_DIR"

    mkdir -p "$SMARTDNS_TEST_DIR" || return 1


    rm -f "$SMARTDNS_ROUTE_FILE"


    printf '\n'

    _sd_info "正在并行测试 SmartDNS 下载线路..."

    printf '\n'


    for NAME in \
        GH01 \
        GH02 \
        GH03 \
        GH04 \
        GH05 \
        GH06 \
        DIRECT
    do

        PREFIX="$(
            printf '%s\n' "$SMARTDNS_NODES" |
            awk -F '|' \
                -v n="$NAME" \
                '$1 == n { print $2; exit }'
        )"


        smartdns_test_route \
            "$NAME" \
            "$PREFIX" \
            "$ORIGINAL" \
            "$SMARTDNS_TEST_DIR/$NAME" &

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


    for NAME in \
        GH01 \
        GH02 \
        GH03 \
        GH04 \
        GH05 \
        GH06 \
        DIRECT
    do

        FILE="$SMARTDNS_TEST_DIR/$NAME"


        if [ ! -s "$FILE" ] ||
           [ "$(cut -d '|' -f2 "$FILE")" != "OK" ]
        then

            printf \
                '%-8s %-12s %-14s \033[1;91m%s\033[0m\n' \
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


        printf \
            '%-8s %-12s %-14s \033[1;92m%s\033[0m\n' \
            "$NAME" \
            "${TTFB} ms" \
            "$(smartdns_speed_mb "$SPEED") MB/s" \
            "可用"


        printf \
            '%s|%s|%s|%s|%s\n' \
            "$SCORE" \
            "$NAME" \
            "$PREFIX" \
            "$TTFB" \
            "$SPEED" \
            >>"$SMARTDNS_ROUTE_FILE"

    done


    rm -rf "$SMARTDNS_TEST_DIR"


    if [ ! -s "$SMARTDNS_ROUTE_FILE" ]
    then

        _sd_warn "测速线路全部不可用，将尝试 GitHub 官方直连"

        return 1

    fi


    sort -n \
        -t '|' \
        -k1,1 \
        "$SMARTDNS_ROUTE_FILE" \
        >"$SMARTDNS_ROUTE_FILE.sorted"


    mv \
        "$SMARTDNS_ROUTE_FILE.sorted" \
        "$SMARTDNS_ROUTE_FILE"


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


# ============================================================
# 下载一个文件
# ============================================================

smartdns_download_file()
{
    ORIGINAL="$1"
    OUTPUT="$2"


    rm -f "$OUTPUT"


    # ========================================================
    # 按测速排序尝试
    # ========================================================

    if [ -s "$SMARTDNS_ROUTE_FILE" ]
    then

        while IFS='|' read -r \
            SCORE \
            NAME \
            PREFIX \
            TTFB \
            SPEED
        do

            URL="$(smartdns_build_url "$PREFIX" "$ORIGINAL")"


            if curl -4 \
                -L \
                -f \
                -sS \
                --connect-timeout 10 \
                --max-time 300 \
                --retry 1 \
                -o "$OUTPUT" \
                "$URL" \
                >>"$SMARTDNS_LOG" 2>&1
            then

                if [ -s "$OUTPUT" ]
                then
                    return 0
                fi

            fi


            rm -f "$OUTPUT"

        done <"$SMARTDNS_ROUTE_FILE"

    fi


    # ========================================================
    # 官方直连兜底
    # ========================================================

    if curl -4 \
        -L \
        -f \
        -sS \
        --connect-timeout 10 \
        --max-time 300 \
        --retry 1 \
        -o "$OUTPUT" \
        "$ORIGINAL" \
        >>"$SMARTDNS_LOG" 2>&1
    then

        [ -s "$OUTPUT" ] && return 0

    fi


    rm -f "$OUTPUT"


    return 1
}


# ============================================================
# 软件包检测
# ============================================================

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


# ============================================================
# 安装本体
# ============================================================

smartdns_install_main()
{
    case "$SMARTDNS_PKG_MANAGER" in

        opkg)

            # =================================================
            # 使用短文件名避免部分旧 OPKG Illegal file name
            # =================================================

            cp "$SMARTDNS_MAIN_FILE" \
                /tmp/smartdns.ipk \
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
       ! smartdns_package_installed smartdns
    then

        return 1

    fi


    smartdns_package_installed smartdns
}


# ============================================================
# 安装 LuCI
# ============================================================

smartdns_install_luci()
{
    case "$SMARTDNS_PKG_MANAGER" in

        opkg)

            cp "$SMARTDNS_LUCI_FILE" \
                /tmp/smartdns_luci.ipk \
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
       ! smartdns_package_installed luci-app-smartdns
    then

        return 1

    fi


    smartdns_package_installed luci-app-smartdns
}


# ============================================================
# 服务状态
# ============================================================

smartdns_detect_running()
{
    SMARTDNS_WAS_RUNNING=0


    if [ -x /etc/init.d/smartdns ] &&
       /etc/init.d/smartdns status >/dev/null 2>&1
    then

        SMARTDNS_WAS_RUNNING=1

    fi
}


# ============================================================
# 刷新 LuCI
# ============================================================

smartdns_refresh_luci()
{
    rm -rf \
        /tmp/luci-indexcache \
        /tmp/luci-modulecache \
        /tmp/luci-*cache* \
        >/dev/null 2>&1


    if [ -x /etc/init.d/rpcd ]
    then

        /etc/init.d/rpcd restart \
            >>"$SMARTDNS_LOG" 2>&1

    fi


    if [ -x /etc/init.d/uhttpd ]
    then

        /etc/init.d/uhttpd reload \
            >>"$SMARTDNS_LOG" 2>&1

    fi
}


# ============================================================
# 获取版本
# ============================================================

smartdns_get_version()
{
    if command -v smartdns >/dev/null 2>&1
    then

        smartdns -V 2>/dev/null |
            head -n 1

    fi
}


# ============================================================
# 最终验证
# ============================================================

smartdns_verify()
{
    smartdns_package_installed smartdns ||
        return 1


    smartdns_package_installed luci-app-smartdns ||
        return 1


    command -v smartdns >/dev/null 2>&1 ||
        return 1


    [ -x /etc/init.d/smartdns ] ||
        return 1


    return 0
}


# ============================================================
# 主函数
# ============================================================

install_smartdns()
{
    printf '\n'

    printf '%b\n' \
        '\033[1;94m╔══════════════════════════════════════╗\033[0m'

    printf '%b\n' \
        '\033[1;94m║\033[1;92m        SmartDNS 一键安装             \033[1;94m║\033[0m'

    printf '%b\n' \
        '\033[1;94m╚══════════════════════════════════════╝\033[0m'

    printf '\n'


    # ========================================================
    # ROOT
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]
    then

        _sd_error "请使用 root 用户运行"

        return 1

    fi


    smartdns_cleanup_all


    mkdir -p "$SMARTDNS_TMP" || {

        _sd_error "无法创建临时目录"

        return 1
    }


    touch "$SMARTDNS_LOG"


    trap 'smartdns_interrupt' INT TERM


    # ========================================================
    # 5%
    # ========================================================

    smartdns_progress 5


    smartdns_check_runtime || {

        printf '\n'

        smartdns_show_log

        return 1
    }


    smartdns_detect_system || {

        printf '\n'

        return 1
    }


    smartdns_detect_package_manager || {

        printf '\n'

        return 1
    }


    smartdns_detect_arch || {

        printf '\n'

        return 1
    }


    smartdns_check_space || {

        printf '\n'

        return 1
    }


    # ========================================================
    # 15%
    # ========================================================

    smartdns_progress 15


    if ! smartdns_get_release
    then

        smartdns_show_log

        smartdns_cleanup

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 25% 测速
    # ========================================================

    smartdns_progress 25


    smartdns_prepare_routes "$SMARTDNS_MAIN_URL" ||
        true


    # ========================================================
    # 35% 下载本体
    # ========================================================

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


    # ========================================================
    # 50% 下载 LuCI
    # ========================================================

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


    # ========================================================
    # 停止旧服务
    # ========================================================

    smartdns_detect_running


    if [ -x /etc/init.d/smartdns ]
    then

        /etc/init.d/smartdns stop \
            >/dev/null 2>&1

    fi


    # ========================================================
    # 65% 安装本体
    # ========================================================

    smartdns_progress 65


    if ! smartdns_install_main
    then

        printf '\n'

        _sd_error "SmartDNS 主程序安装失败"

        smartdns_show_log

        smartdns_cleanup

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 80% LuCI
    # ========================================================

    smartdns_progress 80


    if ! smartdns_install_luci
    then

        printf '\n'

        _sd_error "SmartDNS LuCI 安装失败"

        smartdns_show_log

        smartdns_cleanup

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 90%
    # ========================================================

    smartdns_progress 90


    smartdns_refresh_luci


    # ========================================================
    # 不主动修改：
    #
    # /etc/config/smartdns
    # dnsmasq
    # 53端口
    #
    # 避免破坏现有：
    #
    # ADG / MosDNS / OpenClash
    # ========================================================


    # ========================================================
    # 启用服务
    # ========================================================

    if [ -x /etc/init.d/smartdns ]
    then

        /etc/init.d/smartdns enable \
            >/dev/null 2>&1

        /etc/init.d/smartdns restart \
            >>"$SMARTDNS_LOG" 2>&1 ||
            true

    fi


    # ========================================================
    # 97% 验证
    # ========================================================

    smartdns_progress 97


    if ! smartdns_verify
    then

        printf '\n'

        _sd_error "SmartDNS 最终验证失败"

        smartdns_show_log

        smartdns_cleanup

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 100%
    # ========================================================

    smartdns_progress 100


    printf '\n\n'


    INSTALLED_VERSION="$(smartdns_get_version)"


    smartdns_cleanup

    rm -f "$SMARTDNS_LOG" 2>/dev/null


    trap - INT TERM


    _sd_ok "SmartDNS 安装完成"


    [ -n "$SMARTDNS_VERSION" ] &&
        _sd_info "Release : $SMARTDNS_VERSION"


    [ -n "$INSTALLED_VERSION" ] &&
        _sd_info "Version : $INSTALLED_VERSION"


    _sd_info "Arch    : $SMARTDNS_ARCH"

    _sd_info "Package : .$SMARTDNS_EXT"

    _sd_info "LuCI    : 服务 → SmartDNS"


    printf '\n'


    return 0
}

#!/bin/sh

# ============================================================
# Open-Pro-Installer
# OpenClash Smart Installer
#
# 功能：
# 1. 自动检测 CPU / Core 架构
# 2. GH01-GH06 + DIRECT 并行真实测速
# 3. 检测 TTFB 首包时间
# 4. 检测实际下载速度
# 5. 自动计算综合成绩并排序
# 6. 自动选择最佳下载线路
# 7. 最佳线路失败自动切换下一线路
# 8. GitHub 官方 DIRECT 最终兜底
# 9. 静默下载
# 10. 静默 OPKG/APK 安装
# 11. 单行动态安装进度条
# 12. 安装失败自动打印详细日志
# 13. 自动验证 OpenClash 安装结果
# 14. 自动检测 Meta / Mihomo Core
# 15. 自动读取当前 Meta Core 版本
# 16. 自动检测官方最新 Meta Core 版本
# 17. 自动筛选最快 GitHub 下载代理
# 18. 调用 OpenClash 官方 openclash_core.sh
# 19. 代理失败自动切换下一线路
# 20. Meta Core 更新后再次验证版本
#
# BusyBox / OpenWrt /bin/sh Compatible
# ============================================================


# ============================================================
# 基础配置
# ============================================================

OPENCLASH_PKG=""

INSTALL_LOG="/tmp/openpro_openclash_install.log"
OC_DOWNLOAD_LOG="/tmp/openpro_openclash_download.log"

OC_ROUTE_FILE="/tmp/openpro_openclash_routes"
OC_SORTED_FILE="/tmp/openpro_openclash_routes.sorted"

OC_TEST_FILE="/tmp/openpro_openclash_speedtest"
OC_TEST_DIR="/tmp/openpro_openclash_speedtest.d"

OC_CORE_UPDATE_LOG="/tmp/openpro_openclash_core_update.log"

PROGRESS_PID=""
CORE_UPDATE_PID=""

OPENCLASH_VERSION=""
OPENCLASH_ARCH=""
OPENCLASH_CORE_ARCH=""

OPENCLASH_DIR="/etc/openclash"
OPENCLASH_CORE_DIR="/etc/openclash/core"

META_CORE_PATH=""
META_CORE_VERSION=""
META_CORE_FULL_VERSION=""

LATEST_META_VERSION=""

OPENCLASH_CORE_CPU_MODEL=""
OPENCLASH_RELEASE_BRANCH="master"


# ============================================================
# 测速设置
# ============================================================

OC_TEST_CONNECT_TIMEOUT=4
OC_TEST_MAX_TIME=6

# 按 10MB 文件预计下载耗时计算综合成绩
OC_SCORE_FILE_KB=10240


# ============================================================
# GitHub 下载线路
# ============================================================

OPENCLASH_DOWNLOAD_NODES="
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

_oc_info()
{
    if command -v info >/dev/null 2>&1; then
        info "$*"
    else
        printf '\033[1;92m[INFO]\033[0m %s\n' "$*"
    fi
}


_oc_warn()
{
    if command -v warning >/dev/null 2>&1; then
        warning "$*"
    elif command -v warn >/dev/null 2>&1; then
        warn "$*"
    else
        printf '\033[1;93m[WARN]\033[0m %s\n' "$*"
    fi
}


_oc_error()
{
    if command -v error >/dev/null 2>&1; then
        error "$*"
    else
        printf '\033[1;91m[ERROR]\033[0m %s\n' "$*"
    fi
}


_oc_ok()
{
    printf '\033[1;92m[OK]\033[0m %s\n' "$*"
}


# ============================================================
# 清理
# ============================================================

cleanup_openclash_package()
{
    [ -n "$OPENCLASH_PKG" ] &&
        rm -f "$OPENCLASH_PKG" 2>/dev/null

    return 0
}


cleanup_openclash_logs()
{
    rm -f "$INSTALL_LOG" 2>/dev/null
    rm -f "$OC_DOWNLOAD_LOG" 2>/dev/null

    return 0
}


cleanup_openclash_temp()
{
    rm -f "$OC_ROUTE_FILE" 2>/dev/null
    rm -f "$OC_SORTED_FILE" 2>/dev/null
    rm -f "$OC_TEST_FILE" 2>/dev/null
    rm -f "$OC_DOWNLOAD_LOG" 2>/dev/null

    rm -rf "$OC_TEST_DIR" 2>/dev/null

    return 0
}


cleanup_core_update()
{
    rm -f "$OC_CORE_UPDATE_LOG" 2>/dev/null

    CORE_UPDATE_PID=""

    return 0
}


# ============================================================
# 检查 OpenClash
# ============================================================

check_openclash()
{
    if command -v opkg >/dev/null 2>&1; then

        opkg status luci-app-openclash 2>/dev/null |
            grep -q 'Status:.*installed'

        return $?
    fi


    if command -v apk >/dev/null 2>&1; then

        apk info -e luci-app-openclash >/dev/null 2>&1

        return $?
    fi


    return 1
}


# ============================================================
# 获取已安装版本
# ============================================================

get_installed_openclash_version()
{
    OPENCLASH_VERSION=""


    if command -v opkg >/dev/null 2>&1; then

        OPENCLASH_VERSION="$(
            opkg status luci-app-openclash 2>/dev/null |
            awk -F ': ' '
                /^Version:/ {
                    print $2
                    exit
                }
            '
        )"

    elif command -v apk >/dev/null 2>&1; then

        OPENCLASH_VERSION="$(
            apk info luci-app-openclash 2>/dev/null |
            sed -n '1p'
        )"

    fi


    [ -n "$OPENCLASH_VERSION" ] ||
        OPENCLASH_VERSION="unknown"
}


# ============================================================
# 构造代理 URL
# ============================================================

build_openclash_url()
{
    PREFIX="$1"
    ORIGINAL_URL="$2"


    if [ -z "$PREFIX" ]; then
        printf '%s' "$ORIGINAL_URL"
    else
        printf '%s%s' "$PREFIX" "$ORIGINAL_URL"
    fi
}


# ============================================================
# 秒 → 毫秒
# ============================================================

oc_seconds_to_ms()
{
    VALUE="$1"


    awk -v t="$VALUE" '
        BEGIN {
            if (t == "" || t !~ /^[0-9.]+$/) {
                print 999999
                exit
            }

            printf "%d", t * 1000
        }
    '
}


# ============================================================
# Bytes/s → MB/s
# ============================================================

oc_speed_to_mb()
{
    VALUE="$1"


    awk -v s="$VALUE" '
        BEGIN {
            if (s == "" || s <= 0) {
                printf "0.00"
                exit
            }

            printf "%.2f", s / 1024 / 1024
        }
    '
}


# ============================================================
# 综合成绩
# ============================================================

oc_calculate_score()
{
    TTFB_MS="$1"
    SPEED_BPS="$2"


    awk \
        -v t="$TTFB_MS" \
        -v s="$SPEED_BPS" \
        -v kb="$OC_SCORE_FILE_KB" '
        BEGIN {
            if (s <= 0) {
                print 999999999
                exit
            }

            speed_kb = s / 1024

            download_ms = (kb / speed_kb) * 1000

            score = t + download_ms

            printf "%d", score
        }
    '
}


# ============================================================
# 检测 HTML 错误页
# ============================================================

oc_test_is_error_page()
{
    FILE="$1"


    if [ ! -s "$FILE" ]; then
        return 1
    fi


    if head -c 1024 "$FILE" 2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
    then
        return 0
    fi


    return 1
}


# ============================================================
# 单线路测速
# ============================================================

test_openclash_route()
{
    TEST_URL="$1"
    TEST_FILE="$2"


    rm -f "$TEST_FILE"


    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi


    CURL_DATA="$(
        curl -4 \
            -L \
            -sS \
            --connect-timeout "$OC_TEST_CONNECT_TIMEOUT" \
            --max-time "$OC_TEST_MAX_TIME" \
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
            rm -f "$TEST_FILE"
            return 1
            ;;
    esac


    RECEIVED_BYTES="$(
        awk -v n="$SIZE_DOWN" '
            BEGIN {
                printf "%d", n
            }
        '
    )"


    if [ "$RECEIVED_BYTES" -lt 4096 ]; then

        rm -f "$TEST_FILE"

        return 1
    fi


    if oc_test_is_error_page "$TEST_FILE"; then

        rm -f "$TEST_FILE"

        return 1
    fi


    TTFB_MS="$(oc_seconds_to_ms "$TTFB")"


    case "$TTFB_MS" in
        ''|*[!0-9]*)
            rm -f "$TEST_FILE"
            return 1
            ;;
    esac


    SPEED_INT="$(
        awk -v s="$SPEED_BPS" '
            BEGIN {
                if (s <= 0) {
                    print 0
                } else {
                    printf "%d", s
                }
            }
        '
    )"


    if [ "$SPEED_INT" -le 0 ]; then

        rm -f "$TEST_FILE"

        return 1
    fi


    SCORE="$(
        oc_calculate_score \
            "$TTFB_MS" \
            "$SPEED_INT"
    )"


    rm -f "$TEST_FILE"


    printf '%s|%s|%s|%s' \
        "$TTFB_MS" \
        "$SPEED_INT" \
        "$RECEIVED_BYTES" \
        "$SCORE"


    return 0
}


# ============================================================
# 后台测速任务
# ============================================================

test_openclash_route_background()
{
    NODE_NAME="$1"
    NODE_PREFIX="$2"
    ORIGINAL_URL="$3"
    RESULT_FILE="$4"
    TEST_FILE="$5"


    TEST_URL="$(
        build_openclash_url \
            "$NODE_PREFIX" \
            "$ORIGINAL_URL"
    )"


    TEST_DATA="$(
        test_openclash_route \
            "$TEST_URL" \
            "$TEST_FILE"
    )"


    TEST_RESULT=$?


    if [ "$TEST_RESULT" -ne 0 ] ||
       [ -z "$TEST_DATA" ]
    then

        printf '%s|FAIL\n' \
            "$NODE_NAME" \
            > "$RESULT_FILE"

        rm -f "$TEST_FILE"

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


    RECEIVED="$(
        printf '%s' "$TEST_DATA" |
        cut -d '|' -f 3
    )"


    SCORE="$(
        printf '%s' "$TEST_DATA" |
        cut -d '|' -f 4
    )"


    printf '%s|OK|%s|%s|%s|%s|%s|%s\n' \
        "$NODE_NAME" \
        "$NODE_PREFIX" \
        "$TEST_URL" \
        "$TTFB_MS" \
        "$SPEED_BPS" \
        "$RECEIVED" \
        "$SCORE" \
        > "$RESULT_FILE"


    rm -f "$TEST_FILE"


    return 0
}


# ============================================================
# 并行测速
# ============================================================

prepare_openclash_routes()
{
    ORIGINAL_URL="$1"


    rm -f "$OC_ROUTE_FILE"
    rm -f "$OC_SORTED_FILE"
    rm -f "$OC_TEST_FILE"

    rm -rf "$OC_TEST_DIR"

    mkdir -p "$OC_TEST_DIR"


    printf "\n"

    _oc_info "正在并行测试 OpenClash 下载线路..."

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
            printf '%s\n' "$OPENCLASH_DOWNLOAD_NODES" |
            awk -F '|' \
                -v node="$NODE_NAME" \
                '$1 == node {
                    print $2
                    exit
                }'
        )"


        RESULT_FILE="$OC_TEST_DIR/result_${NODE_NAME}"
        TEST_FILE="$OC_TEST_DIR/download_${NODE_NAME}"


        test_openclash_route_background \
            "$NODE_NAME" \
            "$NODE_PREFIX" \
            "$ORIGINAL_URL" \
            "$RESULT_FILE" \
            "$TEST_FILE" &

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

        RESULT_FILE="$OC_TEST_DIR/result_${NODE_NAME}"


        if [ ! -s "$RESULT_FILE" ]; then

            printf '%-8s %-12s %-14s \033[1;91m%s\033[0m\n' \
                "$NODE_NAME" \
                "----" \
                "----" \
                "不可用"

            continue
        fi


        RESULT_STATUS="$(
            cut -d '|' -f 2 \
                "$RESULT_FILE"
        )"


        if [ "$RESULT_STATUS" != "OK" ]; then

            printf '%-8s %-12s %-14s \033[1;91m%s\033[0m\n' \
                "$NODE_NAME" \
                "----" \
                "----" \
                "不可用"

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
            cut -d '|' -f 8 \
                "$RESULT_FILE"
        )"


        SPEED_MB="$(
            oc_speed_to_mb "$SPEED_BPS"
        )"


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
            >> "$OC_ROUTE_FILE"

    done


    if [ ! -s "$OC_ROUTE_FILE" ]; then

        printf "\n"

        _oc_warn "没有发现可用测速线路"

        rm -rf "$OC_TEST_DIR"

        return 1
    fi


    sort -n -t '|' -k 1,1 \
        "$OC_ROUTE_FILE" \
        > "$OC_SORTED_FILE" \
        2>/dev/null


    if [ -s "$OC_SORTED_FILE" ]; then

        mv "$OC_SORTED_FILE" \
            "$OC_ROUTE_FILE"

    else

        rm -f "$OC_SORTED_FILE"

    fi


    BEST_LINE="$(
        sed -n '1p' \
            "$OC_ROUTE_FILE"
    )"


    BEST_NAME="$(
        printf '%s\n' "$BEST_LINE" |
        cut -d '|' -f 2
    )"


    BEST_TTFB="$(
        printf '%s\n' "$BEST_LINE" |
        cut -d '|' -f 5
    )"


    BEST_SPEED="$(
        printf '%s\n' "$BEST_LINE" |
        cut -d '|' -f 6
    )"


    BEST_SPEED_MB="$(
        oc_speed_to_mb "$BEST_SPEED"
    )"


    printf "\n"

    _oc_ok "最佳线路：$BEST_NAME"

    _oc_info "首包时间：${BEST_TTFB} ms"

    _oc_info "下载速度：${BEST_SPEED_MB} MB/s"

    printf "\n"


    rm -rf "$OC_TEST_DIR"


    return 0
}


# ============================================================
# 验证 OpenClash 软件包
# ============================================================

verify_openclash_package()
{
    FILE="$1"


    if [ ! -s "$FILE" ]; then
        return 1
    fi


    FILE_SIZE="$(
        wc -c < "$FILE" 2>/dev/null
    )"


    case "$FILE_SIZE" in
        ''|*[!0-9]*)
            FILE_SIZE=0
            ;;
    esac


    if [ "$FILE_SIZE" -lt 102400 ]; then
        return 1
    fi


    if head -c 1024 "$FILE" 2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
    then
        return 1
    fi


    return 0
}


# ============================================================
# CURL 下载
# ============================================================

download_openclash_curl()
{
    URL="$1"
    OUTPUT="$2"


    curl -4 \
        -L \
        -f \
        -sS \
        --connect-timeout 8 \
        --max-time 180 \
        --retry 1 \
        --retry-delay 1 \
        -o "$OUTPUT" \
        "$URL" \
        > "$OC_DOWNLOAD_LOG" 2>&1
}


# ============================================================
# WGET 下载
# ============================================================

download_openclash_wget()
{
    URL="$1"
    OUTPUT="$2"


    wget \
        -T 20 \
        -O "$OUTPUT" \
        "$URL" \
        > "$OC_DOWNLOAD_LOG" 2>&1
}


# ============================================================
# 指定 URL 下载
# ============================================================

download_openclash_from_url()
{
    URL="$1"
    OUTPUT="$2"


    rm -f "$OUTPUT"
    rm -f "$OC_DOWNLOAD_LOG"


    if command -v curl >/dev/null 2>&1; then

        download_openclash_curl \
            "$URL" \
            "$OUTPUT"

        RESULT=$?

    elif command -v wget >/dev/null 2>&1; then

        download_openclash_wget \
            "$URL" \
            "$OUTPUT"

        RESULT=$?

    else

        _oc_error "系统缺少 curl / wget"

        return 1
    fi


    if [ "$RESULT" -ne 0 ]; then

        rm -f "$OUTPUT"

        return 1
    fi


    if ! verify_openclash_package "$OUTPUT"; then

        rm -f "$OUTPUT"

        return 1
    fi


    return 0
}


# ============================================================
# 智能下载
# ============================================================

smart_download_openclash()
{
    ORIGINAL_URL="$1"
    OUTPUT="$2"


    prepare_openclash_routes "$ORIGINAL_URL"


    DOWNLOAD_SUCCESS=0
    DIRECT_TRIED=0


    if [ -s "$OC_ROUTE_FILE" ]; then

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


            ROUTE_SPEED_MB="$(
                oc_speed_to_mb "$ROUTE_SPEED"
            )"


            _oc_info "正在使用线路：$ROUTE_NAME"

            _oc_info "测速速度：${ROUTE_SPEED_MB} MB/s"


            if download_openclash_from_url \
                "$ROUTE_URL" \
                "$OUTPUT"
            then

                _oc_ok "下载线路：$ROUTE_NAME"

                DOWNLOAD_SUCCESS=1

                break
            fi


            _oc_warn "$ROUTE_NAME 下载失败，自动切换下一线路..."

        done < "$OC_ROUTE_FILE"

    fi


    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] &&
       [ "$DIRECT_TRIED" -ne 1 ]
    then

        _oc_info "正在尝试 GitHub 官方直连..."


        if download_openclash_from_url \
            "$ORIGINAL_URL" \
            "$OUTPUT"
        then

            _oc_ok "GitHub 官方直连下载成功"

            DOWNLOAD_SUCCESS=1
        fi
    fi


    cleanup_openclash_temp


    [ "$DOWNLOAD_SUCCESS" -eq 1 ]
}


# ============================================================
# 安装进度条
# ============================================================

openclash_progress_bar()
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


    printf '\r\033[2K\033[1;92m[INFO]\033[0m 正在安装 OpenClash... [\033[1;92m%s\033[0m] %3d%%' \
        "$BAR" \
        "$PERCENT"
}


# ============================================================
# 静默安装
# ============================================================

install_openclash_with_progress()
{
    PKG_FILE="$1"
    PKG_TYPE="$2"


    rm -f "$INSTALL_LOG"


    case "$PKG_TYPE" in

        apk)

            apk add \
                --allow-untrusted \
                --force-overwrite \
                "$PKG_FILE" \
                > "$INSTALL_LOG" 2>&1 &

            ;;


        ipk)

            opkg install \
                "$PKG_FILE" \
                > "$INSTALL_LOG" 2>&1 &

            ;;


        *)

            return 1

            ;;

    esac


    PROGRESS_PID=$!

    PERCENT=1


    openclash_progress_bar "$PERCENT"


    while kill -0 "$PROGRESS_PID" 2>/dev/null
    do

        if grep -q '^Configuring ' "$INSTALL_LOG" 2>/dev/null; then

            if [ "$PERCENT" -lt 94 ]; then
                PERCENT=$((PERCENT + 3))
            fi


        elif grep -q '^Installing ' "$INSTALL_LOG" 2>/dev/null; then

            if [ "$PERCENT" -lt 78 ]; then
                PERCENT=$((PERCENT + 3))
            fi


        elif grep -q '^Downloading ' "$INSTALL_LOG" 2>/dev/null; then

            if [ "$PERCENT" -lt 48 ]; then
                PERCENT=$((PERCENT + 2))
            fi


        else

            if [ "$PERCENT" -lt 15 ]; then
                PERCENT=$((PERCENT + 1))
            fi

        fi


        [ "$PERCENT" -gt 95 ] &&
            PERCENT=95


        openclash_progress_bar "$PERCENT"


        sleep 1

    done


    wait "$PROGRESS_PID"

    RESULT=$?

    PROGRESS_PID=""


    if [ "$RESULT" -eq 0 ]; then

        openclash_progress_bar 100

        printf "\n"

        return 0
    fi


    printf "\n"

    return "$RESULT"
}


# ============================================================
# CPU / Core 架构
# ============================================================

detect_openclash_arch()
{
    OPENCLASH_ARCH="$(uname -m 2>/dev/null)"


    [ -n "$OPENCLASH_ARCH" ] ||
        OPENCLASH_ARCH="unknown"


    case "$OPENCLASH_ARCH" in

        aarch64|arm64)

            OPENCLASH_CORE_ARCH="linux-arm64"

            ;;


        x86_64|amd64)

            OPENCLASH_CORE_ARCH="linux-amd64"

            ;;


        armv7*|armv7l)

            OPENCLASH_CORE_ARCH="linux-armv7"

            ;;


        armv6*|armv6l)

            OPENCLASH_CORE_ARCH="linux-armv6"

            ;;


        armv5*|armv5l)

            OPENCLASH_CORE_ARCH="linux-armv5"

            ;;


        mipsel)

            OPENCLASH_CORE_ARCH="linux-mipsle-softfloat"

            ;;


        mips)

            OPENCLASH_CORE_ARCH="linux-mips-softfloat"

            ;;


        *)

            OPENCLASH_CORE_ARCH="unknown"

            ;;

    esac


    _oc_info "处理器架构 : $OPENCLASH_ARCH"


    if [ "$OPENCLASH_CORE_ARCH" != "unknown" ]; then

        _oc_info "内核架构   : $OPENCLASH_CORE_ARCH"

    else

        _oc_warn "暂时无法自动判断 OpenClash 内核架构"

    fi
}


# ============================================================
# 获取官方 Core CPU_MODEL
# ============================================================

detect_openclash_core_cpu_model()
{
    OPENCLASH_CORE_CPU_MODEL="$(
        uci -q get openclash.config.core_version \
        2>/dev/null
    )"


    case "$OPENCLASH_CORE_CPU_MODEL" in
        ""|0)
            OPENCLASH_CORE_CPU_MODEL="$OPENCLASH_CORE_ARCH"
            ;;
    esac


    if [ "$OPENCLASH_CORE_CPU_MODEL" = "unknown" ] ||
       [ -z "$OPENCLASH_CORE_CPU_MODEL" ]
    then

        _oc_error "无法识别 OpenClash Core CPU 架构"

        return 1
    fi


    # 如果 OpenClash 尚未保存 Core 架构，自动写入
    CURRENT_CORE_MODEL="$(
        uci -q get openclash.config.core_version \
        2>/dev/null
    )"


    case "$CURRENT_CORE_MODEL" in
        ""|0)

            uci -q set \
                "openclash.config.core_version=$OPENCLASH_CORE_CPU_MODEL" \
                >/dev/null 2>&1

            uci commit openclash \
                >/dev/null 2>&1

            _oc_info "已自动设置 Core 架构：$OPENCLASH_CORE_CPU_MODEL"

            ;;
    esac


    OPENCLASH_RELEASE_BRANCH="$(
        uci -q get openclash.config.release_branch \
        2>/dev/null
    )"


    [ -n "$OPENCLASH_RELEASE_BRANCH" ] ||
        OPENCLASH_RELEASE_BRANCH="master"


    return 0
}


# ============================================================
# Meta Core 实际路径
# ============================================================

detect_meta_core_path()
{
    SMALL_FLASH="$(
        uci -q get openclash.config.small_flash_memory \
        2>/dev/null
    )"


    if [ "$SMALL_FLASH" = "1" ]; then

        META_CORE_PATH="/tmp/etc/openclash/core/clash_meta"

        mkdir -p /tmp/etc/openclash/core \
            >/dev/null 2>&1

    else

        META_CORE_PATH="/etc/openclash/core/clash_meta"

        mkdir -p /etc/openclash/core \
            >/dev/null 2>&1

    fi
}


# ============================================================
# 获取当前 Meta Core 版本
# ============================================================

get_meta_core_version()
{
    detect_meta_core_path


    META_CORE_VERSION=""
    META_CORE_FULL_VERSION=""


    if [ ! -x "$META_CORE_PATH" ]; then
        return 1
    fi


    META_CORE_FULL_VERSION="$(
        "$META_CORE_PATH" -v \
            2>/dev/null |
        head -n 1
    )"


    if [ -z "$META_CORE_FULL_VERSION" ]; then
        return 1
    fi


    META_CORE_VERSION="$(
        printf '%s\n' "$META_CORE_FULL_VERSION" |
        awk '{print $3}'
    )"


    [ -n "$META_CORE_VERSION" ]
}


# ============================================================
# 检测现有 Core
# ============================================================

check_openclash_core()
{
    printf "\n"

    _oc_info "正在检测 OpenClash 内核..."


    detect_meta_core_path


    CORE_FOUND=0


    if get_meta_core_version; then

        CORE_FOUND=1

        _oc_ok "已检测到 Meta / Mihomo 内核"

        _oc_info "当前版本：$META_CORE_VERSION"

    else

        _oc_warn "未检测到 Meta / Mihomo 内核"

    fi


    if [ -x "$OPENCLASH_CORE_DIR/clash" ]; then

        CORE_FOUND=1

        _oc_ok "已检测到 Clash 内核"

    fi


    if [ -x "$OPENCLASH_CORE_DIR/clash_tun" ]; then

        CORE_FOUND=1

        _oc_ok "已检测到 TUN 内核"

    fi


    [ "$CORE_FOUND" -eq 1 ]
}


# ============================================================
# 使用官方版本脚本获取最新 Meta 版本
#
# $1 = GitHub Proxy
#      DIRECT 时传 0
# ============================================================

get_latest_meta_core_version()
{
    CORE_PROXY="$1"


    VERSION_SCRIPT="/usr/share/openclash/openclash_version.lua"


    if [ ! -f "$VERSION_SCRIPT" ]; then
        return 1
    fi


    if ! command -v lua >/dev/null 2>&1; then
        return 1
    fi


    if ! command -v jsonfilter >/dev/null 2>&1; then
        return 1
    fi


    rm -f /tmp/openclash_version_history.json \
        2>/dev/null


    [ -n "$CORE_PROXY" ] ||
        CORE_PROXY="0"


    lua "$VERSION_SCRIPT" "$CORE_PROXY" \
        >/dev/null 2>&1


    if [ ! -s /tmp/openclash_version_history.json ]; then
        return 1
    fi


    LATEST_META_VERSION="$(
        jsonfilter \
            -i /tmp/openclash_version_history.json \
            -e "@.${OPENCLASH_RELEASE_BRANCH}.latest.core_meta" \
            2>/dev/null
    )"


    [ -n "$LATEST_META_VERSION" ]
}


# ============================================================
# Core 更新进度
# ============================================================

core_update_progress()
{
    PERCENT="$1"
    ROUTE_NAME="$2"

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


    printf '\r\033[2K\033[1;92m[INFO]\033[0m 正在更新 Meta Core [%s] [\033[1;92m%s\033[0m] %3d%%' \
        "$ROUTE_NAME" \
        "$BAR" \
        "$PERCENT"
}


# ============================================================
# 调用 OpenClash 官方 Core 更新脚本
#
# $1 = ROUTE_NAME
# $2 = ROUTE_PREFIX
# ============================================================

run_official_meta_core_update()
{
    ROUTE_NAME="$1"
    ROUTE_PREFIX="$2"


    CORE_UPDATE_SCRIPT="/usr/share/openclash/openclash_core.sh"


    if [ ! -f "$CORE_UPDATE_SCRIPT" ]; then

        _oc_error "没有找到官方 openclash_core.sh"

        return 1
    fi


    if [ ! -x "$CORE_UPDATE_SCRIPT" ]; then

        chmod +x "$CORE_UPDATE_SCRIPT" \
            >/dev/null 2>&1

    fi


    rm -f "$OC_CORE_UPDATE_LOG"


    _oc_info "正在调用 OpenClash 官方 Meta Core 更新脚本..."

    _oc_info "下载线路：$ROUTE_NAME"


    if [ "$ROUTE_NAME" = "DIRECT" ] ||
       [ -z "$ROUTE_PREFIX" ]
    then

        "$CORE_UPDATE_SCRIPT" \
            Meta \
            0 \
            > "$OC_CORE_UPDATE_LOG" 2>&1 &

    else

        "$CORE_UPDATE_SCRIPT" \
            Meta \
            "$ROUTE_PREFIX" \
            > "$OC_CORE_UPDATE_LOG" 2>&1 &

    fi


    CORE_UPDATE_PID=$!


    CORE_PERCENT=5


    core_update_progress \
        "$CORE_PERCENT" \
        "$ROUTE_NAME"


    while kill -0 "$CORE_UPDATE_PID" 2>/dev/null
    do

        if grep -qi \
            'Update Successful\|Download Successful' \
            "$OC_CORE_UPDATE_LOG" \
            2>/dev/null
        then

            if [ "$CORE_PERCENT" -lt 92 ]; then
                CORE_PERCENT=$((CORE_PERCENT + 5))
            fi

        elif grep -qi \
            'Downloading\|Download' \
            "$OC_CORE_UPDATE_LOG" \
            2>/dev/null
        then

            if [ "$CORE_PERCENT" -lt 80 ]; then
                CORE_PERCENT=$((CORE_PERCENT + 3))
            fi

        else

            if [ "$CORE_PERCENT" -lt 50 ]; then
                CORE_PERCENT=$((CORE_PERCENT + 1))
            fi

        fi


        [ "$CORE_PERCENT" -gt 95 ] &&
            CORE_PERCENT=95


        core_update_progress \
            "$CORE_PERCENT" \
            "$ROUTE_NAME"


        sleep 1

    done


    wait "$CORE_UPDATE_PID"

    CORE_SCRIPT_RESULT=$?

    CORE_UPDATE_PID=""


    # 官方脚本部分错误路径也可能返回 0，
    # 因此这里只作为参考，最终以实际 Core 版本验证为准。
    core_update_progress \
        100 \
        "$ROUTE_NAME"

    printf "\n"


    return "$CORE_SCRIPT_RESULT"
}


# ============================================================
# 自动检测并更新 Meta / Mihomo
# ============================================================

auto_update_openclash_core()
{
    printf "\n"

    _oc_info "正在检测 OpenClash Meta / Mihomo 内核更新..."


    CORE_UPDATE_SCRIPT="/usr/share/openclash/openclash_core.sh"


    if [ ! -f "$CORE_UPDATE_SCRIPT" ]; then

        _oc_warn "没有找到 OpenClash 官方 Core 更新脚本"

        return 0
    fi


    _oc_ok "检测到官方更新脚本"

    _oc_info "更新脚本：$CORE_UPDATE_SCRIPT"


    # ========================================================
    # Core CPU 架构
    # ========================================================

    if ! detect_openclash_core_cpu_model; then
        return 1
    fi


    _oc_info "Core 架构：$OPENCLASH_CORE_CPU_MODEL"

    _oc_info "Core 分支：$OPENCLASH_RELEASE_BRANCH"


    # ========================================================
    # 当前版本
    # ========================================================

    OLD_META_VERSION=""

    if get_meta_core_version; then

        OLD_META_VERSION="$META_CORE_VERSION"

        _oc_info "当前版本：$OLD_META_VERSION"

    else

        _oc_warn "当前尚未安装 Meta / Mihomo 内核"

    fi


    # ========================================================
    # 官方 Core 下载地址
    #
    # 仅用于测速。
    # 真正下载仍调用 OpenClash 官方脚本。
    # ========================================================

    CORE_TEST_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/${OPENCLASH_RELEASE_BRANCH}/meta/clash-${OPENCLASH_CORE_CPU_MODEL}.tar.gz"


    printf "\n"

    _oc_info "正在筛选 Meta Core 最佳下载线路..."


    prepare_openclash_routes "$CORE_TEST_URL"


    CORE_ROUTE_AVAILABLE=0


    if [ -s "$OC_ROUTE_FILE" ]; then
        CORE_ROUTE_AVAILABLE=1
    fi


    # ========================================================
    # 获取官方最新版本
    # ========================================================

    LATEST_META_VERSION=""


    if [ "$CORE_ROUTE_AVAILABLE" -eq 1 ]; then

        while IFS='|' read -r \
            ROUTE_SCORE \
            ROUTE_NAME \
            ROUTE_PREFIX \
            ROUTE_URL \
            ROUTE_TTFB \
            ROUTE_SPEED
        do

            if [ "$ROUTE_NAME" = "DIRECT" ] ||
               [ -z "$ROUTE_PREFIX" ]
            then
                VERSION_PROXY="0"
            else
                VERSION_PROXY="$ROUTE_PREFIX"
            fi


            if get_latest_meta_core_version \
                "$VERSION_PROXY"
            then

                _oc_ok "最新 Meta Core：$LATEST_META_VERSION"

                break
            fi

        done < "$OC_ROUTE_FILE"

    fi


    # 没拿到版本时尝试 DIRECT

    if [ -z "$LATEST_META_VERSION" ]; then

        if get_latest_meta_core_version 0; then

            _oc_ok "最新 Meta Core：$LATEST_META_VERSION"

        else

            _oc_warn "暂时无法获取官方最新 Meta Core 版本"

        fi

    fi


    # ========================================================
    # 已是最新版
    # ========================================================

    if [ -n "$OLD_META_VERSION" ] &&
       [ -n "$LATEST_META_VERSION" ] &&
       [ "$OLD_META_VERSION" = "$LATEST_META_VERSION" ]
    then

        _oc_ok "Meta / Mihomo 内核已经是最新版本"

        cleanup_openclash_temp
        cleanup_core_update

        return 0
    fi


    # ========================================================
    # 需要更新
    # ========================================================

    if [ -n "$LATEST_META_VERSION" ]; then

        if [ -n "$OLD_META_VERSION" ]; then

            _oc_info "发现新版本：$LATEST_META_VERSION"

            _oc_info "准备自动更新..."

        else

            _oc_info "准备安装 Meta Core：$LATEST_META_VERSION"

        fi

    else

        _oc_info "将调用官方脚本自动检查并更新 Meta Core"

    fi


    printf "\n"


    CORE_UPDATE_SUCCESS=0
    DIRECT_CORE_TRIED=0


    # ========================================================
    # 按测速排名依次调用官方脚本
    # ========================================================

    if [ "$CORE_ROUTE_AVAILABLE" -eq 1 ]; then

        while IFS='|' read -r \
            ROUTE_SCORE \
            ROUTE_NAME \
            ROUTE_PREFIX \
            ROUTE_URL \
            ROUTE_TTFB \
            ROUTE_SPEED
        do

            [ -n "$ROUTE_NAME" ] ||
                continue


            if [ "$ROUTE_NAME" = "DIRECT" ]; then
                DIRECT_CORE_TRIED=1
            fi


            ROUTE_SPEED_MB="$(
                oc_speed_to_mb "$ROUTE_SPEED"
            )"


            _oc_info "尝试 Core 下载线路：$ROUTE_NAME"

            _oc_info "测速速度：${ROUTE_SPEED_MB} MB/s"


            run_official_meta_core_update \
                "$ROUTE_NAME" \
                "$ROUTE_PREFIX"


            # =================================================
            # 真实验证 Core
            # =================================================

            sleep 1


            if get_meta_core_version; then

                NEW_META_VERSION="$META_CORE_VERSION"


                _oc_info "验证版本：$NEW_META_VERSION"


                # ---------------------------------------------
                # 已知最新版本时必须一致
                # ---------------------------------------------

                if [ -n "$LATEST_META_VERSION" ]; then

                    if [ "$NEW_META_VERSION" = "$LATEST_META_VERSION" ]; then

                        CORE_UPDATE_SUCCESS=1

                        _oc_ok "Meta / Mihomo 内核更新成功"

                        _oc_info "当前版本：$NEW_META_VERSION"

                        break
                    fi


                # ---------------------------------------------
                # 无法获取 latest 时：
                # 新安装成功，或版本发生变化，也视为成功
                # ---------------------------------------------

                else

                    if [ -z "$OLD_META_VERSION" ] ||
                       [ "$NEW_META_VERSION" != "$OLD_META_VERSION" ]
                    then

                        CORE_UPDATE_SUCCESS=1

                        _oc_ok "Meta / Mihomo 内核安装/更新成功"

                        _oc_info "当前版本：$NEW_META_VERSION"

                        break
                    fi
                fi

            fi


            _oc_warn "$ROUTE_NAME Core 更新验证失败，切换下一线路..."


        done < "$OC_ROUTE_FILE"

    fi


    # ========================================================
    # DIRECT 最终兜底
    # ========================================================

    if [ "$CORE_UPDATE_SUCCESS" -ne 1 ] &&
       [ "$DIRECT_CORE_TRIED" -ne 1 ]
    then

        printf "\n"

        _oc_info "正在使用 GitHub 官方直连更新 Meta Core..."


        run_official_meta_core_update \
            "DIRECT" \
            ""


        sleep 1


        if get_meta_core_version; then

            NEW_META_VERSION="$META_CORE_VERSION"


            if [ -n "$LATEST_META_VERSION" ]; then

                if [ "$NEW_META_VERSION" = "$LATEST_META_VERSION" ]; then
                    CORE_UPDATE_SUCCESS=1
                fi

            else

                if [ -z "$OLD_META_VERSION" ] ||
                   [ "$NEW_META_VERSION" != "$OLD_META_VERSION" ]
                then
                    CORE_UPDATE_SUCCESS=1
                fi
            fi

        fi

    fi


    # ========================================================
    # 最终验证
    # ========================================================

    printf "\n"

    _oc_info "正在进行最终 Meta Core 验证..."


    if get_meta_core_version; then

        _oc_ok "Meta / Mihomo 内核运行正常"

        _oc_info "当前版本：$META_CORE_VERSION"


        if [ -n "$LATEST_META_VERSION" ]; then

            if [ "$META_CORE_VERSION" = "$LATEST_META_VERSION" ]; then

                _oc_ok "当前已是官方最新版本"

                CORE_UPDATE_SUCCESS=1

            else

                _oc_warn "当前版本与官方最新版本不一致"

                _oc_info "当前：$META_CORE_VERSION"

                _oc_info "最新：$LATEST_META_VERSION"

            fi
        fi

    else

        _oc_error "Meta / Mihomo 内核验证失败"

    fi


    # ========================================================
    # 更新失败显示官方日志
    # ========================================================

    if [ "$CORE_UPDATE_SUCCESS" -ne 1 ]; then

        _oc_error "Meta Core 自动更新未成功"


        if [ -s "$OC_CORE_UPDATE_LOG" ]; then

            printf "\n"

            printf "========== CORE UPDATE LOG ==========\n"

            tail -n 40 "$OC_CORE_UPDATE_LOG"

            printf "=====================================\n"

        fi

    fi


    cleanup_openclash_temp
    cleanup_core_update


    [ "$CORE_UPDATE_SUCCESS" -eq 1 ]
}


# ============================================================
# 刷新 LuCI
# ============================================================

reload_luci()
{
    if [ -x /etc/init.d/uhttpd ]; then

        _oc_info "正在刷新 LuCI..."

        /etc/init.d/uhttpd reload \
            >/dev/null 2>&1

    fi


    return 0
}


# ============================================================
# 中断
# ============================================================

interrupt_openclash()
{
    printf "\n"

    _oc_warn "OpenClash 安装被中断"


    if [ -n "$PROGRESS_PID" ]; then

        kill "$PROGRESS_PID" \
            >/dev/null 2>&1

        wait "$PROGRESS_PID" \
            >/dev/null 2>&1
    fi


    if [ -n "$CORE_UPDATE_PID" ]; then

        kill "$CORE_UPDATE_PID" \
            >/dev/null 2>&1

        wait "$CORE_UPDATE_PID" \
            >/dev/null 2>&1
    fi


    cleanup_openclash_package
    cleanup_openclash_temp
    cleanup_core_update


    trap - INT TERM


    return 130
}


# ============================================================
# 主安装函数
# ============================================================

install_openclash()
{
    printf "\n"

    printf "======================================\n"
    printf "        OpenClash Installer\n"
    printf "======================================\n"

    printf "\n"


    # ========================================================
    # Root
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _oc_error "请使用 root 用户运行"

        return 1
    fi


    # ========================================================
    # 工具
    # ========================================================

    if ! command -v curl >/dev/null 2>&1 &&
       ! command -v wget >/dev/null 2>&1
    then

        _oc_error "系统缺少 curl / wget"

        return 1
    fi


    # ========================================================
    # 架构
    # ========================================================

    detect_openclash_arch


    # ========================================================
    # 参数
    # ========================================================

    if [ -z "$DOWNLOAD_URL" ]; then

        _oc_error "DOWNLOAD_URL 为空"

        return 1
    fi


    if [ -z "$PACKAGE_EXT" ]; then

        _oc_error "PACKAGE_EXT 为空"

        return 1
    fi


    if [ -n "$RELEASE_TAG" ]; then

        _oc_info "OpenClash Version : $RELEASE_TAG"

    fi


    _oc_info "Package Format    : $PACKAGE_EXT"


    printf "\n"


    OPENCLASH_PKG="/tmp/openclash.${PACKAGE_EXT}"


    rm -f "$OPENCLASH_PKG"
    rm -f "$INSTALL_LOG"


    cleanup_openclash_temp
    cleanup_core_update


    trap 'interrupt_openclash' INT TERM


    # ========================================================
    # OpenClash 下载
    # ========================================================

    if ! smart_download_openclash \
        "$DOWNLOAD_URL" \
        "$OPENCLASH_PKG"
    then

        printf "\n"

        _oc_error "OpenClash 下载失败"

        _oc_error "所有下载线路均不可用"


        cleanup_openclash_package
        cleanup_openclash_temp

        trap - INT TERM

        return 1
    fi


    _oc_ok "OpenClash 下载完成"


    SIZE="$(
        du -h "$OPENCLASH_PKG" 2>/dev/null |
        awk '{print $1}'
    )"


    if [ -n "$SIZE" ]; then
        _oc_info "File Size : $SIZE"
    fi


    printf "\n"


    # ========================================================
    # 安装
    # ========================================================

    case "$PACKAGE_EXT" in

        apk)

            if ! command -v apk >/dev/null 2>&1; then

                _oc_error "当前系统没有 APK 包管理器"

                cleanup_openclash_package

                trap - INT TERM

                return 1
            fi


            install_openclash_with_progress \
                "$OPENCLASH_PKG" \
                "apk"

            INSTALL_RESULT=$?

            ;;


        ipk)

            if ! command -v opkg >/dev/null 2>&1; then

                _oc_error "当前系统没有 OPKG 包管理器"

                cleanup_openclash_package

                trap - INT TERM

                return 1
            fi


            install_openclash_with_progress \
                "$OPENCLASH_PKG" \
                "ipk"

            INSTALL_RESULT=$?

            ;;


        *)

            _oc_error "未知软件包格式：$PACKAGE_EXT"

            cleanup_openclash_package

            trap - INT TERM

            return 1

            ;;

    esac


    # ========================================================
    # 安装失败
    # ========================================================

    if [ "$INSTALL_RESULT" -ne 0 ]; then

        printf "\n"

        _oc_error "OpenClash 安装失败"


        if [ -s "$INSTALL_LOG" ]; then

            printf "\n"

            printf "========== INSTALL ERROR ==========\n"

            cat "$INSTALL_LOG"

            printf "===================================\n"

        fi


        cleanup_openclash_package
        cleanup_openclash_temp

        trap - INT TERM

        return 1
    fi


    cleanup_openclash_package


    printf "\n"


    # ========================================================
    # 验证 OpenClash
    # ========================================================

    _oc_info "正在验证 OpenClash 安装结果..."


    if ! check_openclash; then

        _oc_error "未检测到 luci-app-openclash"

        _oc_error "OpenClash 可能没有正确安装"


        if [ -s "$INSTALL_LOG" ]; then

            printf "\n"

            cat "$INSTALL_LOG"
        fi


        cleanup_openclash_logs
        cleanup_openclash_temp

        trap - INT TERM

        return 1
    fi


    _oc_ok "OpenClash 安装成功"


    get_installed_openclash_version


    _oc_info "已安装版本 : $OPENCLASH_VERSION"


    cleanup_openclash_logs


    mkdir -p "$OPENCLASH_CORE_DIR" \
        >/dev/null 2>&1


    # ========================================================
    # 第一次检测 Core
    # ========================================================

    check_openclash_core


    # ========================================================
    # 自动检查 / 安装 / 更新 Meta Core
    # ========================================================

    if auto_update_openclash_core; then

        _oc_ok "Meta Core 检查/更新完成"

    else

        _oc_warn "Meta Core 自动更新存在异常"

        _oc_info "OpenClash 本体已安装，不影响进入 LuCI 后继续处理"

    fi


    # ========================================================
    # 再次验证 Core
    # ========================================================

    check_openclash_core


    # ========================================================
    # LuCI
    # ========================================================

    reload_luci


    trap - INT TERM


    # ========================================================
    # 完成
    # ========================================================

    printf "\n"

    printf "======================================\n"
    printf "        OpenClash Installed\n"
    printf "======================================\n"

    printf "\n"


    _oc_ok "OpenClash 安装完成"

    _oc_info "版本 : $OPENCLASH_VERSION"

    _oc_info "CPU  : $OPENCLASH_ARCH"

    _oc_info "Core : $OPENCLASH_CORE_ARCH"


    if get_meta_core_version; then

        _oc_info "Meta : $META_CORE_VERSION"

    else

        _oc_warn "Meta : 未安装"

    fi


    printf "\n"

    printf "LuCI：服务 → OpenClash\n"

    printf "内核：OpenClash → 版本更新\n"

    printf "\n"


    return 0
}

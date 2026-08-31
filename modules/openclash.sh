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
# 21. 自动检查基础运行环境
# 22. 自动检查 Meta Core 更新依赖
# 23. 兼容旧版 linux-armv8 → linux-arm64
# 24. Core 更新采用完整测速 URL
# 25. Core 未真实验证前不显示 100%
#
# 26. 自动下载并运行 openclash-swap
#     与 27 共用同一份 GH01-GH06 + DIRECT 测速结果
#     并将完整线路排名传递给 openclash-swap
#
# 27. 自动下载并安装 openclash-smart-select
#     保存到 /usr/bin/openclash-smart-select
#     自动添加执行权限
#
# 28. 自动添加 Smart Select 定时任务
#     每 30 分钟自动运行一次
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
# 26 / 27 / 28 扩展功能配置
# ============================================================

OC_SCRIPT_ROUTE_FILE="/tmp/openpro_openclash_script_routes"

OPENCLASH_SWAP_URL="https://raw.githubusercontent.com/zimoadmin/Open-Pro-Installer/refs/heads/main/modules/openclash-swap"

OPENCLASH_SMART_SELECT_URL="https://raw.githubusercontent.com/zimoadmin/Open-Pro-Installer/refs/heads/main/modules/openclash-smart-select.sh"

OPENCLASH_SMART_SELECT_PATH="/usr/bin/openclash-smart-select"

OPENCLASH_SMART_SELECT_CRON_LOG="/tmp/openclash-smart-select.log"


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


cleanup_openclash_script_routes()
{
    rm -f \
        "$OC_SCRIPT_ROUTE_FILE" \
        2>/dev/null

    return 0
}


# ============================================================
# 基础运行环境检查
# ============================================================

check_openclash_runtime()
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
        wc \
        du \
        uci
    do

        if ! command -v "$CMD" >/dev/null 2>&1; then
            MISSING="$MISSING $CMD"
        fi

    done


    if [ -n "$MISSING" ]; then

        _oc_error "系统缺少基础命令:$MISSING"

        return 1
    fi


    return 0
}


# ============================================================
# Meta Core 更新环境检查
# ============================================================

check_openclash_core_runtime()
{
    MISSING=""


    for CMD in \
        bash \
        lua \
        jsonfilter \
        uci \
        curl \
        gzip \
        tar \
        flock \
        tr
    do

        if ! command -v "$CMD" >/dev/null 2>&1; then
            MISSING="$MISSING $CMD"
        fi

    done


    if [ -n "$MISSING" ]; then

        _oc_warn "Meta Core 更新缺少依赖:$MISSING"

        return 1
    fi


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
            apk info -v luci-app-openclash 2>/dev/null |
            sed -n '1p' |
            sed 's/^luci-app-openclash-//'
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


    if ! command -v curl >/dev/null 2>&1; then

        _oc_warn "系统未安装 curl，无法执行智能测速"

        rm -rf "$OC_TEST_DIR"

        return 1
    fi


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
# 26 / 27
# 生成一份共享 GH01-GH06 + DIRECT 测速结果
#
# 只执行一次测速
#
# 缓存格式：
# score|name|prefix|ttfb|speed
# ============================================================

prepare_openclash_script_routes()
{
    cleanup_openclash_script_routes


    printf "\n"

    _oc_info "正在为 OpenClash 扩展功能筛选最佳下载线路..."


    if ! prepare_openclash_routes \
        "$OPENCLASH_SWAP_URL"
    then

        _oc_warn "扩展功能下载线路测速失败"

        cleanup_openclash_temp

        return 1
    fi


    if [ ! -s "$OC_ROUTE_FILE" ]; then

        _oc_warn "没有生成有效扩展下载线路"

        cleanup_openclash_temp

        return 1
    fi


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


        printf '%s|%s|%s|%s|%s\n' \
            "$ROUTE_SCORE" \
            "$ROUTE_NAME" \
            "$ROUTE_PREFIX" \
            "$ROUTE_TTFB" \
            "$ROUTE_SPEED" \
            >> "$OC_SCRIPT_ROUTE_FILE"


    done < "$OC_ROUTE_FILE"


    rm -f \
        "$OC_ROUTE_FILE" \
        "$OC_SORTED_FILE" \
        "$OC_TEST_FILE" \
        "$OC_DOWNLOAD_LOG" \
        2>/dev/null

    rm -rf "$OC_TEST_DIR" 2>/dev/null


    if [ ! -s "$OC_SCRIPT_ROUTE_FILE" ]; then

        _oc_warn "扩展功能测速缓存生成失败"

        return 1
    fi


    SCRIPT_BEST_LINE="$(
        sed -n '1p' \
            "$OC_SCRIPT_ROUTE_FILE"
    )"


    SCRIPT_BEST_NAME="$(
        printf '%s\n' "$SCRIPT_BEST_LINE" |
        cut -d '|' -f 2
    )"


    SCRIPT_BEST_TTFB="$(
        printf '%s\n' "$SCRIPT_BEST_LINE" |
        cut -d '|' -f 4
    )"


    SCRIPT_BEST_SPEED="$(
        printf '%s\n' "$SCRIPT_BEST_LINE" |
        cut -d '|' -f 5
    )"


    _oc_ok "扩展功能最佳线路：$SCRIPT_BEST_NAME"

    _oc_info "首包时间：${SCRIPT_BEST_TTFB} ms"

    _oc_info "下载速度：$(oc_speed_to_mb "$SCRIPT_BEST_SPEED") MB/s"


    return 0
}


# ============================================================
# 26 / 27
# 使用共享测速结果下载普通 Shell 文件
#
# 不再次测速
#
# $1 = GitHub 原始 URL
# $2 = 输出文件
# ============================================================

smart_download_openclash_script_cached()
{
    ORIGINAL_URL="$1"
    OUTPUT="$2"

    DOWNLOAD_SUCCESS=0
    DIRECT_TRIED=0


    rm -f "$OUTPUT" 2>/dev/null


    if [ ! -s "$OC_SCRIPT_ROUTE_FILE" ]; then

        _oc_warn "没有可用的共享测速结果"

        return 1
    fi


    while IFS='|' read -r \
        ROUTE_SCORE \
        ROUTE_NAME \
        ROUTE_PREFIX \
        ROUTE_TTFB \
        ROUTE_SPEED
    do

        [ -n "$ROUTE_NAME" ] ||
            continue


        if [ "$ROUTE_NAME" = "DIRECT" ] ||
           [ -z "$ROUTE_PREFIX" ]
        then

            ROUTE_URL="$ORIGINAL_URL"

            DIRECT_TRIED=1

        else

            ROUTE_URL="$(
                build_openclash_url \
                    "$ROUTE_PREFIX" \
                    "$ORIGINAL_URL"
            )"

        fi


        ROUTE_SPEED_MB="$(
            oc_speed_to_mb "$ROUTE_SPEED"
        )"


        _oc_info "正在使用线路：$ROUTE_NAME"

        _oc_info "复用测速速度：${ROUTE_SPEED_MB} MB/s"


        rm -f "$OUTPUT" 2>/dev/null


        curl -4 \
            -L \
            -f \
            -sS \
            --connect-timeout 8 \
            --max-time 120 \
            --retry 1 \
            --retry-delay 1 \
            -o "$OUTPUT" \
            "$ROUTE_URL" \
            >/dev/null 2>&1


        if [ $? -eq 0 ] &&
           [ -s "$OUTPUT" ]
        then

            if ! head -c 1024 "$OUTPUT" 2>/dev/null |
                grep -Eqi \
                '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
            then

                _oc_ok "下载线路：$ROUTE_NAME"

                DOWNLOAD_SUCCESS=1

                break
            fi

        fi


        rm -f "$OUTPUT" 2>/dev/null


        _oc_warn "$ROUTE_NAME 下载失败，自动切换下一线路..."


    done < "$OC_SCRIPT_ROUTE_FILE"


    # ========================================================
    # DIRECT 最终兜底
    # ========================================================

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] &&
       [ "$DIRECT_TRIED" -ne 1 ]
    then

        _oc_info "正在尝试 GitHub 官方直连..."


        rm -f "$OUTPUT" 2>/dev/null


        curl -4 \
            -L \
            -f \
            -sS \
            --connect-timeout 8 \
            --max-time 120 \
            --retry 1 \
            --retry-delay 1 \
            -o "$OUTPUT" \
            "$ORIGINAL_URL" \
            >/dev/null 2>&1


        if [ $? -eq 0 ] &&
           [ -s "$OUTPUT" ]
        then

            if ! head -c 1024 "$OUTPUT" 2>/dev/null |
                grep -Eqi \
                '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
            then

                _oc_ok "GitHub 官方直连下载成功"

                DOWNLOAD_SUCCESS=1
            fi

        fi

    fi


    [ "$DOWNLOAD_SUCCESS" -eq 1 ]
}


# ============================================================
# 26. 下载并运行 OpenClash Swap
#
# 下载 openclash-swap 时：
# 使用共享测速排名
#
# openclash-swap 内部下载配置时：
# 通过 OPENPRO_SCRIPT_ROUTE_FILE
# 再次复用完全相同的线路排名
# ============================================================

run_openclash_swap()
{
    SWAP_TMP="/tmp/openclash-swap.$$"


    printf "\n"

    _oc_info "正在下载 OpenClash 文件替换脚本..."


    if ! smart_download_openclash_script_cached \
        "$OPENCLASH_SWAP_URL" \
        "$SWAP_TMP"
    then

        rm -f "$SWAP_TMP" 2>/dev/null

        _oc_warn "OpenClash 文件替换脚本下载失败"

        return 1
    fi


    if [ ! -s "$SWAP_TMP" ]; then

        rm -f "$SWAP_TMP" 2>/dev/null

        _oc_warn "OpenClash 文件替换脚本为空"

        return 1
    fi


    chmod 755 \
        "$SWAP_TMP" \
        >/dev/null 2>&1


    _oc_info "正在执行 OpenClash 文件智能替换..."


    OPENPRO_SCRIPT_ROUTE_FILE="$OC_SCRIPT_ROUTE_FILE" \
        sh "$SWAP_TMP"


    SWAP_RESULT=$?


    rm -f \
        "$SWAP_TMP" \
        >/dev/null 2>&1


    if [ "$SWAP_RESULT" -eq 0 ]; then

        _oc_ok "OpenClash 文件替换完成"

        return 0

    fi


    _oc_warn "OpenClash 文件替换执行失败"

    return 1
}


# ============================================================
# 27. 安装 OpenClash Smart Select
#
# 继续复用同一份 GH01-GH06 + DIRECT 测速排名
# ============================================================

install_openclash_smart_select()
{
    SMART_SELECT_TMP="/tmp/openclash-smart-select.$$"


    printf "\n"

    _oc_info "正在下载 OpenClash Smart Select..."


    if ! smart_download_openclash_script_cached \
        "$OPENCLASH_SMART_SELECT_URL" \
        "$SMART_SELECT_TMP"
    then

        rm -f "$SMART_SELECT_TMP" 2>/dev/null

        _oc_warn "OpenClash Smart Select 下载失败"

        return 1
    fi


    if [ ! -s "$SMART_SELECT_TMP" ]; then

        rm -f "$SMART_SELECT_TMP" 2>/dev/null

        _oc_warn "OpenClash Smart Select 文件为空"

        return 1
    fi


    if head -c 1024 "$SMART_SELECT_TMP" 2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
    then

        rm -f "$SMART_SELECT_TMP" 2>/dev/null

        _oc_warn "OpenClash Smart Select 下载内容异常"

        return 1
    fi


    rm -f \
        "$OPENCLASH_SMART_SELECT_PATH" \
        >/dev/null 2>&1


    if ! mv \
        "$SMART_SELECT_TMP" \
        "$OPENCLASH_SMART_SELECT_PATH"
    then

        rm -f "$SMART_SELECT_TMP" 2>/dev/null

        _oc_warn "OpenClash Smart Select 安装失败"

        return 1
    fi


    if ! chmod +x \
        "$OPENCLASH_SMART_SELECT_PATH"
    then

        _oc_warn "OpenClash Smart Select 设置执行权限失败"

        return 1
    fi


    if [ ! -x "$OPENCLASH_SMART_SELECT_PATH" ]; then

        _oc_warn "OpenClash Smart Select 安装验证失败"

        return 1
    fi


    _oc_ok "OpenClash Smart Select 安装完成"

    _oc_info "安装路径：$OPENCLASH_SMART_SELECT_PATH"


    return 0
}


# ============================================================
# 28. 添加每 30 分钟 Smart Select 定时任务
# ============================================================

setup_openclash_smart_select_cron()
{
    CRON_FILE="/etc/crontabs/root"
    CRON_TMP="/tmp/openclash-smart-select-cron.tmp"


    printf "\n"

    _oc_info "正在配置 OpenClash Smart Select 定时任务..."


    if [ ! -x "$OPENCLASH_SMART_SELECT_PATH" ]; then

        _oc_warn "没有检测到 $OPENCLASH_SMART_SELECT_PATH"

        _oc_warn "跳过 Smart Select 定时任务"

        return 1
    fi


    mkdir -p /etc/crontabs \
        >/dev/null 2>&1


    touch "$CRON_FILE" \
        >/dev/null 2>&1


    rm -f "$CRON_TMP" 2>/dev/null


    grep -v \
        '/usr/bin/openclash-smart-select' \
        "$CRON_FILE" \
        2>/dev/null \
        > "$CRON_TMP"


    echo '*/30 * * * * /usr/bin/openclash-smart-select >/tmp/openclash-smart-select.log 2>&1' \
        >> "$CRON_TMP"


    if ! mv \
        "$CRON_TMP" \
        "$CRON_FILE"
    then

        rm -f "$CRON_TMP" 2>/dev/null

        _oc_warn "Smart Select Cron 写入失败"

        return 1
    fi


    if [ ! -x /etc/init.d/cron ]; then

        _oc_warn "没有找到 /etc/init.d/cron"

        return 1
    fi


    /etc/init.d/cron restart \
        >/dev/null 2>&1


    if ! grep -q \
        '^\*/30 \* \* \* \* /usr/bin/openclash-smart-select ' \
        "$CRON_FILE" \
        2>/dev/null
    then

        _oc_warn "Smart Select Cron 验证失败"

        return 1
    fi


    _oc_ok "Smart Select 定时任务配置完成"

    _oc_info "执行周期：每 30 分钟"

    _oc_info "执行脚本：$OPENCLASH_SMART_SELECT_PATH"

    _oc_info "运行日志：$OPENCLASH_SMART_SELECT_CRON_LOG"


    return 0
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
    CURRENT_CORE_MODEL="$(
        uci -q get openclash.config.core_version \
        2>/dev/null
    )"


    OPENCLASH_CORE_CPU_MODEL="$CURRENT_CORE_MODEL"

    NEED_SAVE_CORE_MODEL=0


    case "$OPENCLASH_CORE_CPU_MODEL" in

        ""|0)

            OPENCLASH_CORE_CPU_MODEL="$OPENCLASH_CORE_ARCH"

            NEED_SAVE_CORE_MODEL=1

            ;;


        linux-armv8)

            OPENCLASH_CORE_CPU_MODEL="linux-arm64"

            NEED_SAVE_CORE_MODEL=1

            _oc_info "检测到旧 Core 架构：linux-armv8"

            ;;

    esac


    if [ "$OPENCLASH_CORE_CPU_MODEL" = "unknown" ] ||
       [ -z "$OPENCLASH_CORE_CPU_MODEL" ]
    then

        _oc_error "无法识别 OpenClash Core CPU 架构"

        return 1
    fi


    if [ "$NEED_SAVE_CORE_MODEL" -eq 1 ]; then

        uci -q set \
            "openclash.config.core_version=$OPENCLASH_CORE_CPU_MODEL" \
            >/dev/null 2>&1

        uci commit openclash \
            >/dev/null 2>&1


        if [ "$CURRENT_CORE_MODEL" = "linux-armv8" ]; then

            _oc_info "已修正 Core 架构：linux-armv8 → linux-arm64"

        else

            _oc_info "已自动设置 Core 架构：$OPENCLASH_CORE_CPU_MODEL"

        fi

    fi


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


core_update_progress_success()
{
    ROUTE_NAME="$1"


    core_update_progress \
        100 \
        "$ROUTE_NAME"


    printf "\n"
}


# ============================================================
# 调用 OpenClash 官方 Core 更新脚本
# ============================================================

run_official_meta_core_update()
{
    ROUTE_NAME="$1"
    ROUTE_URL="$2"


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


    if [ -n "$ROUTE_URL" ]; then

        "$CORE_UPDATE_SCRIPT" \
            Meta \
            "$ROUTE_URL" \
            > "$OC_CORE_UPDATE_LOG" 2>&1 &

    else

        "$CORE_UPDATE_SCRIPT" \
            Meta \
            0 \
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
            'Update Successful' \
            "$OC_CORE_UPDATE_LOG" \
            2>/dev/null
        then

            if [ "$CORE_PERCENT" -lt 94 ]; then
                CORE_PERCENT=$((CORE_PERCENT + 5))
            fi


        elif grep -qi \
            'Download Successful' \
            "$OC_CORE_UPDATE_LOG" \
            2>/dev/null
        then

            if [ "$CORE_PERCENT" -lt 88 ]; then
                CORE_PERCENT=$((CORE_PERCENT + 4))
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


    core_update_progress \
        95 \
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


    if ! check_openclash_core_runtime; then

        _oc_warn "当前环境无法自动更新 Meta Core"

        return 1
    fi


    if ! detect_openclash_core_cpu_model; then
        return 1
    fi


    _oc_info "Core 架构：$OPENCLASH_CORE_CPU_MODEL"

    _oc_info "Core 分支：$OPENCLASH_RELEASE_BRANCH"


    OLD_META_VERSION=""


    if get_meta_core_version; then

        OLD_META_VERSION="$META_CORE_VERSION"

        _oc_info "当前版本：$OLD_META_VERSION"

    else

        _oc_warn "当前尚未安装 Meta / Mihomo 内核"

    fi


    CORE_TEST_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/${OPENCLASH_RELEASE_BRANCH}/meta/clash-${OPENCLASH_CORE_CPU_MODEL}.tar.gz"


    printf "\n"

    _oc_info "正在筛选 Meta Core 最佳下载线路..."


    prepare_openclash_routes "$CORE_TEST_URL"


    CORE_ROUTE_AVAILABLE=0


    if [ -s "$OC_ROUTE_FILE" ]; then
        CORE_ROUTE_AVAILABLE=1
    fi


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


    if [ -z "$LATEST_META_VERSION" ]; then

        if get_latest_meta_core_version 0; then

            _oc_ok "最新 Meta Core：$LATEST_META_VERSION"

        else

            _oc_warn "暂时无法获取官方最新 Meta Core 版本"

        fi

    fi


    if [ -n "$OLD_META_VERSION" ] &&
       [ -n "$LATEST_META_VERSION" ] &&
       [ "$OLD_META_VERSION" = "$LATEST_META_VERSION" ]
    then

        _oc_ok "Meta / Mihomo 内核已经是最新版本"

        cleanup_openclash_temp
        cleanup_core_update

        return 0
    fi


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

            [ -n "$ROUTE_URL" ] ||
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
                "$ROUTE_URL"


            sleep 1


            if get_meta_core_version; then

                NEW_META_VERSION="$META_CORE_VERSION"


                _oc_info "验证版本：$NEW_META_VERSION"


                if [ -n "$LATEST_META_VERSION" ]; then

                    if [ "$NEW_META_VERSION" = "$LATEST_META_VERSION" ]; then

                        CORE_UPDATE_SUCCESS=1


                        core_update_progress_success \
                            "$ROUTE_NAME"


                        _oc_ok "Meta / Mihomo 内核更新成功"

                        _oc_info "当前版本：$NEW_META_VERSION"

                        break
                    fi


                else

                    if [ -z "$OLD_META_VERSION" ] ||
                       [ "$NEW_META_VERSION" != "$OLD_META_VERSION" ]
                    then

                        CORE_UPDATE_SUCCESS=1


                        core_update_progress_success \
                            "$ROUTE_NAME"


                        _oc_ok "Meta / Mihomo 内核安装/更新成功"

                        _oc_info "当前版本：$NEW_META_VERSION"

                        break
                    fi

                fi

            fi


            _oc_warn "$ROUTE_NAME Core 更新验证失败，切换下一线路..."


        done < "$OC_ROUTE_FILE"

    fi


    if [ "$CORE_UPDATE_SUCCESS" -ne 1 ] &&
       [ "$DIRECT_CORE_TRIED" -ne 1 ]
    then

        printf "\n"

        _oc_info "正在使用 GitHub 官方直连更新 Meta Core..."


        run_official_meta_core_update \
            "DIRECT" \
            "$CORE_TEST_URL"


        sleep 1


        if get_meta_core_version; then

            NEW_META_VERSION="$META_CORE_VERSION"


            _oc_info "验证版本：$NEW_META_VERSION"


            if [ -n "$LATEST_META_VERSION" ]; then

                if [ "$NEW_META_VERSION" = "$LATEST_META_VERSION" ]; then

                    CORE_UPDATE_SUCCESS=1

                    core_update_progress_success \
                        "DIRECT"

                fi

            else

                if [ -z "$OLD_META_VERSION" ] ||
                   [ "$NEW_META_VERSION" != "$OLD_META_VERSION" ]
                then

                    CORE_UPDATE_SUCCESS=1

                    core_update_progress_success \
                        "DIRECT"

                fi

            fi

        fi

    fi


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

        elif [ -n "$META_CORE_VERSION" ]; then

            if [ -z "$OLD_META_VERSION" ]; then
                CORE_UPDATE_SUCCESS=1
            fi

        fi

    else

        _oc_error "Meta / Mihomo 内核验证失败"

    fi


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
    cleanup_openclash_script_routes


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


    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _oc_error "请使用 root 用户运行"

        return 1
    fi


    if ! check_openclash_runtime; then

        return 1

    fi


    if ! command -v curl >/dev/null 2>&1 &&
       ! command -v wget >/dev/null 2>&1
    then

        _oc_error "系统缺少 curl / wget"

        return 1
    fi


    if ! command -v curl >/dev/null 2>&1; then

        _oc_warn "当前系统没有 curl"

        _oc_warn "OpenClash 软件包仍可尝试使用 wget 下载"

        _oc_warn "但多线路测速与 Meta Core 自动更新将受到限制"

    fi


    detect_openclash_arch


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
    cleanup_openclash_script_routes


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
    # 26 / 27
    # 只执行一次 GH01-GH06 + DIRECT 并行测速
    # ========================================================

    EXT_ROUTE_READY=0


    if prepare_openclash_script_routes; then

        EXT_ROUTE_READY=1

    else

        _oc_warn "扩展功能 GitHub 线路测速失败"

        _oc_info "OpenClash 本体和 Meta Core 不受影响"

    fi


    # ========================================================
    # 26. OpenClash Swap
    # ========================================================

    if [ "$EXT_ROUTE_READY" -eq 1 ]; then

        if run_openclash_swap; then

            _oc_ok "OpenClash Swap 执行完成"

        else

            _oc_warn "OpenClash Swap 执行存在异常"

            _oc_info "OpenClash 本体和 Meta Core 不受影响"

        fi

    else

        _oc_warn "没有共享测速结果，跳过 OpenClash Swap"

    fi


    # ========================================================
    # 27. OpenClash Smart Select
    # ========================================================

    SMART_SELECT_INSTALLED=0


    if [ "$EXT_ROUTE_READY" -eq 1 ]; then

        if install_openclash_smart_select; then

            SMART_SELECT_INSTALLED=1

        else

            _oc_warn "OpenClash Smart Select 安装存在异常"

            _oc_info "OpenClash 本体和 Meta Core 不受影响"

        fi

    else

        _oc_warn "没有共享测速结果，跳过 OpenClash Smart Select"

    fi


    # ========================================================
    # 28. 每 30 分钟自动运行 Smart Select
    # ========================================================

    if [ "$SMART_SELECT_INSTALLED" -eq 1 ]; then

        if setup_openclash_smart_select_cron; then

            _oc_ok "OpenClash Smart Select 自动任务配置完成"

        else

            _oc_warn "OpenClash Smart Select 自动任务配置存在异常"

            _oc_info "不会影响 OpenClash 正常使用"

        fi

    else

        _oc_warn "Smart Select 未成功安装，跳过 Cron 配置"

    fi


    # 26 / 27 / 28 已全部处理完
    cleanup_openclash_script_routes


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


    if [ -x "$OPENCLASH_SMART_SELECT_PATH" ]; then

        _oc_info "Smart Select : 已安装"

    fi


    if grep -q \
        '/usr/bin/openclash-smart-select' \
        /etc/crontabs/root \
        2>/dev/null
    then

        _oc_info "Smart Select Cron : 每 30 分钟"

    fi


    printf "\n"

    printf "LuCI：服务 → OpenClash\n"

    printf "内核：OpenClash → 版本更新\n"

    printf "\n"


    return 0
}

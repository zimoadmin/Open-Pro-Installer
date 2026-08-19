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
# 14. 自动检测 Meta / Mihomo / Clash / TUN Core
# 15. 自动检测 OpenClash 更新组件
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

PROGRESS_PID=""

OPENCLASH_VERSION=""
OPENCLASH_ARCH=""
OPENCLASH_CORE_ARCH=""

OPENCLASH_DIR="/etc/openclash"
OPENCLASH_CORE_DIR="/etc/openclash/core"


# ============================================================
# 测速设置
# ============================================================

OC_TEST_CONNECT_TIMEOUT=4

# 并行测速，可以适当增加单线路测试时间
OC_TEST_MAX_TIME=6

# 综合排名按 10MB 文件预计下载时间计算
OC_SCORE_FILE_KB=10240


# ============================================================
# GitHub 下载线路
#
# 格式：
#
# 名称|代理前缀
#
# DIRECT| = GitHub 官方直连
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

        printf '\033[32m[INFO]\033[0m %s\n' "$*"

    fi
}


_oc_warn()
{
    if command -v warning >/dev/null 2>&1; then

        warning "$*"

    elif command -v warn >/dev/null 2>&1; then

        warn "$*"

    else

        printf '\033[33m[WARN]\033[0m %s\n' "$*"

    fi
}


_oc_error()
{
    if command -v error >/dev/null 2>&1; then

        error "$*"

    else

        printf '\033[31m[ERROR]\033[0m %s\n' "$*"

    fi
}


_oc_ok()
{
    printf '\033[32m[OK]\033[0m %s\n' "$*"
}


# ============================================================
# 清理
# ============================================================

cleanup_openclash_package()
{
    if [ -n "$OPENCLASH_PKG" ]; then

        rm -f "$OPENCLASH_PKG" \
            2>/dev/null

    fi

    return 0
}


cleanup_openclash_logs()
{
    rm -f "$INSTALL_LOG" \
        2>/dev/null

    rm -f "$OC_DOWNLOAD_LOG" \
        2>/dev/null

    return 0
}


cleanup_openclash_temp()
{
    rm -f "$OC_ROUTE_FILE" \
        2>/dev/null

    rm -f "$OC_SORTED_FILE" \
        2>/dev/null

    rm -f "$OC_TEST_FILE" \
        2>/dev/null

    rm -f "$OC_DOWNLOAD_LOG" \
        2>/dev/null

    rm -rf "$OC_TEST_DIR" \
        2>/dev/null

    return 0
}


# ============================================================
# 检查 OpenClash
# ============================================================

check_openclash()
{
    if command -v opkg >/dev/null 2>&1; then

        opkg status luci-app-openclash \
            2>/dev/null |
        grep -q 'Status:.*installed'

        return $?

    fi


    if command -v apk >/dev/null 2>&1; then

        apk info -e luci-app-openclash \
            >/dev/null 2>&1

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
            opkg status luci-app-openclash \
                2>/dev/null |
            awk -F ': ' '
                /^Version:/ {
                    print $2
                    exit
                }
            '
        )"

    elif command -v apk >/dev/null 2>&1; then

        OPENCLASH_VERSION="$(
            apk info luci-app-openclash \
                2>/dev/null |
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

        printf '%s%s' \
            "$PREFIX" \
            "$ORIGINAL_URL"

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
# 计算综合成绩
#
# Score =
#
# TTFB(ms)
# +
# 按当前速度下载 10MB 预计耗时(ms)
#
# Score 越小越好
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
# 检测测速文件是否为错误网页
# ============================================================

oc_test_is_error_page()
{
    FILE="$1"


    if [ ! -s "$FILE" ]; then

        return 1

    fi


    if head -c 1024 "$FILE" \
        2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
    then

        return 0

    fi


    return 1
}


# ============================================================
# 单条线路真实测速
#
# 参数：
#
# $1 = 测速 URL
# $2 = 独立测速文件
#
# 输出：
#
# TTFB_MS|SPEED_BPS|SIZE_DOWNLOAD|SCORE
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


    # ========================================================
    # curl 返回码
    #
    # 0  = 正常结束
    # 28 = 达到测速时间
    # ========================================================

    case "$CURL_CODE" in

        0|28)

            ;;

        *)

            rm -f "$TEST_FILE"

            return 1

        ;;

    esac


    # ========================================================
    # HTTP
    # ========================================================

    case "$HTTP_CODE" in

        200|206)

            ;;

        *)

            rm -f "$TEST_FILE"

            return 1

        ;;

    esac


    # ========================================================
    # 下载大小
    # ========================================================

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


    # ========================================================
    # 至少收到 4KB
    # ========================================================

    if [ "$RECEIVED_BYTES" -lt 4096 ]; then

        rm -f "$TEST_FILE"

        return 1

    fi


    # ========================================================
    # 检测代理返回错误网页
    # ========================================================

    if oc_test_is_error_page "$TEST_FILE"; then

        rm -f "$TEST_FILE"

        return 1

    fi


    # ========================================================
    # TTFB
    # ========================================================

    TTFB_MS="$(
        oc_seconds_to_ms "$TTFB"
    )"


    case "$TTFB_MS" in

        ''|*[!0-9]*)

            rm -f "$TEST_FILE"

            return 1

        ;;

    esac


    # ========================================================
    # 下载速度
    # ========================================================

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


    # ========================================================
    # 综合成绩
    # ========================================================

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
# 单线路后台测速任务
#
# 每条线路使用：
#
# 独立下载文件
# 独立结果文件
#
# 避免并行测速互相覆盖
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


    # ========================================================
    # 测速失败
    # ========================================================

    if [ "$TEST_RESULT" -ne 0 ] ||
       [ -z "$TEST_DATA" ]
    then

        printf '%s|FAIL\n' \
            "$NODE_NAME" \
            > "$RESULT_FILE"


        rm -f "$TEST_FILE"


        return 1

    fi


    # ========================================================
    # 解析结果
    # ========================================================

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


    # ========================================================
    # 保存结果
    #
    # Name
    # Status
    # Prefix
    # URL
    # TTFB
    # Speed
    # Received
    # Score
    # ========================================================

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
# 并行测速所有线路
# ============================================================

prepare_openclash_routes()
{
    ORIGINAL_URL="$1"


    # ========================================================
    # 清理旧数据
    # ========================================================

    rm -f "$OC_ROUTE_FILE"
    rm -f "$OC_SORTED_FILE"
    rm -f "$OC_TEST_FILE"

    rm -rf "$OC_TEST_DIR"

    mkdir -p "$OC_TEST_DIR"


    printf "\n"


    _oc_info "正在并行测试 OpenClash 下载线路..."


    printf "\n"


    # ========================================================
    # 同时启动全部线路
    # ========================================================

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


    # ========================================================
    # 等待所有测速任务
    # ========================================================

    wait


    # ========================================================
    # 表头
    # ========================================================

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


    # ========================================================
    # 固定顺序显示
    # ========================================================

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


        # ====================================================
        # 没有结果
        # ====================================================

        if [ ! -s "$RESULT_FILE" ]; then

            printf '%-8s %-12s %-14s \033[31m%s\033[0m\n' \
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


        # ====================================================
        # 测速失败
        # ====================================================

        if [ "$RESULT_STATUS" != "OK" ]; then

            printf '%-8s %-12s %-14s \033[31m%s\033[0m\n' \
                "$NODE_NAME" \
                "----" \
                "----" \
                "不可用"


            continue

        fi


        # ====================================================
        # 读取测速结果
        # ====================================================

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


        RECEIVED="$(
            cut -d '|' -f 7 \
                "$RESULT_FILE"
        )"


        SCORE="$(
            cut -d '|' -f 8 \
                "$RESULT_FILE"
        )"


        SPEED_MB="$(
            oc_speed_to_mb "$SPEED_BPS"
        )"


        # ====================================================
        # 显示
        # ====================================================

        printf '%-8s %-12s %-14s \033[32m%s\033[0m\n' \
            "$NODE_NAME" \
            "${TTFB_MS} ms" \
            "${SPEED_MB} MB/s" \
            "可用"


        # ====================================================
        # 保存到候选线路
        #
        # Score|Name|Prefix|URL|TTFB|Speed
        # ====================================================

        printf '%s|%s|%s|%s|%s|%s\n' \
            "$SCORE" \
            "$NODE_NAME" \
            "$NODE_PREFIX" \
            "$TEST_URL" \
            "$TTFB_MS" \
            "$SPEED_BPS" \
            >> "$OC_ROUTE_FILE"

    done


    # ========================================================
    # 删除测速下载文件
    # ========================================================

    rm -f "$OC_TEST_FILE"


    # ========================================================
    # 无可用线路
    # ========================================================

    if [ ! -s "$OC_ROUTE_FILE" ]; then

        printf "\n"


        _oc_warn "没有发现可用测速线路"

        _oc_info "稍后直接尝试 GitHub 官方地址"


        rm -rf "$OC_TEST_DIR"


        return 1

    fi


    # ========================================================
    # 按综合成绩排序
    #
    # 数字越小越好
    # ========================================================

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


    # ========================================================
    # 最佳线路
    # ========================================================

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


    # ========================================================
    # 清理并行测速文件
    # ========================================================

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
        wc -c < "$FILE" \
            2>/dev/null
    )"


    case "$FILE_SIZE" in

        ''|*[!0-9]*)

            FILE_SIZE=0

        ;;

    esac


    # 至少 100KB
    if [ "$FILE_SIZE" -lt 102400 ]; then

        return 1

    fi


    # 防止代理返回网页
    if head -c 1024 "$FILE" \
        2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
    then

        return 1

    fi


    return 0
}


# ============================================================
# CURL 真正下载
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
# WGET 真正下载
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


    prepare_openclash_routes \
        "$ORIGINAL_URL"


    DOWNLOAD_SUCCESS=0

    DIRECT_TRIED=0


    # ========================================================
    # 按测速排名逐个尝试
    # ========================================================

    if [ -s "$OC_ROUTE_FILE" ]; then

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

                DIRECT_TRIED=1

            fi


            ROUTE_SPEED_MB="$(
                oc_speed_to_mb \
                    "$ROUTE_SPEED"
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


    # ========================================================
    # DIRECT 最终兜底
    # ========================================================

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


    if [ "$DOWNLOAD_SUCCESS" -eq 1 ]; then

        return 0

    fi


    return 1
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


    printf '\r\033[2K[INFO] 正在安装 OpenClash... [\033[32m%s\033[0m] %3d%%' \
        "$BAR" \
        "$PERCENT"
}


# ============================================================
# 静默安装 + 动态进度
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


    openclash_progress_bar \
        "$PERCENT"


    while kill -0 "$PROGRESS_PID" \
        2>/dev/null
    do

        if grep -q '^Configuring ' \
            "$INSTALL_LOG" \
            2>/dev/null
        then

            if [ "$PERCENT" -lt 94 ]; then

                PERCENT=$((PERCENT + 3))

            fi


        elif grep -q '^Installing ' \
            "$INSTALL_LOG" \
            2>/dev/null
        then

            if [ "$PERCENT" -lt 78 ]; then

                PERCENT=$((PERCENT + 3))

            fi


        elif grep -q '^Downloading ' \
            "$INSTALL_LOG" \
            2>/dev/null
        then

            if [ "$PERCENT" -lt 48 ]; then

                PERCENT=$((PERCENT + 2))

            fi


        else

            if [ "$PERCENT" -lt 15 ]; then

                PERCENT=$((PERCENT + 1))

            fi

        fi


        if [ "$PERCENT" -gt 95 ]; then

            PERCENT=95

        fi


        openclash_progress_bar \
            "$PERCENT"


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
    OPENCLASH_ARCH="$(
        uname -m \
            2>/dev/null
    )"


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
# 检测 Core
# ============================================================

check_openclash_core()
{
    printf "\n"


    _oc_info "正在检测 OpenClash 内核..."


    CORE_FOUND=0


    # ========================================================
    # Meta / Mihomo
    # ========================================================

    if [ -x "$OPENCLASH_CORE_DIR/clash_meta" ]; then

        CORE_FOUND=1


        _oc_ok "已检测到 Meta / Mihomo 内核"


        CORE_VERSION="$(
            "$OPENCLASH_CORE_DIR/clash_meta" \
                -v \
                2>/dev/null |
            head -n 1
        )"


        if [ -n "$CORE_VERSION" ]; then

            _oc_info "$CORE_VERSION"

        fi

    fi


    # ========================================================
    # Clash
    # ========================================================

    if [ -x "$OPENCLASH_CORE_DIR/clash" ]; then

        CORE_FOUND=1


        _oc_ok "已检测到 Clash 内核"

    fi


    # ========================================================
    # TUN
    # ========================================================

    if [ -x "$OPENCLASH_CORE_DIR/clash_tun" ]; then

        CORE_FOUND=1


        _oc_ok "已检测到 TUN 内核"

    fi


    if [ "$CORE_FOUND" -eq 0 ]; then

        _oc_warn "当前尚未检测到 OpenClash 内核"


        return 1

    fi


    return 0
}


# ============================================================
# 检测更新组件
# ============================================================

auto_update_openclash_core()
{
    printf "\n"


    _oc_info "正在检测 OpenClash 内核更新能力..."


    CORE_UPDATE_SCRIPT=""


    for SCRIPT in \
        /usr/share/openclash/openclash_core.sh \
        /usr/share/openclash/openclash_core_version.sh \
        /usr/share/openclash/openclash_update.sh
    do

        if [ -f "$SCRIPT" ]; then

            CORE_UPDATE_SCRIPT="$SCRIPT"


            break

        fi

    done


    if [ -z "$CORE_UPDATE_SCRIPT" ]; then

        _oc_warn "没有找到 OpenClash 内核更新组件"


        _oc_info "可进入 OpenClash → 版本更新 页面检查内核"


        return 0

    fi


    _oc_ok "检测到 OpenClash 更新组件"


    _oc_info "更新脚本 : $CORE_UPDATE_SCRIPT"


    if [ ! -x "$CORE_UPDATE_SCRIPT" ]; then

        chmod +x "$CORE_UPDATE_SCRIPT" \
            >/dev/null 2>&1

    fi


    _oc_ok "OpenClash 自动更新组件工作正常"


    return 0
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
# 中断处理
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


    # ========================================================
    # 终止可能仍在运行的测速 curl
    # ========================================================

    if [ -d "$OC_TEST_DIR" ]; then

        for PID_FILE in "$OC_TEST_DIR"/pid_*
        do

            [ -f "$PID_FILE" ] ||
                continue


            TEST_PID="$(
                cat "$PID_FILE" \
                    2>/dev/null
            )"


            case "$TEST_PID" in

                ''|*[!0-9]*)

                    ;;

                *)

                    kill "$TEST_PID" \
                        >/dev/null 2>&1

                ;;

            esac

        done

    fi


    cleanup_openclash_package

    cleanup_openclash_temp


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
    # 下载工具
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
    # DOWNLOAD_URL
    # ========================================================

    if [ -z "$DOWNLOAD_URL" ]; then

        _oc_error "DOWNLOAD_URL 为空"


        return 1

    fi


    # ========================================================
    # PACKAGE_EXT
    # ========================================================

    if [ -z "$PACKAGE_EXT" ]; then

        _oc_error "PACKAGE_EXT 为空"


        return 1

    fi


    # ========================================================
    # 版本
    # ========================================================

    if [ -n "$RELEASE_TAG" ]; then

        _oc_info "OpenClash Version : $RELEASE_TAG"

    fi


    _oc_info "Package Format    : $PACKAGE_EXT"


    printf "\n"


    OPENCLASH_PKG="/tmp/openclash.${PACKAGE_EXT}"


    rm -f "$OPENCLASH_PKG"

    rm -f "$INSTALL_LOG"


    cleanup_openclash_temp


    trap 'interrupt_openclash' INT TERM


    # ========================================================
    # 并行测速 + 智能下载
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


    # ========================================================
    # 文件大小
    # ========================================================

    SIZE="$(
        du -h "$OPENCLASH_PKG" \
            2>/dev/null |
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


            printf "\n"

        fi


        cleanup_openclash_package

        cleanup_openclash_temp


        trap - INT TERM


        return 1

    fi


    cleanup_openclash_package


    printf "\n"


    # ========================================================
    # 验证安装
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


    # ========================================================
    # 获取版本
    # ========================================================

    get_installed_openclash_version


    _oc_info "已安装版本 : $OPENCLASH_VERSION"


    cleanup_openclash_logs

    cleanup_openclash_temp


    # ========================================================
    # Core 目录
    # ========================================================

    mkdir -p "$OPENCLASH_CORE_DIR" \
        >/dev/null 2>&1


    # ========================================================
    # Core 检测
    # ========================================================

    check_openclash_core


    # ========================================================
    # 更新组件
    # ========================================================

    auto_update_openclash_core


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


    printf "\n"


    printf "LuCI：服务 → OpenClash\n"

    printf "内核：OpenClash → 版本更新\n"


    printf "\n"


    return 0
}

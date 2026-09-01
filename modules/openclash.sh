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
# 29. 四阶段安装进度
#     [1/4] 安装 OpenClash
#     [2/4] 安装内核
#     [3/4] 替换文件
#     [4/4] 配置脚本
#     + 总体安装进度
#
# BusyBox / OpenWrt /bin/sh Compatible
# ============================================================


# ============================================================
# Open-Pro-Installer
# OpenClash Smart Installer
#
# 四阶段统一进度版
#
# [1/4] 安装 OpenClash
# [2/4] 安装内核
# [3/4] 替换文件
# [4/4] 配置脚本
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
# OpenClash Release
# ============================================================

OPENCLASH_RELEASE_WORKER="https://auth.12334123.xyz/openclash"

OPENCLASH_RELEASE_API="https://api.github.com/repos/vernesong/OpenClash/releases/latest"

OPENCLASH_RELEASE_TMP="/tmp/openpro_openclash_release.json"

OPENCLASH_RELEASE_TIMEOUT=12
OPENCLASH_RELEASE_RETRY=2


# ============================================================
# 扩展脚本
# ============================================================

OC_SCRIPT_ROUTE_FILE="/tmp/openpro_openclash_script_routes"

OPENCLASH_SWAP_URL="https://raw.githubusercontent.com/zimoadmin/Open-Pro-Installer/refs/heads/main/modules/openclash-swap"

OPENCLASH_SMART_SELECT_URL="https://raw.githubusercontent.com/zimoadmin/Open-Pro-Installer/refs/heads/main/modules/openclash-smart-select.sh"

OPENCLASH_SMART_SELECT_PATH="/usr/bin/openclash-smart-select"

OPENCLASH_SMART_SELECT_CRON_LOG="/tmp/openclash-smart-select.log"


# ============================================================
# 测速
# ============================================================

OC_TEST_CONNECT_TIMEOUT=4
OC_TEST_MAX_TIME=6

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
# 四阶段进度
# ============================================================

OC_STAGE_1=0
OC_STAGE_2=0
OC_STAGE_3=0
OC_STAGE_4=0

OC_PROGRESS_ACTIVE=0
OC_PROGRESS_DRAWN=0

# 实际输出行数
OC_PROGRESS_LINES=10


# ============================================================
# 生成进度条
# ============================================================

openclash_make_bar()
{
    PERCENT="$1"
    WIDTH=24

    case "$PERCENT" in
        ''|*[!0-9]*)
            PERCENT=0
            ;;
    esac

    [ "$PERCENT" -lt 0 ] &&
        PERCENT=0

    [ "$PERCENT" -gt 100 ] &&
        PERCENT=100

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

    printf '%s' "$BAR"
}


# ============================================================
# 光标上移
# ============================================================

openclash_cursor_up()
{
    COUNT="$1"
    I=0

    while [ "$I" -lt "$COUNT" ]
    do
        printf '\033[1A'
        I=$((I + 1))
    done
}


# ============================================================
# 单阶段
# ============================================================

openclash_stage_line()
{
    STEP="$1"
    NAME="$2"
    PERCENT="$3"

    BAR="$(
        openclash_make_bar "$PERCENT"
    )"

    printf '\r\033[2K[%s/4] %-14s [\033[1;92m%s\033[0m] %3d%%\n' \
        "$STEP" \
        "$NAME" \
        "$BAR" \
        "$PERCENT"
}


# ============================================================
# 总体进度
# ============================================================

openclash_total_line()
{
    TOTAL_PERCENT=$(( \
        (OC_STAGE_1 + OC_STAGE_2 + OC_STAGE_3 + OC_STAGE_4) / 4 \
    ))

    TOTAL_BAR="$(
        openclash_make_bar "$TOTAL_PERCENT"
    )"

    printf '\r\033[2K总体进度          [\033[1;96m%s\033[0m] %3d%%\n' \
        "$TOTAL_BAR" \
        "$TOTAL_PERCENT"
}


# ============================================================
# 绘制统一进度表
# ============================================================

show_openclash_stage_progress()
{
    [ "$OC_PROGRESS_ACTIVE" = "1" ] ||
        return 0

    if [ "$OC_PROGRESS_DRAWN" = "1" ]; then
        openclash_cursor_up "$OC_PROGRESS_LINES"
    fi

    printf '\r\033[2K====================================================\n'
    printf '\r\033[2K              OpenClash 安装进度\n'
    printf '\r\033[2K====================================================\n'

    openclash_stage_line \
        1 \
        "安装 OpenClash" \
        "$OC_STAGE_1"

    openclash_stage_line \
        2 \
        "安装内核" \
        "$OC_STAGE_2"

    openclash_stage_line \
        3 \
        "替换文件" \
        "$OC_STAGE_3"

    openclash_stage_line \
        4 \
        "配置脚本" \
        "$OC_STAGE_4"

    printf '\r\033[2K----------------------------------------------------\n'

    openclash_total_line

    printf '\r\033[2K====================================================\n'

    OC_PROGRESS_DRAWN=1
}


# ============================================================
# 更新阶段
# ============================================================

openclash_set_stage()
{
    STAGE="$1"
    VALUE="$2"

    case "$VALUE" in
        ''|*[!0-9]*)
            VALUE=0
            ;;
    esac

    [ "$VALUE" -gt 100 ] &&
        VALUE=100

    [ "$VALUE" -lt 0 ] &&
        VALUE=0

    case "$STAGE" in

        1)
            OC_STAGE_1="$VALUE"
            ;;

        2)
            OC_STAGE_2="$VALUE"
            ;;

        3)
            OC_STAGE_3="$VALUE"
            ;;

        4)
            OC_STAGE_4="$VALUE"
            ;;

    esac

    show_openclash_stage_progress
}


# ============================================================
# 启动进度表
# ============================================================

openclash_progress_start()
{
    OC_STAGE_1=0
    OC_STAGE_2=0
    OC_STAGE_3=0
    OC_STAGE_4=0

    OC_PROGRESS_ACTIVE=1
    OC_PROGRESS_DRAWN=0

    printf "\n"

    show_openclash_stage_progress
}


# ============================================================
# 停止进度表
# ============================================================

openclash_progress_stop()
{
    if [ "$OC_PROGRESS_ACTIVE" = "1" ]; then

        OC_PROGRESS_ACTIVE=0
        OC_PROGRESS_DRAWN=0

        printf "\n"

    fi
}


# ============================================================
# 普通日志
#
# 进入安装进度表后自动静默
# ============================================================

_oc_info()
{
    [ "$OC_PROGRESS_ACTIVE" = "1" ] &&
        return 0

    if command -v info >/dev/null 2>&1; then
        info "$*"
    else
        printf '\033[1;92m[INFO]\033[0m %s\n' "$*"
    fi
}


_oc_ok()
{
    [ "$OC_PROGRESS_ACTIVE" = "1" ] &&
        return 0

    printf '\033[1;92m[OK]\033[0m %s\n' "$*"
}


_oc_warn()
{
    [ "$OC_PROGRESS_ACTIVE" = "1" ] &&
        return 0

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
    if [ "$OC_PROGRESS_ACTIVE" = "1" ]; then
        openclash_progress_stop
    fi

    if command -v error >/dev/null 2>&1; then
        error "$*"
    else
        printf '\033[1;91m[ERROR]\033[0m %s\n' "$*"
    fi
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
    rm -f \
        "$INSTALL_LOG" \
        "$OC_DOWNLOAD_LOG" \
        2>/dev/null

    return 0
}


cleanup_openclash_temp()
{
    rm -f \
        "$OC_ROUTE_FILE" \
        "$OC_SORTED_FILE" \
        "$OC_TEST_FILE" \
        "$OC_DOWNLOAD_LOG" \
        2>/dev/null

    rm -rf \
        "$OC_TEST_DIR" \
        2>/dev/null

    return 0
}


cleanup_core_update()
{
    rm -f \
        "$OC_CORE_UPDATE_LOG" \
        2>/dev/null

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
# 环境检查
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

        command -v "$CMD" >/dev/null 2>&1 ||
            MISSING="$MISSING $CMD"

    done

    if [ -n "$MISSING" ]; then

        _oc_error "系统缺少基础命令:$MISSING"

        return 1

    fi

    return 0
}


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

        command -v "$CMD" >/dev/null 2>&1 ||
            MISSING="$MISSING $CMD"

    done

    if [ -n "$MISSING" ]; then

        _oc_warn "Meta Core 更新缺少依赖:$MISSING"

        return 1

    fi

    return 0
}


# ============================================================
# OpenClash 已安装检测
# ============================================================

check_openclash()
{
    if command -v opkg >/dev/null 2>&1; then

        opkg status \
            luci-app-openclash \
            2>/dev/null |
            grep -q 'Status:.*installed'

        return $?

    fi

    if command -v apk >/dev/null 2>&1; then

        apk info -e \
            luci-app-openclash \
            >/dev/null 2>&1

        return $?

    fi

    return 1
}


# ============================================================
# 已安装 OpenClash 版本
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
# 构造 GitHub 代理 URL
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
# Release 是否已存在
# ============================================================

openclash_release_ready()
{
    [ -n "$DOWNLOAD_URL" ] &&
    [ -n "$PACKAGE_EXT" ]
}


# ============================================================
# Worker JSON
# ============================================================

parse_openclash_worker_release()
{
    FILE="$1"

    [ -s "$FILE" ] ||
        return 1

    RELEASE_TAG="$(
        sed -n \
            's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            "$FILE" |
        head -n 1
    )"

    RELEASE_IPK="$(
        sed -n \
            's/.*"ipk"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            "$FILE" |
        head -n 1
    )"

    RELEASE_APK="$(
        sed -n \
            's/.*"apk"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            "$FILE" |
        head -n 1
    )"

    if command -v apk >/dev/null 2>&1 &&
       [ -n "$RELEASE_APK" ]
    then

        DOWNLOAD_URL="$RELEASE_APK"
        PACKAGE_EXT="apk"

    elif command -v opkg >/dev/null 2>&1 &&
         [ -n "$RELEASE_IPK" ]
    then

        DOWNLOAD_URL="$RELEASE_IPK"
        PACKAGE_EXT="ipk"

    elif [ -n "$RELEASE_IPK" ]; then

        DOWNLOAD_URL="$RELEASE_IPK"
        PACKAGE_EXT="ipk"

    elif [ -n "$RELEASE_APK" ]; then

        DOWNLOAD_URL="$RELEASE_APK"
        PACKAGE_EXT="apk"

    else

        return 1

    fi

    [ -n "$RELEASE_TAG" ] &&
    [ -n "$DOWNLOAD_URL" ] &&
    [ -n "$PACKAGE_EXT" ]
}


# ============================================================
# GitHub API JSON
# ============================================================

parse_openclash_github_release()
{
    FILE="$1"

    [ -s "$FILE" ] ||
        return 1

    RELEASE_TAG="$(
        sed -n \
            's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            "$FILE" |
        head -n 1
    )"

    RELEASE_APK="$(
        grep -o \
            'https://[^"]*luci-app-openclash[^"]*\.apk' \
            "$FILE" \
            2>/dev/null |
        head -n 1
    )"

    RELEASE_IPK="$(
        grep -o \
            'https://[^"]*luci-app-openclash[^"]*_all\.ipk' \
            "$FILE" \
            2>/dev/null |
        head -n 1
    )"

    if [ -z "$RELEASE_IPK" ]; then

        RELEASE_IPK="$(
            grep -o \
                'https://[^"]*luci-app-openclash[^"]*\.ipk' \
                "$FILE" \
                2>/dev/null |
            head -n 1
        )"

    fi

    if command -v apk >/dev/null 2>&1 &&
       [ -n "$RELEASE_APK" ]
    then

        DOWNLOAD_URL="$RELEASE_APK"
        PACKAGE_EXT="apk"

    elif command -v opkg >/dev/null 2>&1 &&
         [ -n "$RELEASE_IPK" ]
    then

        DOWNLOAD_URL="$RELEASE_IPK"
        PACKAGE_EXT="ipk"

    elif [ -n "$RELEASE_IPK" ]; then

        DOWNLOAD_URL="$RELEASE_IPK"
        PACKAGE_EXT="ipk"

    elif [ -n "$RELEASE_APK" ]; then

        DOWNLOAD_URL="$RELEASE_APK"
        PACKAGE_EXT="apk"

    else

        return 1

    fi

    [ -n "$RELEASE_TAG" ] &&
    [ -n "$DOWNLOAD_URL" ] &&
    [ -n "$PACKAGE_EXT" ]
}


# ============================================================
# 下载 Release JSON
# ============================================================

download_openclash_release_json()
{
    URL="$1"
    OUTPUT="$2"

    rm -f "$OUTPUT"

    curl \
        -4 \
        -L \
        -f \
        -sS \
        --connect-timeout 4 \
        --max-time "$OPENCLASH_RELEASE_TIMEOUT" \
        -A "Open-Pro-Installer" \
        -H "Accept: application/json" \
        -o "$OUTPUT" \
        "$URL" \
        >/dev/null 2>&1

    [ $? -eq 0 ] &&
    [ -s "$OUTPUT" ]
}


# ============================================================
# Worker 获取 Release
# ============================================================

get_openclash_release_from_worker()
{
    TRY=1

    while [ "$TRY" -le "$OPENCLASH_RELEASE_RETRY" ]
    do

        if download_openclash_release_json \
            "$OPENCLASH_RELEASE_WORKER" \
            "$OPENCLASH_RELEASE_TMP"
        then

            if parse_openclash_worker_release \
                "$OPENCLASH_RELEASE_TMP"
            then

                rm -f "$OPENCLASH_RELEASE_TMP"

                return 0

            fi

        fi

        rm -f "$OPENCLASH_RELEASE_TMP"

        TRY=$((TRY + 1))

    done

    return 1
}


# ============================================================
# DIRECT + GH01-GH06 并行获取 Release
# ============================================================

get_openclash_release_parallel()
{
    RELEASE_DIR="/tmp/openpro_openclash_release.d"

    rm -rf "$RELEASE_DIR"

    mkdir -p "$RELEASE_DIR" ||
        return 1

    for NODE_NAME in \
        DIRECT \
        GH01 \
        GH02 \
        GH03 \
        GH04 \
        GH05 \
        GH06
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

        if [ "$NODE_NAME" = "DIRECT" ]; then

            API_URL="$OPENCLASH_RELEASE_API"

        else

            [ -n "$NODE_PREFIX" ] ||
                continue

            API_URL="$(
                build_openclash_url \
                    "$NODE_PREFIX" \
                    "$OPENCLASH_RELEASE_API"
            )"

        fi

        (
            JSON_FILE="$RELEASE_DIR/${NODE_NAME}.json"
            OK_FILE="$RELEASE_DIR/${NODE_NAME}.ok"

            rm -f "$JSON_FILE" "$OK_FILE"

            if download_openclash_release_json \
                "$API_URL" \
                "$JSON_FILE"
            then

                TEST_TAG="$(
                    sed -n \
                        's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
                        "$JSON_FILE" |
                    head -n 1
                )"

                if [ -n "$TEST_TAG" ] &&
                   grep -q \
                       'luci-app-openclash' \
                       "$JSON_FILE" \
                       2>/dev/null
                then

                    printf '%s\n' \
                        "$NODE_NAME" \
                        > "$OK_FILE"

                fi

            fi

        ) &

    done

    WAIT_COUNT=0
    MAX_WAIT=$((OPENCLASH_RELEASE_TIMEOUT * 10))

    WINNER=""

    while [ "$WAIT_COUNT" -lt "$MAX_WAIT" ]
    do

        for NODE_NAME in \
            DIRECT \
            GH01 \
            GH02 \
            GH03 \
            GH04 \
            GH05 \
            GH06
        do

            if [ -s "$RELEASE_DIR/${NODE_NAME}.ok" ]; then

                WINNER="$NODE_NAME"

                break 2

            fi

        done

        sleep 0.1

        WAIT_COUNT=$((WAIT_COUNT + 1))

    done

    if [ -z "$WINNER" ]; then

        wait 2>/dev/null

        rm -rf "$RELEASE_DIR"

        return 1

    fi

    WINNER_JSON="$RELEASE_DIR/${WINNER}.json"

    if ! parse_openclash_github_release \
        "$WINNER_JSON"
    then

        wait 2>/dev/null

        rm -rf "$RELEASE_DIR"

        return 1

    fi

    wait 2>/dev/null

    rm -rf "$RELEASE_DIR"

    return 0
}


# ============================================================
# Release 智能获取
# ============================================================

get_openclash_release()
{
    if openclash_release_ready; then
        return 0
    fi

    DOWNLOAD_URL=""
    PACKAGE_EXT=""
    RELEASE_TAG=""

    if get_openclash_release_from_worker; then
        return 0
    fi

    if get_openclash_release_parallel; then
        return 0
    fi

    return 1
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
# 综合评分
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
# HTML 错误页
# ============================================================

oc_test_is_error_page()
{
    FILE="$1"

    [ -s "$FILE" ] ||
        return 1

    head -c 1024 \
        "$FILE" \
        2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
}


# ============================================================
# 单线路测速
# ============================================================

test_openclash_route()
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

    RECEIVED_BYTES="$(
        awk -v n="$SIZE_DOWN" '
            BEGIN {
                if (n ~ /^[0-9.]+$/)
                    printf "%d", n
                else
                    printf "0"
            }
        '
    )"

    [ "$RECEIVED_BYTES" -ge 4096 ] || {

        rm -f "$TEST_FILE"

        return 1

    }

    if oc_test_is_error_page "$TEST_FILE"; then

        rm -f "$TEST_FILE"

        return 1

    fi

    TTFB_MS="$(
        oc_seconds_to_ms "$TTFB"
    )"

    SPEED_INT="$(
        awk -v s="$SPEED_BPS" '
            BEGIN {
                if (s > 0)
                    printf "%d", s
                else
                    printf "0"
            }
        '
    )"

    [ "$SPEED_INT" -gt 0 ] || {

        rm -f "$TEST_FILE"

        return 1

    }

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
}


# ============================================================
# 后台测速
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

    if [ $? -ne 0 ] ||
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
#
# 注意：
# 进度模式下不再显示测速详情
# ============================================================

prepare_openclash_routes()
{
    ORIGINAL_URL="$1"

    rm -f \
        "$OC_ROUTE_FILE" \
        "$OC_SORTED_FILE" \
        "$OC_TEST_FILE"

    rm -rf "$OC_TEST_DIR"

    mkdir -p "$OC_TEST_DIR" ||
        return 1

    command -v curl >/dev/null 2>&1 || {

        rm -rf "$OC_TEST_DIR"

        return 1

    }

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

        [ -s "$RESULT_FILE" ] ||
            continue

        RESULT_STATUS="$(
            cut -d '|' -f 2 \
                "$RESULT_FILE"
        )"

        [ "$RESULT_STATUS" = "OK" ] ||
            continue

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

        printf '%s|%s|%s|%s|%s|%s\n' \
            "$SCORE" \
            "$NODE_NAME" \
            "$NODE_PREFIX" \
            "$TEST_URL" \
            "$TTFB_MS" \
            "$SPEED_BPS" \
            >> "$OC_ROUTE_FILE"

    done

    rm -rf "$OC_TEST_DIR"

    [ -s "$OC_ROUTE_FILE" ] ||
        return 1

    sort \
        -n \
        -t '|' \
        -k 1,1 \
        "$OC_ROUTE_FILE" \
        > "$OC_SORTED_FILE" \
        2>/dev/null

    if [ -s "$OC_SORTED_FILE" ]; then

        mv \
            "$OC_SORTED_FILE" \
            "$OC_ROUTE_FILE"

    else

        rm -f "$OC_SORTED_FILE"

    fi

    return 0
}


# ============================================================
# 保存测速排名
# ============================================================

cache_openclash_routes_for_reuse()
{
    cleanup_openclash_script_routes

    [ -s "$OC_ROUTE_FILE" ] ||
        return 1

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

    [ -s "$OC_SCRIPT_ROUTE_FILE" ]
}


# ============================================================
# 验证 OpenClash 软件包
# ============================================================

verify_openclash_package()
{
    FILE="$1"

    [ -s "$FILE" ] ||
        return 1

    FILE_SIZE="$(
        wc -c < "$FILE" \
        2>/dev/null
    )"

    case "$FILE_SIZE" in

        ''|*[!0-9]*)
            FILE_SIZE=0
            ;;

    esac

    [ "$FILE_SIZE" -ge 102400 ] ||
        return 1

    if head -c 1024 \
        "$FILE" \
        2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
    then

        return 1

    fi

    return 0
}


# ============================================================
# OpenClash 下载
# ============================================================

download_openclash_from_url()
{
    URL="$1"
    OUTPUT="$2"

    rm -f \
        "$OUTPUT" \
        "$OC_DOWNLOAD_LOG"

    if command -v curl >/dev/null 2>&1; then

        curl \
            -4 \
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

        RESULT=$?

    elif command -v wget >/dev/null 2>&1; then

        wget \
            -T 20 \
            -O "$OUTPUT" \
            "$URL" \
            > "$OC_DOWNLOAD_LOG" 2>&1

        RESULT=$?

    else

        return 1

    fi

    [ "$RESULT" -eq 0 ] || {

        rm -f "$OUTPUT"

        return 1

    }

    verify_openclash_package \
        "$OUTPUT" || {

            rm -f "$OUTPUT"

            return 1

        }

    return 0
}


# ============================================================
# 智能下载 OpenClash
# ============================================================

smart_download_openclash()
{
    ORIGINAL_URL="$1"
    OUTPUT="$2"

    openclash_set_stage 1 10

    prepare_openclash_routes \
        "$ORIGINAL_URL" ||
        return 1

    openclash_set_stage 1 20

    cache_openclash_routes_for_reuse ||
        true

    DOWNLOAD_SUCCESS=0
    DIRECT_TRIED=0

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

        if download_openclash_from_url \
            "$ROUTE_URL" \
            "$OUTPUT"
        then

            DOWNLOAD_SUCCESS=1

            break

        fi

    done < "$OC_ROUTE_FILE"

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] &&
       [ "$DIRECT_TRIED" -ne 1 ]
    then

        if download_openclash_from_url \
            "$ORIGINAL_URL" \
            "$OUTPUT"
        then

            DOWNLOAD_SUCCESS=1

        fi

    fi

    [ "$DOWNLOAD_SUCCESS" -eq 1 ] ||
        return 1

    openclash_set_stage 1 45

    return 0
}


# ============================================================
# 安装 OpenClash 软件包
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

    STAGE_PERCENT=50

    openclash_set_stage \
        1 \
        "$STAGE_PERCENT"

    while kill -0 \
        "$PROGRESS_PID" \
        2>/dev/null
    do

        if grep -q \
            '^Configuring ' \
            "$INSTALL_LOG" \
            2>/dev/null
        then

            [ "$STAGE_PERCENT" -lt 90 ] &&
                STAGE_PERCENT=$((STAGE_PERCENT + 4))

        elif grep -q \
            '^Installing ' \
            "$INSTALL_LOG" \
            2>/dev/null
        then

            [ "$STAGE_PERCENT" -lt 80 ] &&
                STAGE_PERCENT=$((STAGE_PERCENT + 3))

        elif grep -q \
            '^Downloading ' \
            "$INSTALL_LOG" \
            2>/dev/null
        then

            [ "$STAGE_PERCENT" -lt 68 ] &&
                STAGE_PERCENT=$((STAGE_PERCENT + 2))

        else

            [ "$STAGE_PERCENT" -lt 60 ] &&
                STAGE_PERCENT=$((STAGE_PERCENT + 1))

        fi

        [ "$STAGE_PERCENT" -gt 92 ] &&
            STAGE_PERCENT=92

        openclash_set_stage \
            1 \
            "$STAGE_PERCENT"

        sleep 1

    done

    wait "$PROGRESS_PID"

    RESULT=$?

    PROGRESS_PID=""

    [ "$RESULT" -eq 0 ] ||
        return "$RESULT"

    openclash_set_stage 1 95

    return 0
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
}


# ============================================================
# Core CPU Model
# ============================================================

detect_openclash_core_cpu_model()
{
    CURRENT_CORE_MODEL="$(
        uci -q get \
            openclash.config.core_version \
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

            ;;

    esac

    [ -n "$OPENCLASH_CORE_CPU_MODEL" ] &&
    [ "$OPENCLASH_CORE_CPU_MODEL" != "unknown" ] ||
        return 1

    if [ "$NEED_SAVE_CORE_MODEL" -eq 1 ]; then

        uci -q set \
            "openclash.config.core_version=$OPENCLASH_CORE_CPU_MODEL" \
            >/dev/null 2>&1

        uci commit openclash \
            >/dev/null 2>&1

    fi

    OPENCLASH_RELEASE_BRANCH="$(
        uci -q get \
            openclash.config.release_branch \
            2>/dev/null
    )"

    [ -n "$OPENCLASH_RELEASE_BRANCH" ] ||
        OPENCLASH_RELEASE_BRANCH="master"

    return 0
}


# ============================================================
# Meta Core 路径
# ============================================================

detect_meta_core_path()
{
    SMALL_FLASH="$(
        uci -q get \
            openclash.config.small_flash_memory \
            2>/dev/null
    )"

    if [ "$SMALL_FLASH" = "1" ]; then

        META_CORE_PATH="/tmp/etc/openclash/core/clash_meta"

        mkdir -p \
            /tmp/etc/openclash/core \
            >/dev/null 2>&1

    else

        META_CORE_PATH="/etc/openclash/core/clash_meta"

        mkdir -p \
            /etc/openclash/core \
            >/dev/null 2>&1

    fi
}


# ============================================================
# 当前 Meta Core 版本
# ============================================================

get_meta_core_version()
{
    detect_meta_core_path

    META_CORE_VERSION=""
    META_CORE_FULL_VERSION=""

    [ -x "$META_CORE_PATH" ] ||
        return 1

    META_CORE_FULL_VERSION="$(
        "$META_CORE_PATH" -v \
            2>/dev/null |
        head -n 1
    )"

    [ -n "$META_CORE_FULL_VERSION" ] ||
        return 1

    META_CORE_VERSION="$(
        printf '%s\n' \
            "$META_CORE_FULL_VERSION" |
        awk '{print $3}'
    )"

    [ -n "$META_CORE_VERSION" ]
}


# ============================================================
# Core 检测
# ============================================================

check_openclash_core()
{
    CORE_FOUND=0

    if get_meta_core_version; then
        CORE_FOUND=1
    fi

    [ -x "$OPENCLASH_CORE_DIR/clash" ] &&
        CORE_FOUND=1

    [ -x "$OPENCLASH_CORE_DIR/clash_tun" ] &&
        CORE_FOUND=1

    [ "$CORE_FOUND" -eq 1 ]
}

# ============================================================
# 最新 Meta Core 版本
# ============================================================

get_latest_meta_core_version()
{
    CORE_PROXY="$1"

    VERSION_SCRIPT="/usr/share/openclash/openclash_version.lua"

    [ -f "$VERSION_SCRIPT" ] ||
        return 1

    command -v lua >/dev/null 2>&1 ||
        return 1

    command -v jsonfilter >/dev/null 2>&1 ||
        return 1

    rm -f \
        /tmp/openclash_version_history.json \
        2>/dev/null

    [ -n "$CORE_PROXY" ] ||
        CORE_PROXY="0"

    lua \
        "$VERSION_SCRIPT" \
        "$CORE_PROXY" \
        >/dev/null 2>&1

    [ -s /tmp/openclash_version_history.json ] ||
        return 1

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
#
# 不再单独输出 Core 进度条
# 直接写入 [2/4]
# ============================================================

core_update_progress()
{
    PERCENT="$1"
    ROUTE_NAME="$2"

    case "$PERCENT" in

        ''|*[!0-9]*)
            PERCENT=5
            ;;

    esac

    # 官方 Core 内部 0~100
    # 映射到阶段 20~90

    MAPPED=$((20 + PERCENT * 70 / 100))

    [ "$MAPPED" -gt 90 ] &&
        MAPPED=90

    openclash_set_stage \
        2 \
        "$MAPPED"
}


core_update_progress_success()
{
    ROUTE_NAME="$1"

    openclash_set_stage 2 100
}


# ============================================================
# 官方 Core 更新
# ============================================================

run_official_meta_core_update()
{
    ROUTE_NAME="$1"
    ROUTE_URL="$2"

    CORE_UPDATE_SCRIPT="/usr/share/openclash/openclash_core.sh"

    [ -f "$CORE_UPDATE_SCRIPT" ] ||
        return 1

    [ -x "$CORE_UPDATE_SCRIPT" ] ||
        chmod +x \
            "$CORE_UPDATE_SCRIPT" \
            >/dev/null 2>&1

    rm -f "$OC_CORE_UPDATE_LOG"

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

    while kill -0 \
        "$CORE_UPDATE_PID" \
        2>/dev/null
    do

        if grep -qi \
            'Update Successful' \
            "$OC_CORE_UPDATE_LOG" \
            2>/dev/null
        then

            [ "$CORE_PERCENT" -lt 94 ] &&
                CORE_PERCENT=$((CORE_PERCENT + 5))

        elif grep -qi \
            'Download Successful' \
            "$OC_CORE_UPDATE_LOG" \
            2>/dev/null
        then

            [ "$CORE_PERCENT" -lt 88 ] &&
                CORE_PERCENT=$((CORE_PERCENT + 4))

        elif grep -qi \
            'Downloading\|Download' \
            "$OC_CORE_UPDATE_LOG" \
            2>/dev/null
        then

            [ "$CORE_PERCENT" -lt 80 ] &&
                CORE_PERCENT=$((CORE_PERCENT + 3))

        else

            [ "$CORE_PERCENT" -lt 50 ] &&
                CORE_PERCENT=$((CORE_PERCENT + 1))

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

    return "$CORE_SCRIPT_RESULT"
}


# ============================================================
# Meta Core 自动检查 / 安装 / 更新
# ============================================================

auto_update_openclash_core()
{
    openclash_set_stage 2 5

    CORE_UPDATE_SCRIPT="/usr/share/openclash/openclash_core.sh"

    # 没有官方脚本时，不阻止 OpenClash 本体
    if [ ! -f "$CORE_UPDATE_SCRIPT" ]; then

        openclash_set_stage 2 100

        return 0

    fi

    openclash_set_stage 2 10

    check_openclash_core_runtime ||
        return 1

    detect_openclash_core_cpu_model ||
        return 1

    openclash_set_stage 2 15

    OLD_META_VERSION=""

    if get_meta_core_version; then
        OLD_META_VERSION="$META_CORE_VERSION"
    fi

    CORE_TEST_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/${OPENCLASH_RELEASE_BRANCH}/meta/clash-${OPENCLASH_CORE_CPU_MODEL}.tar.gz"

    CORE_ROUTE_AVAILABLE=0

    if [ -s "$OC_SCRIPT_ROUTE_FILE" ]; then
        CORE_ROUTE_AVAILABLE=1
    fi

    LATEST_META_VERSION=""

    # ========================================================
    # 获取最新版本
    # ========================================================

    if [ "$CORE_ROUTE_AVAILABLE" -eq 1 ]; then

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

                VERSION_PROXY="0"

            else

                VERSION_PROXY="$ROUTE_PREFIX"

            fi

            if get_latest_meta_core_version \
                "$VERSION_PROXY"
            then
                break
            fi

        done < "$OC_SCRIPT_ROUTE_FILE"

    fi

    if [ -z "$LATEST_META_VERSION" ]; then

        get_latest_meta_core_version 0 ||
            true

    fi

    openclash_set_stage 2 20

    # ========================================================
    # 已是最新版本
    # ========================================================

    if [ -n "$OLD_META_VERSION" ] &&
       [ -n "$LATEST_META_VERSION" ] &&
       [ "$OLD_META_VERSION" = "$LATEST_META_VERSION" ]
    then

        openclash_set_stage 2 100

        cleanup_core_update

        return 0

    fi

    CORE_UPDATE_SUCCESS=0
    DIRECT_CORE_TRIED=0

    # ========================================================
    # 使用共享线路更新
    # ========================================================

    if [ "$CORE_ROUTE_AVAILABLE" -eq 1 ]; then

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

                ROUTE_URL="$CORE_TEST_URL"

                DIRECT_CORE_TRIED=1

            else

                ROUTE_URL="$(
                    build_openclash_url \
                        "$ROUTE_PREFIX" \
                        "$CORE_TEST_URL"
                )"

            fi

            run_official_meta_core_update \
                "$ROUTE_NAME" \
                "$ROUTE_URL"

            sleep 1

            if get_meta_core_version; then

                NEW_META_VERSION="$META_CORE_VERSION"

                if [ -n "$LATEST_META_VERSION" ]; then

                    if [ "$NEW_META_VERSION" = "$LATEST_META_VERSION" ]; then

                        CORE_UPDATE_SUCCESS=1

                        break

                    fi

                else

                    if [ -z "$OLD_META_VERSION" ] ||
                       [ "$NEW_META_VERSION" != "$OLD_META_VERSION" ]
                    then

                        CORE_UPDATE_SUCCESS=1

                        break

                    fi

                fi

            fi

        done < "$OC_SCRIPT_ROUTE_FILE"

    fi

    # ========================================================
    # DIRECT 兜底
    # ========================================================

    if [ "$CORE_UPDATE_SUCCESS" -ne 1 ] &&
       [ "$DIRECT_CORE_TRIED" -ne 1 ]
    then

        run_official_meta_core_update \
            "DIRECT" \
            "$CORE_TEST_URL"

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

    if get_meta_core_version; then

        if [ -n "$LATEST_META_VERSION" ]; then

            if [ "$META_CORE_VERSION" = "$LATEST_META_VERSION" ]; then
                CORE_UPDATE_SUCCESS=1
            fi

        elif [ -n "$META_CORE_VERSION" ]; then

            CORE_UPDATE_SUCCESS=1

        fi

    fi

    cleanup_core_update

    if [ "$CORE_UPDATE_SUCCESS" -eq 1 ]; then

        openclash_set_stage 2 100

        return 0

    fi

    return 1
}


# ============================================================
# 共享线路检查
# ============================================================

prepare_openclash_script_routes()
{
    [ -s "$OC_SCRIPT_ROUTE_FILE" ]
}


# ============================================================
# 下载普通 Shell
# ============================================================

smart_download_openclash_script_cached()
{
    ORIGINAL_URL="$1"
    OUTPUT="$2"

    DOWNLOAD_SUCCESS=0
    DIRECT_TRIED=0

    rm -f "$OUTPUT" 2>/dev/null

    [ -s "$OC_SCRIPT_ROUTE_FILE" ] ||
        return 1

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

        rm -f "$OUTPUT" 2>/dev/null

        curl \
            -4 \
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

            if ! head -c 1024 \
                "$OUTPUT" \
                2>/dev/null |
                grep -Eqi \
                '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
            then

                DOWNLOAD_SUCCESS=1

                break

            fi

        fi

        rm -f "$OUTPUT" 2>/dev/null

    done < "$OC_SCRIPT_ROUTE_FILE"

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] &&
       [ "$DIRECT_TRIED" -ne 1 ]
    then

        rm -f "$OUTPUT" 2>/dev/null

        curl \
            -4 \
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

            if ! head -c 1024 \
                "$OUTPUT" \
                2>/dev/null |
                grep -Eqi \
                '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
            then

                DOWNLOAD_SUCCESS=1

            fi

        fi

    fi

    [ "$DOWNLOAD_SUCCESS" -eq 1 ]
}


# ============================================================
# [3/4] OpenClash Swap
# ============================================================

run_openclash_swap()
{
    SWAP_TMP="/tmp/openclash-swap.$$"

    openclash_set_stage 3 10

    if ! smart_download_openclash_script_cached \
        "$OPENCLASH_SWAP_URL" \
        "$SWAP_TMP"
    then

        rm -f "$SWAP_TMP" 2>/dev/null

        return 1

    fi

    openclash_set_stage 3 40

    [ -s "$SWAP_TMP" ] || {

        rm -f "$SWAP_TMP"

        return 1

    }

    chmod 755 \
        "$SWAP_TMP" \
        >/dev/null 2>&1 ||
        return 1

    openclash_set_stage 3 60

    OPENPRO_SCRIPT_ROUTE_FILE="$OC_SCRIPT_ROUTE_FILE" \
        sh "$SWAP_TMP" \
        >/tmp/openpro_openclash_swap.log 2>&1

    SWAP_RESULT=$?

    rm -f \
        "$SWAP_TMP" \
        >/dev/null 2>&1

    if [ "$SWAP_RESULT" -eq 0 ]; then

        openclash_set_stage 3 100

        return 0

    fi

    return 1
}


# ============================================================
# [4/4] Smart Select
# ============================================================

install_openclash_smart_select()
{
    SMART_SELECT_TMP="/tmp/openclash-smart-select.$$"

    openclash_set_stage 4 10

    if ! smart_download_openclash_script_cached \
        "$OPENCLASH_SMART_SELECT_URL" \
        "$SMART_SELECT_TMP"
    then

        rm -f "$SMART_SELECT_TMP" \
            2>/dev/null

        return 1

    fi

    openclash_set_stage 4 30

    [ -s "$SMART_SELECT_TMP" ] || {

        rm -f "$SMART_SELECT_TMP"

        return 1

    }

    if head -c 1024 \
        "$SMART_SELECT_TMP" \
        2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
    then

        rm -f "$SMART_SELECT_TMP"

        return 1

    fi

    rm -f \
        "$OPENCLASH_SMART_SELECT_PATH" \
        >/dev/null 2>&1

    mv \
        "$SMART_SELECT_TMP" \
        "$OPENCLASH_SMART_SELECT_PATH" ||
        return 1

    chmod +x \
        "$OPENCLASH_SMART_SELECT_PATH" ||
        return 1

    [ -x "$OPENCLASH_SMART_SELECT_PATH" ] ||
        return 1

    openclash_set_stage 4 55

    return 0
}

# ============================================================
# Smart Select Cron
# ============================================================

setup_openclash_smart_select_cron()
{
    CRON_FILE="/etc/crontabs/root"
    CRON_TMP="/tmp/openclash-smart-select-cron.tmp"

    [ -x "$OPENCLASH_SMART_SELECT_PATH" ] ||
        return 1

    openclash_set_stage 4 65

    mkdir -p \
        /etc/crontabs \
        >/dev/null 2>&1

    touch \
        "$CRON_FILE" \
        >/dev/null 2>&1

    rm -f \
        "$CRON_TMP" \
        2>/dev/null

    grep -v \
        '/usr/bin/openclash-smart-select' \
        "$CRON_FILE" \
        2>/dev/null \
        > "$CRON_TMP"

    printf '%s\n' \
        '*/30 * * * * /usr/bin/openclash-smart-select >/tmp/openclash-smart-select.log 2>&1' \
        >> "$CRON_TMP"

    mv \
        "$CRON_TMP" \
        "$CRON_FILE" ||
        return 1

    openclash_set_stage 4 80

    if [ -x /etc/init.d/cron ]; then

        /etc/init.d/cron restart \
            >/dev/null 2>&1

    fi

    grep -q \
        '^\*/30 \* \* \* \* /usr/bin/openclash-smart-select ' \
        "$CRON_FILE" \
        2>/dev/null ||
        return 1

    openclash_set_stage 4 90

    return 0
}


# ============================================================
# 刷新 LuCI
# ============================================================

reload_luci()
{
    rm -rf \
        /tmp/luci-indexcache \
        /tmp/luci-modulecache \
        /tmp/luci-templatecache \
        /tmp/luci-*cache* \
        >/dev/null 2>&1

    if [ -x /etc/init.d/rpcd ]; then

        /etc/init.d/rpcd restart \
            >/dev/null 2>&1

    fi

    if [ -x /etc/init.d/uhttpd ]; then

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
    if [ -n "$PROGRESS_PID" ]; then

        kill \
            "$PROGRESS_PID" \
            >/dev/null 2>&1

        wait \
            "$PROGRESS_PID" \
            >/dev/null 2>&1

    fi

    if [ -n "$CORE_UPDATE_PID" ]; then

        kill \
            "$CORE_UPDATE_PID" \
            >/dev/null 2>&1

        wait \
            "$CORE_UPDATE_PID" \
            >/dev/null 2>&1

    fi

    openclash_progress_stop

    printf '\033[1;93m[WARN]\033[0m OpenClash 安装已中断\n'

    cleanup_openclash_package
    cleanup_openclash_temp
    cleanup_core_update
    cleanup_openclash_script_routes

    trap - INT TERM

    return 130
}


# ============================================================
# 主安装
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
    # Runtime
    # ========================================================

    check_openclash_runtime ||
        return 1

    if ! command -v curl >/dev/null 2>&1 &&
       ! command -v wget >/dev/null 2>&1
    then

        _oc_error "系统缺少 curl / wget"

        return 1

    fi

    # ========================================================
    # CPU
    # ========================================================

    detect_openclash_arch

    # ========================================================
    # Release
    #
    # 此时还没有启动进度表，所以失败信息仍正常显示
    # ========================================================

    if ! get_openclash_release; then

        _oc_error \
            "OpenClash版本获取失败"

        return 1

    fi

    if [ -z "$DOWNLOAD_URL" ]; then

        _oc_error \
            "OpenClash 下载地址为空"

        return 1

    fi

    if [ -z "$PACKAGE_EXT" ]; then

        _oc_error \
            "OpenClash 软件包格式为空"

        return 1

    fi

    # ========================================================
    # 初始化
    # ========================================================

    OPENCLASH_PKG="/tmp/openclash.${PACKAGE_EXT}"

    rm -f \
        "$OPENCLASH_PKG" \
        "$INSTALL_LOG"

    cleanup_openclash_temp
    cleanup_core_update
    cleanup_openclash_script_routes

    trap \
        'interrupt_openclash' \
        INT TERM

    # ========================================================
    # 启动唯一进度表
    # ========================================================

    openclash_progress_start

    # ========================================================
    # [1/4] 下载 OpenClash
    # ========================================================

    openclash_set_stage 1 5

    if ! smart_download_openclash \
        "$DOWNLOAD_URL" \
        "$OPENCLASH_PKG"
    then

        _oc_error \
            "OpenClash 下载失败，所有线路均不可用"

        cleanup_openclash_package
        cleanup_openclash_temp

        trap - INT TERM

        return 1

    fi

    # ========================================================
    # [1/4] 安装 OpenClash
    # ========================================================

    case "$PACKAGE_EXT" in

        apk)

            if ! command -v apk >/dev/null 2>&1; then

                _oc_error \
                    "当前系统没有 APK 包管理器"

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

                _oc_error \
                    "当前系统没有 OPKG 包管理器"

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

            _oc_error \
                "未知软件包格式：$PACKAGE_EXT"

            cleanup_openclash_package

            trap - INT TERM

            return 1

            ;;

    esac

    if [ "$INSTALL_RESULT" -ne 0 ]; then

        _oc_error \
            "OpenClash 安装失败"

        if [ -s "$INSTALL_LOG" ]; then

            printf "\n"
            printf "========== INSTALL ERROR ==========\n"

            tail -n 80 \
                "$INSTALL_LOG"

            printf "===================================\n"

        fi

        cleanup_openclash_package
        cleanup_openclash_temp

        trap - INT TERM

        return 1

    fi

    cleanup_openclash_package

    # ========================================================
    # 验证 OpenClash
    # ========================================================

    openclash_set_stage 1 97

    if ! check_openclash; then

        _oc_error \
            "未检测到 luci-app-openclash"

        cleanup_openclash_logs
        cleanup_openclash_temp

        trap - INT TERM

        return 1

    fi

    get_installed_openclash_version

    openclash_set_stage 1 100

    cleanup_openclash_logs

    mkdir -p \
        "$OPENCLASH_CORE_DIR" \
        >/dev/null 2>&1

    # ========================================================
    # [2/4] Meta / Mihomo Core
    # ========================================================

    openclash_set_stage 2 5

    check_openclash_core ||
        true

    if auto_update_openclash_core; then

        openclash_set_stage 2 100

    else

        # OpenClash 本体成功后，Core 更新异常不直接终止整个流程
        #
        # 如果已经存在可运行 Meta Core，
        # 仍视为第二阶段完成

        if get_meta_core_version; then

            openclash_set_stage 2 100

        else

            openclash_set_stage 2 100

        fi

    fi

    # ========================================================
    # [3/4] 文件替换
    # ========================================================

    EXT_ROUTE_READY=0

    if prepare_openclash_script_routes; then
        EXT_ROUTE_READY=1
    fi

    if [ "$EXT_ROUTE_READY" -eq 1 ]; then

        if run_openclash_swap; then

            openclash_set_stage 3 100

        else

            # Swap 属于增强功能
            # 不影响 OpenClash 本体
            openclash_set_stage 3 100

        fi

    else

        # 没有线路缓存时跳过
        openclash_set_stage 3 100

    fi

    # ========================================================
    # [4/4] Smart Select + Cron
    # ========================================================

    SMART_SELECT_INSTALLED=0

    openclash_set_stage 4 5

    if [ "$EXT_ROUTE_READY" -eq 1 ]; then

        if install_openclash_smart_select; then

            SMART_SELECT_INSTALLED=1

        fi

    fi

    if [ "$SMART_SELECT_INSTALLED" -eq 1 ]; then

        setup_openclash_smart_select_cron ||
            true

    else

        openclash_set_stage 4 80

    fi

    # ========================================================
    # LuCI
    # ========================================================

    openclash_set_stage 4 95

    reload_luci

    openclash_set_stage 4 100

    # ========================================================
    # 保证最终状态
    # ========================================================

    OC_STAGE_1=100
    OC_STAGE_2=100
    OC_STAGE_3=100
    OC_STAGE_4=100

    show_openclash_stage_progress

    # ========================================================
    # 完成
    # ========================================================

    sleep 1

    openclash_progress_stop

    trap - INT TERM

    cleanup_openclash_temp
    cleanup_core_update
    cleanup_openclash_script_routes

    printf '\033[1;92m====================================================\033[0m\n'
    printf '\033[1;92m            OpenClash 安装全部完成\033[0m\n'
    printf '\033[1;92m====================================================\033[0m\n'

    printf "\n"

    printf '\033[1;92m[OK]\033[0m OpenClash 安装完成\n'

    printf '\033[1;92m[INFO]\033[0m 版本 : %s\n' \
        "$OPENCLASH_VERSION"

    printf '\033[1;92m[INFO]\033[0m CPU  : %s\n' \
        "$OPENCLASH_ARCH"

    printf '\033[1;92m[INFO]\033[0m Core : %s\n' \
        "$OPENCLASH_CORE_ARCH"

    if get_meta_core_version; then

        printf '\033[1;92m[INFO]\033[0m Meta : %s\n' \
            "$META_CORE_VERSION"

    fi

    if [ -x "$OPENCLASH_SMART_SELECT_PATH" ]; then

        printf '\033[1;92m[INFO]\033[0m Smart Select : 已安装\n'

    fi

    if grep -q \
        '/usr/bin/openclash-smart-select' \
        /etc/crontabs/root \
        2>/dev/null
    then

        printf '\033[1;92m[INFO]\033[0m Smart Select Cron : 每 30 分钟\n'

    fi

    printf "\n"

    printf "LuCI：服务 → OpenClash\n"
    printf "内核：OpenClash → 版本更新\n"

    printf "\n"

    return 0
}

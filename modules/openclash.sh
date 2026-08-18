#!/bin/sh

# ============================================================
# Open-Pro-Installer
# OpenClash Auto Installer
#
# 功能：
# 1. 安装 OpenClash
# 2. GitHub Release 多线路自动测速
# 3. 自动选择最快下载线路
# 4. 最快线路失败后自动切换备用线路
# 5. 最后自动回退 GitHub 官方直连
# 6. 隐藏 curl/wget/opkg/apk 大量日志
# 7. OpenClash 安装动态进度条
# 8. 安装失败自动显示详细日志
# 9. 自动检测 OpenClash 是否安装成功
# 10. 自动检测 CPU / Core 架构
# 11. 自动检测 OpenClash Core
# 12. 检测 OpenClash 更新组件
# 13. 清理临时文件
#
# BusyBox / OpenWrt Compatible
# ============================================================


# ============================================================
# 基础配置
# ============================================================

OPENCLASH_PKG=""
INSTALL_LOG="/tmp/openpro_openclash_install.log"

PROGRESS_PID=""

OPENCLASH_VERSION=""
OPENCLASH_ARCH=""
OPENCLASH_CORE_ARCH=""

OPENCLASH_DIR="/etc/openclash"
OPENCLASH_CORE_DIR="/etc/openclash/core"

OC_ROUTE_FILE="/tmp/openpro_openclash_routes"
OC_TEST_FILE="/tmp/openpro_openclash_test"
OC_DOWNLOAD_LOG="/tmp/openpro_openclash_download.log"


# ============================================================
# GitHub 下载线路
#
# 格式：
# 名称|前缀
#
# DIRECT| 代表 GitHub 官方直连
#
# 如果以后代理失效，只需要修改这里。
# ============================================================

OPENCLASH_DOWNLOAD_NODES="
GH01|https://ghproxy.net/
GH02|https://gh-proxy.com/
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
    rm -f "$OC_TEST_FILE" 2>/dev/null
    rm -f "$OC_DOWNLOAD_LOG" 2>/dev/null

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

        apk info -e luci-app-openclash \
            >/dev/null 2>&1

        return $?
    fi


    return 1
}


# ============================================================
# 获取 OpenClash 已安装版本
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
# 根据节点生成下载 URL
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
# 毫秒计算
# ============================================================

oc_seconds_to_ms()
{
    VALUE="$1"


    awk -v t="$VALUE" '
        BEGIN {
            if (t == "" || t !~ /^[0-9.]+$/) {
                print 999999
            } else {
                printf "%d\n", t * 1000
            }
        }
    '
}


# ============================================================
# 测试一条 GitHub 下载线路
#
# curl 使用 Range，只获取少量数据。
# 防止测速阶段完整下载 OpenClash 安装包。
# ============================================================

test_openclash_route()
{
    TEST_URL="$1"

    rm -f "$OC_TEST_FILE"


    if command -v curl >/dev/null 2>&1; then

        TEST_TIME="$(
            curl -4 \
                -L \
                -sS \
                -f \
                --connect-timeout 4 \
                --max-time 8 \
                -r 0-1023 \
                -o "$OC_TEST_FILE" \
                -w '%{time_total}' \
                "$TEST_URL" \
                2>/dev/null
        )"

        TEST_RESULT=$?


        if [ "$TEST_RESULT" -ne 0 ]; then
            return 1
        fi


        if [ ! -s "$OC_TEST_FILE" ]; then
            return 1
        fi


        TEST_MS="$(oc_seconds_to_ms "$TEST_TIME")"


        case "$TEST_MS" in
            ''|*[!0-9]*)
                return 1
                ;;
        esac


        printf '%s' "$TEST_MS"

        return 0
    fi


    # --------------------------------------------------------
    # 没有 curl 时使用 wget 做可用性检测
    #
    # BusyBox wget 很难准确获得毫秒时间，
    # 所以只判断线路是否可用。
    # --------------------------------------------------------

    if command -v wget >/dev/null 2>&1; then

        START_TIME="$(date +%s 2>/dev/null)"


        if wget \
            -T 8 \
            -O "$OC_TEST_FILE" \
            "$TEST_URL" \
            >/dev/null 2>&1
        then

            END_TIME="$(date +%s 2>/dev/null)"


            [ -n "$START_TIME" ] || START_TIME=0
            [ -n "$END_TIME" ] || END_TIME="$START_TIME"


            TEST_MS=$(( (END_TIME - START_TIME) * 1000 ))


            if [ "$TEST_MS" -le 0 ]; then
                TEST_MS=1
            fi


            printf '%s' "$TEST_MS"

            return 0
        fi
    fi


    return 1
}


# ============================================================
# GitHub Release 线路测速
# ============================================================

prepare_openclash_routes()
{
    ORIGINAL_URL="$1"

    rm -f "$OC_ROUTE_FILE"
    rm -f "$OC_TEST_FILE"


    printf "\n"

    _oc_info "正在测试 OpenClash 下载线路..."

    printf "\n"


    printf '%s\n' "$OPENCLASH_DOWNLOAD_NODES" |
    while IFS='|' read -r NODE_NAME NODE_PREFIX
    do

        [ -n "$NODE_NAME" ] || continue


        TEST_URL="$(
            build_openclash_url \
                "$NODE_PREFIX" \
                "$ORIGINAL_URL"
        )"


        printf '  %-10s ' "$NODE_NAME"


        NODE_MS="$(
            test_openclash_route "$TEST_URL"
        )"

        TEST_RESULT=$?


        if [ "$TEST_RESULT" -eq 0 ] &&
           [ -n "$NODE_MS" ]; then

            printf '\033[32m%6s ms\033[0m\n' \
                "$NODE_MS"


            printf '%s|%s|%s|%s\n' \
                "$NODE_MS" \
                "$NODE_NAME" \
                "$NODE_PREFIX" \
                "$TEST_URL" \
                >> "$OC_ROUTE_FILE"

        else

            printf '\033[31m不可用\033[0m\n'

        fi

    done


    rm -f "$OC_TEST_FILE"


    if [ ! -s "$OC_ROUTE_FILE" ]; then

        printf "\n"

        _oc_warn "测速没有发现可用代理线路"
        _oc_info "稍后将尝试 GitHub 官方地址"

        return 1
    fi


    # --------------------------------------------------------
    # 按延迟排序
    # --------------------------------------------------------

    SORTED_FILE="${OC_ROUTE_FILE}.sorted"


    sort -n -t '|' -k 1,1 \
        "$OC_ROUTE_FILE" \
        > "$SORTED_FILE" 2>/dev/null


    if [ -s "$SORTED_FILE" ]; then

        mv "$SORTED_FILE" "$OC_ROUTE_FILE"

    else

        rm -f "$SORTED_FILE"

    fi


    BEST_LINE="$(
        sed -n '1p' "$OC_ROUTE_FILE"
    )"


    BEST_MS="$(
        printf '%s\n' "$BEST_LINE" |
        cut -d '|' -f 1
    )"


    BEST_NAME="$(
        printf '%s\n' "$BEST_LINE" |
        cut -d '|' -f 2
    )"


    printf "\n"

    _oc_ok "最快线路：$BEST_NAME"

    _oc_info "线路延迟：${BEST_MS} ms"

    printf "\n"


    return 0
}


# ============================================================
# 验证下载文件
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


    # OpenClash 软件包正常远大于 100KB。
    # 主要防止代理返回 HTML 错误页。
    if [ "$FILE_SIZE" -lt 102400 ]; then
        return 1
    fi


    # --------------------------------------------------------
    # HTML 错误页检测
    # --------------------------------------------------------

    if head -c 512 "$FILE" 2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|bad gateway|cloudflare|error 404'
    then
        return 1
    fi


    return 0
}


# ============================================================
# 使用 curl 下载
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
        >"$OC_DOWNLOAD_LOG" 2>&1
}


# ============================================================
# 使用 wget 下载
# ============================================================

download_openclash_wget()
{
    URL="$1"
    OUTPUT="$2"


    wget \
        -T 20 \
        -O "$OUTPUT" \
        "$URL" \
        >"$OC_DOWNLOAD_LOG" 2>&1
}


# ============================================================
# 下载单条线路
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
# OpenClash 多线路智能下载
#
# 1. 测速
# 2. 延迟排序
# 3. 最快线路优先
# 4. 失败自动切换下一条
# 5. 确保最后尝试 GitHub 官方直连
# ============================================================

smart_download_openclash()
{
    ORIGINAL_URL="$1"
    OUTPUT="$2"


    prepare_openclash_routes "$ORIGINAL_URL"


    DOWNLOAD_SUCCESS=0
    DIRECT_TRIED=0


    # ========================================================
    # 按测速结果依次下载
    # ========================================================

    if [ -s "$OC_ROUTE_FILE" ]; then

        while IFS='|' read -r \
            ROUTE_MS \
            ROUTE_NAME \
            ROUTE_PREFIX \
            ROUTE_URL
        do

            [ -n "$ROUTE_NAME" ] || continue
            [ -n "$ROUTE_URL" ] || continue


            if [ "$ROUTE_NAME" = "DIRECT" ]; then
                DIRECT_TRIED=1
            fi


            _oc_info "正在使用线路：$ROUTE_NAME"


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
    # 如果测速列表全部失败，确保再尝试官方直连
    # ========================================================

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] &&
       [ "$DIRECT_TRIED" -ne 1 ]; then

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

    while [ "$I" -lt "$FILLED" ]; do

        BAR="${BAR}#"

        I=$((I + 1))

    done


    I=0

    while [ "$I" -lt "$EMPTY" ]; do

        BAR="${BAR}-"

        I=$((I + 1))

    done


    printf '\r\033[2K[INFO] 正在安装 OpenClash... [\033[32m%s\033[0m] %3d%%' \
        "$BAR" \
        "$PERCENT"
}


# ============================================================
# 带进度条安装
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
                >"$INSTALL_LOG" 2>&1 &

            ;;


        ipk)

            opkg install \
                "$PKG_FILE" \
                >"$INSTALL_LOG" 2>&1 &

            ;;


        *)

            return 1

            ;;

    esac


    PROGRESS_PID=$!

    PERCENT=1


    openclash_progress_bar "$PERCENT"


    while kill -0 "$PROGRESS_PID" 2>/dev/null; do


        if grep -q '^Configuring ' \
            "$INSTALL_LOG" 2>/dev/null
        then

            if [ "$PERCENT" -lt 94 ]; then
                PERCENT=$((PERCENT + 3))
            fi


        elif grep -q '^Installing ' \
            "$INSTALL_LOG" 2>/dev/null
        then

            if [ "$PERCENT" -lt 78 ]; then
                PERCENT=$((PERCENT + 3))
            fi


        elif grep -q '^Downloading ' \
            "$INSTALL_LOG" 2>/dev/null
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
# 检测 CPU / OpenClash Core 架构
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
# 检测 OpenClash 内核
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
                -v 2>/dev/null |
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
# 检测 OpenClash 自带更新组件
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

        _oc_warn "没有找到可直接调用的 OpenClash 内核更新脚本"

        _oc_info "可进入 OpenClash → 版本更新 页面检查内核"

        return 0

    fi


    _oc_ok "检测到 OpenClash 更新组件"

    _oc_info "更新脚本 : $CORE_UPDATE_SCRIPT"


    if [ -x "$CORE_UPDATE_SCRIPT" ]; then

        _oc_ok "OpenClash 自动更新组件工作正常"

    else

        chmod +x "$CORE_UPDATE_SCRIPT" \
            >/dev/null 2>&1

    fi


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


    cleanup_openclash_package
    cleanup_openclash_temp


    trap - INT TERM


    return 130
}


# ============================================================
# 主安装函数
#
# install.sh 调用：
#
# install_openclash
#
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
       ! command -v wget >/dev/null 2>&1; then

        _oc_error "系统缺少 curl / wget"

        return 1

    fi


    # ========================================================
    # 架构
    # ========================================================

    detect_openclash_arch


    # ========================================================
    # install.sh 传入参数
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


    # ========================================================
    # 临时文件
    # ========================================================

    OPENCLASH_PKG="/tmp/openclash.${PACKAGE_EXT}"


    rm -f "$OPENCLASH_PKG"
    rm -f "$INSTALL_LOG"

    cleanup_openclash_temp


    trap 'interrupt_openclash' INT TERM


    # ========================================================
    # 智能线路下载
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

            printf "\n"

        fi


        cleanup_openclash_package
        cleanup_openclash_temp


        trap - INT TERM


        return 1

    fi


    # ========================================================
    # 删除安装包
    # ========================================================

    cleanup_openclash_package


    printf "\n"


    # ========================================================
    # 验证
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


    # ========================================================
    # 清理安装日志
    # ========================================================

    cleanup_openclash_logs
    cleanup_openclash_temp


    # ========================================================
    # 创建 Core 目录
    # ========================================================

    mkdir -p "$OPENCLASH_CORE_DIR" \
        >/dev/null 2>&1


    # ========================================================
    # Core 检测
    # ========================================================

    check_openclash_core


    # ========================================================
    # 更新组件检测
    # ========================================================

    auto_update_openclash_core


    # ========================================================
    # 刷新 LuCI
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

    printf "请进入 LuCI 后台查看：\n"
    printf "服务 → OpenClash\n"

    printf "\n"

    printf "内核更新位置：\n"
    printf "OpenClash → 版本更新\n"

    printf "\n"


    return 0
}

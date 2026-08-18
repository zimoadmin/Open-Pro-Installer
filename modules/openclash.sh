#!/bin/sh

# ============================================================
# Open-Pro-Installer
# OpenClash Auto Installer
# BusyBox / OpenWrt Compatible
# ============================================================


# ============================================================
# 基础配置
# ============================================================

OPENCLASH_PKG=""
INSTALL_LOG="/tmp/openpro_openclash_install.log"
OC_ROUTE_FILE="/tmp/openpro_openclash_routes"
OC_TEST_FILE="/tmp/openpro_openclash_test"
OC_DOWNLOAD_LOG="/tmp/openpro_openclash_download.log"

PROGRESS_PID=""

OPENCLASH_VERSION=""
OPENCLASH_ARCH=""
OPENCLASH_CORE_ARCH=""

OPENCLASH_DIR="/etc/openclash"
OPENCLASH_CORE_DIR="/etc/openclash/core"


# ============================================================
# 小文件测速地址
#
# 只用 bootstrap.sh 测试 GitHub 线路速度
# 不使用 OpenClash 10MB 安装包测速
# ============================================================

OC_SPEED_TEST_URL="https://raw.githubusercontent.com/zimoadmin/Open-Pro-Installer/main/bootstrap.sh"


# ============================================================
# GitHub 下载线路
#
# 格式：
# 名称|代理前缀
#
# DIRECT| = GitHub 官方直连
# ============================================================

OPENCLASH_DOWNLOAD_NODES="
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
DIRECT|
"


# ============================================================
# 日志函数
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
        rm -f "$OPENCLASH_PKG" 2>/dev/null
    fi

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
    rm -f "${OC_ROUTE_FILE}.sorted" 2>/dev/null
    rm -f "$OC_TEST_FILE" 2>/dev/null
    rm -f "$OC_DOWNLOAD_LOG" 2>/dev/null

    return 0
}


# ============================================================
# 检查 OpenClash 是否已经安装
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


    if [ -z "$OPENCLASH_VERSION" ]; then
        OPENCLASH_VERSION="unknown"
    fi
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
# 秒转换为毫秒
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
# 测试单条 GitHub 线路
#
# 使用 bootstrap.sh 小文件测速
# ============================================================

test_openclash_route()
{
    TEST_URL="$1"

    rm -f "$OC_TEST_FILE"


    # ========================================================
    # CURL
    # ========================================================

    if command -v curl >/dev/null 2>&1; then

        CURL_RESULT_DATA="$(
            curl -4 \
                -L \
                -sS \
                -f \
                --connect-timeout 4 \
                --max-time 10 \
                -o "$OC_TEST_FILE" \
                -w '%{http_code}|%{time_starttransfer}|%{time_total}' \
                "$TEST_URL" \
                2>/dev/null
        )"

        CURL_RESULT=$?


        if [ "$CURL_RESULT" -ne 0 ]; then
            rm -f "$OC_TEST_FILE"
            return 1
        fi


        HTTP_CODE="$(
            printf '%s' "$CURL_RESULT_DATA" |
            cut -d '|' -f 1
        )"


        START_TIME="$(
            printf '%s' "$CURL_RESULT_DATA" |
            cut -d '|' -f 2
        )"


        case "$HTTP_CODE" in

            200|206)
                ;;

            *)
                rm -f "$OC_TEST_FILE"
                return 1
                ;;

        esac


        if [ ! -s "$OC_TEST_FILE" ]; then
            rm -f "$OC_TEST_FILE"
            return 1
        fi


        # ----------------------------------------------------
        # 防止代理返回 HTML
        # ----------------------------------------------------

        if head -c 1024 "$OC_TEST_FILE" 2>/dev/null |
            grep -Eqi '<html|<!doctype|bad gateway|404 not found|502 bad gateway|403 forbidden'
        then

            rm -f "$OC_TEST_FILE"
            return 1
        fi


        # ----------------------------------------------------
        # 确认确实是我们的 bootstrap.sh
        # ----------------------------------------------------

        if ! grep -q 'Open-Pro-Installer' "$OC_TEST_FILE" 2>/dev/null; then

            rm -f "$OC_TEST_FILE"
            return 1
        fi


        TEST_MS="$(oc_seconds_to_ms "$START_TIME")"


        case "$TEST_MS" in

            ''|*[!0-9]*)
                rm -f "$OC_TEST_FILE"
                return 1
                ;;

        esac


        rm -f "$OC_TEST_FILE"


        printf '%s' "$TEST_MS"

        return 0
    fi


    # ========================================================
    # WGET 备用
    # ========================================================

    if command -v wget >/dev/null 2>&1; then

        START_SECONDS="$(date +%s 2>/dev/null)"


        if wget \
            -T 10 \
            -O "$OC_TEST_FILE" \
            "$TEST_URL" \
            >/dev/null 2>&1
        then

            if [ ! -s "$OC_TEST_FILE" ]; then
                rm -f "$OC_TEST_FILE"
                return 1
            fi


            if ! grep -q 'Open-Pro-Installer' "$OC_TEST_FILE" 2>/dev/null; then
                rm -f "$OC_TEST_FILE"
                return 1
            fi


            END_SECONDS="$(date +%s 2>/dev/null)"


            [ -n "$START_SECONDS" ] || START_SECONDS=0
            [ -n "$END_SECONDS" ] || END_SECONDS="$START_SECONDS"


            # ------------------------------------------------
            # 修正：BusyBox POSIX sh 正确算术语法
            # ------------------------------------------------

            TEST_MS=$(( (END_SECONDS - START_SECONDS) * 1000 ))


            if [ "$TEST_MS" -le 0 ]; then
                TEST_MS=1
            fi


            rm -f "$OC_TEST_FILE"


            printf '%s' "$TEST_MS"

            return 0
        fi
    fi


    rm -f "$OC_TEST_FILE"

    return 1
}


# ============================================================
# 准备 OpenClash 下载线路
#
# bootstrap.sh 测速
# OpenClash Release 真正下载
# ============================================================

prepare_openclash_routes()
{
    ORIGINAL_URL="$1"


    rm -f "$OC_ROUTE_FILE"
    rm -f "${OC_ROUTE_FILE}.sorted"
    rm -f "$OC_TEST_FILE"


    printf "\n"

    _oc_info "正在测试 GitHub 下载线路..."

    printf "\n"


    printf '%s\n' "$OPENCLASH_DOWNLOAD_NODES" |
    while IFS='|' read -r NODE_NAME NODE_PREFIX
    do

        [ -n "$NODE_NAME" ] || continue


        TEST_URL="$(
            build_openclash_url \
                "$NODE_PREFIX" \
                "$OC_SPEED_TEST_URL"
        )"


        DOWNLOAD_ROUTE_URL="$(
            build_openclash_url \
                "$NODE_PREFIX" \
                "$ORIGINAL_URL"
        )"


        printf '  %-8s ' "$NODE_NAME"


        NODE_MS="$(
            test_openclash_route "$TEST_URL"
        )"

        TEST_RESULT=$?


        if [ "$TEST_RESULT" -eq 0 ] &&
           [ -n "$NODE_MS" ]
        then

            printf '\033[32m%s ms\033[0m\n' "$NODE_MS"


            printf '%s|%s|%s|%s\n' \
                "$NODE_MS" \
                "$NODE_NAME" \
                "$NODE_PREFIX" \
                "$DOWNLOAD_ROUTE_URL" \
                >> "$OC_ROUTE_FILE"

        else

            printf '\033[31m不可用\033[0m\n'

        fi

    done


    rm -f "$OC_TEST_FILE"


    # ========================================================
    # 没有可用线路
    # ========================================================

    if [ ! -s "$OC_ROUTE_FILE" ]; then

        printf "\n"

        _oc_warn "测速没有发现可用线路"

        _oc_info "稍后尝试 GitHub 官方地址"

        return 1
    fi


    # ========================================================
    # 按延迟排序
    # ========================================================

    SORTED_FILE="${OC_ROUTE_FILE}.sorted"


    sort -n -t '|' -k 1,1 \
        "$OC_ROUTE_FILE" \
        > "$SORTED_FILE" \
        2>/dev/null


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


    # OpenClash 包正常明显大于 100KB

    if [ "$FILE_SIZE" -lt 102400 ]; then
        return 1
    fi


    # --------------------------------------------------------
    # 防止下载到 HTML 错误页
    # --------------------------------------------------------

    if head -c 1024 "$FILE" 2>/dev/null |
        grep -Eqi '<html|<!doctype|bad gateway|404 not found|502 bad gateway|403 forbidden'
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
        >"$OC_DOWNLOAD_LOG" 2>&1
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
        >"$OC_DOWNLOAD_LOG" 2>&1
}


# ============================================================
# 从指定 URL 下载 OpenClash
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
# OpenClash 智能下载
#
# 1. 测速
# 2. 排序
# 3. 最快优先
# 4. 失败切换
# 5. 官方兜底
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
    # 官方 GitHub 最终兜底
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
# OpenClash 安装进度条
# ============================================================

openclash_progress_bar()
{
    PERCENT="$1"
    WIDTH=30


    # ========================================================
    # 修正后的 BusyBox / POSIX sh 算术
    # ========================================================

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


    # ========================================================
    # 后台安装
    # ========================================================

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


    # ========================================================
    # 分析安装日志推进进度
    # ========================================================

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


        if [ "$PERCENT" -gt 95 ]; then
            PERCENT=95
        fi


        openclash_progress_bar "$PERCENT"


        sleep 1

    done


    # ========================================================
    # 获取真实安装结果
    # ========================================================

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


    if [ -z "$OPENCLASH_ARCH" ]; then
        OPENCLASH_ARCH="unknown"
    fi


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
# 检测 OpenClash Core
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
# Ctrl+C / 中断
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
# ============================================================

install_openclash()
{
    printf "\n"

    printf "======================================\n"
    printf "        OpenClash Installer\n"
    printf "======================================\n"

    printf "\n"


    # ========================================================
    # ROOT
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
    # CPU 架构
    # ========================================================

    detect_openclash_arch


    # ========================================================
    # install.sh 传入变量
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
    # 多线路智能下载
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
    # Core 目录
    # ========================================================

    mkdir -p "$OPENCLASH_CORE_DIR" \
        >/dev/null 2>&1


    # ========================================================
    # 检测 Core
    # ========================================================

    check_openclash_core


    # ========================================================
    # 检测更新组件
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

    printf "LuCI：服务 → OpenClash\n"

    printf "内核：OpenClash → 版本更新\n"

    printf "\n"


    return 0
}

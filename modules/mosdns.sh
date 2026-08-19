#!/bin/sh

# ============================================================
# Open-Pro-Installer
# MosDNS Smart Installer
#
# 适用：
# - OpenWrt / BusyBox /bin/sh
# - OPKG
# - aarch64_cortex-a53
#
# 功能：
# 1. 自动检测 Root / OPKG / 架构
# 2. 7 条 GitHub 线路并行测速
# 3. 测速仅显示：线路 / 延迟 / 下载速度
# 4. 下载速度优先、延迟辅助排序
# 5. MosDNS + LuCI 共用一次测速结果
# 6. 最佳线路失败自动切换下一线路
# 7. DIRECT 官方直连最终兜底
# 8. 下载后验证 IPK，防止代理返回 HTML
# 9. 自动安装基础依赖
# 10. 先安装 MosDNS Core，再安装 luci-app-mosdns
# 11. 自动验证安装结果
# 12. 自动 enable / restart MosDNS
# 13. 自动刷新 LuCI
#
# install.sh 调用：
#
# install_mosdns
#
# ============================================================


# ============================================================
# 颜色
# ============================================================

BOLD="$(printf '\033[1m')"
GREEN="$(printf '\033[1;92m')"
CYAN="$(printf '\033[1;96m')"
BLUE="$(printf '\033[1;94m')"
RED="$(printf '\033[1;91m')"
YELLOW="$(printf '\033[1;93m')"
WHITE="$(printf '\033[1;97m')"
RESET="$(printf '\033[0m')"


# ============================================================
# MosDNS 包信息
#
# 默认使用 GitHub Release：
# zimoadmin/Open-Pro-Installer
# Tag: mosdns-21.02
#
# 需要 Release 中存在下面两个文件：
#
# mosdns_5.3.4-7_aarch64_cortex-a53.ipk
# luci-app-mosdns_1.7.6_all.ipk
#
# 如果以后版本变化，只修改这里即可。
# ============================================================

MOSDNS_REPO="zimoadmin/Open-Pro-Installer"
MOSDNS_RELEASE_TAG="mosdns-21.02"

MOSDNS_CORE_FILE="mosdns_5.3.4-7_aarch64_cortex-a53.ipk"
MOSDNS_LUCI_FILE="luci-app-mosdns_1.7.6_all.ipk"

MOSDNS_RELEASE_BASE="https://github.com/${MOSDNS_REPO}/releases/download/${MOSDNS_RELEASE_TAG}"

MOSDNS_CORE_URL="${MOSDNS_RELEASE_BASE}/${MOSDNS_CORE_FILE}"
MOSDNS_LUCI_URL="${MOSDNS_RELEASE_BASE}/${MOSDNS_LUCI_FILE}"


# ============================================================
# 下载线路
#
# Name|Prefix
#
# DIRECT| = GitHub 官方直连
# ============================================================

MOSDNS_DOWNLOAD_NODES="
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
GH04|https://cdn.akaere.online/
GH05|https://github.mxw.qzz.io/
GH06|https://gh.07150721.xyz/
DIRECT|
"


# ============================================================
# 临时文件
# ============================================================

MOSDNS_TMP_DIR="/tmp/openpro_mosdns"
MOSDNS_TEST_DIR="${MOSDNS_TMP_DIR}/speedtest"
MOSDNS_ROUTE_FILE="${MOSDNS_TMP_DIR}/routes"
MOSDNS_SORTED_FILE="${MOSDNS_TMP_DIR}/routes.sorted"

MOSDNS_CORE_TMP="${MOSDNS_TMP_DIR}/${MOSDNS_CORE_FILE}"
MOSDNS_LUCI_TMP="${MOSDNS_TMP_DIR}/${MOSDNS_LUCI_FILE}"

MOSDNS_DOWNLOAD_LOG="${MOSDNS_TMP_DIR}/download.log"
MOSDNS_INSTALL_LOG="${MOSDNS_TMP_DIR}/install.log"


# ============================================================
# 测速设置
# ============================================================

MOSDNS_TEST_CONNECT_TIMEOUT=4
MOSDNS_TEST_MAX_TIME=6

# 至少收到 32KB 才认为测速有效
MOSDNS_TEST_MIN_BYTES=32768


# ============================================================
# 日志
# ============================================================

_md_info()
{
    printf "%b\n" "${GREEN}[INFO]${RESET} ${BOLD}$*${RESET}"
}

_md_ok()
{
    printf "%b\n" "${GREEN}[OK]${RESET} ${BOLD}$*${RESET}"
}

_md_warn()
{
    printf "%b\n" "${YELLOW}[WARN]${RESET} ${BOLD}$*${RESET}"
}

_md_error()
{
    printf "%b\n" "${RED}[ERROR]${RESET} ${BOLD}$*${RESET}"
}


# ============================================================
# 清理
# ============================================================

cleanup_mosdns_temp()
{
    rm -rf "$MOSDNS_TMP_DIR" 2>/dev/null
    return 0
}


# ============================================================
# 获取 OPKG 架构
# ============================================================

get_mosdns_pkg_arch()
{
    MOSDNS_PKG_ARCH=""

    if command -v opkg >/dev/null 2>&1; then
        MOSDNS_PKG_ARCH="$(
            opkg print-architecture 2>/dev/null |
            awk '
                $1 != "arch" && NF >= 2 {
                    print $1
                }
                $1 == "arch" && NF >= 2 {
                    print $2
                }
            ' |
            grep -v -E '^(all|noarch)$' |
            tail -n 1
        )"
    fi

    if [ -z "$MOSDNS_PKG_ARCH" ]; then
        MOSDNS_PKG_ARCH="$(
            . /etc/openwrt_release 2>/dev/null
            printf '%s' "${DISTRIB_ARCH:-}"
        )"
    fi

    [ -n "$MOSDNS_PKG_ARCH" ] || MOSDNS_PKG_ARCH="$(uname -m 2>/dev/null)"
}


# ============================================================
# 环境检测
# ============================================================

check_mosdns_environment()
{
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        _md_error "请使用 root 用户运行"
        return 1
    fi

    if ! command -v opkg >/dev/null 2>&1; then
        _md_error "当前系统没有检测到 OPKG"
        _md_warn "此版本 MosDNS 安装包面向 OpenWrt 21.02 / OPKG"
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        _md_info "当前系统缺少 curl，正在尝试安装..."

        opkg update >/dev/null 2>&1 || true

        if ! opkg install curl >/dev/null 2>&1; then
            _md_error "curl 安装失败"
            return 1
        fi
    fi

    if ! command -v awk >/dev/null 2>&1; then
        _md_error "当前系统缺少 awk"
        return 1
    fi

    if ! command -v sort >/dev/null 2>&1; then
        _md_error "当前系统缺少 sort"
        return 1
    fi

    get_mosdns_pkg_arch

    _md_info "软件包架构 : ${MOSDNS_PKG_ARCH:-unknown}"

    case "$MOSDNS_PKG_ARCH" in
        aarch64_cortex-a53)
            ;;
        *)
            _md_error "当前 MosDNS Core 不适用于该架构"
            _md_error "需要：aarch64_cortex-a53"
            _md_error "当前：${MOSDNS_PKG_ARCH:-unknown}"
            return 1
            ;;
    esac

    return 0
}


# ============================================================
# 构造代理 URL
# ============================================================

build_mosdns_url()
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
# 秒 -> 毫秒
# ============================================================

mosdns_seconds_to_ms()
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
# Bytes/s -> MB/s
# ============================================================

mosdns_speed_to_mb()
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
# 检测下载内容是否为错误网页
# ============================================================

mosdns_is_error_page()
{
    FILE="$1"

    [ -s "$FILE" ] || return 1

    if head -c 2048 "$FILE" 2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied|cloudflare'
    then
        return 0
    fi

    return 1
}


# ============================================================
# 单线路真实测速
#
# $1 URL
# $2 测速文件
#
# 输出：
# LATENCY_MS|SPEED_BPS|SIZE
#
# "延迟" 使用 TTFB / 首包时间。
# ============================================================

test_mosdns_route()
{
    TEST_URL="$1"
    TEST_FILE="$2"

    rm -f "$TEST_FILE"

    CURL_DATA="$(
        curl -4 \
            -L \
            -sS \
            --connect-timeout "$MOSDNS_TEST_CONNECT_TIMEOUT" \
            --max-time "$MOSDNS_TEST_MAX_TIME" \
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
                if (n == "" || n < 0) {
                    print 0
                } else {
                    printf "%d", n
                }
            }
        '
    )"

    if [ "$RECEIVED_BYTES" -lt "$MOSDNS_TEST_MIN_BYTES" ]; then
        rm -f "$TEST_FILE"
        return 1
    fi

    if mosdns_is_error_page "$TEST_FILE"; then
        rm -f "$TEST_FILE"
        return 1
    fi

    LATENCY_MS="$(mosdns_seconds_to_ms "$TTFB")"

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

    case "$LATENCY_MS" in
        ''|*[!0-9]*)
            rm -f "$TEST_FILE"
            return 1
            ;;
    esac

    case "$SPEED_INT" in
        ''|*[!0-9]*)
            rm -f "$TEST_FILE"
            return 1
            ;;
    esac

    if [ "$SPEED_INT" -le 0 ]; then
        rm -f "$TEST_FILE"
        return 1
    fi

    rm -f "$TEST_FILE"

    printf '%s|%s|%s' \
        "$LATENCY_MS" \
        "$SPEED_INT" \
        "$RECEIVED_BYTES"

    return 0
}


# ============================================================
# 单线路后台测速
# ============================================================

test_mosdns_route_background()
{
    NODE_NAME="$1"
    NODE_PREFIX="$2"
    ORIGINAL_URL="$3"
    RESULT_FILE="$4"
    TEST_FILE="$5"

    TEST_URL="$(
        build_mosdns_url \
            "$NODE_PREFIX" \
            "$ORIGINAL_URL"
    )"

    TEST_DATA="$(
        test_mosdns_route \
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

    LATENCY_MS="$(printf '%s' "$TEST_DATA" | cut -d '|' -f 1)"
    SPEED_BPS="$(printf '%s' "$TEST_DATA" | cut -d '|' -f 2)"
    RECEIVED="$(printf '%s' "$TEST_DATA" | cut -d '|' -f 3)"

    printf '%s|OK|%s|%s|%s|%s|%s\n' \
        "$NODE_NAME" \
        "$NODE_PREFIX" \
        "$TEST_URL" \
        "$LATENCY_MS" \
        "$SPEED_BPS" \
        "$RECEIVED" \
        > "$RESULT_FILE"

    rm -f "$TEST_FILE"

    return 0
}


# ============================================================
# 获取节点前缀
# ============================================================

get_mosdns_node_prefix()
{
    TARGET_NODE="$1"

    printf '%s\n' "$MOSDNS_DOWNLOAD_NODES" |
    awk -F '|' \
        -v node="$TARGET_NODE" \
        '$1 == node {
            print $2
            exit
        }'
}


# ============================================================
# 7 线路并行测速
#
# 只显示：
# 线路 / 延迟 / 下载速度
#
# 排名：
# 下载速度从高到低
# 同速度时延迟从低到高
#
# 路线文件格式：
# SPEED|LATENCY|NAME|PREFIX
# ============================================================

prepare_mosdns_routes()
{
    ORIGINAL_URL="$1"

    rm -rf "$MOSDNS_TEST_DIR"
    rm -f "$MOSDNS_ROUTE_FILE"
    rm -f "$MOSDNS_SORTED_FILE"

    mkdir -p "$MOSDNS_TEST_DIR" || return 1

    printf "\n"
    _md_info "正在并行测试 7 条下载线路..."
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
        NODE_PREFIX="$(get_mosdns_node_prefix "$NODE_NAME")"

        RESULT_FILE="${MOSDNS_TEST_DIR}/result_${NODE_NAME}"
        TEST_FILE="${MOSDNS_TEST_DIR}/download_${NODE_NAME}"

        test_mosdns_route_background \
            "$NODE_NAME" \
            "$NODE_PREFIX" \
            "$ORIGINAL_URL" \
            "$RESULT_FILE" \
            "$TEST_FILE" &
    done

    # BusyBox ash：等待全部后台测速完成
    wait

    printf '%-10s %-14s %-16s\n' \
        "线路" \
        "延迟" \
        "下载速度"

    printf '%-10s %-14s %-16s\n' \
        "----------" \
        "--------------" \
        "----------------"

    for NODE_NAME in \
        GH01 \
        GH02 \
        GH03 \
        GH04 \
        GH05 \
        GH06 \
        DIRECT
    do
        RESULT_FILE="${MOSDNS_TEST_DIR}/result_${NODE_NAME}"

        if [ ! -s "$RESULT_FILE" ]; then
            printf '%-10s %-14s %-16s\n' \
                "$NODE_NAME" \
                "----" \
                "----"
            continue
        fi

        RESULT_STATUS="$(cut -d '|' -f 2 "$RESULT_FILE")"

        if [ "$RESULT_STATUS" != "OK" ]; then
            printf '%-10s %-14s %-16s\n' \
                "$NODE_NAME" \
                "----" \
                "----"
            continue
        fi

        NODE_PREFIX="$(cut -d '|' -f 3 "$RESULT_FILE")"
        LATENCY_MS="$(cut -d '|' -f 5 "$RESULT_FILE")"
        SPEED_BPS="$(cut -d '|' -f 6 "$RESULT_FILE")"

        SPEED_MB="$(mosdns_speed_to_mb "$SPEED_BPS")"

        printf '%-10s %-14s %-16s\n' \
            "$NODE_NAME" \
            "${LATENCY_MS} ms" \
            "${SPEED_MB} MB/s"

        printf '%s|%s|%s|%s\n' \
            "$SPEED_BPS" \
            "$LATENCY_MS" \
            "$NODE_NAME" \
            "$NODE_PREFIX" \
            >> "$MOSDNS_ROUTE_FILE"
    done

    rm -rf "$MOSDNS_TEST_DIR"

    if [ ! -s "$MOSDNS_ROUTE_FILE" ]; then
        printf "\n"
        _md_warn "没有发现可用测速线路"
        _md_info "下载时将直接尝试 GitHub 官方地址"
        return 1
    fi

    # 速度降序，延迟升序
    sort -t '|' \
        -k1,1nr \
        -k2,2n \
        "$MOSDNS_ROUTE_FILE" \
        > "$MOSDNS_SORTED_FILE" \
        2>/dev/null

    if [ -s "$MOSDNS_SORTED_FILE" ]; then
        mv "$MOSDNS_SORTED_FILE" "$MOSDNS_ROUTE_FILE"
    fi

    BEST_LINE="$(sed -n '1p' "$MOSDNS_ROUTE_FILE")"

    BEST_SPEED="$(printf '%s\n' "$BEST_LINE" | cut -d '|' -f 1)"
    BEST_LATENCY="$(printf '%s\n' "$BEST_LINE" | cut -d '|' -f 2)"
    BEST_NAME="$(printf '%s\n' "$BEST_LINE" | cut -d '|' -f 3)"

    BEST_SPEED_MB="$(mosdns_speed_to_mb "$BEST_SPEED")"

    printf "\n"
    _md_ok "最佳线路：$BEST_NAME"
    _md_info "延迟：${BEST_LATENCY} ms"
    _md_info "下载速度：${BEST_SPEED_MB} MB/s"
    printf "\n"

    return 0
}


# ============================================================
# 验证 IPK
#
# OpenWrt 21.02 的 IPK 可能是 gzip tar 格式，
# 因此不强依赖 ar。
# ============================================================

verify_mosdns_ipk()
{
    FILE="$1"

    [ -s "$FILE" ] || return 1

    FILE_SIZE="$(wc -c < "$FILE" 2>/dev/null)"

    case "$FILE_SIZE" in
        ''|*[!0-9]*)
            FILE_SIZE=0
            ;;
    esac

    if [ "$FILE_SIZE" -lt 10240 ]; then
        return 1
    fi

    if mosdns_is_error_page "$FILE"; then
        return 1
    fi

    # OpenWrt 21.02 常见 gzip tar IPK
    if tar -tzf "$FILE" >/dev/null 2>&1; then
        if tar -tzf "$FILE" 2>/dev/null |
            grep -q 'control.tar'
        then
            return 0
        fi
    fi

    # 兼容 ar 格式 IPK
    if command -v ar >/dev/null 2>&1; then
        if ar t "$FILE" 2>/dev/null |
            grep -q 'control.tar'
        then
            return 0
        fi
    fi

    return 1
}


# ============================================================
# 指定 URL 正式下载
# ============================================================

download_mosdns_url()
{
    URL="$1"
    OUTPUT="$2"

    rm -f "$OUTPUT"
    rm -f "$MOSDNS_DOWNLOAD_LOG"

    if ! curl -4 \
        -L \
        -f \
        -sS \
        --connect-timeout 8 \
        --max-time 180 \
        --retry 1 \
        --retry-delay 1 \
        -o "$OUTPUT" \
        "$URL" \
        >"$MOSDNS_DOWNLOAD_LOG" 2>&1
    then
        rm -f "$OUTPUT"
        return 1
    fi

    if ! verify_mosdns_ipk "$OUTPUT"; then
        rm -f "$OUTPUT"
        return 1
    fi

    return 0
}


# ============================================================
# 使用已经测速得到的路线表下载
#
# 两个 IPK 共用同一 MOSDNS_ROUTE_FILE，
# 不会重复进行 7 线路测速。
# ============================================================

smart_download_mosdns_file()
{
    ORIGINAL_URL="$1"
    OUTPUT="$2"
    DISPLAY_NAME="$3"

    DOWNLOAD_SUCCESS=0
    DIRECT_TRIED=0

    if [ -s "$MOSDNS_ROUTE_FILE" ]; then

        while IFS='|' read -r \
            ROUTE_SPEED \
            ROUTE_LATENCY \
            ROUTE_NAME \
            ROUTE_PREFIX
        do
            [ -n "$ROUTE_NAME" ] || continue

            if [ "$ROUTE_NAME" = "DIRECT" ]; then
                DIRECT_TRIED=1
            fi

            DOWNLOAD_URL="$(
                build_mosdns_url \
                    "$ROUTE_PREFIX" \
                    "$ORIGINAL_URL"
            )"

            _md_info "正在下载 ${DISPLAY_NAME}：$ROUTE_NAME"

            if download_mosdns_url \
                "$DOWNLOAD_URL" \
                "$OUTPUT"
            then
                _md_ok "${DISPLAY_NAME} 下载完成"
                DOWNLOAD_SUCCESS=1
                break
            fi

            _md_warn "$ROUTE_NAME 下载失败，自动切换下一线路..."

        done < "$MOSDNS_ROUTE_FILE"
    fi

    # 没有路线表或 DIRECT 尚未尝试时，官方直连兜底
    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] &&
       [ "$DIRECT_TRIED" -ne 1 ]
    then
        _md_info "正在使用 GitHub 官方直连下载 ${DISPLAY_NAME}..."

        if download_mosdns_url \
            "$ORIGINAL_URL" \
            "$OUTPUT"
        then
            _md_ok "${DISPLAY_NAME} 下载完成"
            DOWNLOAD_SUCCESS=1
        fi
    fi

    [ "$DOWNLOAD_SUCCESS" -eq 1 ]
}


# ============================================================
# 检查软件包是否已经安装
# ============================================================

mosdns_pkg_installed()
{
    PKG="$1"

    opkg status "$PKG" 2>/dev/null |
    grep -q 'Status:.*installed'
}


# ============================================================
# 安装依赖
#
# luci-app-mosdns_1.7.6 依赖：
# mosdns, curl, v2ray-geoip, v2ray-geosite, v2dat, ucode
#
# mosdns Core 依赖：
# libc, ca-bundle
# ============================================================

install_mosdns_dependencies()
{
    printf "\n"
    _md_info "正在检查 MosDNS 依赖..."

    opkg update >/dev/null 2>&1 || \
        _md_warn "软件源更新存在异常，将继续尝试安装依赖"

    DEPENDENCIES="
ca-bundle
curl
v2ray-geoip
v2ray-geosite
v2dat
ucode
"

    MISSING_DEP=""

    for PKG in $DEPENDENCIES
    do
        if mosdns_pkg_installed "$PKG"; then
            continue
        fi

        _md_info "正在安装依赖：$PKG"

        if opkg install "$PKG" >/dev/null 2>&1; then
            _md_ok "$PKG 安装完成"
        else
            _md_warn "$PKG 安装失败"
            MISSING_DEP="${MISSING_DEP} ${PKG}"
        fi
    done

    if [ -n "$MISSING_DEP" ]; then
        printf "\n"
        _md_error "以下依赖当前软件源中无法正常安装："
        printf "%b\n" "${RED}${MISSING_DEP}${RESET}"
        _md_warn "为避免强制安装导致 LuCI/MosDNS 异常，已停止安装"
        return 1
    fi

    _md_ok "MosDNS 依赖检查完成"

    return 0
}


# ============================================================
# 安装单个 IPK
# ============================================================

install_mosdns_ipk()
{
    FILE="$1"
    NAME="$2"

    rm -f "$MOSDNS_INSTALL_LOG"

    _md_info "正在安装：$NAME"

    if opkg install "$FILE" \
        >"$MOSDNS_INSTALL_LOG" 2>&1
    then
        _md_ok "$NAME 安装完成"
        return 0
    fi

    _md_error "$NAME 安装失败"

    if [ -s "$MOSDNS_INSTALL_LOG" ]; then
        printf "\n"
        printf "%b\n" "${RED}========== INSTALL ERROR ==========${RESET}"
        cat "$MOSDNS_INSTALL_LOG"
        printf "%b\n" "${RED}===================================${RESET}"
        printf "\n"
    fi

    return 1
}


# ============================================================
# 刷新 LuCI
# ============================================================

reload_mosdns_luci()
{
    rm -rf \
        /tmp/luci-* \
        /tmp/luci-indexcache \
        /tmp/luci-modulecache \
        2>/dev/null

    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd restart >/dev/null 2>&1 || true
    fi

    if [ -x /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd reload >/dev/null 2>&1 || true
    fi

    return 0
}


# ============================================================
# 验证安装结果
# ============================================================

verify_mosdns_install()
{
    printf "\n"
    _md_info "正在验证 MosDNS 安装结果..."

    if ! mosdns_pkg_installed mosdns; then
        _md_error "未检测到 mosdns 软件包"
        return 1
    fi

    if ! mosdns_pkg_installed luci-app-mosdns; then
        _md_error "未检测到 luci-app-mosdns 软件包"
        return 1
    fi

    if ! command -v mosdns >/dev/null 2>&1; then
        _md_error "没有检测到 mosdns 可执行文件"
        return 1
    fi

    _md_ok "MosDNS Core 安装成功"
    _md_ok "luci-app-mosdns 安装成功"

    MOSDNS_VERSION="$(
        mosdns version 2>/dev/null |
        head -n 1
    )"

    if [ -z "$MOSDNS_VERSION" ]; then
        MOSDNS_VERSION="$(
            mosdns -v 2>/dev/null |
            head -n 1
        )"
    fi

    if [ -n "$MOSDNS_VERSION" ]; then
        _md_info "Core：$MOSDNS_VERSION"
    fi

    if [ -x /etc/init.d/mosdns ]; then

        /etc/init.d/mosdns enable >/dev/null 2>&1 || true

        if /etc/init.d/mosdns restart >/dev/null 2>&1; then
            _md_ok "MosDNS 服务已启动"
        else
            _md_warn "MosDNS 已安装，但服务暂未成功启动"
            _md_warn "可进入 LuCI → 服务 → MosDNS 检查配置"
        fi

    else
        _md_warn "没有检测到 /etc/init.d/mosdns"
    fi

    reload_mosdns_luci

    return 0
}


# ============================================================
# 中断处理
# ============================================================

interrupt_mosdns()
{
    printf "\n"
    _md_warn "MosDNS 安装被中断"

    cleanup_mosdns_temp

    trap - INT TERM

    return 130
}


# ============================================================
# 主安装函数
# ============================================================

install_mosdns()
{
    printf "\n"

    printf "%b\n" "${BLUE}======================================${RESET}"
    printf "%b\n" "${GREEN}           MosDNS Installer${RESET}"
    printf "%b\n" "${BLUE}======================================${RESET}"

    printf "\n"

    if ! check_mosdns_environment; then
        return 1
    fi

    # 已安装
    if mosdns_pkg_installed mosdns &&
       mosdns_pkg_installed luci-app-mosdns
    then
        _md_ok "MosDNS 已经安装"
        verify_mosdns_install
        return 0
    fi

    cleanup_mosdns_temp
    mkdir -p "$MOSDNS_TMP_DIR" || {
        _md_error "无法创建临时目录"
        return 1
    }

    trap 'interrupt_mosdns' INT TERM

    # ========================================================
    # 一次测速
    #
    # 使用较大的 MosDNS Core 作为测速对象，
    # 测速结果同时给 Core 和 LuCI 使用。
    # ========================================================

    prepare_mosdns_routes "$MOSDNS_CORE_URL" || true

    # ========================================================
    # 下载 Core
    # ========================================================

    if ! smart_download_mosdns_file \
        "$MOSDNS_CORE_URL" \
        "$MOSDNS_CORE_TMP" \
        "MosDNS Core"
    then
        _md_error "MosDNS Core 下载失败"
        cleanup_mosdns_temp
        trap - INT TERM
        return 1
    fi

    # ========================================================
    # 下载 LuCI
    # ========================================================

    if ! smart_download_mosdns_file \
        "$MOSDNS_LUCI_URL" \
        "$MOSDNS_LUCI_TMP" \
        "luci-app-mosdns"
    then
        _md_error "luci-app-mosdns 下载失败"
        cleanup_mosdns_temp
        trap - INT TERM
        return 1
    fi

    # ========================================================
    # 依赖
    # ========================================================

    if ! install_mosdns_dependencies; then
        cleanup_mosdns_temp
        trap - INT TERM
        return 1
    fi

    # ========================================================
    # Core
    # ========================================================

    if ! install_mosdns_ipk \
        "$MOSDNS_CORE_TMP" \
        "MosDNS Core"
    then
        cleanup_mosdns_temp
        trap - INT TERM
        return 1
    fi

    # ========================================================
    # LuCI
    # ========================================================

    if ! install_mosdns_ipk \
        "$MOSDNS_LUCI_TMP" \
        "luci-app-mosdns"
    then
        cleanup_mosdns_temp
        trap - INT TERM
        return 1
    fi

    # ========================================================
    # 验证
    # ========================================================

    if ! verify_mosdns_install; then
        cleanup_mosdns_temp
        trap - INT TERM
        return 1
    fi

    cleanup_mosdns_temp

    trap - INT TERM

    printf "\n"
    printf "%b\n" "${BLUE}======================================${RESET}"
    printf "%b\n" "${GREEN}          MosDNS Installed${RESET}"
    printf "%b\n" "${BLUE}======================================${RESET}"
    printf "\n"

    _md_ok "MosDNS 安装完成"
    _md_info "Core : 5.3.4-7"
    _md_info "LuCI : 1.7.6"

    printf "\n"
    printf "%b\n" "${CYAN}LuCI：服务 → MosDNS${RESET}"
    printf "\n"

    return 0
}

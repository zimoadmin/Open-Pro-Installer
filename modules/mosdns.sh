#!/bin/sh

# ============================================================
# Open-Pro-Installer
# MosDNS Smart Installer
#
# 功能：
# 1. 自动检测 OpenWrt 系统
# 2. 自动检测 OPKG / APK
# 3. 自动识别 OpenWrt 精确软件包架构
# 4. 自动选择 OpenWrt 24.10 / 25.12 Release 包
# 5. 检查官方支持的平台架构
# 6. 检查可用存储空间
# 7. GH01-GH06 + DIRECT 并行真实测速
# 8. 检测 TTFB 首包时间
# 9. 检测实际下载速度
# 10. 综合计算最佳下载线路
# 11. 最佳线路失败自动切换
# 12. DIRECT 官方 GitHub 最终兜底
# 13. 自动验证 tar.gz
# 14. 自动解压 Release 软件包
# 15. 自动递归寻找 APK / IPK
# 16. 自动检查六个必要组件
# 17. 按依赖顺序逐个安装
# 18. 每安装一个组件立即验证
# 19. 安装失败显示对应日志
# 20. 自动启动 MosDNS
# 21. 自动刷新 LuCI
# 22. 最终验证 MosDNS / LuCI
#
# BusyBox / OpenWrt /bin/sh Compatible
# ============================================================


# ============================================================
# 基础配置
# ============================================================

MOSDNS_TMP_DIR="/tmp/openpro_mosdns"
MOSDNS_ARCHIVE_FILE=""
MOSDNS_ARCHIVE_NAME=""
MOSDNS_BASE_URL=""

MOSDNS_INSTALL_LOG="/tmp/openpro_mosdns_install.log"
MOSDNS_DOWNLOAD_LOG="/tmp/openpro_mosdns_download.log"

MOSDNS_ROUTE_FILE="/tmp/openpro_mosdns_routes"
MOSDNS_SORTED_FILE="/tmp/openpro_mosdns_routes.sorted"

MOSDNS_TEST_DIR="/tmp/openpro_mosdns_speedtest.d"

MOSDNS_CPU_ARCH=""
MOSDNS_ARCH=""
MOSDNS_PKG_MANAGER=""
MOSDNS_PKG_EXT=""
MOSDNS_SDK=""

MOSDNS_WAS_RUNNING=0

V2DAT_PKG=""
V2RAY_GEOIP_PKG=""
V2RAY_GEOSITE_PKG=""
MOSDNS_MAIN_PKG=""
MOSDNS_LUCI_PKG=""
MOSDNS_I18N_PKG=""


# ============================================================
# 测速设置
# ============================================================

MOSDNS_TEST_CONNECT_TIMEOUT=4
MOSDNS_TEST_MAX_TIME=6

# 按 10MB 文件预计下载时间计算综合评分
MOSDNS_SCORE_FILE_KB=10240


# ============================================================
# GitHub 下载线路
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
# 官方支持架构
# ============================================================

MOSDNS_SUPPORTED_ARCHS="
aarch64_cortex-a53
aarch64_cortex-a72
aarch64_cortex-a76
aarch64_generic
arm_arm1176jzf-s_vfp
arm_arm926ej-s
arm_cortex-a15_neon-vfpv4
arm_cortex-a5_vfpv4
arm_cortex-a7
arm_cortex-a7_neon-vfpv4
arm_cortex-a7_vfpv4
arm_cortex-a8_vfpv3
arm_cortex-a9
arm_cortex-a9_neon
arm_cortex-a9_vfpv3-d16
arm_fa526
arm_xscale
i386_pentium-mmx
i386_pentium4
loongarch64_generic
mips64_mips64r2
mips64_octeonplus
mips64el_mips64r2
mips_24kc
mips_4kec
mips_mips32
mipsel_24kc
mipsel_24kc_24kf
mipsel_74kc
mipsel_mips32
riscv64_riscv64
riscv64_generic
x86_64
"


# ============================================================
# 日志
# ============================================================

_mos_info()
{
    if command -v info >/dev/null 2>&1; then
        info "$*"
    else
        printf '\033[1;92m[INFO]\033[0m %s\n' "$*"
    fi
}


_mos_warn()
{
    if command -v warning >/dev/null 2>&1; then
        warning "$*"
    elif command -v warn >/dev/null 2>&1; then
        warn "$*"
    else
        printf '\033[1;93m[WARN]\033[0m %s\n' "$*"
    fi
}


_mos_error()
{
    if command -v error >/dev/null 2>&1; then
        error "$*"
    else
        printf '\033[1;91m[ERROR]\033[0m %s\n' "$*"
    fi
}


_mos_ok()
{
    printf '\033[1;92m[OK]\033[0m %s\n' "$*"
}


# ============================================================
# 清理
# ============================================================

cleanup_mosdns_temp()
{
    rm -rf "$MOSDNS_TMP_DIR" 2>/dev/null

    rm -f "$MOSDNS_ROUTE_FILE" 2>/dev/null
    rm -f "$MOSDNS_SORTED_FILE" 2>/dev/null

    rm -rf "$MOSDNS_TEST_DIR" 2>/dev/null

    return 0
}


cleanup_mosdns_logs()
{
    rm -f "$MOSDNS_INSTALL_LOG" 2>/dev/null
    rm -f "$MOSDNS_DOWNLOAD_LOG" 2>/dev/null

    return 0
}


cleanup_mosdns_all()
{
    cleanup_mosdns_temp
    cleanup_mosdns_logs

    return 0
}


# ============================================================
# 中断
# ============================================================

interrupt_mosdns()
{
    printf "\n"

    _mos_warn "MosDNS 安装被中断"


    if [ "$MOSDNS_WAS_RUNNING" -eq 1 ] &&
       [ -x /etc/init.d/mosdns ]
    then

        /etc/init.d/mosdns start \
            >/dev/null 2>&1

    fi


    cleanup_mosdns_all

    trap - INT TERM

    return 130
}


# ============================================================
# 基础环境检查
# ============================================================

check_mosdns_runtime()
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
        find \
        tar \
        gzip \
        df \
        wc \
        curl
    do

        if ! command -v "$CMD" >/dev/null 2>&1; then

            MISSING="$MISSING $CMD"

        fi

    done


    if [ -n "$MISSING" ]; then

        _mos_error "系统缺少必要命令:$MISSING"

        return 1
    fi


    return 0
}


# ============================================================
# 检测 OpenWrt
# ============================================================

detect_mosdns_openwrt()
{
    if [ ! -f /etc/openwrt_release ]; then

        _mos_error "当前系统不是受支持的 OpenWrt"

        return 1

    fi


    . /etc/openwrt_release


    _mos_info "OpenWrt Version : ${DISTRIB_RELEASE:-unknown}"

    _mos_info "OpenWrt Target  : ${DISTRIB_TARGET:-unknown}"


    if [ ! -d /usr/share/luci/menu.d ]; then

        _mos_error "当前 LuCI 版本不受支持"

        _mos_error "MosDNS 要求 OpenWrt 21.02 或更高版本"

        return 1

    fi


    return 0
}


# ============================================================
# 检测 CPU
# ============================================================

detect_mosdns_cpu()
{
    MOSDNS_CPU_ARCH="$(uname -m 2>/dev/null)"


    [ -n "$MOSDNS_CPU_ARCH" ] ||
        MOSDNS_CPU_ARCH="unknown"


    _mos_info "CPU Architecture : $MOSDNS_CPU_ARCH"


    return 0
}


# ============================================================
# 检测包管理器
#
# 当前官方：
#
# APK  → openwrt-25.12
# OPKG → openwrt-24.10
# ============================================================

detect_mosdns_package_manager()
{
    MOSDNS_PKG_MANAGER=""
    MOSDNS_PKG_EXT=""
    MOSDNS_SDK=""


    if command -v apk >/dev/null 2>&1; then

        MOSDNS_PKG_MANAGER="apk"

        MOSDNS_PKG_EXT="apk"

        MOSDNS_SDK="openwrt-25.12"


    elif command -v opkg >/dev/null 2>&1; then

        MOSDNS_PKG_MANAGER="opkg"

        MOSDNS_PKG_EXT="ipk"

        MOSDNS_SDK="openwrt-24.10"


    else

        _mos_error "没有检测到 APK / OPKG 包管理器"

        return 1

    fi


    _mos_info "Package Manager  : $MOSDNS_PKG_MANAGER"

    _mos_info "Package Format   : $MOSDNS_PKG_EXT"

    _mos_info "MosDNS SDK       : $MOSDNS_SDK"


    return 0
}


# ============================================================
# 检测 OpenWrt 精确架构
# ============================================================

detect_mosdns_arch()
{
    MOSDNS_ARCH=""


    if [ -f /etc/openwrt_release ]; then

        . /etc/openwrt_release

        MOSDNS_ARCH="${DISTRIB_ARCH:-}"

    fi


    # ========================================================
    # OPKG 备用检测
    # ========================================================

    if [ -z "$MOSDNS_ARCH" ] &&
       command -v opkg >/dev/null 2>&1
    then

        MOSDNS_ARCH="$(
            opkg print-architecture 2>/dev/null |
            awk '
                $1 == "arch" &&
                $2 != "all" &&
                $2 != "noarch" {

                    if ($3 > priority) {

                        priority = $3
                        arch = $2

                    }
                }

                END {
                    print arch
                }
            '
        )"

    fi


    # ========================================================
    # APK 备用检测
    # ========================================================

    if [ -z "$MOSDNS_ARCH" ] &&
       command -v apk >/dev/null 2>&1
    then

        MOSDNS_ARCH="$(
            apk --print-arch 2>/dev/null |
            head -n 1
        )"

    fi


    if [ -z "$MOSDNS_ARCH" ]; then

        _mos_error "无法识别 OpenWrt 软件包架构"

        return 1

    fi


    _mos_info "Package Arch     : $MOSDNS_ARCH"


    return 0
}


# ============================================================
# 检查官方是否支持此架构
# ============================================================

check_mosdns_arch_supported()
{
    FOUND=0


    for ARCH_ITEM in $MOSDNS_SUPPORTED_ARCHS
    do

        if [ "$MOSDNS_ARCH" = "$ARCH_ITEM" ]; then

            FOUND=1

            break

        fi

    done


    if [ "$FOUND" -ne 1 ]; then

        _mos_error "MosDNS 官方暂不支持当前架构：$MOSDNS_ARCH"

        return 1

    fi


    _mos_ok "当前架构受 MosDNS 官方支持"


    return 0
}


# ============================================================
# 检查空间
# ============================================================

check_mosdns_disk_space()
{
    FREE_KB="$(
        df -k /usr 2>/dev/null |
        awk '
            END {
                print $4
            }
        '
    )"


    case "$FREE_KB" in
        ''|*[!0-9]*)
            FREE_KB=0
            ;;
    esac


    FREE_MB=$((FREE_KB / 1024))


    _mos_info "可用空间        : ${FREE_MB} MB"


    if [ "$FREE_MB" -lt 35 ]; then

        _mos_error "可用存储空间不足"

        _mos_error "安装 MosDNS 至少需要约 35 MB 可用空间"

        return 1

    fi


    return 0
}


# ============================================================
# 构造下载信息
# ============================================================

prepare_mosdns_download_info()
{
    MOSDNS_ARCHIVE_NAME="${MOSDNS_ARCH}-${MOSDNS_SDK}.tar.gz"


    MOSDNS_BASE_URL="https://github.com/sbwml/luci-app-mosdns/releases/latest/download/${MOSDNS_ARCHIVE_NAME}"


    mkdir -p "$MOSDNS_TMP_DIR" \
        >/dev/null 2>&1


    MOSDNS_ARCHIVE_FILE="${MOSDNS_TMP_DIR}/${MOSDNS_ARCHIVE_NAME}"


    _mos_info "Release Package  : $MOSDNS_ARCHIVE_NAME"


    return 0
}


# ============================================================
# GitHub URL 构造
# ============================================================

build_mosdns_url()
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

mosdns_seconds_to_ms()
{
    VALUE="$1"


    awk \
        -v t="$VALUE" '
        BEGIN {

            if (t == "" ||
                t !~ /^[0-9.]+$/)
            {
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

mosdns_speed_to_mb()
{
    VALUE="$1"


    awk \
        -v s="$VALUE" '
        BEGIN {

            if (s == "" ||
                s <= 0)
            {
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

mosdns_calculate_score()
{
    TTFB_MS="$1"
    SPEED_BPS="$2"


    awk \
        -v t="$TTFB_MS" \
        -v s="$SPEED_BPS" \
        -v kb="$MOSDNS_SCORE_FILE_KB" '
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

mosdns_test_is_error_page()
{
    FILE="$1"


    if [ ! -s "$FILE" ]; then
        return 1
    fi


    if head -c 1024 "$FILE" 2>/dev/null |
        grep -Eqi \
        '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied|cloudflare'
    then

        return 0

    fi


    return 1
}


# ============================================================
# 单线路测速
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


    # curl 超时 28 时，如果已经真实下载到数据，
    # 仍允许参与测速。

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
        awk \
            -v n="$SIZE_DOWN" '
            BEGIN {
                printf "%d", n
            }
        '
    )"


    if [ "$RECEIVED_BYTES" -lt 4096 ]; then

        rm -f "$TEST_FILE"

        return 1

    fi


    if mosdns_test_is_error_page "$TEST_FILE"; then

        rm -f "$TEST_FILE"

        return 1

    fi


    TTFB_MS="$(
        mosdns_seconds_to_ms \
            "$TTFB"
    )"


    SPEED_INT="$(
        awk \
            -v s="$SPEED_BPS" '
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
        mosdns_calculate_score \
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
# 后台测速
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

prepare_mosdns_routes()
{
    ORIGINAL_URL="$1"


    rm -f "$MOSDNS_ROUTE_FILE"
    rm -f "$MOSDNS_SORTED_FILE"

    rm -rf "$MOSDNS_TEST_DIR"

    mkdir -p "$MOSDNS_TEST_DIR"


    printf "\n"

    _mos_info "正在并行测试 MosDNS 下载线路..."

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
            printf '%s\n' "$MOSDNS_DOWNLOAD_NODES" |
            awk \
                -F '|' \
                -v node="$NODE_NAME" \
                '$1 == node {
                    print $2
                    exit
                }'
        )"


        RESULT_FILE="${MOSDNS_TEST_DIR}/result_${NODE_NAME}"

        TEST_FILE="${MOSDNS_TEST_DIR}/download_${NODE_NAME}"


        test_mosdns_route_background \
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

        RESULT_FILE="${MOSDNS_TEST_DIR}/result_${NODE_NAME}"


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
            mosdns_speed_to_mb \
                "$SPEED_BPS"
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
            >> "$MOSDNS_ROUTE_FILE"

    done


    rm -rf "$MOSDNS_TEST_DIR"


    if [ ! -s "$MOSDNS_ROUTE_FILE" ]; then

        printf "\n"

        _mos_warn "没有发现可用测速线路"

        return 1

    fi


    sort \
        -n \
        -t '|' \
        -k 1,1 \
        "$MOSDNS_ROUTE_FILE" \
        > "$MOSDNS_SORTED_FILE" \
        2>/dev/null


    if [ -s "$MOSDNS_SORTED_FILE" ]; then

        mv "$MOSDNS_SORTED_FILE" \
            "$MOSDNS_ROUTE_FILE"

    else

        rm -f "$MOSDNS_SORTED_FILE"

    fi


    BEST_LINE="$(
        sed -n '1p' \
            "$MOSDNS_ROUTE_FILE"
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
        mosdns_speed_to_mb \
            "$BEST_SPEED"
    )"


    printf "\n"

    _mos_ok "最佳线路：$BEST_NAME"

    _mos_info "首包时间：${BEST_TTFB} ms"

    _mos_info "下载速度：${BEST_SPEED_MB} MB/s"

    printf "\n"


    return 0
}


# ============================================================
# 验证下载文件
# ============================================================

verify_mosdns_archive()
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


    # 正常 Release 包十几 MB。
    # 小于 1MB 基本可以判定异常。

    if [ "$FILE_SIZE" -lt 1048576 ]; then

        return 1

    fi


    if mosdns_test_is_error_page "$FILE"; then

        return 1

    fi


    # 真正验证 gzip/tar

    if ! tar -tzf "$FILE" \
        >/dev/null 2>&1
    then

        return 1

    fi


    return 0
}


# ============================================================
# 下载指定 URL
# ============================================================

download_mosdns_from_url()
{
    URL="$1"
    OUTPUT="$2"


    rm -f "$OUTPUT"
    rm -f "$MOSDNS_DOWNLOAD_LOG"


    curl -4 \
        -L \
        -f \
        -sS \
        --connect-timeout 10 \
        --max-time 300 \
        --retry 1 \
        --retry-delay 1 \
        -o "$OUTPUT" \
        "$URL" \
        > "$MOSDNS_DOWNLOAD_LOG" 2>&1


    RESULT=$?


    if [ "$RESULT" -ne 0 ]; then

        rm -f "$OUTPUT"

        return 1

    fi


    if ! verify_mosdns_archive "$OUTPUT"; then

        rm -f "$OUTPUT"

        return 1

    fi


    return 0
}


# ============================================================
# 智能下载
# ============================================================

smart_download_mosdns()
{
    ORIGINAL_URL="$1"
    OUTPUT="$2"


    prepare_mosdns_routes \
        "$ORIGINAL_URL"


    DOWNLOAD_SUCCESS=0
    DIRECT_TRIED=0


    if [ -s "$MOSDNS_ROUTE_FILE" ]; then

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
                mosdns_speed_to_mb \
                    "$ROUTE_SPEED"
            )"


            _mos_info "正在使用线路：$ROUTE_NAME"

            _mos_info "测速速度：${ROUTE_SPEED_MB} MB/s"


            if download_mosdns_from_url \
                "$ROUTE_URL" \
                "$OUTPUT"
            then

                _mos_ok "MosDNS 下载线路：$ROUTE_NAME"

                DOWNLOAD_SUCCESS=1

                break

            fi


            _mos_warn "$ROUTE_NAME 下载失败，切换下一线路..."


        done < "$MOSDNS_ROUTE_FILE"

    fi


    # ========================================================
    # DIRECT 最终兜底
    # ========================================================

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] &&
       [ "$DIRECT_TRIED" -ne 1 ]
    then

        _mos_info "正在尝试 GitHub 官方直连..."


        if download_mosdns_from_url \
            "$ORIGINAL_URL" \
            "$OUTPUT"
        then

            _mos_ok "GitHub 官方直连下载成功"

            DOWNLOAD_SUCCESS=1

        fi

    fi


    rm -f "$MOSDNS_ROUTE_FILE"
    rm -f "$MOSDNS_SORTED_FILE"


    [ "$DOWNLOAD_SUCCESS" -eq 1 ]
}


# ============================================================
# 解压
# ============================================================

extract_mosdns_archive()
{
    _mos_info "正在解压 MosDNS 安装包..."


    if ! tar -zxf \
        "$MOSDNS_ARCHIVE_FILE" \
        -C "$MOSDNS_TMP_DIR" \
        >/dev/null 2>&1
    then

        _mos_error "MosDNS 安装包解压失败"

        return 1

    fi


    _mos_ok "MosDNS 安装包解压完成"


    return 0
}


# ============================================================
# 查找指定软件包
#
# 自动递归查找，所以同时支持：
#
# /tmp/openpro_mosdns/*.apk
#
# 以及
#
# /tmp/openpro_mosdns/packages_ci/*.apk
# ============================================================

find_mosdns_package()
{
    PACKAGE_PREFIX="$1"


    find "$MOSDNS_TMP_DIR" \
        -type f \
        -name "${PACKAGE_PREFIX}*.${MOSDNS_PKG_EXT}" \
        2>/dev/null |
        head -n 1
}


# ============================================================
# 定位 6 个安装包
# ============================================================

locate_mosdns_packages()
{
    _mos_info "正在识别 MosDNS 组件..."


    V2DAT_PKG="$(
        find_mosdns_package \
            "v2dat"
    )"


    V2RAY_GEOIP_PKG="$(
        find_mosdns_package \
            "v2ray-geoip"
    )"


    V2RAY_GEOSITE_PKG="$(
        find_mosdns_package \
            "v2ray-geosite"
    )"


    MOSDNS_MAIN_PKG="$(
        find_mosdns_package \
            "mosdns"
    )"


    MOSDNS_LUCI_PKG="$(
        find_mosdns_package \
            "luci-app-mosdns"
    )"


    MOSDNS_I18N_PKG="$(
        find_mosdns_package \
            "luci-i18n-mosdns-zh-cn"
    )"


    MISSING_PACKAGE=0


    if [ -z "$V2DAT_PKG" ]; then

        _mos_error "缺少组件：v2dat"

        MISSING_PACKAGE=1

    fi


    if [ -z "$V2RAY_GEOIP_PKG" ]; then

        _mos_error "缺少组件：v2ray-geoip"

        MISSING_PACKAGE=1

    fi


    if [ -z "$V2RAY_GEOSITE_PKG" ]; then

        _mos_error "缺少组件：v2ray-geosite"

        MISSING_PACKAGE=1

    fi


    if [ -z "$MOSDNS_MAIN_PKG" ]; then

        _mos_error "缺少组件：mosdns"

        MISSING_PACKAGE=1

    fi


    if [ -z "$MOSDNS_LUCI_PKG" ]; then

        _mos_error "缺少组件：luci-app-mosdns"

        MISSING_PACKAGE=1

    fi


    if [ -z "$MOSDNS_I18N_PKG" ]; then

        _mos_error "缺少组件：luci-i18n-mosdns-zh-cn"

        MISSING_PACKAGE=1

    fi


    if [ "$MISSING_PACKAGE" -ne 0 ]; then

        return 1

    fi


    _mos_ok "已识别全部 6 个 MosDNS 组件"


    printf "\n"

    _mos_info "v2dat        : $(basename "$V2DAT_PKG")"

    _mos_info "GeoIP        : $(basename "$V2RAY_GEOIP_PKG")"

    _mos_info "GeoSite      : $(basename "$V2RAY_GEOSITE_PKG")"

    _mos_info "MosDNS       : $(basename "$MOSDNS_MAIN_PKG")"

    _mos_info "LuCI         : $(basename "$MOSDNS_LUCI_PKG")"

    _mos_info "中文语言包   : $(basename "$MOSDNS_I18N_PKG")"


    return 0
}


# ============================================================
# 检查软件包是否已安装
# ============================================================

check_mosdns_package_installed()
{
    PACKAGE_NAME="$1"


    case "$MOSDNS_PKG_MANAGER" in

        apk)

            apk info -e \
                "$PACKAGE_NAME" \
                >/dev/null 2>&1

            return $?

            ;;


        opkg)

            opkg status \
                "$PACKAGE_NAME" \
                2>/dev/null |
                grep -q 'Status:.*installed'

            return $?

            ;;

    esac


    return 1
}


# ============================================================
# 安装单个软件包
# ============================================================

install_single_mosdns_package()
{
    PACKAGE_NAME="$1"
    PACKAGE_FILE="$2"
    INDEX="$3"
    TOTAL="$4"


    rm -f "$MOSDNS_INSTALL_LOG"


    printf "\n"

    _mos_info "[$INDEX/$TOTAL] 正在安装：$PACKAGE_NAME"


    case "$MOSDNS_PKG_MANAGER" in

        apk)

            apk add \
                --allow-untrusted \
                "$PACKAGE_FILE" \
                > "$MOSDNS_INSTALL_LOG" 2>&1

            RESULT=$?

            ;;


        opkg)

            opkg install \
                --force-downgrade \
                "$PACKAGE_FILE" \
                > "$MOSDNS_INSTALL_LOG" 2>&1

            RESULT=$?

            ;;


        *)

            _mos_error "未知包管理器"

            return 1

            ;;

    esac


    if [ "$RESULT" -ne 0 ]; then

        _mos_error "$PACKAGE_NAME 安装失败"


        if [ -s "$MOSDNS_INSTALL_LOG" ]; then

            printf "\n"

            printf "========== %s INSTALL LOG ==========\n" \
                "$PACKAGE_NAME"

            cat "$MOSDNS_INSTALL_LOG"

            printf "=====================================\n"

        fi


        return 1

    fi


    if ! check_mosdns_package_installed \
        "$PACKAGE_NAME"
    then

        _mos_error "$PACKAGE_NAME 安装后验证失败"


        if [ -s "$MOSDNS_INSTALL_LOG" ]; then

            printf "\n"

            cat "$MOSDNS_INSTALL_LOG"

        fi


        return 1

    fi


    _mos_ok "$PACKAGE_NAME 安装成功"


    return 0
}


# ============================================================
# 按依赖顺序安装全部组件
# ============================================================

install_mosdns_packages()
{
    TOTAL=6


    install_single_mosdns_package \
        "v2dat" \
        "$V2DAT_PKG" \
        "1" \
        "$TOTAL" ||
        return 1


    install_single_mosdns_package \
        "v2ray-geoip" \
        "$V2RAY_GEOIP_PKG" \
        "2" \
        "$TOTAL" ||
        return 1


    install_single_mosdns_package \
        "v2ray-geosite" \
        "$V2RAY_GEOSITE_PKG" \
        "3" \
        "$TOTAL" ||
        return 1


    install_single_mosdns_package \
        "mosdns" \
        "$MOSDNS_MAIN_PKG" \
        "4" \
        "$TOTAL" ||
        return 1


    install_single_mosdns_package \
        "luci-app-mosdns" \
        "$MOSDNS_LUCI_PKG" \
        "5" \
        "$TOTAL" ||
        return 1


    install_single_mosdns_package \
        "luci-i18n-mosdns-zh-cn" \
        "$MOSDNS_I18N_PKG" \
        "6" \
        "$TOTAL" ||
        return 1


    return 0
}


# ============================================================
# 检测 MosDNS 服务运行状态
# ============================================================

detect_existing_mosdns_service()
{
    MOSDNS_WAS_RUNNING=0


    if [ -x /etc/init.d/mosdns ]; then

        if /etc/init.d/mosdns status \
            >/dev/null 2>&1
        then

            MOSDNS_WAS_RUNNING=1

        fi

    fi


    return 0
}


# ============================================================
# 停止 MosDNS
# ============================================================

stop_mosdns_service()
{
    if [ -x /etc/init.d/mosdns ]; then

        _mos_info "正在停止现有 MosDNS 服务..."

        /etc/init.d/mosdns stop \
            >/dev/null 2>&1

    fi


    return 0
}


# ============================================================
# 启动 MosDNS
# ============================================================

start_mosdns_service()
{
    if [ ! -x /etc/init.d/mosdns ]; then

        _mos_error "没有找到 MosDNS 服务脚本"

        return 1

    fi


    _mos_info "正在启动 MosDNS..."


    /etc/init.d/mosdns start \
        >/dev/null 2>&1


    sleep 1


    if /etc/init.d/mosdns status \
        >/dev/null 2>&1
    then

        _mos_ok "MosDNS 服务已启动"

        return 0

    fi


    # 某些固件的 init.d status 返回值并不可靠，
    # 因此只要二进制与软件包存在，也不直接判安装失败。

    if command -v mosdns >/dev/null 2>&1 &&
       check_mosdns_package_installed "mosdns"
    then

        _mos_warn "MosDNS 已安装，但服务状态暂时无法确认"

        return 0

    fi


    _mos_error "MosDNS 服务启动失败"

    return 1
}


# ============================================================
# 清理 LuCI 缓存
# ============================================================

reload_mosdns_luci()
{
    _mos_info "正在刷新 LuCI..."


    rm -rf /tmp/luci-* \
        >/dev/null 2>&1


    if [ -x /etc/init.d/uhttpd ]; then

        /etc/init.d/uhttpd reload \
            >/dev/null 2>&1

    fi


    return 0
}


# ============================================================
# 获取 MosDNS 版本
# ============================================================

get_mosdns_version()
{
    MOSDNS_VERSION=""


    if ! command -v mosdns >/dev/null 2>&1; then

        return 1

    fi


    MOSDNS_VERSION="$(
        mosdns version \
            2>/dev/null |
        head -n 1
    )"


    if [ -z "$MOSDNS_VERSION" ]; then

        MOSDNS_VERSION="$(
            mosdns -v \
                2>/dev/null |
            head -n 1
        )"

    fi


    [ -n "$MOSDNS_VERSION" ]
}


# ============================================================
# 最终验证
# ============================================================

verify_mosdns_installation()
{
    printf "\n"

    _mos_info "正在进行 MosDNS 最终验证..."


    VERIFY_FAILED=0


    for PACKAGE_NAME in \
        v2dat \
        v2ray-geoip \
        v2ray-geosite \
        mosdns \
        luci-app-mosdns \
        luci-i18n-mosdns-zh-cn
    do

        if check_mosdns_package_installed \
            "$PACKAGE_NAME"
        then

            _mos_ok "$PACKAGE_NAME"

        else

            _mos_error "$PACKAGE_NAME 未正确安装"

            VERIFY_FAILED=1

        fi

    done


    if ! command -v mosdns >/dev/null 2>&1; then

        _mos_error "没有检测到 MosDNS 可执行文件"

        VERIFY_FAILED=1

    else

        _mos_ok "MosDNS 可执行文件正常"

    fi


    [ "$VERIFY_FAILED" -eq 0 ]
}


# ============================================================
# 主安装函数
# ============================================================

install_mosdns()
{
    printf "\n"

    printf "======================================\n"
    printf "          MosDNS Installer\n"
    printf "======================================\n"

    printf "\n"


    # ========================================================
    # Root
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _mos_error "请使用 root 用户运行"

        return 1

    fi


    # ========================================================
    # 基础环境
    # ========================================================

    if ! check_mosdns_runtime; then

        return 1

    fi


    # ========================================================
    # OpenWrt
    # ========================================================

    if ! detect_mosdns_openwrt; then

        return 1

    fi


    # ========================================================
    # CPU
    # ========================================================

    detect_mosdns_cpu


    # ========================================================
    # 包管理器
    # ========================================================

    if ! detect_mosdns_package_manager; then

        return 1

    fi


    # ========================================================
    # 精确架构
    # ========================================================

    if ! detect_mosdns_arch; then

        return 1

    fi


    # ========================================================
    # 架构支持
    # ========================================================

    if ! check_mosdns_arch_supported; then

        return 1

    fi


    # ========================================================
    # 存储空间
    # ========================================================

    if ! check_mosdns_disk_space; then

        return 1

    fi


    # ========================================================
    # 构造 Release 下载地址
    # ========================================================

    cleanup_mosdns_all


    mkdir -p "$MOSDNS_TMP_DIR" \
        >/dev/null 2>&1


    prepare_mosdns_download_info


    printf "\n"


    trap 'interrupt_mosdns' INT TERM


    # ========================================================
    # 智能下载
    # ========================================================

    if ! smart_download_mosdns \
        "$MOSDNS_BASE_URL" \
        "$MOSDNS_ARCHIVE_FILE"
    then

        printf "\n"

        _mos_error "MosDNS 下载失败"

        _mos_error "所有 GitHub 下载线路均不可用"


        if [ -s "$MOSDNS_DOWNLOAD_LOG" ]; then

            printf "\n"

            printf "========== DOWNLOAD LOG ==========\n"

            tail -n 30 "$MOSDNS_DOWNLOAD_LOG"

            printf "==================================\n"

        fi


        cleanup_mosdns_temp

        trap - INT TERM

        return 1

    fi


    _mos_ok "MosDNS 安装包下载完成"


    ARCHIVE_SIZE="$(
        wc -c < "$MOSDNS_ARCHIVE_FILE" 2>/dev/null
    )"


    ARCHIVE_MB="$(
        awk \
            -v size="$ARCHIVE_SIZE" '
            BEGIN {

                if (size > 0) {
                    printf "%.2f", size / 1024 / 1024
                } else {
                    printf "0.00"
                }

            }
        '
    )"


    _mos_info "File Size        : ${ARCHIVE_MB} MB"


    printf "\n"


    # ========================================================
    # 解压
    # ========================================================

    if ! extract_mosdns_archive; then

        cleanup_mosdns_temp

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 定位所有安装包
    # ========================================================

    if ! locate_mosdns_packages; then

        _mos_error "Release 压缩包内容不完整"

        cleanup_mosdns_temp

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 检测旧服务状态
    # ========================================================

    detect_existing_mosdns_service


    # ========================================================
    # 停止 MosDNS
    # ========================================================

    stop_mosdns_service


    # ========================================================
    # 逐个安装
    # ========================================================

    printf "\n"

    _mos_info "开始安装 MosDNS 组件..."


    if ! install_mosdns_packages; then

        printf "\n"

        _mos_error "MosDNS 组件安装失败"


        if [ "$MOSDNS_WAS_RUNNING" -eq 1 ] &&
           [ -x /etc/init.d/mosdns ]
        then

            _mos_info "正在恢复原 MosDNS 服务..."

            /etc/init.d/mosdns start \
                >/dev/null 2>&1

        fi


        cleanup_mosdns_temp

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 最终验证
    # ========================================================

    if ! verify_mosdns_installation; then

        _mos_error "MosDNS 最终验证失败"


        cleanup_mosdns_temp

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # LuCI
    # ========================================================

    reload_mosdns_luci


    # ========================================================
    # 启动服务
    # ========================================================

    start_mosdns_service


    # ========================================================
    # 获取版本
    # ========================================================

    get_mosdns_version


    # ========================================================
    # 清理
    # ========================================================

    cleanup_mosdns_temp

    cleanup_mosdns_logs


    trap - INT TERM


    # ========================================================
    # 完成
    # ========================================================

    printf "\n"

    printf "======================================\n"
    printf "          MosDNS Installed\n"
    printf "======================================\n"

    printf "\n"


    _mos_ok "MosDNS 安装完成"


    _mos_info "CPU      : $MOSDNS_CPU_ARCH"

    _mos_info "Arch     : $MOSDNS_ARCH"

    _mos_info "SDK      : $MOSDNS_SDK"

    _mos_info "Package  : $MOSDNS_PKG_EXT"


    if [ -n "$MOSDNS_VERSION" ]; then

        _mos_info "Version  : $MOSDNS_VERSION"

    fi


    printf "\n"

    printf "LuCI：服务 → MosDNS\n"

    printf "\n"


    return 0
}

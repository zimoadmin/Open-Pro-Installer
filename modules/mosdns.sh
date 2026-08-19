#!/bin/sh

# ============================================================
# Open-Pro-Installer
# MosDNS Smart Installer
#
# 功能：
# 1. 自动检测 OpenWrt / OPKG / APK / 精确架构
# 2. 自动选择 MosDNS 官方 24.10 / 25.12 Release 包
# 3. GH01-GH06 + DIRECT 并行真实测速并自动切线
# 4. 下载后验证 tar.gz，自动解压并定位 6 个组件
# 5. 按依赖顺序逐个安装并逐包验证
# 6. 兼容 GL.iNet / 旧 OPKG 长文件名 Illegal file name
# 7. 自动验证 MosDNS / LuCI / 服务
# 8. 自动修复旧版 rpcd 无法加载 /usr/share/rpcd/ucode/luci.mosdns
# 9. 旧 rpcd 自动创建 /usr/libexec/rpcd/luci.mosdns 兼容桥
# 10. 自动验证 ubus 对象 luci.mosdns
# 11. 自动归一化 aarch64_cortex-a53_neon-vfpv4 等 Release 架构
# 12. GitHub Release API 自动匹配真实 tar.gz Asset，避免 404
# 13. 自动检测并从当前软件源补齐 ucode-mod-fs / uci / ubus
# 14. ucode 模块缺失时阻止数据库更新假启动/无限转圈
# 15. GitHub API 失败时自动改用普通 Release 页面
# 16. 自动验证 RPC start_update / get_update_log 方法
# 17. 正常环境检测信息静默显示，仅保留必要提示
#
# BusyBox / OpenWrt /bin/sh Compatible
# ============================================================

MOSDNS_TMP_DIR="/tmp/openpro_mosdns"
MOSDNS_INSTALL_LOG="/tmp/openpro_mosdns_install.log"
MOSDNS_DOWNLOAD_LOG="/tmp/openpro_mosdns_download.log"
MOSDNS_ROUTE_FILE="/tmp/openpro_mosdns_routes"
MOSDNS_SORTED_FILE="/tmp/openpro_mosdns_routes.sorted"
MOSDNS_TEST_DIR="/tmp/openpro_mosdns_speedtest.d"
MOSDNS_RPC_COMPAT="/usr/libexec/rpcd/luci.mosdns"
MOSDNS_RELEASE_JSON="/tmp/openpro_mosdns_release.json"
MOSDNS_RELEASE_HTML="/tmp/openpro_mosdns_release.html"
MOSDNS_ASSET_LIST="/tmp/openpro_mosdns_assets.list"
MOSDNS_UCODE_LOG="/tmp/openpro_mosdns_ucode.log"

MOSDNS_ARCHIVE_FILE=""
MOSDNS_ARCHIVE_NAME=""
MOSDNS_BASE_URL=""
MOSDNS_CPU_ARCH=""
MOSDNS_ARCH=""
MOSDNS_ARCH_RAW=""
MOSDNS_PKG_MANAGER=""
MOSDNS_PKG_EXT=""
MOSDNS_SDK=""
MOSDNS_VERSION=""
MOSDNS_WAS_RUNNING=0

V2DAT_PKG=""
V2RAY_GEOIP_PKG=""
V2RAY_GEOSITE_PKG=""
MOSDNS_MAIN_PKG=""
MOSDNS_LUCI_PKG=""
MOSDNS_I18N_PKG=""

MOSDNS_TEST_CONNECT_TIMEOUT=4
MOSDNS_TEST_MAX_TIME=6
MOSDNS_SCORE_FILE_KB=10240

MOSDNS_DOWNLOAD_NODES="
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
GH04|https://cdn.akaere.online/
GH05|https://github.mxw.qzz.io/
GH06|https://gh.07150721.xyz/
DIRECT|
"

_mos_info() {
    if command -v info >/dev/null 2>&1; then info "$*"; else printf '\033[1;92m[INFO]\033[0m %s\n' "$*"; fi
}
_mos_warn() {
    if command -v warning >/dev/null 2>&1; then warning "$*"; elif command -v warn >/dev/null 2>&1; then warn "$*"; else printf '\033[1;93m[WARN]\033[0m %s\n' "$*"; fi
}
_mos_error() {
    if command -v error >/dev/null 2>&1; then error "$*"; else printf '\033[1;91m[ERROR]\033[0m %s\n' "$*"; fi
}
_mos_ok() { printf '\033[1;92m[OK]\033[0m %s\n' "$*"; }

cleanup_mosdns_safe_packages() {
    rm -f /tmp/mos1.ipk /tmp/mos2.ipk /tmp/mos3.ipk /tmp/mos4.ipk /tmp/mos5.ipk /tmp/mos6.ipk 2>/dev/null
}
cleanup_mosdns_temp() {
    rm -rf "$MOSDNS_TMP_DIR" "$MOSDNS_TEST_DIR" 2>/dev/null
    rm -f "$MOSDNS_ROUTE_FILE" "$MOSDNS_SORTED_FILE" "$MOSDNS_RELEASE_JSON" "$MOSDNS_RELEASE_HTML" "$MOSDNS_ASSET_LIST" 2>/dev/null
    cleanup_mosdns_safe_packages
}
cleanup_mosdns_logs() {
    rm -f "$MOSDNS_INSTALL_LOG" "$MOSDNS_DOWNLOAD_LOG" "$MOSDNS_UCODE_LOG" 2>/dev/null
}
cleanup_mosdns_all() {
    cleanup_mosdns_temp
    cleanup_mosdns_logs
}

interrupt_mosdns() {
    printf '\n'
    _mos_warn "MosDNS 安装被中断"
    cleanup_mosdns_safe_packages
    if [ "$MOSDNS_WAS_RUNNING" -eq 1 ] && [ -x /etc/init.d/mosdns ]; then
        /etc/init.d/mosdns start >/dev/null 2>&1
    fi
    cleanup_mosdns_all
    trap - INT TERM
    return 130
}

check_mosdns_runtime() {
    MISSING=""
    for CMD in awk sed grep cut sort head tail find tar gzip df wc curl cp basename mkdir chmod cat tr; do
        command -v "$CMD" >/dev/null 2>&1 || MISSING="$MISSING $CMD"
    done
    if [ -n "$MISSING" ]; then
        _mos_error "系统缺少必要命令:$MISSING"
        return 1
    fi
    return 0
}

detect_mosdns_openwrt() {
    [ -f /etc/openwrt_release ] || {
        _mos_error "当前系统不是受支持的 OpenWrt"
        return 1
    }

    . /etc/openwrt_release

    return 0
}

detect_mosdns_cpu() {
    MOSDNS_CPU_ARCH="$(uname -m 2>/dev/null)"
    [ -n "$MOSDNS_CPU_ARCH" ] || MOSDNS_CPU_ARCH="unknown"
}

detect_mosdns_package_manager() {
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

    return 0
}

normalize_mosdns_arch() {
    MOSDNS_ARCH_RAW="$MOSDNS_ARCH"

    case "$MOSDNS_ARCH" in
        aarch64_cortex-a53|aarch64_cortex-a53_*)
            MOSDNS_ARCH="aarch64_cortex-a53"
            ;;
        aarch64_cortex-a72|aarch64_cortex-a72_*)
            MOSDNS_ARCH="aarch64_cortex-a72"
            ;;
        aarch64_cortex-a76|aarch64_cortex-a76_*)
            MOSDNS_ARCH="aarch64_cortex-a76"
            ;;
        aarch64_generic|aarch64_generic_*)
            MOSDNS_ARCH="aarch64_generic"
            ;;
        aarch64|arm64)
            MOSDNS_ARCH="aarch64_generic"
            ;;
        *)
            ;;
    esac
}

detect_mosdns_arch() {
    MOSDNS_ARCH=""

    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        MOSDNS_ARCH="${DISTRIB_ARCH:-}"
    fi

    if [ -z "$MOSDNS_ARCH" ] && command -v opkg >/dev/null 2>&1; then
        MOSDNS_ARCH="$(
            opkg print-architecture 2>/dev/null |
            awk '$1=="arch" && $2!="all" && $2!="noarch" {
                if ($3>p) { p=$3; a=$2 }
            } END { print a }'
        )"
    fi

    if [ -z "$MOSDNS_ARCH" ] && command -v apk >/dev/null 2>&1; then
        MOSDNS_ARCH="$(apk --print-arch 2>/dev/null | head -n 1)"
    fi

    [ -n "$MOSDNS_ARCH" ] || {
        _mos_error "无法识别 OpenWrt 软件包架构"
        return 1
    }

    normalize_mosdns_arch
}

check_mosdns_disk_space() {
    FREE_KB="$(df -k /usr 2>/dev/null | awk 'END{print $4}')"

    case "$FREE_KB" in
        ''|*[!0-9]*)
            FREE_KB=0
            ;;
    esac

    FREE_MB=$((FREE_KB / 1024))

    if [ "$FREE_MB" -lt 35 ]; then
        _mos_error "可用存储空间不足，建议至少保留 35 MB"
        return 1
    fi

    return 0
}

prepare_mosdns_download_info() {
    mkdir -p "$MOSDNS_TMP_DIR" || return 1

    rm -f \
        "$MOSDNS_RELEASE_JSON" \
        "$MOSDNS_RELEASE_HTML" \
        "$MOSDNS_ASSET_LIST" \
        2>/dev/null

    EXPECTED_NAME="${MOSDNS_ARCH}-${MOSDNS_SDK}.tar.gz"
    MOSDNS_BASE_URL=""


    # ========================================================
    # 第一层：GitHub API DIRECT
    # ========================================================

    if curl -4 -fLsS \
        --connect-timeout 8 \
        --max-time 30 \
        -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: Open-Pro-Installer' \
        'https://api.github.com/repos/sbwml/luci-app-mosdns/releases/latest' \
        -o "$MOSDNS_RELEASE_JSON" \
        >/dev/null 2>&1
    then
        if command -v jsonfilter >/dev/null 2>&1; then
            jsonfilter \
                -i "$MOSDNS_RELEASE_JSON" \
                -e '@.assets[*].browser_download_url' \
                2>/dev/null \
                > "$MOSDNS_ASSET_LIST"
        else
            tr ',' '\n' < "$MOSDNS_RELEASE_JSON" |
                sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' \
                > "$MOSDNS_ASSET_LIST"
        fi
    else
        _mos_warn "GitHub API 不可用或触发限流，切换普通 Release 页面..."
        rm -f "$MOSDNS_RELEASE_JSON"
    fi

    # ========================================================
    # 第二层：普通 GitHub Release 页面兜底
    # 不消耗 REST API 额度
    # ========================================================

    if [ ! -s "$MOSDNS_ASSET_LIST" ]; then
        LATEST_PAGE="https://github.com/sbwml/luci-app-mosdns/releases/latest"

        EFFECTIVE_URL="$(
            curl \
                -4 \
                -L \
                -sS \
                --connect-timeout 8 \
                --max-time 30 \
                -o /dev/null \
                -w '%{url_effective}' \
                "$LATEST_PAGE" \
                2>/dev/null
        )"

        RELEASE_TAG="$(
            printf '%s\n' "$EFFECTIVE_URL" |
            sed -n 's#^.*/releases/tag/\([^/?#]*\).*$#\1#p'
        )"

        if [ -n "$RELEASE_TAG" ]; then
            EXPANDED_URL="https://github.com/sbwml/luci-app-mosdns/releases/expanded_assets/${RELEASE_TAG}"

            if curl -4 -fLsS \
                --connect-timeout 8 \
                --max-time 30 \
                -H 'User-Agent: Open-Pro-Installer' \
                "$EXPANDED_URL" \
                -o "$MOSDNS_RELEASE_HTML" \
                >/dev/null 2>&1
            then
                grep -o \
                    '/sbwml/luci-app-mosdns/releases/download/[^"]*' \
                    "$MOSDNS_RELEASE_HTML" \
                    2>/dev/null |
                    sed 's/&amp;/\&/g' |
                    while IFS= read -r ASSET_PATH
                    do
                        printf 'https://github.com%s\n' "$ASSET_PATH"
                    done \
                    > "$MOSDNS_ASSET_LIST"
            fi
        fi
    fi

    # ========================================================
    # 精确匹配真实 Asset
    # ========================================================

    if [ -s "$MOSDNS_ASSET_LIST" ]; then
        MOSDNS_BASE_URL="$(
            awk -v name="$EXPECTED_NAME" '
                {
                    n=$0
                    sub(/^.*\//, "", n)
                    if (n == name) {
                        print $0
                        exit
                    }
                }
            ' "$MOSDNS_ASSET_LIST"
        )"

        if [ -z "$MOSDNS_BASE_URL" ]; then
            MOSDNS_BASE_URL="$(
                grep "/${MOSDNS_ARCH}[^/]*-${MOSDNS_SDK}\.tar\.gz$" \
                    "$MOSDNS_ASSET_LIST" |
                head -n 1
            )"
        fi

        if [ -z "$MOSDNS_BASE_URL" ] &&
           [ -n "$MOSDNS_ARCH_RAW" ] &&
           [ "$MOSDNS_ARCH_RAW" != "$MOSDNS_ARCH" ]
        then
            MOSDNS_BASE_URL="$(
                grep "/${MOSDNS_ARCH_RAW}[^/]*-${MOSDNS_SDK}\.tar\.gz$" \
                    "$MOSDNS_ASSET_LIST" |
                head -n 1
            )"
        fi
    fi

    # ========================================================
    # 最终兜底：标准 latest/download
    # ========================================================

    if [ -z "$MOSDNS_BASE_URL" ]; then
        MOSDNS_ARCHIVE_NAME="$EXPECTED_NAME"
        MOSDNS_BASE_URL="https://github.com/sbwml/luci-app-mosdns/releases/latest/download/${MOSDNS_ARCHIVE_NAME}"
        _mos_warn "未解析到真实 Asset，尝试标准地址：$MOSDNS_ARCHIVE_NAME"
    else
        MOSDNS_ARCHIVE_NAME="$(basename "$MOSDNS_BASE_URL")"
    fi

    MOSDNS_ARCHIVE_FILE="${MOSDNS_TMP_DIR}/${MOSDNS_ARCHIVE_NAME}"


    return 0
}

build_mosdns_url() {
    if [ -z "$1" ]; then printf '%s' "$2"; else printf '%s%s' "$1" "$2"; fi
}
mosdns_seconds_to_ms() {
    awk -v t="$1" 'BEGIN{if(t==""||t!~/^[0-9.]+$/){print 999999}else{printf "%d",t*1000}}'
}
mosdns_speed_to_mb() {
    awk -v s="$1" 'BEGIN{if(s==""||s<=0){printf "0.00"}else{printf "%.2f",s/1024/1024}}'
}
mosdns_calculate_score() {
    awk -v t="$1" -v s="$2" -v kb="$MOSDNS_SCORE_FILE_KB" 'BEGIN{if(s<=0){print 999999999;exit} speed_kb=s/1024; printf "%d",t+(kb/speed_kb)*1000}'
}
mosdns_test_is_error_page() {
    [ -s "$1" ] || return 1
    head -c 1024 "$1" 2>/dev/null | grep -Eqi '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
}

test_mosdns_route() {
    TEST_URL="$1"; TEST_FILE="$2"
    rm -f "$TEST_FILE"
    CURL_DATA="$(curl -4 -L -sS --connect-timeout "$MOSDNS_TEST_CONNECT_TIMEOUT" --max-time "$MOSDNS_TEST_MAX_TIME" -o "$TEST_FILE" -w '%{http_code}|%{time_starttransfer}|%{speed_download}|%{size_download}' "$TEST_URL" 2>/dev/null)"
    CURL_CODE=$?
    HTTP_CODE="$(printf '%s' "$CURL_DATA" | cut -d '|' -f1)"
    TTFB="$(printf '%s' "$CURL_DATA" | cut -d '|' -f2)"
    SPEED_BPS="$(printf '%s' "$CURL_DATA" | cut -d '|' -f3)"
    SIZE_DOWN="$(printf '%s' "$CURL_DATA" | cut -d '|' -f4)"
    case "$CURL_CODE" in 0|28) ;; *) rm -f "$TEST_FILE"; return 1;; esac
    case "$HTTP_CODE" in 200|206) ;; *) rm -f "$TEST_FILE"; return 1;; esac
    RECEIVED_BYTES="$(awk -v n="$SIZE_DOWN" 'BEGIN{if(n+0>0)printf "%d",n;else print 0}')"
    [ "$RECEIVED_BYTES" -ge 4096 ] || { rm -f "$TEST_FILE"; return 1; }
    mosdns_test_is_error_page "$TEST_FILE" && { rm -f "$TEST_FILE"; return 1; }
    TTFB_MS="$(mosdns_seconds_to_ms "$TTFB")"
    SPEED_INT="$(awk -v s="$SPEED_BPS" 'BEGIN{if(s>0)printf "%d",s;else print 0}')"
    [ "$SPEED_INT" -gt 0 ] || { rm -f "$TEST_FILE"; return 1; }
    SCORE="$(mosdns_calculate_score "$TTFB_MS" "$SPEED_INT")"
    rm -f "$TEST_FILE"
    printf '%s|%s|%s|%s' "$TTFB_MS" "$SPEED_INT" "$RECEIVED_BYTES" "$SCORE"
}

test_mosdns_route_background() {
    NODE_NAME="$1"; NODE_PREFIX="$2"; ORIGINAL_URL="$3"; RESULT_FILE="$4"; TEST_FILE="$5"
    TEST_URL="$(build_mosdns_url "$NODE_PREFIX" "$ORIGINAL_URL")"
    TEST_DATA="$(test_mosdns_route "$TEST_URL" "$TEST_FILE")"
    if [ $? -ne 0 ] || [ -z "$TEST_DATA" ]; then
        printf '%s|FAIL\n' "$NODE_NAME" > "$RESULT_FILE"
        return 1
    fi
    TTFB_MS="$(printf '%s' "$TEST_DATA" | cut -d '|' -f1)"
    SPEED_BPS="$(printf '%s' "$TEST_DATA" | cut -d '|' -f2)"
    RECEIVED="$(printf '%s' "$TEST_DATA" | cut -d '|' -f3)"
    SCORE="$(printf '%s' "$TEST_DATA" | cut -d '|' -f4)"
    printf '%s|OK|%s|%s|%s|%s|%s|%s\n' "$NODE_NAME" "$NODE_PREFIX" "$TEST_URL" "$TTFB_MS" "$SPEED_BPS" "$RECEIVED" "$SCORE" > "$RESULT_FILE"
}

prepare_mosdns_routes() {
    ORIGINAL_URL="$1"
    rm -f "$MOSDNS_ROUTE_FILE" "$MOSDNS_SORTED_FILE"
    rm -rf "$MOSDNS_TEST_DIR"; mkdir -p "$MOSDNS_TEST_DIR" || return 1
    printf '\n'; _mos_info "正在并行测试 MosDNS 下载线路..."; printf '\n'
    for NODE_NAME in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT; do
        NODE_PREFIX="$(printf '%s\n' "$MOSDNS_DOWNLOAD_NODES" | awk -F '|' -v n="$NODE_NAME" '$1==n{print $2;exit}')"
        test_mosdns_route_background "$NODE_NAME" "$NODE_PREFIX" "$ORIGINAL_URL" "$MOSDNS_TEST_DIR/result_${NODE_NAME}" "$MOSDNS_TEST_DIR/download_${NODE_NAME}" &
    done
    wait
    printf '%-8s %-12s %-14s %s\n' "线路" "首包" "下载速度" "状态"
    printf '%-8s %-12s %-14s %s\n' "--------" "------------" "--------------" "------"
    for NODE_NAME in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT; do
        RESULT_FILE="$MOSDNS_TEST_DIR/result_${NODE_NAME}"
        if [ ! -s "$RESULT_FILE" ] || [ "$(cut -d '|' -f2 "$RESULT_FILE")" != "OK" ]; then
            printf '%-8s %-12s %-14s \033[1;91m%s\033[0m\n' "$NODE_NAME" "----" "----" "不可用"
            continue
        fi
        NODE_PREFIX="$(cut -d '|' -f3 "$RESULT_FILE")"
        TEST_URL="$(cut -d '|' -f4 "$RESULT_FILE")"
        TTFB_MS="$(cut -d '|' -f5 "$RESULT_FILE")"
        SPEED_BPS="$(cut -d '|' -f6 "$RESULT_FILE")"
        SCORE="$(cut -d '|' -f8 "$RESULT_FILE")"
        SPEED_MB="$(mosdns_speed_to_mb "$SPEED_BPS")"
        printf '%-8s %-12s %-14s \033[1;92m%s\033[0m\n' "$NODE_NAME" "${TTFB_MS} ms" "${SPEED_MB} MB/s" "可用"
        printf '%s|%s|%s|%s|%s|%s\n' "$SCORE" "$NODE_NAME" "$NODE_PREFIX" "$TEST_URL" "$TTFB_MS" "$SPEED_BPS" >> "$MOSDNS_ROUTE_FILE"
    done
    rm -rf "$MOSDNS_TEST_DIR"
    [ -s "$MOSDNS_ROUTE_FILE" ] || { _mos_warn "没有发现可用测速线路"; return 1; }
    sort -n -t '|' -k1,1 "$MOSDNS_ROUTE_FILE" > "$MOSDNS_SORTED_FILE" 2>/dev/null && mv "$MOSDNS_SORTED_FILE" "$MOSDNS_ROUTE_FILE"
    BEST_LINE="$(sed -n '1p' "$MOSDNS_ROUTE_FILE")"
    BEST_NAME="$(printf '%s' "$BEST_LINE" | cut -d '|' -f2)"
    BEST_TTFB="$(printf '%s' "$BEST_LINE" | cut -d '|' -f5)"
    BEST_SPEED="$(printf '%s' "$BEST_LINE" | cut -d '|' -f6)"
    printf '\n'; _mos_ok "最佳线路：$BEST_NAME"; _mos_info "首包时间：${BEST_TTFB} ms"; _mos_info "下载速度：$(mosdns_speed_to_mb "$BEST_SPEED") MB/s"; printf '\n'
}

verify_mosdns_archive() {
    FILE="$1"
    [ -s "$FILE" ] || return 1
    FILE_SIZE="$(wc -c < "$FILE" 2>/dev/null)"
    case "$FILE_SIZE" in ''|*[!0-9]*) FILE_SIZE=0;; esac
    [ "$FILE_SIZE" -ge 1048576 ] || return 1
    mosdns_test_is_error_page "$FILE" && return 1
    tar -tzf "$FILE" >/dev/null 2>&1
}

download_mosdns_from_url() {
    rm -f "$2" "$MOSDNS_DOWNLOAD_LOG"
    curl -4 -L -f -sS --connect-timeout 10 --max-time 300 --retry 1 --retry-delay 1 -o "$2" "$1" > "$MOSDNS_DOWNLOAD_LOG" 2>&1 || { rm -f "$2"; return 1; }
    verify_mosdns_archive "$2" || { rm -f "$2"; return 1; }
}

smart_download_mosdns() {
    ORIGINAL_URL="$1"; OUTPUT="$2"; DOWNLOAD_SUCCESS=0; DIRECT_TRIED=0
    prepare_mosdns_routes "$ORIGINAL_URL"
    if [ -s "$MOSDNS_ROUTE_FILE" ]; then
        while IFS='|' read -r ROUTE_SCORE ROUTE_NAME ROUTE_PREFIX ROUTE_URL ROUTE_TTFB ROUTE_SPEED; do
            [ -n "$ROUTE_NAME" ] && [ -n "$ROUTE_URL" ] || continue
            [ "$ROUTE_NAME" = "DIRECT" ] && DIRECT_TRIED=1
            _mos_info "正在使用线路：$ROUTE_NAME"
            _mos_info "测速速度：$(mosdns_speed_to_mb "$ROUTE_SPEED") MB/s"
            if download_mosdns_from_url "$ROUTE_URL" "$OUTPUT"; then
                _mos_ok "MosDNS 下载线路：$ROUTE_NAME"; DOWNLOAD_SUCCESS=1; break
            fi
            _mos_warn "$ROUTE_NAME 下载失败，切换下一线路..."
        done < "$MOSDNS_ROUTE_FILE"
    fi
    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] && [ "$DIRECT_TRIED" -ne 1 ]; then
        _mos_info "正在尝试 GitHub 官方直连..."
        download_mosdns_from_url "$ORIGINAL_URL" "$OUTPUT" && { _mos_ok "GitHub 官方直连下载成功"; DOWNLOAD_SUCCESS=1; }
    fi
    rm -f "$MOSDNS_ROUTE_FILE" "$MOSDNS_SORTED_FILE"
    [ "$DOWNLOAD_SUCCESS" -eq 1 ]
}

extract_mosdns_archive() {
    _mos_info "正在解压 MosDNS 安装包..."
    tar -zxf "$MOSDNS_ARCHIVE_FILE" -C "$MOSDNS_TMP_DIR" >/dev/null 2>&1 || { _mos_error "MosDNS 安装包解压失败"; return 1; }
    _mos_ok "MosDNS 安装包解压完成"
}

find_mosdns_package() {
    find "$MOSDNS_TMP_DIR" -type f -name "${1}*.${MOSDNS_PKG_EXT}" 2>/dev/null | head -n 1
}

locate_mosdns_packages() {
    _mos_info "正在识别 MosDNS 组件..."
    V2DAT_PKG="$(find_mosdns_package 'v2dat')"
    V2RAY_GEOIP_PKG="$(find_mosdns_package 'v2ray-geoip')"
    V2RAY_GEOSITE_PKG="$(find_mosdns_package 'v2ray-geosite')"
    MOSDNS_MAIN_PKG="$(find_mosdns_package 'mosdns')"
    MOSDNS_LUCI_PKG="$(find_mosdns_package 'luci-app-mosdns')"
    MOSDNS_I18N_PKG="$(find_mosdns_package 'luci-i18n-mosdns-zh-cn')"
    MISSING=0
    for P in V2DAT_PKG V2RAY_GEOIP_PKG V2RAY_GEOSITE_PKG MOSDNS_MAIN_PKG MOSDNS_LUCI_PKG MOSDNS_I18N_PKG; do
        eval "V=\${$P}"
        [ -n "$V" ] || MISSING=1
    done
    [ "$MISSING" -eq 0 ] || { _mos_error "Release 压缩包缺少必要组件"; return 1; }
    _mos_ok "已识别全部 6 个 MosDNS 组件"
    printf '\n'
}

check_mosdns_package_installed() {
    case "$MOSDNS_PKG_MANAGER" in
        apk) apk info -e "$1" >/dev/null 2>&1;;
        opkg) opkg status "$1" 2>/dev/null | grep -q 'Status:.*installed';;
        *) return 1;;
    esac
}


# ============================================================
# MosDNS 6 组件总进度条
# ============================================================

mosdns_install_progress() {
    CURRENT="$1"
    TOTAL="$2"
    PACKAGE_NAME="$3"

    WIDTH=30

    [ "$TOTAL" -gt 0 ] || TOTAL=1

    PERCENT=$((CURRENT * 100 / TOTAL))
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

    printf '\r\033[2K\033[1;92m[INFO]\033[0m 总体进度: [\033[1;92m%s\033[0m] %3d%% (%d/%d)  当前: %s' \
        "$BAR" \
        "$PERCENT" \
        "$CURRENT" \
        "$TOTAL" \
        "$PACKAGE_NAME"
}

install_single_mosdns_package() {
    PACKAGE_NAME="$1"
    PACKAGE_FILE="$2"
    INDEX="$3"
    TOTAL="$4"
    SAFE_PACKAGE_FILE=""

    rm -f "$MOSDNS_INSTALL_LOG"

    [ -f "$PACKAGE_FILE" ] || {
        printf '\n'
        _mos_error "安装文件不存在：$PACKAGE_NAME"
        return 1
    }

    case "$MOSDNS_PKG_MANAGER" in
        apk)
            apk add \
                --allow-untrusted \
                "$PACKAGE_FILE" \
                > "$MOSDNS_INSTALL_LOG" 2>&1

            RESULT=$?
            ;;

        opkg)
            SAFE_PACKAGE_FILE="/tmp/mos${INDEX}.ipk"

            rm -f "$SAFE_PACKAGE_FILE"

            cp "$PACKAGE_FILE" "$SAFE_PACKAGE_FILE" \
                >/dev/null 2>&1 || {
                    printf '\n'
                    _mos_error "无法创建 OPKG 临时安装文件"
                    return 1
                }

            [ -s "$SAFE_PACKAGE_FILE" ] || {
                rm -f "$SAFE_PACKAGE_FILE"
                printf '\n'
                _mos_error "OPKG 临时安装文件无效"
                return 1
            }

            opkg install \
                --force-downgrade \
                "$SAFE_PACKAGE_FILE" \
                > "$MOSDNS_INSTALL_LOG" 2>&1

            RESULT=$?

            rm -f "$SAFE_PACKAGE_FILE"
            ;;

        *)
            printf '\n'
            _mos_error "未知包管理器：$MOSDNS_PKG_MANAGER"
            return 1
            ;;
    esac

    if [ "$RESULT" -ne 0 ]; then
        printf '\n'
        _mos_error "$PACKAGE_NAME 安装失败"

        if [ -s "$MOSDNS_INSTALL_LOG" ]; then
            printf '\n========== %s INSTALL LOG ==========\n' "$PACKAGE_NAME"
            cat "$MOSDNS_INSTALL_LOG"
            printf '=====================================\n'
        fi

        return 1
    fi

    if ! check_mosdns_package_installed "$PACKAGE_NAME"; then
        printf '\n'
        _mos_error "$PACKAGE_NAME 安装后验证失败"
        return 1
    fi

    return 0
}

install_mosdns_packages() {
    TOTAL=6
    CURRENT=0

    printf '\n'
    _mos_info "正在安装 MosDNS 组件（共 6 个）..."
    printf '\n'

    mosdns_install_progress "$CURRENT" "$TOTAL" "v2dat"

    install_single_mosdns_package \
        v2dat \
        "$V2DAT_PKG" \
        1 \
        "$TOTAL" || return 1

    CURRENT=1
    mosdns_install_progress "$CURRENT" "$TOTAL" "v2ray-geoip"

    install_single_mosdns_package \
        v2ray-geoip \
        "$V2RAY_GEOIP_PKG" \
        2 \
        "$TOTAL" || return 1

    CURRENT=2
    mosdns_install_progress "$CURRENT" "$TOTAL" "v2ray-geosite"

    install_single_mosdns_package \
        v2ray-geosite \
        "$V2RAY_GEOSITE_PKG" \
        3 \
        "$TOTAL" || return 1

    CURRENT=3
    mosdns_install_progress "$CURRENT" "$TOTAL" "mosdns"

    install_single_mosdns_package \
        mosdns \
        "$MOSDNS_MAIN_PKG" \
        4 \
        "$TOTAL" || return 1

    CURRENT=4
    mosdns_install_progress "$CURRENT" "$TOTAL" "luci-app-mosdns"

    install_single_mosdns_package \
        luci-app-mosdns \
        "$MOSDNS_LUCI_PKG" \
        5 \
        "$TOTAL" || return 1

    CURRENT=5
    mosdns_install_progress "$CURRENT" "$TOTAL" "luci-i18n-mosdns-zh-cn"

    install_single_mosdns_package \
        luci-i18n-mosdns-zh-cn \
        "$MOSDNS_I18N_PKG" \
        6 \
        "$TOTAL" || return 1

    CURRENT=6
    mosdns_install_progress "$CURRENT" "$TOTAL" "完成"

    printf '\n'
    _mos_ok "MosDNS 6 个组件安装完成"

    cleanup_mosdns_safe_packages

    return 0
}

detect_existing_mosdns_service() {
    MOSDNS_WAS_RUNNING=0
    [ -x /etc/init.d/mosdns ] && /etc/init.d/mosdns status >/dev/null 2>&1 && MOSDNS_WAS_RUNNING=1
}
stop_mosdns_service() {
    [ -x /etc/init.d/mosdns ] && { _mos_info "正在停止现有 MosDNS 服务..."; /etc/init.d/mosdns stop >/dev/null 2>&1; }
}
start_mosdns_service() {
    [ -x /etc/init.d/mosdns ] || { _mos_error "没有找到 MosDNS 服务脚本"; return 1; }
    _mos_info "正在启动 MosDNS..."
    /etc/init.d/mosdns start >/dev/null 2>&1
    sleep 1
    if /etc/init.d/mosdns status >/dev/null 2>&1; then _mos_ok "MosDNS 服务已启动"; return 0; fi
    if command -v mosdns >/dev/null 2>&1 && check_mosdns_package_installed mosdns; then _mos_warn "MosDNS 已安装，但服务状态暂时无法确认"; return 0; fi
    _mos_error "MosDNS 服务启动失败"; return 1
}

check_ucode_package_installed() {
    PACKAGE_NAME="$1"

    case "$MOSDNS_PKG_MANAGER" in
        opkg)
            opkg status "$PACKAGE_NAME" 2>/dev/null |
                grep -q 'Status:.*installed'
            ;;
        apk)
            apk info -e "$PACKAGE_NAME" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}


install_missing_mosdns_ucode_modules() {
    rm -f "$MOSDNS_UCODE_LOG"

    if check_mosdns_ucode_modules; then
        _mos_ok "ucode fs / uci / ubus 模块已完整"
        return 0
    fi

    _mos_warn "检测到 ucode fs / uci / ubus 模块缺失或不可用"
    _mos_info "正在尝试从当前系统软件源自动补齐..."

    case "$MOSDNS_PKG_MANAGER" in

        opkg)
            opkg update > "$MOSDNS_UCODE_LOG" 2>&1

            UPDATE_RESULT=$?

            if [ "$UPDATE_RESULT" -ne 0 ]; then
                _mos_warn "OPKG 软件索引更新返回异常，继续尝试安装"
            fi

            UCODE_INSTALL_FAILED=0

            for PKG in \
                ucode-mod-fs \
                ucode-mod-uci \
                ucode-mod-ubus
            do
                if check_ucode_package_installed "$PKG"; then
                    _mos_ok "$PKG 已安装"
                    continue
                fi

                if ! opkg list 2>/dev/null |
                    grep -q "^${PKG} "
                then
                    _mos_error "当前 OPKG 软件源没有找到：$PKG"
                    UCODE_INSTALL_FAILED=1
                    continue
                fi

                _mos_info "正在安装：$PKG"

                if opkg install "$PKG" \
                    >> "$MOSDNS_UCODE_LOG" 2>&1
                then
                    _mos_ok "$PKG 安装成功"
                else
                    _mos_error "$PKG 安装失败"
                    UCODE_INSTALL_FAILED=1
                fi
            done

            [ "$UCODE_INSTALL_FAILED" -eq 0 ] || {
                if [ -s "$MOSDNS_UCODE_LOG" ]; then
                    printf '\n========== UCODE INSTALL LOG ==========\n'
                    tail -n 60 "$MOSDNS_UCODE_LOG"
                    printf '=======================================\n'
                fi
                return 1
            }
            ;;

        apk)
            _mos_info "正在安装 ucode 扩展模块..."

            if ! apk add \
                ucode-mod-fs \
                ucode-mod-uci \
                ucode-mod-ubus \
                > "$MOSDNS_UCODE_LOG" 2>&1
            then
                _mos_error "APK ucode 扩展模块安装失败"

                [ -s "$MOSDNS_UCODE_LOG" ] && {
                    printf '\n========== UCODE INSTALL LOG ==========\n'
                    tail -n 60 "$MOSDNS_UCODE_LOG"
                    printf '=======================================\n'
                }

                return 1
            fi
            ;;

        *)
            _mos_error "未知包管理器，无法自动补齐 ucode 模块"
            return 1
            ;;
    esac

    # ========================================================
    # 真实 import 验证
    # ========================================================

    if check_mosdns_ucode_modules; then
        _mos_ok "ucode fs / uci / ubus 模块验证通过"
        return 0
    fi

    # 已安装但 import 仍失败时，OPKG 再尝试一次强制重装。
    if [ "$MOSDNS_PKG_MANAGER" = "opkg" ]; then
        _mos_warn "ucode 模块已安装但加载失败，尝试强制重装..."

        opkg install \
            --force-reinstall \
            ucode-mod-fs \
            ucode-mod-uci \
            ucode-mod-ubus \
            >> "$MOSDNS_UCODE_LOG" 2>&1 || true

        if check_mosdns_ucode_modules; then
            _mos_ok "ucode 模块强制重装后验证通过"
            return 0
        fi
    fi

    _mos_error "ucode fs / uci / ubus 模块仍无法正常加载"

    [ -s "$MOSDNS_UCODE_LOG" ] && {
        printf '\n========== UCODE INSTALL LOG ==========\n'
        tail -n 60 "$MOSDNS_UCODE_LOG"
        printf '=======================================\n'
    }

    return 1
}


check_mosdns_ucode_modules() {
    command -v ucode >/dev/null 2>&1 || return 1

    ucode -e '
        import { stat } from "fs";
        import { cursor } from "uci";
        import { connect } from "ubus";
    ' >/dev/null 2>&1
}

rpc_mosdns_exists() {
    command -v ubus >/dev/null 2>&1 || return 1
    ubus list 2>/dev/null | grep -qx 'luci.mosdns'
}


verify_mosdns_rpc_methods() {
    rpc_mosdns_exists || return 1

    RPC_INFO="$(
        ubus -v list luci.mosdns 2>/dev/null
    )"

    printf '%s\n' "$RPC_INFO" |
        grep -q '"start_update"' || return 1

    printf '%s\n' "$RPC_INFO" |
        grep -q '"get_update_log"' || return 1

    return 0
}

write_mosdns_rpc_compat() {
    mkdir -p /usr/libexec/rpcd || return 1
    cat > "$MOSDNS_RPC_COMPAT" <<'MOSDNS_RPC_EOF'
#!/bin/sh

json_escape() {
    awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\");gsub(/\"/,"\\\"");gsub(/\r/,"\\r");gsub(/\t/,"\\t");if(NR>1)printf "\\n";printf "%s",$0}'
}

json_reply_string() {
    KEY="$1"
    VALUE="$2"
    printf '{"%s":"' "$KEY"
    printf '%s' "$VALUE" | json_escape
    printf '"}\n'
}

json_reply_error() {
    printf '{"success":false,"error":"'
    printf '%s' "$1" | json_escape
    printf '"}\n'
}

get_logfile_path() {
    CONFIGFILE="$(uci -q get mosdns.config.configfile 2>/dev/null)"
    LOGFILE=""
    if [ -z "$CONFIGFILE" ] || [ "$CONFIGFILE" = "/var/etc/mosdns.json" ]; then
        LOGFILE="$(uci -q get mosdns.config.log_file 2>/dev/null)"
    elif [ -f "$CONFIGFILE" ]; then
        LOGFILE="$(sed -n 's/^[[:space:]]*file:[[:space:]]*//p' "$CONFIGFILE" | head -n 1 | sed 's/^["]//;s/["]$//')"
    fi
    [ -n "$LOGFILE" ] || LOGFILE="/var/log/mosdns.log"
    printf '%s' "$LOGFILE"
}

case "$1" in
    list)
        printf '%s\n' '{"flush_cache":{},"print_log":{},"clean_log":{},"get_version":{},"start_update":{},"get_update_log":{}}'
        exit 0
        ;;
    call)
        METHOD="$2"
        cat >/dev/null 2>&1
        case "$METHOD" in
            get_version)
                OUT="$(mosdns version 2>&1)"; RC=$?
                if [ "$RC" -eq 0 ]; then json_reply_string version "$OUT"; else json_reply_error "$OUT"; fi
                ;;
            flush_cache)
                PORT="$(uci -q get mosdns.config.listen_port_api 2>/dev/null)"
                [ -n "$PORT" ] || PORT="9091"
                OUT="$(curl -sS "http://127.0.0.1:${PORT}/plugins/lazy_cache/flush" 2>&1)"; RC=$?
                if [ "$RC" -eq 0 ]; then printf '%s\n' '{"success":true}'; else json_reply_error "$OUT"; fi
                ;;
            print_log)
                LOGFILE="$(get_logfile_path)"
                if [ -f "$LOGFILE" ]; then
                    printf '{"log":"'; cat "$LOGFILE" 2>/dev/null | json_escape; printf '"}\n'
                else
                    json_reply_error "Log file not accessible or does not exist."
                fi
                ;;
            clean_log)
                LOGFILE="$(get_logfile_path)"
                mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null
                if : > "$LOGFILE" 2>/dev/null; then printf '%s\n' '{"success":true}'; else json_reply_error "Failed to open log file for writing."; fi
                ;;
            start_update)
                if [ -e /var/lock/mosdns_update.lock ]; then
                    json_reply_error "Another update is already in progress."
                    exit 0
                fi

                if [ ! -f /usr/share/mosdns/mosdns.uc ]; then
                    json_reply_error "mosdns.uc not found."
                    exit 0
                fi

                if ! command -v ucode >/dev/null 2>&1; then
                    json_reply_error "ucode not found."
                    exit 0
                fi

                if ! ucode -e '
                    import { stat } from "fs";
                    import { cursor } from "uci";
                    import { connect } from "ubus";
                ' >/dev/null 2>&1
                then
                    json_reply_error "ucode modules fs/uci/ubus are missing. Please install the matching ucode modules first."
                    exit 0
                fi

                : > /var/log/mosdns_update.log 2>/dev/null

                ucode /usr/share/mosdns/mosdns.uc update \
                    > /var/log/mosdns_update.log 2>&1 </dev/null &

                printf '%s\n' '{"success":true}'
                ;;
            get_update_log)
                if [ -f /var/log/mosdns_update.log ]; then
                    printf '{"log":"'; cat /var/log/mosdns_update.log 2>/dev/null | json_escape; printf '"}\n'
                else
                    printf '%s\n' '{"log":""}'
                fi
                ;;
            *)
                json_reply_error "Unknown method."
                ;;
        esac
        exit 0
        ;;
esac

exit 1
MOSDNS_RPC_EOF
    chmod 755 "$MOSDNS_RPC_COMPAT" || return 1
}

ensure_mosdns_rpc() {
    if [ ! -x /etc/init.d/rpcd ] || ! command -v ubus >/dev/null 2>&1; then
        _mos_warn "系统缺少 rpcd / ubus，跳过 MosDNS RPC 自动修复"
        return 1
    fi

    _mos_info "正在检测 MosDNS RPC..."

    if [ -f "$MOSDNS_RPC_COMPAT" ]; then
        rm -f "$MOSDNS_RPC_COMPAT" 2>/dev/null
    fi

    /etc/init.d/rpcd restart >/dev/null 2>&1
    sleep 2

    UCODE_MODULES_OK=0

    if check_mosdns_ucode_modules; then
        UCODE_MODULES_OK=1
        _mos_ok "ucode fs / uci / ubus 模块正常"
    else
        _mos_warn "ucode fs / uci / ubus 模块不完整"
    fi

    if rpc_mosdns_exists &&
       [ "$UCODE_MODULES_OK" -eq 1 ] &&
       verify_mosdns_rpc_methods
    then
        _mos_ok "MosDNS RPC 原生注册成功"
        return 0
    fi

    _mos_warn "当前 rpcd 无法原生注册 luci.mosdns，正在启用兼容模式..."

    if ! write_mosdns_rpc_compat; then
        _mos_error "MosDNS RPC 兼容桥创建失败"
        return 1
    fi

    /etc/init.d/rpcd restart >/dev/null 2>&1
    sleep 2

    if rpc_mosdns_exists &&
       verify_mosdns_rpc_methods
    then
        _mos_ok "MosDNS RPC 兼容模式已启用"
        _mos_ok "start_update / get_update_log 方法正常"

        if [ "$UCODE_MODULES_OK" -ne 1 ]; then
            _mos_warn "数据库在线更新仍需安装匹配版本的 ucode fs/uci/ubus 模块"
        fi

        return 0
    fi

    _mos_error "MosDNS RPC 注册失败"
    _mos_error "请检查 /usr/libexec/rpcd/luci.mosdns 与 rpcd 日志"

    return 1
}

reload_mosdns_luci() {
    _mos_info "正在刷新 LuCI..."
    rm -rf /tmp/luci-* >/dev/null 2>&1
    [ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd reload >/dev/null 2>&1
}

get_mosdns_version() {
    MOSDNS_VERSION=""
    command -v mosdns >/dev/null 2>&1 || return 1
    MOSDNS_VERSION="$(mosdns version 2>/dev/null | head -n 1)"
    [ -n "$MOSDNS_VERSION" ] || MOSDNS_VERSION="$(mosdns -v 2>/dev/null | head -n 1)"
    [ -n "$MOSDNS_VERSION" ]
}

verify_mosdns_installation() {
    printf '\n'; _mos_info "正在进行 MosDNS 最终验证..."
    VERIFY_FAILED=0
    for PACKAGE_NAME in v2dat v2ray-geoip v2ray-geosite mosdns luci-app-mosdns luci-i18n-mosdns-zh-cn; do
        if check_mosdns_package_installed "$PACKAGE_NAME"; then _mos_ok "$PACKAGE_NAME"; else _mos_error "$PACKAGE_NAME 未正确安装"; VERIFY_FAILED=1; fi
    done
    if command -v mosdns >/dev/null 2>&1; then _mos_ok "MosDNS 可执行文件正常"; else _mos_error "没有检测到 MosDNS 可执行文件"; VERIFY_FAILED=1; fi
    [ "$VERIFY_FAILED" -eq 0 ]
}

install_mosdns() {
    printf '\n======================================\n          MosDNS Installer\n======================================\n\n'

    [ "$(id -u 2>/dev/null)" = "0" ] || { _mos_error "请使用 root 用户运行"; return 1; }
    _mos_info "正在准备 MosDNS 安装环境..."

    check_mosdns_runtime || return 1
    detect_mosdns_openwrt || return 1
    detect_mosdns_cpu
    detect_mosdns_package_manager || return 1
    detect_mosdns_arch || return 1
    check_mosdns_disk_space || return 1

    _mos_ok "环境检测完成"

    cleanup_mosdns_all
    mkdir -p "$MOSDNS_TMP_DIR" || return 1
    prepare_mosdns_download_info || return 1
    printf '\n'
    trap 'interrupt_mosdns' INT TERM

    if ! smart_download_mosdns "$MOSDNS_BASE_URL" "$MOSDNS_ARCHIVE_FILE"; then
        _mos_error "MosDNS 下载失败，所有 GitHub 下载线路均不可用"
        [ -s "$MOSDNS_DOWNLOAD_LOG" ] && { printf '\n========== DOWNLOAD LOG ==========\n'; tail -n 30 "$MOSDNS_DOWNLOAD_LOG"; printf '==================================\n'; }
        cleanup_mosdns_temp; trap - INT TERM; return 1
    fi

    _mos_ok "MosDNS 安装包下载完成"
    ARCHIVE_SIZE="$(wc -c < "$MOSDNS_ARCHIVE_FILE" 2>/dev/null)"
    ARCHIVE_MB="$(awk -v s="$ARCHIVE_SIZE" 'BEGIN{if(s>0)printf "%.2f",s/1024/1024;else printf "0.00"}')"
    _mos_info "File Size        : ${ARCHIVE_MB} MB"
    printf '\n'

    extract_mosdns_archive || { cleanup_mosdns_temp; trap - INT TERM; return 1; }
    locate_mosdns_packages || { cleanup_mosdns_temp; trap - INT TERM; return 1; }
    detect_existing_mosdns_service
    stop_mosdns_service

    if ! install_mosdns_packages; then
        _mos_error "MosDNS 组件安装失败"
        [ "$MOSDNS_WAS_RUNNING" -eq 1 ] && [ -x /etc/init.d/mosdns ] && /etc/init.d/mosdns start >/dev/null 2>&1
        cleanup_mosdns_temp; trap - INT TERM; return 1
    fi

    verify_mosdns_installation || { _mos_error "MosDNS 最终验证失败"; cleanup_mosdns_temp; trap - INT TERM; return 1; }

    printf '\n'
    _mos_info "正在检查 MosDNS 所需 ucode 模块..."

    if ! install_missing_mosdns_ucode_modules; then
        _mos_error "ucode 依赖修复失败"
        _mos_warn "MosDNS 本体已安装，但数据库在线更新将不可用"
    fi

    if ! ensure_mosdns_rpc; then
        _mos_warn "MosDNS 已安装，但 LuCI RPC 兼容处理存在异常"
    fi

    reload_mosdns_luci
    start_mosdns_service || _mos_warn "MosDNS 软件包已安装，但服务自动启动存在异常"
    get_mosdns_version

    cleanup_mosdns_temp
    cleanup_mosdns_logs
    trap - INT TERM

    printf '\n======================================\n          MosDNS Installed\n======================================\n\n'
    _mos_ok "MosDNS 安装完成"
    _mos_info "CPU      : $MOSDNS_CPU_ARCH"
    _mos_info "Arch     : $MOSDNS_ARCH"
    _mos_info "SDK      : $MOSDNS_SDK"
    _mos_info "Package  : $MOSDNS_PKG_EXT"
    [ -n "$MOSDNS_VERSION" ] && _mos_info "Version  : $MOSDNS_VERSION"
    if rpc_mosdns_exists; then _mos_ok "RPC      : luci.mosdns 正常"; else _mos_warn "RPC      : luci.mosdns 未注册"; fi
    if verify_mosdns_rpc_methods; then _mos_ok "RPC API  : start_update / get_update_log 正常"; else _mos_warn "RPC API  : 更新方法验证失败"; fi
    if check_mosdns_ucode_modules; then _mos_ok "Ucode    : fs / uci / ubus 正常"; else _mos_warn "Ucode    : 缺少 fs / uci / ubus 模块，数据库在线更新不可用"; fi
    printf '\nLuCI：服务 → MosDNS\n\n'
    return 0
}

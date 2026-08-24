#!/bin/sh

# ============================================================
# Open-Pro-Installer
# iStoreOS Style / Argon + QuickStart Installer
#
# 支持：
#   OpenWrt 21.x / 22.x / 23.x / 24.x / 25.x
#   OPKG / APK 自动识别
# ============================================================

GREEN="$(printf '\033[32m')"
BLUE="$(printf '\033[34m')"
RED="$(printf '\033[31m')"
YELLOW="$(printf '\033[33m')"
CYAN="$(printf '\033[36m')"
RESET="$(printf '\033[0m')"

THEME_TMP="/tmp/openpro-theme"
THEME_LOG="/tmp/openpro-theme.log"
THEME_ROUTE_FILE="/tmp/openpro_theme_routes"
THEME_SORTED_FILE="/tmp/openpro_theme_routes.sorted"
THEME_TEST_DIR="/tmp/openpro_theme_speedtest.d"

MODEL=""
CPU_ARCH=""
PKG_ARCH=""
OPENWRT_VERSION=""
OPENWRT_MAJOR=""
PKG_MANAGER=""
ARGON_PACKAGE_TYPE=""

ARGON_REPO="jerrykuku/luci-theme-argon"
ARGON_RELEASE_API="https://api.github.com/repos/${ARGON_REPO}/releases/latest"
ARGON_RELEASE_JSON="${THEME_TMP}/argon_release.json"
ARGON_ASSET_LIST="${THEME_TMP}/argon_assets.list"
ARGON_EXPANDED_ASSETS="${THEME_TMP}/argon_assets.html"
ARGON_RELEASE_TAG=""
ARGON_TARGET_TAG=""
ARGON_THEME_URL=""
ARGON_CONFIG_URL=""
ARGON_LANG_URL=""
ARGON_THEME_FILE=""
ARGON_CONFIG_FILE=""
ARGON_LANG_FILE=""

IS_OPKG_URL="https://raw.githubusercontent.com/linkease/istore/main/luci/luci-app-store/root/bin/is-opkg"
IS_OPKG_BIN=""
QUICKSTART_CONFIG_URL="https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/config/quickstart"
QUICKSTART_CONFIG_TMP="${THEME_TMP}/quickstart.conf"
QUICKSTART_CONFIG_BAK="/etc/config/quickstart.openpro.bak"

THEME_TEST_CONNECT_TIMEOUT=4
THEME_TEST_MAX_TIME=6
THEME_SCORE_FILE_KB=4096
THEME_DOWNLOAD_NODES="
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
GH04|https://cdn.akaere.online/
GH05|https://github.mxw.qzz.io/
GH06|https://gh.07150721.xyz/
DIRECT|
"

_theme_info() { printf "%b\n" "${GREEN}[INFO]${RESET} $*"; }
_theme_ok() { printf "%b\n" "${GREEN}[OK]${RESET} $*"; }
_theme_warn() { printf "%b\n" "${YELLOW}[WARN]${RESET} $*"; }
_theme_error() { printf "%b\n" "${RED}[ERROR]${RESET} $*"; }

theme_progress()
{
    PERCENT="$1"
    TEXT="$2"
    WIDTH=30
    FILLED=$((PERCENT * WIDTH / 100))
    EMPTY=$((WIDTH - FILLED))
    BAR=""
    I=0
    while [ "$I" -lt "$FILLED" ]; do BAR="${BAR}#"; I=$((I + 1)); done
    I=0
    while [ "$I" -lt "$EMPTY" ]; do BAR="${BAR}-"; I=$((I + 1)); done
    printf "\r\033[2K${GREEN}[INFO]${RESET} %-28s [${GREEN}%s${RESET}] %3d%%" "$TEXT" "$BAR" "$PERCENT"
}

show_theme_error_log()
{
    printf "\n%b\n" "${RED}========== ERROR LOG ==========${RESET}"
    if [ -s "$THEME_LOG" ]; then tail -n 120 "$THEME_LOG"; else printf "没有可用错误日志\n"; fi
    printf "%b\n\n" "${RED}===============================${RESET}"
}

cleanup_theme_temp()
{
    rm -rf "$THEME_TMP" "$THEME_TEST_DIR" 2>/dev/null
    rm -f "$THEME_ROUTE_FILE" "$THEME_SORTED_FILE" 2>/dev/null
}

theme_interrupt()
{
    printf "\n"
    _theme_warn "iStoreOS 风格安装已中断"
    _theme_info "安装日志保留：$THEME_LOG"
    cleanup_theme_temp
    trap - INT TERM
    return 130
}

check_theme_runtime()
{
    MISSING=""
    for CMD in grep sed awk head tail cut tr sort basename cp rm mkdir chmod df uci uname id
    do
        command -v "$CMD" >/dev/null 2>&1 || MISSING="$MISSING $CMD"
    done
    [ -z "$MISSING" ] || { _theme_error "系统缺少必要命令:$MISSING"; return 1; }
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || {
        _theme_error "系统缺少 curl / wget"; return 1;
    }
}

detect_package_manager()
{
    if command -v opkg >/dev/null 2>&1; then PKG_MANAGER="opkg"; ARGON_PACKAGE_TYPE="ipk"; return 0; fi
    if command -v apk >/dev/null 2>&1; then PKG_MANAGER="apk"; ARGON_PACKAGE_TYPE="apk"; return 0; fi
    return 1
}

detect_openwrt_major()
{
    OPENWRT_MAJOR="$(printf '%s\n' "$OPENWRT_VERSION" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')"
    case "$OPENWRT_MAJOR" in ''|*[!0-9]*) OPENWRT_MAJOR=0 ;; esac
}

detect_theme_system()
{
    if [ -f /etc/openwrt_release ]; then . /etc/openwrt_release; OPENWRT_VERSION="${DISTRIB_RELEASE:-unknown}"; else OPENWRT_VERSION="unknown"; fi
    detect_openwrt_major
    MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"; [ -n "$MODEL" ] || MODEL="Unknown"
    CPU_ARCH="$(uname -m 2>/dev/null)"; [ -n "$CPU_ARCH" ] || CPU_ARCH="Unknown"
    if [ "$PKG_MANAGER" = "opkg" ]; then
        PKG_ARCH="$(opkg print-architecture 2>/dev/null | awk '$1=="arch" && $2!="all" && $2!="noarch" {if ($3>p){p=$3;a=$2}} END{print a}')"
    else
        PKG_ARCH="$CPU_ARCH"
    fi
    [ -n "$PKG_ARCH" ] || PKG_ARCH="Unknown"
    _theme_info "OpenWrt版本 : $OPENWRT_VERSION"
    _theme_info "OpenWrt主版本: $OPENWRT_MAJOR"
    _theme_info "设备型号    : $MODEL"
    _theme_info "CPU架构     : $CPU_ARCH"
    _theme_info "软件包架构  : $PKG_ARCH"
    _theme_info "包管理器    : $PKG_MANAGER"
}

check_theme_disk_space()
{
    FREE_KB="$(df -k / 2>/dev/null | awk 'END {print $4}')"
    case "$FREE_KB" in ''|*[!0-9]*) FREE_KB=0 ;; esac
    FREE_MB=$((FREE_KB / 1024))
    _theme_info "可用空间    : ${FREE_MB} MB"
    [ "$FREE_MB" -ge 15 ] || { _theme_error "可用空间不足，至少需要 15 MB"; return 1; }
}

select_argon_compat()
{
    case "$OPENWRT_MAJOR" in
        21) ARGON_TARGET_TAG="v2.2.9" ;;
        22|23|24|25) ARGON_TARGET_TAG="" ;;
        *) ARGON_TARGET_TAG=""; _theme_warn "未知 OpenWrt 主版本，使用最新 Argon" ;;
    esac
    _theme_info "兼容策略    : OpenWrt ${OPENWRT_MAJOR}.x"
    if [ -n "$ARGON_TARGET_TAG" ]; then _theme_info "Argon版本   : $ARGON_TARGET_TAG"; else _theme_info "Argon版本   : 自动获取最新兼容版本"; fi
    case "$ARGON_PACKAGE_TYPE" in
        ipk) ARGON_THEME_FILE="${THEME_TMP}/argon-theme.ipk"; ARGON_CONFIG_FILE="${THEME_TMP}/argon-config.ipk"; ARGON_LANG_FILE="${THEME_TMP}/argon-lang.ipk" ;;
        apk) ARGON_THEME_FILE="${THEME_TMP}/argon-theme.apk"; ARGON_CONFIG_FILE="${THEME_TMP}/argon-config.apk"; ARGON_LANG_FILE="${THEME_TMP}/argon-lang.apk" ;;
        *) _theme_error "未知软件包格式：$ARGON_PACKAGE_TYPE"; return 1 ;;
    esac
    _theme_info "软件包格式  : .$ARGON_PACKAGE_TYPE"
}

download_direct()
{
    URL="$1"; OUTPUT="$2"; rm -f "$OUTPUT"
    if command -v curl >/dev/null 2>&1; then
        curl -4 -L -f -sS --connect-timeout 10 --max-time 180 --retry 2 --retry-delay 1 -H "User-Agent: Open-Pro-Installer" -o "$OUTPUT" "$URL" >>"$THEME_LOG" 2>&1
    else
        wget -T 30 --header="User-Agent: Open-Pro-Installer" -O "$OUTPUT" "$URL" >>"$THEME_LOG" 2>&1
    fi
    RESULT=$?
    [ "$RESULT" -eq 0 ] && [ -s "$OUTPUT" ] || { rm -f "$OUTPUT"; return 1; }
    if head -c 512 "$OUTPUT" 2>/dev/null | grep -Eqi '<html|<!doctype|404 not found|bad gateway|502 bad gateway|403 forbidden|cloudflare'; then
        printf "Invalid response: %s\n" "$URL" >>"$THEME_LOG"; rm -f "$OUTPUT"; return 1
    fi
}

package_installed()
{
    case "$PKG_MANAGER" in
        opkg) opkg status "$1" 2>/dev/null | grep -q 'Status:.*installed' ;;
        apk) apk list --installed "$1" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

fetch_argon_release_page()
{
    TAG="$1"
    [ -n "$TAG" ] || return 1
    download_direct "https://github.com/${ARGON_REPO}/releases/expanded_assets/${TAG}" "$ARGON_EXPANDED_ASSETS" || return 1
    grep -o "/${ARGON_REPO}/releases/download/[^\"]*" "$ARGON_EXPANDED_ASSETS" 2>/dev/null |
        sed 's/&amp;/\&/g' | while IFS= read -r ASSET_PATH; do printf 'https://github.com%s\n' "$ASSET_PATH"; done >"$ARGON_ASSET_LIST"
    [ -s "$ARGON_ASSET_LIST" ]
}

fetch_argon_release()
{
    rm -f "$ARGON_RELEASE_JSON" "$ARGON_ASSET_LIST" "$ARGON_EXPANDED_ASSETS"
    ARGON_RELEASE_TAG=""; ARGON_THEME_URL=""; ARGON_CONFIG_URL=""; ARGON_LANG_URL=""
    if [ -n "$ARGON_TARGET_TAG" ]; then
        ARGON_RELEASE_TAG="$ARGON_TARGET_TAG"
        _theme_info "正在读取 Argon Release：$ARGON_RELEASE_TAG"
        fetch_argon_release_page "$ARGON_RELEASE_TAG" || { _theme_error "无法读取 Argon $ARGON_RELEASE_TAG Release"; return 1; }
    else
        _theme_info "正在直连 GitHub API 获取 Argon 最新版本..."
        if download_direct "$ARGON_RELEASE_API" "$ARGON_RELEASE_JSON"; then
            if command -v jsonfilter >/dev/null 2>&1; then
                ARGON_RELEASE_TAG="$(jsonfilter -i "$ARGON_RELEASE_JSON" -e '@.tag_name' 2>/dev/null)"
                jsonfilter -i "$ARGON_RELEASE_JSON" -e '@.assets[*].browser_download_url' 2>/dev/null >"$ARGON_ASSET_LIST"
            else
                ARGON_RELEASE_TAG="$(tr ',' '\n' <"$ARGON_RELEASE_JSON" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
                tr ',' '\n' <"$ARGON_RELEASE_JSON" | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' >"$ARGON_ASSET_LIST"
            fi
        fi
        if [ -z "$ARGON_RELEASE_TAG" ] || [ ! -s "$ARGON_ASSET_LIST" ]; then
            _theme_warn "GitHub API 不可用，切换普通 Release 页面..."
            if command -v curl >/dev/null 2>&1; then
                EFFECTIVE_URL="$(curl -4 -L -sS --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' "https://github.com/${ARGON_REPO}/releases/latest" 2>>"$THEME_LOG")"
                ARGON_RELEASE_TAG="$(printf '%s\n' "$EFFECTIVE_URL" | sed -n 's#^.*/releases/tag/\([^/?#]*\).*$#\1#p')"
            fi
            [ -n "$ARGON_RELEASE_TAG" ] || { _theme_error "无法识别 Argon 最新版本"; return 1; }
            fetch_argon_release_page "$ARGON_RELEASE_TAG" || { _theme_error "无法读取 Argon Release Asset"; return 1; }
        fi
    fi

    case "$ARGON_PACKAGE_TYPE" in
        ipk)
            ARGON_THEME_URL="$(grep '/luci-theme-argon_[^/]*\.ipk$' "$ARGON_ASSET_LIST" | head -n 1)"
            ARGON_CONFIG_URL="$(grep '/luci-app-argon-config_[^/]*\.ipk$' "$ARGON_ASSET_LIST" | head -n 1)"
            ARGON_LANG_URL="$(grep '/luci-i18n-argon-config-zh-cn_[^/]*\.ipk$' "$ARGON_ASSET_LIST" | head -n 1)"
            ;;
        apk)
            ARGON_THEME_URL="$(grep '/luci-theme-argon[^/]*\.apk$' "$ARGON_ASSET_LIST" | head -n 1)"
            ARGON_CONFIG_URL="$(grep '/luci-app-argon-config[^/]*\.apk$' "$ARGON_ASSET_LIST" | head -n 1)"
            ARGON_LANG_URL="$(grep '/luci-i18n-argon-config-zh-cn[^/]*\.apk$' "$ARGON_ASSET_LIST" | head -n 1)"
            ;;
    esac

    case "$ARGON_THEME_URL" in https://github.com/*) ;; *) ARGON_THEME_URL="" ;; esac
    case "$ARGON_CONFIG_URL" in https://github.com/*) ;; *) ARGON_CONFIG_URL="" ;; esac
    case "$ARGON_LANG_URL" in https://github.com/*) ;; *) ARGON_LANG_URL="" ;; esac

    [ -n "$ARGON_THEME_URL" ] || { _theme_error "Release 中没有 .$ARGON_PACKAGE_TYPE 格式的 Argon Theme"; return 1; }
    [ -n "$ARGON_CONFIG_URL" ] || _theme_warn "Release 中没有 Argon Config，将仅安装 Theme"
    _theme_ok "Argon Release：$ARGON_RELEASE_TAG"
    _theme_info "Theme  : $(basename "$ARGON_THEME_URL")"
    if [ -n "$ARGON_CONFIG_URL" ]; then _theme_info "Config : $(basename "$ARGON_CONFIG_URL")"; else _theme_info "Config : 无"; fi
    if [ -n "$ARGON_LANG_URL" ]; then _theme_info "中文包 : $(basename "$ARGON_LANG_URL")"; else _theme_info "中文包 : 无独立中文包"; fi
}

theme_seconds_to_ms()
{
    T="$1"
    case "$T" in ''|*[!0-9.]*) printf '%s' 999999; return 0 ;; esac
    SEC="${T%%.*}"; FRAC="${T#*.}"; [ "$SEC" = "$T" ] && FRAC=0
    [ -n "$SEC" ] || SEC=0
    FRAC="${FRAC}000"; FRAC="$(printf '%.3s' "$FRAC")"
    SEC="$(printf '%s' "$SEC" | sed 's/^0*//')"; FRAC="$(printf '%s' "$FRAC" | sed 's/^0*//')"
    [ -n "$SEC" ] || SEC=0; [ -n "$FRAC" ] || FRAC=0
    printf '%s' $((SEC * 1000 + FRAC))
}

theme_speed_to_mb()
{
    S="$1"
    case "$S" in ''|*[!0-9.]*) printf '%s' 0.00; return 0 ;; esac
    S="${S%%.*}"; [ -n "$S" ] || S=0
    WHOLE=$((S / 1048576)); REM=$((S % 1048576)); DEC=$((REM * 100 / 1048576))
    printf '%d.%02d' "$WHOLE" "$DEC"
}

theme_calculate_score()
{
    T="$1"; S="$2"
    case "$T" in ''|*[!0-9]*) T=999999 ;; esac
    case "$S" in ''|*[!0-9]*) S=0 ;; esac
    [ "$S" -gt 0 ] || { printf '%s' 999999999; return 0; }
    SPEED_KB=$((S / 1024))
    [ "$SPEED_KB" -gt 0 ] || { printf '%s' 999999999; return 0; }
    DOWNLOAD_MS=$((THEME_SCORE_FILE_KB * 1000 / SPEED_KB))
    printf '%s' $((T + DOWNLOAD_MS))
}

test_theme_route()
{
    NAME="$1"; PREFIX="$2"; RESULT_FILE="${THEME_TEST_DIR}/${NAME}.result"
    TEST_URL="${PREFIX}${ARGON_THEME_URL}"
    if ! command -v curl >/dev/null 2>&1; then printf '%s|999999999|999999|0|0.00|%s\n' "$NAME" "$PREFIX" >"$RESULT_FILE"; return; fi
    CURL_DATA="$(curl -4 -L -f -sS --connect-timeout "$THEME_TEST_CONNECT_TIMEOUT" --max-time "$THEME_TEST_MAX_TIME" -o /dev/null -w '%{time_starttransfer}|%{speed_download}|%{size_download}' "$TEST_URL" 2>>"$THEME_LOG")"
    RESULT=$?
    TTFB="$(printf '%s' "$CURL_DATA" | cut -d '|' -f 1)"
    SPEED_BPS="$(printf '%s' "$CURL_DATA" | cut -d '|' -f 2)"
    SIZE_DOWN="$(printf '%s' "$CURL_DATA" | cut -d '|' -f 3)"
    case "$SIZE_DOWN" in ''|*[!0-9.]*) RECEIVED_BYTES=0 ;; *) RECEIVED_BYTES="${SIZE_DOWN%%.*}"; [ -n "$RECEIVED_BYTES" ] || RECEIVED_BYTES=0 ;; esac
    case "$SPEED_BPS" in ''|*[!0-9.]*) SPEED_INT=0 ;; *) SPEED_INT="${SPEED_BPS%%.*}"; [ -n "$SPEED_INT" ] || SPEED_INT=0 ;; esac
    if [ "$RESULT" -eq 0 ] && [ "$RECEIVED_BYTES" -gt 0 ] && [ "$SPEED_INT" -gt 0 ]; then
        TTFB_MS="$(theme_seconds_to_ms "$TTFB")"; SPEED_MB="$(theme_speed_to_mb "$SPEED_INT")"; SCORE="$(theme_calculate_score "$TTFB_MS" "$SPEED_INT")"
        printf '%s|%s|%s|%s|%s|%s\n' "$NAME" "$SCORE" "$TTFB_MS" "$SPEED_INT" "$SPEED_MB" "$PREFIX" >"$RESULT_FILE"
    else
        printf '%s|999999999|999999|0|0.00|%s\n' "$NAME" "$PREFIX" >"$RESULT_FILE"
    fi
}

test_theme_routes()
{
    rm -rf "$THEME_TEST_DIR"; mkdir -p "$THEME_TEST_DIR"; : >"$THEME_ROUTE_FILE"
    _theme_info "正在并行测试 Argon 下载线路..."
    printf '%s\n' "$THEME_DOWNLOAD_NODES" | while IFS='|' read -r NAME PREFIX; do [ -n "$NAME" ] && test_theme_route "$NAME" "$PREFIX" & done
    wait
    printf "\n%-10s %-14s %-16s\n" "线路" "延迟" "下载速度"
    printf '%s\n' "----------------------------------------"
    printf '%s\n' "$THEME_DOWNLOAD_NODES" | while IFS='|' read -r NAME PREFIX; do
        [ -n "$NAME" ] || continue
        FILE="${THEME_TEST_DIR}/${NAME}.result"
        if [ -s "$FILE" ]; then
            LINE="$(cat "$FILE")"; printf '%s\n' "$LINE" >>"$THEME_ROUTE_FILE"
            SCORE="$(printf '%s' "$LINE" | cut -d '|' -f 2)"; MS="$(printf '%s' "$LINE" | cut -d '|' -f 3)"; MB="$(printf '%s' "$LINE" | cut -d '|' -f 5)"
            if [ "$SCORE" -lt 999999999 ]; then printf '%-10s %-14s %-16s\n' "$NAME" "${MS} ms" "${MB} MB/s"; else printf '%-10s %-14s %-16s\n' "$NAME" "----" "----"; fi
        fi
    done
    sort -n -t '|' -k 2,2 "$THEME_ROUTE_FILE" >"$THEME_SORTED_FILE"
    BEST_LINE="$(head -n 1 "$THEME_SORTED_FILE")"; BEST_SCORE="$(printf '%s' "$BEST_LINE" | cut -d '|' -f 2)"
    [ -n "$BEST_LINE" ] && [ "$BEST_SCORE" -lt 999999999 ] || { _theme_error "所有下载线路测速均失败"; return 1; }
    _theme_ok "最佳线路：$(printf '%s' "$BEST_LINE" | cut -d '|' -f 1)"
    _theme_info "延迟：$(printf '%s' "$BEST_LINE" | cut -d '|' -f 3) ms"
    _theme_info "下载速度：$(printf '%s' "$BEST_LINE" | cut -d '|' -f 5) MB/s"
}

download_from_routes()
{
    SOURCE_URL="$1"; OUTPUT="$2"
    while IFS='|' read -r NAME SCORE MS SPEED MB PREFIX; do
        [ -n "$NAME" ] || continue
        _theme_info "使用线路 $NAME 下载 $(basename "$SOURCE_URL")..."
        download_direct "${PREFIX}${SOURCE_URL}" "$OUTPUT" && return 0
        _theme_warn "线路 $NAME 下载失败，切换下一线路"
    done <"$THEME_SORTED_FILE"
    _theme_warn "代理线路均失败，最后尝试 DIRECT"
    download_direct "$SOURCE_URL" "$OUTPUT"
}

install_local_package()
{
    FILE="$1"
    case "$PKG_MANAGER" in opkg) opkg install "$FILE" >>"$THEME_LOG" 2>&1 ;; apk) apk add --allow-untrusted "$FILE" >>"$THEME_LOG" 2>&1 ;; esac
}

install_argon()
{
    download_from_routes "$ARGON_THEME_URL" "$ARGON_THEME_FILE" || { _theme_error "Argon Theme 下载失败"; return 1; }
    install_local_package "$ARGON_THEME_FILE" || { _theme_error "Argon Theme 安装失败"; return 1; }
    if [ -n "$ARGON_CONFIG_URL" ]; then
        if download_from_routes "$ARGON_CONFIG_URL" "$ARGON_CONFIG_FILE"; then install_local_package "$ARGON_CONFIG_FILE" || _theme_warn "Argon Config 安装失败，Theme 已保留"; fi
    fi
    if [ -n "$ARGON_LANG_URL" ]; then
        if download_from_routes "$ARGON_LANG_URL" "$ARGON_LANG_FILE"; then install_local_package "$ARGON_LANG_FILE" || _theme_warn "Argon 中文包安装失败"; fi
    fi
    uci set luci.main.mediaurlbase='/luci-static/argon' 2>>"$THEME_LOG"
    uci commit luci 2>>"$THEME_LOG"
    _theme_ok "Argon 已设置为默认主题"
}

rollback_bootstrap()
{
    _theme_warn "Argon 验证失败，正在恢复 Bootstrap"
    uci set luci.main.mediaurlbase='/luci-static/bootstrap' 2>>"$THEME_LOG"
    uci commit luci 2>>"$THEME_LOG"
}

install_quickstart()
{
    _theme_info "正在安装 QuickStart 首页与网络向导..."
    IS_OPKG_BIN="${THEME_TMP}/is-opkg"
    download_direct "$IS_OPKG_URL" "$IS_OPKG_BIN" || { _theme_warn "is-opkg 下载失败，跳过 QuickStart"; return 0; }
    chmod +x "$IS_OPKG_BIN"
    "$IS_OPKG_BIN" update >>"$THEME_LOG" 2>&1 || true
    "$IS_OPKG_BIN" install luci-app-quickstart luci-app-wizard >>"$THEME_LOG" 2>&1 || { _theme_warn "QuickStart 部分组件安装失败"; return 0; }
    if download_direct "$QUICKSTART_CONFIG_URL" "$QUICKSTART_CONFIG_TMP"; then
        [ -f /etc/config/quickstart ] && [ ! -f "$QUICKSTART_CONFIG_BAK" ] && cp /etc/config/quickstart "$QUICKSTART_CONFIG_BAK"
        cp "$QUICKSTART_CONFIG_TMP" /etc/config/quickstart
    fi
    _theme_ok "QuickStart 配置完成"
}

refresh_luci()
{
    rm -rf /tmp/luci-* /tmp/luci-modulecache 2>/dev/null
    /etc/init.d/rpcd restart >/dev/null 2>&1 || true
    /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
}

verify_theme()
{
    package_installed luci-theme-argon || { rollback_bootstrap; return 1; }
    [ -d /www/luci-static/argon ] || { rollback_bootstrap; return 1; }
    CURRENT_THEME="$(uci -q get luci.main.mediaurlbase)"
    [ "$CURRENT_THEME" = "/luci-static/argon" ] || { rollback_bootstrap; return 1; }
    return 0
}

install_theme()
{
    trap 'theme_interrupt' INT TERM
    rm -f "$THEME_LOG"; mkdir -p "$THEME_TMP"; : >"$THEME_LOG"
    theme_progress 5 "正在检测运行环境..."
    printf "\n"
    check_theme_runtime || return 1
    detect_package_manager || { _theme_error "未找到支持的软件包管理器"; return 1; }
    detect_theme_system
    select_argon_compat || return 1
    check_theme_disk_space || return 1
    theme_progress 20 "正在获取 Argon 版本..."; printf "\n"
    fetch_argon_release || { show_theme_error_log; return 1; }
    theme_progress 35 "正在测试下载线路..."; printf "\n"
    test_theme_routes || { show_theme_error_log; return 1; }
    theme_progress 55 "正在下载并安装 Argon..."; printf "\n"
    install_argon || { rollback_bootstrap; show_theme_error_log; return 1; }
    theme_progress 75 "正在安装 QuickStart..."; printf "\n"
    install_quickstart
    theme_progress 90 "正在刷新 LuCI..."; printf "\n"
    refresh_luci
    verify_theme || { _theme_error "Argon 验证失败，已恢复 Bootstrap"; show_theme_error_log; return 1; }
    theme_progress 100 "iStoreOS 风格安装完成"; printf "\n"
    _theme_ok "Argon + QuickStart 安装完成"
    cleanup_theme_temp
    trap - INT TERM
    return 0
}


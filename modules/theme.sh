#!/bin/sh

# ============================================================
# Open-Pro-Installer
# iStoreOS / Argon Theme + QuickStart Installer
# BusyBox / OpenWrt /bin/sh Compatible
# ============================================================

GREEN="$(printf '\033[32m')"
BLUE="$(printf '\033[34m')"
RED="$(printf '\033[31m')"
YELLOW="$(printf '\033[33m')"
RESET="$(printf '\033[0m')"

THEME_TMP="/tmp/openpro-theme"
THEME_LOG="/tmp/openpro-theme.log"

ARGON_REPO="jerrykuku/luci-theme-argon"
ARGON_RELEASE_API="https://api.github.com/repos/${ARGON_REPO}/releases/latest"
ARGON_LEGACY_TAG="v1.8.4"
ARGON_LEGACY_CONFIG_URL="https://github.com/jerrykuku/luci-app-argon-config/releases/download/v0.9/luci-app-argon-config_0.9_all.ipk"

ARGON_RELEASE_JSON="${THEME_TMP}/argon_release.json"
ARGON_ASSET_LIST="${THEME_TMP}/argon_assets.list"
ARGON_EXPANDED_ASSETS="${THEME_TMP}/argon_expanded_assets.html"
ARGON_RELEASE_HEADERS="${THEME_TMP}/argon_release_headers.txt"

ARGON_RELEASE_TAG=""
ARGON_THEME_URL=""
ARGON_CONFIG_URL=""
ARGON_LANG_URL=""
ARGON_THEME_FILE="${THEME_TMP}/argon-theme.ipk"
ARGON_CONFIG_FILE="${THEME_TMP}/argon-config.ipk"
ARGON_LANG_FILE="${THEME_TMP}/argon-lang.ipk"

LUCI_ENGINE=""
ARGON_MODE=""

IS_OPKG_URL="https://raw.githubusercontent.com/linkease/istore/main/luci/luci-app-store/root/bin/is-opkg"
IS_OPKG_BIN=""

QUICKSTART_CONFIG_URL="https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/config/quickstart"
QUICKSTART_CONFIG_TMP="${THEME_TMP}/quickstart.conf"
QUICKSTART_CONFIG_BAK="/etc/config/quickstart.openpro.bak"

MODEL=""
CPU_ARCH=""
PKG_ARCH=""
OPENWRT_VERSION=""

THEME_ROUTE_FILE="/tmp/openpro_theme_routes"
THEME_SORTED_FILE="/tmp/openpro_theme_routes.sorted"
THEME_TEST_DIR="/tmp/openpro_theme_speedtest.d"
THEME_TEST_CONNECT_TIMEOUT=4
THEME_TEST_MAX_TIME=6
THEME_SCORE_FILE_KB=4096
THEME_MIN_SPEED_BPS=104857

THEME_DOWNLOAD_NODES="
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
GH04|https://cdn.akaere.online/
GH05|https://github.mxw.qzz.io/
GH06|https://gh.07150721.xyz/
DIRECT|
"

_theme_info(){ printf "%b\n" "${GREEN}[INFO]${RESET} $*"; }
_theme_ok(){ printf "%b\n" "${GREEN}[OK]${RESET} $*"; }
_theme_warn(){ printf "%b\n" "${YELLOW}[WARN]${RESET} $*"; }
_theme_error(){ printf "%b\n" "${RED}[ERROR]${RESET} $*"; }

theme_progress(){
    PERCENT="$1"; TEXT="$2"; WIDTH=30
    FILLED=$((PERCENT * WIDTH / 100)); EMPTY=$((WIDTH - FILLED))
    BAR=""; I=0
    while [ "$I" -lt "$FILLED" ]; do BAR="${BAR}#"; I=$((I+1)); done
    I=0
    while [ "$I" -lt "$EMPTY" ]; do BAR="${BAR}-"; I=$((I+1)); done
    printf "\r\033[2K${GREEN}[INFO]${RESET} %-24s [${GREEN}%s${RESET}] %3d%%" "$TEXT" "$BAR" "$PERCENT"
}

show_theme_error_log(){
    printf "\n%b\n" "${RED}========== ERROR LOG ==========${RESET}"
    if [ -s "$THEME_LOG" ]; then tail -n 120 "$THEME_LOG"; else printf "没有可用错误日志\n"; fi
    printf "%b\n\n" "${RED}===============================${RESET}"
}

cleanup_theme_temp(){
    rm -rf "$THEME_TMP" "$THEME_TEST_DIR" 2>/dev/null
    rm -f "$THEME_ROUTE_FILE" "$THEME_SORTED_FILE" 2>/dev/null
}
cleanup_theme_all(){ cleanup_theme_temp; rm -f "$THEME_LOG" 2>/dev/null; }

theme_interrupt(){
    printf "\n"; _theme_warn "iStoreOS 风格安装已中断"
    _theme_info "安装日志保留在：$THEME_LOG"
    cleanup_theme_temp
    trap - INT TERM
    return 130
}

check_theme_runtime(){
    MISSING=""
    for CMD in opkg grep sed awk head tail cut tr sort basename cp rm mkdir chmod df uci; do
        command -v "$CMD" >/dev/null 2>&1 || MISSING="$MISSING $CMD"
    done
    [ -z "$MISSING" ] || { _theme_error "系统缺少必要命令:$MISSING"; return 1; }
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || {
        _theme_error "系统缺少 curl / wget"; return 1;
    }
}

detect_theme_system(){
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        OPENWRT_VERSION="${DISTRIB_RELEASE:-unknown}"
    else
        OPENWRT_VERSION="unknown"
    fi
    MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"; [ -n "$MODEL" ] || MODEL="Unknown"
    CPU_ARCH="$(uname -m 2>/dev/null)"; [ -n "$CPU_ARCH" ] || CPU_ARCH="Unknown"
    PKG_ARCH="$(opkg print-architecture 2>/dev/null | awk '$1=="arch" && $2!="all" && $2!="noarch" {if($3>p){p=$3;a=$2}} END{print a}')"
    [ -n "$PKG_ARCH" ] || PKG_ARCH="Unknown"
    _theme_info "OpenWrt版本 : $OPENWRT_VERSION"
    _theme_info "设备型号    : $MODEL"
    _theme_info "CPU架构     : $CPU_ARCH"
    _theme_info "软件包架构  : $PKG_ARCH"
    _theme_info "包管理器    : opkg"
}

# 关键：优先看系统 Bootstrap 的实际模板，避免被误装的新版 Argon ucode 文件干扰。
detect_luci_engine(){
    LUCI_ENGINE=""; ARGON_MODE=""
    if [ -f /usr/lib/lua/luci/view/themes/bootstrap/header.htm ] || [ -f /usr/lib/lua/luci/dispatcher.lua ]; then
        LUCI_ENGINE="lua"; ARGON_MODE="legacy"
    elif [ -f /usr/share/ucode/luci/template/themes/bootstrap/header.ut ] || [ -f /usr/share/ucode/luci/template/themes/bootstrap/header.uc ]; then
        LUCI_ENGINE="ucode"; ARGON_MODE="modern"
    else
        _theme_error "无法识别当前 LuCI 模板体系"
        return 1
    fi
    if [ "$LUCI_ENGINE" = "lua" ]; then
        _theme_info "LuCI模板体系 : Lua LuCI (.htm)"
        _theme_info "Argon方案    : Legacy $ARGON_LEGACY_TAG"
    else
        _theme_info "LuCI模板体系 : ucode LuCI (.ut)"
        _theme_info "Argon方案    : 官方最新 Release"
    fi
}

check_theme_disk_space(){
    FREE_KB="$(df -k / 2>/dev/null | awk 'END{print $4}')"
    case "$FREE_KB" in ''|*[!0-9]*) FREE_KB=0;; esac
    FREE_MB=$((FREE_KB/1024)); _theme_info "可用空间    : ${FREE_MB} MB"
    [ "$FREE_MB" -ge 15 ] || { _theme_error "可用空间不足，建议至少保留 15 MB"; return 1; }
}

download_direct(){
    URL="$1"; OUTPUT="$2"; rm -f "$OUTPUT"
    if command -v curl >/dev/null 2>&1; then
        curl -4 -L -f -sS --connect-timeout 10 --max-time 180 --retry 2 --retry-delay 1 \
            -H "User-Agent: Open-Pro-Installer" -o "$OUTPUT" "$URL" >>"$THEME_LOG" 2>&1
        RESULT=$?
    else
        wget -T 30 --header="User-Agent: Open-Pro-Installer" -O "$OUTPUT" "$URL" >>"$THEME_LOG" 2>&1
        RESULT=$?
    fi
    [ "$RESULT" -eq 0 ] && [ -s "$OUTPUT" ] || { rm -f "$OUTPUT"; return 1; }
}

package_installed(){ opkg status "$1" 2>/dev/null | grep -q 'Status:.*installed'; }
get_package_version(){ opkg status "$1" 2>/dev/null | sed -n 's/^Version:[[:space:]]*//p' | head -n 1; }

parse_argon_expanded_assets(){
    TAG="$1"
    rm -f "$ARGON_ASSET_LIST" "$ARGON_EXPANDED_ASSETS"
    URL="https://github.com/${ARGON_REPO}/releases/expanded_assets/${TAG}"
    download_direct "$URL" "$ARGON_EXPANDED_ASSETS" || return 1
    grep -o '/jerrykuku/luci-theme-argon/releases/download/[^"]*' "$ARGON_EXPANDED_ASSETS" 2>/dev/null | \
        sed 's/&amp;/\&/g' | while IFS= read -r P; do printf 'https://github.com%s\n' "$P"; done > "$ARGON_ASSET_LIST"
    if [ ! -s "$ARGON_ASSET_LIST" ]; then
        sed -n 's#.*href="\(/jerrykuku/luci-theme-argon/releases/download/[^"]*\)".*#https://github.com\1#p' \
            "$ARGON_EXPANDED_ASSETS" > "$ARGON_ASSET_LIST"
    fi
    [ -s "$ARGON_ASSET_LIST" ]
}

fetch_argon_modern_release(){
    rm -f "$ARGON_RELEASE_JSON" "$ARGON_ASSET_LIST" "$ARGON_RELEASE_HEADERS" "$ARGON_EXPANDED_ASSETS"
    ARGON_RELEASE_TAG=""; ARGON_THEME_URL=""; ARGON_CONFIG_URL=""; ARGON_LANG_URL=""
    _theme_info "正在直连 GitHub API 获取 Argon 最新版本..."
    if download_direct "$ARGON_RELEASE_API" "$ARGON_RELEASE_JSON" && grep -q '"tag_name"' "$ARGON_RELEASE_JSON"; then
        if command -v jsonfilter >/dev/null 2>&1; then
            ARGON_RELEASE_TAG="$(jsonfilter -i "$ARGON_RELEASE_JSON" -e '@.tag_name' 2>/dev/null)"
            jsonfilter -i "$ARGON_RELEASE_JSON" -e '@.assets[*].browser_download_url' 2>/dev/null > "$ARGON_ASSET_LIST"
        else
            ARGON_RELEASE_TAG="$(tr ',' '\n' < "$ARGON_RELEASE_JSON" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
            tr ',' '\n' < "$ARGON_RELEASE_JSON" | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' > "$ARGON_ASSET_LIST"
        fi
    fi
    if [ -z "$ARGON_RELEASE_TAG" ] || [ ! -s "$ARGON_ASSET_LIST" ]; then
        _theme_warn "GitHub API 不可用/限流，切换普通 Release 页面..."
        LATEST_PAGE="https://github.com/${ARGON_REPO}/releases/latest"
        if command -v curl >/dev/null 2>&1; then
            EFFECTIVE_URL="$(curl -4 -L -sS --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' "$LATEST_PAGE" 2>>"$THEME_LOG")"
        else
            rm -f "$ARGON_RELEASE_HEADERS"
            wget -S --spider -T 30 "$LATEST_PAGE" 2> "$ARGON_RELEASE_HEADERS"
            EFFECTIVE_URL="$(sed -n 's/^[[:space:]]*Location:[[:space:]]*//Ip' "$ARGON_RELEASE_HEADERS" | tail -n 1 | tr -d '\r')"
        fi
        ARGON_RELEASE_TAG="$(printf '%s\n' "$EFFECTIVE_URL" | sed -n 's#^.*/releases/tag/\([^/?#]*\).*$#\1#p')"
        [ -n "$ARGON_RELEASE_TAG" ] || { _theme_error "无法解析 Argon 最新 Release"; return 1; }
        parse_argon_expanded_assets "$ARGON_RELEASE_TAG" || return 1
    fi
    ARGON_THEME_URL="$(grep '/luci-theme-argon_[^/]*\.ipk$' "$ARGON_ASSET_LIST" | head -n 1)"
    ARGON_CONFIG_URL="$(grep '/luci-app-argon-config_[^/]*\.ipk$' "$ARGON_ASSET_LIST" | head -n 1)"
    ARGON_LANG_URL="$(grep '/luci-i18n-argon-config-zh-cn_[^/]*\.ipk$' "$ARGON_ASSET_LIST" | head -n 1)"
    [ -n "$ARGON_THEME_URL" ] || { _theme_error "Release 中未找到 luci-theme-argon IPK"; return 1; }
    [ -n "$ARGON_CONFIG_URL" ] || { _theme_error "Release 中未找到 luci-app-argon-config IPK"; return 1; }
    _theme_ok "Argon 官方最新版本：$ARGON_RELEASE_TAG"
    _theme_info "Theme  : $(basename "$ARGON_THEME_URL")"
    _theme_info "Config : $(basename "$ARGON_CONFIG_URL")"
}

fetch_argon_legacy_release(){
    ARGON_RELEASE_TAG="$ARGON_LEGACY_TAG"; ARGON_THEME_URL=""; ARGON_CONFIG_URL="$ARGON_LEGACY_CONFIG_URL"; ARGON_LANG_URL=""
    _theme_info "正在读取 Argon Legacy $ARGON_LEGACY_TAG..."
    parse_argon_expanded_assets "$ARGON_LEGACY_TAG" || { _theme_error "无法读取 Argon Legacy Release Asset"; return 1; }
    ARGON_THEME_URL="$(grep '/luci-theme-argon_[^/]*\.ipk$' "$ARGON_ASSET_LIST" | head -n 1)"
    [ -n "$ARGON_THEME_URL" ] || { _theme_error "Legacy Release 中未找到 luci-theme-argon IPK"; return 1; }
    _theme_ok "Argon Legacy 版本：$ARGON_LEGACY_TAG"
    _theme_info "Theme  : $(basename "$ARGON_THEME_URL")"
    _theme_info "Config : luci-app-argon-config_0.9_all.ipk"
}

fetch_argon_release(){
    case "$ARGON_MODE" in legacy) fetch_argon_legacy_release;; modern) fetch_argon_modern_release;; *) return 1;; esac
}

build_theme_url(){ [ -z "$1" ] && printf '%s' "$2" || printf '%s%s' "$1" "$2"; }
theme_seconds_to_ms(){ awk -v t="$1" 'BEGIN{if(t==""||t!~/^[0-9.]+$/)print 999999;else printf "%d",t*1000}'; }
theme_speed_to_mb(){ awk -v s="$1" 'BEGIN{if(s==""||s<=0)printf "0.00";else printf "%.2f",s/1024/1024}'; }
theme_calculate_score(){ awk -v t="$1" -v s="$2" -v kb="$THEME_SCORE_FILE_KB" 'BEGIN{if(s<=0){print 999999999;exit} sk=s/1024; printf "%d",t+(kb/sk)*1000}'; }
theme_test_is_error_page(){ [ -s "$1" ] || return 1; head -c 1024 "$1" 2>/dev/null | grep -Eqi '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'; }

test_theme_route(){
    TEST_URL="$1"; TEST_FILE="$2"; rm -f "$TEST_FILE"; command -v curl >/dev/null 2>&1 || return 1
    DATA="$(curl -4 -L -sS --connect-timeout "$THEME_TEST_CONNECT_TIMEOUT" --max-time "$THEME_TEST_MAX_TIME" \
        -o "$TEST_FILE" -w '%{http_code}|%{time_starttransfer}|%{speed_download}|%{size_download}' "$TEST_URL" 2>/dev/null)"
    CODE=$?; HTTP="$(printf '%s' "$DATA"|cut -d'|' -f1)"; TTFB="$(printf '%s' "$DATA"|cut -d'|' -f2)"; SPEED="$(printf '%s' "$DATA"|cut -d'|' -f3)"; SIZE="$(printf '%s' "$DATA"|cut -d'|' -f4)"
    case "$CODE" in 0|28);; *) rm -f "$TEST_FILE"; return 1;; esac
    case "$HTTP" in 200|206);; *) rm -f "$TEST_FILE"; return 1;; esac
    BYTES="$(awk -v n="$SIZE" 'BEGIN{if(n+0>0)printf "%d",n;else print 0}')"; [ "$BYTES" -ge 2048 ] || { rm -f "$TEST_FILE"; return 1; }
    theme_test_is_error_page "$TEST_FILE" && { rm -f "$TEST_FILE"; return 1; }
    MS="$(theme_seconds_to_ms "$TTFB")"; BPS="$(awk -v s="$SPEED" 'BEGIN{if(s>0)printf "%d",s;else print 0}')"
    [ "$BPS" -ge "$THEME_MIN_SPEED_BPS" ] || { rm -f "$TEST_FILE"; return 1; }
    SCORE="$(theme_calculate_score "$MS" "$BPS")"; rm -f "$TEST_FILE"; printf '%s|%s|%s' "$MS" "$BPS" "$SCORE"
}

test_theme_route_background(){
    N="$1"; P="$2"; O="$3"; R="$4"; F="$5"; U="$(build_theme_url "$P" "$O")"; D="$(test_theme_route "$U" "$F")"
    [ $? -eq 0 ] && [ -n "$D" ] || { printf '%s|FAIL\n' "$N" > "$R"; return 1; }
    M="$(printf '%s' "$D"|cut -d'|' -f1)"; S="$(printf '%s' "$D"|cut -d'|' -f2)"; C="$(printf '%s' "$D"|cut -d'|' -f3)"
    printf '%s|OK|%s|%s|%s|%s|%s\n' "$N" "$P" "$U" "$M" "$S" "$C" > "$R"
}

prepare_theme_routes(){
    O="$1"; rm -f "$THEME_ROUTE_FILE" "$THEME_SORTED_FILE"; rm -rf "$THEME_TEST_DIR"; mkdir -p "$THEME_TEST_DIR" || return 1
    printf "\n"; _theme_info "正在并行测试 Argon 下载线路..."; printf "\n"
    for N in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT; do
        P="$(printf '%s\n' "$THEME_DOWNLOAD_NODES" | awk -F'|' -v n="$N" '$1==n{print $2;exit}')"
        test_theme_route_background "$N" "$P" "$O" "$THEME_TEST_DIR/result_${N}" "$THEME_TEST_DIR/download_${N}" &
    done
    wait
    printf '%-8s %-12s %-14s %s\n' "线路" "延迟" "下载速度" "状态"
    printf '%-8s %-12s %-14s %s\n' "--------" "------------" "--------------" "------"
    for N in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT; do
        R="$THEME_TEST_DIR/result_${N}"
        if [ ! -s "$R" ] || [ "$(cut -d'|' -f2 "$R")" != "OK" ]; then
            printf '%-8s %-12s %-14s \033[1;91m%s\033[0m\n' "$N" "----" "----" "不可用"; continue
        fi
        P="$(cut -d'|' -f3 "$R")"; U="$(cut -d'|' -f4 "$R")"; M="$(cut -d'|' -f5 "$R")"; S="$(cut -d'|' -f6 "$R")"; C="$(cut -d'|' -f7 "$R")"
        printf '%-8s %-12s %-14s \033[1;92m%s\033[0m\n' "$N" "${M} ms" "$(theme_speed_to_mb "$S") MB/s" "可用"
        printf '%s|%s|%s|%s|%s|%s\n' "$C" "$N" "$P" "$U" "$M" "$S" >> "$THEME_ROUTE_FILE"
    done
    rm -rf "$THEME_TEST_DIR"; [ -s "$THEME_ROUTE_FILE" ] || { _theme_warn "没有发现可用测速线路"; return 1; }
    sort -n -t'|' -k1,1 "$THEME_ROUTE_FILE" > "$THEME_SORTED_FILE" 2>/dev/null
    [ -s "$THEME_SORTED_FILE" ] && mv "$THEME_SORTED_FILE" "$THEME_ROUTE_FILE"
    B="$(sed -n '1p' "$THEME_ROUTE_FILE")"; BN="$(printf '%s' "$B"|cut -d'|' -f2)"; BM="$(printf '%s' "$B"|cut -d'|' -f5)"; BS="$(printf '%s' "$B"|cut -d'|' -f6)"
    printf "\n"; _theme_ok "最佳线路：$BN"; _theme_info "延迟：${BM} ms"; _theme_info "下载速度：$(theme_speed_to_mb "$BS") MB/s"; printf "\n"
}

smart_download_release(){
    O="$1"; OUT="$2"; OK=0; DT=0; prepare_theme_routes "$O"
    if [ -s "$THEME_ROUTE_FILE" ]; then
        while IFS='|' read -r C N P U M S; do
            [ -n "$N" ] || continue; [ "$N" = "DIRECT" ] && DT=1
            _theme_info "正在使用线路：$N"
            if download_direct "$U" "$OUT"; then _theme_ok "下载线路：$N"; OK=1; break; fi
            _theme_warn "$N 下载失败，自动切换下一线路..."
        done < "$THEME_ROUTE_FILE"
    fi
    if [ "$OK" -ne 1 ] && [ "$DT" -ne 1 ]; then
        _theme_info "正在尝试 GitHub 官方直连..."; download_direct "$O" "$OUT" && { _theme_ok "GitHub 官方直连下载成功"; OK=1; }
    fi
    rm -f "$THEME_ROUTE_FILE" "$THEME_SORTED_FILE"; [ "$OK" -eq 1 ]
}

verify_argon_templates(){
    case "$LUCI_ENGINE" in
        lua)
            [ -f /usr/lib/lua/luci/view/themes/argon/header.htm ] || { _theme_error "缺少 Lua Argon 模板 header.htm"; return 1; }
            [ -f /usr/lib/lua/luci/view/themes/argon/footer.htm ] || { _theme_error "缺少 Lua Argon 模板 footer.htm"; return 1; }
            ;;
        ucode)
            [ -f /usr/share/ucode/luci/template/themes/argon/header.ut ] || { _theme_error "缺少 ucode Argon 模板 header.ut"; return 1; }
            [ -f /usr/share/ucode/luci/template/themes/argon/footer.ut ] || { _theme_error "缺少 ucode Argon 模板 footer.ut"; return 1; }
            ;;
        *) return 1;;
    esac
}

verify_argon_install(){ package_installed luci-theme-argon && [ -d /www/luci-static/argon ] && verify_argon_templates; }

install_argon_official(){
    fetch_argon_release || return 1
    theme_progress 28 "正在下载 Argon Theme..."; printf "\n"; smart_download_release "$ARGON_THEME_URL" "$ARGON_THEME_FILE" || return 1
    theme_progress 42 "正在下载 Argon Config..."; printf "\n"
    if ! smart_download_release "$ARGON_CONFIG_URL" "$ARGON_CONFIG_FILE"; then
        [ "$ARGON_MODE" = "legacy" ] && { _theme_warn "Legacy Config 下载失败，将仅安装主题"; rm -f "$ARGON_CONFIG_FILE"; } || return 1
    fi
    rm -f "$ARGON_LANG_FILE"
    if [ -n "$ARGON_LANG_URL" ]; then theme_progress 50 "正在下载 Argon 中文包..."; printf "\n"; smart_download_release "$ARGON_LANG_URL" "$ARGON_LANG_FILE" || rm -f "$ARGON_LANG_FILE"; fi
    theme_progress 58 "正在安装 Argon..."; printf "\n===== Argon Install =====\n" >> "$THEME_LOG"
    if [ "$ARGON_MODE" = "legacy" ]; then
        _theme_info "旧 Lua LuCI：允许降级到兼容版 Argon"
        if [ -s "$ARGON_CONFIG_FILE" ]; then
            opkg install --force-downgrade "$ARGON_THEME_FILE" "$ARGON_CONFIG_FILE" >>"$THEME_LOG" 2>&1
        else
            opkg install --force-downgrade "$ARGON_THEME_FILE" >>"$THEME_LOG" 2>&1
        fi
    else
        if [ -s "$ARGON_LANG_FILE" ]; then opkg install "$ARGON_THEME_FILE" "$ARGON_CONFIG_FILE" "$ARGON_LANG_FILE" >>"$THEME_LOG" 2>&1; else opkg install "$ARGON_THEME_FILE" "$ARGON_CONFIG_FILE" >>"$THEME_LOG" 2>&1; fi
    fi
    verify_argon_install || { _theme_error "Argon 安装后模板验证失败"; return 1; }
    _theme_ok "Argon 主题安装及模板验证成功"
}

set_argon_default(){
    verify_argon_install || return 1
    [ -d /www/luci-static/bootstrap ] && uci set luci.themes.Bootstrap='/luci-static/bootstrap' >>"$THEME_LOG" 2>&1
    uci set luci.main.theme='argon' >>"$THEME_LOG" 2>&1
    uci set luci.main.mediaurlbase='/luci-static/argon' >>"$THEME_LOG" 2>&1
    uci set luci.themes.Argon='/luci-static/argon' >>"$THEME_LOG" 2>&1
    uci commit luci >>"$THEME_LOG" 2>&1
    [ "$(uci -q get luci.main.mediaurlbase)" = "/luci-static/argon" ]
}

verify_quickstart_install(){ package_installed quickstart && package_installed luci-app-quickstart && package_installed luci-i18n-quickstart-zh-cn; }

ensure_is_opkg(){
    IS_OPKG_BIN=""
    command -v is-opkg >/dev/null 2>&1 && { IS_OPKG_BIN="$(command -v is-opkg)"; return 0; }
    [ -x /bin/is-opkg ] && { IS_OPKG_BIN=/bin/is-opkg; return 0; }
    [ -x /usr/bin/is-opkg ] && { IS_OPKG_BIN=/usr/bin/is-opkg; return 0; }
    IS_OPKG_BIN="${THEME_TMP}/is-opkg"; _theme_info "正在直连下载 iStore 官方 is-opkg..."
    download_direct "$IS_OPKG_URL" "$IS_OPKG_BIN" || { IS_OPKG_BIN=""; return 1; }
    chmod 755 "$IS_OPKG_BIN" >>"$THEME_LOG" 2>&1
}

apply_quickstart_config(){
    rm -f "$QUICKSTART_CONFIG_TMP" 2>/dev/null
    download_direct "$QUICKSTART_CONFIG_URL" "$QUICKSTART_CONFIG_TMP" || { _theme_warn "QuickStart 风格配置下载失败，保留默认配置"; return 0; }
    if [ -f /etc/config/quickstart ] && [ ! -f "$QUICKSTART_CONFIG_BAK" ]; then cp -f /etc/config/quickstart "$QUICKSTART_CONFIG_BAK" >>"$THEME_LOG" 2>&1 || true; fi
    cp -f "$QUICKSTART_CONFIG_TMP" /etc/config/quickstart >>"$THEME_LOG" 2>&1 || return 0
    if ! uci -q show quickstart >/dev/null 2>&1; then
        _theme_warn "QuickStart 风格配置不兼容当前版本"
        [ -f "$QUICKSTART_CONFIG_BAK" ] && cp -f "$QUICKSTART_CONFIG_BAK" /etc/config/quickstart >>"$THEME_LOG" 2>&1 || true
        return 0
    fi
    _theme_ok "QuickStart iStoreOS 风格配置已应用"
}

install_quickstart(){
    if verify_quickstart_install; then _theme_ok "首页 + 网络向导已安装"; apply_quickstart_config; return 0; fi
    ensure_is_opkg || return 1
    printf "\n===== QuickStart Install =====\n" >> "$THEME_LOG"
    theme_progress 70 "正在更新 QuickStart 索引..."; "$IS_OPKG_BIN" update >>"$THEME_LOG" 2>&1 || _theme_warn "iStore 软件索引更新返回异常，继续安装"
    theme_progress 78 "正在安装首页和网络向导..."; "$IS_OPKG_BIN" install luci-i18n-quickstart-zh-cn >>"$THEME_LOG" 2>&1
    if ! verify_quickstart_install; then "$IS_OPKG_BIN" install luci-i18n-quickstart-zh-cn --force-depends >>"$THEME_LOG" 2>&1; fi
    verify_quickstart_install || { _theme_error "首页 + 网络向导安装失败"; return 1; }
    theme_progress 86 "正在配置首页和网络向导..."; apply_quickstart_config; _theme_ok "首页 + 网络向导安装成功"
}

refresh_theme_luci(){
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-templatecache /tmp/luci-*cache* >/dev/null 2>&1
    [ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart >>"$THEME_LOG" 2>&1
    [ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd restart >>"$THEME_LOG" 2>&1
}

verify_argon_active(){ verify_argon_install && [ "$(uci -q get luci.main.mediaurlbase)" = "/luci-static/argon" ]; }

install_theme(){
    printf "\n%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"
    printf "%b\n" "${BLUE}║${GREEN}        iStoreOS 风格一键安装         ${BLUE}║${RESET}"
    printf "%b\n\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"
    [ "$(id -u 2>/dev/null)" = "0" ] || { _theme_error "请使用 root 用户运行"; return 1; }
    command -v opkg >/dev/null 2>&1 || { _theme_error "未检测到 OPKG 包管理器"; return 1; }
    cleanup_theme_all; mkdir -p "$THEME_TMP" || return 1; touch "$THEME_LOG" 2>/dev/null; trap 'theme_interrupt' INT TERM
    theme_progress 5 "正在检测运行环境..."
    check_theme_runtime && detect_theme_system && detect_luci_engine && check_theme_disk_space || { printf "\n"; cleanup_theme_temp; trap - INT TERM; return 1; }
    printf "\n"; theme_progress 15 "正在获取 Argon Release..."; printf "\n"
    install_argon_official || { printf "\n"; _theme_error "Argon 安装失败"; show_theme_error_log; cleanup_theme_temp; trap - INT TERM; return 1; }
    theme_progress 64 "正在设置 Argon 默认主题..."; set_argon_default || { printf "\n"; _theme_error "Argon 默认主题设置失败"; show_theme_error_log; cleanup_theme_temp; trap - INT TERM; return 1; }
    theme_progress 67 "正在准备首页和网络向导..."; install_quickstart || { printf "\n"; _theme_error "Argon 已安装，但首页 / 网络向导安装失败"; show_theme_error_log; cleanup_theme_temp; trap - INT TERM; return 1; }
    theme_progress 93 "正在刷新 LuCI..."; refresh_theme_luci; sleep 1
    theme_progress 97 "正在进行最终验证..."; verify_argon_active || { printf "\n"; _theme_error "Argon 最终验证失败"; show_theme_error_log; cleanup_theme_temp; trap - INT TERM; return 1; }
    verify_quickstart_install || { printf "\n"; _theme_error "首页 / 网络向导最终验证失败"; show_theme_error_log; cleanup_theme_temp; trap - INT TERM; return 1; }
    theme_progress 100 "iStoreOS 风格安装完成"; printf "\n\n"
    AVER="$(get_package_version luci-theme-argon)"; CVER="$(get_package_version luci-app-argon-config)"; QVER="$(get_package_version luci-app-quickstart)"
    cleanup_theme_temp; trap - INT TERM
    _theme_ok "Argon 主题安装成功"; _theme_ok "Argon 模板体系验证成功"; _theme_ok "首页 + 网络向导安装成功"
    _theme_info "LuCI Engine     : $LUCI_ENGINE"; _theme_info "Argon Mode      : $ARGON_MODE"; _theme_info "Argon Release   : $ARGON_RELEASE_TAG"
    [ -n "$AVER" ] && _theme_info "Argon Version   : $AVER"; [ -n "$CVER" ] && _theme_info "Argon Config    : $CVER"; [ -n "$QVER" ] && _theme_info "QuickStart      : $QVER"
    [ "$ARGON_MODE" = "legacy" ] && _theme_info "模板验证        : /usr/lib/lua/luci/view/themes/argon/*.htm" || _theme_info "模板验证        : /usr/share/ucode/luci/template/themes/argon/*.ut"
    _theme_info "Bootstrap       : 已保留，可作为 LuCI 回退主题"; _theme_info "当前默认主题    : /luci-static/argon"; _theme_info "如页面未更新，请 Ctrl+F5 或重新登录 LuCI"
    printf "\n"; rm -f "$THEME_LOG" 2>/dev/null; return 0
}

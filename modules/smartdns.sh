#!/bin/sh

SMARTDNS_TMP="/tmp/openpro_smartdns"
SMARTDNS_LOG="/tmp/openpro_smartdns.log"
SMARTDNS_RELEASE_JSON="$SMARTDNS_TMP/release.json"
SMARTDNS_ASSET_LIST="$SMARTDNS_TMP/assets.list"
SMARTDNS_EXPANDED_HTML="$SMARTDNS_TMP/expanded_assets.html"
SMARTDNS_ROUTE_FILE="$SMARTDNS_TMP/routes"
SMARTDNS_TEST_DIR="$SMARTDNS_TMP/test"
SMARTDNS_REPO="pymumu/smartdns"
SMARTDNS_VERSION=""
SMARTDNS_CPU=""
SMARTDNS_ARCH=""
SMARTDNS_ARCH_RAW=""
SMARTDNS_PKG_MANAGER=""
SMARTDNS_EXT=""
SMARTDNS_MAIN_URL=""
SMARTDNS_LUCI_URL=""
SMARTDNS_MAIN_FILE=""
SMARTDNS_LUCI_FILE=""
SMARTDNS_WAS_RUNNING=0

SMARTDNS_NODES="
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
GH04|https://cdn.akaere.online/
GH05|https://github.mxw.qzz.io/
GH06|https://gh.07150721.xyz/
DIRECT|
"

_sd_info(){ printf '\033[1;92m[INFO]\033[0m %s\n' "$*"; }
_sd_ok(){ printf '\033[1;92m[OK]\033[0m %s\n' "$*"; }
_sd_warn(){ printf '\033[1;93m[WARN]\033[0m %s\n' "$*"; }
_sd_error(){ printf '\033[1;91m[ERROR]\033[0m %s\n' "$*"; }

smartdns_show_log(){
    printf '\n\033[1;91m========== SMARTDNS ERROR ==========\033[0m\n'
    [ -s "$SMARTDNS_LOG" ] && tail -n 100 "$SMARTDNS_LOG" || printf '没有可用错误日志\n'
    printf '\033[1;91m====================================\033[0m\n\n'
}

smartdns_cleanup(){
    rm -rf "$SMARTDNS_TMP" 2>/dev/null
    rm -f /tmp/smartdns.ipk /tmp/smartdns_luci.ipk /tmp/openpro_smartdns_*install.log 2>/dev/null
}

smartdns_cleanup_all(){ smartdns_cleanup; rm -f "$SMARTDNS_LOG" 2>/dev/null; }

smartdns_interrupt(){
    printf '\n'; _sd_warn "SmartDNS 安装已中断"
    [ "$SMARTDNS_WAS_RUNNING" -eq 1 ] && [ -x /etc/init.d/smartdns ] && /etc/init.d/smartdns start >/dev/null 2>&1
    smartdns_cleanup
    trap - INT TERM
    return 130
}

smartdns_check_runtime(){
    MISSING=""
    for CMD in awk sed grep cut sort head tail curl cp basename mkdir chmod cat df wc; do
        command -v "$CMD" >/dev/null 2>&1 || MISSING="$MISSING $CMD"
    done
    [ -z "$MISSING" ] || { _sd_error "系统缺少必要命令:$MISSING"; return 1; }
}

smartdns_detect_system(){
    _sd_info "正在检测 OpenWrt 系统..."
    [ -f /etc/openwrt_release ] || { _sd_error "当前系统不是受支持的 OpenWrt"; return 1; }
    . /etc/openwrt_release
    _sd_ok "OpenWrt 系统检测完成"
    _sd_info "OpenWrt Version : ${DISTRIB_RELEASE:-unknown}"
    _sd_info "OpenWrt Target  : ${DISTRIB_TARGET:-unknown}"
}

smartdns_detect_package_manager(){
    _sd_info "正在检测软件包管理器..."
    if command -v apk >/dev/null 2>&1; then SMARTDNS_PKG_MANAGER="apk"; SMARTDNS_EXT="apk"
    elif command -v opkg >/dev/null 2>&1; then SMARTDNS_PKG_MANAGER="opkg"; SMARTDNS_EXT="ipk"
    else _sd_error "没有检测到 OPKG / APK"; return 1; fi
    _sd_ok "软件包管理器检测完成"
    _sd_info "Package Manager  : $SMARTDNS_PKG_MANAGER"
    _sd_info "Package Format   : .$SMARTDNS_EXT"
}

smartdns_detect_arch(){
    _sd_info "正在检测 CPU / 软件包架构..."
    SMARTDNS_CPU="$(uname -m 2>/dev/null)"
    case "$SMARTDNS_CPU" in
        aarch64|arm64) SMARTDNS_ARCH="aarch64";;
        x86_64|amd64) SMARTDNS_ARCH="x86_64";;
        armv7*|armv6*|arm) SMARTDNS_ARCH="arm";;
        i386|i486|i586|i686) SMARTDNS_ARCH="i386";;
        mips64el*) SMARTDNS_ARCH="mips64el";;
        mips64*) SMARTDNS_ARCH="mips64";;
        mipsel*) SMARTDNS_ARCH="mipsel";;
        mips*) SMARTDNS_ARCH="mips";;
        *) _sd_error "暂不支持 CPU 架构：$SMARTDNS_CPU"; return 1;;
    esac
    if [ "$SMARTDNS_PKG_MANAGER" = "opkg" ]; then
        SMARTDNS_ARCH_RAW="$(opkg print-architecture 2>/dev/null | tail -n 1 | cut -d ' ' -f 2)"
    else
        SMARTDNS_ARCH_RAW="$(apk --print-arch 2>/dev/null | head -n 1)"
    fi
    _sd_ok "架构检测完成"
    _sd_info "CPU Architecture : $SMARTDNS_CPU"
    [ -n "$SMARTDNS_ARCH_RAW" ] && _sd_info "OpenWrt Arch     : $SMARTDNS_ARCH_RAW"
    _sd_info "Release Arch     : $SMARTDNS_ARCH"
}

smartdns_check_space(){
    FREE_KB="$(df -k /usr 2>/dev/null | tail -n 1 | awk '{print $4}')"
    case "$FREE_KB" in ''|*[!0-9]*) FREE_KB=0;; esac
    FREE_MB=$((FREE_KB / 1024))
    _sd_info "可用空间        : ${FREE_MB} MB"
    [ "$FREE_MB" -ge 25 ] || { _sd_error "可用空间不足，建议至少保留 25 MB"; return 1; }
}

smartdns_extract_assets(){
    rm -f "$SMARTDNS_ASSET_LIST"
    if command -v jsonfilter >/dev/null 2>&1; then
        jsonfilter -i "$SMARTDNS_RELEASE_JSON" -e '@.assets[*].browser_download_url' 2>/dev/null > "$SMARTDNS_ASSET_LIST"
    else
        grep '"browser_download_url"' "$SMARTDNS_RELEASE_JSON" | sed 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/' > "$SMARTDNS_ASSET_LIST"
    fi
    [ -s "$SMARTDNS_ASSET_LIST" ]
}

smartdns_parse_expanded_assets(){
    rm -f "$SMARTDNS_ASSET_LIST"
    sed 's/href=/\
href=/g' "$SMARTDNS_EXPANDED_HTML" |
        sed -n 's/.*href="\([^"]*\/releases\/download\/[^"]*\)".*/\1/p' |
        sed 's/&amp;/\&/g' |
        while IFS= read -r P; do
            case "$P" in http://*|https://*) printf '%s\n' "$P";; /*) printf 'https://github.com%s\n' "$P";; esac
        done | awk '!seen[$0]++' > "$SMARTDNS_ASSET_LIST"
    [ -s "$SMARTDNS_ASSET_LIST" ]
}

smartdns_get_release(){
    mkdir -p "$SMARTDNS_TMP" || return 1
    rm -f "$SMARTDNS_RELEASE_JSON" "$SMARTDNS_ASSET_LIST" "$SMARTDNS_EXPANDED_HTML"
    SMARTDNS_VERSION=""; SMARTDNS_MAIN_URL=""; SMARTDNS_LUCI_URL=""; API_OK=0
    _sd_info "正在获取 SmartDNS 官方 Release..."

    HTTP_CODE="$(curl -4 -L -sS --connect-timeout 10 --max-time 30 -H 'Accept: application/vnd.github+json' -H 'User-Agent: Open-Pro-Installer' -o "$SMARTDNS_RELEASE_JSON" -w '%{http_code}' "https://api.github.com/repos/${SMARTDNS_REPO}/releases/latest")"
    RC=$?
    if [ "$RC" -eq 0 ] && [ "$HTTP_CODE" = "200" ] && [ -s "$SMARTDNS_RELEASE_JSON" ]; then
        if command -v jsonfilter >/dev/null 2>&1; then SMARTDNS_VERSION="$(jsonfilter -i "$SMARTDNS_RELEASE_JSON" -e '@.tag_name' 2>/dev/null)"
        else SMARTDNS_VERSION="$(grep '"tag_name"' "$SMARTDNS_RELEASE_JSON" | head -n 1 | sed 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/')"; fi
        smartdns_extract_assets && [ -n "$SMARTDNS_VERSION" ] && API_OK=1
    else
        case "$HTTP_CODE" in 403) _sd_warn "GitHub API 已触发访问限制";; 429) _sd_warn "GitHub API 请求过于频繁";; 000|"") _sd_warn "GitHub API 当前无法连接";; *) _sd_warn "GitHub API 返回 HTTP $HTTP_CODE";; esac
    fi

    if [ "$API_OK" -ne 1 ]; then
        _sd_info "正在切换 GitHub Release 页面模式..."
        RELEASE_URL="$(curl -4 -L -sS --connect-timeout 10 --max-time 30 -H 'User-Agent: Mozilla/5.0' -o /dev/null -w '%{url_effective}' "https://github.com/${SMARTDNS_REPO}/releases/latest")"
        RC=$?
        [ "$RC" -eq 0 ] && [ -n "$RELEASE_URL" ] || { _sd_error "无法访问 SmartDNS Release 页面"; return 1; }
        case "$RELEASE_URL" in */releases/tag/*) SMARTDNS_VERSION="$(printf '%s' "$RELEASE_URL" | sed 's#^.*/releases/tag/##' | cut -d '?' -f1 | cut -d '#' -f1)";; *) SMARTDNS_VERSION="";; esac
        [ -n "$SMARTDNS_VERSION" ] || { _sd_error "无法识别 SmartDNS 最新 Release 版本"; return 1; }
        _sd_ok "SmartDNS 最新版本获取成功"
        _sd_info "Release Version  : $SMARTDNS_VERSION"
        EXPANDED_URL="https://github.com/${SMARTDNS_REPO}/releases/expanded_assets/${SMARTDNS_VERSION}"
        _sd_info "正在获取 SmartDNS Release Assets..."
        curl -4 -L -f -sS --connect-timeout 10 --max-time 30 -H 'User-Agent: Mozilla/5.0' "$EXPANDED_URL" -o "$SMARTDNS_EXPANDED_HTML" || { _sd_error "无法获取 SmartDNS Release Assets"; return 1; }
        smartdns_parse_expanded_assets || { _sd_error "Release 页面没有解析到安装包"; return 1; }
        _sd_ok "SmartDNS Release Assets 获取成功"
    else
        _sd_ok "SmartDNS 官方 Release 获取成功"
        _sd_info "Release Version  : $SMARTDNS_VERSION"
    fi

    { printf '\n===== SMARTDNS ASSET LIST =====\n'; cat "$SMARTDNS_ASSET_LIST"; printf '\n===============================\n'; } >> "$SMARTDNS_LOG"

    SMARTDNS_MAIN_URL="$(grep '/smartdns\.' "$SMARTDNS_ASSET_LIST" | grep "\.${SMARTDNS_ARCH}-openwrt-all\.${SMARTDNS_EXT}$" | head -n 1)"
    [ -n "$SMARTDNS_MAIN_URL" ] || SMARTDNS_MAIN_URL="$(grep -i 'smartdns' "$SMARTDNS_ASSET_LIST" | grep -vi 'luci-app-smartdns' | grep -i "$SMARTDNS_ARCH" | grep -i 'openwrt' | grep "\.${SMARTDNS_EXT}$" | head -n 1)"

    if [ "$SMARTDNS_PKG_MANAGER" = "opkg" ]; then
        SMARTDNS_LUCI_URL="$(grep -i 'luci-app-smartdns' "$SMARTDNS_ASSET_LIST" | grep -i 'luci-compat' | grep '\.ipk$' | grep -vi 'lite' | head -n 1)"
        [ -n "$SMARTDNS_LUCI_URL" ] || SMARTDNS_LUCI_URL="$(grep -i 'luci-app-smartdns' "$SMARTDNS_ASSET_LIST" | grep '\.ipk$' | grep -vi 'lite' | head -n 1)"
    else
        SMARTDNS_LUCI_URL="$(grep -i 'luci-app-smartdns' "$SMARTDNS_ASSET_LIST" | grep '\.apk$' | grep -vi 'lite' | head -n 1)"
    fi

    [ -n "$SMARTDNS_MAIN_URL" ] || { _sd_error "没有找到当前架构的 SmartDNS 官方安装包"; return 1; }
    [ -n "$SMARTDNS_LUCI_URL" ] || { _sd_error "没有找到 SmartDNS LuCI 安装包"; return 1; }
    SMARTDNS_MAIN_FILE="$SMARTDNS_TMP/smartdns.$SMARTDNS_EXT"
    SMARTDNS_LUCI_FILE="$SMARTDNS_TMP/luci-app-smartdns.$SMARTDNS_EXT"
    _sd_ok "SmartDNS Release 解析完成"
    _sd_info "SmartDNS Asset   : $(basename "$SMARTDNS_MAIN_URL")"
    _sd_info "LuCI Asset       : $(basename "$SMARTDNS_LUCI_URL")"
}

smartdns_build_url(){ [ -z "$1" ] && printf '%s' "$2" || printf '%s%s' "$1" "$2"; }
smartdns_speed_mb(){ awk -v s="$1" 'BEGIN{if(s<=0)printf "0.00"; else printf "%.2f",s/1024/1024}'; }

smartdns_test_route(){
    N="$1"; P="$2"; O="$3"; R="$4"; U="$(smartdns_build_url "$P" "$O")"
    D="$(curl -4 -L -sS --connect-timeout 4 --max-time 6 -o /dev/null -w '%{http_code}|%{time_starttransfer}|%{speed_download}' "$U" 2>/dev/null)"; RC=$?
    [ "$RC" -eq 0 ] || [ "$RC" -eq 28 ] || { printf '%s|FAIL\n' "$N" > "$R"; return; }
    H="$(printf '%s' "$D" | cut -d '|' -f1)"; T="$(printf '%s' "$D" | cut -d '|' -f2)"; S="$(printf '%s' "$D" | cut -d '|' -f3)"
    case "$H" in 200|206);; *) printf '%s|FAIL\n' "$N" > "$R"; return;; esac
    TM="$(awk -v t="$T" 'BEGIN{if(t==""||t!~/^[0-9.]+$/)print 999999; else printf "%d",t*1000}')"
    SI="$(awk -v s="$S" 'BEGIN{if(s>0)printf "%d",s; else print 0}')"
    [ "$SI" -gt 0 ] || { printf '%s|FAIL\n' "$N" > "$R"; return; }
    SC="$(awk -v t="$TM" -v s="$SI" 'BEGIN{printf "%d",t+(10485760/s)*1000}')"
    printf '%s|OK|%s|%s|%s|%s\n' "$N" "$P" "$TM" "$SI" "$SC" > "$R"
}

smartdns_prepare_routes(){
    O="$1"; rm -rf "$SMARTDNS_TEST_DIR"; mkdir -p "$SMARTDNS_TEST_DIR" || return 1; rm -f "$SMARTDNS_ROUTE_FILE"
    printf '\n'; _sd_info "正在并行测试 SmartDNS 下载线路..."; printf '\n'
    for N in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT; do
        P="$(printf '%s\n' "$SMARTDNS_NODES" | awk -F '|' -v n="$N" '$1==n{print $2;exit}')"
        smartdns_test_route "$N" "$P" "$O" "$SMARTDNS_TEST_DIR/$N" &
    done
    wait
    printf '%-8s %-12s %-14s %s\n' "线路" "首包" "下载速度" "状态"
    for N in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT; do
        F="$SMARTDNS_TEST_DIR/$N"
        if [ ! -s "$F" ] || [ "$(cut -d '|' -f2 "$F")" != "OK" ]; then printf '%-8s %-12s %-14s \033[1;91m%s\033[0m\n' "$N" "----" "----" "不可用"; continue; fi
        P="$(cut -d '|' -f3 "$F")"; T="$(cut -d '|' -f4 "$F")"; S="$(cut -d '|' -f5 "$F")"; SC="$(cut -d '|' -f6 "$F")"
        printf '%-8s %-12s %-14s \033[1;92m%s\033[0m\n' "$N" "${T} ms" "$(smartdns_speed_mb "$S") MB/s" "可用"
        printf '%s|%s|%s|%s|%s\n' "$SC" "$N" "$P" "$T" "$S" >> "$SMARTDNS_ROUTE_FILE"
    done
    rm -rf "$SMARTDNS_TEST_DIR"
    [ -s "$SMARTDNS_ROUTE_FILE" ] || return 1
    sort -n -t '|' -k1,1 "$SMARTDNS_ROUTE_FILE" -o "$SMARTDNS_ROUTE_FILE"
    B="$(head -n1 "$SMARTDNS_ROUTE_FILE")"; _sd_ok "最佳线路：$(printf '%s' "$B" | cut -d '|' -f2)"
}

smartdns_download_file(){
    O="$1"; OUT="$2"; LABEL="$3"; rm -f "$OUT"
    if [ -s "$SMARTDNS_ROUTE_FILE" ]; then
        while IFS='|' read -r SC N P T S; do
            U="$(smartdns_build_url "$P" "$O")"; _sd_info "正在使用线路：$N"
            if curl -4 -L -f --connect-timeout 10 --max-time 300 --retry 1 --retry-delay 1 -o "$OUT" "$U"; then [ -s "$OUT" ] && { _sd_ok "$LABEL 下载完成（线路：$N）"; return 0; }; fi
            rm -f "$OUT"
        done < "$SMARTDNS_ROUTE_FILE"
    fi
    _sd_info "正在尝试 GitHub 官方直连..."
    curl -4 -L -f --connect-timeout 10 --max-time 300 --retry 1 --retry-delay 1 -o "$OUT" "$O" && [ -s "$OUT" ]
}

smartdns_package_installed(){ case "$SMARTDNS_PKG_MANAGER" in opkg) opkg status "$1" 2>/dev/null | grep -q 'Status:.*installed';; apk) apk info -e "$1" >/dev/null 2>&1;; *) return 1;; esac; }

smartdns_fix_uci_init(){
    F="/etc/init.d/smartdns"; B="/etc/init.d/smartdns.openpro.bak"; [ -f "$F" ] || return 0
    grep -q 'OPENPRO_SMARTDNS_UCI_FIX' "$F" 2>/dev/null && return 0
    [ -f "$B" ] || cp "$F" "$B" 2>/dev/null || return 0
    T="/tmp/smartdns_init_fix.$$"
    awk '
    BEGIN{fixed=0}
    {
      l=$0
      if(l~/uci_batch="\$uci_batch delete smartdns\.@smartdns\[0\]\.old_port\\n"/){if(!fixed){print "\t# OPENPRO_SMARTDNS_UCI_FIX";fixed=1};print "\tuci -q get smartdns.@smartdns[0].old_port >/dev/null 2>&1 && \\\";print "\t\tuci_batch=\"$uci_batch delete smartdns.@smartdns[0].old_port\\\\n\"";next}
      if(l~/uci_batch="\$uci_batch delete smartdns\.@smartdns\[0\]\.old_enabled\\n"/){print "\tuci -q get smartdns.@smartdns[0].old_enabled >/dev/null 2>&1 && \\\";print "\t\tuci_batch=\"$uci_batch delete smartdns.@smartdns[0].old_enabled\\\\n\"";next}
      if(l~/uci_batch="\$uci_batch delete smartdns\.@smartdns\[0\]\.old_auto_set_dnsmasq\\n"/){print "\tuci -q get smartdns.@smartdns[0].old_auto_set_dnsmasq >/dev/null 2>&1 && \\\";print "\t\tuci_batch=\"$uci_batch delete smartdns.@smartdns[0].old_auto_set_dnsmasq\\\\n\"";next}
      print l
    }' "$F" > "$T" || return 0
    [ -s "$T" ] && cp "$T" "$F" && chmod 755 "$F"
    rm -f "$T"
    _sd_ok "SmartDNS UCI 兼容修复完成"
}

smartdns_install_main(){
    _sd_info "正在安装 SmartDNS 主程序..."; RC=1
    if [ "$SMARTDNS_PKG_MANAGER" = "opkg" ]; then
        cp "$SMARTDNS_MAIN_FILE" /tmp/smartdns.ipk || return 1
        L="/tmp/openpro_smartdns_opkg_install.log"; rm -f "$L"
        opkg install --force-downgrade /tmp/smartdns.ipk > "$L" 2>&1; RC=$?
        { printf '\n===== SMARTDNS OPKG RAW LOG =====\n'; cat "$L"; } >> "$SMARTDNS_LOG"
        sed '/^uci: Entry not found$/d' "$L"; rm -f "$L" /tmp/smartdns.ipk
    else apk add --allow-untrusted "$SMARTDNS_MAIN_FILE"; RC=$?; fi
    [ "$RC" -eq 0 ] || smartdns_package_installed smartdns || return 1
    smartdns_package_installed smartdns || return 1
    _sd_ok "SmartDNS 主程序安装完成"; smartdns_fix_uci_init
}

smartdns_install_luci(){
    _sd_info "正在安装 SmartDNS LuCI..."; RC=1
    if [ "$SMARTDNS_PKG_MANAGER" = "opkg" ]; then
        cp "$SMARTDNS_LUCI_FILE" /tmp/smartdns_luci.ipk || return 1
        L="/tmp/openpro_smartdns_luci_install.log"; rm -f "$L"
        opkg install --force-downgrade /tmp/smartdns_luci.ipk > "$L" 2>&1; RC=$?; cat "$L"; cat "$L" >> "$SMARTDNS_LOG"; rm -f "$L" /tmp/smartdns_luci.ipk
    else apk add --allow-untrusted "$SMARTDNS_LUCI_FILE"; RC=$?; fi
    [ "$RC" -eq 0 ] || smartdns_package_installed luci-app-smartdns || return 1
    smartdns_package_installed luci-app-smartdns || return 1
    _sd_ok "SmartDNS LuCI 安装完成"
}

smartdns_refresh_luci(){
    _sd_info "正在刷新 LuCI..."; rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-*cache* >/dev/null 2>&1
    [ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart
    [ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd reload
    _sd_ok "LuCI 刷新完成"
}

smartdns_verify(){
    _sd_info "正在验证 SmartDNS 安装结果..."
    smartdns_package_installed smartdns && smartdns_package_installed luci-app-smartdns && command -v smartdns >/dev/null 2>&1 && [ -x /etc/init.d/smartdns ] || return 1
    _sd_ok "SmartDNS 安装验证通过"
}

install_smartdns(){
    printf '\n\033[1;94m╔══════════════════════════════════════╗\033[0m\n'
    printf '\033[1;94m║\033[1;92m        SmartDNS 一键安装             \033[1;94m║\033[0m\n'
    printf '\033[1;94m╚══════════════════════════════════════╝\033[0m\n\n'
    [ "$(id -u 2>/dev/null)" = "0" ] || { _sd_error "请使用 root 用户运行"; return 1; }
    smartdns_cleanup_all; mkdir -p "$SMARTDNS_TMP" || return 1; : > "$SMARTDNS_LOG"; trap 'smartdns_interrupt' INT TERM
    _sd_info "开始 SmartDNS 安装流程..."
    smartdns_check_runtime && smartdns_detect_system && smartdns_detect_package_manager && smartdns_detect_arch && smartdns_check_space || { smartdns_show_log; return 1; }
    smartdns_get_release || { smartdns_show_log; return 1; }
    smartdns_prepare_routes "$SMARTDNS_MAIN_URL" || true
    smartdns_download_file "$SMARTDNS_MAIN_URL" "$SMARTDNS_MAIN_FILE" "SmartDNS 主程序" || { _sd_error "SmartDNS 主程序下载失败"; smartdns_show_log; return 1; }
    smartdns_download_file "$SMARTDNS_LUCI_URL" "$SMARTDNS_LUCI_FILE" "SmartDNS LuCI" || { _sd_error "SmartDNS LuCI 下载失败"; smartdns_show_log; return 1; }
    [ -x /etc/init.d/smartdns ] && /etc/init.d/smartdns stop >/dev/null 2>&1
    smartdns_install_main || { _sd_error "SmartDNS 主程序安装失败"; smartdns_show_log; return 1; }
    smartdns_install_luci || { _sd_error "SmartDNS LuCI 安装失败"; smartdns_show_log; return 1; }
    smartdns_refresh_luci
    if [ -x /etc/init.d/smartdns ]; then /etc/init.d/smartdns enable; /etc/init.d/smartdns restart || true; fi
    smartdns_verify || { _sd_error "SmartDNS 最终验证失败"; smartdns_show_log; return 1; }
    smartdns_cleanup; trap - INT TERM
    printf '\n'; _sd_ok "SmartDNS 安装完成"; _sd_info "安装日志保留在：$SMARTDNS_LOG"; printf '\n'
}

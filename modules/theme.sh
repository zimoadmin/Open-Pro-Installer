#!/bin/sh

GREEN="$(printf '\033[32m')"
BLUE="$(printf '\033[34m')"
RED="$(printf '\033[31m')"
YELLOW="$(printf '\033[33m')"
CYAN="$(printf '\033[36m')"
RESET="$(printf '\033[0m')"

THEME_TMP="/tmp/openpro-theme"
THEME_LOG="/tmp/openpro-theme.log"

ARGON_REPO="jerrykuku/luci-theme-argon"
ARGON_RELEASE_API="https://api.github.com/repos/${ARGON_REPO}/releases/latest"

ARGON_RELEASE_JSON="${THEME_TMP}/argon_release.json"
ARGON_ASSET_LIST="${THEME_TMP}/argon_assets.list"
ARGON_EXPANDED_ASSETS="${THEME_TMP}/argon_expanded_assets.html"

ARGON_TARGET_TAG=""
ARGON_RELEASE_TAG=""
ARGON_THEME_URL=""
ARGON_CONFIG_URL=""
ARGON_LANG_URL=""

ARGON_THEME_FILE="${THEME_TMP}/argon-theme.pkg"
ARGON_CONFIG_FILE="${THEME_TMP}/argon-config.pkg"
ARGON_LANG_FILE="${THEME_TMP}/argon-lang.pkg"

ARGON_PACKAGE_TYPE=""
ARGON_TEMPLATE_TYPE=""

IS_OPKG_URL="https://raw.githubusercontent.com/linkease/istore/main/luci/luci-app-store/root/bin/is-opkg"
IS_OPKG_BIN=""

QUICKSTART_CONFIG_URL="https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/config/quickstart"
QUICKSTART_CONFIG_TMP="${THEME_TMP}/quickstart.conf"
QUICKSTART_CONFIG_BAK="/etc/config/quickstart.openpro.bak"

MODEL=""
CPU_ARCH=""
PKG_ARCH=""
OPENWRT_VERSION=""
OPENWRT_MAJOR=""
PKG_MANAGER=""

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

theme_progress()
{
    PERCENT="$1"; TEXT="$2"; WIDTH=30
    FILLED=$((PERCENT * WIDTH / 100)); EMPTY=$((WIDTH - FILLED))
    BAR=""; I=0
    while [ "$I" -lt "$FILLED" ]; do BAR="${BAR}#"; I=$((I + 1)); done
    I=0
    while [ "$I" -lt "$EMPTY" ]; do BAR="${BAR}-"; I=$((I + 1)); done
    printf "\r\033[2K${GREEN}[INFO]${RESET} %-24s [${GREEN}%s${RESET}] %3d%%" "$TEXT" "$BAR" "$PERCENT"
}

show_theme_error_log()
{
    printf "\n%b\n" "${RED}========== ERROR LOG ==========${RESET}"
    if [ -s "$THEME_LOG" ]; then tail -n 120 "$THEME_LOG"; else printf "没有可用错误日志\n"; fi
    printf "%b\n\n" "${RED}===============================${RESET}"
}

cleanup_theme_temp(){ rm -rf "$THEME_TMP" "$THEME_TEST_DIR" 2>/dev/null; rm -f "$THEME_ROUTE_FILE" "$THEME_SORTED_FILE" 2>/dev/null; }
cleanup_theme_all(){ cleanup_theme_temp; rm -f "$THEME_LOG" 2>/dev/null; }

theme_interrupt()
{
    printf "\n"; _theme_warn "iStoreOS 风格安装已中断"; _theme_info "安装日志保留在：$THEME_LOG"
    cleanup_theme_temp; trap - INT TERM; return 130
}

check_theme_runtime()
{
    MISSING=""
    for CMD in grep sed awk head tail cut tr basename cp rm mkdir chmod df uci
    do command -v "$CMD" >/dev/null 2>&1 || MISSING="$MISSING $CMD"; done
    [ -z "$MISSING" ] || { _theme_error "系统缺少必要命令:$MISSING"; return 1; }
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || {
        _theme_error "系统缺少 curl / wget"; return 1;
    }
}

detect_theme_system()
{
    OPENWRT_VERSION="unknown"; OPENWRT_MAJOR=""; PKG_MANAGER=""; PKG_ARCH="Unknown"
    if [ -f /etc/openwrt_release ]; then . /etc/openwrt_release; OPENWRT_VERSION="${DISTRIB_RELEASE:-unknown}"; fi
    OPENWRT_MAJOR="$(printf '%s\n' "$OPENWRT_VERSION" | sed -n 's/^\([0-9][0-9]*\)\..*$/\1/p')"
    MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"; [ -n "$MODEL" ] || MODEL="Unknown"
    CPU_ARCH="$(uname -m 2>/dev/null)"; [ -n "$CPU_ARCH" ] || CPU_ARCH="Unknown"

    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        PKG_ARCH="$(apk --print-arch 2>/dev/null | head -n 1)"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
        PKG_ARCH="$(opkg print-architecture 2>/dev/null | awk '$1=="arch" && $2!="all" && $2!="noarch"{if($3>p){p=$3;a=$2}} END{print a}')"
    fi

    [ -n "$PKG_ARCH" ] || PKG_ARCH="Unknown"

    _theme_info "OpenWrt版本 : $OPENWRT_VERSION"
    _theme_info "OpenWrt主版本: ${OPENWRT_MAJOR:-unknown}"
    _theme_info "设备型号    : $MODEL"
    _theme_info "CPU架构     : $CPU_ARCH"
    _theme_info "软件包架构  : $PKG_ARCH"
    _theme_info "包管理器    : ${PKG_MANAGER:-unknown}"
}

select_argon_compat()
{
    case "$OPENWRT_MAJOR" in
        21)
            ARGON_TARGET_TAG="v2.2.9"; ARGON_PACKAGE_TYPE="ipk"; ARGON_TEMPLATE_TYPE="lua"
            _theme_info "兼容策略    : OpenWrt 21.x"; _theme_info "Argon版本   : v2.2.9"
            ;;
        22|23)
            ARGON_TARGET_TAG="v2.3.1"; ARGON_PACKAGE_TYPE="ipk"; ARGON_TEMPLATE_TYPE="lua"
            _theme_info "兼容策略    : OpenWrt ${OPENWRT_MAJOR}.x"; _theme_info "Argon版本   : v2.3.1"
            ;;
        24)
            ARGON_TARGET_TAG="latest"; ARGON_PACKAGE_TYPE="ipk"; ARGON_TEMPLATE_TYPE="modern"
            _theme_info "兼容策略    : OpenWrt 24.x"; _theme_info "Argon版本   : 官方最新 IPK"
            ;;
        25)
            ARGON_TARGET_TAG="latest"; ARGON_PACKAGE_TYPE="apk"; ARGON_TEMPLATE_TYPE="modern"
            _theme_info "兼容策略    : OpenWrt 25.x"; _theme_info "Argon版本   : 官方最新 APK"
            ;;
        *)
            _theme_error "暂不支持 OpenWrt ${OPENWRT_VERSION}"
            _theme_warn "当前仅自动适配 21.x / 22.x / 23.x / 24.x / 25.x"
            return 1
            ;;
    esac

    if [ "$ARGON_PACKAGE_TYPE" = "ipk" ] && [ "$PKG_MANAGER" != "opkg" ]; then
        _theme_error "该 OpenWrt 版本需要 IPK，但系统没有 OPKG"; return 1
    fi
    if [ "$ARGON_PACKAGE_TYPE" = "apk" ] && [ "$PKG_MANAGER" != "apk" ]; then
        _theme_error "OpenWrt 25.x 方案需要 APK 包管理器"; return 1
    fi
}

check_theme_disk_space()
{
    FREE_KB="$(df -k / 2>/dev/null | awk 'END {print $4}')"
    case "$FREE_KB" in ''|*[!0-9]*) FREE_KB=0 ;; esac
    FREE_MB=$((FREE_KB / 1024))
    _theme_info "可用空间    : ${FREE_MB} MB"
    [ "$FREE_MB" -ge 15 ] || { _theme_error "可用空间不足，建议至少保留 15 MB"; return 1; }
}

download_direct()
{
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

package_installed()
{
    PACKAGE_NAME="$1"
    if [ "$PKG_MANAGER" = "opkg" ]; then
        opkg status "$PACKAGE_NAME" 2>/dev/null | grep -q 'Status:.*installed'
    elif [ "$PKG_MANAGER" = "apk" ]; then
        apk info -e "$PACKAGE_NAME" >/dev/null 2>&1
    else
        return 1
    fi
}

get_package_version()
{
    PACKAGE_NAME="$1"
    if [ "$PKG_MANAGER" = "opkg" ]; then
        opkg status "$PACKAGE_NAME" 2>/dev/null | sed -n 's/^Version:[[:space:]]*//p' | head -n 1
    elif [ "$PKG_MANAGER" = "apk" ]; then
        apk info "$PACKAGE_NAME" 2>/dev/null | head -n 1
    fi
}

parse_expanded_assets()
{
    TAG="$1"; rm -f "$ARGON_ASSET_LIST" "$ARGON_EXPANDED_ASSETS"
    EXPANDED_URL="https://github.com/${ARGON_REPO}/releases/expanded_assets/${TAG}"
    download_direct "$EXPANDED_URL" "$ARGON_EXPANDED_ASSETS" || return 1

    grep -o "/${ARGON_REPO}/releases/download/[^\"]*" "$ARGON_EXPANDED_ASSETS" 2>/dev/null |
        sed 's/&amp;/\&/g' |
        while IFS= read -r ASSET_PATH; do printf 'https://github.com%s\n' "$ASSET_PATH"; done \
        > "$ARGON_ASSET_LIST"

    [ -s "$ARGON_ASSET_LIST" ]
}

get_latest_argon_tag()
{
    ARGON_RELEASE_TAG=""; rm -f "$ARGON_RELEASE_JSON"
    _theme_info "正在直连 GitHub API 获取 Argon 最新版本..."

    if download_direct "$ARGON_RELEASE_API" "$ARGON_RELEASE_JSON"; then
        if command -v jsonfilter >/dev/null 2>&1; then
            ARGON_RELEASE_TAG="$(jsonfilter -i "$ARGON_RELEASE_JSON" -e '@.tag_name' 2>/dev/null)"
        else
            ARGON_RELEASE_TAG="$(tr ',' '\n' < "$ARGON_RELEASE_JSON" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
        fi
    fi

    if [ -z "$ARGON_RELEASE_TAG" ] && command -v curl >/dev/null 2>&1; then
        _theme_warn "GitHub API 不可用，切换普通 Release 页面..."
        EFFECTIVE_URL="$(curl -4 -L -sS --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' \
            "https://github.com/${ARGON_REPO}/releases/latest" 2>>"$THEME_LOG")"
        ARGON_RELEASE_TAG="$(printf '%s\n' "$EFFECTIVE_URL" | sed -n 's#^.*/releases/tag/\([^/?#]*\).*$#\1#p')"
    fi

    [ -n "$ARGON_RELEASE_TAG" ]
}

fetch_argon_release()
{
    ARGON_THEME_URL=""; ARGON_CONFIG_URL=""; ARGON_LANG_URL=""

    if [ "$ARGON_TARGET_TAG" = "latest" ]; then
        get_latest_argon_tag || { _theme_error "无法获取 Argon 最新版本"; return 1; }
    else
        ARGON_RELEASE_TAG="$ARGON_TARGET_TAG"
    fi

    _theme_info "正在读取 Argon Release：$ARGON_RELEASE_TAG"
    parse_expanded_assets "$ARGON_RELEASE_TAG" || { _theme_error "无法读取 Argon Release Assets"; return 1; }

    if [ "$ARGON_PACKAGE_TYPE" = "ipk" ]; then
        ARGON_THEME_URL="$(grep '/luci-theme-argon_[^/]*\.ipk$' "$ARGON_ASSET_LIST" | head -n 1)"
        ARGON_CONFIG_URL="$(grep '/luci-app-argon-config_[^/]*\.ipk$' "$ARGON_ASSET_LIST" | head -n 1)"
        ARGON_LANG_URL="$(grep '/luci-i18n-argon-config-zh-cn_[^/]*\.ipk$' "$ARGON_ASSET_LIST" | head -n 1)"
    else
        ARGON_THEME_URL="$(grep '/luci-theme-argon-[^/]*\.apk$' "$ARGON_ASSET_LIST" | head -n 1)"
        ARGON_CONFIG_URL="$(grep '/luci-app-argon-config-[^/]*\.apk$' "$ARGON_ASSET_LIST" | head -n 1)"
        ARGON_LANG_URL="$(grep '/luci-i18n-argon-config-zh-cn-[^/]*\.apk$' "$ARGON_ASSET_LIST" | head -n 1)"
    fi

    [ -n "$ARGON_THEME_URL" ] || { _theme_error "Release 中未找到对应的 Argon ${ARGON_PACKAGE_TYPE}"; return 1; }

    _theme_ok "Argon 版本：$ARGON_RELEASE_TAG"
    _theme_info "Theme  : $(basename "$ARGON_THEME_URL")"

    if [ -n "$ARGON_CONFIG_URL" ]; then
        _theme_info "Config : $(basename "$ARGON_CONFIG_URL")"
    else
        _theme_warn "当前 Release 未提供 Argon Config"
    fi

    if [ -n "$ARGON_LANG_URL" ]; then
        _theme_info "中文包 : $(basename "$ARGON_LANG_URL")"
    else
        _theme_info "当前 Release 未提供独立中文包，自动跳过"
    fi

    return 0
}

build_theme_url()
{
    PREFIX="$1"; ORIGINAL_URL="$2"
    if [ -z "$PREFIX" ]; then printf '%s' "$ORIGINAL_URL"; else printf '%s%s' "$PREFIX" "$ORIGINAL_URL"; fi
}

theme_seconds_to_ms()
{
    awk -v t="$1" 'BEGIN{if(t=="" || t !~ /^[0-9.]+$/){print 999999}else{printf "%d",t*1000}}'
}

theme_speed_to_mb()
{
    awk -v s="$1" 'BEGIN{if(s=="" || s<=0){printf "0.00"}else{printf "%.2f",s/1024/1024}}'
}

theme_calculate_score()
{
    awk -v t="$1" -v s="$2" -v kb="$THEME_SCORE_FILE_KB" \
        'BEGIN{if(s<=0){print 999999999;exit} speed_kb=s/1024; printf "%d",t+(kb/speed_kb)*1000}'
}

theme_test_is_error_page()
{
    FILE="$1"; [ -s "$FILE" ] || return 1
    head -c 1024 "$FILE" 2>/dev/null |
        grep -Eqi '<html|<!doctype|bad gateway|502 bad gateway|404 not found|403 forbidden|access denied'
}

test_theme_route()
{
    TEST_URL="$1"; TEST_FILE="$2"; rm -f "$TEST_FILE"
    command -v curl >/dev/null 2>&1 || return 1

    CURL_DATA="$(curl -4 -L -sS --connect-timeout "$THEME_TEST_CONNECT_TIMEOUT" --max-time "$THEME_TEST_MAX_TIME" \
        -o "$TEST_FILE" -w '%{http_code}|%{time_starttransfer}|%{speed_download}|%{size_download}' "$TEST_URL" 2>/dev/null)"
    CURL_CODE=$?

    HTTP_CODE="$(printf '%s' "$CURL_DATA" | cut -d '|' -f 1)"
    TTFB="$(printf '%s' "$CURL_DATA" | cut -d '|' -f 2)"
    SPEED_BPS="$(printf '%s' "$CURL_DATA" | cut -d '|' -f 3)"
    SIZE_DOWN="$(printf '%s' "$CURL_DATA" | cut -d '|' -f 4)"

    case "$CURL_CODE" in 0|28) ;; *) rm -f "$TEST_FILE"; return 1 ;; esac
    case "$HTTP_CODE" in 200|206) ;; *) rm -f "$TEST_FILE"; return 1 ;; esac

    RECEIVED_BYTES="$(awk -v n="$SIZE_DOWN" 'BEGIN{if(n+0>0){printf "%d",n}else{print 0}}')"
    [ "$RECEIVED_BYTES" -ge 2048 ] || { rm -f "$TEST_FILE"; return 1; }
    theme_test_is_error_page "$TEST_FILE" && { rm -f "$TEST_FILE"; return 1; }

    TTFB_MS="$(theme_seconds_to_ms "$TTFB")"
    SPEED_INT="$(awk -v s="$SPEED_BPS" 'BEGIN{if(s>0){printf "%d",s}else{print 0}}')"
    [ "$SPEED_INT" -ge "$THEME_MIN_SPEED_BPS" ] || { rm -f "$TEST_FILE"; return 1; }

    SCORE="$(theme_calculate_score "$TTFB_MS" "$SPEED_INT")"
    rm -f "$TEST_FILE"
    printf '%s|%s|%s' "$TTFB_MS" "$SPEED_INT" "$SCORE"
}

test_theme_route_background()
{
    NODE_NAME="$1"; NODE_PREFIX="$2"; ORIGINAL_URL="$3"; RESULT_FILE="$4"; TEST_FILE="$5"
    TEST_URL="$(build_theme_url "$NODE_PREFIX" "$ORIGINAL_URL")"
    TEST_DATA="$(test_theme_route "$TEST_URL" "$TEST_FILE")"
    if [ $? -ne 0 ] || [ -z "$TEST_DATA" ]; then printf '%s|FAIL\n' "$NODE_NAME" > "$RESULT_FILE"; return 1; fi

    TTFB_MS="$(printf '%s' "$TEST_DATA" | cut -d '|' -f 1)"
    SPEED_BPS="$(printf '%s' "$TEST_DATA" | cut -d '|' -f 2)"
    SCORE="$(printf '%s' "$TEST_DATA" | cut -d '|' -f 3)"

    printf '%s|OK|%s|%s|%s|%s|%s\n' "$NODE_NAME" "$NODE_PREFIX" "$TEST_URL" "$TTFB_MS" "$SPEED_BPS" "$SCORE" > "$RESULT_FILE"
}

prepare_theme_routes()
{
    ORIGINAL_URL="$1"
    rm -f "$THEME_ROUTE_FILE" "$THEME_SORTED_FILE"; rm -rf "$THEME_TEST_DIR"
    mkdir -p "$THEME_TEST_DIR" || return 1

    printf "\n"; _theme_info "正在并行测试 Argon 下载线路..."; printf "\n"

    for NODE_NAME in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT
    do
        NODE_PREFIX="$(printf '%s\n' "$THEME_DOWNLOAD_NODES" | awk -F '|' -v n="$NODE_NAME" '$1==n{print $2;exit}')"
        test_theme_route_background "$NODE_NAME" "$NODE_PREFIX" "$ORIGINAL_URL" \
            "$THEME_TEST_DIR/result_${NODE_NAME}" "$THEME_TEST_DIR/download_${NODE_NAME}" &
    done

    wait

    printf '%-8s %-12s %-14s\n' "线路" "延迟" "下载速度"
    printf '%-8s %-12s %-14s\n' "--------" "------------" "--------------"

    for NODE_NAME in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT
    do
        RESULT_FILE="$THEME_TEST_DIR/result_${NODE_NAME}"

        if [ ! -s "$RESULT_FILE" ] || [ "$(cut -d '|' -f 2 "$RESULT_FILE")" != "OK" ]; then
            printf '%-8s %-12s %-14s\n' "$NODE_NAME" "----" "----"
            continue
        fi

        NODE_PREFIX="$(cut -d '|' -f 3 "$RESULT_FILE")"
        TEST_URL="$(cut -d '|' -f 4 "$RESULT_FILE")"
        TTFB_MS="$(cut -d '|' -f 5 "$RESULT_FILE")"
        SPEED_BPS="$(cut -d '|' -f 6 "$RESULT_FILE")"
        SCORE="$(cut -d '|' -f 7 "$RESULT_FILE")"
        SPEED_MB="$(theme_speed_to_mb "$SPEED_BPS")"

        printf '%-8s %-12s %-14s\n' "$NODE_NAME" "${TTFB_MS} ms" "${SPEED_MB} MB/s"
        printf '%s|%s|%s|%s|%s|%s\n' "$SCORE" "$NODE_NAME" "$NODE_PREFIX" "$TEST_URL" "$TTFB_MS" "$SPEED_BPS" >> "$THEME_ROUTE_FILE"
    done

    rm -rf "$THEME_TEST_DIR"
    [ -s "$THEME_ROUTE_FILE" ] || { _theme_warn "没有发现可用测速线路"; return 1; }

    sort -n -t '|' -k 1,1 "$THEME_ROUTE_FILE" > "$THEME_SORTED_FILE" 2>/dev/null
    [ -s "$THEME_SORTED_FILE" ] && mv "$THEME_SORTED_FILE" "$THEME_ROUTE_FILE"

    BEST_LINE="$(sed -n '1p' "$THEME_ROUTE_FILE")"
    BEST_NAME="$(printf '%s' "$BEST_LINE" | cut -d '|' -f 2)"
    BEST_TTFB="$(printf '%s' "$BEST_LINE" | cut -d '|' -f 5)"
    BEST_SPEED="$(printf '%s' "$BEST_LINE" | cut -d '|' -f 6)"

    printf "\n"
    _theme_ok "最佳线路：$BEST_NAME"
    _theme_info "延迟：${BEST_TTFB} ms"
    _theme_info "下载速度：$(theme_speed_to_mb "$BEST_SPEED") MB/s"
    printf "\n"
}

smart_download_release()
{
    ORIGINAL_URL="$1"; OUTPUT="$2"
    DOWNLOAD_SUCCESS=0; DIRECT_TRIED=0
    prepare_theme_routes "$ORIGINAL_URL"

    if [ -s "$THEME_ROUTE_FILE" ]; then
        while IFS='|' read -r ROUTE_SCORE ROUTE_NAME ROUTE_PREFIX ROUTE_URL ROUTE_TTFB ROUTE_SPEED
        do
            [ -n "$ROUTE_NAME" ] || continue
            [ -n "$ROUTE_URL" ] || continue
            [ "$ROUTE_NAME" = "DIRECT" ] && DIRECT_TRIED=1

            _theme_info "正在使用线路：$ROUTE_NAME"
            if download_direct "$ROUTE_URL" "$OUTPUT"; then
                _theme_ok "下载线路：$ROUTE_NAME"; DOWNLOAD_SUCCESS=1; break
            fi
            _theme_warn "$ROUTE_NAME 下载失败，自动切换下一线路..."
        done < "$THEME_ROUTE_FILE"
    fi

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] && [ "$DIRECT_TRIED" -ne 1 ]; then
        _theme_info "正在尝试 GitHub 官方直连..."
        if download_direct "$ORIGINAL_URL" "$OUTPUT"; then
            _theme_ok "GitHub 官方直连下载成功"; DOWNLOAD_SUCCESS=1
        fi
    fi

    rm -f "$THEME_ROUTE_FILE" "$THEME_SORTED_FILE"
    [ "$DOWNLOAD_SUCCESS" -eq 1 ]
}

rollback_bootstrap()
{
    _theme_warn "正在回滚到 Bootstrap 主题..."
    uci set luci.main.theme='bootstrap' >>"$THEME_LOG" 2>&1
    uci set luci.main.mediaurlbase='/luci-static/bootstrap' >>"$THEME_LOG" 2>&1
    uci commit luci >>"$THEME_LOG" 2>&1

    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-templatecache /tmp/luci-*cache* >/dev/null 2>&1
    [ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart >>"$THEME_LOG" 2>&1
    [ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd restart >>"$THEME_LOG" 2>&1

    _theme_ok "已恢复 Bootstrap"
}

verify_argon_install()
{
    package_installed "luci-theme-argon" || return 1
    [ -d /www/luci-static/argon ] || return 1

    if [ "$ARGON_TEMPLATE_TYPE" = "lua" ]; then
        [ -f /usr/lib/lua/luci/view/themes/argon/header.htm ] || {
            _theme_error "缺少 Argon Lua 模板：header.htm"; return 1;
        }
    fi
}

prepare_argon_21_dependencies()
{
    [ "$OPENWRT_MAJOR" = "21" ] || return 0
    [ "$PKG_MANAGER" = "opkg" ] || return 0

    _theme_info "正在检查 OpenWrt 21.x Argon 兼容依赖..."

    for DEP in luci-compat luci-lib-ipkg
    do
        if package_installed "$DEP"; then
            _theme_ok "$DEP 已安装"
        else
            _theme_info "正在尝试安装：$DEP"
            if opkg install "$DEP" >>"$THEME_LOG" 2>&1; then
                _theme_ok "$DEP 安装完成"
            else
                _theme_warn "$DEP 当前软件源无法安装，主题主体仍继续安装"
            fi
        fi
    done
}

install_argon_package()
{
    prepare_argon_21_dependencies

    theme_progress 28 "正在下载 Argon Theme..."; printf "\n"
    smart_download_release "$ARGON_THEME_URL" "$ARGON_THEME_FILE" || {
        _theme_error "Argon Theme 下载失败"; return 1;
    }

    rm -f "$ARGON_CONFIG_FILE" "$ARGON_LANG_FILE"

    if [ -n "$ARGON_CONFIG_URL" ]; then
        theme_progress 42 "正在下载 Argon Config..."; printf "\n"
        smart_download_release "$ARGON_CONFIG_URL" "$ARGON_CONFIG_FILE" || {
            _theme_warn "Argon Config 下载失败，将继续安装主题"; rm -f "$ARGON_CONFIG_FILE";
        }
    fi

    if [ -n "$ARGON_LANG_URL" ]; then
        theme_progress 48 "正在下载 Argon 中文包..."; printf "\n"
        smart_download_release "$ARGON_LANG_URL" "$ARGON_LANG_FILE" || rm -f "$ARGON_LANG_FILE"
    fi

    theme_progress 58 "正在安装 Argon..."
    printf "\n===== Argon Install =====\n" >>"$THEME_LOG"

    if [ "$PKG_MANAGER" = "opkg" ]; then
        if [ "$OPENWRT_MAJOR" = "21" ] || [ "$OPENWRT_MAJOR" = "22" ] || [ "$OPENWRT_MAJOR" = "23" ]; then
            opkg install --force-downgrade "$ARGON_THEME_FILE" >>"$THEME_LOG" 2>&1
        else
            opkg install "$ARGON_THEME_FILE" >>"$THEME_LOG" 2>&1
        fi
        THEME_INSTALL_RESULT=$?

        if [ -s "$ARGON_CONFIG_FILE" ]; then
            opkg install "$ARGON_CONFIG_FILE" >>"$THEME_LOG" 2>&1 || _theme_warn "Argon Config 安装失败，主题本体不受影响"
        fi
        if [ -s "$ARGON_LANG_FILE" ]; then
            opkg install "$ARGON_LANG_FILE" >>"$THEME_LOG" 2>&1 || true
        fi

    elif [ "$PKG_MANAGER" = "apk" ]; then
        apk add --allow-untrusted "$ARGON_THEME_FILE" >>"$THEME_LOG" 2>&1
        THEME_INSTALL_RESULT=$?

        [ -s "$ARGON_CONFIG_FILE" ] && apk add --allow-untrusted "$ARGON_CONFIG_FILE" >>"$THEME_LOG" 2>&1 || true
        [ -s "$ARGON_LANG_FILE" ] && apk add --allow-untrusted "$ARGON_LANG_FILE" >>"$THEME_LOG" 2>&1 || true
    else
        return 1
    fi

    [ "$THEME_INSTALL_RESULT" -eq 0 ] || { _theme_error "Argon Theme 包安装失败"; return 1; }
    verify_argon_install || { _theme_error "Argon 安装后验证失败"; return 1; }

    _theme_ok "Argon Theme 安装成功"
    return 0
}

set_argon_default()
{
    verify_argon_install || return 1

    [ -d /www/luci-static/bootstrap ] &&
        uci set luci.themes.Bootstrap='/luci-static/bootstrap' >>"$THEME_LOG" 2>&1

    uci set luci.main.theme='argon' >>"$THEME_LOG" 2>&1
    uci set luci.main.mediaurlbase='/luci-static/argon' >>"$THEME_LOG" 2>&1
    uci set luci.themes.Argon='/luci-static/argon' >>"$THEME_LOG" 2>&1
    uci commit luci >>"$THEME_LOG" 2>&1

    [ "$(uci -q get luci.main.mediaurlbase)" = "/luci-static/argon" ] || return 1
    return 0
}

verify_quickstart_install()
{
    [ "$PKG_MANAGER" = "opkg" ] || return 1
    package_installed "quickstart" &&
    package_installed "luci-app-quickstart" &&
    package_installed "luci-i18n-quickstart-zh-cn"
}

ensure_is_opkg()
{
    IS_OPKG_BIN=""
    if command -v is-opkg >/dev/null 2>&1; then IS_OPKG_BIN="$(command -v is-opkg)"; return 0; fi
    [ -x /bin/is-opkg ] && { IS_OPKG_BIN="/bin/is-opkg"; return 0; }
    [ -x /usr/bin/is-opkg ] && { IS_OPKG_BIN="/usr/bin/is-opkg"; return 0; }

    IS_OPKG_BIN="${THEME_TMP}/is-opkg"
    _theme_info "正在直连下载 iStore 官方 is-opkg..."
    download_direct "$IS_OPKG_URL" "$IS_OPKG_BIN" || { _theme_error "iStore 官方 is-opkg 下载失败"; return 1; }
    chmod 755 "$IS_OPKG_BIN" >>"$THEME_LOG" 2>&1
}

apply_quickstart_config()
{
    rm -f "$QUICKSTART_CONFIG_TMP" 2>/dev/null
    download_direct "$QUICKSTART_CONFIG_URL" "$QUICKSTART_CONFIG_TMP" || {
        _theme_warn "QuickStart iStoreOS 风格配置下载失败，保留默认配置"; return 0;
    }

    if [ -f /etc/config/quickstart ] && [ ! -f "$QUICKSTART_CONFIG_BAK" ]; then
        cp -f /etc/config/quickstart "$QUICKSTART_CONFIG_BAK" >>"$THEME_LOG" 2>&1 || true
    fi

    cp -f "$QUICKSTART_CONFIG_TMP" /etc/config/quickstart >>"$THEME_LOG" 2>&1 || return 0

    if ! uci -q show quickstart >/dev/null 2>&1; then
        _theme_warn "QuickStart 风格配置不兼容当前版本"
        [ -f "$QUICKSTART_CONFIG_BAK" ] &&
            cp -f "$QUICKSTART_CONFIG_BAK" /etc/config/quickstart >>"$THEME_LOG" 2>&1 || true
        return 0
    fi

    _theme_ok "QuickStart iStoreOS 风格配置已应用"
    return 0
}

install_quickstart()
{
    if [ "$PKG_MANAGER" != "opkg" ]; then
        _theme_warn "当前为 APK 系统，已自动跳过 OPKG QuickStart"
        return 0
    fi

    if verify_quickstart_install; then
        _theme_ok "首页 + 网络向导已安装"; apply_quickstart_config; return 0
    fi

    ensure_is_opkg || return 1

    printf "\n===== QuickStart Install =====\n" >>"$THEME_LOG"
    theme_progress 70 "正在更新 QuickStart 索引..."
    "$IS_OPKG_BIN" update >>"$THEME_LOG" 2>&1 || _theme_warn "iStore 索引更新返回异常，继续安装"

    theme_progress 78 "正在安装首页和网络向导..."
    "$IS_OPKG_BIN" install luci-i18n-quickstart-zh-cn >>"$THEME_LOG" 2>&1
    INSTALL_RESULT=$?

    if [ "$INSTALL_RESULT" -ne 0 ]; then
        "$IS_OPKG_BIN" install luci-i18n-quickstart-zh-cn --force-depends >>"$THEME_LOG" 2>&1
    fi

    verify_quickstart_install || { _theme_error "首页 + 网络向导安装失败"; return 1; }

    theme_progress 86 "正在配置首页和网络向导..."
    apply_quickstart_config
    _theme_ok "首页 + 网络向导安装成功"
    return 0
}

refresh_theme_luci()
{
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-templatecache /tmp/luci-*cache* >/dev/null 2>&1
    [ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart >>"$THEME_LOG" 2>&1
    [ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd restart >>"$THEME_LOG" 2>&1
    return 0
}

verify_argon_active()
{
    verify_argon_install || return 1
    [ "$(uci -q get luci.main.mediaurlbase)" = "/luci-static/argon" ] || return 1
    return 0
}

install_theme()
{
    printf "\n"
    printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"
    printf "%b\n" "${BLUE}║${GREEN}        iStoreOS 风格一键安装         ${BLUE}║${RESET}"
    printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"
    printf "\n"

    [ "$(id -u 2>/dev/null)" = "0" ] || { _theme_error "请使用 root 用户运行"; return 1; }

    cleanup_theme_all
    mkdir -p "$THEME_TMP" || { _theme_error "无法创建临时目录"; return 1; }
    touch "$THEME_LOG" 2>/dev/null
    trap 'theme_interrupt' INT TERM

    theme_progress 5 "正在检测运行环境..."
    if ! check_theme_runtime || ! detect_theme_system || ! select_argon_compat || ! check_theme_disk_space; then
        printf "\n"; cleanup_theme_temp; trap - INT TERM; return 1
    fi

    printf "\n"
    theme_progress 15 "正在获取兼容 Argon..."; printf "\n"

    if ! fetch_argon_release; then
        _theme_error "Argon Release 获取失败"; show_theme_error_log; cleanup_theme_temp; trap - INT TERM; return 1
    fi

    if ! install_argon_package; then
        printf "\n"; _theme_error "Argon 安装失败"; rollback_bootstrap; show_theme_error_log
        cleanup_theme_temp; trap - INT TERM; return 1
    fi

    theme_progress 64 "正在设置 Argon 默认主题..."
    if ! set_argon_default; then
        printf "\n"; _theme_error "Argon 默认主题设置失败"; rollback_bootstrap; show_theme_error_log
        cleanup_theme_temp; trap - INT TERM; return 1
    fi

    theme_progress 67 "正在准备首页和网络向导..."
    install_quickstart || _theme_warn "Argon 已成功安装，但 QuickStart 安装失败"

    theme_progress 93 "正在刷新 LuCI..."
    refresh_theme_luci
    sleep 1

    theme_progress 97 "正在进行最终验证..."
    if ! verify_argon_active; then
        printf "\n"; _theme_error "Argon 最终验证失败"; rollback_bootstrap; show_theme_error_log
        cleanup_theme_temp; trap - INT TERM; return 1
    fi

    theme_progress 100 "iStoreOS 风格安装完成"
    printf "\n\n"

    ARGON_INSTALLED_VERSION="$(get_package_version luci-theme-argon)"
    ARGON_CONFIG_VERSION="$(get_package_version luci-app-argon-config)"
    QUICKSTART_VERSION=""
    [ "$PKG_MANAGER" = "opkg" ] && QUICKSTART_VERSION="$(get_package_version luci-app-quickstart)"

    cleanup_theme_temp
    trap - INT TERM

    _theme_ok "Argon 主题安装成功"
    _theme_info "OpenWrt         : $OPENWRT_VERSION"
    _theme_info "兼容策略        : OpenWrt ${OPENWRT_MAJOR}.x"
    _theme_info "Argon Release   : $ARGON_RELEASE_TAG"
    [ -n "$ARGON_INSTALLED_VERSION" ] && _theme_info "Argon Version   : $ARGON_INSTALLED_VERSION"
    [ -n "$ARGON_CONFIG_VERSION" ] && _theme_info "Argon Config    : $ARGON_CONFIG_VERSION"
    [ -n "$QUICKSTART_VERSION" ] && _theme_info "QuickStart      : $QUICKSTART_VERSION"
    _theme_info "Package         : $ARGON_PACKAGE_TYPE"
    _theme_info "Argon 下载      : GH01-GH06 + DIRECT 自动测速"
    _theme_info "Bootstrap       : 已保留作为回退主题"
    _theme_info "当前默认主题    : /luci-static/argon"
    _theme_info "如页面未更新，请 Ctrl+F5 或重新登录 LuCI"

    printf "\n"
    rm -f "$THEME_LOG" 2>/dev/null
    return 0
}

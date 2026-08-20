#!/bin/sh

# ============================================================
# Open-Pro-Installer
# GL-E5800 Screen zh-CN Smart Installer
# BusyBox / OpenWrt /bin/sh Compatible
# ============================================================

E5800_REPO="tutugreen/gl-screen-e5800-i18n-zh-cn"
E5800_PACKAGE="gl-screen-e5800-i18n-zh-cn"

E5800_TMP="/tmp/openpro_e5800_screen_zh"
E5800_LOG="/tmp/openpro_e5800_screen_zh.log"
E5800_RELEASE_JSON="$E5800_TMP/release.json"
E5800_ASSET_LIST="$E5800_TMP/assets.list"
E5800_EXPANDED_HTML="$E5800_TMP/expanded_assets.html"
E5800_ROUTE_FILE="$E5800_TMP/routes"
E5800_TEST_DIR="$E5800_TMP/test"
E5800_IPK="$E5800_TMP/e5800-screen-zh.ipk"

E5800_VERSION=""
E5800_ASSET_URL=""

E5800_NODES="
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
GH04|https://cdn.akaere.online/
GH05|https://github.mxw.qzz.io/
GH06|https://gh.07150721.xyz/
DIRECT|
"

_e58_info(){ printf '\033[1;92m[INFO]\033[0m %s\n' "$*"; }
_e58_ok(){ printf '\033[1;92m[OK]\033[0m %s\n' "$*"; }
_e58_warn(){ printf '\033[1;93m[WARN]\033[0m %s\n' "$*"; }
_e58_error(){ printf '\033[1;91m[ERROR]\033[0m %s\n' "$*"; }

_e58_show_log()
{
    printf '\n\033[1;91m========== E5800 SCREEN ERROR ==========\033[0m\n'
    if [ -s "$E5800_LOG" ]; then
        tail -n 100 "$E5800_LOG"
    else
        printf '没有可用错误日志\n'
    fi
    printf '\033[1;91m========================================\033[0m\n\n'
}

_e58_cleanup()
{
    rm -rf "$E5800_TMP" 2>/dev/null
    rm -f /tmp/e5800-screen-zh.ipk 2>/dev/null
}

_e58_check_runtime()
{
    MISSING=""
    for CMD in awk sed grep cut sort head tail curl cp basename mkdir cat df wc opkg; do
        command -v "$CMD" >/dev/null 2>&1 || MISSING="$MISSING $CMD"
    done
    [ -z "$MISSING" ] || {
        _e58_error "系统缺少必要命令:$MISSING"
        return 1
    }
}

_e58_check_device()
{
    MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"

    if [ -z "$MODEL" ] && command -v ubus >/dev/null 2>&1 && command -v jsonfilter >/dev/null 2>&1; then
        MODEL="$(ubus call system board 2>/dev/null | jsonfilter -e '@.model' 2>/dev/null)"
    fi

    [ -n "$MODEL" ] || MODEL="Unknown"

    _e58_info "设备型号：$MODEL"

    case "$MODEL" in
        *E5800*|*e5800*)
            return 0
            ;;
        *)
            _e58_error "此模块仅适用于 GL.iNet GL-E5800"
            return 1
            ;;
    esac
}

_e58_check_space()
{
    FREE_KB="$(df -k /tmp 2>/dev/null | tail -n 1 | awk '{print $4}')"
    case "$FREE_KB" in ''|*[!0-9]*) FREE_KB=0;; esac

    FREE_MB=$((FREE_KB / 1024))
    _e58_info "临时空间：${FREE_MB} MB"

    [ "$FREE_MB" -ge 40 ] || {
        _e58_error "临时空间不足，建议至少保留 40 MB"
        return 1
    }
}

_e58_extract_api_assets()
{
    rm -f "$E5800_ASSET_LIST"

    if command -v jsonfilter >/dev/null 2>&1; then
        jsonfilter \
            -i "$E5800_RELEASE_JSON" \
            -e '@.assets[*].browser_download_url' \
            2>/dev/null \
            > "$E5800_ASSET_LIST"
    else
        grep '"browser_download_url"' "$E5800_RELEASE_JSON" |
            sed 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/' \
            > "$E5800_ASSET_LIST"
    fi

    [ -s "$E5800_ASSET_LIST" ]
}

_e58_parse_expanded_assets()
{
    rm -f "$E5800_ASSET_LIST"

    sed 's/href=/\
href=/g' "$E5800_EXPANDED_HTML" |
        sed -n 's/.*href="\([^"]*\/releases\/download\/[^"]*\)".*/\1/p' |
        sed 's/&amp;/\&/g' |
        while IFS= read -r P
        do
            case "$P" in
                http://*|https://*) printf '%s\n' "$P" ;;
                /*) printf 'https://github.com%s\n' "$P" ;;
            esac
        done |
        awk '!seen[$0]++' \
        > "$E5800_ASSET_LIST"

    [ -s "$E5800_ASSET_LIST" ]
}

_e58_get_release()
{
    mkdir -p "$E5800_TMP" || return 1

    rm -f \
        "$E5800_RELEASE_JSON" \
        "$E5800_ASSET_LIST" \
        "$E5800_EXPANDED_HTML"

    E5800_VERSION=""
    E5800_ASSET_URL=""
    API_OK=0

    _e58_info "正在获取最新 E5800 屏幕中文包..."

    HTTP_CODE="$(
        curl -4 \
            -L \
            -sS \
            --connect-timeout 10 \
            --max-time 30 \
            -H 'Accept: application/vnd.github+json' \
            -H 'User-Agent: Open-Pro-Installer' \
            -o "$E5800_RELEASE_JSON" \
            -w '%{http_code}' \
            "https://api.github.com/repos/${E5800_REPO}/releases/latest"
    )"
    RC=$?

    if [ "$RC" -eq 0 ] &&
       [ "$HTTP_CODE" = "200" ] &&
       [ -s "$E5800_RELEASE_JSON" ]; then

        if command -v jsonfilter >/dev/null 2>&1; then
            E5800_VERSION="$(
                jsonfilter \
                    -i "$E5800_RELEASE_JSON" \
                    -e '@.tag_name' \
                    2>/dev/null
            )"
        else
            E5800_VERSION="$(
                grep '"tag_name"' "$E5800_RELEASE_JSON" |
                head -n 1 |
                sed 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/'
            )"
        fi

        if _e58_extract_api_assets && [ -n "$E5800_VERSION" ]; then
            API_OK=1
        fi
    else
        case "$HTTP_CODE" in
            403) _e58_warn "GitHub API 已触发访问限制" ;;
            429) _e58_warn "GitHub API 请求过于频繁" ;;
            000|"") _e58_warn "GitHub API 当前无法连接" ;;
            *) _e58_warn "GitHub API 返回 HTTP $HTTP_CODE" ;;
        esac
    fi

    if [ "$API_OK" -ne 1 ]; then
        _e58_info "正在切换 GitHub Release 页面模式..."

        RELEASE_URL="$(
            curl -4 \
                -L \
                -sS \
                --connect-timeout 10 \
                --max-time 30 \
                -H 'User-Agent: Mozilla/5.0' \
                -o /dev/null \
                -w '%{url_effective}' \
                "https://github.com/${E5800_REPO}/releases/latest"
        )"
        RC=$?

        [ "$RC" -eq 0 ] && [ -n "$RELEASE_URL" ] || {
            _e58_error "无法访问 Release 页面"
            return 1
        }

        case "$RELEASE_URL" in
            */releases/tag/*)
                E5800_VERSION="$(
                    printf '%s' "$RELEASE_URL" |
                    sed 's#^.*/releases/tag/##' |
                    cut -d '?' -f1 |
                    cut -d '#' -f1
                )"
                ;;
            *)
                E5800_VERSION=""
                ;;
        esac

        [ -n "$E5800_VERSION" ] || {
            _e58_error "无法识别最新 Release 版本"
            return 1
        }

        EXPANDED_URL="https://github.com/${E5800_REPO}/releases/expanded_assets/${E5800_VERSION}"

        curl -4 \
            -L \
            -f \
            -sS \
            --connect-timeout 10 \
            --max-time 30 \
            -H 'User-Agent: Mozilla/5.0' \
            "$EXPANDED_URL" \
            -o "$E5800_EXPANDED_HTML" \
            >>"$E5800_LOG" 2>&1 || {
                _e58_error "无法获取 Release Assets"
                return 1
            }

        _e58_parse_expanded_assets || {
            _e58_error "Release 页面没有解析到 IPK"
            return 1
        }
    fi

    E5800_ASSET_URL="$(
        grep '/gl-screen-e5800-i18n-zh-cn_' "$E5800_ASSET_LIST" |
        grep '_all\.ipk$' |
        head -n 1
    )"

    if [ -z "$E5800_ASSET_URL" ]; then
        E5800_ASSET_URL="$(
            grep -i 'gl-screen-e5800-i18n-zh-cn' "$E5800_ASSET_LIST" |
            grep '\.ipk$' |
            head -n 1
        )"
    fi

    [ -n "$E5800_ASSET_URL" ] || {
        _e58_error "没有找到 E5800 屏幕中文 IPK"
        {
            printf '\n===== E5800 ASSETS =====\n'
            cat "$E5800_ASSET_LIST"
            printf '\n========================\n'
        } >> "$E5800_LOG"
        return 1
    }

    _e58_ok "已获取最新版本：$E5800_VERSION"
    _e58_info "安装包：$(basename "$E5800_ASSET_URL")"
}

_e58_build_url()
{
    if [ -z "$1" ]; then
        printf '%s' "$2"
    else
        printf '%s%s' "$1" "$2"
    fi
}

_e58_speed_mb()
{
    awk -v s="$1" 'BEGIN{if(s<=0)printf "0.00"; else printf "%.2f",s/1024/1024}'
}

_e58_test_route()
{
    NAME="$1"
    PREFIX="$2"
    ORIGINAL="$3"
    RESULT="$4"

    URL="$(_e58_build_url "$PREFIX" "$ORIGINAL")"

    DATA="$(
        curl -4 \
            -L \
            -sS \
            --connect-timeout 4 \
            --max-time 6 \
            -o /dev/null \
            -w '%{http_code}|%{time_starttransfer}|%{speed_download}' \
            "$URL" \
            2>/dev/null
    )"
    RC=$?

    [ "$RC" -eq 0 ] || [ "$RC" -eq 28 ] || {
        printf '%s|FAIL\n' "$NAME" > "$RESULT"
        return
    }

    HTTP="$(printf '%s' "$DATA" | cut -d '|' -f1)"
    TTFB="$(printf '%s' "$DATA" | cut -d '|' -f2)"
    SPEED="$(printf '%s' "$DATA" | cut -d '|' -f3)"

    case "$HTTP" in
        200|206) ;;
        *)
            printf '%s|FAIL\n' "$NAME" > "$RESULT"
            return
            ;;
    esac

    TTFB_MS="$(
        awk -v t="$TTFB" \
            'BEGIN{if(t==""||t!~/^[0-9.]+$/)print 999999; else printf "%d",t*1000}'
    )"

    SPEED_INT="$(
        awk -v s="$SPEED" \
            'BEGIN{if(s>0)printf "%d",s; else print 0}'
    )"

    [ "$SPEED_INT" -gt 0 ] || {
        printf '%s|FAIL\n' "$NAME" > "$RESULT"
        return
    }

    SCORE="$(
        awk -v t="$TTFB_MS" -v s="$SPEED_INT" \
            'BEGIN{printf "%d",t+(10485760/s)*1000}'
    )"

    printf '%s|OK|%s|%s|%s|%s\n' \
        "$NAME" "$PREFIX" "$TTFB_MS" "$SPEED_INT" "$SCORE" \
        > "$RESULT"
}

_e58_prepare_routes()
{
    ORIGINAL="$1"

    rm -rf "$E5800_TEST_DIR"
    mkdir -p "$E5800_TEST_DIR" || return 1
    rm -f "$E5800_ROUTE_FILE"

    printf '\n'
    _e58_info "正在并行测试下载线路..."
    printf '\n'

    for NAME in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT
    do
        PREFIX="$(
            printf '%s\n' "$E5800_NODES" |
            awk -F '|' -v n="$NAME" '$1==n{print $2;exit}'
        )"

        _e58_test_route \
            "$NAME" \
            "$PREFIX" \
            "$ORIGINAL" \
            "$E5800_TEST_DIR/$NAME" &
    done

    wait

    printf '%-8s %-12s %-14s %s\n' \
        "线路" "首包" "下载速度" "状态"

    printf '%-8s %-12s %-14s %s\n' \
        "--------" "------------" "--------------" "------"

    for NAME in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT
    do
        FILE="$E5800_TEST_DIR/$NAME"

        if [ ! -s "$FILE" ] ||
           [ "$(cut -d '|' -f2 "$FILE")" != "OK" ]; then
            printf '%-8s %-12s %-14s \033[1;91m%s\033[0m\n' \
                "$NAME" "----" "----" "不可用"
            continue
        fi

        PREFIX="$(cut -d '|' -f3 "$FILE")"
        TTFB="$(cut -d '|' -f4 "$FILE")"
        SPEED="$(cut -d '|' -f5 "$FILE")"
        SCORE="$(cut -d '|' -f6 "$FILE")"

        printf '%-8s %-12s %-14s \033[1;92m%s\033[0m\n' \
            "$NAME" \
            "${TTFB} ms" \
            "$(_e58_speed_mb "$SPEED") MB/s" \
            "可用"

        printf '%s|%s|%s|%s|%s\n' \
            "$SCORE" "$NAME" "$PREFIX" "$TTFB" "$SPEED" \
            >> "$E5800_ROUTE_FILE"
    done

    rm -rf "$E5800_TEST_DIR"

    [ -s "$E5800_ROUTE_FILE" ] || {
        _e58_warn "测速线路全部不可用，将尝试官方直连"
        return 1
    }

    sort -n \
        -t '|' \
        -k1,1 \
        "$E5800_ROUTE_FILE" \
        -o "$E5800_ROUTE_FILE"

    BEST="$(head -n 1 "$E5800_ROUTE_FILE")"

    _e58_ok "最佳线路：$(printf '%s' "$BEST" | cut -d '|' -f2)"
    _e58_info "首包时间：$(printf '%s' "$BEST" | cut -d '|' -f4) ms"
    _e58_info "下载速度：$(_e58_speed_mb "$(printf '%s' "$BEST" | cut -d '|' -f5)") MB/s"

    printf '\n'
}

_e58_download()
{
    ORIGINAL="$1"

    rm -f "$E5800_IPK"

    if [ -s "$E5800_ROUTE_FILE" ]; then
        while IFS='|' read -r SCORE NAME PREFIX TTFB SPEED
        do
            URL="$(_e58_build_url "$PREFIX" "$ORIGINAL")"

            _e58_info "正在使用线路：$NAME"

            if curl -4 \
                -L \
                -f \
                -sS \
                --connect-timeout 10 \
                --max-time 300 \
                --retry 1 \
                --retry-delay 1 \
                -o "$E5800_IPK" \
                "$URL" \
                >>"$E5800_LOG" 2>&1
            then
                if [ -s "$E5800_IPK" ]; then
                    _e58_ok "下载完成（线路：$NAME）"
                    return 0
                fi
            fi

            rm -f "$E5800_IPK"
        done < "$E5800_ROUTE_FILE"
    fi

    _e58_info "正在尝试 GitHub 官方直连..."

    curl -4 \
        -L \
        -f \
        -sS \
        --connect-timeout 10 \
        --max-time 300 \
        --retry 1 \
        --retry-delay 1 \
        -o "$E5800_IPK" \
        "$ORIGINAL" \
        >>"$E5800_LOG" 2>&1 && \
        [ -s "$E5800_IPK" ]
}

_e58_installed()
{
    opkg status "$E5800_PACKAGE" 2>/dev/null |
        grep -q 'Status:.*installed'
}

_e58_install_ipk()
{
    cp "$E5800_IPK" /tmp/e5800-screen-zh.ipk \
        >>"$E5800_LOG" 2>&1 || return 1

    _e58_info "正在安装 E5800 屏幕中文包..."

    if _e58_installed; then
        opkg install \
            --force-reinstall \
            /tmp/e5800-screen-zh.ipk \
            >>"$E5800_LOG" 2>&1
    else
        opkg install \
            /tmp/e5800-screen-zh.ipk \
            >>"$E5800_LOG" 2>&1
    fi

    RC=$?

    rm -f /tmp/e5800-screen-zh.ipk

    if [ "$RC" -ne 0 ] && ! _e58_installed; then
        return 1
    fi

    _e58_installed || return 1

    _e58_ok "E5800 屏幕中文包安装完成"
}

install_e5800_screen_zh()
{
    printf '\n'
    printf '\033[1;94m╔══════════════════════════════════════╗\033[0m\n'
    printf '\033[1;94m║\033[1;92m      E5800 屏幕中文一键安装          \033[1;94m║\033[0m\n'
    printf '\033[1;94m╚══════════════════════════════════════╝\033[0m\n'
    printf '\n'

    [ "$(id -u 2>/dev/null)" = "0" ] || {
        _e58_error "请使用 root 用户运行"
        return 1
    }

    _e58_cleanup
    rm -f "$E5800_LOG" 2>/dev/null

    mkdir -p "$E5800_TMP" || {
        _e58_error "无法创建临时目录"
        return 1
    }

    : > "$E5800_LOG"

    _e58_check_runtime || return 1
    _e58_check_device || return 1
    _e58_check_space || return 1

    _e58_get_release || {
        _e58_show_log
        _e58_cleanup
        return 1
    }

    _e58_prepare_routes "$E5800_ASSET_URL" || true

    _e58_download "$E5800_ASSET_URL" || {
        _e58_error "下载失败"
        _e58_show_log
        _e58_cleanup
        return 1
    }

    _e58_install_ipk || {
        _e58_error "安装失败"
        _e58_show_log
        _e58_cleanup
        return 1
    }

    INSTALLED_VERSION="$(
        opkg status "$E5800_PACKAGE" 2>/dev/null |
        sed -n 's/^Version:[[:space:]]*//p' |
        head -n 1
    )"

    _e58_cleanup

    printf '\n'
    _e58_ok "E5800 屏幕中文安装完成"
    _e58_info "Release：$E5800_VERSION"
    [ -n "$INSTALLED_VERSION" ] &&
        _e58_info "Installed：$INSTALLED_VERSION"
    _e58_info "日志：$E5800_LOG"
    _e58_info "如屏幕未立即刷新，请重启设备"
    printf '\n'

    return 0
}

smartdns_get_release()
{
    mkdir -p "$SMARTDNS_TMP" || return 1

    rm -f \
        "$SMARTDNS_RELEASE_JSON" \
        "$SMARTDNS_ASSET_LIST" \
        "$SMARTDNS_TMP/expanded_assets.html" \
        "$SMARTDNS_TMP/release_headers"

    SMARTDNS_VERSION=""
    SMARTDNS_MAIN_URL=""
    SMARTDNS_LUCI_URL=""

    _sd_info "正在获取 SmartDNS 官方 Release..."

    # ========================================================
    # 第一方案：GitHub API
    # ========================================================

    API_OK=0

    HTTP_CODE="$(
        curl -4 \
            -L \
            -sS \
            --connect-timeout 10 \
            --max-time 30 \
            -H 'Accept: application/vnd.github+json' \
            -H 'User-Agent: Open-Pro-Installer' \
            -o "$SMARTDNS_RELEASE_JSON" \
            -w '%{http_code}' \
            "https://api.github.com/repos/${SMARTDNS_REPO}/releases/latest"
    )"

    CURL_RC=$?

    if [ "$CURL_RC" -eq 0 ] &&
       [ "$HTTP_CODE" = "200" ] &&
       [ -s "$SMARTDNS_RELEASE_JSON" ]
    then

        _sd_ok "GitHub API 连接成功"

        # ----------------------------------------------------
        # 获取 Release Tag
        # ----------------------------------------------------

        if command -v jsonfilter >/dev/null 2>&1
        then

            SMARTDNS_VERSION="$(
                jsonfilter \
                    -i "$SMARTDNS_RELEASE_JSON" \
                    -e '@.tag_name' \
                    2>/dev/null
            )"

        else

            SMARTDNS_VERSION="$(
                grep '"tag_name"' "$SMARTDNS_RELEASE_JSON" |
                head -n 1 |
                sed 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/'
            )"

        fi

        # ----------------------------------------------------
        # 获取 Assets
        # ----------------------------------------------------

        if smartdns_extract_assets
        then

            if [ -n "$SMARTDNS_VERSION" ] &&
               [ -s "$SMARTDNS_ASSET_LIST" ]
            then
                API_OK=1
            fi

        fi

    else

        case "$HTTP_CODE" in

            403)
                _sd_warn "GitHub API 已触发访问限制"
                ;;

            429)
                _sd_warn "GitHub API 请求过于频繁"
                ;;

            000)
                _sd_warn "GitHub API 当前无法连接"
                ;;

            *)
                _sd_warn "GitHub API 返回 HTTP $HTTP_CODE"
                ;;

        esac

    fi


    # ========================================================
    # 第二方案：
    #
    # GitHub API 失败 / 403 / Rate Limit
    #
    # 不再依赖 API
    #
    # releases/latest
    #        ↓
    # 获取真实 Release Tag
    #        ↓
    # expanded_assets
    #        ↓
    # 获取全部安装包
    # ========================================================

    if [ "$API_OK" -ne 1 ]
    then

        _sd_info "正在切换 GitHub Release 页面模式..."

        RELEASE_URL="$(
            curl -4 \
                -L \
                -sS \
                --connect-timeout 10 \
                --max-time 30 \
                -o /dev/null \
                -w '%{url_effective}' \
                "https://github.com/${SMARTDNS_REPO}/releases/latest"
        )"

        CURL_RC=$?

        if [ "$CURL_RC" -ne 0 ] ||
           [ -z "$RELEASE_URL" ]
        then

            _sd_error "无法访问 SmartDNS Release 页面"

            {
                printf '\n'
                printf '===== SMARTDNS RELEASE FALLBACK =====\n'
                printf 'GitHub API HTTP: %s\n' "$HTTP_CODE"
                printf 'Release URL: %s\n' "$RELEASE_URL"
                printf '=====================================\n'
            } >>"$SMARTDNS_LOG"

            return 1

        fi


        # ----------------------------------------------------
        # releases/latest 最终应该跳转：
        #
        # https://github.com/pymumu/smartdns/releases/tag/ReleaseXX
        # ----------------------------------------------------

        case "$RELEASE_URL" in

            */releases/tag/*)

                SMARTDNS_VERSION="$(
                    printf '%s' "$RELEASE_URL" |
                    sed 's#^.*/releases/tag/##' |
                    cut -d '?' -f1 |
                    cut -d '#' -f1
                )"

                ;;

            *)

                SMARTDNS_VERSION=""

                ;;

        esac


        if [ -z "$SMARTDNS_VERSION" ]
        then

            _sd_error "无法识别 SmartDNS 最新 Release 版本"

            {
                printf '\n'
                printf '===== SMARTDNS RELEASE URL =====\n'
                printf '%s\n' "$RELEASE_URL"
                printf '================================\n'
            } >>"$SMARTDNS_LOG"

            return 1

        fi


        _sd_ok "SmartDNS 最新版本获取成功"

        _sd_info "Release Version  : $SMARTDNS_VERSION"


        # ====================================================
        # 获取 expanded_assets
        # ====================================================

        EXPANDED_URL="https://github.com/${SMARTDNS_REPO}/releases/expanded_assets/${SMARTDNS_VERSION}"

        EXPANDED_FILE="$SMARTDNS_TMP/expanded_assets.html"


        _sd_info "正在获取 SmartDNS Release Assets..."


        if ! curl -4 \
            -L \
            -f \
            -sS \
            --connect-timeout 10 \
            --max-time 30 \
            -H 'User-Agent: Mozilla/5.0' \
            "$EXPANDED_URL" \
            -o "$EXPANDED_FILE"
        then

            _sd_error "无法获取 SmartDNS Release Assets"

            return 1

        fi


        if [ ! -s "$EXPANDED_FILE" ]
        then

            _sd_error "SmartDNS Release Assets 页面为空"

            return 1

        fi


        # ====================================================
        # 从 HTML 中提取：
        #
        # /pymumu/smartdns/releases/download/ReleaseXX/xxx.ipk
        #
        # BusyBox grep 不一定支持 -o，
        # 所以这里故意不用 grep -o。
        # ====================================================

        sed \
            's/href=/\
href=/g' \
            "$EXPANDED_FILE" |
            sed -n \
            's/.*href="\([^"]*\/releases\/download\/[^"]*\)".*/\1/p' |
            sed \
            's/&amp;/\&/g' |
            while IFS= read -r ASSET_PATH
            do

                case "$ASSET_PATH" in

                    http://*|https://*)

                        printf '%s\n' "$ASSET_PATH"
                        ;;

                    /*)

                        printf 'https://github.com%s\n' "$ASSET_PATH"
                        ;;

                esac

            done |
            awk '!seen[$0]++' \
            >"$SMARTDNS_ASSET_LIST"


        if [ ! -s "$SMARTDNS_ASSET_LIST" ]
        then

            _sd_error "Release 页面没有解析到安装包"

            {
                printf '\n'
                printf '===== SMARTDNS EXPANDED ASSETS =====\n'
                cat "$EXPANDED_FILE"
                printf '\n====================================\n'
            } >>"$SMARTDNS_LOG"

            return 1

        fi


        _sd_ok "SmartDNS Release Assets 获取成功"

    else

        _sd_ok "SmartDNS 官方 Release 获取成功"

        [ -n "$SMARTDNS_VERSION" ] &&
            _sd_info "Release Version  : $SMARTDNS_VERSION"

    fi


    # ========================================================
    # 调试：记录所有 Assets
    # ========================================================

    {
        printf '\n'
        printf '===== SMARTDNS ASSET LIST =====\n'
        cat "$SMARTDNS_ASSET_LIST"
        printf '\n===============================\n'
    } >>"$SMARTDNS_LOG"


    # ========================================================
    # SmartDNS 主程序匹配
    #
    # 官方目前命名类似：
    #
    # smartdns.1.x.x.aarch64-openwrt-all.ipk
    #
    # 因此不要使用 OpenWrt：
    #
    # aarch64_cortex-a53
    #
    # 来匹配 Release。
    # ========================================================

    SMARTDNS_MAIN_URL="$(
        grep '/smartdns\.' "$SMARTDNS_ASSET_LIST" |
        grep "\.${SMARTDNS_ARCH}-openwrt-all\.${SMARTDNS_EXT}$" |
        head -n 1
    )"


    # ========================================================
    # 第一层宽松匹配
    # ========================================================

    if [ -z "$SMARTDNS_MAIN_URL" ]
    then

        SMARTDNS_MAIN_URL="$(
            grep -i '/smartdns\.' "$SMARTDNS_ASSET_LIST" |
            grep -i "$SMARTDNS_ARCH" |
            grep -i 'openwrt' |
            grep "\.${SMARTDNS_EXT}$" |
            head -n 1
        )"

    fi


    # ========================================================
    # 第二层宽松匹配
    # ========================================================

    if [ -z "$SMARTDNS_MAIN_URL" ]
    then

        SMARTDNS_MAIN_URL="$(
            grep -i 'smartdns' "$SMARTDNS_ASSET_LIST" |
            grep -vi 'luci-app-smartdns' |
            grep -vi 'source' |
            grep -vi '\.tar\.gz$' |
            grep -i "$SMARTDNS_ARCH" |
            grep "\.${SMARTDNS_EXT}$" |
            head -n 1
        )"

    fi


    # ========================================================
    # LuCI 匹配
    # ========================================================

    SMARTDNS_LUCI_URL=""


    if [ "$SMARTDNS_PKG_MANAGER" = "opkg" ]
    then

        # ----------------------------------------------------
        # OPKG 优先 luci-compat
        # ----------------------------------------------------

        SMARTDNS_LUCI_URL="$(
            grep -i 'luci-app-smartdns' "$SMARTDNS_ASSET_LIST" |
            grep -i 'luci-compat' |
            grep '\.ipk$' |
            grep -vi 'lite' |
            head -n 1
        )"


        # ----------------------------------------------------
        # 没有 compat 使用普通 LuCI
        # ----------------------------------------------------

        if [ -z "$SMARTDNS_LUCI_URL" ]
        then

            SMARTDNS_LUCI_URL="$(
                grep -i 'luci-app-smartdns' "$SMARTDNS_ASSET_LIST" |
                grep '\.ipk$' |
                grep -vi 'lite' |
                head -n 1
            )"

        fi

    else

        # ----------------------------------------------------
        # APK
        # ----------------------------------------------------

        SMARTDNS_LUCI_URL="$(
            grep -i 'luci-app-smartdns' "$SMARTDNS_ASSET_LIST" |
            grep '\.apk$' |
            grep -vi 'lite' |
            head -n 1
        )"

    fi


    # ========================================================
    # 验证 SmartDNS
    # ========================================================

    if [ -z "$SMARTDNS_MAIN_URL" ]
    then

        _sd_error "没有找到当前架构的 SmartDNS 官方安装包"

        {
            printf '\n'
            printf '===== SMARTDNS PACKAGE MATCH DEBUG =====\n'
            printf 'CPU             : %s\n' "$SMARTDNS_CPU"
            printf 'OpenWrt Arch    : %s\n' "$SMARTDNS_ARCH_RAW"
            printf 'Release Arch    : %s\n' "$SMARTDNS_ARCH"
            printf 'Package Manager : %s\n' "$SMARTDNS_PKG_MANAGER"
            printf 'Extension       : %s\n' "$SMARTDNS_EXT"
            printf '\n'
            cat "$SMARTDNS_ASSET_LIST"
            printf '\n'
            printf '========================================\n'
        } >>"$SMARTDNS_LOG"

        return 1

    fi


    # ========================================================
    # 验证 LuCI
    # ========================================================

    if [ -z "$SMARTDNS_LUCI_URL" ]
    then

        _sd_error "没有找到 SmartDNS LuCI 安装包"

        {
            printf '\n'
            printf '===== SMARTDNS LUCI MATCH DEBUG =====\n'
            cat "$SMARTDNS_ASSET_LIST"
            printf '\n'
            printf '=====================================\n'
        } >>"$SMARTDNS_LOG"

        return 1

    fi


    # ========================================================
    # 本地文件
    # ========================================================

    SMARTDNS_MAIN_FILE="$SMARTDNS_TMP/smartdns.$SMARTDNS_EXT"

    SMARTDNS_LUCI_FILE="$SMARTDNS_TMP/luci-app-smartdns.$SMARTDNS_EXT"


    # ========================================================
    # 最终结果
    # ========================================================

    _sd_ok "SmartDNS Release 解析完成"

    [ -n "$SMARTDNS_VERSION" ] &&
        _sd_info "Release Version  : $SMARTDNS_VERSION"

    _sd_info "SmartDNS Asset   : $(basename "$SMARTDNS_MAIN_URL")"

    _sd_info "LuCI Asset       : $(basename "$SMARTDNS_LUCI_URL")"


    return 0
}

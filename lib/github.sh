#!/bin/sh

# ============================================================
# Open-Pro-Installer
# OpenClash Release Resolver
#
# BusyBox / OpenWrt /bin/sh Compatible
#
# 流程：
# 1. 优先读取 1 小时缓存
# 2. 尝试 Open-Pro Worker
# 3. Worker 失败后：
#    DIRECT + GH01-GH06 并行获取 GitHub Release
# 4. 自动解析最新版
# 5. 自动识别 OPKG / APK
# 6. 输出：
#       RELEASE_TAG
#       DOWNLOAD_URL
#       PACKAGE_EXT
# ============================================================


# ============================================================
# Config
# ============================================================

OPENCLASH_WORKER="https://auth.12334123.xyz/openclash"

OPENCLASH_GITHUB_API="https://api.github.com/repos/vernesong/OpenClash/releases/latest"

CACHE_FILE="/tmp/openclash_version"

RELEASE_TMP_DIR="/tmp/openpro_release_resolver"

RELEASE_TIMEOUT=8


# ============================================================
# GitHub Proxy
# ============================================================

RELEASE_NODES="
DIRECT|
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
GH04|https://cdn.akaere.online/
GH05|https://github.mxw.qzz.io/
GH06|https://gh.07150721.xyz/
"


# ============================================================
# Log Compatibility
# ============================================================

_gh_info()
{
    if command -v info >/dev/null 2>&1; then
        info "$*"
    else
        printf '\033[1;92m[INFO]\033[0m %s\n' "$*"
    fi
}


_gh_ok()
{
    printf '\033[1;92m[OK]\033[0m %s\n' "$*"
}


_gh_warn()
{
    if command -v warning >/dev/null 2>&1; then
        warning "$*"
    elif command -v warn >/dev/null 2>&1; then
        warn "$*"
    else
        printf '\033[1;93m[WARN]\033[0m %s\n' "$*"
    fi
}


_gh_error()
{
    if command -v error >/dev/null 2>&1; then
        error "$*"
    else
        printf '\033[1;91m[ERROR]\033[0m %s\n' "$*"
    fi
}


# ============================================================
# Cleanup
# ============================================================

cleanup_release_resolver()
{
    rm -rf "$RELEASE_TMP_DIR" 2>/dev/null
}


# ============================================================
# CURL JSON Download
# ============================================================

download_release_json()
{
    URL="$1"
    OUTPUT="$2"

    rm -f "$OUTPUT"

    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi

    curl \
        -L \
        -sS \
        --connect-timeout 10 \
        --max-time 15 \
        -o "$OUTPUT" \
        "$URL" \
        >/dev/null 2>&1

    RESULT=$?

    if [ "$RESULT" -ne 0 ]; then
        rm -f "$OUTPUT"
        return 1
    fi

    if [ ! -s "$OUTPUT" ]; then
        rm -f "$OUTPUT"
        return 1
    fi

    return 0
}

# ============================================================
# Worker JSON Validate
# ============================================================

validate_worker_json()
{
    FILE="$1"

    [ -s "$FILE" ] || return 1


    grep -q \
        '"success"[[:space:]]*:[[:space:]]*true' \
        "$FILE" \
        2>/dev/null ||
        return 1


    grep -q \
        '"version"' \
        "$FILE" \
        2>/dev/null ||
        return 1


    grep -q \
        'luci-app-openclash' \
        "$FILE" \
        2>/dev/null ||
        return 1


    return 0
}


# ============================================================
# GitHub JSON Validate
# ============================================================

validate_github_json()
{
    FILE="$1"

    [ -s "$FILE" ] || return 1


    grep -q \
        '"tag_name"' \
        "$FILE" \
        2>/dev/null ||
        return 1


    grep -q \
        'luci-app-openclash' \
        "$FILE" \
        2>/dev/null ||
        return 1


    return 0
}


# ============================================================
# Parse Worker JSON
# ============================================================

parse_worker_release()
{
    FILE="$1"

    RELEASE_TAG=""
    RELEASE_IPK=""
    RELEASE_APK=""


    RELEASE_TAG="$(
        sed -n \
            's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            "$FILE" |
        head -n 1
    )"


    RELEASE_IPK="$(
        sed -n \
            's/.*"ipk"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            "$FILE" |
        head -n 1
    )"


    RELEASE_APK="$(
        sed -n \
            's/.*"apk"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            "$FILE" |
        head -n 1
    )"


    select_release_package
}


# ============================================================
# Parse GitHub JSON
# ============================================================

parse_github_release()
{
    FILE="$1"

    RELEASE_TAG=""
    RELEASE_IPK=""
    RELEASE_APK=""


    RELEASE_TAG="$(
        sed -n \
            's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            "$FILE" |
        head -n 1
    )"


    RELEASE_IPK="$(
        grep -o \
            'https://[^"]*luci-app-openclash[^"]*_all\.ipk' \
            "$FILE" \
            2>/dev/null |
        head -n 1
    )"


    if [ -z "$RELEASE_IPK" ]; then

        RELEASE_IPK="$(
            grep -o \
                'https://[^"]*luci-app-openclash[^"]*\.ipk' \
                "$FILE" \
                2>/dev/null |
            head -n 1
        )"

    fi


    RELEASE_APK="$(
        grep -o \
            'https://[^"]*luci-app-openclash[^"]*\.apk' \
            "$FILE" \
            2>/dev/null |
        head -n 1
    )"


    select_release_package
}


# ============================================================
# Select IPK / APK
# ============================================================

select_release_package()
{
    DOWNLOAD_URL=""
    PACKAGE_EXT=""


    if command -v apk >/dev/null 2>&1 &&
       [ -n "$RELEASE_APK" ]
    then

        DOWNLOAD_URL="$RELEASE_APK"

        PACKAGE_EXT="apk"


    elif command -v opkg >/dev/null 2>&1 &&
         [ -n "$RELEASE_IPK" ]
    then

        DOWNLOAD_URL="$RELEASE_IPK"

        PACKAGE_EXT="ipk"


    elif [ -n "$RELEASE_IPK" ]
    then

        DOWNLOAD_URL="$RELEASE_IPK"

        PACKAGE_EXT="ipk"


    elif [ -n "$RELEASE_APK" ]
    then

        DOWNLOAD_URL="$RELEASE_APK"

        PACKAGE_EXT="apk"

    fi


    [ -n "$RELEASE_TAG" ] || return 1

    [ -n "$DOWNLOAD_URL" ] || return 1

    [ -n "$PACKAGE_EXT" ] || return 1


    return 0
}


# ============================================================
# Read Cache
# ============================================================

load_release_cache()
{
    [ -s "$CACHE_FILE" ] || return 1


    CACHE_TIME="$(
        stat -c %Y \
            "$CACHE_FILE" \
            2>/dev/null
    )"


    NOW_TIME="$(
        date +%s \
            2>/dev/null
    )"


    case "$CACHE_TIME" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac


    case "$NOW_TIME" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac


    AGE=$((NOW_TIME - CACHE_TIME))


    if [ "$AGE" -ge 3600 ]; then

        rm -f "$CACHE_FILE"

        return 1
    fi


    # --------------------------------------------------------
    # 新版缓存
    # --------------------------------------------------------

    RELEASE_TAG="$(
        sed -n \
            's/^RELEASE_TAG=//p' \
            "$CACHE_FILE" |
        head -n 1
    )"


    DOWNLOAD_URL="$(
        sed -n \
            's/^DOWNLOAD_URL=//p' \
            "$CACHE_FILE" |
        head -n 1
    )"


    PACKAGE_EXT="$(
        sed -n \
            's/^PACKAGE_EXT=//p' \
            "$CACHE_FILE" |
        head -n 1
    )"


    [ -n "$RELEASE_TAG" ] || return 1

    [ -n "$DOWNLOAD_URL" ] || return 1

    [ -n "$PACKAGE_EXT" ] || return 1


    _gh_ok "使用 OpenClash Release 缓存"

    return 0
}


# ============================================================
# Save Cache
# ============================================================

save_release_cache()
{
    {
        printf 'RELEASE_TAG=%s\n' \
            "$RELEASE_TAG"

        printf 'DOWNLOAD_URL=%s\n' \
            "$DOWNLOAD_URL"

        printf 'PACKAGE_EXT=%s\n' \
            "$PACKAGE_EXT"

    } > "$CACHE_FILE"


    return 0
}


# ============================================================
# Worker
# ============================================================

get_release_from_worker()
{
    WORKER_JSON="${RELEASE_TMP_DIR}/worker.json"


    _gh_info "正在连接 Open-Pro Worker..."


    if ! download_release_json \
        "$OPENCLASH_WORKER" \
        "$WORKER_JSON"
    then

        _gh_warn "Worker 连接失败"

        return 1
    fi


    if ! validate_worker_json \
        "$WORKER_JSON"
    then

        _gh_warn "Worker 返回数据无效"

        return 1
    fi


    if ! parse_worker_release \
        "$WORKER_JSON"
    then

        _gh_warn "Worker Release 解析失败"

        return 1
    fi


    _gh_ok "Worker 获取成功"

    return 0
}


# ============================================================
# 并行 API 请求
# ============================================================

release_parallel_job()
{
    NODE_NAME="$1"
    NODE_PREFIX="$2"

    JSON_FILE="${RELEASE_TMP_DIR}/${NODE_NAME}.json"
    OK_FILE="${RELEASE_TMP_DIR}/${NODE_NAME}.ok"


    if [ "$NODE_NAME" = "DIRECT" ]; then

        API_URL="$OPENCLASH_GITHUB_API"

    else

        API_URL="${NODE_PREFIX}${OPENCLASH_GITHUB_API}"

    fi


    if download_release_json \
        "$API_URL" \
        "$JSON_FILE"
    then

        if validate_github_json \
            "$JSON_FILE"
        then

            printf '%s\n' \
                "$NODE_NAME" \
                > "$OK_FILE"

        fi

    fi
}


# ============================================================
# DIRECT + GH01-GH06 Parallel
# ============================================================

get_release_parallel()
{
    _gh_info "Worker 不可用，启动多线路并行获取..."

    _gh_info "线路：DIRECT + GH01-GH06"


    rm -f \
        "$RELEASE_TMP_DIR"/*.json \
        "$RELEASE_TMP_DIR"/*.ok \
        2>/dev/null


    while IFS='|' read -r \
        NODE_NAME \
        NODE_PREFIX
    do

        [ -n "$NODE_NAME" ] ||
            continue


        release_parallel_job \
            "$NODE_NAME" \
            "$NODE_PREFIX" &

    done <<EOF
DIRECT|
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
GH04|https://cdn.akaere.online/
GH05|https://github.mxw.qzz.io/
GH06|https://gh.07150721.xyz/
EOF


    wait


    # ========================================================
    # 优先顺序
    #
    # DIRECT 成功优先，其次 GH01-GH06
    # ========================================================

    for NODE_NAME in \
        DIRECT \
        GH01 \
        GH02 \
        GH03 \
        GH04 \
        GH05 \
        GH06
    do

        OK_FILE="${RELEASE_TMP_DIR}/${NODE_NAME}.ok"

        JSON_FILE="${RELEASE_TMP_DIR}/${NODE_NAME}.json"


        [ -s "$OK_FILE" ] ||
            continue


        if parse_github_release \
            "$JSON_FILE"
        then

            _gh_ok "Release 获取线路：$NODE_NAME"

            return 0
        fi

    done


    _gh_error "DIRECT + GH01-GH06 全部失败"

    return 1
}


# ============================================================
# Main
#
# 保持原 install.sh 使用的旧函数名称：
#
# get_latest_release
#
# 所以 install.sh 不需要修改。
# ============================================================

get_latest_release()
{
    RELEASE_TAG=""
    DOWNLOAD_URL=""
    PACKAGE_EXT=""


    _gh_info "Getting latest OpenClash release..."


    # ========================================================
    # Prepare
    # ========================================================

    cleanup_release_resolver


    mkdir -p \
        "$RELEASE_TMP_DIR" ||
        return 1


    # ========================================================
    # 1. Cache
    # ========================================================

    if load_release_cache; then

        cleanup_release_resolver

        return 0

    fi


    # ========================================================
    # 2. Worker
    # ========================================================

    if get_release_from_worker; then

        save_release_cache

        cleanup_release_resolver

        _gh_info "Latest Version : $RELEASE_TAG"

        _gh_info "Package Type   : $PACKAGE_EXT"

        _gh_info "Download URL   : $DOWNLOAD_URL"

        return 0

    fi


    # ========================================================
    # 3. DIRECT + GH01-GH06
    # ========================================================

    if get_release_parallel; then

        save_release_cache

        cleanup_release_resolver

        _gh_info "Latest Version : $RELEASE_TAG"

        _gh_info "Package Type   : $PACKAGE_EXT"

        _gh_info "Download URL   : $DOWNLOAD_URL"

        return 0

    fi


    # ========================================================
    # Failed
    # ========================================================

    cleanup_release_resolver


    _gh_error "Failed to download release information."


    return 1
}

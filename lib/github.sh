#!/bin/sh

OPENCLASH_API="https://api.github.com/repos/vernesong/OpenClash/releases/latest"

get_latest_release() {

    info "Getting latest OpenClash release..."

    # 下载 Release 信息
    if ! wget -qO /tmp/openclash_version "$OPENCLASH_API"; then
        error "Failed to download release information."
        return 1
    fi

    # 获取版本号
    RELEASE_TAG="$(jsonfilter -i /tmp/openclash_version -e '@.tag_name')"

    # 自动判断包管理器
    if command -v apk >/dev/null 2>&1; then
        PACKAGE_EXT="apk"
    elif command -v opkg >/dev/null 2>&1; then
        PACKAGE_EXT="ipk"
    else
        error "Unsupported package manager."
        return 1
    fi

    # 获取对应下载地址
    DOWNLOAD_URL="$(
        jsonfilter -i /tmp/openclash_version -e '@.assets[*].browser_download_url' \
        | grep "\.${PACKAGE_EXT}$" \
        | head -n1
    )"

    info "Latest Version : $RELEASE_TAG"
    info "Package Type   : $PACKAGE_EXT"
    info "Download URL   : $DOWNLOAD_URL"
}

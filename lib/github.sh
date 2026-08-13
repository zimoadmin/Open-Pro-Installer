#!/bin/sh

OPENCLASH_API="https://api.github.com/repos/vernesong/OpenClash/releases/latest"

get_latest_release() {

    info "Getting latest OpenClash release..."

    wget -qO /tmp/openclash_version "$OPENCLASH_API"

    if [ ! -f /tmp/openclash_version ]; then
        error "Failed to download release information."
        return 1
    fi

    # 获取版本号
    RELEASE_TAG="$(jsonfilter -i /tmp/openclash_version -e '@.tag_name')"

    # 获取 IPK 下载地址
    DOWNLOAD_URL="$(jsonfilter -i /tmp/openclash_version -e '@.assets[*].browser_download_url' | grep '\.ipk$' | head -n1)"

    info "Latest Version : $RELEASE_TAG"
    info "Download URL : $DOWNLOAD_URL"
}

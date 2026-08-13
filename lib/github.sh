#!/bin/sh

OPENCLASH_API="https://api.github.com/repos/vernesong/OpenClash/releases/latest"

get_latest_release() {

    info "Getting latest OpenClash release..."

    JSON="$(wget -qO- "$OPENCLASH_API")"

    if [ -z "$JSON" ]; then
        error "Failed to connect GitHub API"
        exit 1
    fi

    RELEASE_TAG="$(echo "$JSON" | grep '"tag_name"' | head -n1 | cut -d '"' -f4)"

    DOWNLOAD_URL="$(echo "$JSON" \
        | grep browser_download_url \
        | grep "luci-app-openclash" \
        | cut -d '"' -f4 \
        | head -n1)"

    info "Latest Version : $RELEASE_TAG"
    info "Download URL : $DOWNLOAD_URL"
}

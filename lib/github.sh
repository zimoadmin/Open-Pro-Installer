#!/bin/sh

OPENCLASH_API="https://api.github.com/repos/vernesong/OpenClash/releases/latest"

get_latest_release() {

    info "Getting latest OpenClash release..."

    JSON="$(wget -qO- "$OPENCLASH_API")"

    [ -z "$JSON" ] && {
        error "GitHub API unavailable."
        return 1
    }

    RELEASE_TAG="$(echo "$JSON" | grep '"tag_name"' | head -n1 | cut -d '"' -f4)"

    DOWNLOAD_URL="$(echo "$JSON" \
        | grep browser_download_url \
        | grep luci-app-openclash \
        | cut -d '"' -f4 \
        | head -n1)"

    info "Latest Version : $RELEASE_TAG"

    info "Download URL :"

    echo "$DOWNLOAD_URL"
}

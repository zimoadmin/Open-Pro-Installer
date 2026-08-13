#!/bin/sh

OPENCLASH_API="https://api.github.com/repos/vernesong/OpenClash/releases/latest"

get_latest_release() {

    info "Getting latest OpenClash release..."

    wget -qO /tmp/openclash_version "$OPENCLASH_API"

    [ ! -f /tmp/openclash_version ] && {
        error "Download release info failed"
        return 1
    }

    RELEASE_TAG="$(jsonfilter -i /tmp/openclash_version -e '@.tag_name')"

    DOWNLOAD_URL="$(jsonfilter -i /tmp/openclash_version -e '@.assets[*].browser_download_url' | grep '\.ipk$' | head -n1)"

    info "Latest Version : $RELEASE_TAG"
    info "Download URL : $DOWNLOAD_URL"
}

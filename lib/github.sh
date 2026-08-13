#!/bin/sh

GITHUB_API="https://api.github.com/repos/vernesong/OpenClash/releases/latest"

get_latest_release() {
    info "Getting latest OpenClash release..."

    JSON="$(wget -qO- "$GITHUB_API")"

    if [ -z "$JSON" ]; then
        error "Unable to connect to GitHub API."
        return 1
    fi

    RELEASE_TAG="$(echo "$JSON" | grep '"tag_name"' | head -n1 | cut -d '"' -f4)"

    if [ -z "$RELEASE_TAG" ]; then
        error "Failed to parse release tag."
        return 1
    fi

    info "Latest version: $RELEASE_TAG"
}

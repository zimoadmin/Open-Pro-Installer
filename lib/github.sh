#!/bin/sh

OPENCLASH_API="https://api.github.com/repos/vernesong/OpenClash/releases/latest"

get_latest_release() {

    info "github.sh loaded"

    JSON="$(wget -qO- https://api.github.com/repos/vernesong/OpenClash/releases/latest)"

    echo "$JSON" | head -n 5

}

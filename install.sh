#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

. "$SCRIPT_DIR/lib/logger.sh"
. "$SCRIPT_DIR/lib/github.sh"

clear

echo "======================================"
echo "        Open-Pro-Installer"
echo "======================================"

echo "1. Install OpenClash"
echo "0. Exit"

printf "Choose: "
read CHOOSE

case "$CHOOSE" in
1)
    get_latest_release

    . "$SCRIPT_DIR/modules/openclash.sh"
    install_openclash
    ;;
esac

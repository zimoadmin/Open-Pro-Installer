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
read CHOOSE </dev/tty

case "$CHOOSE" in
1)
    echo "===== STEP 1 ====="

    get_latest_release

    echo "===== STEP 2 ====="

    . "$SCRIPT_DIR/modules/openclash.sh"

    echo "===== STEP 3 ====="

    install_openclash

    echo "===== STEP 4 ====="
    ;;
*)
    exit 0
    ;;
esac

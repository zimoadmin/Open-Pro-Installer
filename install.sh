#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

. "$SCRIPT_DIR/lib/logger.sh"
. "$SCRIPT_DIR/lib/github.sh"

clear

echo "======================================"
echo "        Open-Pro-Installer"
echo "======================================"

echo "1. Install OpenClash"
echo "2. Install SSR Plus+"
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

2)
    echo "===== STEP 1 ====="
    echo "Preparing SSR Plus+..."

    . "$SCRIPT_DIR/modules/ssrplus.sh"

    echo "===== STEP 2 ====="

    install_ssrplus

    echo "===== STEP 3 ====="
    ;;

0)
    echo "Exit."
    exit 0
    ;;

*)
    echo "[ERROR] Invalid option."
    exit 1
    ;;

esac

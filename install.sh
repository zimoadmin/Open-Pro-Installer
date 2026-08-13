#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

. "$SCRIPT_DIR/lib/logger.sh"
. "$SCRIPT_DIR/lib/github.sh"

clear


# ==============================
# Color
# ==============================

GREEN="\033[32m"
PURPLE="\033[35m"
BLUE="\033[34m"
RED="\033[31m"
RESET="\033[0m"


LINE="${BLUE}======================================${RESET}"


# ==============================
# Main UI
# ==============================

echo ""

echo "$LINE"

echo -e "${GREEN}"
echo "        Open-Pro-Installer"
echo -e "${RESET}"

echo "$LINE"

echo ""

echo -e "${PURPLE}1. Install OpenClash${RESET}"
echo -e "${PURPLE}2. Install SSR Plus+${RESET}"
echo ""

echo -e "${PURPLE}0. Exit${RESET}"

echo ""

echo "$LINE"

printf "${PURPLE}Choose: ${RESET}"

read CHOOSE </dev/tty


echo ""

echo "$LINE"


case "$CHOOSE" in


1)

    echo -e "${GREEN}"
    echo "===== STEP 1 ====="
    echo -e "${RESET}"

    get_latest_release


    echo -e "${GREEN}"
    echo "===== STEP 2 ====="
    echo -e "${RESET}"


    . "$SCRIPT_DIR/modules/openclash.sh"


    echo -e "${GREEN}"
    echo "===== STEP 3 ====="
    echo -e "${RESET}"


    install_openclash


    echo -e "${GREEN}"
    echo "===== STEP 4 ====="
    echo -e "${RESET}"

    ;;


2)

    echo -e "${GREEN}"
    echo "===== STEP 1 ====="
    echo "Preparing SSR Plus+..."
    echo -e "${RESET}"


    . "$SCRIPT_DIR/modules/ssrplus.sh"


    echo -e "${GREEN}"
    echo "===== STEP 2 ====="
    echo -e "${RESET}"


    install_ssrplus


    echo -e "${GREEN}"
    echo "===== STEP 3 ====="
    echo -e "${RESET}"

    ;;


0)

    echo -e "${RED}Exit.${RESET}"

    exit 0

    ;;


*)

    echo -e "${RED}[ERROR] Invalid option.${RESET}"

    exit 1

    ;;


esac


echo ""

echo "$LINE"

echo ""

#!/bin/sh


SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"


. "$SCRIPT_DIR/lib/logger.sh"
. "$SCRIPT_DIR/lib/github.sh"


clear


# ==============================
# Color
# ==============================

GREEN="$(printf '\033[32m')"
CYAN="$(printf '\033[36m')"
BLUE="$(printf '\033[34m')"
RED="$(printf '\033[31m')"
YELLOW="$(printf '\033[33m')"
RESET="$(printf '\033[0m')"



# ==============================
# UI Function
# ==============================


show_banner()
{

printf "\n"


printf "%b\n" "${BLUE}╭──────────────────────────────────────╮${RESET}"

printf "%b\n" "${BLUE}│${GREEN}        Open-Pro-Installer        ${BLUE}│${RESET}"

printf "%b\n" "${BLUE}│${GREEN}            Version 1.0            ${BLUE}│${RESET}"

printf "%b\n" "${BLUE}╰──────────────────────────────────────╯${RESET}"


printf "%b\n" "${BLUE}┌──────────────────────────────────────┐${RESET}"

printf "%b\n" "${BLUE}│          ${CYAN}Plugin Manager${BLUE}             │${RESET}"

printf "%b\n" "${BLUE}├──────────────────────────────────────┤${RESET}"


printf "%b\n" "${BLUE}│                                      │${RESET}"

printf "%b\n" "${BLUE}│  ${CYAN}[1]${RESET} Install OpenClash              ${BLUE}│${RESET}"

printf "%b\n" "${BLUE}│                                      │${RESET}"

printf "%b\n" "${BLUE}│  ${CYAN}[2]${RESET} Install SSR Plus+              ${BLUE}│${RESET}"

printf "%b\n" "${BLUE}│                                      │${RESET}"

printf "%b\n" "${BLUE}│  ${CYAN}[0]${RESET} Exit                          ${BLUE}│${RESET}"

printf "%b\n" "${BLUE}│                                      │${RESET}"


printf "%b\n" "${BLUE}└──────────────────────────────────────┘${RESET}"


printf "\n"


printf "%b" "${YELLOW} Select option > ${RESET}"


}



# ==============================
# Main
# ==============================


show_banner


read CHOOSE </dev/tty


printf "\n"


case "$CHOOSE" in


1)

    printf "%b\n" "${GREEN}===== STEP 1 =====${RESET}"


    get_latest_release


    printf "%b\n" "${GREEN}===== STEP 2 =====${RESET}"


    . "$SCRIPT_DIR/modules/openclash.sh"


    printf "%b\n" "${GREEN}===== STEP 3 =====${RESET}"


    install_openclash


    printf "%b\n" "${GREEN}===== STEP 4 =====${RESET}"


    ;;



2)


    printf "%b\n" "${GREEN}===== STEP 1 =====${RESET}"

    printf "%b\n" "${YELLOW}Preparing SSR Plus+...${RESET}"


    . "$SCRIPT_DIR/modules/ssrplus.sh"



    printf "%b\n" "${GREEN}===== STEP 2 =====${RESET}"


    install_ssrplus



    printf "%b\n" "${GREEN}===== STEP 3 =====${RESET}"


    ;;



0)


    printf "%b\n" "${RED}Exit.${RESET}"

    exit 0

    ;;



*)


    printf "%b\n" "${RED}[ERROR] Invalid option.${RESET}"

    exit 1

    ;;


esac



printf "\n"


printf "%b\n" "${BLUE}══════════════════════════════════════${RESET}"

printf "\n"

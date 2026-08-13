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
# 一级菜单
# ==============================


main_menu()
{


clear


printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"

printf "%b\n" "${BLUE}║${GREEN}             ZIMO--工具箱             ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}║${GREEN}                 v1.0.0               ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}╠══════════════════════════════════════╣${RESET}"


printf "%b\n" "${BLUE}║${CYAN}  [1] 一键仿 iStoreOS 主题             ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}║${CYAN}  [2] 安装 iStore 商店                ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}║${CYAN}  [3] 安装代理工具                    ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}║${CYAN}  [4] 解锁区域限制                    ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}║${CYAN}  [0] 退出                            ${BLUE}║${RESET}"


printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"



printf "\n"

printf "%b" "${YELLOW} 选择序列 > ${RESET}"


read CHOOSE </dev/tty



case "$CHOOSE" in


1)

    printf "${GREEN}正在应用 iStoreOS 主题...${RESET}\n"

    if [ -f "$SCRIPT_DIR/modules/istore-theme.sh" ]
    then
        . "$SCRIPT_DIR/modules/istore-theme.sh"
        install_theme
    else
        echo "主题模块不存在"
    fi

    ;;



2)

    printf "${GREEN}正在安装 iStore 商店...${RESET}\n"

    if [ -f "$SCRIPT_DIR/modules/istore.sh" ]
    then
        . "$SCRIPT_DIR/modules/istore.sh"
        install_istore
    else
        echo "iStore模块不存在"
    fi

    ;;



3)

    proxy_menu

    ;;



4)

    printf "${GREEN}正在解锁区域...${RESET}\n"

    if [ -f "$SCRIPT_DIR/modules/unlock.sh" ]
    then
        . "$SCRIPT_DIR/modules/unlock.sh"
        unlock_region
    else
        echo "解锁模块不存在"
    fi

    ;;



0)

    printf "${RED}Exit.${RESET}\n"

    exit 0

    ;;



*)

    printf "${RED}[ERROR] 输入错误${RESET}\n"

    sleep 2

    main_menu

    ;;


esac


}




# ==============================
# 二级代理菜单
# ==============================


proxy_menu()
{


clear



printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"

printf "%b\n" "${BLUE}║${GREEN}              代理工具                ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}╠══════════════════════════════════════╣${RESET}"


printf "%b\n" "${BLUE}║${CYAN}  [1] 安装 OpenClash                  ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}║${CYAN}  [2] 安装 SSR Plus+                  ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}║${CYAN}  [0] 返回                            ${BLUE}║${RESET}"


printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"



printf "\n"

printf "%b" "${YELLOW} 选择序列 > ${RESET}"



read PROXY_CHOOSE </dev/tty




case "$PROXY_CHOOSE" in



1)


printf "${GREEN}正在安装 OpenClash...${RESET}\n"


get_latest_release


. "$SCRIPT_DIR/modules/openclash.sh"


install_openclash


;;



2)


printf "${GREEN}正在安装 SSR Plus+...${RESET}\n"



. "$SCRIPT_DIR/modules/ssrplus.sh"


install_ssrplus


;;



0)


main_menu


;;



*)

printf "${RED}[ERROR] 输入错误${RESET}\n"

sleep 2

proxy_menu


;;


esac


}




# ==============================
# Start
# ==============================


main_menu

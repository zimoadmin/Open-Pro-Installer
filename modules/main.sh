#!/bin/sh


SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"


. "$SCRIPT_DIR/lib/logger.sh"
. "$SCRIPT_DIR/lib/github.sh"


if [ -f "$SCRIPT_DIR/modules/depend.sh" ]; then
    . "$SCRIPT_DIR/modules/depend.sh"
fi


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
# 返回主菜单
# ==============================

back_main()
{

printf "\n"

printf "%b\n" "${GREEN}返回主菜单...${RESET}"

sleep 1

}





# ==============================
# 返回代理菜单
# ==============================

back_proxy()
{

printf "\n"

printf "%b\n" "${GREEN}返回代理工具...${RESET}"

sleep 1

proxy_menu

}






# ==============================
# 主菜单
# ==============================


main_menu()
{


while true
do


clear


printf "\n"


printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"

printf "%b\n" "${BLUE}║${GREEN}             ZIMO--工具箱             ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}║${GREEN}                 v1.0.0               ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}╠══════════════════════════════════════╣${RESET}"

printf "%b\n" "${BLUE}║${CYAN}  [1] 一键仿 iStoreOS 主题            ${BLUE}║${RESET}"

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


printf "%b\n" "${GREEN}[主题] 正在安装 iStoreOS 风格主题...${RESET}"


if [ -f "$SCRIPT_DIR/modules/theme.sh" ]
then

    . "$SCRIPT_DIR/modules/theme.sh"

    install_theme


else

    printf "%b\n" "${RED}[ERROR] theme.sh 不存在${RESET}"

fi


back_main

;;



2)


printf "%b\n" "${GREEN}[iStore] 正在安装 iStore 商店...${RESET}"


if [ -f "$SCRIPT_DIR/modules/istore.sh" ]
then

    . "$SCRIPT_DIR/modules/istore.sh"

    install_istore


else

    printf "%b\n" "${RED}[ERROR] istore.sh 不存在${RESET}"

fi


back_main

;;



3)


proxy_menu

;;



4)


printf "%b\n" "${GREEN}[区域] 打开区域限制管理...${RESET}"



if [ -f "$SCRIPT_DIR/modules/unlock.sh" ]
then


    . "$SCRIPT_DIR/modules/unlock.sh"


    region_menu



else


    printf "%b\n" "${RED}[ERROR] unlock.sh 不存在${RESET}"


    sleep 2


fi



;;



0)


printf "%b\n" "${RED}Exit.${RESET}"

exit 0

;;



*)

printf "%b\n" "${RED}[ERROR] 输入错误${RESET}"

sleep 1

;;


esac


done


}









# ==============================
# 代理菜单
# ==============================


proxy_menu()
{


while true
do


clear



printf "\n"


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


printf "%b\n" "${GREEN}===== OpenClash =====${RESET}"



if ! get_latest_release
then

printf "%b\n" "${RED}OpenClash版本获取失败${RESET}"

sleep 2

continue

fi



. "$SCRIPT_DIR/modules/openclash.sh"


install_openclash


;;



2)


printf "%b\n" "${GREEN}===== SSR Plus+ =====${RESET}"



if [ -f "$SCRIPT_DIR/modules/ssrplus.sh" ]
then


. "$SCRIPT_DIR/modules/ssrplus.sh"


install_ssrplus


else


printf "%b\n" "${RED}SSR Plus模块不存在${RESET}"


fi



sleep 2


;;



0)


return


;;



*)

printf "%b\n" "${RED}[ERROR] 输入错误${RESET}"

sleep 1


;;


esac


done


}







# ==============================
# Start
# ==============================


main_menu

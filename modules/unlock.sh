#!/bin/sh


GREEN="\033[32m"
CYAN="\033[36m"
BLUE="\033[34m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"



unlock_region()
{

printf "\n"

printf "%b\n" "${GREEN}[INFO] 正在解锁海外版软件...${RESET}"


find /usr/share/oui/menu.d \
-type f \
-name "*.json" \
-exec sed -i 's/"zh-cn"/"zh-tw"/g' {} +


printf "\n"

printf "%b\n" "${GREEN}[SUCCESS] 解锁完成${RESET}"

}




lock_region()
{

printf "\n"

printf "%b\n" "${YELLOW}[INFO] 恢复官方限制...${RESET}"


find /usr/share/oui/menu.d \
-type f \
-name "*.json" \
-exec sed -i 's/"zh-tw"/"zh-cn"/g' {} +


printf "%b\n" "${GREEN}[SUCCESS] 已恢复${RESET}"

}




check_region()
{


COUNT=$(grep -r '"zh-tw"' /usr/share/oui/menu.d 2>/dev/null | wc -l)


if [ "$COUNT" -gt 0 ]
then

printf "%b\n" "${GREEN}当前状态：已解锁${RESET}"

else

printf "%b\n" "${RED}当前状态：未解锁${RESET}"

fi

}




region_menu()
{


while true
do


clear


printf "\n"

printf "%b\n" "${BLUE}╔══════════════════════════╗${RESET}"
printf "%b\n" "${BLUE}║${GREEN}       区域限制管理       ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}╠══════════════════════════╣${RESET}"
printf "%b\n" "${BLUE}║${CYAN} [1] 解锁海外版软件       ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}║${CYAN} [2] 恢复官方限制         ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}║${CYAN} [3] 查看状态             ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}║${CYAN} [0] 返回主菜单           ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}╚══════════════════════════╝${RESET}"


printf "\n"

printf "%b" "${YELLOW}请选择 > ${RESET}"


read CHOOSE </dev/tty


case "$CHOOSE" in


1)

unlock_region

sleep 2

;;


2)

lock_region

sleep 2

;;


3)

check_region

sleep 3

;;


0)

return

;;


*)

printf "%b\n" "${RED}输入错误${RESET}"

sleep 1

;;


esac


done

}

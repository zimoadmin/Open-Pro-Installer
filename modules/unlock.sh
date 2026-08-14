#!/bin/sh


region_menu()
{

while true
do

clear


printf "\n"

printf "%b\n" "${BLUE}╔══════════════════════════╗${RESET}"
printf "%b\n" "${BLUE}║${GREEN}      区域限制管理        ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}╠══════════════════════════╣${RESET}"
printf "%b\n" "${BLUE}║${CYAN} [1] 解锁海外版软件       ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}║${CYAN} [2] 恢复官方限制         ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}║${CYAN} [3] 查看状态             ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}║${CYAN} [0] 返回主菜单           ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}╚══════════════════════════╝${RESET}"


printf "\n"

printf "%b" "${YELLOW}选择序列 > ${RESET}"


read REGION_CHOOSE </dev/tty


case "$REGION_CHOOSE" in


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





unlock_region()
{

printf "%b\n" "${GREEN}[INFO] 正在解锁海外版软件...${RESET}"


find /usr/share/oui/menu.d \
-type f \
-name "*.json" \
-exec sed -i 's/"zh-cn"/"zh-tw"/g' {} +


printf "%b\n" "${GREEN}[SUCCESS] 解锁完成${RESET}"

}





lock_region()
{

printf "%b\n" "${YELLOW}[INFO] 正在恢复官方限制...${RESET}"


find /usr/share/oui/menu.d \
-type f \
-name "*.json" \
-exec sed -i 's/"zh-tw"/"zh-cn"/g' {} +


printf "%b\n" "${GREEN}[SUCCESS] 恢复完成${RESET}"

}





check_region()
{

num=$(grep -r "zh-tw" /usr/share/oui/menu.d 2>/dev/null | wc -l)


printf "\n"

if [ "$num" -gt 0 ]
then

printf "%b\n" "${GREEN}状态：海外版解锁${RESET}"

else

printf "%b\n" "${RED}状态：官方限制${RESET}"

fi


}

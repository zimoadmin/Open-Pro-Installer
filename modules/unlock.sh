#!/bin/sh


# ======================================
# 海外版软件解锁
# GL.iNet 区域限制解除
# ======================================



GREEN="$(printf '\033[32m')"
BLUE="$(printf '\033[34m')"
RED="$(printf '\033[31m')"
YELLOW="$(printf '\033[33m')"
RESET="$(printf '\033[0m')"





# ======================================
# 解锁区域限制
# ======================================


unlock_region()
{


clear


printf "\n"

printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"

printf "%b\n" "${BLUE}║${GREEN}          海外版软件解锁              ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"


echo ""



printf "%b\n" "${YELLOW}正在检测 GL.iNet 菜单文件...${RESET}"




if [ ! -d "/usr/share/oui/menu.d" ]
then


printf "%b\n" "${RED}未找到 GL.iNet 菜单目录${RESET}"

return 1


fi





printf "\n"

printf "%b" "${YELLOW}确认解除区域限制? (y/N): ${RESET}"

read confirm





case "$confirm" in


[yY]*)



printf "\n"

printf "%b\n" "${GREEN}开始解除区域限制...${RESET}"





# 修改GL官方隐藏菜单语言限制


find /usr/share/oui/menu.d \
-type f \
-name "*.json" \
-exec sed -i 's/"zh-cn"/"zh-tw"/g' {} +





printf "\n"

printf "%b\n" "${GREEN}区域限制解除完成${RESET}"

printf "%b\n" "${YELLOW}请刷新LuCI页面或重启路由器${RESET}"



;;



*)


printf "%b\n" "${RED}已取消${RESET}"


;;



esac



}





# ======================================
# 恢复官方状态
# ======================================


lock_region()
{


clear


printf "\n"

printf "%b\n" "${BLUE}恢复官方区域限制${RESET}"



find /usr/share/oui/menu.d \
-type f \
-name "*.json" \
-exec sed -i 's/"zh-tw"/"zh-cn"/g' {} +




printf "%b\n" "${GREEN}恢复完成${RESET}"



}






# ======================================
# 查看状态
# ======================================


check_region()
{


clear


printf "\n"

printf "%b\n" "${BLUE}检测区域限制状态${RESET}"



NUM=$(grep -r '"zh-tw"' \
/usr/share/oui/menu.d \
2>/dev/null | wc -l)




if [ "$NUM" -gt 0 ]
then


printf "%b\n" "${GREEN}当前状态：已解锁${RESET}"


else


printf "%b\n" "${RED}当前状态：未解锁${RESET}"


fi


}





# ======================================
# 解锁菜单
# ======================================


region_menu()
{


while true
do


clear


printf "\n"

printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"

printf "%b\n" "${BLUE}║${GREEN}          区域限制管理                ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}╠══════════════════════════════════════╣${RESET}"

printf "%b\n" "${BLUE}║${GREEN} 1. 解锁海外版软件                   ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}║${GREEN} 2. 恢复官方限制                     ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}║${GREEN} 3. 查看当前状态                     ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}║${GREEN} 0. 返回                             ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"



printf "\n选择: "

read c



case "$c" in


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

sleep 2

;;


0)

return

;;


*)

printf "错误"

sleep 1

;;


esac


done


}

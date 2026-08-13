#!/bin/sh


# ==============================
# iStore 商店安装模块
# ==============================


install_istore()
{


GREEN="$(printf '\033[32m')"
CYAN="$(printf '\033[36m')"
RED="$(printf '\033[31m')"
YELLOW="$(printf '\033[33m')"
RESET="$(printf '\033[0m')"



echo ""

printf "%b\n" "${CYAN}===== iStore 商店安装 =====${RESET}"


echo ""


# ==============================
# 检查 opkg
# ==============================


if ! command -v opkg >/dev/null 2>&1
then

    printf "%b\n" "${RED}[ERROR] 当前系统不是 OpenWrt${RESET}"

    return 1

fi



# ==============================
# 更新软件源
# ==============================


printf "%b\n" "${GREEN}[INFO] 更新软件源...${RESET}"


opkg update



# ==============================
# 添加 iStore 源
# ==============================


printf "%b\n" "${GREEN}[INFO] 添加 iStore 软件源...${RESET}"



mkdir -p /tmp/is-root



wget -qO /tmp/istore_install.sh \
https://gitee.com/wukongdaily/gl_onescript/raw/master/reinstall_istore.sh



if [ ! -s /tmp/istore_install.sh ]
then


printf "%b\n" "${RED}[ERROR] 获取 iStore 安装脚本失败${RESET}"

return 1


fi



chmod +x /tmp/istore_install.sh




# ==============================
# 执行安装
# ==============================


printf "%b\n" "${GREEN}[INFO] 开始安装 iStore...${RESET}"


sh /tmp/istore_install.sh



if [ $? -eq 0 ]
then


printf "\n"

printf "%b\n" "${GREEN}iStore 商店安装完成！${RESET}"


else


printf "\n"

printf "%b\n" "${RED}iStore 安装失败${RESET}"


return 1


fi



echo ""

printf "%b\n" "${CYAN}请进入 LuCI 查看：服务 → iStore${RESET}"



return 0


}

#!/bin/sh


# ======================================
# iStoreOS Theme Installer
# ======================================


GREEN="\033[32m"
BLUE="\033[34m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"



# ======================================
# 安装主题
# ======================================


install_theme()
{


echo ""


printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"
printf "%b\n" "${BLUE}║${GREEN}          iStoreOS主题安装            ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"


echo ""



# ======================================
# 检测系统
# ======================================


if command -v opkg >/dev/null 2>&1
then

    PKG="opkg"
    EXT="ipk"


elif command -v apk >/dev/null 2>&1
then

    PKG="apk"
    EXT="apk"


else


    printf "${RED}[ERROR] 未检测到软件包管理器${RESET}\n"

    return 1


fi




printf "${GREEN}[INFO] 软件管理器:${RESET} $PKG\n"
printf "${GREEN}[INFO] 软件包类型:${RESET} .$EXT\n"





# ======================================
# 获取 Argon 最新版本
# ======================================


ARGON_API="https://openpro-auth.zimo4399.workers.dev/argon"


printf "${GREEN}[INFO] 获取 Argon 最新版本...${RESET}\n"



if command -v wget >/dev/null 2>&1
then

    wget -qO /tmp/argon.json "$ARGON_API"


elif command -v curl >/dev/null 2>&1
then

    curl -fsSL "$ARGON_API" -o /tmp/argon.json


else

    printf "${RED}[ERROR] 缺少 wget/curl${RESET}\n"

    return 1

fi





if command -v jsonfilter >/dev/null 2>&1
then


    VERSION="$(jsonfilter -i /tmp/argon.json -e '@.version')"


else


    VERSION="$(grep '"tag_name"' /tmp/argon.json | sed 's/.*"tag_name": "\(.*\)",/\1/')"


fi





if [ -z "$VERSION" ]
then


printf "${RED}[ERROR] 获取版本失败${RESET}\n"

return 1


fi




# 去掉 v

VERSION="${VERSION#v}"



printf "${GREEN}[INFO] 最新版本:${RESET} v$VERSION\n"






# ======================================
# 下载地址
# ======================================



if [ "$EXT" = "ipk" ]
then



THEME_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v${VERSION}/luci-theme-argon_${VERSION}-1_all.ipk"


CONFIG_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v${VERSION}/luci-app-argon-config_${VERSION}-1_all.ipk"



else



THEME_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v${VERSION}/luci-theme-argon-${VERSION}-r1.apk"


CONFIG_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v${VERSION}/luci-app-argon-config-${VERSION}-r1.apk"



fi





# ======================================
# 下载
# ======================================


cd /tmp || return 1



printf "\n"

printf "${GREEN}[INFO] 下载主题...${RESET}\n"



wget -O "theme.$EXT" "$THEME_URL"



if [ $? -ne 0 ]
then

printf "${RED}[ERROR] 主题下载失败${RESET}\n"

return 1

fi





printf "${GREEN}[INFO] 下载配置插件...${RESET}\n"



wget -O "config.$EXT" "$CONFIG_URL"



if [ $? -ne 0 ]
then

printf "${RED}[ERROR] 配置插件下载失败${RESET}\n"

return 1

fi







# ======================================
# 安装
# ======================================



if [ "$PKG" = "opkg" ]
then


printf "${GREEN}[INFO] 正在安装 IPK...${RESET}\n"


opkg install \
./theme.ipk \
./config.ipk



else



printf "${GREEN}[INFO] 正在安装 APK...${RESET}\n"



apk add \
--allow-untrusted \
./theme.apk \
./config.apk



fi





if [ $? -ne 0 ]
then


printf "${RED}[ERROR] 安装失败${RESET}\n"


return 1


fi





# ======================================
# 设置 Argon
# ======================================


printf "${YELLOW}[INFO] 设置 Argon主题...${RESET}\n"



if command -v uci >/dev/null 2>&1
then


uci set luci.main.mediaurlbase='/luci-static/argon'

uci commit luci


/etc/init.d/uhttpd restart 2>/dev/null


fi





printf "\n"

printf "${GREEN}[SUCCESS] iStoreOS主题安装完成${RESET}\n"


printf "${CYAN}[INFO] 请刷新 LuCI 页面${RESET}\n"



echo ""


}

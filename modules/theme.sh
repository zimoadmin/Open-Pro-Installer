#!/bin/sh


# ======================================
# iStoreOS Theme Installer
# ======================================


GREEN="\033[32m"
BLUE="\033[34m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"



install_theme()
{


echo ""

printf "${BLUE}==============================${RESET}\n"
printf "${GREEN}   iStoreOS主题安装${RESET}\n"
printf "${BLUE}==============================${RESET}\n"


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

    printf "${RED}[ERROR] 不支持的软件包管理器${RESET}\n"

    return 1

fi



printf "${GREEN}[INFO] 软件管理器:${RESET} $PKG\n"

printf "${GREEN}[INFO] 软件包类型:${RESET} .$EXT\n"





# ======================================
# 下载地址
# ======================================


VERSION="2.4.6"



if [ "$EXT" = "ipk" ]
then


THEME_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v${VERSION}/luci-theme-argon_${VERSION}-1_all.ipk"


CONFIG_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v${VERSION}/luci-app-argon-config_${VERSION}-1_all.ipk"



else


THEME_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v${VERSION}/luci-theme-argon-${VERSION}-r1.apk"


CONFIG_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v${VERSION}/luci-app-argon-config-${VERSION}-r1.apk"



fi





cd /tmp || exit 1



echo ""

printf "${GREEN}[INFO] 下载主题...${RESET}\n"


wget -O theme.$EXT "$THEME_URL"



printf "${GREEN}[INFO] 下载配置插件...${RESET}\n"


wget -O config.$EXT "$CONFIG_URL"





# ======================================
# 安装
# ======================================



if [ "$PKG" = "opkg" ]
then


printf "${GREEN}[INFO] 安装ipk...${RESET}\n"


opkg install \
./theme.ipk \
./config.ipk



else


printf "${GREEN}[INFO] 安装apk...${RESET}\n"


apk add \
--allow-untrusted \
./theme.apk \
./config.apk



fi




if [ $? -eq 0 ]
then

printf "${GREEN}[SUCCESS] iStoreOS主题安装完成${RESET}\n"


else

printf "${RED}[ERROR] 安装失败${RESET}\n"

return 1


fi



echo ""


printf "${YELLOW}[INFO] 正在设置Argon主题...${RESET}\n"


uci set luci.main.mediaurlbase='/luci-static/argon'

uci commit luci



/etc/init.d/uhttpd restart 2>/dev/null



printf "${GREEN}[DONE] 请刷新LuCI页面${RESET}\n"



}

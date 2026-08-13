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



install_theme()
{


echo ""


printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"
printf "%b\n" "${BLUE}║${GREEN}        iStoreOS主题一键安装          ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"


echo ""



# ======================================
# 检测设备
# ======================================


MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"


[ -z "$MODEL" ] && MODEL="Unknown"



ARCH="$(uname -m)"



printf "${GREEN}[INFO] 设备型号:${RESET} $MODEL\n"

printf "${GREEN}[INFO] CPU架构:${RESET} $ARCH\n"





# ======================================
# 检测包管理器
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


printf "${RED}[ERROR] 不支持的软件管理器${RESET}\n"

return 1


fi




printf "${GREEN}[INFO] 软件管理器:${RESET} $PKG\n"

printf "${GREEN}[INFO] 软件包类型:${RESET} .$EXT\n"






# ======================================
# 临时添加 Argon源
# ======================================


ARGON_FEED="/etc/opkg/customfeeds.conf"



if [ "$PKG" = "opkg" ]
then


printf "${GREEN}[INFO] 添加Argon临时源...${RESET}\n"



cp "$ARGON_FEED" \
/tmp/customfeeds.backup 2>/dev/null



sed -i '/argon_theme/d' "$ARGON_FEED" 2>/dev/null



cat >> "$ARGON_FEED" <<EOF

src/gz argon_theme https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/theme

EOF



opkg update >/dev/null 2>&1



fi







# ======================================
# 安装依赖
# ======================================


printf "${GREEN}[INFO] 检查依赖...${RESET}\n"



if [ "$PKG" = "opkg" ]
then



for DEP in \
luci-lua-runtime \
luci-lib-ipkg \
luci-compat \
libopenssl3


do


if ! opkg list-installed | grep -q "$DEP"
then


printf "${YELLOW}[INFO] 安装依赖:$DEP${RESET}\n"


opkg install "$DEP" >/dev/null 2>&1


fi


done


fi







# ======================================
# 下载 Argon
# ======================================


cd /tmp || return 1



printf "${GREEN}[INFO] 下载Argon主题...${RESET}\n"




if [ "$PKG" = "opkg" ]
then



wget -O luci-theme-argon.ipk \
https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/theme/luci-theme-argon-master_2.2.9.4_all.ipk



wget -O luci-app-argon-config.ipk \
https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/theme/luci-app-argon-config_0.9_all.ipk



wget -O luci-i18n-argon-config-zh-cn.ipk \
https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/theme/luci-i18n-argon-config-zh-cn.ipk



else



printf "${RED}[ERROR] 暂不支持APK版Argon源安装${RESET}\n"

return 1


fi






# ======================================
# 安装
# ======================================


printf "${GREEN}[INFO] 安装Argon主题...${RESET}\n"



opkg install \
/tmp/luci-theme-argon.ipk \
/tmp/luci-app-argon-config.ipk \
/tmp/luci-i18n-argon-config-zh-cn.ipk






if [ $? -ne 0 ]
then


printf "${RED}[ERROR] Argon安装失败${RESET}\n"

return 1


fi








# ======================================
# 删除临时源
# ======================================


printf "${GREEN}[INFO] 清理临时源...${RESET}\n"



sed -i '/argon_theme/d' \
/etc/opkg/customfeeds.conf



if [ -f /tmp/customfeeds.backup ]
then


cp /tmp/customfeeds.backup \
/etc/opkg/customfeeds.conf



fi




opkg update >/dev/null 2>&1







# ======================================
# 设置主题
# ======================================


printf "${YELLOW}[INFO] 设置Argon主题...${RESET}\n"



uci set luci.main.theme='argon'

uci set luci.main.mediaurlbase='/luci-static/argon'


uci commit luci




rm -rf /tmp/luci-*



/etc/init.d/rpcd restart 2>/dev/null

/etc/init.d/uhttpd restart 2>/dev/null






printf "\n"

printf "${GREEN}[SUCCESS] Argon主题安装成功${RESET}\n"

printf "${CYAN}[INFO] 请重新登录LuCI页面${RESET}\n"


echo ""



return 0


}

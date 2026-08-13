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


if [ -z "$MODEL" ]
then

MODEL="Unknown"

fi



ARCH="$(uname -m)"



printf "${GREEN}[INFO] 设备型号:${RESET} $MODEL\n"

printf "${GREEN}[INFO] CPU架构:${RESET} $ARCH\n"





# ======================================
# 软件包管理器
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
# 更新软件源
# ======================================


printf "${GREEN}[INFO] 更新软件源...${RESET}\n"



if [ "$PKG" = "opkg" ]
then


opkg update >/dev/null 2>&1


else


apk update >/dev/null 2>&1


fi







# ======================================
# 安装依赖
# ======================================


printf "${GREEN}[INFO] 检查依赖...${RESET}\n"



if [ "$PKG" = "opkg" ]
then


for DEP in luci-lib-ipkg luci-compat
do


if ! opkg list-installed | grep -q "$DEP"
then


printf "${YELLOW}[INFO] 安装依赖:$DEP${RESET}\n"


opkg install "$DEP" >/dev/null 2>&1


fi


done


fi







# ======================================
# 获取 Argon 信息
# ======================================


ARGON_API="https://openpro-auth.zimo4399.workers.dev/argon"



printf "${GREEN}[INFO] 获取 Argon 最新版本...${RESET}\n"



wget -qO /tmp/argon.json "$ARGON_API"




if [ ! -s /tmp/argon.json ]
then


printf "${RED}[ERROR] Worker返回为空${RESET}\n"


return 1


fi







VERSION="$(jsonfilter \
-i /tmp/argon.json \
-e '@.version')"



if [ -z "$VERSION" ]
then


printf "${RED}[ERROR] 获取版本失败${RESET}\n"


cat /tmp/argon.json


return 1


fi




printf "${GREEN}[INFO] Argon版本:${RESET} $VERSION\n"







# ======================================
# 获取真实下载地址
# ======================================


if [ "$EXT" = "ipk" ]
then


THEME_URL="$(jsonfilter \
-i /tmp/argon.json \
-e '@.theme_ipk')"


CONFIG_URL="$(jsonfilter \
-i /tmp/argon.json \
-e '@.config_ipk')"



else


THEME_URL="$(jsonfilter \
-i /tmp/argon.json \
-e '@.theme_apk')"



CONFIG_URL="$(jsonfilter \
-i /tmp/argon.json \
-e '@.config_apk')"



fi





if [ -z "$THEME_URL" ]
then


printf "${RED}[ERROR] 没有主题下载地址${RESET}\n"


cat /tmp/argon.json


return 1


fi







# ======================================
# 下载
# ======================================


cd /tmp || return 1



rm -f argon-theme.$EXT argon-config.$EXT




printf "${GREEN}[INFO] 下载 Argon主题...${RESET}\n"



wget \
-O argon-theme.$EXT \
"$THEME_URL"



if [ $? -ne 0 ]
then


printf "${RED}[ERROR] 主题下载失败${RESET}\n"


return 1


fi






printf "${GREEN}[INFO] 下载配置插件...${RESET}\n"



wget \
-O argon-config.$EXT \
"$CONFIG_URL"




if [ $? -ne 0 ]
then


printf "${RED}[ERROR] 配置下载失败${RESET}\n"


return 1


fi







# ======================================
# 安装
# ======================================


if [ "$PKG" = "opkg" ]
then


printf "${GREEN}[INFO] 安装IPK...${RESET}\n"



opkg install \
argon-theme.$EXT \
argon-config.$EXT




else



printf "${GREEN}[INFO] 安装APK...${RESET}\n"



apk add \
--allow-untrusted \
argon-theme.$EXT \
argon-config.$EXT



fi






if [ $? -ne 0 ]
then


printf "${RED}[ERROR] 安装失败${RESET}\n"


return 1


fi







# ======================================
# 设置主题
# ======================================


printf "${YELLOW}[INFO] 设置 Argon主题...${RESET}\n"



if command -v uci >/dev/null 2>&1
then



uci set luci.main.theme='Argon'

uci set luci.main.mediaurlbase='/luci-static/argon'


uci commit luci



rm -rf /tmp/luci-*



/etc/init.d/rpcd restart 2>/dev/null

/etc/init.d/uhttpd restart 2>/dev/null



fi






printf "\n"


printf "${GREEN}[SUCCESS] Argon主题安装成功${RESET}\n"


printf "${CYAN}[INFO] 请重新登录 LuCI 页面${RESET}\n"



echo ""



return 0


}

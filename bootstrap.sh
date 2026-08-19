#!/bin/sh

# ======================================
# Open-Pro-Installer Bootstrap
# BusyBox / OpenWrt Compatible
#
# 正常启动流程静默化版本
# ======================================


# ======================================
# Color
# ======================================

BOLD="$(printf '\033[1m')"
GREEN="$(printf '\033[1;92m')"
BLUE="$(printf '\033[1;94m')"
CYAN="$(printf '\033[1;96m')"
YELLOW="$(printf '\033[1;93m')"
RED="$(printf '\033[1;91m')"
WHITE="$(printf '\033[1;97m')"
RESET="$(printf '\033[0m')"


# ======================================
# Config
# ======================================

REPO="https://auth.12334123.xyz/installer"

WORKDIR="/tmp/Open-Pro-Installer"

AUTH_SERVER="https://auth.12334123.xyz"

ZIP_FILE="$WORKDIR/main.zip"

BOOTSTRAP_LOG="/tmp/openpro_bootstrap.log"


# ======================================
# Header
# ======================================

printf "\n"


# ======================================
# Disclaimer
# ======================================

printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"
printf "%b\n" "${BLUE}║${GREEN}              免责声明                ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}╠══════════════════════════════════════╣${RESET}"

printf "%b\n" "${BLUE}║${CYAN} 本工具仅用于学习交流和个人设备管理。 ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}║${CYAN} 使用本工具产生的风险由用户承担。     ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}║${CYAN} 请勿用于违反当地法律法规的用途。     ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}╠══════════════════════════════════════╣${RESET}"

printf "%b\n" "${BLUE}║${YELLOW} 是否同意以上免责声明？(Y/N)          ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"

printf "\n"

printf "%b" "${YELLOW}输入 > ${RESET}"

read AGREE </dev/tty


case "$AGREE" in

Y|y)

    printf "\n"
    printf "%b\n" "${GREEN}[INFO] 已同意免责声明，继续运行...${RESET}"
    printf "\n"

    ;;

N|n)

    printf "\n"
    printf "%b\n" "${RED}[INFO] 已拒绝免责声明，程序退出。${RESET}"

    exit 0

    ;;

*)

    printf "\n"
    printf "%b\n" "${RED}[ERROR] 输入无效，程序退出。${RESET}"

    exit 1

    ;;

esac


# ======================================
# Check tools
# ======================================

for cmd in curl wget unzip
do

    if ! command -v "$cmd" >/dev/null 2>&1
    then

        printf "%b\n" "${RED}[ERROR] 缺少命令: $cmd${RESET}"

        exit 1

    fi

done


# ======================================
# Request Auth
# ======================================

printf "%b\n" "${GREEN}[AUTH] 正在申请授权...${RESET}"


AUTH_RESPONSE="$(

curl -4 \
    --connect-timeout 10 \
    --max-time 20 \
    -fsS \
    -X POST \
    "$AUTH_SERVER/request" \
    2>/dev/null

)"


if [ -z "$AUTH_RESPONSE" ]
then

    printf "%b\n" "${RED}[ERROR] 无法连接授权服务器${RESET}"

    exit 1

fi


if ! printf "%s" "$AUTH_RESPONSE" |
    grep -q '"success"[[:space:]]*:[[:space:]]*true'
then

    printf "%b\n" "${RED}[ERROR] 申请验证码失败${RESET}"

    printf "%s\n" "$AUTH_RESPONSE"

    exit 1

fi


printf "%b\n" "${GREEN}[AUTH] 验证码已发送给管理员${RESET}"

printf "\n"


# ======================================
# Input Code
# ======================================

printf "%b" "${YELLOW}请输入验证码: ${RESET}" >/dev/tty

IFS= read -r AUTH_CODE </dev/tty


if [ -z "$AUTH_CODE" ]
then

    printf "%b\n" "${RED}[ERROR] 验证码不能为空${RESET}"

    exit 1

fi


case "$AUTH_CODE" in

    [0-9][0-9][0-9][0-9][0-9][0-9])

        ;;

    *)

        printf "%b\n" "${RED}[ERROR] 验证码必须是6位数字${RESET}"

        exit 1

        ;;

esac


printf "\n"

printf "%b\n" "${GREEN}[AUTH] 正在验证...${RESET}"


# ======================================
# Verify
# ======================================

VERIFY_DATA="$(printf '{"code":"%s"}' "$AUTH_CODE")"


VERIFY_RESPONSE="$(

curl -4 \
    --connect-timeout 10 \
    --max-time 20 \
    -sS \
    -X POST \
    -H "Content-Type: application/json" \
    --data "$VERIFY_DATA" \
    "$AUTH_SERVER/verify" \
    2>/dev/null

)"


if printf '%s' "$VERIFY_RESPONSE" |
   grep -q '"success"[[:space:]]*:[[:space:]]*true'
then

    # ==================================
    # 授权成功
    #
    # 原来的：
    # [AUTH] 授权成功
    #
    # 已隐藏
    # ==================================

    :

else

    printf "%b\n" "${RED}[ERROR] 授权失败${RESET}"

    printf "%s\n" "$VERIFY_RESPONSE"

    exit 1

fi


# ======================================
# Prepare Workdir
# ======================================

rm -rf "$WORKDIR"

mkdir -p "$WORKDIR" || {

    printf "%b\n" "${RED}[ERROR] 无法创建临时目录${RESET}"

    exit 1
}


rm -f "$BOOTSTRAP_LOG"


# ======================================
# Download Function
#
# 正常下载完全静默
# ======================================

download_repo()
{

    rm -f "$ZIP_FILE"


    # ----------------------------------
    # 方法1：curl
    # 完全隐藏进度和正常输出
    # ----------------------------------

    if curl -4 \
        -L \
        -f \
        -sS \
        --connect-timeout 10 \
        --max-time 60 \
        --retry 2 \
        --retry-delay 1 \
        -o "$ZIP_FILE" \
        "$REPO" \
        >>"$BOOTSTRAP_LOG" 2>&1
    then

        if [ -s "$ZIP_FILE" ]
        then

            return 0

        fi

    fi


    rm -f "$ZIP_FILE"


    # ----------------------------------
    # 方法2：wget
    # 同样完全静默
    # ----------------------------------

    if wget \
        -4 \
        -q \
        -T 15 \
        -O "$ZIP_FILE" \
        "$REPO" \
        >>"$BOOTSTRAP_LOG" 2>&1
    then

        if [ -s "$ZIP_FILE" ]
        then

            return 0

        fi

    fi


    rm -f "$ZIP_FILE"

    return 1
}


# ======================================
# Download
# ======================================

if ! download_repo
then

    printf "\n"

    printf "%b\n" "${RED}[ERROR] 项目文件下载失败${RESET}"

    printf "%b\n" "${YELLOW}[INFO] 请检查网络、DNS 或服务器连接${RESET}"

    if [ -s "$BOOTSTRAP_LOG" ]
    then

        printf "\n"
        printf "%b\n" "${RED}========== DOWNLOAD ERROR ==========${RESET}"

        tail -n 20 "$BOOTSTRAP_LOG"

        printf "%b\n" "${RED}====================================${RESET}"

    fi

    exit 1

fi


# ======================================
# Check ZIP
# ======================================

if [ ! -s "$ZIP_FILE" ]
then

    printf "%b\n" "${RED}[ERROR] 下载文件为空${RESET}"

    exit 1

fi


# ======================================
# 文件大小
#
# 已隐藏
# ======================================

# FILE_SIZE="$(du -h "$ZIP_FILE" 2>/dev/null | awk '{print $1}')"
# printf "%b\n" "${GREEN}[INFO] 文件大小: ${FILE_SIZE:-未知}${RESET}"


# ======================================
# Extract
#
# "正在解压..." 已隐藏
# ======================================

if ! unzip -oq \
    "$ZIP_FILE" \
    -d "$WORKDIR" \
    >>"$BOOTSTRAP_LOG" 2>&1
then

    printf "%b\n" "${RED}[ERROR] 解压失败${RESET}"

    printf "%b\n" "${YELLOW}[INFO] 下载文件可能不完整${RESET}"

    if [ -s "$BOOTSTRAP_LOG" ]
    then

        printf "\n"
        printf "%b\n" "${RED}========== EXTRACT ERROR ==========${RESET}"

        tail -n 20 "$BOOTSTRAP_LOG"

        printf "%b\n" "${RED}===================================${RESET}"

    fi

    exit 1

fi


# ======================================
# Check Installer
# ======================================

INSTALL_DIR="$WORKDIR/Open-Pro-Installer-main"


if [ ! -d "$INSTALL_DIR" ]
then

    printf "%b\n" "${RED}[ERROR] 项目目录不存在${RESET}"

    exit 1

fi


if [ ! -f "$INSTALL_DIR/install.sh" ]
then

    printf "%b\n" "${RED}[ERROR] install.sh 不存在${RESET}"

    exit 1

fi


# ======================================
# Permission
# ======================================

cd "$INSTALL_DIR" || {

    printf "%b\n" "${RED}[ERROR] 无法进入项目目录${RESET}"

    exit 1
}


chmod +x install.sh 2>/dev/null

chmod +x lib/*.sh 2>/dev/null

chmod +x modules/*.sh 2>/dev/null


# ======================================
# Clean ZIP
# ======================================

rm -f "$ZIP_FILE"


# ======================================
# Check LuCI Dependencies
#
# 正常过程全部静默
# 失败也不影响工具箱启动
# ======================================

check_luci_dependencies()
{

    # ----------------------------------
    # 仅 OPKG 系统
    # ----------------------------------

    if ! command -v opkg >/dev/null 2>&1
    then

        return 0

    fi


    NEED_PACKAGES=""


    # ----------------------------------
    # luci-compat
    # ----------------------------------

    if ! opkg status luci-compat 2>/dev/null |
         grep -q 'Status:.*installed'
    then

        NEED_PACKAGES="$NEED_PACKAGES luci-compat"

    fi


    # ----------------------------------
    # luci-lib-ipkg
    # ----------------------------------

    if ! opkg status luci-lib-ipkg 2>/dev/null |
         grep -q 'Status:.*installed'
    then

        NEED_PACKAGES="$NEED_PACKAGES luci-lib-ipkg"

    fi


    # ----------------------------------
    # 已满足
    # ----------------------------------

    if [ -z "$NEED_PACKAGES" ]
    then

        return 0

    fi


    # ----------------------------------
    # 静默更新
    # ----------------------------------

    opkg update \
        >>"$BOOTSTRAP_LOG" 2>&1 ||
        true


    # ----------------------------------
    # 安装缺失依赖
    # ----------------------------------

    for PKG in $NEED_PACKAGES
    do

        if opkg status "$PKG" 2>/dev/null |
           grep -q 'Status:.*installed'
        then

            continue

        fi


        # --------------------------------
        # 软件源不存在就跳过
        # --------------------------------

        if ! opkg list "$PKG" 2>/dev/null |
             awk -v pkg="$PKG" \
             '$1 == pkg {found=1} END {exit !found}'
        then

            continue

        fi


        # --------------------------------
        # 静默安装
        # --------------------------------

        opkg install "$PKG" \
            >>"$BOOTSTRAP_LOG" 2>&1 ||
            true

    done


    return 0
}


# ======================================
# 项目准备完成
#
# 已隐藏
# ======================================

# printf "%b\n" "${GREEN}[SUCCESS] 项目准备完成${RESET}"


# ======================================
# Check LuCI Base Dependencies
# ======================================

check_luci_dependencies


# ======================================
# 清理 Bootstrap 日志
# ======================================

rm -f "$BOOTSTRAP_LOG" 2>/dev/null


# ======================================
# Start ZIMO
#
# "正在启动 ZIMO--工具箱..."
# 已隐藏
# ======================================

# printf "%b\n" "${BLUE}[INFO] 正在启动 ZIMO--工具箱...${RESET}"


# ======================================
# 直接进入主菜单
# ======================================

exec ./install.sh

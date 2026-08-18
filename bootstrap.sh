#!/bin/sh


# ======================================
# Open-Pro-Installer Bootstrap
# BusyBox / OpenWrt Compatible
# ======================================


# ======================================
# Color
# ======================================

GREEN="\033[32m"
BLUE="\033[34m"
CYAN="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"


# ======================================
# Config
# ======================================

REPO="https://auth.12334123.xyz/installer"

WORKDIR="/tmp/Open-Pro-Installer"

AUTH_SERVER="https://auth.12334123.xyz"

ZIP_FILE="$WORKDIR/main.zip"


# ======================================
# Header
# ======================================

echo ""


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

printf "%b" "${YELLOW} 输入 > ${RESET}"

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


if ! printf "%s" "$AUTH_RESPONSE" | grep -q \
'"success"[[:space:]]*:[[:space:]]*true'
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


if printf '%s' "$VERIFY_RESPONSE" | grep -q \
'"success"[[:space:]]*:[[:space:]]*true'
then

    printf "%b\n" "${GREEN}[AUTH] 授权成功${RESET}"

    printf "\n"

else

    printf "%b\n" "${RED}[ERROR] 授权失败${RESET}"

    printf "%s\n" "$VERIFY_RESPONSE"

    exit 1

fi


# ======================================
# Prepare Workdir
# ======================================

rm -rf "$WORKDIR"

mkdir -p "$WORKDIR"


# ======================================
# Download Function
# ======================================

download_repo()
{

    rm -f "$ZIP_FILE"

    printf "%b\n" "${BLUE}[INFO] 正在下载最新版本...${RESET}"


    # ----------------------------------
    # 方法1：curl IPv4
    # ----------------------------------

    printf "%b\n" "${CYAN}[INFO] 下载方式 1/2：curl${RESET}"


    if curl -4 \
        -L \
        --connect-timeout 10 \
        --max-time 60 \
        --retry 2 \
        -f \
        -o "$ZIP_FILE" \
        "$REPO"
    then

        if [ -s "$ZIP_FILE" ]
        then

            printf "%b\n" "${GREEN}[SUCCESS] 下载完成${RESET}"

            return 0

        fi

    fi


    rm -f "$ZIP_FILE"


    # ----------------------------------
    # 方法2：BusyBox wget
    # ----------------------------------

    printf "%b\n" "${YELLOW}[WARN] curl 下载失败，切换 wget...${RESET}"

    printf "%b\n" "${CYAN}[INFO] 下载方式 2/2：wget${RESET}"


    if wget \
        -4 \
        -T 15 \
        -O "$ZIP_FILE" \
        "$REPO"
    then

        if [ -s "$ZIP_FILE" ]
        then

            printf "%b\n" "${GREEN}[SUCCESS] 下载完成${RESET}"

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

    printf "%b\n" "${YELLOW}[INFO] 当前设备无法正常连接 GitHub${RESET}"

    printf "%b\n" "${YELLOW}[INFO] 请检查 DNS、网络或代理后重新运行${RESET}"

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


FILE_SIZE="$(du -h "$ZIP_FILE" 2>/dev/null | awk '{print $1}')"

printf "%b\n" "${GREEN}[INFO] 文件大小: ${FILE_SIZE:-未知}${RESET}"


# ======================================
# Extract
# ======================================

printf "%b\n" "${BLUE}[INFO] 正在解压...${RESET}"


if ! unzip -oq \
    "$ZIP_FILE" \
    -d "$WORKDIR"
then

    printf "%b\n" "${RED}[ERROR] 解压失败${RESET}"

    printf "%b\n" "${YELLOW}[INFO] 下载文件可能不完整${RESET}"

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

cd "$INSTALL_DIR" || exit 1


chmod +x install.sh

chmod +x lib/*.sh 2>/dev/null

chmod +x modules/*.sh 2>/dev/null


# ======================================
# Clean ZIP
# ======================================

rm -f "$ZIP_FILE"


# ======================================
# Check LuCI Dependencies
# ======================================

check_luci_dependencies()
{
    # ----------------------------------
    # 仅 OPKG 系统执行
    # ----------------------------------

    if ! command -v opkg >/dev/null 2>&1
    then
        return 0
    fi


    NEED_PACKAGES=""


    # ----------------------------------
    # 检测 luci-compat
    # ----------------------------------

    if ! opkg status luci-compat 2>/dev/null |
         grep -q 'Status:.*installed'
    then

        NEED_PACKAGES="$NEED_PACKAGES luci-compat"

    fi


    # ----------------------------------
    # 检测 luci-lib-ipkg
    # ----------------------------------

    if ! opkg status luci-lib-ipkg 2>/dev/null |
         grep -q 'Status:.*installed'
    then

        NEED_PACKAGES="$NEED_PACKAGES luci-lib-ipkg"

    fi


    # ----------------------------------
    # 两个都已安装
    # 静默跳过
    # ----------------------------------

    if [ -z "$NEED_PACKAGES" ]
    then
        return 0
    fi


    printf "%b\n" "${BLUE}[INFO] 正在检查 LuCI 基础依赖...${RESET}"


    # ==================================
    # 更新软件源
    # ==================================

    printf "%b\n" "${BLUE}[INFO] 正在更新软件源...${RESET}"


    LUCI_UPDATE_LOG="/tmp/zimo_luci_update.log"

    rm -f "$LUCI_UPDATE_LOG"


    if opkg update >"$LUCI_UPDATE_LOG" 2>&1
    then

        printf "%b\n" "${GREEN}[SUCCESS] 软件源更新完成${RESET}"

    else

        printf "%b\n" "${YELLOW}[WARN] 软件源更新存在异常，继续检测可用依赖${RESET}"

    fi


    rm -f "$LUCI_UPDATE_LOG"


    # ==================================
    # 安装缺少的软件包
    # ==================================

    for PKG in $NEED_PACKAGES
    do

        # --------------------------------
        # 再次确认是否已经安装
        # --------------------------------

        if opkg status "$PKG" 2>/dev/null |
           grep -q 'Status:.*installed'
        then
            continue
        fi


        # --------------------------------
        # 检查软件源是否存在
        # --------------------------------

        if ! opkg list "$PKG" 2>/dev/null |
             awk -v pkg="$PKG" \
             '$1 == pkg {found=1} END {exit !found}'
        then

            printf "%b\n" \
                "${YELLOW}[SKIP] 软件源不存在 $PKG，已跳过${RESET}"

            continue

        fi


        # --------------------------------
        # 安装
        # --------------------------------

        printf "%b\n" \
            "${BLUE}[INFO] 正在安装 $PKG...${RESET}"


        LUCI_INSTALL_LOG="/tmp/zimo_${PKG}_install.log"

        rm -f "$LUCI_INSTALL_LOG"


        if opkg install "$PKG" >"$LUCI_INSTALL_LOG" 2>&1
        then

            # ----------------------------
            # 安装后验证
            # ----------------------------

            if opkg status "$PKG" 2>/dev/null |
               grep -q 'Status:.*installed'
            then

                printf "%b\n" \
                    "${GREEN}[SUCCESS] $PKG 安装完成${RESET}"

            else

                printf "%b\n" \
                    "${YELLOW}[WARN] $PKG 安装状态无法确认，已继续${RESET}"

            fi

        else

            printf "%b\n" \
                "${YELLOW}[WARN] $PKG 安装失败，已跳过${RESET}"

        fi


        rm -f "$LUCI_INSTALL_LOG"

    done


    return 0
}


# ======================================
# Start Installer
# ======================================

printf "%b\n" "${GREEN}[SUCCESS] 项目准备完成${RESET}"


# ======================================
# Check LuCI Base Dependencies
# ======================================

check_luci_dependencies


# ======================================
# Start ZIMO
# ======================================

printf "%b\n" "${BLUE}[INFO] 正在启动 ZIMO--工具箱...${RESET}"

printf "\n"


exec ./install.sh

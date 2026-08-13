#!/bin/sh


# ======================================
# Color
# ======================================

GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"



# ======================================
# Config
# ======================================

REPO="https://github.com/zimoadmin/Open-Pro-Installer/archive/refs/heads/main.zip"

WORKDIR="/tmp/Open-Pro-Installer"

AUTH_SERVER="https://openpro-auth.zimo4399.workers.dev"



# ======================================
# Header
# ======================================

printf "${GREEN}======================================${RESET}\n"
printf "${GREEN}      Open-Pro-Installer Bootstrap${RESET}\n"
printf "${GREEN}======================================${RESET}\n"

echo ""



# ======================================
# Check tools
# ======================================

for cmd in curl wget unzip; do

    if ! command -v "$cmd" >/dev/null 2>&1; then

        printf "${RED}[ERROR] Missing command: $cmd${RESET}\n"

        exit 1

    fi

done



# ======================================
# Request Auth
# ======================================


printf "${GREEN}[AUTH] 正在申请授权...${RESET}\n"


AUTH_RESPONSE="$(curl -fsS \
-X POST \
"$AUTH_SERVER/request" \
2>/dev/null)"



if [ -z "$AUTH_RESPONSE" ]; then

    printf "${RED}[ERROR] 无法连接授权服务器${RESET}\n"

    exit 1

fi




if ! printf "%s" "$AUTH_RESPONSE" | grep -q \
'"success"[[:space:]]*:[[:space:]]*true'
then

    printf "${RED}[ERROR] 申请验证码失败${RESET}\n"

    echo "$AUTH_RESPONSE"

    exit 1

fi




printf "${GREEN}[AUTH] 验证码已发送给管理员${RESET}\n"

printf "${GREEN}[AUTH] 验证码有效时间：3分钟${RESET}\n"

echo ""



# ======================================
# Input Code
# ======================================


printf "${YELLOW}请输入验证码: ${RESET}" > /dev/tty


IFS= read -r AUTH_CODE < /dev/tty




if [ -z "$AUTH_CODE" ]; then

    printf "${RED}[ERROR] 验证码不能为空${RESET}\n"

    exit 1

fi




case "$AUTH_CODE" in

    [0-9][0-9][0-9][0-9][0-9][0-9])

        ;;

    *)

        printf "${RED}[ERROR] 验证码必须是6位数字${RESET}\n"

        exit 1

        ;;

esac




echo ""

printf "${GREEN}[AUTH] 正在验证...${RESET}\n"



# ======================================
# Verify
# ======================================


VERIFY_DATA="$(printf '{"code":"%s"}' "$AUTH_CODE")"




VERIFY_RESPONSE="$(curl -sS \
-X POST \
-H "Content-Type: application/json" \
--data "$VERIFY_DATA" \
"$AUTH_SERVER/verify" \
2>/dev/null)"





if printf '%s' "$VERIFY_RESPONSE" | grep -q \
'"success"[[:space:]]*:[[:space:]]*true'
then


    printf "${GREEN}[AUTH] 授权成功${RESET}\n"

    echo ""


else


    printf "${RED}[ERROR] 授权失败${RESET}\n"

    echo "$VERIFY_RESPONSE"

    exit 1


fi





# ======================================
# Download
# ======================================


rm -rf "$WORKDIR"

mkdir -p "$WORKDIR"




printf "${BLUE}[INFO] Downloading latest version...${RESET}\n"



if ! wget \
-O "$WORKDIR/main.zip" \
"$REPO"
then


    printf "${RED}[ERROR] Download failed${RESET}\n"

    exit 1


fi





# ======================================
# Extract
# ======================================


printf "${BLUE}[INFO] Extracting...${RESET}\n"



if ! unzip -oq \
"$WORKDIR/main.zip" \
-d "$WORKDIR"
then


    printf "${RED}[ERROR] Unzip failed${RESET}\n"

    exit 1


fi





# ======================================
# Start Installer
# ======================================


cd "$WORKDIR/Open-Pro-Installer-main" || exit 1




chmod +x install.sh

chmod +x lib/*.sh 2>/dev/null

chmod +x modules/*.sh 2>/dev/null




printf "${BLUE}[INFO] Starting installer...${RESET}\n"

echo ""



exec ./install.sh

#!/bin/sh


# ======================================
# Color
# ======================================

GREEN="$(printf '\033[32m')"
BLUE="$(printf '\033[34m')"
YELLOW="$(printf '\033[33m')"
RED="$(printf '\033[31m')"
RESET="$(printf '\033[0m')"



# ======================================
# Config
# ======================================

REPO="https://github.com/zimoadmin/Open-Pro-Installer/archive/refs/heads/main.zip"

WORKDIR="/tmp/Open-Pro-Installer"

AUTH_SERVER="https://openpro-auth.zimo4399.workers.dev"



# ======================================
# Header
# ======================================

printf "%b\n" "${GREEN}======================================${RESET}"
printf "%b\n" "${GREEN}      Open-Pro-Installer Bootstrap${RESET}"
printf "%b\n" "${GREEN}======================================${RESET}"

echo ""



# ======================================
# Check tools
# ======================================

for cmd in curl wget unzip; do

    if ! command -v "$cmd" >/dev/null 2>&1
    then

        printf "%b\n" "${RED}[ERROR] Missing command: $cmd${RESET}"

        exit 1

    fi

done




# ======================================
# Request Auth
# ======================================


printf "%b\n" "${GREEN}[AUTH] 正在申请授权...${RESET}"



AUTH_RESPONSE="$(curl -fsS \
--connect-timeout 10 \
-X POST \
"$AUTH_SERVER/request" \
2>/dev/null)"




if [ -z "$AUTH_RESPONSE" ]; then


    printf "%b\n" "${RED}[ERROR] 无法连接授权服务器${RESET}"

    exit 1


fi





if ! printf "%s" "$AUTH_RESPONSE" | grep -q \
'"success"[[:space:]]*:[[:space:]]*true'
then

    printf "%b\n" "${RED}[ERROR] 获取验证码失败${RESET}"

    echo "$AUTH_RESPONSE"

    exit 1

fi




printf "%b\n" "${GREEN}[AUTH] 验证码已发送给管理员${RESET}"

printf "%b\n" "${GREEN}[AUTH] 验证码有效时间：3分钟${RESET}"

echo ""




# ======================================
# Input Code
# ======================================


printf "%b" "${YELLOW}请输入验证码: ${RESET}"


read AUTH_CODE </dev/tty




if [ -z "$AUTH_CODE" ]; then


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




echo ""

printf "%b\n" "${GREEN}[AUTH] 正在验证...${RESET}"





# ======================================
# Verify
# ======================================


VERIFY_DATA="$(printf '{"code":"%s"}' "$AUTH_CODE")"




VERIFY_RESPONSE="$(curl -fsS \
--connect-timeout 10 \
-X POST \
-H "Content-Type: application/json" \
-d "$VERIFY_DATA" \
"$AUTH_SERVER/verify" \
2>/dev/null)"





if printf "%s" "$VERIFY_RESPONSE" | grep -q \
'"success"[[:space:]]*:[[:space:]]*true'
then


    printf "%b\n" "${GREEN}[AUTH] 授权成功${RESET}"

    echo ""


else


    printf "%b\n" "${RED}[ERROR] 授权失败${RESET}"

    echo "$VERIFY_RESPONSE"

    exit 1


fi





# ======================================
# Download
# ======================================


rm -rf "$WORKDIR"

mkdir -p "$WORKDIR"




printf "%b\n" "${BLUE}[INFO] Downloading latest version...${RESET}"




if ! wget \
-O "$WORKDIR/main.zip" \
"$REPO"
then


    printf "%b\n" "${RED}[ERROR] Download failed${RESET}"

    exit 1


fi





# ======================================
# Extract
# ======================================


printf "%b\n" "${BLUE}[INFO] Extracting...${RESET}"



if ! unzip -oq \
"$WORKDIR/main.zip" \
-d "$WORKDIR"
then


    printf "%b\n" "${RED}[ERROR] Extract failed${RESET}"

    exit 1


fi





# ======================================
# Start Installer
# ======================================


cd "$WORKDIR/Open-Pro-Installer-main" || exit 1




chmod +x install.sh

chmod +x lib/*.sh 2>/dev/null

chmod +x modules/*.sh 2>/dev/null





printf "%b\n" "${BLUE}[INFO] Starting installer...${RESET}"

echo ""




exec ./install.sh

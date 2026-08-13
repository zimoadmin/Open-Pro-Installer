#!/bin/sh


REPO="https://github.com/zimoadmin/Open-Pro-Installer/archive/refs/heads/main.zip"

WORKDIR="/tmp/Open-Pro-Installer"

AUTH_SERVER="https://openpro-auth.zimo4399.workers.dev"



echo "======================================"
echo "      Open-Pro-Installer Bootstrap"
echo "======================================"

echo ""



# ======================================
# 检查工具
# ======================================


for cmd in curl wget unzip; do

    if ! command -v "$cmd" >/dev/null 2>&1; then

        echo "[ERROR] Missing command: $cmd"

        exit 1

    fi

done




# ======================================
# 请求授权
# ======================================


echo "[AUTH] 正在申请授权..."



AUTH_RESPONSE="$(curl -fsS \
    --connect-timeout 10 \
    -X POST \
    "$AUTH_SERVER/request" \
    2>/dev/null)"




if [ -z "$AUTH_RESPONSE" ]; then


    echo "[ERROR] 授权服务器连接失败"

    exit 1


fi




if ! printf "%s" "$AUTH_RESPONSE" | grep -q '"success"[[:space:]]*:[[:space:]]*true'
then

    echo "[ERROR] 获取验证码失败"

    echo "$AUTH_RESPONSE"

    exit 1

fi




echo "[AUTH] 验证码已发送给管理员"

echo "[AUTH] 验证码有效时间：3分钟"

echo ""




# ======================================
# 输入验证码
# ======================================


printf "请输入验证码: "

read AUTH_CODE </dev/tty



if [ -z "$AUTH_CODE" ]; then


    echo ""

    echo "[ERROR] 验证码不能为空"

    exit 1


fi




case "$AUTH_CODE" in


    [0-9][0-9][0-9][0-9][0-9][0-9])

        ;;


    *)

        echo ""

        echo "[ERROR] 验证码必须是6位数字"

        exit 1

        ;;

esac





echo ""

echo "[AUTH] 正在验证..."





# ======================================
# 验证
# ======================================


VERIFY_DATA="$(printf \
'{"code":"%s"}' \
"$AUTH_CODE")"





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


    echo "[AUTH] 授权成功"

    echo ""


else


    echo "[ERROR] 授权失败"

    echo "$VERIFY_RESPONSE"

    exit 1


fi





# ======================================
# 下载程序
# ======================================


rm -rf "$WORKDIR"

mkdir -p "$WORKDIR"




echo "[INFO] Downloading latest version..."



if ! wget \
-O "$WORKDIR/main.zip" \
"$REPO"
then


    echo "[ERROR] Download failed"

    exit 1


fi




echo "[INFO] Extracting..."



if ! unzip -oq \
"$WORKDIR/main.zip" \
-d "$WORKDIR"
then


    echo "[ERROR] Extract failed"

    exit 1


fi





# ======================================
# 启动
# ======================================


cd "$WORKDIR/Open-Pro-Installer-main" || exit 1





chmod +x install.sh

chmod +x lib/*.sh 2>/dev/null

chmod +x modules/*.sh 2>/dev/null





echo ""

echo "[INFO] Starting installer..."

echo ""





exec ./install.sh

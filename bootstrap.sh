#!/bin/sh

REPO="https://github.com/zimoadmin/Open-Pro-Installer/archive/refs/heads/main.zip"
WORKDIR="/tmp/Open-Pro-Installer"
AUTH_SERVER="https://openpro-auth.zimo4399.workers.dev"

echo "======================================"
echo "      Open-Pro-Installer Bootstrap"
echo "======================================"
echo ""

# ======================================
# 检查必要工具
# ======================================

for cmd in curl wget unzip; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] Missing command: $cmd"
        exit 1
    fi
done

# ======================================
# 申请验证码
# ======================================

echo "[AUTH] 正在申请授权..."

AUTH_RESPONSE="$(curl -fsS -X POST "$AUTH_SERVER/request" 2>/dev/null)"

if [ $? -ne 0 ] || [ -z "$AUTH_RESPONSE" ]; then
    echo "[ERROR] 无法连接授权服务器"
    exit 1
fi

# ======================================
# 提取 request_id
# ======================================

REQUEST_ID="$(printf '%s' "$AUTH_RESPONSE" | sed -n \
    's/.*"request_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

if [ -z "$REQUEST_ID" ]; then
    echo "[ERROR] 申请验证码失败"
    echo "$AUTH_RESPONSE"
    exit 1
fi

echo "[AUTH] 验证码已发送给管理员"
echo "[AUTH] 验证码有效时间：3 分钟"
echo ""

# ======================================
# 从 SSH 终端读取验证码
# ======================================

printf "请输入验证码: " > /dev/tty

IFS= read -r AUTH_CODE < /dev/tty

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
        echo "[ERROR] 验证码必须是 6 位数字"
        exit 1
        ;;
esac

echo ""
echo "[AUTH] 正在验证..."

# ======================================
# 构造 JSON
# ======================================

VERIFY_DATA="$(printf '{"request_id":"%s","code":"%s"}' \
    "$REQUEST_ID" \
    "$AUTH_CODE")"

# ======================================
# 验证验证码
# ======================================

VERIFY_RESPONSE="$(curl -sS \
    -X POST \
    -H "Content-Type: application/json" \
    --data "$VERIFY_DATA" \
    "$AUTH_SERVER/verify" 2>/dev/null)"

if printf '%s' "$VERIFY_RESPONSE" | grep -q \
    '"success"[[:space:]]*:[[:space:]]*true'; then

    echo "[AUTH] 授权成功"
    echo ""

else

    echo "[ERROR] 授权失败"
    echo "$VERIFY_RESPONSE"
    exit 1

fi

# ======================================
# 清理旧目录
# ======================================

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

# ======================================
# 下载最新版
# ======================================

echo "[INFO] Downloading latest version..."

if ! wget -O "$WORKDIR/main.zip" "$REPO"; then
    echo "[ERROR] Download failed."
    exit 1
fi

# ======================================
# 解压
# ======================================

echo "[INFO] Extracting..."

if ! unzip -oq "$WORKDIR/main.zip" -d "$WORKDIR"; then
    echo "[ERROR] Unzip failed."
    exit 1
fi

# ======================================
# 进入项目目录
# ======================================

cd "$WORKDIR/Open-Pro-Installer-main" || exit 1

# ======================================
# 添加执行权限
# ======================================

chmod +x install.sh
chmod +x lib/*.sh 2>/dev/null
chmod +x modules/*.sh 2>/dev/null

# ======================================
# 启动安装器
# ======================================

echo "[INFO] Starting installer..."
echo ""

exec ./install.sh

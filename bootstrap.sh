#!/bin/sh

REPO="https://github.com/zimoadmin/Open-Pro-Installer/archive/refs/heads/main.zip"
WORKDIR="/tmp/Open-Pro-Installer"

echo "======================================"
echo "      Open-Pro-Installer Bootstrap"
echo "======================================"

# 检查工具
for cmd in wget unzip; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] Missing command: $cmd"
        exit 1
    fi
done

# 清理旧目录
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

echo "[INFO] Downloading latest version..."

if ! wget -O "$WORKDIR/main.zip" "$REPO"; then
    echo "[ERROR] Download failed."
    exit 1
fi

echo "[INFO] Extracting..."

if ! unzip -oq "$WORKDIR/main.zip" -d "$WORKDIR"; then
    echo "[ERROR] Unzip failed."
    exit 1
fi

cd "$WORKDIR/Open-Pro-Installer-main" || exit 1

chmod +x install.sh
chmod +x lib/*.sh
chmod +x modules/*.sh

echo "[INFO] Starting installer..."

exec ./install.sh

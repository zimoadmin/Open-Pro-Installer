#!/bin/sh

# ======================================
# Open-Pro-Installer
# SSR Plus+ Installer
# ======================================

install_ssrplus() {

    echo "======================================"
    echo "        SSR Plus+ Installer"
    echo "======================================"
    echo ""

    # ----------------------------------
    # STEP 1 检测系统
    # ----------------------------------

    echo "[INFO] 检测 OpenWrt 系统..."

    OPENWRT_VERSION="unknown"
    OPENWRT_TARGET="unknown"

    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release

        OPENWRT_VERSION="${DISTRIB_RELEASE:-unknown}"
        OPENWRT_TARGET="${DISTRIB_TARGET:-unknown}"
    fi

    echo "[INFO] OpenWrt Version : $OPENWRT_VERSION"
    echo "[INFO] Target          : $OPENWRT_TARGET"

    # ----------------------------------
    # STEP 2 检测 CPU
    # ----------------------------------

    ARCH="$(uname -m)"

    echo "[INFO] CPU Architecture: $ARCH"

    case "$ARCH" in
        x86_64)
            ARCH_TYPE="x86_64"
            ;;
        aarch64|arm64)
            ARCH_TYPE="aarch64"
            ;;
        armv7l|armv7*)
            ARCH_TYPE="arm"
            ;;
        mips*)
            ARCH_TYPE="mips"
            ;;
        *)
            ARCH_TYPE="$ARCH"
            ;;
    esac

    echo "[INFO] Architecture     : $ARCH_TYPE"
    echo ""

    # ----------------------------------
    # STEP 3 检测包管理器
    # ----------------------------------

    echo "[INFO] 检测包管理器..."

    if command -v apk >/dev/null 2>&1; then

        PKG_MANAGER="apk"

    elif command -v opkg >/dev/null 2>&1; then

        PKG_MANAGER="opkg"

    else

        echo "[ERROR] 未检测到 apk 或 opkg"
        echo "[ERROR] 当前系统暂不支持自动安装"
        return 1

    fi

    echo "[INFO] Package Manager : $PKG_MANAGER"
    echo ""

    # ----------------------------------
    # STEP 4 更新软件源
    # ----------------------------------

    echo "[INFO] 正在更新软件源..."

    if [ "$PKG_MANAGER" = "apk" ]; then

        if ! apk update; then
            echo "[ERROR] apk update 失败"
            return 1
        fi

    else

        if ! opkg update; then
            echo "[ERROR] opkg update 失败"
            return 1
        fi

    fi

    echo ""
    echo "[INFO] 软件源更新完成"
    echo ""

    # ----------------------------------
    # STEP 5 检查是否已经安装
    # ----------------------------------

    echo "[INFO] 检查 SSR Plus+ 是否已经安装..."

    if [ "$PKG_MANAGER" = "apk" ]; then

        if apk info -e luci-app-ssr-plus >/dev/null 2>&1; then

            echo "[OK] SSR Plus+ 已经安装"
            return 0

        fi

    else

        if opkg

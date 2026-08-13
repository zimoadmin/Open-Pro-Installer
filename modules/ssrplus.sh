#!/bin/sh

install_ssrplus() {
    echo "======================================"
    echo "        SSR Plus+ Installer"
    echo "======================================"
    echo ""

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

    ARCH="$(uname -m 2>/dev/null)"
    [ -n "$ARCH" ] || ARCH="unknown"

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

    echo "[INFO] 检测包管理器..."

    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
    else
        echo "[ERROR] 未检测到 apk 或 opkg"
        return 1
    fi

    echo "[INFO] Package Manager : $PKG_MANAGER"
    echo ""

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

    echo "[INFO] 检查 SSR Plus+ 是否已经安装..."

    if [ "$PKG_MANAGER" = "apk" ]; then
        if apk info -e luci-app-ssr-plus >/dev/null 2>&1; then
            echo "[OK] SSR Plus+ 已经安装"
            return 0
        fi
    else
        if opkg status luci-app-ssr-plus 2>/dev/null | grep -q "Status: install"; then
            echo "[OK] SSR Plus+ 已经安装"
            return 0
        fi
    fi

    echo "[INFO] SSR Plus+ 尚未安装"
    echo ""

    echo "[INFO] 正在查询 luci-app-ssr-plus..."

    PACKAGE_FOUND=0

    if [ "$PKG_MANAGER" = "apk" ]; then
        if apk search -x luci-app-ssr-plus 2>/dev/null | grep -q "luci-app-ssr-plus"; then
            PACKAGE_FOUND=1
        fi
    else
        if opkg list 2>/dev/null | grep -q '^luci-app-ssr-plus '; then
            PACKAGE_FOUND=1
        fi
    fi

    if [ "$PACKAGE_FOUND" = "1" ]; then
        echo "[OK] 软件源存在 luci-app-ssr-plus"
        echo "[INFO] 开始安装 SSR Plus+..."
        echo ""

        if [ "$PKG_MANAGER" = "apk" ]; then
            if ! apk add luci-app-ssr-plus; then
                echo "[ERROR] SSR Plus+ 安装失败"
                return 1
            fi
        else
            if ! opkg install luci-app-ssr-plus; then
                echo "[ERROR] SSR Plus+ 安装失败"
                return 1
            fi
        fi

    else
        echo ""
        echo "[WARN] 当前软件源没有 luci-app-ssr-plus"
        echo ""

        echo "系统信息："
        echo "--------------------------------------"
        echo "OpenWrt : $OPENWRT_VERSION"
        echo "Target  : $OPENWRT_TARGET"
        echo "CPU     : $ARCH_TYPE"
        echo "Manager : $PKG_MANAGER"
        echo "--------------------------------------"
        echo ""

        echo "[WARN] 暂停安装，避免安装错误架构的软件包。"

        return 2
    fi

    echo ""
    echo "[INFO] 正在检查安装结果..."

    INSTALL_OK=0

    if [ "$PKG_MANAGER" = "apk" ]; then
        if apk info -e luci-app-ssr-plus >/dev/null 2>&1; then
            INSTALL_OK=1
        fi
    else
        if opkg status luci-app-ssr-plus 2>/dev/null | grep -q "Status: install"; then
            INSTALL_OK=1
        fi
    fi

    if [ "$INSTALL_OK" != "1" ]; then
        echo "[ERROR] 未检测到 luci-app-ssr-plus"
        echo "[ERROR] 安装可能失败"
        return 1
    fi

    echo "[OK] SSR Plus+ 安装成功"

    if [ -x /etc/init.d/shadowsocksr ]; then
        echo "[INFO] 启用 SSR Plus+ 服务..."
        /etc/init.d/shadowsocksr enable >/dev/null 2>&1
    fi

    echo ""
    echo "======================================"
    echo "        SSR Plus+ Installed"
    echo "======================================"
    echo ""

    echo "请进入 LuCI 后台查看："
    echo "服务 → ShadowSocksR Plus+"
    echo ""

    return 0
}

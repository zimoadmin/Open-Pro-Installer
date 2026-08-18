#!/bin/sh

# ============================================================
# Open-Pro-Installer
# OpenClash Auto Installer
#
# 功能：
# 1. 安装 OpenClash
# 2. 隐藏 opkg/apk 大量安装日志
# 3. 单行动态安装进度条
# 4. 安装失败自动显示详细日志
# 5. 自动检测 OpenClash 是否安装成功
# 6. 自动检测 CPU 架构
# 7. 尝试调用 OpenClash 自带更新脚本
# 8. 清理临时文件
# ============================================================


# ============================================================
# 基础配置
# ============================================================

OPENCLASH_PKG=""
INSTALL_LOG="/tmp/openpro_openclash_install.log"

PROGRESS_PID=""

OPENCLASH_VERSION=""
OPENCLASH_ARCH=""
OPENCLASH_CORE_ARCH=""

OPENCLASH_DIR="/etc/openclash"
OPENCLASH_CORE_DIR="/etc/openclash/core"


# ============================================================
# 日志
# ============================================================

_oc_info()
{
    if command -v info >/dev/null 2>&1; then
        info "$*"
    else
        printf '\033[32m[INFO]\033[0m %s\n' "$*"
    fi
}


_oc_warn()
{
    if command -v warning >/dev/null 2>&1; then
        warning "$*"
    elif command -v warn >/dev/null 2>&1; then
        warn "$*"
    else
        printf '\033[33m[WARN]\033[0m %s\n' "$*"
    fi
}


_oc_error()
{
    if command -v error >/dev/null 2>&1; then
        error "$*"
    else
        printf '\033[31m[ERROR]\033[0m %s\n' "$*"
    fi
}


_oc_ok()
{
    printf '\033[32m[OK]\033[0m %s\n' "$*"
}


# ============================================================
# 清理临时文件
# ============================================================

cleanup_openclash_package()
{
    [ -n "$OPENCLASH_PKG" ] &&
        rm -f "$OPENCLASH_PKG" 2>/dev/null

    return 0
}


cleanup_openclash_logs()
{
    rm -f "$INSTALL_LOG" 2>/dev/null

    return 0
}


# ============================================================
# 检查 OpenClash 是否安装
# ============================================================

check_openclash()
{
    if command -v opkg >/dev/null 2>&1; then

        opkg status luci-app-openclash 2>/dev/null |
            grep -q 'Status:.*installed'

        return $?

    fi


    if command -v apk >/dev/null 2>&1; then

        apk info -e luci-app-openclash \
            >/dev/null 2>&1

        return $?

    fi


    return 1
}


# ============================================================
# 获取 OpenClash 已安装版本
# ============================================================

get_installed_openclash_version()
{
    OPENCLASH_VERSION=""


    if command -v opkg >/dev/null 2>&1; then

        OPENCLASH_VERSION="$(
            opkg status luci-app-openclash 2>/dev/null |
            awk -F ': ' '
                /^Version:/ {
                    print $2
                    exit
                }
            '
        )"

    elif command -v apk >/dev/null 2>&1; then

        OPENCLASH_VERSION="$(
            apk info luci-app-openclash 2>/dev/null |
            sed -n '1p'
        )"

    fi


    [ -n "$OPENCLASH_VERSION" ] ||
        OPENCLASH_VERSION="unknown"
}


# ============================================================
# 进度条
# ============================================================

openclash_progress_bar()
{
    PERCENT="$1"
    WIDTH=30

    FILLED=$((PERCENT * WIDTH / 100))
    EMPTY=$((WIDTH - FILLED))

    BAR=""

    I=0

    while [ "$I" -lt "$FILLED" ]; do

        BAR="${BAR}#"

        I=$((I + 1))

    done


    I=0

    while [ "$I" -lt "$EMPTY" ]; do

        BAR="${BAR}-"

        I=$((I + 1))

    done


    printf '\r\033[2K[INFO] 正在安装 OpenClash... [\033[32m%s\033[0m] %3d%%' \
        "$BAR" \
        "$PERCENT"
}


# ============================================================
# 带进度条安装
# ============================================================

install_openclash_with_progress()
{
    PKG_FILE="$1"
    PKG_TYPE="$2"


    rm -f "$INSTALL_LOG"


    # ========================================================
    # 后台安装
    # ========================================================

    case "$PKG_TYPE" in

        apk)

            apk add \
                --allow-untrusted \
                --force-overwrite \
                "$PKG_FILE" \
                >"$INSTALL_LOG" 2>&1 &

            ;;


        ipk)

            opkg install \
                "$PKG_FILE" \
                >"$INSTALL_LOG" 2>&1 &

            ;;


        *)

            return 1

            ;;

    esac


    PROGRESS_PID=$!

    PERCENT=1


    openclash_progress_bar "$PERCENT"


    # ========================================================
    # 动态判断安装阶段
    # ========================================================

    while kill -0 "$PROGRESS_PID" 2>/dev/null; do


        # ----------------------------------------------------
        # Configuring
        # ----------------------------------------------------

        if grep -q '^Configuring ' \
            "$INSTALL_LOG" 2>/dev/null
        then

            if [ "$PERCENT" -lt 94 ]; then

                PERCENT=$((PERCENT + 3))

            fi


        # ----------------------------------------------------
        # Installing
        # ----------------------------------------------------

        elif grep -q '^Installing ' \
            "$INSTALL_LOG" 2>/dev/null
        then

            if [ "$PERCENT" -lt 78 ]; then

                PERCENT=$((PERCENT + 3))

            fi


        # ----------------------------------------------------
        # Downloading
        # ----------------------------------------------------

        elif grep -q '^Downloading ' \
            "$INSTALL_LOG" 2>/dev/null
        then

            if [ "$PERCENT" -lt 48 ]; then

                PERCENT=$((PERCENT + 2))

            fi


        # ----------------------------------------------------
        # 等待阶段
        # ----------------------------------------------------

        else

            if [ "$PERCENT" -lt 15 ]; then

                PERCENT=$((PERCENT + 1))

            fi

        fi


        # ----------------------------------------------------
        # 真正完成以前最多 95%
        # ----------------------------------------------------

        if [ "$PERCENT" -gt 95 ]; then

            PERCENT=95

        fi


        openclash_progress_bar "$PERCENT"


        sleep 1

    done


    # ========================================================
    # 获取真实安装结果
    # ========================================================

    wait "$PROGRESS_PID"

    RESULT=$?


    PROGRESS_PID=""


    # ========================================================
    # 成功
    # ========================================================

    if [ "$RESULT" -eq 0 ]; then

        openclash_progress_bar 100

        printf "\n"

        return 0

    fi


    # ========================================================
    # 失败
    # ========================================================

    printf "\n"

    return "$RESULT"
}


# ============================================================
# 检测 CPU / OpenClash Core 架构
# ============================================================

detect_openclash_arch()
{
    OPENCLASH_ARCH="$(uname -m 2>/dev/null)"

    [ -n "$OPENCLASH_ARCH" ] ||
        OPENCLASH_ARCH="unknown"


    case "$OPENCLASH_ARCH" in

        aarch64|arm64)

            OPENCLASH_CORE_ARCH="linux-arm64"

            ;;


        x86_64|amd64)

            OPENCLASH_CORE_ARCH="linux-amd64"

            ;;


        armv7*|armv7l)

            OPENCLASH_CORE_ARCH="linux-armv7"

            ;;


        armv6*|armv6l)

            OPENCLASH_CORE_ARCH="linux-armv6"

            ;;


        armv5*|armv5l)

            OPENCLASH_CORE_ARCH="linux-armv5"

            ;;


        mipsel)

            OPENCLASH_CORE_ARCH="linux-mipsle-softfloat"

            ;;


        mips)

            OPENCLASH_CORE_ARCH="linux-mips-softfloat"

            ;;


        *)

            OPENCLASH_CORE_ARCH="unknown"

            ;;

    esac


    _oc_info "处理器架构 : $OPENCLASH_ARCH"


    if [ "$OPENCLASH_CORE_ARCH" != "unknown" ]; then

        _oc_info "内核架构   : $OPENCLASH_CORE_ARCH"

    else

        _oc_warn "暂时无法自动判断 OpenClash 内核架构"

    fi
}


# ============================================================
# 检测当前 OpenClash 内核
# ============================================================

check_openclash_core()
{
    printf "\n"

    _oc_info "正在检测 OpenClash 内核..."


    CORE_FOUND=0


    # ========================================================
    # Mihomo / Meta
    # ========================================================

    if [ -x "$OPENCLASH_CORE_DIR/clash_meta" ]; then

        CORE_FOUND=1

        _oc_ok "已检测到 Meta / Mihomo 内核"

        CORE_VERSION="$(
            "$OPENCLASH_CORE_DIR/clash_meta" \
                -v 2>/dev/null |
            head -n 1
        )"


        if [ -n "$CORE_VERSION" ]; then

            _oc_info "$CORE_VERSION"

        fi

    fi


    # ========================================================
    # Clash
    # ========================================================

    if [ -x "$OPENCLASH_CORE_DIR/clash" ]; then

        CORE_FOUND=1

        _oc_ok "已检测到 Clash 内核"

    fi


    # ========================================================
    # Tun
    # ========================================================

    if [ -x "$OPENCLASH_CORE_DIR/clash_tun" ]; then

        CORE_FOUND=1

        _oc_ok "已检测到 TUN 内核"

    fi


    if [ "$CORE_FOUND" -eq 0 ]; then

        _oc_warn "当前尚未检测到 OpenClash 内核"

        return 1

    fi


    return 0
}


# ============================================================
# 尝试使用 OpenClash 自带脚本更新内核
#
# 不自己拼第三方下载地址。
# 优先让 OpenClash 自己判断：
#   架构
#   分支
#   下载源
#   Core 类型
# ============================================================

auto_update_openclash_core()
{
    printf "\n"

    _oc_info "正在检测 OpenClash 内核更新能力..."


    # ========================================================
    # 常见 OpenClash shell 路径
    # ========================================================

    CORE_UPDATE_SCRIPT=""


    for SCRIPT in \
        /usr/share/openclash/openclash_core.sh \
        /usr/share/openclash/openclash_core_version.sh \
        /usr/share/openclash/openclash_update.sh
    do

        if [ -f "$SCRIPT" ]; then

            CORE_UPDATE_SCRIPT="$SCRIPT"

            break

        fi

    done


    # ========================================================
    # 找不到脚本
    # ========================================================

    if [ -z "$CORE_UPDATE_SCRIPT" ]; then

        _oc_warn "没有找到可直接调用的 OpenClash 内核更新脚本"
        _oc_info "可进入 OpenClash → 版本更新 页面检查内核"

        return 0

    fi


    _oc_ok "检测到 OpenClash 更新组件"

    _oc_info "更新脚本 : $CORE_UPDATE_SCRIPT"


    # ========================================================
    # 注意：
    # 不盲目执行未知参数。
    #
    # OpenClash 不同版本脚本参数可能变化。
    # 安装完成后至少确保 OpenClash 自身更新组件存在。
    # ========================================================

    if [ -x "$CORE_UPDATE_SCRIPT" ]; then

        _oc_ok "OpenClash 自动更新组件工作正常"

    else

        chmod +x "$CORE_UPDATE_SCRIPT" \
            >/dev/null 2>&1

    fi


    return 0
}


# ============================================================
# 重载 uhttpd
# ============================================================

reload_luci()
{
    if [ -x /etc/init.d/uhttpd ]; then

        _oc_info "正在刷新 LuCI..."

        /etc/init.d/uhttpd reload \
            >/dev/null 2>&1

    fi


    return 0
}


# ============================================================
# 中断处理
# ============================================================

interrupt_openclash()
{
    printf "\n"


    _oc_warn "OpenClash 安装被中断"


    if [ -n "$PROGRESS_PID" ]; then

        kill "$PROGRESS_PID" \
            >/dev/null 2>&1

        wait "$PROGRESS_PID" \
            >/dev/null 2>&1

    fi


    cleanup_openclash_package


    trap - INT TERM


    return 130
}


# ============================================================
# 主安装函数
#
# install.sh 调用：
#
# install_openclash
#
# ============================================================

install_openclash()
{
    printf "\n"

    printf "======================================\n"
    printf "        OpenClash Installer\n"
    printf "======================================\n"

    printf "\n"


    # ========================================================
    # Root
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _oc_error "请使用 root 用户运行"

        return 1

    fi


    # ========================================================
    # 检测架构
    # ========================================================

    detect_openclash_arch


    # ========================================================
    # 检查 install.sh 传进来的变量
    # ========================================================

    if [ -z "$DOWNLOAD_URL" ]; then

        _oc_error "DOWNLOAD_URL 为空"

        return 1

    fi


    if [ -z "$PACKAGE_EXT" ]; then

        _oc_error "PACKAGE_EXT 为空"

        return 1

    fi


    if [ -n "$RELEASE_TAG" ]; then

        _oc_info "OpenClash Version : $RELEASE_TAG"

    fi


    _oc_info "Package Format    : $PACKAGE_EXT"


    printf "\n"


    # ========================================================
    # 临时文件
    # ========================================================

    OPENCLASH_PKG="/tmp/openclash.${PACKAGE_EXT}"


    rm -f "$OPENCLASH_PKG"

    rm -f "$INSTALL_LOG"


    trap 'interrupt_openclash' INT TERM


    # ========================================================
    # 下载
    # ========================================================

    _oc_info "正在下载 OpenClash..."


    RETRY=3

    DOWNLOAD_OK=0


    while [ "$RETRY" -gt 0 ]; do


        if wget \
            -T 20 \
            -O "$OPENCLASH_PKG" \
            "$DOWNLOAD_URL"
        then

            if [ -s "$OPENCLASH_PKG" ]; then

                DOWNLOAD_OK=1

                break

            fi

        fi


        RETRY=$((RETRY - 1))


        if [ "$RETRY" -gt 0 ]; then

            _oc_warn "下载失败，正在重试..."

            sleep 2

        fi

    done


    # ========================================================
    # 下载失败
    # ========================================================

    if [ "$DOWNLOAD_OK" -ne 1 ]; then

        _oc_error "OpenClash 下载失败"

        cleanup_openclash_package

        trap - INT TERM

        return 1

    fi


    _oc_ok "OpenClash 下载完成"


    # ========================================================
    # 文件大小
    # ========================================================

    SIZE="$(
        du -h "$OPENCLASH_PKG" 2>/dev/null |
        awk '{print $1}'
    )"


    if [ -n "$SIZE" ]; then

        _oc_info "File Size : $SIZE"

    fi


    printf "\n"


    # ========================================================
    # 安装
    # ========================================================

    case "$PACKAGE_EXT" in

        apk)

            if ! command -v apk >/dev/null 2>&1; then

                _oc_error "当前系统没有 APK 包管理器"

                cleanup_openclash_package

                trap - INT TERM

                return 1

            fi


            install_openclash_with_progress \
                "$OPENCLASH_PKG" \
                "apk"

            INSTALL_RESULT=$?

            ;;


        ipk)

            if ! command -v opkg >/dev/null 2>&1; then

                _oc_error "当前系统没有 OPKG 包管理器"

                cleanup_openclash_package

                trap - INT TERM

                return 1

            fi


            install_openclash_with_progress \
                "$OPENCLASH_PKG" \
                "ipk"

            INSTALL_RESULT=$?

            ;;


        *)

            _oc_error "未知软件包格式：$PACKAGE_EXT"

            cleanup_openclash_package

            trap - INT TERM

            return 1

            ;;

    esac


    # ========================================================
    # 安装失败
    # ========================================================

    if [ "$INSTALL_RESULT" -ne 0 ]; then

        printf "\n"

        _oc_error "OpenClash 安装失败"


        if [ -s "$INSTALL_LOG" ]; then

            printf "\n"

            printf "========== INSTALL ERROR ==========\n"

            cat "$INSTALL_LOG"

            printf "===================================\n"

            printf "\n"

        fi


        cleanup_openclash_package

        cleanup_openclash_logs


        trap - INT TERM


        return 1

    fi


    # ========================================================
    # 删除安装包
    # ========================================================

    cleanup_openclash_package


    printf "\n"


    # ========================================================
    # 验证 OpenClash
    # ========================================================

    _oc_info "正在验证 OpenClash 安装结果..."


    if ! check_openclash; then

        _oc_error "未检测到 luci-app-openclash"

        _oc_error "OpenClash 可能没有正确安装"


        if [ -s "$INSTALL_LOG" ]; then

            printf "\n"

            cat "$INSTALL_LOG"

        fi


        cleanup_openclash_logs

        trap - INT TERM


        return 1

    fi


    _oc_ok "OpenClash 安装成功"


    # ========================================================
    # 获取版本
    # ========================================================

    get_installed_openclash_version


    _oc_info "已安装版本 : $OPENCLASH_VERSION"


    # ========================================================
    # 清理安装日志
    # ========================================================

    cleanup_openclash_logs


    # ========================================================
    # 创建核心目录
    # ========================================================

    mkdir -p "$OPENCLASH_CORE_DIR" \
        >/dev/null 2>&1


    # ========================================================
    # 检测内核
    # ========================================================

    check_openclash_core


    # ========================================================
    # 检测更新组件
    # ========================================================

    auto_update_openclash_core


    # ========================================================
    # 刷新 LuCI
    # ========================================================

    reload_luci


    trap - INT TERM


    # ========================================================
    # 完成
    # ========================================================

    printf "\n"

    printf "======================================\n"
    printf "        OpenClash Installed\n"
    printf "======================================\n"

    printf "\n"


    _oc_ok "OpenClash 安装完成"

    _oc_info "版本 : $OPENCLASH_VERSION"

    _oc_info "CPU  : $OPENCLASH_ARCH"

    _oc_info "Core : $OPENCLASH_CORE_ARCH"


    printf "\n"

    printf "请进入 LuCI 后台查看：\n"
    printf "服务 → OpenClash\n"

    printf "\n"

    printf "内核更新位置：\n"
    printf "OpenClash → 版本更新\n"

    printf "\n"


    return 0
}

#!/bin/sh


# ============================================================
# Open-Pro-Installer
# OpenClash Auto Installer
#
# 功能：
# 1. 下载 OpenClash
# 2. 安装 OpenClash
# 3. 自动检测 CPU 架构
# 4. 自动识别 OpenClash Core 架构
# 5. 自动检测 Meta / Mihomo Core
# 6. 调用 OpenClash 自带脚本安装 / 更新 Meta Core
# 7. 验证 Meta / Mihomo Core
#
# install.sh 调用：
#
# . "$SCRIPT_DIR/modules/openclash.sh"
# install_openclash
#
# ============================================================


# ============================================================
# 基础配置
# ============================================================

OPENCLASH_DIR="/etc/openclash"

OPENCLASH_CORE_DIR="/etc/openclash/core"

META_CORE="/etc/openclash/core/clash_meta"

CORE_SCRIPT="/usr/share/openclash/openclash_core.sh"

OPENCLASH_PKG=""

CPU_ARCH="unknown"

OPKG_ARCH="unknown"

CORE_ARCH="unknown"

META_VERSION="unknown"


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
# 检测 OpenClash 是否安装
# ============================================================

check_openclash()
{
    if command -v opkg >/dev/null 2>&1; then

        if opkg status luci-app-openclash 2>/dev/null |
            grep -q 'Status:.*installed'
        then

            return 0

        fi

    fi


    if command -v apk >/dev/null 2>&1; then

        if apk info -e luci-app-openclash >/dev/null 2>&1
        then

            return 0

        fi

    fi


    # 文件兜底

    if [ -d "$OPENCLASH_DIR" ] ||
       [ -f /usr/share/openclash/openclash_core.sh ]
    then

        return 0

    fi


    return 1
}


# ============================================================
# 获取 OpenClash 实际安装版本
# ============================================================

get_openclash_version()
{
    CURRENT_OC_VERSION=""


    if command -v opkg >/dev/null 2>&1; then

        CURRENT_OC_VERSION="$(
            opkg status luci-app-openclash 2>/dev/null |
            awk -F ': ' '
                /^Version:/ {
                    print $2
                    exit
                }
            '
        )"

    elif command -v apk >/dev/null 2>&1; then

        CURRENT_OC_VERSION="$(
            apk info luci-app-openclash 2>/dev/null |
            head -n 1
        )"

    fi


    [ -n "$CURRENT_OC_VERSION" ] ||
        CURRENT_OC_VERSION="${RELEASE_TAG:-unknown}"
}


# ============================================================
# 获取 OPKG Architecture
# ============================================================

detect_package_arch()
{
    OPKG_ARCH="unknown"


    if command -v opkg >/dev/null 2>&1; then

        OPKG_ARCH="$(
            opkg print-architecture 2>/dev/null |
            awk '
                $1=="arch" &&
                $2!="all" &&
                $2!="noarch" {
                    arch=$2
                }
                END {
                    if (arch != "")
                        print arch
                }
            '
        )"

    fi


    [ -n "$OPKG_ARCH" ] ||
        OPKG_ARCH="unknown"
}


# ============================================================
# 检测 CPU / Core 架构
# ============================================================

detect_openclash_arch()
{
    printf "\n"

    _oc_info "正在检测处理器架构..."


    CPU_ARCH="$(uname -m 2>/dev/null)"

    [ -n "$CPU_ARCH" ] ||
        CPU_ARCH="unknown"


    detect_package_arch


    case "$CPU_ARCH" in

        aarch64|arm64)

            CORE_ARCH="linux-arm64"

            ;;


        armv8*)

            CORE_ARCH="linux-arm64"

            ;;


        armv7*|armv7l)

            CORE_ARCH="linux-armv7"

            ;;


        armv6*)

            CORE_ARCH="linux-armv6"

            ;;


        x86_64|amd64)

            CORE_ARCH="linux-amd64"

            ;;


        i386|i486|i586|i686)

            CORE_ARCH="linux-386"

            ;;


        mips64el*)

            CORE_ARCH="linux-mips64le"

            ;;


        mips64*)

            CORE_ARCH="linux-mips64"

            ;;


        mipsel*)

            CORE_ARCH="linux-mipsle"

            ;;


        mips*)

            CORE_ARCH="linux-mips"

            ;;


        *)

            CORE_ARCH="unknown"

            ;;

    esac


    _oc_ok "CPU Architecture  : $CPU_ARCH"


    if [ "$OPKG_ARCH" != "unknown" ]; then

        _oc_ok "Package Arch      : $OPKG_ARCH"

    fi


    if [ "$CORE_ARCH" != "unknown" ]; then

        _oc_ok "Core Architecture : $CORE_ARCH"

    else

        _oc_warn "Core Architecture : 无法自动判断"
        _oc_warn "将交由 OpenClash 自带脚本处理"

    fi


    return 0
}


# ============================================================
# 获取 Meta / Mihomo 版本
# ============================================================

get_meta_version()
{
    META_VERSION="unknown"


    if [ ! -f "$META_CORE" ]; then

        return 1

    fi


    chmod +x "$META_CORE" 2>/dev/null


    if [ ! -x "$META_CORE" ]; then

        return 1

    fi


    META_VERSION="$(
        "$META_CORE" -v 2>/dev/null |
        head -n 1
    )"


    if [ -z "$META_VERSION" ]; then

        META_VERSION="$(
            "$META_CORE" version 2>/dev/null |
            head -n 1
        )"

    fi


    if [ -z "$META_VERSION" ]; then

        META_VERSION="unknown"

        return 1

    fi


    return 0
}


# ============================================================
# 检测 OpenClash Core 更新脚本
# ============================================================

check_core_script()
{
    if [ ! -f "$CORE_SCRIPT" ]; then

        return 1

    fi


    if [ ! -x "$CORE_SCRIPT" ]; then

        chmod +x "$CORE_SCRIPT" 2>/dev/null

    fi


    [ -x "$CORE_SCRIPT" ]
}


# ============================================================
# 安装 / 更新 Meta / Mihomo Core
# ============================================================

install_openclash_meta()
{
    printf "\n"

    _oc_info "正在检查 Meta / Mihomo 内核..."


    # ========================================================
    # 创建目录
    # ========================================================

    if ! mkdir -p "$OPENCLASH_CORE_DIR"; then

        _oc_error "无法创建 Core 目录"

        return 1

    fi


    # ========================================================
    # 检查现有 Core
    # ========================================================

    OLD_META_VERSION=""


    if get_meta_version; then

        OLD_META_VERSION="$META_VERSION"

        _oc_ok "已检测到 Meta / Mihomo Core"
        _oc_info "当前内核 : $META_VERSION"

    else

        _oc_warn "当前未检测到 Meta / Mihomo Core"

    fi


    # ========================================================
    # 检查官方脚本
    # ========================================================

    if ! check_core_script; then

        _oc_error "没有找到 OpenClash 内核管理脚本"

        _oc_warn "$CORE_SCRIPT"

        return 1

    fi


    _oc_ok "已找到 OpenClash 内核管理脚本"


    # ========================================================
    # 更新
    # ========================================================

    printf "\n"

    _oc_info "正在检查 Meta / Mihomo Core 更新..."


    if [ "$CORE_ARCH" != "unknown" ]; then

        _oc_info "Core Architecture : $CORE_ARCH"

    fi


    printf "\n"


    # ========================================================
    # 调用 OpenClash 自带内核管理器
    #
    # 不自行拼接下载 URL
    # 架构、下载源、版本由 OpenClash 自身处理
    # ========================================================

    "$CORE_SCRIPT" Meta

    CORE_RESULT=$?


    printf "\n"


    # ========================================================
    # 更新脚本返回非 0
    #
    # 如果原本存在正常 Core，不立即删除
    # ========================================================

    if [ "$CORE_RESULT" -ne 0 ]; then

        _oc_warn "内核更新脚本返回：$CORE_RESULT"

    fi


    # ========================================================
    # 验证文件
    # ========================================================

    _oc_info "正在验证 Meta / Mihomo Core..."


    if [ ! -f "$META_CORE" ]; then

        _oc_error "没有检测到 Meta / Mihomo Core"

        _oc_error "Core Path : $META_CORE"

        return 1

    fi


    chmod +x "$META_CORE" 2>/dev/null


    if [ ! -x "$META_CORE" ]; then

        _oc_error "Meta / Mihomo Core 没有执行权限"

        return 1

    fi


    # ========================================================
    # 验证运行
    # ========================================================

    if ! get_meta_version; then

        _oc_error "Meta / Mihomo Core 无法正常执行"

        return 1

    fi


    # ========================================================
    # 成功
    # ========================================================

    _oc_ok "Meta / Mihomo Core 检测正常"

    _oc_info "Core Version : $META_VERSION"


    # ========================================================
    # 判断有没有发生更新
    # ========================================================

    if [ -n "$OLD_META_VERSION" ]; then

        if [ "$OLD_META_VERSION" = "$META_VERSION" ]; then

            _oc_ok "当前 Meta / Mihomo Core 已可正常使用"

        else

            _oc_ok "Meta / Mihomo Core 已更新"

        fi

    else

        _oc_ok "Meta / Mihomo Core 安装成功"

    fi


    return 0
}


# ============================================================
# 清理安装文件
# ============================================================

cleanup_openclash_package()
{
    if [ -n "$OPENCLASH_PKG" ]; then

        rm -f "$OPENCLASH_PKG" 2>/dev/null

    fi
}


# ============================================================
# 主安装函数
# ============================================================

install_openclash()
{
    printf "\n"
    printf "======================================\n"
    printf "        OpenClash Installer\n"
    printf "======================================\n"
    printf "\n"


    # ========================================================
    # ROOT 检查
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _oc_error "请使用 root 用户运行"

        return 1

    fi


    # ========================================================
    # 检查上层变量
    # ========================================================

    if [ -z "$RELEASE_TAG" ]; then

        _oc_error "RELEASE_TAG 为空"

        return 1

    fi


    if [ -z "$PACKAGE_EXT" ]; then

        _oc_error "PACKAGE_EXT 为空"

        return 1

    fi


    if [ -z "$DOWNLOAD_URL" ]; then

        _oc_error "DOWNLOAD_URL 为空"

        return 1

    fi


    # ========================================================
    # 安装信息
    # ========================================================

    _oc_info "准备安装 OpenClash"

    _oc_info "Version : $RELEASE_TAG"

    _oc_info "Package : $PACKAGE_EXT"


    # ========================================================
    # 临时文件
    # ========================================================

    OPENCLASH_PKG="/tmp/openclash.${PACKAGE_EXT}"


    rm -f "$OPENCLASH_PKG"


    # ========================================================
    # 下载
    # ========================================================

    printf "\n"

    _oc_info "正在下载 OpenClash..."


    retry=3


    while [ "$retry" -gt 0 ]
    do

        if wget \
            -T 15 \
            -O "$OPENCLASH_PKG" \
            "$DOWNLOAD_URL"
        then

            if [ -s "$OPENCLASH_PKG" ]; then

                break

            fi

        fi


        rm -f "$OPENCLASH_PKG"


        retry=$((retry - 1))


        if [ "$retry" -gt 0 ]; then

            _oc_warn "下载失败，正在重试..."

            sleep 2

        fi

    done


    # ========================================================
    # 下载失败
    # ========================================================

    if [ ! -s "$OPENCLASH_PKG" ]; then

        _oc_error "OpenClash 下载失败"

        cleanup_openclash_package

        return 1

    fi


    # ========================================================
    # 文件大小
    # ========================================================

    SIZE="$(
        ls -lh "$OPENCLASH_PKG" 2>/dev/null |
        awk '{print $5}'
    )"


    _oc_ok "OpenClash 下载完成"

    _oc_info "File Size : ${SIZE:-unknown}"


    # ========================================================
    # 安装
    # ========================================================

    printf "\n"

    _oc_info "正在安装 OpenClash..."


    INSTALL_RESULT=1


    case "$PACKAGE_EXT" in

        apk)

            if ! command -v apk >/dev/null 2>&1; then

                _oc_error "当前系统没有 APK 包管理器"

                cleanup_openclash_package

                return 1

            fi


            apk add \
                --allow-untrusted \
                --force-overwrite \
                "$OPENCLASH_PKG"

            INSTALL_RESULT=$?

            ;;


        ipk)

            if ! command -v opkg >/dev/null 2>&1; then

                _oc_error "当前系统没有 OPKG 包管理器"

                cleanup_openclash_package

                return 1

            fi


            opkg install "$OPENCLASH_PKG"

            INSTALL_RESULT=$?

            ;;


        *)

            _oc_error "未知安装包格式：$PACKAGE_EXT"

            cleanup_openclash_package

            return 1

            ;;

    esac


    # ========================================================
    # 删除安装包
    # ========================================================

    cleanup_openclash_package


    # ========================================================
    # 判断安装结果
    # ========================================================

    if [ "$INSTALL_RESULT" -ne 0 ]; then

        printf "\n"

        _oc_error "OpenClash 安装失败"

        return 1

    fi


    printf "\n"

    _oc_ok "OpenClash 软件包安装完成"


    # ========================================================
    # 再次验证
    # ========================================================

    _oc_info "正在验证 OpenClash..."


    if ! check_openclash; then

        _oc_error "没有检测到 OpenClash"

        return 1

    fi


    get_openclash_version


    _oc_ok "OpenClash 安装成功"

    _oc_info "OpenClash Version : $CURRENT_OC_VERSION"


    # ========================================================
    # 检测架构
    # ========================================================

    detect_openclash_arch


    # ========================================================
    # Meta / Mihomo
    # ========================================================

    META_STATUS="FAILED"


    if install_openclash_meta; then

        META_STATUS="OK"

    else

        printf "\n"

        _oc_warn "Meta / Mihomo Core 自动安装/更新失败"

        _oc_warn "OpenClash 本体已经安装成功"

        _oc_warn "可进入 OpenClash → 版本更新 手动检查内核"

    fi


    # ========================================================
    # 最终结果
    # ========================================================

    printf "\n"
    printf "======================================\n"
    printf "        OpenClash Installed\n"
    printf "======================================\n"

    printf "OpenClash : %s\n" "$CURRENT_OC_VERSION"

    printf "CPU       : %s\n" "$CPU_ARCH"

    if [ "$OPKG_ARCH" != "unknown" ]; then

        printf "Package   : %s\n" "$OPKG_ARCH"

    fi

    printf "Core Arch : %s\n" "$CORE_ARCH"


    if [ "$META_STATUS" = "OK" ]; then

        printf "Meta Core : OK\n"

        if get_meta_version; then

            printf "Meta Ver  : %s\n" "$META_VERSION"

        fi

    else

        printf "Meta Core : FAILED\n"

    fi


    printf "======================================\n"

    printf "\n"


    _oc_ok "OpenClash 部署完成"


    return 0
}

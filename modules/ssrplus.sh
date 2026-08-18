#!/bin/sh

# ============================================================
# Open-Pro-Installer
# SSR Plus+ Auto Installer
#
# 流程：
# 1. 检测设备
# 2. 检测处理器/平台
# 3. 检测 OpenWrt
# 4. 检测 Kernel
# 5. 检测 32/64 位
# 6. 自动匹配软件源
# 7. 备份原始软件源
# 8. 临时添加软件源
# 9. 安装 SSR Plus+
# 10. 恢复原始软件源
# ============================================================


# ============================================================
# 基础配置
# ============================================================

SSR_BASE="http://glinet.83970255.xyz/?f="

BACKUP_DIR="/tmp/openpro_ssrplus_backup"

CUSTOMFEEDS="/etc/opkg/customfeeds.conf"
DISTFEEDS="/etc/opkg/distfeeds.conf"

FEED_NAME=""


# ============================================================
# 日志兼容
# ============================================================

_ssr_info()
{
    if command -v info >/dev/null 2>&1; then
        info "$*"
    else
        printf '\033[32m[INFO]\033[0m %s\n' "$*"
    fi
}


_ssr_warn()
{
    if command -v warn >/dev/null 2>&1; then
        warn "$*"
    else
        printf '\033[33m[WARN]\033[0m %s\n' "$*"
    fi
}


_ssr_error()
{
    if command -v error >/dev/null 2>&1; then
        error "$*"
    else
        printf '\033[31m[ERROR]\033[0m %s\n' "$*"
    fi
}


_ssr_ok()
{
    printf '\033[32m[OK]\033[0m %s\n' "$*"
}


# ============================================================
# 获取设备信息
# ============================================================

detect_system()
{

    _ssr_info "正在检测设备信息..."

    MODEL="unknown"
    OPENWRT_VERSION="unknown"
    OPENWRT_TARGET="unknown"
    KERNEL_VERSION="$(uname -r 2>/dev/null)"
    ARCH="$(uname -m 2>/dev/null)"

    [ -n "$KERNEL_VERSION" ] || KERNEL_VERSION="unknown"
    [ -n "$ARCH" ] || ARCH="unknown"


    # --------------------------------------------------------
    # 获取型号
    # --------------------------------------------------------

    if [ -f /tmp/sysinfo/model ]; then

        MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"

    elif [ -f /proc/device-tree/model ]; then

        MODEL="$(tr -d '\000' </proc/device-tree/model 2>/dev/null)"

    fi


    # --------------------------------------------------------
    # OpenWrt 信息
    # --------------------------------------------------------

    if [ -f /etc/openwrt_release ]; then

        . /etc/openwrt_release

        OPENWRT_VERSION="${DISTRIB_RELEASE:-unknown}"
        OPENWRT_TARGET="${DISTRIB_TARGET:-unknown}"

    fi


    # --------------------------------------------------------
    # 位数
    # --------------------------------------------------------

    case "$ARCH" in

        x86_64|aarch64|arm64|mips64*)
            BITS="64"
            ;;

        armv7*|armv6*|mips|mipsel|mips32*)
            BITS="32"
            ;;

        *)
            LONG_BIT="$(getconf LONG_BIT 2>/dev/null)"

            case "$LONG_BIT" in
                32|64)
                    BITS="$LONG_BIT"
                    ;;
                *)
                    BITS="unknown"
                    ;;
            esac
            ;;

    esac


    # --------------------------------------------------------
    # 平台识别
    # --------------------------------------------------------

    DETECT_STRING="$(printf '%s %s' "$MODEL" "$OPENWRT_TARGET" | tr '[:upper:]' '[:lower:]')"

    PLATFORM="unknown"


    # Mudi7 优先判断
    case "$DETECT_STRING" in
        *e5800*|*mudi7*|*sdx72*)
            PLATFORM="SDX72"
            ;;
    esac


    if [ "$PLATFORM" = "unknown" ]; then

        case "$DETECT_STRING" in

            *mt798*|*mt2500*|*mt3000*|*mt5000*|*mt6000*|*mt3600*)
                PLATFORM="MT798X"
                ;;

            *ipq6000*|*ax1800*|*axt1800*)
                PLATFORM="IPQ6000"
                ;;

            *ipq53*|*ipq5312*|*be3600*|*be6500*|*be9300*)
                PLATFORM="IPQ53XX"
                ;;

            *ipq5018*|*b3000*)
                PLATFORM="IPQ5018"
                ;;

            *ipq401*|*b1300*)
                PLATFORM="IPQ401X"
                ;;

        esac

    fi


    printf "\n"
    printf "======================================\n"
    printf "          设备检测结果\n"
    printf "======================================\n"
    printf "机型     : %s\n" "$MODEL"
    printf "平台     : %s\n" "$PLATFORM"
    printf "OpenWrt  : %s\n" "$OPENWRT_VERSION"
    printf "Target   : %s\n" "$OPENWRT_TARGET"
    printf "Kernel   : %s\n" "$KERNEL_VERSION"
    printf "架构     : %s\n" "$ARCH"
    printf "系统     : %s 位\n" "$BITS"
    printf "======================================\n"
    printf "\n"

}


# ============================================================
# 匹配软件源
# ============================================================

match_feed()
{

    FEED_PATH=""
    FEED_NAME=""


    # ========================================================
    # MT798X
    # ========================================================

    if [ "$PLATFORM" = "MT798X" ]; then


        # OpenWrt 21 + Kernel 5.4 + 64位

        case "$OPENWRT_VERSION" in

            21.*)

                case "$KERNEL_VERSION" in

                    5.4.*)

                        if [ "$BITS" = "64" ]; then

                            FEED_PATH="/mt798x-openwrt21"
                            FEED_NAME="MT798X / OpenWrt 21 / Kernel 5.4 / 64位"

                        fi

                        ;;

                esac

                ;;


            # OpenWrt 24 + Kernel 6.6 + 64位

            24.*)

                case "$KERNEL_VERSION" in

                    6.6.*)

                        if [ "$BITS" = "64" ]; then

                            FEED_PATH="/mt798x-openwrt24"
                            FEED_NAME="MT798X / OpenWrt 24 / Kernel 6.6 / 64位"

                        fi

                        ;;

                esac

                ;;

        esac

    fi


    # ========================================================
    # IPQ6000
    # ========================================================

    if [ "$PLATFORM" = "IPQ6000" ]; then

        if [ "$BITS" = "64" ]; then

            case "$OPENWRT_VERSION" in

                23.*)

                    FEED_PATH="/ipq6000-tip-64bit"
                    FEED_NAME="IPQ6000 / OpenWrt 23 / 64位"

                    ;;

            esac


        elif [ "$BITS" = "32" ]; then

            FEED_PATH="/ipq6000-2023-09-不再更新"
            FEED_NAME="IPQ6000 / 32位旧系统"

            _ssr_warn "当前 IPQ6000 为32位旧系统"
            _ssr_warn "对应软件源已经停止更新"

        fi

    fi


    # ========================================================
    # IPQ53XX
    # ========================================================

    if [ "$PLATFORM" = "IPQ53XX" ]; then

        case "$OPENWRT_VERSION" in

            23.*)

                if [ "$BITS" = "64" ]; then

                    FEED_PATH="/ipq5312-qsdk12-5-64bit"
                    FEED_NAME="IPQ53XX / OpenWrt 23.05 / QSDK 12.5 / 64位"

                fi

                ;;

        esac

    fi


    # ========================================================
    # IPQ5018 / B3000
    # ========================================================

    if [ "$PLATFORM" = "IPQ5018" ]; then

        case "$OPENWRT_VERSION" in

            19.*)

                if [ "$BITS" = "64" ]; then

                    FEED_PATH="/b3000-qsdk12-2"
                    FEED_NAME="IPQ5018 / B3000 / OpenWrt 19.07 / 64位"

                fi

                ;;

        esac

    fi


    # ========================================================
    # IPQ401X
    # ========================================================

    if [ "$PLATFORM" = "IPQ401X" ]; then

        case "$OPENWRT_VERSION" in

            21.*)

                if [ "$BITS" = "32" ]; then

                    FEED_PATH="/ipq4019"
                    FEED_NAME="IPQ401X / OpenWrt 21 / 32位"

                fi

                ;;

        esac

    fi


    # ========================================================
    # Mudi7 / E5800
    # ========================================================

    if [ "$PLATFORM" = "SDX72" ]; then

        case "$OPENWRT_VERSION" in

            23.*)

                if [ "$BITS" = "64" ]; then

                    FEED_PATH="/mudi7"
                    FEED_NAME="Mudi7 / SDX72 / OpenWrt 23.05 / 64位"

                fi

                ;;

        esac

    fi


    # ========================================================
    # 没有匹配
    # ========================================================

    if [ -z "$FEED_PATH" ]; then

        _ssr_error "没有找到适用于当前设备的软件源"

        printf "\n"
        printf "系统信息：\n"
        printf "--------------------------------------\n"
        printf "机型    : %s\n" "$MODEL"
        printf "平台    : %s\n" "$PLATFORM"
        printf "OpenWrt : %s\n" "$OPENWRT_VERSION"
        printf "Kernel  : %s\n" "$KERNEL_VERSION"
        printf "架构    : %s\n" "$ARCH"
        printf "位数    : %s\n" "$BITS"
        printf "--------------------------------------\n"
        printf "\n"

        _ssr_warn "为避免安装错误架构的软件包，已取消安装。"

        return 1

    fi


    _ssr_ok "已自动匹配软件源"
    _ssr_info "$FEED_NAME"

    printf "\n"

    return 0

}


# ============================================================
# 备份软件源
# ============================================================

backup_feeds()
{

    _ssr_info "正在备份原始软件源..."

    rm -rf "$BACKUP_DIR"

    mkdir -p "$BACKUP_DIR" || return 1


    if [ -f "$DISTFEEDS" ]; then

        cp "$DISTFEEDS" \
        "$BACKUP_DIR/distfeeds.conf"

    fi


    if [ -f "$CUSTOMFEEDS" ]; then

        cp "$CUSTOMFEEDS" \
        "$BACKUP_DIR/customfeeds.conf"

    else

        touch "$BACKUP_DIR/customfeeds.notexist"

    fi


    _ssr_ok "原始软件源备份完成"

}


# ============================================================
# 添加临时软件源
# ============================================================

add_temp_feeds()
{

    _ssr_info "正在添加 SSR Plus+ 临时软件源..."


    mkdir -p /etc/opkg


    # 删除以前可能残留的 Open-Pro 源

    if [ -f "$CUSTOMFEEDS" ]; then

        sed -i \
        '/^src\/gz openpro_/d' \
        "$CUSTOMFEEDS"

    fi


    printf '\n' >> "$CUSTOMFEEDS"


    printf 'src/gz openpro_packages %s%s/packages\n' \
        "$SSR_BASE" \
        "$FEED_PATH" \
        >> "$CUSTOMFEEDS"


    printf 'src/gz openpro_luci %s%s/luci\n' \
        "$SSR_BASE" \
        "$FEED_PATH" \
        >> "$CUSTOMFEEDS"


    printf 'src/gz openpro_base %s%s/base\n' \
        "$SSR_BASE" \
        "$FEED_PATH" \
        >> "$CUSTOMFEEDS"


    _ssr_ok "临时软件源添加完成"

    printf "\n"

    _ssr_info "Packages : ${SSR_BASE}${FEED_PATH}/packages"
    _ssr_info "LuCI     : ${SSR_BASE}${FEED_PATH}/luci"
    _ssr_info "Base     : ${SSR_BASE}${FEED_PATH}/base"

    printf "\n"

}


# ============================================================
# 恢复软件源
# ============================================================

restore_feeds()
{

    if [ ! -d "$BACKUP_DIR" ]; then
        return 0
    fi


    _ssr_info "正在恢复原始软件源..."


    if [ -f "$BACKUP_DIR/distfeeds.conf" ]; then

        cp "$BACKUP_DIR/distfeeds.conf" \
        "$DISTFEEDS"

    fi


    if [ -f "$BACKUP_DIR/customfeeds.conf" ]; then

        cp "$BACKUP_DIR/customfeeds.conf" \
        "$CUSTOMFEEDS"

    elif [ -f "$BACKUP_DIR/customfeeds.notexist" ]; then

        rm -f "$CUSTOMFEEDS"

    fi


    rm -rf "$BACKUP_DIR"


    _ssr_ok "原始软件源已恢复"

}


# ============================================================
# 检查是否安装
# ============================================================

check_ssrplus()
{

    opkg status luci-app-ssr-plus 2>/dev/null |
        grep -q "Status: install"

}


# ============================================================
# 主安装函数
# ============================================================

install_ssrplus()
{

    printf "\n"
    printf "======================================\n"
    printf "        SSR Plus+ Installer\n"
    printf "======================================\n"
    printf "\n"


    # --------------------------------------------------------
    # ROOT
    # --------------------------------------------------------

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _ssr_error "请使用 root 用户运行"

        return 1

    fi


    # --------------------------------------------------------
    # 包管理器
    # --------------------------------------------------------

    if command -v opkg >/dev/null 2>&1; then

        PKG_MANAGER="opkg"

    elif command -v apk >/dev/null 2>&1; then

        _ssr_error "检测到 APK 包管理器"

        _ssr_warn "当前提供的软件源为 opkg 软件源。"
        _ssr_warn "为避免破坏系统，本次不自动添加。"

        return 1

    else

        _ssr_error "未检测到 opkg 包管理器"

        return 1

    fi


    _ssr_info "Package Manager : $PKG_MANAGER"

    printf "\n"


    # --------------------------------------------------------
    # 已经安装
    # --------------------------------------------------------

    if check_ssrplus; then

        _ssr_ok "SSR Plus+ 已经安装"

        return 0

    fi


    # --------------------------------------------------------
    # 检测
    # --------------------------------------------------------

    detect_system


    # --------------------------------------------------------
    # 匹配
    # --------------------------------------------------------

    if ! match_feed; then

        return 2

    fi


    # --------------------------------------------------------
    # 备份
    # --------------------------------------------------------

    if ! backup_feeds; then

        _ssr_error "软件源备份失败"

        return 1

    fi


    # --------------------------------------------------------
    # 从这里开始必须保证恢复
    # --------------------------------------------------------

    trap 'restore_feeds' EXIT INT TERM


    # --------------------------------------------------------
    # 临时源
    # --------------------------------------------------------

    add_temp_feeds


    # --------------------------------------------------------
    # 更新
    # --------------------------------------------------------

    _ssr_info "正在更新软件列表..."

    printf "\n"


    if ! opkg update; then

        printf "\n"

        _ssr_error "软件源更新失败"

        restore_feeds

        trap - EXIT INT TERM

        return 1

    fi


    printf "\n"

    _ssr_ok "软件列表更新完成"


    # --------------------------------------------------------
    # 查询 SSR Plus+
    # --------------------------------------------------------

    _ssr_info "正在查询 luci-app-ssr-plus..."


    if ! opkg list 2>/dev/null |
        grep -q '^luci-app-ssr-plus '; then

        _ssr_error "临时软件源中没有找到 luci-app-ssr-plus"

        restore_feeds

        trap - EXIT INT TERM

        return 2

    fi


    _ssr_ok "已找到 luci-app-ssr-plus"

    printf "\n"


    # --------------------------------------------------------
    # 安装
    # --------------------------------------------------------

    _ssr_info "开始安装 SSR Plus+..."

    printf "\n"


    if ! opkg install luci-app-ssr-plus; then

        printf "\n"

        _ssr_error "SSR Plus+ 安装失败"

        restore_feeds

        trap - EXIT INT TERM

        return 1

    fi


    # --------------------------------------------------------
    # 验证
    # --------------------------------------------------------

    printf "\n"

    _ssr_info "正在检查安装结果..."


    if ! check_ssrplus; then

        _ssr_error "未检测到 luci-app-ssr-plus"
        _ssr_error "安装可能失败"

        restore_feeds

        trap - EXIT INT TERM

        return 1

    fi


    _ssr_ok "SSR Plus+ 安装成功"


    # --------------------------------------------------------
    # 启用服务
    # --------------------------------------------------------

    if [ -x /etc/init.d/shadowsocksr ]; then

        _ssr_info "正在启用 SSR Plus+ 服务..."

        /etc/init.d/shadowsocksr enable >/dev/null 2>&1

    fi


    # --------------------------------------------------------
    # 恢复软件源
    # --------------------------------------------------------

    printf "\n"

    restore_feeds

    trap - EXIT INT TERM


    # --------------------------------------------------------
    # 完成
    # --------------------------------------------------------

    printf "\n"
    printf "======================================\n"
    printf "        SSR Plus+ Installed\n"
    printf "======================================\n"
    printf "\n"

    _ssr_ok "SSR Plus+ 安装完成"
    _ssr_ok "临时软件源已经删除"
    _ssr_ok "路由器原始软件源已经恢复"

    printf "\n"

    printf "请进入 LuCI 后台查看：\n"
    printf "服务 → ShadowSocksR Plus+\n"

    printf "\n"

    return 0
}

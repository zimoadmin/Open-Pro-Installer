#!/bin/sh

# ============================================================
# Open-Pro-Installer
# SSR Plus+ Auto Installer
#
# 支持：
#
# MT798X
#   OpenWrt 21 / Kernel 5.4 / 64bit
#   OpenWrt 24 / Kernel 6.6 / 64bit
#
# IPQ6000
#   OpenWrt 23 / 64bit
#   旧 32bit
#
# IPQ53XX
#   BE3600 / BE6500 / BE9300
#   IPQ5312 / IPQ5332
#   OpenWrt 23 / 64bit
#
# IPQ5018
#   B3000 / OpenWrt 19 / 64bit
#
# IPQ401X
#   OpenWrt 21 / 32bit
#
# SDX72
#   Mudi7 / E5800 / OpenWrt 23 / 64bit
#
# 安装流程：
# 1. 检测设备
# 2. 识别处理器平台
# 3. 检测 OpenWrt
# 4. 检测 Kernel
# 5. 检测 32/64 位
# 6. 自动匹配软件源
# 7. 备份原始软件源
# 8. 临时添加软件源
# 9. 更新软件列表
# 10. 安装 SSR Plus+
# 11. 验证安装结果
# 12. 删除临时源
# 13. 恢复原始软件源
# ============================================================


# ============================================================
# 基础配置
# ============================================================

SSR_BASE="http://glinet.83970255.xyz/?f="

BACKUP_DIR="/tmp/openpro_ssrplus_backup"

CUSTOMFEEDS="/etc/opkg/customfeeds.conf"
DISTFEEDS="/etc/opkg/distfeeds.conf"

FEED_PATH=""
FEED_NAME=""

MODEL="unknown"
OPENWRT_VERSION="unknown"
OPENWRT_TARGET="unknown"
KERNEL_VERSION="unknown"
ARCH="unknown"
BITS="unknown"
PLATFORM="unknown"

TARGET_LOWER=""
TARGET_FAMILY=""
MODEL_LOWER=""

PKG_MANAGER=""


# ============================================================
# 日志
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
# 检测系统
# ============================================================

detect_system()
{
    _ssr_info "正在检测设备信息..."

    MODEL="unknown"
    OPENWRT_VERSION="unknown"
    OPENWRT_TARGET="unknown"
    KERNEL_VERSION="unknown"
    ARCH="unknown"
    BITS="unknown"
    PLATFORM="unknown"

    TARGET_LOWER=""
    TARGET_FAMILY=""
    MODEL_LOWER=""


    # ========================================================
    # Kernel / Architecture
    # ========================================================

    KERNEL_VERSION="$(uname -r 2>/dev/null)"
    ARCH="$(uname -m 2>/dev/null)"

    [ -n "$KERNEL_VERSION" ] || KERNEL_VERSION="unknown"
    [ -n "$ARCH" ] || ARCH="unknown"


    # ========================================================
    # 获取设备型号
    # ========================================================

    if [ -s /tmp/sysinfo/model ]; then

        MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"

    elif [ -f /proc/device-tree/model ]; then

        MODEL="$(
            tr -d '\000' \
            < /proc/device-tree/model \
            2>/dev/null
        )"

    fi

    [ -n "$MODEL" ] || MODEL="unknown"


    # ========================================================
    # 获取 OpenWrt 信息
    # ========================================================

    if [ -f /etc/openwrt_release ]; then

        . /etc/openwrt_release

        OPENWRT_VERSION="${DISTRIB_RELEASE:-unknown}"
        OPENWRT_TARGET="${DISTRIB_TARGET:-unknown}"

    fi


    # ========================================================
    # UBUS 兜底
    # ========================================================

    if command -v ubus >/dev/null 2>&1 &&
       command -v jsonfilter >/dev/null 2>&1; then

        BOARD_JSON="$(ubus call system board 2>/dev/null)"


        if [ "$OPENWRT_TARGET" = "unknown" ] ||
           [ -z "$OPENWRT_TARGET" ]; then

            TMP_TARGET="$(
                printf '%s' "$BOARD_JSON" |
                jsonfilter -e '@.release.target' 2>/dev/null
            )"

            if [ -n "$TMP_TARGET" ]; then
                OPENWRT_TARGET="$TMP_TARGET"
            fi

        fi


        if [ "$OPENWRT_VERSION" = "unknown" ] ||
           [ -z "$OPENWRT_VERSION" ]; then

            TMP_VERSION="$(
                printf '%s' "$BOARD_JSON" |
                jsonfilter -e '@.release.version' 2>/dev/null
            )"

            if [ -n "$TMP_VERSION" ]; then
                OPENWRT_VERSION="$TMP_VERSION"
            fi

        fi

    fi


    # ========================================================
    # 清理 CR / LF
    # ========================================================

    OPENWRT_TARGET="$(
        printf '%s' "$OPENWRT_TARGET" |
        tr -d '\r\n\t '
    )"

    OPENWRT_VERSION="$(
        printf '%s' "$OPENWRT_VERSION" |
        tr -d '\r\n\t '
    )"

    MODEL="$(
        printf '%s' "$MODEL" |
        tr -d '\r\n'
    )"


    # ========================================================
    # 检测 32 / 64 位
    # ========================================================

    case "$ARCH" in

        x86_64|aarch64|arm64|mips64|mips64el|mips64*)
            BITS="64"
            ;;

        armv5*|armv6*|armv7*|armhf|mips|mipsel|mips32*)
            BITS="32"
            ;;

        *)

            LONG_BIT="$(getconf LONG_BIT 2>/dev/null)"

            case "$LONG_BIT" in

                64)
                    BITS="64"
                    ;;

                32)
                    BITS="32"
                    ;;

                *)
                    BITS="unknown"
                    ;;

            esac

            ;;

    esac


    # ========================================================
    # 转小写
    # ========================================================

    TARGET_LOWER="$(
        printf '%s' "$OPENWRT_TARGET" |
        tr '[:upper:]' '[:lower:]' |
        tr -d '\r\n\t '
    )"

    MODEL_LOWER="$(
        printf '%s' "$MODEL" |
        tr '[:upper:]' '[:lower:]' |
        tr -d '\r\n'
    )"


    # ========================================================
    # 提取 Target Family
    #
    # ipq53xx/generic -> ipq53xx
    # mediatek/mt7987 -> mediatek
    # ========================================================

    TARGET_FAMILY="$(
        printf '%s' "$TARGET_LOWER" |
        cut -d '/' -f 1
    )"


    # ========================================================
    # 第一层识别
    # Target Family
    # ========================================================

    case "$TARGET_FAMILY" in

        ipq53xx|ipq5332|ipq5312)
            PLATFORM="IPQ53XX"
            ;;

        ipq6000)
            PLATFORM="IPQ6000"
            ;;

        ipq5018)
            PLATFORM="IPQ5018"
            ;;

        ipq4019|ipq401x)
            PLATFORM="IPQ401X"
            ;;

        sdx72)
            PLATFORM="SDX72"
            ;;

    esac


    # ========================================================
    # 第二层识别
    # 完整 OpenWrt Target
    # ========================================================

    if [ "$PLATFORM" = "unknown" ]; then

        case "$TARGET_LOWER" in

            *ipq53xx*|*ipq5332*|*ipq5312*)
                PLATFORM="IPQ53XX"
                ;;

            *ipq6000*)
                PLATFORM="IPQ6000"
                ;;

            *ipq5018*)
                PLATFORM="IPQ5018"
                ;;

            *ipq4019*|*ipq401x*)
                PLATFORM="IPQ401X"
                ;;

            *mt7981*|*mt7986*|*mt7987*|*mt7988*|*mt798x*)
                PLATFORM="MT798X"
                ;;

            *sdx72*)
                PLATFORM="SDX72"
                ;;

        esac

    fi


    # ========================================================
    # 第三层识别
    # Model / SoC
    # ========================================================

    if [ "$PLATFORM" = "unknown" ]; then

        case "$MODEL_LOWER" in

            *ipq53xx*|*ipq5312*|*ipq5332*)
                PLATFORM="IPQ53XX"
                ;;

            *ipq6000*)
                PLATFORM="IPQ6000"
                ;;

            *ipq5018*)
                PLATFORM="IPQ5018"
                ;;

            *ipq4019*|*ipq401x*)
                PLATFORM="IPQ401X"
                ;;

            *mt7981*|*mt7986*|*mt7987*|*mt7988*|*mt798x*)
                PLATFORM="MT798X"
                ;;

            *sdx72*)
                PLATFORM="SDX72"
                ;;

        esac

    fi


    # ========================================================
    # 第四层识别
    # GL.iNet 型号
    # ========================================================

    if [ "$PLATFORM" = "unknown" ]; then

        case "$MODEL_LOWER" in

            *be3600*|*be6500*|*be9300*)
                PLATFORM="IPQ53XX"
                ;;

            *ax1800*|*axt1800*)
                PLATFORM="IPQ6000"
                ;;

            *b3000*)
                PLATFORM="IPQ5018"
                ;;

            *b1300*)
                PLATFORM="IPQ401X"
                ;;

            *mt2500*|*mt3000*|*mt5000*|*mt6000*|*mt3600*)
                PLATFORM="MT798X"
                ;;

            *e5800*|*mudi7*)
                PLATFORM="SDX72"
                ;;

        esac

    fi


    # ========================================================
    # 第五层：
    # IPQ53XX 强制兜底
    #
    # 解决：
    # Qualcomm Technologies, Inc. IPQ5332/AP-MI01.2
    # Target: ipq53xx/generic
    # ========================================================

    if [ "$PLATFORM" = "unknown" ]; then

        if printf '%s\n%s\n' \
            "$OPENWRT_TARGET" \
            "$MODEL" |
            grep -Eqi 'ipq53xx|ipq5332|ipq5312|be3600|be6500|be9300'
        then

            PLATFORM="IPQ53XX"

        fi

    fi


    # ========================================================
    # 第六层：
    # MT798X 强制兜底
    # ========================================================

    if [ "$PLATFORM" = "unknown" ]; then

        if printf '%s\n%s\n' \
            "$OPENWRT_TARGET" \
            "$MODEL" |
            grep -Eqi 'mt7981|mt7986|mt7987|mt7988|mt2500|mt3000|mt5000|mt6000|mt3600'
        then

            PLATFORM="MT798X"

        fi

    fi


    # ========================================================
    # 显示结果
    # ========================================================

    printf "\n"
    printf "======================================\n"
    printf "          设备检测结果\n"
    printf "======================================\n"
    printf "机型     : %s\n" "$MODEL"
    printf "平台     : %s\n" "$PLATFORM"
    printf "OpenWrt  : %s\n" "$OPENWRT_VERSION"
    printf "Target   : %s\n" "$OPENWRT_TARGET"
    printf "Family   : %s\n" "$TARGET_FAMILY"
    printf "Kernel   : %s\n" "$KERNEL_VERSION"
    printf "架构     : %s\n" "$ARCH"
    printf "系统     : %s 位\n" "$BITS"
    printf "======================================\n"
    printf "\n"


    # ========================================================
    # 验证
    # ========================================================

    if [ "$PLATFORM" = "unknown" ]; then

        _ssr_error "无法识别当前设备平台"

        printf "\n"
        _ssr_error "Target : $OPENWRT_TARGET"
        _ssr_error "Family : $TARGET_FAMILY"
        _ssr_error "Model  : $MODEL"

        return 1

    fi


    if [ "$BITS" = "unknown" ]; then

        _ssr_error "无法识别当前系统位数"

        return 1

    fi


    return 0
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

        if [ "$BITS" = "64" ]; then

            case "$OPENWRT_VERSION" in

                21.*)

                    case "$KERNEL_VERSION" in

                        5.4.*)

                            FEED_PATH="/mt798x-openwrt21"
                            FEED_NAME="MT798X / OpenWrt 21 / Kernel 5.4 / 64位"

                            ;;

                    esac

                    ;;


                24.*)

                    case "$KERNEL_VERSION" in

                        6.6.*)

                            FEED_PATH="/mt798x-openwrt24"
                            FEED_NAME="MT798X / OpenWrt 24 / Kernel 6.6 / 64位"

                            ;;

                    esac

                    ;;

            esac

        fi

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

            _ssr_warn "当前 IPQ6000 使用32位旧系统"
            _ssr_warn "该软件源已经停止更新"

        fi

    fi


    # ========================================================
    # IPQ53XX
    # ========================================================

    if [ "$PLATFORM" = "IPQ53XX" ]; then

        if [ "$BITS" = "64" ]; then

            case "$OPENWRT_VERSION" in

                23.*)

                    FEED_PATH="/ipq5312-qsdk12-5-64bit"
                    FEED_NAME="IPQ53XX / QSDK 12.5 / OpenWrt 23 / 64位"

                    ;;

            esac

        fi

    fi


    # ========================================================
    # IPQ5018 / B3000
    # ========================================================

    if [ "$PLATFORM" = "IPQ5018" ]; then

        if [ "$BITS" = "64" ]; then

            case "$OPENWRT_VERSION" in

                19.*)

                    FEED_PATH="/b3000-qsdk12-2"
                    FEED_NAME="IPQ5018 / B3000 / OpenWrt 19 / 64位"

                    ;;

            esac

        fi

    fi


    # ========================================================
    # IPQ401X
    # ========================================================

    if [ "$PLATFORM" = "IPQ401X" ]; then

        if [ "$BITS" = "32" ]; then

            case "$OPENWRT_VERSION" in

                21.*)

                    FEED_PATH="/ipq4019"
                    FEED_NAME="IPQ401X / OpenWrt 21 / 32位"

                    ;;

            esac

        fi

    fi


    # ========================================================
    # SDX72 / Mudi7 / E5800
    # ========================================================

    if [ "$PLATFORM" = "SDX72" ]; then

        if [ "$BITS" = "64" ]; then

            case "$OPENWRT_VERSION" in

                23.*)

                    FEED_PATH="/mudi7"
                    FEED_NAME="Mudi7 / SDX72 / OpenWrt 23 / 64位"

                    ;;

            esac

        fi

    fi


    # ========================================================
    # 未匹配
    # ========================================================

    if [ -z "$FEED_PATH" ]; then

        _ssr_error "没有找到适用于当前设备的软件源"

        printf "\n"
        printf "系统信息：\n"
        printf "--------------------------------------\n"
        printf "机型    : %s\n" "$MODEL"
        printf "平台    : %s\n" "$PLATFORM"
        printf "OpenWrt : %s\n" "$OPENWRT_VERSION"
        printf "Target  : %s\n" "$OPENWRT_TARGET"
        printf "Family  : %s\n" "$TARGET_FAMILY"
        printf "Kernel  : %s\n" "$KERNEL_VERSION"
        printf "架构    : %s\n" "$ARCH"
        printf "位数    : %s\n" "$BITS"
        printf "--------------------------------------\n"
        printf "\n"

        _ssr_warn "为避免安装错误架构的软件包，已取消安装。"

        return 1

    fi


    # ========================================================
    # 匹配成功
    # ========================================================

    _ssr_ok "已自动匹配软件源"
    _ssr_info "$FEED_NAME"

    printf "\n"

    _ssr_info "Packages : ${SSR_BASE}${FEED_PATH}/packages"
    _ssr_info "LuCI     : ${SSR_BASE}${FEED_PATH}/luci"
    _ssr_info "Base     : ${SSR_BASE}${FEED_PATH}/base"

    printf "\n"

    return 0
}


# ============================================================
# 备份原始软件源
# ============================================================

backup_feeds()
{
    _ssr_info "正在备份原始软件源..."

    rm -rf "$BACKUP_DIR"

    mkdir -p "$BACKUP_DIR" || {

        _ssr_error "无法创建备份目录"

        return 1

    }


    # ========================================================
    # distfeeds.conf
    # ========================================================

    if [ -f "$DISTFEEDS" ]; then

        cp "$DISTFEEDS" \
            "$BACKUP_DIR/distfeeds.conf" || {

            _ssr_error "备份 distfeeds.conf 失败"

            return 1

        }

    else

        touch "$BACKUP_DIR/distfeeds.notexist"

    fi


    # ========================================================
    # customfeeds.conf
    # ========================================================

    if [ -f "$CUSTOMFEEDS" ]; then

        cp "$CUSTOMFEEDS" \
            "$BACKUP_DIR/customfeeds.conf" || {

            _ssr_error "备份 customfeeds.conf 失败"

            return 1

        }

    else

        touch "$BACKUP_DIR/customfeeds.notexist"

    fi


    _ssr_ok "原始软件源备份完成"

    return 0
}


# ============================================================
# 添加临时软件源
# ============================================================

add_temp_feeds()
{
    _ssr_info "正在添加 SSR Plus+ 临时软件源..."


    mkdir -p /etc/opkg || {

        _ssr_error "无法创建 /etc/opkg"

        return 1

    }


    if [ ! -f "$CUSTOMFEEDS" ]; then

        touch "$CUSTOMFEEDS" || {

            _ssr_error "无法创建 customfeeds.conf"

            return 1

        }

    fi


    # ========================================================
    # 删除以前可能残留的 Open-Pro 源
    # ========================================================

    sed -i \
        '/^src\/gz openpro_/d' \
        "$CUSTOMFEEDS"


    # ========================================================
    # 添加三个临时源
    # ========================================================

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

    return 0
}


# ============================================================
# 恢复原始软件源
# ============================================================

restore_feeds()
{
    if [ ! -d "$BACKUP_DIR" ]; then
        return 0
    fi


    _ssr_info "正在恢复原始软件源..."


    # ========================================================
    # 恢复 distfeeds.conf
    # ========================================================

    if [ -f "$BACKUP_DIR/distfeeds.conf" ]; then

        cp "$BACKUP_DIR/distfeeds.conf" \
            "$DISTFEEDS"

    elif [ -f "$BACKUP_DIR/distfeeds.notexist" ]; then

        rm -f "$DISTFEEDS"

    fi


    # ========================================================
    # 恢复 customfeeds.conf
    # ========================================================

    if [ -f "$BACKUP_DIR/customfeeds.conf" ]; then

        cp "$BACKUP_DIR/customfeeds.conf" \
            "$CUSTOMFEEDS"

    elif [ -f "$BACKUP_DIR/customfeeds.notexist" ]; then

        rm -f "$CUSTOMFEEDS"

    fi


    rm -rf "$BACKUP_DIR"


    _ssr_ok "原始软件源已恢复"

    return 0
}


# ============================================================
# 清理临时软件列表
# ============================================================

clean_openpro_lists()
{
    rm -f /var/opkg-lists/openpro_packages 2>/dev/null
    rm -f /var/opkg-lists/openpro_luci 2>/dev/null
    rm -f /var/opkg-lists/openpro_base 2>/dev/null

    return 0
}


# ============================================================
# 检查 SSR Plus+ 是否已经安装
# ============================================================

check_ssrplus()
{
    opkg status luci-app-ssr-plus 2>/dev/null |
        grep -q 'Status:.*installed'
}


# ============================================================
# 安全清理
# ============================================================

cleanup_ssrplus()
{
    restore_feeds
    clean_openpro_lists
}


# ============================================================
# 中断处理
# ============================================================

interrupt_ssrplus()
{
    printf "\n"

    _ssr_warn "安装被中断"

    cleanup_ssrplus

    trap - EXIT INT TERM

    exit 130
}


# ============================================================
# 主安装函数
#
# install.sh 调用的就是这个函数
# 千万不要删除
# ============================================================

install_ssrplus()
{
    printf "\n"
    printf "======================================\n"
    printf "        SSR Plus+ Installer\n"
    printf "======================================\n"
    printf "\n"


    # ========================================================
    # ROOT
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _ssr_error "请使用 root 用户运行"

        return 1

    fi


    # ========================================================
    # 包管理器
    # ========================================================

    if command -v opkg >/dev/null 2>&1; then

        PKG_MANAGER="opkg"

    elif command -v apk >/dev/null 2>&1; then

        _ssr_error "检测到 APK 包管理器"
        _ssr_warn "当前 SSR Plus+ 软件源为 OPKG 软件源"
        _ssr_warn "为避免软件包格式不兼容，已取消安装"

        return 1

    else

        _ssr_error "未检测到 OPKG 包管理器"

        return 1

    fi


    _ssr_info "Package Manager : $PKG_MANAGER"

    printf "\n"


    # ========================================================
    # 检查是否已经安装
    # ========================================================

    if check_ssrplus; then

        _ssr_ok "SSR Plus+ 已经安装"

        return 0

    fi


    # ========================================================
    # 检测系统
    # ========================================================

    if ! detect_system; then

        return 2

    fi


    # ========================================================
    # 匹配软件源
    # ========================================================

    if ! match_feed; then

        return 2

    fi


    # ========================================================
    # 备份原始软件源
    # ========================================================

    if ! backup_feeds; then

        _ssr_error "软件源备份失败"

        return 1

    fi


    # ========================================================
    # 设置安全恢复
    # ========================================================

    trap 'cleanup_ssrplus' EXIT
    trap 'interrupt_ssrplus' INT TERM


    # ========================================================
    # 添加临时软件源
    # ========================================================

    if ! add_temp_feeds; then

        _ssr_error "添加临时软件源失败"

        cleanup_ssrplus

        trap - EXIT INT TERM

        return 1

    fi


    # ========================================================
    # 清理旧缓存
    # ========================================================

    clean_openpro_lists


    # ========================================================
    # 更新软件列表
    # ========================================================

    printf "\n"

    _ssr_info "正在更新软件列表..."

    printf "\n"


    if ! opkg update; then

        printf "\n"

        _ssr_error "软件源更新失败"

        cleanup_ssrplus

        trap - EXIT INT TERM

        return 1

    fi


    printf "\n"

    _ssr_ok "软件列表更新完成"

    printf "\n"


    # ========================================================
    # 查询 SSR Plus+
    # ========================================================

    _ssr_info "正在查询 luci-app-ssr-plus..."


    SSR_PACKAGE="$(
        opkg list 2>/dev/null |
        awk '$1=="luci-app-ssr-plus"{print $1; exit}'
    )"


    if [ "$SSR_PACKAGE" != "luci-app-ssr-plus" ]; then

        printf "\n"

        _ssr_error "软件源中没有找到 luci-app-ssr-plus"

        printf "\n"

        _ssr_warn "请检查该软件源是否包含 SSR Plus+"

        cleanup_ssrplus

        trap - EXIT INT TERM

        return 2

    fi


    _ssr_ok "已找到 luci-app-ssr-plus"


    # ========================================================
    # 获取版本
    # ========================================================

    SSR_VERSION="$(
        opkg list luci-app-ssr-plus 2>/dev/null |
        awk -F ' - ' 'NR==1 {print $2}'
    )"


    if [ -n "$SSR_VERSION" ]; then

        _ssr_info "SSR Plus+ Version : $SSR_VERSION"

    fi


    # ========================================================
    # 安装
    # ========================================================

    printf "\n"

    _ssr_info "开始安装 SSR Plus+..."

    printf "\n"


    if ! opkg install luci-app-ssr-plus; then

        printf "\n"

        _ssr_error "SSR Plus+ 安装失败"

        cleanup_ssrplus

        trap - EXIT INT TERM

        return 1

    fi


    # ========================================================
    # 验证安装
    # ========================================================

    printf "\n"

    _ssr_info "正在检查安装结果..."


    if ! check_ssrplus; then

        _ssr_error "未检测到 luci-app-ssr-plus"
        _ssr_error "SSR Plus+ 安装可能失败"

        cleanup_ssrplus

        trap - EXIT INT TERM

        return 1

    fi


    _ssr_ok "SSR Plus+ 安装成功"


    # ========================================================
    # 启用 SSR Plus+
    # ========================================================

    if [ -x /etc/init.d/shadowsocksr ]; then

        _ssr_info "正在启用 SSR Plus+ 服务..."

        /etc/init.d/shadowsocksr enable >/dev/null 2>&1

    fi


    # ========================================================
    # 恢复原始软件源
    # ========================================================

    printf "\n"

    cleanup_ssrplus

    trap - EXIT INT TERM


    # ========================================================
    # 完成
    # ========================================================

    printf "\n"
    printf "======================================\n"
    printf "        SSR Plus+ Installed\n"
    printf "======================================\n"
    printf "\n"

    _ssr_ok "SSR Plus+ 安装完成"
    _ssr_ok "临时软件源已经删除"
    _ssr_ok "临时软件列表已经清理"
    _ssr_ok "路由器原始软件源已经恢复"

    printf "\n"

    printf "请进入 LuCI 后台查看：\n"
    printf "服务 → ShadowSocksR Plus+\n"

    printf "\n"

    return 0
}

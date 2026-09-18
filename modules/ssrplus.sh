#!/bin/sh

# ============================================================
# Open-Pro-Installer
# SSR Plus+ Auto Installer
# Five Stage Progress Edition
#
# 功能：
# 1. 自动识别设备平台
# 2. 自动匹配软件源
# 3. 自动备份原始软件源
# 4. 临时添加 SSR Plus+ 软件源
# 5. 静默更新软件列表
# 6. 五阶段动态进度安装 SSR Plus+
# 7. 自动检测中文语言包
# 8. 自动扫描所有 shadowsocksr-libev-ssr-*
# 9. 自动安装缺失组件
# 10. 自动恢复原始软件源
# ============================================================


# ============================================================
# 基础配置
# ============================================================

SSR_BASE="http://glinet.83970255.xyz/?f="

BACKUP_DIR="/tmp/openpro_ssrplus_backup"

CUSTOMFEEDS="/etc/opkg/customfeeds.conf"
DISTFEEDS="/etc/opkg/distfeeds.conf"

UPDATE_LOG="/tmp/openpro_ssrplus_update.log"
INSTALL_LOG="/tmp/openpro_ssrplus_install.log"

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

PROGRESS_PID=""


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
# 生成进度条
# ============================================================

make_bar()
{
    PERCENT="$1"
    WIDTH="${2:-25}"

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

    printf '%s' "$BAR"
}


# ============================================================
# 绘制五阶段进度
# ============================================================

draw_install_progress()
{
    P1="$1"
    P2="$2"
    P3="$3"
    P4="$4"
    P5="$5"
    TOTAL="$6"

    B1="$(make_bar "$P1" 20)"
    B2="$(make_bar "$P2" 20)"
    B3="$(make_bar "$P3" 20)"
    B4="$(make_bar "$P4" 20)"
    B5="$(make_bar "$P5" 20)"
    BT="$(make_bar "$TOTAL" 30)"

    printf '\033[6A'

    printf '\033[2K\r[1/5] 准备安装环境  [\033[32m%s\033[0m] %3d%%\n' \
        "$B1" "$P1"

    printf '\033[2K\r[2/5] 下载软件包    [\033[32m%s\033[0m] %3d%%\n' \
        "$B2" "$P2"

    printf '\033[2K\r[3/5] 安装软件包    [\033[32m%s\033[0m] %3d%%\n' \
        "$B3" "$P3"

    printf '\033[2K\r[4/5] 配置软件包    [\033[32m%s\033[0m] %3d%%\n' \
        "$B4" "$P4"

    printf '\033[2K\r[5/5] 完成安装      [\033[32m%s\033[0m] %3d%%\n' \
        "$B5" "$P5"

    printf '\033[2K\r总体进度           [\033[32m%s\033[0m] %3d%%\n' \
        "$BT" "$TOTAL"
}


# ============================================================
# 初始化进度区域
# ============================================================

init_install_progress()
{
    printf "[1/5] 准备安装环境  [--------------------]   0%%\n"
    printf "[2/5] 下载软件包    [--------------------]   0%%\n"
    printf "[3/5] 安装软件包    [--------------------]   0%%\n"
    printf "[4/5] 配置软件包    [--------------------]   0%%\n"
    printf "[5/5] 完成安装      [--------------------]   0%%\n"
    printf "总体进度           [------------------------------]   0%%\n"
}


# ============================================================
# 五阶段安装
# ============================================================

install_with_progress()
{
    PACKAGE="$1"
    LOG_FILE="$2"

    rm -f "$LOG_FILE"

    P1=100
    P2=0
    P3=0
    P4=0
    P5=0

    TOTAL=20

    if [ "${SSR_PROGRESS_READY:-0}" != "1" ]; then
        init_install_progress
    fi
    SSR_PROGRESS_READY=0

    draw_install_progress \
        "$P1" "$P2" "$P3" "$P4" "$P5" "$TOTAL"

    opkg install "$PACKAGE" >"$LOG_FILE" 2>&1 &

    PROGRESS_PID=$!


    while kill -0 "$PROGRESS_PID" 2>/dev/null; do

        HAS_DOWNLOAD=0
        HAS_INSTALL=0
        HAS_CONFIG=0


        if grep -q '^Downloading ' "$LOG_FILE" 2>/dev/null; then
            HAS_DOWNLOAD=1
        fi


        if grep -q '^Installing ' "$LOG_FILE" 2>/dev/null; then
            HAS_INSTALL=1
        fi


        if grep -q '^Configuring ' "$LOG_FILE" 2>/dev/null; then
            HAS_CONFIG=1
        fi


        # ----------------------------------------------------
        # 下载阶段
        # ----------------------------------------------------

        if [ "$HAS_DOWNLOAD" -eq 1 ]; then

            if [ "$P2" -lt 90 ]; then
                P2=$((P2 + 5))
            fi

        else

            if [ "$P2" -lt 15 ]; then
                P2=$((P2 + 3))
            fi

        fi


        # ----------------------------------------------------
        # 安装阶段
        # ----------------------------------------------------

        if [ "$HAS_INSTALL" -eq 1 ]; then

            P2=100

            if [ "$P3" -lt 90 ]; then
                P3=$((P3 + 5))
            fi

        fi


        # ----------------------------------------------------
        # 配置阶段
        # ----------------------------------------------------

        if [ "$HAS_CONFIG" -eq 1 ]; then

            P2=100
            P3=100

            if [ "$P4" -lt 90 ]; then
                P4=$((P4 + 5))
            fi

        fi


        [ "$P2" -gt 100 ] && P2=100
        [ "$P3" -gt 100 ] && P3=100
        [ "$P4" -gt 100 ] && P4=100


        TOTAL=$(
            expr \
            "$P1" + \
            "$P2" + \
            "$P3" + \
            "$P4" + \
            "$P5"
        )

        TOTAL=$((TOTAL / 5))


        if [ "$TOTAL" -gt 95 ]; then
            TOTAL=95
        fi


        draw_install_progress \
            "$P1" \
            "$P2" \
            "$P3" \
            "$P4" \
            "$P5" \
            "$TOTAL"


        sleep 1

    done


    wait "$PROGRESS_PID"

    RESULT=$?

    PROGRESS_PID=""


    if [ "$RESULT" -eq 0 ]; then

        P1=100
        P2=100
        P3=100
        P4=100
        P5=100
        TOTAL=100


        draw_install_progress \
            "$P1" \
            "$P2" \
            "$P3" \
            "$P4" \
            "$P5" \
            "$TOTAL"


        return 0

    fi


    return "$RESULT"
}


# ============================================================
# 检测系统
# ============================================================

detect_system()
{
    # _ssr_info "正在检测设备信息..."

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
    # OpenWrt
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

            [ -n "$TMP_TARGET" ] &&
                OPENWRT_TARGET="$TMP_TARGET"

        fi


        if [ "$OPENWRT_VERSION" = "unknown" ] ||
           [ -z "$OPENWRT_VERSION" ]; then

            TMP_VERSION="$(
                printf '%s' "$BOARD_JSON" |
                jsonfilter -e '@.release.version' 2>/dev/null
            )"

            [ -n "$TMP_VERSION" ] &&
                OPENWRT_VERSION="$TMP_VERSION"

        fi

    fi


    # ========================================================
    # 清理字符
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
    # 32 / 64 位
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


    TARGET_FAMILY="$(
        printf '%s' "$TARGET_LOWER" |
        cut -d '/' -f 1
    )"


    # ========================================================
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
    # 完整 Target
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
    # Model
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
    # GL.iNet 型号兜底
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
    # IPQ53XX 强制兜底
    # ========================================================

    if [ "$PLATFORM" = "unknown" ]; then

        if printf '%s\n%s\n' \
            "$OPENWRT_TARGET" \
            "$MODEL" |
            grep -Eqi \
            'ipq53xx|ipq5332|ipq5312|be3600|be6500|be9300'
        then

            PLATFORM="IPQ53XX"

        fi

    fi


    # ========================================================
    # MT798X 强制兜底
    # ========================================================

    if [ "$PLATFORM" = "unknown" ]; then

        if printf '%s\n%s\n' \
            "$OPENWRT_TARGET" \
            "$MODEL" |
            grep -Eqi \
            'mt7981|mt7986|mt7987|mt7988|mt2500|mt3000|mt5000|mt6000|mt3600'
        then

            PLATFORM="MT798X"

        fi

    fi


    # ========================================================
    # 显示
    # ========================================================

    printf "\n"
    printf "======================================\n"
    printf "        SSR Plus+ Installer\n"
    printf "======================================\n"
    printf "包管理器 : %s\n" "$PKG_MANAGER"
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


    if [ "$PLATFORM" = "unknown" ]; then

        _ssr_error "无法识别当前设备平台"

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

    if [ "$PLATFORM" = "MT798X" ] &&
       [ "$BITS" = "64" ]; then

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

    if [ "$PLATFORM" = "IPQ53XX" ] &&
       [ "$BITS" = "64" ]; then

        case "$OPENWRT_VERSION" in

            23.*)

                FEED_PATH="/ipq5312-qsdk12-5-64bit"
                FEED_NAME="IPQ53XX / QSDK 12.5 / OpenWrt 23 / 64位"

                ;;

        esac

    fi


    # ========================================================
    # IPQ5018
    # ========================================================

    if [ "$PLATFORM" = "IPQ5018" ] &&
       [ "$BITS" = "64" ]; then

        case "$OPENWRT_VERSION" in

            19.*)

                FEED_PATH="/b3000-qsdk12-2"
                FEED_NAME="IPQ5018 / B3000 / OpenWrt 19 / 64位"

                ;;

        esac

    fi


    # ========================================================
    # IPQ401X
    # ========================================================

    if [ "$PLATFORM" = "IPQ401X" ] &&
       [ "$BITS" = "32" ]; then

        case "$OPENWRT_VERSION" in

            21.*)

                FEED_PATH="/ipq4019"
                FEED_NAME="IPQ401X / OpenWrt 21 / 32位"

                ;;

        esac

    fi


    # ========================================================
    # SDX72
    # ========================================================

    if [ "$PLATFORM" = "SDX72" ] &&
       [ "$BITS" = "64" ]; then

        case "$OPENWRT_VERSION" in

            23.*)

                FEED_PATH="/mudi7"
                FEED_NAME="Mudi7 / SDX72 / OpenWrt 23 / 64位"

                ;;

        esac

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


    # _ssr_ok "已自动匹配软件源"
    # _ssr_info "$FEED_NAME"

    # printf "\n"

    return 0
}


# ============================================================
# 备份原始软件源
# ============================================================

backup_feeds()
{
    # _ssr_info "正在备份原始软件源..."

    rm -rf "$BACKUP_DIR"


    mkdir -p "$BACKUP_DIR" || {

        _ssr_error "无法创建备份目录"

        return 1

    }


    if [ -f "$DISTFEEDS" ]; then

        cp "$DISTFEEDS" \
            "$BACKUP_DIR/distfeeds.conf" || return 1

    else

        touch "$BACKUP_DIR/distfeeds.notexist"

    fi


    if [ -f "$CUSTOMFEEDS" ]; then

        cp "$CUSTOMFEEDS" \
            "$BACKUP_DIR/customfeeds.conf" || return 1

    else

        touch "$BACKUP_DIR/customfeeds.notexist"

    fi


    # _ssr_ok "原始软件源备份完成"

    return 0
}


# ============================================================
# 添加临时软件源
# ============================================================

add_temp_feeds()
{
    # _ssr_info "正在添加 SSR Plus+ 临时软件源..."


    mkdir -p /etc/opkg || return 1


    [ -f "$CUSTOMFEEDS" ] ||
        touch "$CUSTOMFEEDS" ||
        return 1


    sed -i \
        '/^src\/gz openpro_/d' \
        "$CUSTOMFEEDS"


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


    # _ssr_ok "临时软件源添加完成"

    return 0
}


# ============================================================
# 恢复软件源
# ============================================================

restore_feeds()
{
    [ -d "$BACKUP_DIR" ] ||
        return 0


    _ssr_info "正在恢复原始软件源..."


    if [ -f "$BACKUP_DIR/distfeeds.conf" ]; then

        cp "$BACKUP_DIR/distfeeds.conf" \
            "$DISTFEEDS"

    elif [ -f "$BACKUP_DIR/distfeeds.notexist" ]; then

        rm -f "$DISTFEEDS"

    fi


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
# 清理
# ============================================================

clean_openpro_lists()
{
    rm -f /var/opkg-lists/openpro_packages 2>/dev/null
    rm -f /var/opkg-lists/openpro_luci 2>/dev/null
    rm -f /var/opkg-lists/openpro_base 2>/dev/null
}


clean_ssr_logs()
{
    # 保留最近一次更新日志；下次更新覆盖。
    rm -f "$INSTALL_LOG" 2>/dev/null
}


# ============================================================
# 检测指定软件包是否安装
# ============================================================

is_package_installed()
{
    opkg status "$1" 2>/dev/null |
        grep -q 'Status:.*installed'
}


# ============================================================
# SSR Plus+
# ============================================================

check_ssrplus()
{
    is_package_installed "luci-app-ssr-plus"
}


# ============================================================
# 安装一个可选组件
#
# 失败不影响 SSR Plus+ 主程序
# ============================================================

install_optional_package()
{
    OPTIONAL_PKG="$1"

    [ -n "$OPTIONAL_PKG" ] ||
        return 0


    # --------------------------------------------------------
    # 已安装
    # --------------------------------------------------------

    if is_package_installed "$OPTIONAL_PKG"; then

        _ssr_ok "$OPTIONAL_PKG 已安装"

        return 0

    fi


    # --------------------------------------------------------
    # 安装
    # --------------------------------------------------------

    _ssr_info "正在安装：$OPTIONAL_PKG"


    OPTIONAL_LOG="/tmp/openpro_ssrplus_extra.log"
    SSR_EXTRA_LOG="$OPTIONAL_LOG"

    rm -f "$OPTIONAL_LOG"


    if ssr_install_extra_visible "$OPTIONAL_PKG"
    then

        if is_package_installed "$OPTIONAL_PKG"; then

            _ssr_ok "$OPTIONAL_PKG 安装成功"

        else

            _ssr_warn "$OPTIONAL_PKG 安装完成，但状态无法确认"

        fi

    else

        _ssr_warn "$OPTIONAL_PKG 安装失败，已跳过"

    fi


    rm -f "$OPTIONAL_LOG"

    return 0
}


# ============================================================
# 自动检测并安装 SSR Plus+ 扩展组件
#
# 1. luci-i18n-ssr-plus-zh-cn
#
# 2. 自动扫描所有：
#
#    shadowsocksr-libev-ssr-*
#
# 软件源以后出现新的同前缀包，
# 也会自动识别并安装。
# ============================================================

install_optional_ssr_packages()
{
    : > /tmp/openpro_ssrplus_extra_failures.log
    printf "\n"

    _ssr_info "正在检测 SSR Plus+ 扩展组件..."

    printf "\n"


    # ========================================================
    # 中文语言包
    # ========================================================

    LANG_PKG="luci-i18n-ssr-plus-zh-cn"


    if is_package_installed "$LANG_PKG"; then

        _ssr_ok "中文语言包已安装"

    else

        LANG_FOUND="$(
            opkg list "$LANG_PKG" 2>/dev/null |
            awk -v pkg="$LANG_PKG" '
                $1 == pkg {
                    print $1
                    exit
                }
            '
        )"


        if [ "$LANG_FOUND" = "$LANG_PKG" ]; then

            _ssr_info "发现中文语言包"

            install_optional_package "$LANG_PKG"

        else

            _ssr_warn "未找到中文语言包，已跳过"

        fi

    fi


    printf "\n"


    # ========================================================
    # ShadowsocksR Libev
    # 自动扫描所有匹配包
    # ========================================================

    _ssr_info "正在扫描 ShadowsocksR Libev 组件..."


    SSR_LIBEV_PACKAGES="$(
        opkg list 2>/dev/null |
        awk '
            $1 ~ /^shadowsocksr-libev-ssr-/ {
                print $1
            }
        ' |
        sort -u
    )"


    # ========================================================
    # 没有发现
    # ========================================================

    if [ -z "$SSR_LIBEV_PACKAGES" ]; then

        _ssr_warn "未发现 shadowsocksr-libev-ssr-* 组件"

        printf "\n"

        return 0

    fi


    # ========================================================
    # 统计数量
    # ========================================================

    SSR_LIBEV_COUNT="$(
        printf '%s\n' "$SSR_LIBEV_PACKAGES" |
        awk '
            NF {
                count++
            }

            END {
                print count+0
            }
        '
    )"


    _ssr_ok "发现 $SSR_LIBEV_COUNT 个 ShadowsocksR Libev 组件"

    printf "\n"


    # ========================================================
    # 逐个安装
    # ========================================================

    for pkg in $SSR_LIBEV_PACKAGES
    do

        install_optional_package "$pkg"

    done


    printf "\n"

    _ssr_ok "SSR Plus+ 扩展组件检测完成"

    printf "\n"

    return 0
}


# ============================================================
# 安全清理
# ============================================================

cleanup_ssrplus()
{
    restore_feeds

    clean_openpro_lists
    clean_ssr_logs
}


# ============================================================
# 中断
# ============================================================

interrupt_ssrplus()
{
    printf "\n"

    _ssr_warn "安装被中断"


    if [ -n "$PROGRESS_PID" ]; then

        kill "$PROGRESS_PID" 2>/dev/null
        wait "$PROGRESS_PID" 2>/dev/null

    fi


    cleanup_ssrplus

    trap - EXIT INT TERM

    exit 130
}


# ============================================================
# 主安装函数
# ============================================================

ssr_disable_signature_check()
{
    SSR_SIG_BACKUP=""
    for SSR_SIG_FILE in /etc/opkg.conf /etc/opkg/*.conf; do
        [ -f "$SSR_SIG_FILE" ] || continue
        grep -Eq '^[[:space:]]*option[[:space:]]+check_signature([[:space:]]|$)' "$SSR_SIG_FILE" || continue
        if [ -z "$SSR_SIG_BACKUP" ]; then
            SSR_SIG_BACKUP="$(mktemp -d /root/opkg-signature-backup.XXXXXX)" || return 1
        fi
        # 保留目录层级，避免同名配置文件覆盖备份。
        mkdir -p "$SSR_SIG_BACKUP$(dirname "$SSR_SIG_FILE")" || return 1
        cp -p "$SSR_SIG_FILE" "$SSR_SIG_BACKUP$SSR_SIG_FILE" || return 1
    done
    for SSR_SIG_FILE in /etc/opkg.conf /etc/opkg/*.conf; do
        [ -f "$SSR_SIG_FILE" ] || continue
        sed -i '/^[[:space:]]*option[[:space:]][[:space:]]*check_signature\([[:space:]].*\)\{0,1\}$/d' "$SSR_SIG_FILE" || return 1
        if grep -Eq '^[[:space:]]*option[[:space:]]+check_signature([[:space:]]|$)' "$SSR_SIG_FILE"; then
            _ssr_error "签名校验配置未能移除：$SSR_SIG_FILE"
            return 1
        fi
    done
    _ssr_warn "OPKG 全局签名校验已永久关闭"
    [ -z "$SSR_SIG_BACKUP" ] || _ssr_info "原签名配置备份：$SSR_SIG_BACKUP"
    return 0
}

ssr_install_extra_visible()
{
    _ssr_info "正在安装扩展组件：$1"
    opkg install "$1" >"$SSR_EXTRA_LOG" 2>&1 &
    PROGRESS_PID=$!
    SSR_EXTRA_WAIT=0
    while kill -0 "$PROGRESS_PID" 2>/dev/null; do
        sleep 1
        SSR_EXTRA_WAIT=$((SSR_EXTRA_WAIT + 1))
        if [ $((SSR_EXTRA_WAIT % 10)) -eq 0 ]; then
            _ssr_info "$1 仍在运行，已等待 $SSR_EXTRA_WAIT 秒"
            tail -n 2 "$SSR_EXTRA_LOG"
        fi
    done
    wait "$PROGRESS_PID"
    SSR_EXTRA_RC=$?
    PROGRESS_PID=""
    if [ "$SSR_EXTRA_RC" -ne 0 ]; then
        { printf '\n=== %s，退出码 %s ===\n' "$1" "$SSR_EXTRA_RC"; cat "$SSR_EXTRA_LOG"; } >> /tmp/openpro_ssrplus_extra_failures.log
        tail -n 12 "$SSR_EXTRA_LOG"
    fi
    return "$SSR_EXTRA_RC"
}

ssr_diagnose_missing_package()
{
    SSR_DIAG_LOG="/tmp/openpro_ssrplus_diagnostic.log"
    {
        printf '\n=== 软件源更新日志 ===\n'
        if [ -s "$UPDATE_LOG" ]; then cat "$UPDATE_LOG"; else echo "没有更新日志"; fi
        printf '\n=== OPKG 接受的架构 ===\n'
        opkg print-architecture
        printf '\n=== 当前临时软件源配置 ===\n'
        grep '^src/gz openpro_' "$CUSTOMFEEDS"
        printf '\n=== OPKG 列表目录配置 ===\n'
        grep -hE '^[[:space:]]*lists_dir[[:space:]]' /etc/opkg.conf /etc/opkg/*.conf 2>/dev/null
        printf '\n=== 临时索引中的 PassWall 记录 ===\n'
        for SSR_DIAG_DIR in /var/opkg-lists /tmp/opkg-lists; do
            for SSR_DIAG_NAME in openpro_base openpro_luci openpro_packages; do
                SSR_DIAG_FILE="$SSR_DIAG_DIR/$SSR_DIAG_NAME"
                printf '\n%s\n' "$SSR_DIAG_FILE"
                if [ -s "$SSR_DIAG_FILE" ]; then
                    ls -l "$SSR_DIAG_FILE"
                    awk 'BEGIN { RS="" } /(^|\n)Package: luci-app-ssr-plus([[:space:]]|$)/ { print; found=1 }
                         END { if (!found) print "此索引未匹配到目标记录" }' "$SSR_DIAG_FILE"
                else
                    echo "索引不存在或为空"
                fi
            done
        done
        printf '\n=== OPKG 查询输出及退出码 ===\n'
        opkg list luci-app-ssr-plus
        SSR_DIAG_RC=$?
        printf 'opkg list 退出码：%s\n' "$SSR_DIAG_RC"
    } > "$SSR_DIAG_LOG" 2>&1
    cat "$SSR_DIAG_LOG"
    _ssr_info "诊断日志：$SSR_DIAG_LOG"
}

install_ssrplus()
{
    SSR_PROGRESS_READY=0


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

        return 1

    else

        _ssr_error "未检测到 OPKG 包管理器"

        return 1

    fi





    # ========================================================
    # 检测设备
    #
    # 注意：
    # 即使 SSR Plus+ 已经安装，
    # 也继续检测平台和软件源，
    # 这样以后再次运行时可以自动补齐扩展组件。
    # ========================================================

    ssr_disable_signature_check || { _ssr_error "关闭签名校验失败"; return 1; }

    if ! detect_system; then

        return 2

    fi


    # ========================================================
    # 匹配软件源
    # ========================================================

    if ! match_feed; then

        return 2

    fi


    # 在准备环境之前显示进度；已安装时沿用扩展组件流程。
    if ! check_ssrplus; then
        init_install_progress
        SSR_PROGRESS_READY=1
        draw_install_progress 10 0 0 0 0 2
    fi

    # ========================================================
    # 备份
    # ========================================================

    if ! backup_feeds; then

        _ssr_error "软件源备份失败"

        return 1

    fi


    if [ "$SSR_PROGRESS_READY" = "1" ]; then
        draw_install_progress 30 0 0 0 0 6
    fi

    trap 'cleanup_ssrplus' EXIT
    trap 'interrupt_ssrplus' INT TERM


    # ========================================================
    # 临时源
    # ========================================================

    if ! add_temp_feeds; then

        _ssr_error "添加临时软件源失败"

        cleanup_ssrplus

        trap - EXIT INT TERM

        return 1

    fi


    clean_openpro_lists


    # ========================================================
    # 更新软件列表
    # ========================================================

    # printf "\n"

    # _ssr_info "正在更新软件列表..."

    rm -f "$UPDATE_LOG"


    if ! opkg update >"$UPDATE_LOG" 2>&1; then

        printf "\n"

        _ssr_error "软件源更新失败"


        if [ -s "$UPDATE_LOG" ]; then

            printf "\n"
            printf "========== OPKG UPDATE ERROR ==========\n"

            cat "$UPDATE_LOG"

            printf "=======================================\n"

        fi


        cleanup_ssrplus

        trap - EXIT INT TERM

        return 1

    fi


    # 查询结束前保留更新日志。

    if [ "$SSR_PROGRESS_READY" = "1" ]; then
        draw_install_progress 80 0 0 0 0 16
    fi

    # _ssr_ok "软件列表更新完成"

    # printf "\n"


    # ========================================================
    # 如果 SSR Plus+ 已经安装
    #
    # 不再重新安装主程序，
    # 直接进入扩展组件检查。
    # ========================================================

    if check_ssrplus; then

        _ssr_ok "SSR Plus+ 主程序已经安装"

    else

        # ====================================================
        # 查询 SSR Plus+
        # ====================================================

        # _ssr_info "正在查询 luci-app-ssr-plus..."


        SSR_PACKAGE="$(
            opkg list 2>/dev/null |
            awk '
                $1 == "luci-app-ssr-plus" {
                    print $1
                    exit
                }
            '
        )"


        if [ "$SSR_PACKAGE" != "luci-app-ssr-plus" ]; then

            _ssr_error "OPKG 可用列表未查到 luci-app-ssr-plus"
            ssr_diagnose_missing_package

            cleanup_ssrplus

            trap - EXIT INT TERM

            return 2

        fi


        # _ssr_ok "已找到 luci-app-ssr-plus"


        # ====================================================
        # 版本
        # ====================================================

        SSR_VERSION="$(
            opkg list luci-app-ssr-plus 2>/dev/null |
            awk -F ' - ' '
                NR == 1 {
                    print $2
                }
            '
        )"


        # if [ -n "$SSR_VERSION" ]; then

            # _ssr_info "SSR Plus+ Version : $SSR_VERSION"

        # fi


        # ====================================================
        # 五阶段安装
        # ====================================================

        # printf "\n"

        # _ssr_info "开始安装 SSR Plus+..."

        # printf "\n"


        if ! install_with_progress \
            "luci-app-ssr-plus" \
            "$INSTALL_LOG"
        then

            printf "\n"

            _ssr_error "SSR Plus+ 安装失败"


            if [ -s "$INSTALL_LOG" ]; then

                printf "\n"

                printf "========== OPKG INSTALL ERROR =========\n"

                cat "$INSTALL_LOG"

                printf "=======================================\n"

            fi


            cleanup_ssrplus

            trap - EXIT INT TERM

            return 1

        fi


        rm -f "$INSTALL_LOG"

        printf "\n"


        # ====================================================
        # 验证
        # ====================================================

        _ssr_info "正在检查安装结果..."


        if ! check_ssrplus; then

            _ssr_error "未检测到 luci-app-ssr-plus"

            cleanup_ssrplus

            trap - EXIT INT TERM

            return 1

        fi


        _ssr_ok "SSR Plus+ 主程序安装成功"

    fi


    # ========================================================
    # 自动检查扩展组件
    #
    # 必须放在 cleanup_ssrplus 前面
    # 因为这里还需要使用临时软件源
    # ========================================================

    _ssr_info "主程序步骤完成，接下来安装全部匹配的可选组件"
    install_optional_ssr_packages
    if [ -s /tmp/openpro_ssrplus_extra_failures.log ]; then
        _ssr_warn "以下可选组件失败，主程序流程继续："
        grep '^===' /tmp/openpro_ssrplus_extra_failures.log
        _ssr_info "失败详情：/tmp/openpro_ssrplus_extra_failures.log"
    fi


    # ========================================================
    # 启用服务
    # ========================================================

    if [ -x /etc/init.d/shadowsocksr ]; then

        _ssr_info "正在设置 SSR Plus+ 开机启动..."

        /etc/init.d/shadowsocksr enable \
            >/dev/null 2>&1


        _ssr_ok "SSR Plus+ 已设置开机启动"

    else

        _ssr_warn "未找到 SSR Plus+ 服务脚本"

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
    _ssr_ok "扩展组件检测完成"
    _ssr_ok "临时软件源已经删除"
    _ssr_ok "临时软件列表已经清理"
    _ssr_ok "路由器原始软件源已经恢复"

    printf "\n"

    printf "请进入 LuCI 后台查看：\n"
    printf "服务 → ShadowSocksR Plus+\n"

    printf "\n"

    return 0
}

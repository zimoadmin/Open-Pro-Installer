#!/bin/sh

# ============================================================
# Open-Pro-Installer
# SSR Plus+ Auto Installer
# Five Stage Progress Edition
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
# 带五阶段进度执行安装
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

    TOTAL=5

    init_install_progress
    draw_install_progress \
        "$P1" "$P2" "$P3" "$P4" "$P5" "$TOTAL"

    opkg install "$PACKAGE" >"$LOG_FILE" 2>&1 &

    PROGRESS_PID=$!

    TICK=0

    while kill -0 "$PROGRESS_PID" 2>/dev/null; do

        TICK=$((TICK + 1))

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


        # ====================================================
        # 下载阶段
        # ====================================================

        if [ "$HAS_DOWNLOAD" -eq 1 ]; then

            if [ "$P2" -lt 90 ]; then
                P2=$((P2 + 5))
            fi

        else

            if [ "$P2" -lt 15 ]; then
                P2=$((P2 + 3))
            fi

        fi


        # ====================================================
        # 安装阶段
        # ====================================================

        if [ "$HAS_INSTALL" -eq 1 ]; then

            if [ "$P2" -lt 100 ]; then
                P2=100
            fi

            if [ "$P3" -lt 90 ]; then
                P3=$((P3 + 5))
            fi

        fi


        # ====================================================
        # 配置阶段
        # ====================================================

        if [ "$HAS_CONFIG" -eq 1 ]; then

            P2=100
            P3=100

            if [ "$P4" -lt 90 ]; then
                P4=$((P4 + 5))
            fi

        fi


        # ====================================================
        # 防止超过 100
        # ====================================================

        [ "$P2" -gt 100 ] && P2=100
        [ "$P3" -gt 100 ] && P3=100
        [ "$P4" -gt 100 ] && P4=100


        # ====================================================
        # 总进度
        #
        # 安装真正结束前最高 95%
        # ====================================================

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


    # ========================================================
    # 获取真正安装结果
    # ========================================================

    wait "$PROGRESS_PID"
    RESULT=$?

    PROGRESS_PID=""


    # ========================================================
    # 成功
    # ========================================================

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


    # ========================================================
    # 失败
    # ========================================================

    return "$RESULT"
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
    # 小写
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


    # MT798X

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


    # IPQ6000

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


    # IPQ53XX

    if [ "$PLATFORM" = "IPQ53XX" ] &&
       [ "$BITS" = "64" ]; then

        case "$OPENWRT_VERSION" in

            23.*)
                FEED_PATH="/ipq5312-qsdk12-5-64bit"
                FEED_NAME="IPQ53XX / QSDK 12.5 / OpenWrt 23 / 64位"
                ;;

        esac

    fi


    # IPQ5018

    if [ "$PLATFORM" = "IPQ5018" ] &&
       [ "$BITS" = "64" ]; then

        case "$OPENWRT_VERSION" in

            19.*)
                FEED_PATH="/b3000-qsdk12-2"
                FEED_NAME="IPQ5018 / B3000 / OpenWrt 19 / 64位"
                ;;

        esac

    fi


    # IPQ401X

    if [ "$PLATFORM" = "IPQ401X" ] &&
       [ "$BITS" = "32" ]; then

        case "$OPENWRT_VERSION" in

            21.*)
                FEED_PATH="/ipq4019"
                FEED_NAME="IPQ401X / OpenWrt 21 / 32位"
                ;;

        esac

    fi


    # SDX72

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


    _ssr_ok "已自动匹配软件源"
    _ssr_info "$FEED_NAME"

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


    _ssr_ok "原始软件源备份完成"

    return 0
}


# ============================================================
# 添加临时软件源
# ============================================================

add_temp_feeds()
{
    _ssr_info "正在添加 SSR Plus+ 临时软件源..."

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


    _ssr_ok "临时软件源添加完成"

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

        cp "$BACKUP_DIR/distfeeds.conf" "$DISTFEEDS"

    elif [ -f "$BACKUP_DIR/distfeeds.notexist" ]; then

        rm -f "$DISTFEEDS"

    fi


    if [ -f "$BACKUP_DIR/customfeeds.conf" ]; then

        cp "$BACKUP_DIR/customfeeds.conf" "$CUSTOMFEEDS"

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
    rm -f "$UPDATE_LOG" 2>/dev/null
    rm -f "$INSTALL_LOG" 2>/dev/null
}


check_ssrplus()
{
    opkg status luci-app-ssr-plus 2>/dev/null |
        grep -q 'Status:.*installed'
}


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
#
# install.sh 调用：
#
# install_ssrplus
#
# 不要删除这个函数
# ============================================================

install_ssrplus()
{
    printf "\n"
    printf "======================================\n"
    printf "        SSR Plus+ Installer\n"
    printf "======================================\n"
    printf "\n"


    # ROOT

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _ssr_error "请使用 root 用户运行"

        return 1

    fi


    # 包管理器

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


    _ssr_info "Package Manager : $PKG_MANAGER"

    printf "\n"


    # 已安装

    if check_ssrplus; then

        _ssr_ok "SSR Plus+ 已经安装"

        return 0

    fi


    # 检测设备

    if ! detect_system; then
        return 2
    fi


    # 匹配软件源

    if ! match_feed; then
        return 2
    fi


    # 备份

    if ! backup_feeds; then

        _ssr_error "软件源备份失败"

        return 1

    fi


    trap 'cleanup_ssrplus' EXIT
    trap 'interrupt_ssrplus' INT TERM


    # 添加临时源

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

    printf "\n"

    _ssr_info "正在更新软件列表..."

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


    rm -f "$UPDATE_LOG"

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

        _ssr_error "软件源中没有找到 luci-app-ssr-plus"

        cleanup_ssrplus
        trap - EXIT INT TERM

        return 2

    fi


    _ssr_ok "已找到 luci-app-ssr-plus"


    SSR_VERSION="$(
        opkg list luci-app-ssr-plus 2>/dev/null |
        awk -F ' - ' 'NR==1 {print $2}'
    )"


    if [ -n "$SSR_VERSION" ]; then

        _ssr_info "SSR Plus+ Version : $SSR_VERSION"

    fi


    # ========================================================
    # 五阶段安装
    # ========================================================

    printf "\n"

    _ssr_info "开始安装 SSR Plus+..."

    printf "\n"


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


    # ========================================================
    # 验证
    # ========================================================

    _ssr_info "正在检查安装结果..."


    if ! check_ssrplus; then

        _ssr_error "未检测到 luci-app-ssr-plus"

        cleanup_ssrplus
        trap - EXIT INT TERM

        return 1

    fi


    _ssr_ok "SSR Plus+ 安装成功"


    # ========================================================
    # 启用服务
    # ========================================================

    if [ -x /etc/init.d/shadowsocksr ]; then

        _ssr_info "正在启用 SSR Plus+ 服务..."

        /etc/init.d/shadowsocksr enable \
            >/dev/null 2>&1

    fi


    # ========================================================
    # 恢复原始源
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

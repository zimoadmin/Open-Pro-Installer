#!/bin/sh

# ============================================================
# Open-Pro-Installer
# PassWall Auto Installer
# Auto Detect + Shared Feed + Progress Edition
# ============================================================


# ============================================================
# 基础配置
# ============================================================

PW_BASE="http://glinet.83970255.xyz/?f="

PW_BACKUP_DIR="/tmp/openpro_passwall_backup"

PW_CUSTOMFEEDS="/etc/opkg/customfeeds.conf"
PW_DISTFEEDS="/etc/opkg/distfeeds.conf"

PW_UPDATE_LOG="/tmp/openpro_passwall_update.log"
PW_INSTALL_LOG="/tmp/openpro_passwall_install.log"
PW_EXTRA_LOG="/tmp/openpro_passwall_extra.log"

PW_FEED_PATH=""
PW_FEED_NAME=""

PW_MODEL="unknown"
PW_OPENWRT_VERSION="unknown"
PW_OPENWRT_TARGET="unknown"
PW_KERNEL_VERSION="unknown"
PW_ARCH="unknown"
PW_BITS="unknown"
PW_PLATFORM="unknown"

PW_TARGET_LOWER=""
PW_TARGET_FAMILY=""
PW_MODEL_LOWER=""

PW_PKG_MANAGER=""
PW_PROGRESS_PID=""


# ============================================================
# 日志
# ============================================================

_pw_info()
{
    if command -v info >/dev/null 2>&1; then
        info "$*"
    else
        printf '\033[32m[INFO]\033[0m %s\n' "$*"
    fi
}


_pw_warn()
{
    if command -v warn >/dev/null 2>&1; then
        warn "$*"
    else
        printf '\033[33m[WARN]\033[0m %s\n' "$*"
    fi
}


_pw_error()
{
    if command -v error >/dev/null 2>&1; then
        error "$*"
    else
        printf '\033[31m[ERROR]\033[0m %s\n' "$*"
    fi
}


_pw_ok()
{
    printf '\033[32m[OK]\033[0m %s\n' "$*"
}


# ============================================================
# 进度条
# ============================================================

pw_make_bar()
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


pw_draw_progress()
{
    P1="$1"
    P2="$2"
    P3="$3"
    P4="$4"
    P5="$5"
    TOTAL="$6"

    B1="$(pw_make_bar "$P1" 20)"
    B2="$(pw_make_bar "$P2" 20)"
    B3="$(pw_make_bar "$P3" 20)"
    B4="$(pw_make_bar "$P4" 20)"
    B5="$(pw_make_bar "$P5" 20)"
    BT="$(pw_make_bar "$TOTAL" 30)"

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


pw_init_progress()
{
    printf "[1/5] 准备安装环境  [--------------------]   0%%\n"
    printf "[2/5] 下载软件包    [--------------------]   0%%\n"
    printf "[3/5] 安装软件包    [--------------------]   0%%\n"
    printf "[4/5] 配置软件包    [--------------------]   0%%\n"
    printf "[5/5] 完成安装      [--------------------]   0%%\n"
    printf "总体进度           [------------------------------]   0%%\n"
}


# ============================================================
# 安装 + 动态进度
# ============================================================

pw_install_with_progress()
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

    pw_init_progress

    pw_draw_progress \
        "$P1" "$P2" "$P3" "$P4" "$P5" "$TOTAL"

    opkg install "$PACKAGE" >"$LOG_FILE" 2>&1 &

    PW_PROGRESS_PID=$!

    while kill -0 "$PW_PROGRESS_PID" 2>/dev/null; do

        HAS_DOWNLOAD=0
        HAS_INSTALL=0
        HAS_CONFIG=0

        grep -q '^Downloading ' "$LOG_FILE" 2>/dev/null &&
            HAS_DOWNLOAD=1

        grep -q '^Installing ' "$LOG_FILE" 2>/dev/null &&
            HAS_INSTALL=1

        grep -q '^Configuring ' "$LOG_FILE" 2>/dev/null &&
            HAS_CONFIG=1


        if [ "$HAS_DOWNLOAD" -eq 1 ]; then

            if [ "$P2" -lt 90 ]; then
                P2=$((P2 + 5))
            fi

        else

            if [ "$P2" -lt 15 ]; then
                P2=$((P2 + 3))
            fi

        fi


        if [ "$HAS_INSTALL" -eq 1 ]; then

            P2=100

            if [ "$P3" -lt 90 ]; then
                P3=$((P3 + 5))
            fi

        fi


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


        TOTAL=$(( (P1 + P2 + P3 + P4 + P5) / 5 ))

        [ "$TOTAL" -gt 95 ] && TOTAL=95


        pw_draw_progress \
            "$P1" "$P2" "$P3" "$P4" "$P5" "$TOTAL"

        sleep 1

    done


    wait "$PW_PROGRESS_PID"
    RESULT=$?

    PW_PROGRESS_PID=""


    if [ "$RESULT" -eq 0 ]; then

        P1=100
        P2=100
        P3=100
        P4=100
        P5=100
        TOTAL=100

        pw_draw_progress \
            "$P1" "$P2" "$P3" "$P4" "$P5" "$TOTAL"

        return 0

    fi


    return "$RESULT"
}


# ============================================================
# 检测系统
# ============================================================

detect_passwall_system()
{
    _pw_info "正在检测设备信息..."

    PW_MODEL="unknown"
    PW_OPENWRT_VERSION="unknown"
    PW_OPENWRT_TARGET="unknown"
    PW_KERNEL_VERSION="unknown"
    PW_ARCH="unknown"
    PW_BITS="unknown"
    PW_PLATFORM="unknown"

    PW_TARGET_LOWER=""
    PW_TARGET_FAMILY=""
    PW_MODEL_LOWER=""


    # Kernel / Architecture

    PW_KERNEL_VERSION="$(uname -r 2>/dev/null)"
    PW_ARCH="$(uname -m 2>/dev/null)"

    [ -n "$PW_KERNEL_VERSION" ] ||
        PW_KERNEL_VERSION="unknown"

    [ -n "$PW_ARCH" ] ||
        PW_ARCH="unknown"


    # ========================================================
    # 型号
    # ========================================================

    if [ -s /tmp/sysinfo/model ]; then

        PW_MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"

    elif [ -f /proc/device-tree/model ]; then

        PW_MODEL="$(
            tr -d '\000' \
            < /proc/device-tree/model \
            2>/dev/null
        )"

    fi

    [ -n "$PW_MODEL" ] ||
        PW_MODEL="unknown"


    # ========================================================
    # OpenWrt
    # ========================================================

    if [ -f /etc/openwrt_release ]; then

        . /etc/openwrt_release

        PW_OPENWRT_VERSION="${DISTRIB_RELEASE:-unknown}"
        PW_OPENWRT_TARGET="${DISTRIB_TARGET:-unknown}"

    fi


    # ========================================================
    # UBUS 兜底
    # ========================================================

    if command -v ubus >/dev/null 2>&1 &&
       command -v jsonfilter >/dev/null 2>&1; then

        PW_BOARD_JSON="$(ubus call system board 2>/dev/null)"


        if [ "$PW_OPENWRT_TARGET" = "unknown" ] ||
           [ -z "$PW_OPENWRT_TARGET" ]; then

            PW_TMP_TARGET="$(
                printf '%s' "$PW_BOARD_JSON" |
                jsonfilter -e '@.release.target' 2>/dev/null
            )"

            [ -n "$PW_TMP_TARGET" ] &&
                PW_OPENWRT_TARGET="$PW_TMP_TARGET"

        fi


        if [ "$PW_OPENWRT_VERSION" = "unknown" ] ||
           [ -z "$PW_OPENWRT_VERSION" ]; then

            PW_TMP_VERSION="$(
                printf '%s' "$PW_BOARD_JSON" |
                jsonfilter -e '@.release.version' 2>/dev/null
            )"

            [ -n "$PW_TMP_VERSION" ] &&
                PW_OPENWRT_VERSION="$PW_TMP_VERSION"

        fi

    fi


    # ========================================================
    # 清理
    # ========================================================

    PW_OPENWRT_TARGET="$(
        printf '%s' "$PW_OPENWRT_TARGET" |
        tr -d '\r\n\t '
    )"

    PW_OPENWRT_VERSION="$(
        printf '%s' "$PW_OPENWRT_VERSION" |
        tr -d '\r\n\t '
    )"

    PW_MODEL="$(
        printf '%s' "$PW_MODEL" |
        tr -d '\r\n'
    )"


    # ========================================================
    # 32 / 64 位
    # ========================================================

    case "$PW_ARCH" in

        x86_64|aarch64|arm64|mips64|mips64el|mips64*)
            PW_BITS="64"
            ;;

        armv5*|armv6*|armv7*|armhf|mips|mipsel|mips32*)
            PW_BITS="32"
            ;;

        *)

            PW_LONG_BIT="$(getconf LONG_BIT 2>/dev/null)"

            case "$PW_LONG_BIT" in

                64)
                    PW_BITS="64"
                    ;;

                32)
                    PW_BITS="32"
                    ;;

                *)
                    PW_BITS="unknown"
                    ;;

            esac

            ;;

    esac


    # ========================================================
    # 小写
    # ========================================================

    PW_TARGET_LOWER="$(
        printf '%s' "$PW_OPENWRT_TARGET" |
        tr '[:upper:]' '[:lower:]' |
        tr -d '\r\n\t '
    )"

    PW_MODEL_LOWER="$(
        printf '%s' "$PW_MODEL" |
        tr '[:upper:]' '[:lower:]' |
        tr -d '\r\n'
    )"


    PW_TARGET_FAMILY="$(
        printf '%s' "$PW_TARGET_LOWER" |
        cut -d '/' -f 1
    )"


    # ========================================================
    # 第一层：Target Family
    # ========================================================

    case "$PW_TARGET_FAMILY" in

        ipq53xx|ipq5332|ipq5312)
            PW_PLATFORM="IPQ53XX"
            ;;

        ipq6000)
            PW_PLATFORM="IPQ6000"
            ;;

        ipq5018)
            PW_PLATFORM="IPQ5018"
            ;;

        ipq4019|ipq401x)
            PW_PLATFORM="IPQ401X"
            ;;

        sdx72)
            PW_PLATFORM="SDX72"
            ;;

    esac


    # ========================================================
    # 第二层：完整 Target
    # ========================================================

    if [ "$PW_PLATFORM" = "unknown" ]; then

        case "$PW_TARGET_LOWER" in

            *ipq53xx*|*ipq5332*|*ipq5312*)
                PW_PLATFORM="IPQ53XX"
                ;;

            *ipq6000*)
                PW_PLATFORM="IPQ6000"
                ;;

            *ipq5018*)
                PW_PLATFORM="IPQ5018"
                ;;

            *ipq4019*|*ipq401x*)
                PW_PLATFORM="IPQ401X"
                ;;

            *mt7981*|*mt7986*|*mt7987*|*mt7988*|*mt798x*)
                PW_PLATFORM="MT798X"
                ;;

            *sdx72*)
                PW_PLATFORM="SDX72"
                ;;

        esac

    fi


    # ========================================================
    # 第三层：Model / SoC
    # ========================================================

    if [ "$PW_PLATFORM" = "unknown" ]; then

        case "$PW_MODEL_LOWER" in

            *ipq53xx*|*ipq5312*|*ipq5332*)
                PW_PLATFORM="IPQ53XX"
                ;;

            *ipq6000*)
                PW_PLATFORM="IPQ6000"
                ;;

            *ipq5018*)
                PW_PLATFORM="IPQ5018"
                ;;

            *ipq4019*|*ipq401x*)
                PW_PLATFORM="IPQ401X"
                ;;

            *mt7981*|*mt7986*|*mt7987*|*mt7988*|*mt798x*)
                PW_PLATFORM="MT798X"
                ;;

            *sdx72*)
                PW_PLATFORM="SDX72"
                ;;

        esac

    fi


    # ========================================================
    # 第四层：GL.iNet 型号
    # ========================================================

    if [ "$PW_PLATFORM" = "unknown" ]; then

        case "$PW_MODEL_LOWER" in

            *be3600*|*be6500*|*be9300*)
                PW_PLATFORM="IPQ53XX"
                ;;

            *ax1800*|*axt1800*)
                PW_PLATFORM="IPQ6000"
                ;;

            *b3000*)
                PW_PLATFORM="IPQ5018"
                ;;

            *b1300*)
                PW_PLATFORM="IPQ401X"
                ;;

            *mt2500*|*mt3000*|*mt5000*|*mt6000*|*mt3600*)
                PW_PLATFORM="MT798X"
                ;;

            *e5800*|*mudi7*)
                PW_PLATFORM="SDX72"
                ;;

        esac

    fi


    # ========================================================
    # IPQ53XX 强制兜底
    # ========================================================

    if [ "$PW_PLATFORM" = "unknown" ]; then

        if printf '%s\n%s\n' \
            "$PW_OPENWRT_TARGET" \
            "$PW_MODEL" |
            grep -Eqi \
            'ipq53xx|ipq5332|ipq5312|be3600|be6500|be9300'
        then

            PW_PLATFORM="IPQ53XX"

        fi

    fi


    # ========================================================
    # MT798X 强制兜底
    # ========================================================

    if [ "$PW_PLATFORM" = "unknown" ]; then

        if printf '%s\n%s\n' \
            "$PW_OPENWRT_TARGET" \
            "$PW_MODEL" |
            grep -Eqi \
            'mt7981|mt7986|mt7987|mt7988|mt2500|mt3000|mt5000|mt6000|mt3600'
        then

            PW_PLATFORM="MT798X"

        fi

    fi


    # ========================================================
    # 显示结果
    # ========================================================

    printf "\n"
    printf "======================================\n"
    printf "          设备检测结果\n"
    printf "======================================\n"
    printf "机型     : %s\n" "$PW_MODEL"
    printf "平台     : %s\n" "$PW_PLATFORM"
    printf "OpenWrt  : %s\n" "$PW_OPENWRT_VERSION"
    printf "Target   : %s\n" "$PW_OPENWRT_TARGET"
    printf "Family   : %s\n" "$PW_TARGET_FAMILY"
    printf "Kernel   : %s\n" "$PW_KERNEL_VERSION"
    printf "架构     : %s\n" "$PW_ARCH"
    printf "系统     : %s 位\n" "$PW_BITS"
    printf "======================================\n"
    printf "\n"


    if [ "$PW_PLATFORM" = "unknown" ]; then

        _pw_error "无法识别当前设备平台"

        return 1

    fi


    if [ "$PW_BITS" = "unknown" ]; then

        _pw_error "无法识别当前系统位数"

        return 1

    fi


    return 0
}


# ============================================================
# 匹配与 SSR Plus+ 共用的软件源
# ============================================================

match_passwall_feed()
{
    PW_FEED_PATH=""
    PW_FEED_NAME=""


    # ========================================================
    # MT798X
    # ========================================================

    if [ "$PW_PLATFORM" = "MT798X" ] &&
       [ "$PW_BITS" = "64" ]; then

        case "$PW_OPENWRT_VERSION" in

            21.*)

                case "$PW_KERNEL_VERSION" in

                    5.4.*)

                        PW_FEED_PATH="/mt798x-openwrt21"
                        PW_FEED_NAME="MT798X / OpenWrt 21 / Kernel 5.4 / 64位"

                        ;;

                esac

                ;;


            24.*)

                case "$PW_KERNEL_VERSION" in

                    6.6.*)

                        PW_FEED_PATH="/mt798x-openwrt24"
                        PW_FEED_NAME="MT798X / OpenWrt 24 / Kernel 6.6 / 64位"

                        ;;

                esac

                ;;

        esac

    fi


    # ========================================================
    # IPQ6000
    # ========================================================

    if [ "$PW_PLATFORM" = "IPQ6000" ]; then

        if [ "$PW_BITS" = "64" ]; then

            case "$PW_OPENWRT_VERSION" in

                23.*)

                    PW_FEED_PATH="/ipq6000-tip-64bit"
                    PW_FEED_NAME="IPQ6000 / OpenWrt 23 / 64位"

                    ;;

            esac


        elif [ "$PW_BITS" = "32" ]; then

            PW_FEED_PATH="/ipq6000-2023-09-不再更新"
            PW_FEED_NAME="IPQ6000 / 32位旧系统"

            _pw_warn "当前 IPQ6000 使用 32 位旧系统"
            _pw_warn "该软件源已经停止更新"

        fi

    fi


    # ========================================================
    # IPQ53XX
    # ========================================================

    if [ "$PW_PLATFORM" = "IPQ53XX" ] &&
       [ "$PW_BITS" = "64" ]; then

        case "$PW_OPENWRT_VERSION" in

            23.*)

                PW_FEED_PATH="/ipq5312-qsdk12-5-64bit"
                PW_FEED_NAME="IPQ53XX / QSDK 12.5 / OpenWrt 23 / 64位"

                ;;

        esac

    fi


    # ========================================================
    # IPQ5018
    # ========================================================

    if [ "$PW_PLATFORM" = "IPQ5018" ] &&
       [ "$PW_BITS" = "64" ]; then

        case "$PW_OPENWRT_VERSION" in

            19.*)

                PW_FEED_PATH="/b3000-qsdk12-2"
                PW_FEED_NAME="IPQ5018 / B3000 / OpenWrt 19 / 64位"

                ;;

        esac

    fi


    # ========================================================
    # IPQ401X
    # ========================================================

    if [ "$PW_PLATFORM" = "IPQ401X" ] &&
       [ "$PW_BITS" = "32" ]; then

        case "$PW_OPENWRT_VERSION" in

            21.*)

                PW_FEED_PATH="/ipq4019"
                PW_FEED_NAME="IPQ401X / OpenWrt 21 / 32位"

                ;;

        esac

    fi


    # ========================================================
    # SDX72
    # ========================================================

    if [ "$PW_PLATFORM" = "SDX72" ] &&
       [ "$PW_BITS" = "64" ]; then

        case "$PW_OPENWRT_VERSION" in

            23.*)

                PW_FEED_PATH="/mudi7"
                PW_FEED_NAME="Mudi7 / SDX72 / OpenWrt 23 / 64位"

                ;;

        esac

    fi


    # ========================================================
    # 没匹配到
    # ========================================================

    if [ -z "$PW_FEED_PATH" ]; then

        _pw_error "没有找到适用于当前设备的 PassWall 软件源"

        printf "\n"
        printf "系统信息：\n"
        printf "--------------------------------------\n"
        printf "机型    : %s\n" "$PW_MODEL"
        printf "平台    : %s\n" "$PW_PLATFORM"
        printf "OpenWrt : %s\n" "$PW_OPENWRT_VERSION"
        printf "Target  : %s\n" "$PW_OPENWRT_TARGET"
        printf "Family  : %s\n" "$PW_TARGET_FAMILY"
        printf "Kernel  : %s\n" "$PW_KERNEL_VERSION"
        printf "架构    : %s\n" "$PW_ARCH"
        printf "位数    : %s\n" "$PW_BITS"
        printf "--------------------------------------\n"
        printf "\n"

        _pw_warn "为避免安装错误架构的软件包，已取消安装。"

        return 1

    fi


    _pw_ok "已自动匹配软件源"
    _pw_info "$PW_FEED_NAME"

    printf "\n"

    return 0
}


# ============================================================
# 备份软件源
# ============================================================

backup_passwall_feeds()
{
    _pw_info "正在备份原始软件源..."

    rm -rf "$PW_BACKUP_DIR"

    mkdir -p "$PW_BACKUP_DIR" || {

        _pw_error "无法创建备份目录"

        return 1
    }


    if [ -f "$PW_DISTFEEDS" ]; then

        cp "$PW_DISTFEEDS" \
            "$PW_BACKUP_DIR/distfeeds.conf" || return 1

    else

        touch "$PW_BACKUP_DIR/distfeeds.notexist"

    fi


    if [ -f "$PW_CUSTOMFEEDS" ]; then

        cp "$PW_CUSTOMFEEDS" \
            "$PW_BACKUP_DIR/customfeeds.conf" || return 1

    else

        touch "$PW_BACKUP_DIR/customfeeds.notexist"

    fi


    _pw_ok "原始软件源备份完成"

    return 0
}


# ============================================================
# 添加临时软件源
# ============================================================

add_passwall_temp_feeds()
{
    _pw_info "正在添加 PassWall 临时软件源..."

    mkdir -p /etc/opkg || return 1

    [ -f "$PW_CUSTOMFEEDS" ] ||
        touch "$PW_CUSTOMFEEDS" ||
        return 1


    # 删除旧 Open-Pro PassWall 源

    sed -i \
        '/^src\/gz openpro_pw_/d' \
        "$PW_CUSTOMFEEDS"


    printf '\n' >> "$PW_CUSTOMFEEDS"


    printf 'src/gz openpro_pw_packages %s%s/packages\n' \
        "$PW_BASE" \
        "$PW_FEED_PATH" \
        >> "$PW_CUSTOMFEEDS"


    printf 'src/gz openpro_pw_luci %s%s/luci\n' \
        "$PW_BASE" \
        "$PW_FEED_PATH" \
        >> "$PW_CUSTOMFEEDS"


    printf 'src/gz openpro_pw_base %s%s/base\n' \
        "$PW_BASE" \
        "$PW_FEED_PATH" \
        >> "$PW_CUSTOMFEEDS"


    _pw_ok "临时软件源添加完成"

    return 0
}


# ============================================================
# 恢复软件源
# ============================================================

restore_passwall_feeds()
{
    [ -d "$PW_BACKUP_DIR" ] ||
        return 0


    _pw_info "正在恢复原始软件源..."


    if [ -f "$PW_BACKUP_DIR/distfeeds.conf" ]; then

        cp "$PW_BACKUP_DIR/distfeeds.conf" \
            "$PW_DISTFEEDS"

    elif [ -f "$PW_BACKUP_DIR/distfeeds.notexist" ]; then

        rm -f "$PW_DISTFEEDS"

    fi


    if [ -f "$PW_BACKUP_DIR/customfeeds.conf" ]; then

        cp "$PW_BACKUP_DIR/customfeeds.conf" \
            "$PW_CUSTOMFEEDS"

    elif [ -f "$PW_BACKUP_DIR/customfeeds.notexist" ]; then

        rm -f "$PW_CUSTOMFEEDS"

    fi


    rm -rf "$PW_BACKUP_DIR"

    _pw_ok "原始软件源已恢复"

    return 0
}


# ============================================================
# 清理临时列表
# ============================================================

clean_passwall_lists()
{
    rm -f /var/opkg-lists/openpro_pw_packages 2>/dev/null
    rm -f /var/opkg-lists/openpro_pw_luci 2>/dev/null
    rm -f /var/opkg-lists/openpro_pw_base 2>/dev/null
}


clean_passwall_logs()
{
    rm -f "$PW_UPDATE_LOG" 2>/dev/null
    rm -f "$PW_INSTALL_LOG" 2>/dev/null
    rm -f "$PW_EXTRA_LOG" 2>/dev/null
}


# ============================================================
# 检查安装状态
# ============================================================

check_passwall()
{
    opkg status luci-app-passwall 2>/dev/null |
        grep -q 'Status:.*installed'
}


pw_package_exists()
{
    PACKAGE="$1"

    opkg list "$PACKAGE" 2>/dev/null |
        awk -v p="$PACKAGE" '$1 == p { found=1 } END { exit !found }'
}


pw_package_installed()
{
    PACKAGE="$1"

    opkg status "$PACKAGE" 2>/dev/null |
        grep -q 'Status:.*installed'
}


# ============================================================
# 自动安装一个可选包
# ============================================================

pw_install_optional()
{
    PACKAGE="$1"

    if pw_package_installed "$PACKAGE"; then

        _pw_ok "$PACKAGE 已安装"

        return 0
    fi


    if ! pw_package_exists "$PACKAGE"; then

        _pw_warn "$PACKAGE 不存在，已跳过"

        return 0
    fi


    _pw_info "正在安装 $PACKAGE..."


    if opkg install "$PACKAGE" \
        >"$PW_EXTRA_LOG" 2>&1
    then

        _pw_ok "$PACKAGE 安装完成"

        rm -f "$PW_EXTRA_LOG"

        return 0

    fi


    _pw_warn "$PACKAGE 安装失败，已跳过"

    rm -f "$PW_EXTRA_LOG"

    return 0
}


# ============================================================
# 自动发现并安装 PassWall 相关组件
# ============================================================

install_passwall_extras()
{
    printf "\n"

    _pw_info "正在检测 PassWall 中文包及扩展组件..."


    # ========================================================
    # 中文包
    # ========================================================

    pw_install_optional "luci-i18n-passwall-zh-cn"


    # ========================================================
    # 自动发现源中的 PassWall 组件
    #
    # 不写死 xx
    # 源中以后增加新组件，也可以自动发现
    # ========================================================

    PW_COMPONENTS="$(
        opkg list 2>/dev/null |
        awk '{print $1}' |
        grep -E \
        '^(chinadns-ng|dns2socks|ipt2socks|microsocks|naiveproxy|shadowsocks-libev-|shadowsocks-rust-|shadowsocksr-libev-|simple-obfs|sing-box|ssocks|tcping|trojan|trojan-go|tuic-client|v2ray-core|v2ray-geodata|v2ray-plugin|xray-core|xray-plugin|hysteria|hysteria2)' |
        sort -u
    )"


    if [ -z "$PW_COMPONENTS" ]; then

        _pw_warn "没有发现额外 PassWall 组件"

        return 0
    fi


    FOUND_COUNT=0
    INSTALLED_COUNT=0


    for PACKAGE in $PW_COMPONENTS
    do

        FOUND_COUNT=$((FOUND_COUNT + 1))


        if pw_package_installed "$PACKAGE"; then

            continue

        fi


        _pw_info "发现组件：$PACKAGE"


        if opkg install "$PACKAGE" \
            >"$PW_EXTRA_LOG" 2>&1
        then

            _pw_ok "$PACKAGE 安装完成"

            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))

        else

            # 某个可选组件失败不影响 PassWall 主程序
            _pw_warn "$PACKAGE 安装失败，已跳过"

        fi

    done


    rm -f "$PW_EXTRA_LOG"


    printf "\n"

    _pw_ok "扩展组件检测完成"
    _pw_info "发现组件：$FOUND_COUNT 个"
    _pw_info "新增安装：$INSTALLED_COUNT 个"

    return 0
}


# ============================================================
# 清理
# ============================================================

cleanup_passwall()
{
    restore_passwall_feeds
    clean_passwall_lists
    clean_passwall_logs
}


# ============================================================
# 中断处理
# ============================================================

interrupt_passwall()
{
    printf "\n"

    _pw_warn "安装被中断"


    if [ -n "$PW_PROGRESS_PID" ]; then

        kill "$PW_PROGRESS_PID" 2>/dev/null
        wait "$PW_PROGRESS_PID" 2>/dev/null

    fi


    cleanup_passwall

    trap - EXIT INT TERM

    exit 130
}


# ============================================================
# 主安装函数
#
# install.sh 调用：
#
# install_passwall
#
# ============================================================

install_passwall()
{
    printf "\n"
    printf "======================================\n"
    printf "          PassWall Installer\n"
    printf "======================================\n"
    printf "\n"


    # ========================================================
    # ROOT
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _pw_error "请使用 root 用户运行"

        return 1

    fi


    # ========================================================
    # 包管理器
    # ========================================================

    if command -v opkg >/dev/null 2>&1; then

        PW_PKG_MANAGER="opkg"

    elif command -v apk >/dev/null 2>&1; then

        _pw_error "检测到 APK 包管理器"
        _pw_warn "当前 PassWall 软件源为 OPKG 软件源"

        return 1

    else

        _pw_error "未检测到 OPKG 包管理器"

        return 1

    fi


    _pw_info "Package Manager : $PW_PKG_MANAGER"

    printf "\n"


    # ========================================================
    # 已安装
    # ========================================================

    if check_passwall; then

        _pw_ok "PassWall 已经安装"

        return 0

    fi


    # ========================================================
    # 检测系统
    # ========================================================

    if ! detect_passwall_system; then

        return 2

    fi


    # ========================================================
    # 匹配源
    # ========================================================

    if ! match_passwall_feed; then

        return 2

    fi


    # ========================================================
    # 备份源
    # ========================================================

    if ! backup_passwall_feeds; then

        _pw_error "软件源备份失败"

        return 1

    fi


    trap 'cleanup_passwall' EXIT
    trap 'interrupt_passwall' INT TERM


    # ========================================================
    # 添加源
    # ========================================================

    if ! add_passwall_temp_feeds; then

        _pw_error "添加 PassWall 临时软件源失败"

        cleanup_passwall
        trap - EXIT INT TERM

        return 1

    fi


    clean_passwall_lists


    # ========================================================
    # 更新列表
    # ========================================================

    printf "\n"

    _pw_info "正在更新软件列表..."

    rm -f "$PW_UPDATE_LOG"


    if ! opkg update >"$PW_UPDATE_LOG" 2>&1; then

        printf "\n"

        _pw_error "软件源更新失败"


        if [ -s "$PW_UPDATE_LOG" ]; then

            printf "\n"
            printf "========== OPKG UPDATE ERROR ==========\n"
            cat "$PW_UPDATE_LOG"
            printf "=======================================\n"

        fi


        cleanup_passwall
        trap - EXIT INT TERM

        return 1

    fi


    rm -f "$PW_UPDATE_LOG"

    _pw_ok "软件列表更新完成"

    printf "\n"


    # ========================================================
    # 查询 PassWall
    # ========================================================

    _pw_info "正在查询 luci-app-passwall..."


    if ! pw_package_exists "luci-app-passwall"; then

        _pw_error "当前软件源中没有找到 luci-app-passwall"

        printf "\n"
        _pw_warn "设备识别和软件源匹配已经完成"
        _pw_warn "但该目录的软件列表中不存在 PassWall"

        cleanup_passwall
        trap - EXIT INT TERM

        return 2

    fi


    _pw_ok "已找到 luci-app-passwall"


    PW_VERSION="$(
        opkg list luci-app-passwall 2>/dev/null |
        awk -F ' - ' 'NR==1 {print $2}'
    )"


    if [ -n "$PW_VERSION" ]; then

        _pw_info "PassWall Version : $PW_VERSION"

    fi


    # ========================================================
    # 安装 PassWall
    # ========================================================

    printf "\n"

    _pw_info "开始安装 PassWall..."

    printf "\n"


    if ! pw_install_with_progress \
        "luci-app-passwall" \
        "$PW_INSTALL_LOG"
    then

        printf "\n"

        _pw_error "PassWall 安装失败"


        if [ -s "$PW_INSTALL_LOG" ]; then

            printf "\n"
            printf "========== OPKG INSTALL ERROR =========\n"
            cat "$PW_INSTALL_LOG"
            printf "=======================================\n"

        fi


        cleanup_passwall
        trap - EXIT INT TERM

        return 1

    fi


    rm -f "$PW_INSTALL_LOG"

    printf "\n"


    # ========================================================
    # 验证主程序
    # ========================================================

    _pw_info "正在检查安装结果..."


    if ! check_passwall; then

        _pw_error "未检测到 luci-app-passwall"

        cleanup_passwall
        trap - EXIT INT TERM

        return 1

    fi


    _pw_ok "PassWall 安装成功"


    # ========================================================
    # 中文包 + 自动组件
    # ========================================================

    install_passwall_extras


    # ========================================================
    # 启用服务
    # ========================================================

    if [ -x /etc/init.d/passwall ]; then

        printf "\n"

        _pw_info "正在启用 PassWall 服务..."

        /etc/init.d/passwall enable \
            >/dev/null 2>&1

        _pw_ok "PassWall 服务已设置为开机启动"

    fi


    # ========================================================
    # 恢复源
    # ========================================================

    printf "\n"

    cleanup_passwall

    trap - EXIT INT TERM


    # ========================================================
    # 完成
    # ========================================================

    printf "\n"
    printf "======================================\n"
    printf "          PassWall Installed\n"
    printf "======================================\n"
    printf "\n"

    _pw_ok "PassWall 安装完成"
    _pw_ok "PassWall 可用扩展组件检测完成"
    _pw_ok "临时软件源已经删除"
    _pw_ok "临时软件列表已经清理"
    _pw_ok "路由器原始软件源已经恢复"

    printf "\n"
    printf "请进入 LuCI 后台查看：\n"
    printf "服务 → PassWall\n"
    printf "\n"

    return 0
}

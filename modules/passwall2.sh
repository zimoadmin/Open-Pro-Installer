#!/bin/sh

# ============================================================
# Open-Pro-Installer
# PassWall2 Auto Installer
#
# 功能：
# 1. 自动检测设备型号
# 2. 自动识别处理器平台
# 3. 自动检测 OpenWrt
# 4. 自动检测 Kernel
# 5. 自动检测 32/64 位
# 6. 自动匹配软件源
# 7. 自动备份原始软件源
# 8. 临时添加 PassWall2 软件源
# 9. 静默更新软件列表
# 10. 安装 PassWall2
# 11. 五阶段安装进度条
# 12. 自动安装中文语言包
# 13. 自动扫描并安装扩展组件
# 14. 自动安装 Shadowsocks / SSR / Rust 相关组件
# 15. 自动安装 server / local / redir / tunnel 等组件
# 16. 自动安装 Xray / sing-box / Trojan 等组件
# 17. 自动恢复原始软件源
# ============================================================


# ============================================================
# 基础配置
# ============================================================

PW2_BASE="http://glinet.83970255.xyz/?f="

PW2_BACKUP_DIR="/tmp/openpro_passwall2_backup"

PW2_CUSTOMFEEDS="/etc/opkg/customfeeds.conf"
PW2_DISTFEEDS="/etc/opkg/distfeeds.conf"

PW2_UPDATE_LOG="/tmp/openpro_passwall2_update.log"
PW2_INSTALL_LOG="/tmp/openpro_passwall2_install.log"
PW2_EXTRA_LOG="/tmp/openpro_passwall2_extra.log"

PW2_FEED_PATH=""
PW2_FEED_NAME=""

PW2_MODEL="unknown"
PW2_OPENWRT_VERSION="unknown"
PW2_OPENWRT_TARGET="unknown"
PW2_KERNEL_VERSION="unknown"
PW2_ARCH="unknown"
PW2_BITS="unknown"
PW2_PLATFORM="unknown"

PW2_TARGET_LOWER=""
PW2_TARGET_FAMILY=""
PW2_MODEL_LOWER=""

PW2_PKG_MANAGER=""

PW2_PROGRESS_PID=""


# ============================================================
# 日志
# ============================================================

_pw2_info()
{
    if command -v info >/dev/null 2>&1; then
        info "$*"
    else
        printf '\033[32m[INFO]\033[0m %s\n' "$*"
    fi
}


_pw2_warn()
{
    if command -v warn >/dev/null 2>&1; then
        warn "$*"
    else
        printf '\033[33m[WARN]\033[0m %s\n' "$*"
    fi
}


_pw2_error()
{
    if command -v error >/dev/null 2>&1; then
        error "$*"
    else
        printf '\033[31m[ERROR]\033[0m %s\n' "$*"
    fi
}


_pw2_ok()
{
    printf '\033[32m[OK]\033[0m %s\n' "$*"
}


# ============================================================
# 生成进度条
# ============================================================

pw2_make_bar()
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

pw2_draw_progress()
{
    P1="$1"
    P2="$2"
    P3="$3"
    P4="$4"
    P5="$5"
    TOTAL="$6"

    B1="$(pw2_make_bar "$P1" 20)"
    B2="$(pw2_make_bar "$P2" 20)"
    B3="$(pw2_make_bar "$P3" 20)"
    B4="$(pw2_make_bar "$P4" 20)"
    B5="$(pw2_make_bar "$P5" 20)"
    BT="$(pw2_make_bar "$TOTAL" 30)"

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

pw2_init_progress()
{
    printf "[1/5] 准备安装环境  [--------------------]   0%%\n"
    printf "[2/5] 下载软件包    [--------------------]   0%%\n"
    printf "[3/5] 安装软件包    [--------------------]   0%%\n"
    printf "[4/5] 配置软件包    [--------------------]   0%%\n"
    printf "[5/5] 完成安装      [--------------------]   0%%\n"
    printf "总体进度           [------------------------------]   0%%\n"
}


# ============================================================
# 带进度条安装
# ============================================================

pw2_install_with_progress()
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

    pw2_init_progress

    pw2_draw_progress \
        "$P1" "$P2" "$P3" "$P4" "$P5" "$TOTAL"


    opkg install "$PACKAGE" >"$LOG_FILE" 2>&1 &

    PW2_PROGRESS_PID=$!


    while kill -0 "$PW2_PROGRESS_PID" 2>/dev/null; do

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

            P2=100

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


        [ "$P2" -gt 100 ] && P2=100
        [ "$P3" -gt 100 ] && P3=100
        [ "$P4" -gt 100 ] && P4=100


        TOTAL=$(( (P1 + P2 + P3 + P4 + P5) / 5 ))


        if [ "$TOTAL" -gt 95 ]; then
            TOTAL=95
        fi


        pw2_draw_progress \
            "$P1" \
            "$P2" \
            "$P3" \
            "$P4" \
            "$P5" \
            "$TOTAL"


        sleep 1

    done


    # ========================================================
    # 获取安装结果
    # ========================================================

    wait "$PW2_PROGRESS_PID"
    RESULT=$?

    PW2_PROGRESS_PID=""


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


        pw2_draw_progress \
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

detect_passwall2_system()
{
    _pw2_info "正在检测设备信息..."

    PW2_MODEL="unknown"
    PW2_OPENWRT_VERSION="unknown"
    PW2_OPENWRT_TARGET="unknown"
    PW2_KERNEL_VERSION="unknown"
    PW2_ARCH="unknown"
    PW2_BITS="unknown"
    PW2_PLATFORM="unknown"

    PW2_TARGET_LOWER=""
    PW2_TARGET_FAMILY=""
    PW2_MODEL_LOWER=""


    # ========================================================
    # Kernel / Architecture
    # ========================================================

    PW2_KERNEL_VERSION="$(uname -r 2>/dev/null)"
    PW2_ARCH="$(uname -m 2>/dev/null)"

    [ -n "$PW2_KERNEL_VERSION" ] ||
        PW2_KERNEL_VERSION="unknown"

    [ -n "$PW2_ARCH" ] ||
        PW2_ARCH="unknown"


    # ========================================================
    # 设备型号
    # ========================================================

    if [ -s /tmp/sysinfo/model ]; then

        PW2_MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"

    elif [ -f /proc/device-tree/model ]; then

        PW2_MODEL="$(
            tr -d '\000' \
            < /proc/device-tree/model \
            2>/dev/null
        )"

    fi


    [ -n "$PW2_MODEL" ] ||
        PW2_MODEL="unknown"


    # ========================================================
    # OpenWrt 信息
    # ========================================================

    if [ -f /etc/openwrt_release ]; then

        . /etc/openwrt_release

        PW2_OPENWRT_VERSION="${DISTRIB_RELEASE:-unknown}"
        PW2_OPENWRT_TARGET="${DISTRIB_TARGET:-unknown}"

    fi


    # ========================================================
    # UBUS 兜底
    # ========================================================

    if command -v ubus >/dev/null 2>&1 &&
       command -v jsonfilter >/dev/null 2>&1; then

        PW2_BOARD_JSON="$(ubus call system board 2>/dev/null)"


        if [ "$PW2_OPENWRT_TARGET" = "unknown" ] ||
           [ -z "$PW2_OPENWRT_TARGET" ]; then

            PW2_TMP_TARGET="$(
                printf '%s' "$PW2_BOARD_JSON" |
                jsonfilter -e '@.release.target' 2>/dev/null
            )"


            if [ -n "$PW2_TMP_TARGET" ]; then
                PW2_OPENWRT_TARGET="$PW2_TMP_TARGET"
            fi

        fi


        if [ "$PW2_OPENWRT_VERSION" = "unknown" ] ||
           [ -z "$PW2_OPENWRT_VERSION" ]; then

            PW2_TMP_VERSION="$(
                printf '%s' "$PW2_BOARD_JSON" |
                jsonfilter -e '@.release.version' 2>/dev/null
            )"


            if [ -n "$PW2_TMP_VERSION" ]; then
                PW2_OPENWRT_VERSION="$PW2_TMP_VERSION"
            fi

        fi

    fi


    # ========================================================
    # 清理字符
    # ========================================================

    PW2_OPENWRT_TARGET="$(
        printf '%s' "$PW2_OPENWRT_TARGET" |
        tr -d '\r\n\t '
    )"


    PW2_OPENWRT_VERSION="$(
        printf '%s' "$PW2_OPENWRT_VERSION" |
        tr -d '\r\n\t '
    )"


    PW2_MODEL="$(
        printf '%s' "$PW2_MODEL" |
        tr -d '\r\n'
    )"


    # ========================================================
    # 检测 32 / 64 位
    # ========================================================

    case "$PW2_ARCH" in

        x86_64|aarch64|arm64|mips64|mips64el|mips64*)

            PW2_BITS="64"

            ;;


        armv5*|armv6*|armv7*|armhf|mips|mipsel|mips32*)

            PW2_BITS="32"

            ;;


        *)

            PW2_LONG_BIT="$(getconf LONG_BIT 2>/dev/null)"


            case "$PW2_LONG_BIT" in

                64)
                    PW2_BITS="64"
                    ;;

                32)
                    PW2_BITS="32"
                    ;;

                *)
                    PW2_BITS="unknown"
                    ;;

            esac

            ;;

    esac


    # ========================================================
    # 小写
    # ========================================================

    PW2_TARGET_LOWER="$(
        printf '%s' "$PW2_OPENWRT_TARGET" |
        tr '[:upper:]' '[:lower:]' |
        tr -d '\r\n\t '
    )"


    PW2_MODEL_LOWER="$(
        printf '%s' "$PW2_MODEL" |
        tr '[:upper:]' '[:lower:]' |
        tr -d '\r\n'
    )"


    PW2_TARGET_FAMILY="$(
        printf '%s' "$PW2_TARGET_LOWER" |
        cut -d '/' -f 1
    )"


    # ========================================================
    # 第一层：Target Family
    # ========================================================

    case "$PW2_TARGET_FAMILY" in

        ipq53xx|ipq5332|ipq5312)

            PW2_PLATFORM="IPQ53XX"

            ;;


        ipq6000)

            PW2_PLATFORM="IPQ6000"

            ;;


        ipq5018)

            PW2_PLATFORM="IPQ5018"

            ;;


        ipq4019|ipq401x)

            PW2_PLATFORM="IPQ401X"

            ;;


        sdx72)

            PW2_PLATFORM="SDX72"

            ;;

    esac


    # ========================================================
    # 第二层：完整 Target
    # ========================================================

    if [ "$PW2_PLATFORM" = "unknown" ]; then

        case "$PW2_TARGET_LOWER" in

            *ipq53xx*|*ipq5332*|*ipq5312*)

                PW2_PLATFORM="IPQ53XX"

                ;;


            *ipq6000*)

                PW2_PLATFORM="IPQ6000"

                ;;


            *ipq5018*)

                PW2_PLATFORM="IPQ5018"

                ;;


            *ipq4019*|*ipq401x*)

                PW2_PLATFORM="IPQ401X"

                ;;


            *mt7981*|*mt7986*|*mt7987*|*mt7988*|*mt798x*)

                PW2_PLATFORM="MT798X"

                ;;


            *sdx72*)

                PW2_PLATFORM="SDX72"

                ;;

        esac

    fi


    # ========================================================
    # 第三层：Model / SoC
    # ========================================================

    if [ "$PW2_PLATFORM" = "unknown" ]; then

        case "$PW2_MODEL_LOWER" in

            *ipq53xx*|*ipq5312*|*ipq5332*)

                PW2_PLATFORM="IPQ53XX"

                ;;


            *ipq6000*)

                PW2_PLATFORM="IPQ6000"

                ;;


            *ipq5018*)

                PW2_PLATFORM="IPQ5018"

                ;;


            *ipq4019*|*ipq401x*)

                PW2_PLATFORM="IPQ401X"

                ;;


            *mt7981*|*mt7986*|*mt7987*|*mt7988*|*mt798x*)

                PW2_PLATFORM="MT798X"

                ;;


            *sdx72*)

                PW2_PLATFORM="SDX72"

                ;;

        esac

    fi


    # ========================================================
    # 第四层：GL.iNet 型号
    # ========================================================

    if [ "$PW2_PLATFORM" = "unknown" ]; then

        case "$PW2_MODEL_LOWER" in

            *be3600*|*be6500*|*be9300*)

                PW2_PLATFORM="IPQ53XX"

                ;;


            *ax1800*|*axt1800*)

                PW2_PLATFORM="IPQ6000"

                ;;


            *b3000*)

                PW2_PLATFORM="IPQ5018"

                ;;


            *b1300*)

                PW2_PLATFORM="IPQ401X"

                ;;


            *mt2500*|*mt3000*|*mt5000*|*mt6000*|*mt3600*)

                PW2_PLATFORM="MT798X"

                ;;


            *e5800*|*mudi7*)

                PW2_PLATFORM="SDX72"

                ;;

        esac

    fi


    # ========================================================
    # IPQ53XX 强制兜底
    # ========================================================

    if [ "$PW2_PLATFORM" = "unknown" ]; then

        if printf '%s\n%s\n' \
            "$PW2_OPENWRT_TARGET" \
            "$PW2_MODEL" |
            grep -Eqi \
            'ipq53xx|ipq5332|ipq5312|be3600|be6500|be9300'
        then

            PW2_PLATFORM="IPQ53XX"

        fi

    fi


    # ========================================================
    # MT798X 强制兜底
    # ========================================================

    if [ "$PW2_PLATFORM" = "unknown" ]; then

        if printf '%s\n%s\n' \
            "$PW2_OPENWRT_TARGET" \
            "$PW2_MODEL" |
            grep -Eqi \
            'mt7981|mt7986|mt7987|mt7988|mt2500|mt3000|mt5000|mt6000|mt3600'
        then

            PW2_PLATFORM="MT798X"

        fi

    fi


    # ========================================================
    # 显示检测结果
    # ========================================================

    printf "\n"
    printf "======================================\n"
    printf "          设备检测结果\n"
    printf "======================================\n"
    printf "机型     : %s\n" "$PW2_MODEL"
    printf "平台     : %s\n" "$PW2_PLATFORM"
    printf "OpenWrt  : %s\n" "$PW2_OPENWRT_VERSION"
    printf "Target   : %s\n" "$PW2_OPENWRT_TARGET"
    printf "Family   : %s\n" "$PW2_TARGET_FAMILY"
    printf "Kernel   : %s\n" "$PW2_KERNEL_VERSION"
    printf "架构     : %s\n" "$PW2_ARCH"
    printf "系统     : %s 位\n" "$PW2_BITS"
    printf "======================================\n"
    printf "\n"


    if [ "$PW2_PLATFORM" = "unknown" ]; then

        _pw2_error "无法识别当前设备平台"

        return 1

    fi


    if [ "$PW2_BITS" = "unknown" ]; then

        _pw2_error "无法识别当前系统位数"

        return 1

    fi


    return 0
}


# ============================================================
# 自动匹配软件源
# ============================================================

match_passwall2_feed()
{
    PW2_FEED_PATH=""
    PW2_FEED_NAME=""


    # ========================================================
    # MT798X
    # ========================================================

    if [ "$PW2_PLATFORM" = "MT798X" ] &&
       [ "$PW2_BITS" = "64" ]; then

        case "$PW2_OPENWRT_VERSION" in

            21.*)

                case "$PW2_KERNEL_VERSION" in

                    5.4.*)

                        PW2_FEED_PATH="/mt798x-openwrt21"
                        PW2_FEED_NAME="MT798X / OpenWrt 21 / Kernel 5.4 / 64位"

                        ;;

                esac

                ;;


            24.*)

                case "$PW2_KERNEL_VERSION" in

                    6.6.*)

                        PW2_FEED_PATH="/mt798x-openwrt24"
                        PW2_FEED_NAME="MT798X / OpenWrt 24 / Kernel 6.6 / 64位"

                        ;;

                esac

                ;;

        esac

    fi


    # ========================================================
    # IPQ6000
    # ========================================================

    if [ "$PW2_PLATFORM" = "IPQ6000" ]; then

        if [ "$PW2_BITS" = "64" ]; then

            case "$PW2_OPENWRT_VERSION" in

                23.*)

                    PW2_FEED_PATH="/ipq6000-tip-64bit"
                    PW2_FEED_NAME="IPQ6000 / OpenWrt 23 / 64位"

                    ;;

            esac


        elif [ "$PW2_BITS" = "32" ]; then

            PW2_FEED_PATH="/ipq6000-2023-09-不再更新"
            PW2_FEED_NAME="IPQ6000 / 32位旧系统"

            _pw2_warn "当前 IPQ6000 使用 32 位旧系统"
            _pw2_warn "该软件源已经停止更新"

        fi

    fi


    # ========================================================
    # IPQ53XX
    # ========================================================

    if [ "$PW2_PLATFORM" = "IPQ53XX" ] &&
       [ "$PW2_BITS" = "64" ]; then

        case "$PW2_OPENWRT_VERSION" in

            23.*)

                PW2_FEED_PATH="/ipq5312-qsdk12-5-64bit"
                PW2_FEED_NAME="IPQ53XX / QSDK 12.5 / OpenWrt 23 / 64位"

                ;;

        esac

    fi


    # ========================================================
    # IPQ5018
    # ========================================================

    if [ "$PW2_PLATFORM" = "IPQ5018" ] &&
       [ "$PW2_BITS" = "64" ]; then

        case "$PW2_OPENWRT_VERSION" in

            19.*)

                PW2_FEED_PATH="/b3000-qsdk12-2"
                PW2_FEED_NAME="IPQ5018 / B3000 / OpenWrt 19 / 64位"

                ;;

        esac

    fi


    # ========================================================
    # IPQ401X
    # ========================================================

    if [ "$PW2_PLATFORM" = "IPQ401X" ] &&
       [ "$PW2_BITS" = "32" ]; then

        case "$PW2_OPENWRT_VERSION" in

            21.*)

                PW2_FEED_PATH="/ipq4019"
                PW2_FEED_NAME="IPQ401X / OpenWrt 21 / 32位"

                ;;

        esac

    fi


    # ========================================================
    # SDX72
    # ========================================================

    if [ "$PW2_PLATFORM" = "SDX72" ] &&
       [ "$PW2_BITS" = "64" ]; then

        case "$PW2_OPENWRT_VERSION" in

            23.*)

                PW2_FEED_PATH="/mudi7"
                PW2_FEED_NAME="Mudi7 / SDX72 / OpenWrt 23 / 64位"

                ;;

        esac

    fi


    # ========================================================
    # 未匹配
    # ========================================================

    if [ -z "$PW2_FEED_PATH" ]; then

        _pw2_error "没有找到适用于当前设备的 PassWall2 软件源"

        printf "\n"
        printf "系统信息：\n"
        printf "--------------------------------------\n"
        printf "机型    : %s\n" "$PW2_MODEL"
        printf "平台    : %s\n" "$PW2_PLATFORM"
        printf "OpenWrt : %s\n" "$PW2_OPENWRT_VERSION"
        printf "Target  : %s\n" "$PW2_OPENWRT_TARGET"
        printf "Family  : %s\n" "$PW2_TARGET_FAMILY"
        printf "Kernel  : %s\n" "$PW2_KERNEL_VERSION"
        printf "架构    : %s\n" "$PW2_ARCH"
        printf "位数    : %s\n" "$PW2_BITS"
        printf "--------------------------------------\n"
        printf "\n"

        _pw2_warn "为避免安装错误架构的软件包，已取消安装。"

        return 1

    fi


    _pw2_ok "已自动匹配软件源"
    _pw2_info "$PW2_FEED_NAME"

    printf "\n"

    return 0
}


# ============================================================
# 备份原始软件源
# ============================================================

backup_passwall2_feeds()
{
    _pw2_info "正在备份原始软件源..."

    rm -rf "$PW2_BACKUP_DIR"


    mkdir -p "$PW2_BACKUP_DIR" || {

        _pw2_error "无法创建备份目录"

        return 1

    }


    # ========================================================
    # distfeeds
    # ========================================================

    if [ -f "$PW2_DISTFEEDS" ]; then

        cp "$PW2_DISTFEEDS" \
            "$PW2_BACKUP_DIR/distfeeds.conf" || {

            _pw2_error "备份 distfeeds.conf 失败"

            return 1

        }

    else

        touch "$PW2_BACKUP_DIR/distfeeds.notexist"

    fi


    # ========================================================
    # customfeeds
    # ========================================================

    if [ -f "$PW2_CUSTOMFEEDS" ]; then

        cp "$PW2_CUSTOMFEEDS" \
            "$PW2_BACKUP_DIR/customfeeds.conf" || {

            _pw2_error "备份 customfeeds.conf 失败"

            return 1

        }

    else

        touch "$PW2_BACKUP_DIR/customfeeds.notexist"

    fi


    _pw2_ok "原始软件源备份完成"

    return 0
}


# ============================================================
# 添加临时软件源
# ============================================================

add_passwall2_temp_feeds()
{
    _pw2_info "正在添加 PassWall2 临时软件源..."


    mkdir -p /etc/opkg || {

        _pw2_error "无法创建 /etc/opkg"

        return 1

    }


    if [ ! -f "$PW2_CUSTOMFEEDS" ]; then

        touch "$PW2_CUSTOMFEEDS" || {

            _pw2_error "无法创建 customfeeds.conf"

            return 1

        }

    fi


    # ========================================================
    # 删除旧 Open-Pro PassWall2 源
    # ========================================================

    sed -i \
        '/^src\/gz openpro_pw2_/d' \
        "$PW2_CUSTOMFEEDS"


    # ========================================================
    # 写入临时源
    # ========================================================

    printf '\n' >> "$PW2_CUSTOMFEEDS"


    printf 'src/gz openpro_pw2_packages %s%s/packages\n' \
        "$PW2_BASE" \
        "$PW2_FEED_PATH" \
        >> "$PW2_CUSTOMFEEDS"


    printf 'src/gz openpro_pw2_luci %s%s/luci\n' \
        "$PW2_BASE" \
        "$PW2_FEED_PATH" \
        >> "$PW2_CUSTOMFEEDS"


    printf 'src/gz openpro_pw2_base %s%s/base\n' \
        "$PW2_BASE" \
        "$PW2_FEED_PATH" \
        >> "$PW2_CUSTOMFEEDS"


    _pw2_ok "临时软件源添加完成"

    return 0
}


# ============================================================
# 恢复原始软件源
# ============================================================

restore_passwall2_feeds()
{
    if [ ! -d "$PW2_BACKUP_DIR" ]; then
        return 0
    fi


    _pw2_info "正在恢复原始软件源..."


    # ========================================================
    # distfeeds
    # ========================================================

    if [ -f "$PW2_BACKUP_DIR/distfeeds.conf" ]; then

        cp "$PW2_BACKUP_DIR/distfeeds.conf" \
            "$PW2_DISTFEEDS"

    elif [ -f "$PW2_BACKUP_DIR/distfeeds.notexist" ]; then

        rm -f "$PW2_DISTFEEDS"

    fi


    # ========================================================
    # customfeeds
    # ========================================================

    if [ -f "$PW2_BACKUP_DIR/customfeeds.conf" ]; then

        cp "$PW2_BACKUP_DIR/customfeeds.conf" \
            "$PW2_CUSTOMFEEDS"

    elif [ -f "$PW2_BACKUP_DIR/customfeeds.notexist" ]; then

        rm -f "$PW2_CUSTOMFEEDS"

    fi


    rm -rf "$PW2_BACKUP_DIR"


    _pw2_ok "原始软件源已恢复"

    return 0
}


# ============================================================
# 清理临时软件列表
# ============================================================

clean_passwall2_lists()
{
    rm -f /var/opkg-lists/openpro_pw2_packages 2>/dev/null
    rm -f /var/opkg-lists/openpro_pw2_luci 2>/dev/null
    rm -f /var/opkg-lists/openpro_pw2_base 2>/dev/null

    return 0
}


# ============================================================
# 清理日志
# ============================================================

clean_passwall2_logs()
{
    rm -f "$PW2_UPDATE_LOG" 2>/dev/null
    rm -f "$PW2_INSTALL_LOG" 2>/dev/null
    rm -f "$PW2_EXTRA_LOG" 2>/dev/null

    return 0
}


# ============================================================
# 检测软件包是否存在
# ============================================================

pw2_package_exists()
{
    PACKAGE="$1"

    opkg list "$PACKAGE" 2>/dev/null |
        awk -v p="$PACKAGE" \
        '$1 == p { found=1 } END { exit !found }'
}


# ============================================================
# 检测软件包是否安装
# ============================================================

pw2_package_installed()
{
    PACKAGE="$1"

    opkg status "$PACKAGE" 2>/dev/null |
        grep -q 'Status:.*installed'
}


# ============================================================
# 检测 PassWall2
# ============================================================

check_passwall2()
{
    pw2_package_installed "luci-app-passwall2"
}


# ============================================================
# 安装单个可选软件包
# ============================================================

pw2_install_optional()
{
    PACKAGE="$1"
    DISPLAY_NAME="${2:-$PACKAGE}"


    # 已安装
    if pw2_package_installed "$PACKAGE"; then

        _pw2_ok "$DISPLAY_NAME 已安装"

        return 0

    fi


    # 不存在
    if ! pw2_package_exists "$PACKAGE"; then

        _pw2_warn "$DISPLAY_NAME 不存在，已跳过"

        return 0

    fi


    _pw2_info "发现组件：$PACKAGE"


    rm -f "$PW2_EXTRA_LOG"


    if opkg install "$PACKAGE" \
        >"$PW2_EXTRA_LOG" 2>&1
    then

        if pw2_package_installed "$PACKAGE"; then

            _pw2_ok "$PACKAGE 安装完成"

        else

            _pw2_warn "$PACKAGE 安装结果无法确认"

        fi

    else

        _pw2_warn "$PACKAGE 安装失败，已跳过"

    fi


    rm -f "$PW2_EXTRA_LOG"

    return 0
}


# ============================================================
# PassWall2 自动扫描扩展组件
#
# 自动识别：
#
# luci-i18n-passwall2-zh-cn
#
# shadowsocks-libev-*
# shadowsocksr-libev-*
# shadowsocks-rust
# shadowsocks-rust-*
#
# xray-core
# xray-plugin
#
# v2ray-plugin
#
# sing-box
#
# trojan
# trojan-go
#
# chinadns-ng
#
# hysteria
# hysteria2
#
# tuic-client
# tuic-server
#
# naiveproxy
#
# tcping
# dns2socks
#
# 软件源未来出现新的 shadowsocks-rust-* /
# shadowsocks-libev-* / shadowsocksr-libev-*
# 也会自动识别。
# ============================================================

install_passwall2_extras()
{
    printf "\n"

    _pw2_info "正在检测 PassWall2 中文包及扩展组件..."


    # ========================================================
    # 中文包
    # ========================================================

    pw2_install_optional \
        "luci-i18n-passwall2-zh-cn" \
        "PassWall2 中文语言包"


    # ========================================================
    # 自动获取扩展组件
    # ========================================================

    PW2_COMPONENTS="$(
        opkg list 2>/dev/null |
        awk '{print $1}' |
        grep -E \
        '^(shadowsocks-libev($|-)|shadowsocksr-libev($|-)|shadowsocks-rust($|-)|xray-core$|xray-plugin$|v2ray-plugin$|sing-box$|trojan$|trojan-go$|chinadns-ng$|hysteria$|hysteria2$|tuic-client$|tuic-server$|naiveproxy$|tcping$|dns2socks$)' |
        sort -u
    )"


    # ========================================================
    # 没有找到
    # ========================================================

    if [ -z "$PW2_COMPONENTS" ]; then

        _pw2_warn "当前软件源中没有发现额外 PassWall2 组件"

        printf "\n"

        return 0

    fi


    # ========================================================
    # 自动安装
    # ========================================================

    for PACKAGE in $PW2_COMPONENTS
    do

        # ====================================================
        # 已安装
        # ====================================================

        if pw2_package_installed "$PACKAGE"; then

            _pw2_ok "$PACKAGE 已安装"

            continue

        fi


        # ====================================================
        # 安装
        # ====================================================

        _pw2_info "发现组件：$PACKAGE"


        rm -f "$PW2_EXTRA_LOG"


        if opkg install "$PACKAGE" \
            >"$PW2_EXTRA_LOG" 2>&1
        then

            if pw2_package_installed "$PACKAGE"; then

                _pw2_ok "$PACKAGE 安装完成"

            else

                _pw2_warn "$PACKAGE 安装结果无法确认"

            fi

        else

            _pw2_warn "$PACKAGE 安装失败，已跳过"

        fi


        rm -f "$PW2_EXTRA_LOG"

    done


    printf "\n"

    _pw2_ok "PassWall2 扩展组件检测完成"

    return 0
}


# ============================================================
# 安全清理
# ============================================================

cleanup_passwall2()
{
    restore_passwall2_feeds
    clean_passwall2_lists
    clean_passwall2_logs
}


# ============================================================
# 中断处理
# ============================================================

interrupt_passwall2()
{
    printf "\n"

    _pw2_warn "安装被中断"


    if [ -n "$PW2_PROGRESS_PID" ]; then

        kill "$PW2_PROGRESS_PID" 2>/dev/null

        wait "$PW2_PROGRESS_PID" 2>/dev/null

    fi


    cleanup_passwall2

    trap - EXIT INT TERM

    exit 130
}


# ============================================================
# 主安装函数
#
# install.sh 调用：
#
# install_passwall2
#
# 不要删除这个函数
# ============================================================

install_passwall2()
{
    printf "\n"
    printf "======================================\n"
    printf "         PassWall2 Installer\n"
    printf "======================================\n"
    printf "\n"


    # ========================================================
    # ROOT
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _pw2_error "请使用 root 用户运行"

        return 1

    fi


    # ========================================================
    # 包管理器
    # ========================================================

    if command -v opkg >/dev/null 2>&1; then

        PW2_PKG_MANAGER="opkg"

    elif command -v apk >/dev/null 2>&1; then

        _pw2_error "检测到 APK 包管理器"
        _pw2_warn "当前 PassWall2 软件源为 OPKG 软件源"
        _pw2_warn "为避免软件包格式不兼容，已取消安装"

        return 1

    else

        _pw2_error "未检测到 OPKG 包管理器"

        return 1

    fi


    _pw2_info "Package Manager : $PW2_PKG_MANAGER"

    printf "\n"


    # ========================================================
    # 检测系统
    # ========================================================

    if ! detect_passwall2_system; then

        return 2

    fi


    # ========================================================
    # 匹配软件源
    # ========================================================

    if ! match_passwall2_feed; then

        return 2

    fi


    # ========================================================
    # 备份原始软件源
    # ========================================================

    if ! backup_passwall2_feeds; then

        _pw2_error "软件源备份失败"

        return 1

    fi


    # ========================================================
    # 安全恢复
    # ========================================================

    trap 'cleanup_passwall2' EXIT
    trap 'interrupt_passwall2' INT TERM


    # ========================================================
    # 添加临时源
    # ========================================================

    if ! add_passwall2_temp_feeds; then

        _pw2_error "添加 PassWall2 临时软件源失败"

        cleanup_passwall2

        trap - EXIT INT TERM

        return 1

    fi


    clean_passwall2_lists


    # ========================================================
    # 更新软件列表
    # ========================================================

    printf "\n"

    _pw2_info "正在更新软件列表..."

    rm -f "$PW2_UPDATE_LOG"


    if ! opkg update >"$PW2_UPDATE_LOG" 2>&1; then

        printf "\n"

        _pw2_error "软件源更新失败"


        if [ -s "$PW2_UPDATE_LOG" ]; then

            printf "\n"
            printf "========== OPKG UPDATE ERROR ==========\n"
            cat "$PW2_UPDATE_LOG"
            printf "=======================================\n"

        fi


        cleanup_passwall2

        trap - EXIT INT TERM

        return 1

    fi


    rm -f "$PW2_UPDATE_LOG"

    _pw2_ok "软件列表更新完成"

    printf "\n"


    # ========================================================
    # 检查主程序是否已安装
    # ========================================================

    if check_passwall2; then

        _pw2_ok "PassWall2 主程序已经安装"

    else

        # ====================================================
        # 查询 PassWall2
        # ====================================================

        _pw2_info "正在查询 luci-app-passwall2..."


        if ! pw2_package_exists "luci-app-passwall2"; then

            _pw2_error "当前软件源中没有找到 luci-app-passwall2"

            printf "\n"

            _pw2_warn "设备识别和软件源匹配已经完成"
            _pw2_warn "但当前软件源中不存在 PassWall2"

            cleanup_passwall2

            trap - EXIT INT TERM

            return 2

        fi


        _pw2_ok "已找到 luci-app-passwall2"


        # ====================================================
        # 获取版本
        # ====================================================

        PW2_VERSION="$(
            opkg list luci-app-passwall2 2>/dev/null |
            awk -F ' - ' 'NR==1 {print $2}'
        )"


        if [ -n "$PW2_VERSION" ]; then

            _pw2_info "PassWall2 Version : $PW2_VERSION"

        fi


        # ====================================================
        # 开始安装
        # ====================================================

        printf "\n"

        _pw2_info "开始安装 PassWall2..."

        printf "\n"


        if ! pw2_install_with_progress \
            "luci-app-passwall2" \
            "$PW2_INSTALL_LOG"
        then

            printf "\n"

            _pw2_error "PassWall2 安装失败"


            if [ -s "$PW2_INSTALL_LOG" ]; then

                printf "\n"
                printf "========== OPKG INSTALL ERROR =========\n"
                cat "$PW2_INSTALL_LOG"
                printf "=======================================\n"

            fi


            cleanup_passwall2

            trap - EXIT INT TERM

            return 1

        fi


        rm -f "$PW2_INSTALL_LOG"

        printf "\n"


        # ====================================================
        # 验证安装
        # ====================================================

        _pw2_info "正在检查安装结果..."


        if ! check_passwall2; then

            _pw2_error "未检测到 luci-app-passwall2"
            _pw2_error "PassWall2 安装可能失败"

            cleanup_passwall2

            trap - EXIT INT TERM

            return 1

        fi


        _pw2_ok "PassWall2 安装成功"

    fi


    # ========================================================
    # 自动安装中文包 + 全部扩展组件
    # ========================================================

    install_passwall2_extras


    # ========================================================
    # 启用 PassWall2
    # ========================================================

    if [ -x /etc/init.d/passwall2 ]; then

        printf "\n"

        _pw2_info "正在启用 PassWall2 服务..."


        /etc/init.d/passwall2 enable \
            >/dev/null 2>&1


        _pw2_ok "PassWall2 服务已设置为开机启动"

    fi


    # ========================================================
    # 恢复原始软件源
    # ========================================================

    printf "\n"

    cleanup_passwall2

    trap - EXIT INT TERM


    # ========================================================
    # 完成
    # ========================================================

    printf "\n"
    printf "======================================\n"
    printf "         PassWall2 Installed\n"
    printf "======================================\n"
    printf "\n"

    _pw2_ok "PassWall2 安装完成"
    _pw2_ok "中文语言包检测完成"
    _pw2_ok "代理核心及扩展组件检测完成"
    _pw2_ok "临时软件源已经删除"
    _pw2_ok "临时软件列表已经清理"
    _pw2_ok "路由器原始软件源已经恢复"

    printf "\n"
    printf "请进入 LuCI 后台查看：\n"
    printf "服务 → PassWall2\n"
    printf "\n"

    return 0
}

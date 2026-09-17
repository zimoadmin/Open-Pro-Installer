#!/bin/sh

# ============================================================
# Open-Pro-Installer
# SSR Plus+ Auto Installer
# Verbose Installation Edition
#
# 功能：
# 1. 自动识别设备平台
# 2. 自动匹配软件源
# 3. 自动备份原始软件源
# 4. 临时添加 SSR Plus+ 软件源
# 5. 静默更新软件列表
# 6. 从 fw876/helloworld 最新 Release 获取主程序，实时输出安装
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
SSR_DOWNLOAD_DIR=""
SSR_LOCAL_IPK=""


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

# 实时显示输出，同时保留日志和原始退出码。
ssr_run_logged()
{
    SSR_RUN_LOG="$1"
    shift
    SSR_RUN_DIR="$(mktemp -d /tmp/openpro_ssr_log.XXXXXX)" || return 1
    mkfifo "$SSR_RUN_DIR/output" || { rmdir "$SSR_RUN_DIR"; return 1; }
    "$@" >"$SSR_RUN_DIR/output" 2>&1 &
    PROGRESS_PID=$!
    tee "$SSR_RUN_LOG" <"$SSR_RUN_DIR/output"
    wait "$PROGRESS_PID"
    SSR_RUN_RC=$?
    PROGRESS_PID=""
    rm -f "$SSR_RUN_DIR/output"
    rmdir "$SSR_RUN_DIR"
    SSR_RUN_DIR=""
    return "$SSR_RUN_RC"
}

install_ssr_package()
{
    _ssr_info "安装 GitHub 主程序：$1"
    ssr_run_logged "$2" opkg install "$1"
}

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


    _ssr_ok "已自动匹配软件源"
    _ssr_info "$FEED_NAME"

    # printf "\n"

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
    rm -f "$UPDATE_LOG" 2>/dev/null
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


    OPTIONAL_LOG="/tmp/openpro_optional_$$.log"

    rm -f "$OPTIONAL_LOG"


    if ssr_run_logged "$OPTIONAL_LOG" opkg install "$OPTIONAL_PKG"
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
    for SSR_ROUTE_PID in $SSR_ROUTE_PIDS; do kill "$SSR_ROUTE_PID" 2>/dev/null || :; done
    for SSR_ROUTE_PID in $SSR_ROUTE_PIDS; do wait "$SSR_ROUTE_PID" 2>/dev/null || :; done
    SSR_ROUTE_PIDS=""
    if [ -n "$SSR_RUN_DIR" ]; then
        rm -f "$SSR_RUN_DIR/output"
        rmdir "$SSR_RUN_DIR" 2>/dev/null || :
        SSR_RUN_DIR=""
    fi
    restore_feeds

    clean_openpro_lists
    clean_ssr_logs
    if [ -n "$SSR_DOWNLOAD_DIR" ]; then
        rm -f "$SSR_DOWNLOAD_DIR/release.json" "$SSR_LOCAL_IPK"
        rm -f "$SSR_DOWNLOAD_DIR"/sample_* "$SSR_DOWNLOAD_DIR"/route_* "$SSR_DOWNLOAD_DIR/ranked"
        rmdir "$SSR_DOWNLOAD_DIR" 2>/dev/null || :
        SSR_DOWNLOAD_DIR=""
        SSR_LOCAL_IPK=""
    fi
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

# 与 OpenClash 相同的代理线路、6 秒并发测速和 10 MB 综合评分。
SSR_DOWNLOAD_NODES="
GH01|https://ghproxy.net/
GH02|https://gh-proxy.org/
GH03|https://gh-proxy.com/
GH04|https://cdn.akaere.online/
GH05|https://github.mxw.qzz.io/
GH06|https://gh.07150721.xyz/
DIRECT|
"
SSR_ROUTE_PIDS=""

ssr_test_route()
(
    SSR_NODE="$1"
    SSR_PREFIX="$2"
    SSR_SAMPLE="$SSR_DOWNLOAD_DIR/sample_$SSR_NODE"
    SSR_METRICS="$(curl -4 -fLsS --connect-timeout 4 --max-time 6 \
        -o "$SSR_SAMPLE" -w '%{http_code}|%{time_starttransfer}|%{speed_download}|%{size_download}' \
        "$SSR_PREFIX$SSR_ASSET_URL" 2>/dev/null)"
    SSR_TEST_RC=$?
    case "$SSR_TEST_RC" in 0|28) ;; *) rm -f "$SSR_SAMPLE"; exit 1;; esac
    if head -c 1024 "$SSR_SAMPLE" 2>/dev/null | grep -Eqi '<html|<!doctype|bad gateway|access denied'; then
        rm -f "$SSR_SAMPLE"
        exit 1
    fi
    printf '%s\n' "$SSR_METRICS" | awk -F '|' -v node="$SSR_NODE" -v prefix="$SSR_PREFIX" '
        ($1 == 200 || $1 == 206) && $2 ~ /^[0-9.]+$/ && $3 > 0 && $4 >= 4096 {
            printf "%.0f|%s|%s\n", $2 * 1000 + 10485760 / $3 * 1000, node, prefix
        }' > "$SSR_DOWNLOAD_DIR/route_$SSR_NODE"
    rm -f "$SSR_SAMPLE"
)

ssr_download_fastest()
{
    _ssr_info "并发测速 GH01–GH06 和 DIRECT，单条最多 6 秒..."
    SSR_ROUTE_PIDS=""
    for SSR_NODE in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT; do
        SSR_PREFIX="$(printf '%s\n' "$SSR_DOWNLOAD_NODES" | awk -F '|' -v n="$SSR_NODE" '$1==n {print $2;exit}')"
        ssr_test_route "$SSR_NODE" "$SSR_PREFIX" &
        SSR_ROUTE_PIDS="$SSR_ROUTE_PIDS $!"
    done
    for SSR_ROUTE_PID in $SSR_ROUTE_PIDS; do wait "$SSR_ROUTE_PID" || :; done
    SSR_ROUTE_PIDS=""
    cat "$SSR_DOWNLOAD_DIR"/route_* 2>/dev/null | sort -t '|' -k1,1n > "$SSR_DOWNLOAD_DIR/ranked"
    # 测速暂时不可用的线路仍放在最后尝试，不丢失可恢复的下载机会。
    for SSR_NODE in GH01 GH02 GH03 GH04 GH05 GH06 DIRECT; do
        if ! awk -F '|' -v n="$SSR_NODE" '$2==n {found=1} END {exit !found}' "$SSR_DOWNLOAD_DIR/ranked"; then
            SSR_PREFIX="$(printf '%s\n' "$SSR_DOWNLOAD_NODES" | awk -F '|' -v n="$SSR_NODE" '$1==n {print $2;exit}')"
            printf '999999999|%s|%s\n' "$SSR_NODE" "$SSR_PREFIX" >> "$SSR_DOWNLOAD_DIR/ranked"
        fi
    done
    _ssr_info "测速排名（综合预计耗时，越小越快）："
    awk -F '|' '{if ($1 == 999999999) printf "%s：测速未通过，作为备用\n", $2; else printf "%s：%s ms\n", $2, $1}' "$SSR_DOWNLOAD_DIR/ranked"
    while IFS='|' read -r SSR_SCORE SSR_NODE SSR_PREFIX; do
        _ssr_info "正在使用 $SSR_NODE 下载：$SSR_ASSET_NAME"
        if curl -4 -fLsS --connect-timeout 8 --max-time 120 \
            "$SSR_PREFIX$SSR_ASSET_URL" -o "$SSR_LOCAL_IPK" 2>>"$INSTALL_LOG" && [ -s "$SSR_LOCAL_IPK" ]; then
            SSR_ACTUAL_DIGEST="$(sha256sum "$SSR_LOCAL_IPK" | awk '{print $1}')"
            if [ "sha256:$SSR_ACTUAL_DIGEST" = "$SSR_ASSET_DIGEST" ]; then
                _ssr_ok "$SSR_NODE 下载完成，SHA256 校验通过"
                SSR_SELECTED_ROUTE="$SSR_NODE"
                return 0
            fi
        fi
        _ssr_warn "$SSR_NODE 下载或 SHA256 校验失败，尝试下一条"
        rm -f "$SSR_LOCAL_IPK"
    done < "$SSR_DOWNLOAD_DIR/ranked"
    _ssr_error "SSR Plus+ 所有 GitHub 下载线路均失败"
    return 1
}



ssr_fetch_latest()
{
    _ssr_info "获取 fw876/helloworld 最新 Release..."
    command -v curl >/dev/null 2>&1 && command -v jsonfilter >/dev/null 2>&1 &&
        command -v sha256sum >/dev/null 2>&1 || {
        _ssr_error "获取上游安装包需要 curl、jsonfilter 和 sha256sum"
        return 1
    }
    SSR_DOWNLOAD_DIR="$(mktemp -d /tmp/openpro_ssr_release.XXXXXX)" || return 1
    SSR_RELEASE_JSON="$SSR_DOWNLOAD_DIR/release.json"
    curl -fLsS --connect-timeout 15 --max-time 90 --retry 2 \
        https://api.github.com/repos/fw876/helloworld/releases/latest \
        -o "$SSR_RELEASE_JSON" || { _ssr_error "获取 SSR Plus+ 最新 Release 失败"; return 1; }
    SSR_RELEASE_TAG="$(jsonfilter -i "$SSR_RELEASE_JSON" -e '@.tag_name' 2>/dev/null)"
    SSR_ASSET_URL="$(jsonfilter -i "$SSR_RELEASE_JSON" -e '@.assets[*].browser_download_url' 2>/dev/null |
        grep -E '^https://github.com/fw876/helloworld/releases/download/[^/]+/luci-app-ssr-plus_[^/]+_all\.ipk$')"
    [ -n "$SSR_RELEASE_TAG" ] && [ -n "$SSR_ASSET_URL" ] &&
        [ "$(printf '%s\n' "$SSR_ASSET_URL" | wc -l)" -eq 1 ] || {
        _ssr_error "最新 Release 中没有唯一可用的 SSR Plus+ IPK 包"
        return 1
    }
    SSR_ASSET_NAME="${SSR_ASSET_URL##*/}"
    SSR_EXPECTED_VERSION="${SSR_ASSET_NAME#luci-app-ssr-plus_}"
    SSR_EXPECTED_VERSION="${SSR_EXPECTED_VERSION%_all.ipk}"
    SSR_ASSET_DIGEST="$(jsonfilter -i "$SSR_RELEASE_JSON" -e "@.assets[@.name=\"$SSR_ASSET_NAME\"].digest" 2>/dev/null)"
    SSR_LOCAL_IPK="$SSR_DOWNLOAD_DIR/$SSR_ASSET_NAME"
    _ssr_info "上游版本：$SSR_RELEASE_TAG；安装包：$SSR_ASSET_NAME"
    printf '%s\n' "$SSR_ASSET_DIGEST" | grep -Eq '^sha256:[0-9a-f]{64}$' || {
        _ssr_error "上游未提供有效的 SHA256"
        return 1
    }
    ssr_download_fastest || return 1
}

install_ssrplus()
{


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

    if ! detect_system; then

        return 2

    fi


    # ========================================================
    # 匹配软件源
    # ========================================================

    if ! match_feed; then

        return 2

    fi


    # 已安装时也检查上游最新版本。

    # ========================================================
    # 备份
    # ========================================================

    if ! backup_feeds; then

        _ssr_error "软件源备份失败"

        return 1

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

    _ssr_info "正在更新软件列表..."

    rm -f "$UPDATE_LOG"


    if ! ssr_run_logged "$UPDATE_LOG" opkg update; then
        printf "\n"
        _ssr_warn "部分依赖源更新失败；继续获取 GitHub 主程序，并检查可用依赖"
        tail -n 12 "$UPDATE_LOG"
        # 不继续使用这次失败的临时源索引，也不关闭签名验证。
        restore_feeds
        clean_openpro_lists
    fi


    _ssr_ok "软件列表更新完成"

    # printf "\n"


    # ========================================================
    # 每次获取上游最新主程序；依赖沿用当前适配软件源。
    # ========================================================

    if ! ssr_fetch_latest; then
        cleanup_ssrplus
        trap - EXIT INT TERM
        return 1
    fi

    _ssr_info "检查安装包架构和依赖（预演，不执行安装）"
    if ! ssr_run_logged "$INSTALL_LOG" opkg --noaction install "$SSR_LOCAL_IPK"; then
        printf "\n"
        _ssr_error "SSR Plus+ 依赖预检失败，尚未执行安装"
        cat "$INSTALL_LOG"
        if [ -s "$UPDATE_LOG" ]; then
            printf '\n========== 软件源更新记录 ==========\n'
            tail -n 25 "$UPDATE_LOG"
        fi
        cleanup_ssrplus
        trap - EXIT INT TERM
        return 1
    fi

        # ====================================================
        # 实时安装
        # ====================================================

        # printf "\n"

    _ssr_info "开始安装 SSR Plus+..."

        # printf "\n"


        if ! install_ssr_package \
            "$SSR_LOCAL_IPK" \
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


        SSR_INSTALLED_VERSION="$(opkg status luci-app-ssr-plus 2>/dev/null | sed -n 's/^Version: *//p' | head -n 1)"
        if [ "$SSR_INSTALLED_VERSION" != "$SSR_EXPECTED_VERSION" ]; then
            _ssr_error "版本验证失败：期望 $SSR_EXPECTED_VERSION，实际 $SSR_INSTALLED_VERSION"
            cleanup_ssrplus
            trap - EXIT INT TERM
            return 1
        fi
        _ssr_ok "SSR Plus+ $SSR_RELEASE_TAG 主程序安装成功"



    # ========================================================
    # 自动检查扩展组件
    #
    # 必须放在 cleanup_ssrplus 前面
    # 因为这里还需要使用临时软件源
    # ========================================================

    install_optional_ssr_packages


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

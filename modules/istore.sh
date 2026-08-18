#!/bin/sh

# ============================================================
# Open-Pro-Installer
# iStore 商店安装模块
#
# 功能：
# 1. 不修改 /etc/opkg/customfeeds.conf
# 2. 不主动执行普通 opkg update
# 3. 获取 reinstall_istore.sh
# 4. curl / wget 自动选择
# 5. 隐藏大量安装输出
# 6. 单行动态进度条
# 7. 安装失败才显示详细日志
# 8. 严格通过包管理器验证 luci-app-store
# 9. 不使用 LuCI 残留文件判断安装状态
# 10. 已安装时显示真实版本
# 11. 自动刷新 LuCI
# 12. 自动清理临时文件
# 13. BusyBox / OpenWrt /bin/sh 兼容
# ============================================================


# ============================================================
# 颜色
# ============================================================

GREEN="$(printf '\033[32m')"
CYAN="$(printf '\033[36m')"
RED="$(printf '\033[31m')"
YELLOW="$(printf '\033[33m')"
RESET="$(printf '\033[0m')"


# ============================================================
# 临时文件
# ============================================================

ISTORE_SCRIPT="/tmp/reinstall_istore.sh"
ISTORE_LOG="/tmp/openpro_istore.log"

ISTORE_PID=""
ISTORE_VERSION=""


# ============================================================
# 下载地址
# ============================================================

ISTORE_SCRIPT_URL="https://gitee.com/wukongdaily/gl_onescript/raw/master/reinstall_istore.sh"


# ============================================================
# 日志
# ============================================================

_istore_info()
{
    printf "%b\n" "${GREEN}[INFO]${RESET} $*"
}


_istore_ok()
{
    printf "%b\n" "${GREEN}[OK]${RESET} $*"
}


_istore_warn()
{
    printf "%b\n" "${YELLOW}[WARN]${RESET} $*"
}


_istore_error()
{
    printf "%b\n" "${RED}[ERROR]${RESET} $*"
}


# ============================================================
# 进度条
# ============================================================

istore_progress()
{
    PERCENT="$1"
    TEXT="$2"

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


    printf "\r\033[2K${GREEN}[INFO]${RESET} %-18s [${GREEN}%s${RESET}] %3d%%" \
        "$TEXT" \
        "$BAR" \
        "$PERCENT"
}


# ============================================================
# 清理临时文件
# ============================================================

cleanup_istore()
{
    rm -f "$ISTORE_SCRIPT" 2>/dev/null
    rm -f "$ISTORE_LOG" 2>/dev/null

    ISTORE_PID=""

    return 0
}


# ============================================================
# 显示错误日志
# ============================================================

show_istore_error()
{
    printf "\n"

    printf "%b\n" \
        "${RED}========== ERROR LOG ==========${RESET}"


    if [ -s "$ISTORE_LOG" ]; then

        tail -n 80 "$ISTORE_LOG"

    else

        printf "没有可用错误日志\n"

    fi


    printf "%b\n" \
        "${RED}===============================${RESET}"

    printf "\n"
}


# ============================================================
# 严格检查 iStore 是否真正安装
#
# 重要：
#
# 不再检测：
#
# /usr/lib/lua/luci/*
# /www/luci-static/*
# /etc/config/store
#
# 因为卸载以后这些目录可能存在残留文件，
# 使用这些文件判断会造成“已经卸载但仍显示安装”的误判。
#
# 这里只相信包管理器数据库。
# ============================================================

check_istore()
{
    # ========================================================
    # OPKG
    # ========================================================

    if command -v opkg >/dev/null 2>&1; then

        ISTORE_STATUS="$(
            opkg status luci-app-store 2>/dev/null |
            sed -n 's/^Status:[[:space:]]*//p' |
            head -n 1
        )"


        case "$ISTORE_STATUS" in

            *installed*)

                return 0

                ;;

        esac


        return 1

    fi


    # ========================================================
    # APK
    # 预留给新版 OpenWrt
    # ========================================================

    if command -v apk >/dev/null 2>&1; then

        if apk info -e luci-app-store \
            >/dev/null 2>&1
        then

            return 0

        fi


        return 1

    fi


    return 1
}


# ============================================================
# 获取已安装 iStore 版本
# ============================================================

get_istore_version()
{
    ISTORE_VERSION=""


    # ========================================================
    # OPKG
    # ========================================================

    if command -v opkg >/dev/null 2>&1; then

        ISTORE_VERSION="$(
            opkg status luci-app-store 2>/dev/null |
            awk -F ': ' '
                /^Version:/ {
                    print $2
                    exit
                }
            '
        )"

    fi


    # ========================================================
    # APK
    # ========================================================

    if [ -z "$ISTORE_VERSION" ] &&
       command -v apk >/dev/null 2>&1
    then

        ISTORE_VERSION="$(
            apk info -v luci-app-store 2>/dev/null |
            sed -n '1p' |
            sed 's/^luci-app-store-//'
        )"

    fi


    [ -n "$ISTORE_VERSION" ] ||
        ISTORE_VERSION="unknown"


    return 0
}


# ============================================================
# 下载 iStore 安装脚本
# ============================================================

download_istore_script()
{
    rm -f "$ISTORE_SCRIPT"


    # ========================================================
    # 优先 curl
    # ========================================================

    if command -v curl >/dev/null 2>&1; then

        curl \
            -L \
            -f \
            -sS \
            --connect-timeout 8 \
            --max-time 60 \
            --retry 2 \
            --retry-delay 1 \
            -o "$ISTORE_SCRIPT" \
            "$ISTORE_SCRIPT_URL" \
            >>"$ISTORE_LOG" 2>&1

        RESULT=$?


    # ========================================================
    # 回退 wget
    # ========================================================

    elif command -v wget >/dev/null 2>&1; then

        wget \
            -T 20 \
            -O "$ISTORE_SCRIPT" \
            "$ISTORE_SCRIPT_URL" \
            >>"$ISTORE_LOG" 2>&1

        RESULT=$?


    else

        printf "curl / wget not found\n" \
            >>"$ISTORE_LOG"

        return 1

    fi


    # ========================================================
    # 下载命令失败
    # ========================================================

    if [ "$RESULT" -ne 0 ]; then

        rm -f "$ISTORE_SCRIPT"

        return 1

    fi


    # ========================================================
    # 文件不能为空
    # ========================================================

    if [ ! -s "$ISTORE_SCRIPT" ]; then

        printf "Downloaded script is empty\n" \
            >>"$ISTORE_LOG"

        rm -f "$ISTORE_SCRIPT"

        return 1

    fi


    # ========================================================
    # 防止下载到 HTML 错误页面
    # ========================================================

    if head -c 512 "$ISTORE_SCRIPT" 2>/dev/null |
       grep -Eqi \
       '<html|<!doctype|404 not found|bad gateway|cloudflare'
    then

        printf "Invalid HTML response\n" \
            >>"$ISTORE_LOG"

        rm -f "$ISTORE_SCRIPT"

        return 1

    fi


    # ========================================================
    # Shell 语法检查
    # ========================================================

    if ! sh -n "$ISTORE_SCRIPT" \
        >>"$ISTORE_LOG" 2>&1
    then

        printf "Invalid shell script\n" \
            >>"$ISTORE_LOG"

        rm -f "$ISTORE_SCRIPT"

        return 1

    fi


    chmod 755 "$ISTORE_SCRIPT"


    return 0
}


# ============================================================
# 安装 iStore
#
# 安装过程全部写入日志
# 终端只显示动态进度条
# ============================================================

run_istore_install()
{
    # 保留下载阶段产生的日志
    # 不在这里删除 ISTORE_LOG


    sh "$ISTORE_SCRIPT" \
        >>"$ISTORE_LOG" 2>&1 &


    ISTORE_PID=$!


    PERCENT=45


    istore_progress \
        "$PERCENT" \
        "正在安装 iStore..."


    while kill -0 "$ISTORE_PID" 2>/dev/null; do


        # ====================================================
        # 已经出现 luci-app-store
        # ====================================================

        if grep -qi \
            'luci-app-store' \
            "$ISTORE_LOG" 2>/dev/null
        then

            if [ "$PERCENT" -lt 88 ]; then

                PERCENT=$((PERCENT + 3))

            fi


        # ====================================================
        # 安装阶段
        # ====================================================

        elif grep -qi \
            'install' \
            "$ISTORE_LOG" 2>/dev/null
        then

            if [ "$PERCENT" -lt 75 ]; then

                PERCENT=$((PERCENT + 2))

            fi


        # ====================================================
        # 软件源阶段
        # ====================================================

        elif grep -qi \
            'update' \
            "$ISTORE_LOG" 2>/dev/null
        then

            if [ "$PERCENT" -lt 60 ]; then

                PERCENT=$((PERCENT + 2))

            fi


        # ====================================================
        # 等待
        # ====================================================

        else

            if [ "$PERCENT" -lt 55 ]; then

                PERCENT=$((PERCENT + 1))

            fi

        fi


        # ====================================================
        # 真正安装结束之前最多 92%
        # ====================================================

        if [ "$PERCENT" -gt 92 ]; then

            PERCENT=92

        fi


        istore_progress \
            "$PERCENT" \
            "正在安装 iStore..."


        sleep 1

    done


    # ========================================================
    # 获取真实返回值
    # ========================================================

    wait "$ISTORE_PID"

    RESULT=$?


    ISTORE_PID=""


    return "$RESULT"
}


# ============================================================
# 刷新 LuCI
# ============================================================

refresh_istore_luci()
{
    # ========================================================
    # 清理 LuCI 缓存
    # ========================================================

    rm -rf /tmp/luci-indexcache \
        >/dev/null 2>&1

    rm -rf /tmp/luci-modulecache \
        >/dev/null 2>&1

    rm -rf /tmp/luci-*cache* \
        >/dev/null 2>&1


    # ========================================================
    # rpcd
    # ========================================================

    if [ -x /etc/init.d/rpcd ]; then

        /etc/init.d/rpcd restart \
            >/dev/null 2>&1

    fi


    # ========================================================
    # uhttpd
    # ========================================================

    if [ -x /etc/init.d/uhttpd ]; then

        /etc/init.d/uhttpd restart \
            >/dev/null 2>&1

    fi


    return 0
}


# ============================================================
# Ctrl+C / 中断
# ============================================================

interrupt_istore()
{
    printf "\n"


    _istore_warn "iStore 安装已中断"


    if [ -n "$ISTORE_PID" ]; then

        kill "$ISTORE_PID" \
            >/dev/null 2>&1

        wait "$ISTORE_PID" \
            >/dev/null 2>&1

    fi


    rm -f "$ISTORE_SCRIPT" \
        >/dev/null 2>&1


    trap - INT TERM


    return 130
}


# ============================================================
# 主函数
#
# install.sh 调用：
#
# install_istore
# ============================================================

install_istore()
{
    printf "\n"

    printf "%b\n" \
        "${CYAN}╔══════════════════════════════════════╗${RESET}"

    printf "%b\n" \
        "${CYAN}║${GREEN}          iStore 商店安装             ${CYAN}║${RESET}"

    printf "%b\n" \
        "${CYAN}╚══════════════════════════════════════╝${RESET}"

    printf "\n"


    # ========================================================
    # Root 检测
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _istore_error "请使用 root 用户运行"

        return 1

    fi


    # ========================================================
    # 包管理器
    # ========================================================

    if command -v opkg >/dev/null 2>&1; then

        ISTORE_PKG_MANAGER="opkg"

    elif command -v apk >/dev/null 2>&1; then

        ISTORE_PKG_MANAGER="apk"

    else

        _istore_error "没有检测到支持的软件包管理器"

        return 1

    fi


    # ========================================================
    # 初始化
    # ========================================================

    rm -f "$ISTORE_SCRIPT"
    rm -f "$ISTORE_LOG"


    touch "$ISTORE_LOG"


    trap 'interrupt_istore' INT TERM


    # ========================================================
    # 设备信息
    # ========================================================

    MODEL="$(
        cat /tmp/sysinfo/model 2>/dev/null
    )"


    [ -n "$MODEL" ] ||
        MODEL="Unknown"


    ARCH="$(
        uname -m 2>/dev/null
    )"


    [ -n "$ARCH" ] ||
        ARCH="Unknown"


    _istore_info "设备型号: $MODEL"

    _istore_info "CPU架构: $ARCH"

    _istore_info "软件管理器: $ISTORE_PKG_MANAGER"


    printf "\n"


    # ========================================================
    # 严格检查是否已经安装
    # ========================================================

    if check_istore; then

        get_istore_version


        _istore_ok "检测到 iStore 已经安装"

        _istore_info "当前版本: $ISTORE_VERSION"


        rm -f "$ISTORE_LOG"


        trap - INT TERM


        return 0

    fi


    # ========================================================
    # 明确告诉用户当前没有安装
    # ========================================================

    _istore_info "未检测到 iStore，准备开始安装"


    printf "\n"


    # ========================================================
    # 10%
    # ========================================================

    istore_progress \
        10 \
        "正在准备环境..."


    sleep 1


    # ========================================================
    # 网络工具
    # ========================================================

    if ! command -v curl >/dev/null 2>&1 &&
       ! command -v wget >/dev/null 2>&1
    then

        printf "\n"


        _istore_error "系统缺少 curl / wget"


        trap - INT TERM


        return 1

    fi


    # ========================================================
    # 20%
    #
    # 注意：
    #
    # 不执行：
    #
    # opkg update
    #
    # 不修改：
    #
    # /etc/opkg/customfeeds.conf
    # ========================================================

    istore_progress \
        20 \
        "正在检查环境..."


    sleep 1


    # ========================================================
    # 30%
    # 下载 iStore 安装脚本
    # ========================================================

    istore_progress \
        30 \
        "正在获取 iStore..."


    if ! download_istore_script; then

        printf "\n"


        _istore_error "获取 iStore 安装组件失败"


        show_istore_error


        rm -f "$ISTORE_SCRIPT"


        trap - INT TERM


        return 1

    fi


    # ========================================================
    # 40%
    # ========================================================

    istore_progress \
        40 \
        "正在验证组件..."


    sleep 1


    # ========================================================
    # 执行安装
    # ========================================================

    run_istore_install


    INSTALL_RESULT=$?


    # ========================================================
    # 安装脚本返回错误
    # ========================================================

    if [ "$INSTALL_RESULT" -ne 0 ]; then

        printf "\n"


        _istore_error "iStore 安装程序执行失败"


        show_istore_error


        rm -f "$ISTORE_SCRIPT"


        trap - INT TERM


        return 1

    fi


    # ========================================================
    # 95%
    # 严格验证软件包
    # ========================================================

    istore_progress \
        95 \
        "正在验证安装..."


    sleep 1


    if ! check_istore; then

        printf "\n"


        _istore_error "未检测到 luci-app-store"

        _istore_error "iStore 没有正确安装"


        show_istore_error


        rm -f "$ISTORE_SCRIPT"


        trap - INT TERM


        return 1

    fi


    # ========================================================
    # 获取版本
    # ========================================================

    get_istore_version


    # ========================================================
    # 98%
    # 刷新 LuCI
    # ========================================================

    istore_progress \
        98 \
        "正在刷新 LuCI..."


    refresh_istore_luci


    # ========================================================
    # 100%
    # ========================================================

    istore_progress \
        100 \
        "iStore 安装完成"


    printf "\n\n"


    # ========================================================
    # 清理
    # ========================================================

    cleanup_istore


    trap - INT TERM


    # ========================================================
    # 完成
    # ========================================================

    _istore_ok "iStore 商店安装成功"

    _istore_info "版本: $ISTORE_VERSION"

    _istore_info "请刷新 LuCI 后台页面"

    _istore_info "进入：服务 → iStore"


    printf "\n"


    return 0
}

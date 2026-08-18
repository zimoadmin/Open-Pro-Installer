#!/bin/sh

# ============================================================
# Open-Pro-Installer
# iStore 商店安装模块
#
# 特点：
# 1. 不修改 /etc/opkg/customfeeds.conf
# 2. 不执行普通 opkg update
# 3. 获取官方推荐的 reinstall_istore.sh
# 4. curl / wget 自动选择
# 5. 隐藏大量安装输出
# 6. 单行动态进度条
# 7. 安装失败才显示日志
# 8. 安装完成后真实验证 luci-app-store
# 9. 自动刷新 LuCI
# 10. BusyBox / OpenWrt /bin/sh 兼容
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
# 清理
# ============================================================

cleanup_istore()
{
    rm -f "$ISTORE_SCRIPT" 2>/dev/null
    rm -f "$ISTORE_LOG" 2>/dev/null

    ISTORE_PID=""

    return 0
}


# ============================================================
# 错误日志
# ============================================================

show_istore_error()
{
    printf "\n"

    printf "%b\n" \
        "${RED}========== ERROR LOG ==========${RESET}"


    if [ -s "$ISTORE_LOG" ]; then

        tail -n 60 "$ISTORE_LOG"

    else

        printf "没有可用错误日志\n"

    fi


    printf "%b\n" \
        "${RED}===============================${RESET}"

    printf "\n"
}


# ============================================================
# 检查 iStore
# ============================================================

check_istore()
{
    # 软件包检测

    if opkg status luci-app-store 2>/dev/null |
       grep -q 'Status:.*installed'
    then
        return 0
    fi


    # LuCI 文件检测

    if [ -d /usr/lib/lua/luci/controller ] &&
       find /usr/lib/lua/luci \
            -iname '*store*' 2>/dev/null |
            grep -q .
    then
        return 0
    fi


    return 1
}


# ============================================================
# 下载脚本
# ============================================================

download_istore_script()
{
    rm -f "$ISTORE_SCRIPT"


    # --------------------------------------------------------
    # 优先 curl
    # --------------------------------------------------------

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


    # --------------------------------------------------------
    # 回退 wget
    # --------------------------------------------------------

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


    if [ "$RESULT" -ne 0 ]; then

        rm -f "$ISTORE_SCRIPT"

        return 1

    fi


    # --------------------------------------------------------
    # 文件不能为空
    # --------------------------------------------------------

    if [ ! -s "$ISTORE_SCRIPT" ]; then

        printf "Downloaded script is empty\n" \
            >>"$ISTORE_LOG"

        rm -f "$ISTORE_SCRIPT"

        return 1

    fi


    # --------------------------------------------------------
    # 防止下载到 HTML
    # --------------------------------------------------------

    if head -c 512 "$ISTORE_SCRIPT" 2>/dev/null |
       grep -Eqi \
       '<html|<!doctype|404 not found|bad gateway|cloudflare'
    then

        printf "Invalid HTML response\n" \
            >>"$ISTORE_LOG"

        rm -f "$ISTORE_SCRIPT"

        return 1

    fi


    # --------------------------------------------------------
    # Shell 基础验证
    # --------------------------------------------------------

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
# 安装 iStore + 动态进度
# ============================================================

run_istore_install()
{
    rm -f "$ISTORE_LOG"


    sh "$ISTORE_SCRIPT" \
        >>"$ISTORE_LOG" 2>&1 &


    ISTORE_PID=$!


    PERCENT=45


    while kill -0 "$ISTORE_PID" 2>/dev/null; do


        # ----------------------------------------------------
        # 根据日志判断大概安装阶段
        # ----------------------------------------------------

        if grep -qi \
            'luci-app-store' \
            "$ISTORE_LOG" 2>/dev/null
        then

            if [ "$PERCENT" -lt 88 ]; then
                PERCENT=$((PERCENT + 3))
            fi


        elif grep -qi \
            'install' \
            "$ISTORE_LOG" 2>/dev/null
        then

            if [ "$PERCENT" -lt 75 ]; then
                PERCENT=$((PERCENT + 2))
            fi


        elif grep -qi \
            'update' \
            "$ISTORE_LOG" 2>/dev/null
        then

            if [ "$PERCENT" -lt 60 ]; then
                PERCENT=$((PERCENT + 2))
            fi


        else

            if [ "$PERCENT" -lt 55 ]; then
                PERCENT=$((PERCENT + 1))
            fi

        fi


        # 安装真正结束前最多 92%

        if [ "$PERCENT" -gt 92 ]; then
            PERCENT=92
        fi


        istore_progress \
            "$PERCENT" \
            "正在安装 iStore..."


        sleep 1

    done


    wait "$ISTORE_PID"

    RESULT=$?


    ISTORE_PID=""


    return "$RESULT"
}


# ============================================================
# 中断
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


    rm -f "$ISTORE_SCRIPT" 2>/dev/null


    trap - INT TERM


    return 130
}


# ============================================================
# 主函数
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
    # Root
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _istore_error "请使用 root 用户运行"

        return 1

    fi


    # ========================================================
    # opkg
    # ========================================================

    if ! command -v opkg >/dev/null 2>&1; then

        _istore_error "当前系统没有检测到 opkg"

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
    # 设备
    # ========================================================

    MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"

    [ -n "$MODEL" ] ||
        MODEL="Unknown"


    ARCH="$(uname -m 2>/dev/null)"

    [ -n "$ARCH" ] ||
        ARCH="Unknown"


    _istore_info "设备型号: $MODEL"

    _istore_info "CPU架构: $ARCH"

    _istore_info "软件管理器: opkg"


    printf "\n"


    # ========================================================
    # 已安装
    # ========================================================

    if check_istore; then

        _istore_ok "检测到 iStore 已经安装"

        trap - INT TERM

        return 0

    fi


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
    # 这里故意：
    #
    # 不执行 opkg update
    # 不修改 customfeeds.conf
    # ========================================================

    istore_progress \
        20 \
        "正在检查环境..."

    sleep 1


    # ========================================================
    # 30% 下载
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
    # 安装
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
    # 95% 验证
    # ========================================================

    istore_progress \
        95 \
        "正在验证安装..."


    sleep 1


    if ! check_istore; then

        printf "\n"

        _istore_error "未检测到 luci-app-store"

        show_istore_error

        rm -f "$ISTORE_SCRIPT"

        trap - INT TERM

        return 1

    fi


    # ========================================================
    # 刷新 LuCI
    # ========================================================

    istore_progress \
        98 \
        "正在刷新 LuCI..."


    rm -rf /tmp/luci-indexcache \
        >/dev/null 2>&1

    rm -rf /tmp/luci-modulecache \
        >/dev/null 2>&1


    if [ -x /etc/init.d/rpcd ]; then

        /etc/init.d/rpcd restart \
            >/dev/null 2>&1

    fi


    if [ -x /etc/init.d/uhttpd ]; then

        /etc/init.d/uhttpd restart \
            >/dev/null 2>&1

    fi


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

    rm -f "$ISTORE_SCRIPT"
    rm -f "$ISTORE_LOG"


    trap - INT TERM


    # ========================================================
    # 完成
    # ========================================================

    _istore_ok "iStore 商店安装成功"

    _istore_info "请刷新 LuCI 后台页面"

    _istore_info "进入：服务 → iStore"


    printf "\n"


    return 0
}

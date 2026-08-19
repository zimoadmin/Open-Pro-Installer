#!/bin/sh

# ============================================================
# Open-Pro-Installer
# GL.iNet 云服务切换模块
#
# 功能：
# 1. 自动检测 gl-cloud
# 2. 自动读取当前 Server
# 3. 自动识别国内 / 海外服务器
# 4. 获取 GoodCloud 设备绑定 URL
# 5. 一键切换国内服务器
# 6. 一键切换海外服务器
# 7. 自动 uci commit
# 8. 自动重启 gl-cloud
# 9. 修改后真实验证
# 10. BusyBox / OpenWrt /bin/sh 兼容
#
# install.sh 调用：
#
# cloud_menu
#
# ============================================================


# ============================================================
# 颜色 + 粗体
# ============================================================

BOLD="$(printf '\033[1m')"

GREEN="$(printf '\033[1;32m')"
CYAN="$(printf '\033[1;36m')"
BLUE="$(printf '\033[1;34m')"
RED="$(printf '\033[1;31m')"
YELLOW="$(printf '\033[1;33m')"
WHITE="$(printf '\033[1;37m')"

RESET="$(printf '\033[0m')"


# ============================================================
# GL.iNet 云服务器
# ============================================================

CLOUD_SERVER_CN="gslb.gl-inet.cn"
CLOUD_SERVER_GLOBAL="gslb-eu.goodcloud.xyz"


# ============================================================
# 当前状态变量
# ============================================================

CLOUD_SERVER=""
CLOUD_NAME=""
CLOUD_URL=""


# ============================================================
# 返回提示
# ============================================================

_cloud_pause()
{
    printf "\n"
    printf "%b" "${GREEN}按回车返回...${RESET}"

    read CLOUD_DUMMY </dev/tty
}


# ============================================================
# 日志
# ============================================================

_cloud_info()
{
    printf "%b\n" \
        "${GREEN}[INFO]${RESET} ${BOLD}$*${RESET}"
}


_cloud_ok()
{
    printf "%b\n" \
        "${GREEN}[OK]${RESET} ${BOLD}$*${RESET}"
}


_cloud_warn()
{
    printf "%b\n" \
        "${YELLOW}[WARN] $*${RESET}"
}


_cloud_error()
{
    printf "%b\n" \
        "${RED}[ERROR] $*${RESET}"
}


# ============================================================
# 检查运行环境
# ============================================================

check_cloud_environment()
{
    # Root

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _cloud_error "请使用 root 用户运行"

        return 1

    fi


    # UCI

    if ! command -v uci >/dev/null 2>&1; then

        _cloud_error "当前系统没有检测到 uci"

        return 1

    fi


    # UBUS

    if ! command -v ubus >/dev/null 2>&1; then

        _cloud_error "当前系统没有检测到 ubus"

        return 1

    fi


    # gl-cloud

    if ! uci -q show gl-cloud >/dev/null 2>&1; then

        _cloud_error "没有检测到 GL.iNet gl-cloud"

        _cloud_warn "当前设备可能不是 GL.iNet 官方系统"

        return 1

    fi


    return 0
}


# ============================================================
# 读取当前 Server
#
# 三种方式兼容不同 GL.iNet 固件
# ============================================================

get_cloud_server()
{
    CLOUD_SERVER=""


    # ========================================================
    # 方法 1
    # ========================================================

    CLOUD_SERVER="$(
        uci -q get 'gl-cloud.@cloud[0].server' \
        2>/dev/null
    )"


    # ========================================================
    # 方法 2
    # ========================================================

    if [ -z "$CLOUD_SERVER" ]; then

        CLOUD_SERVER="$(
            uci -q show gl-cloud 2>/dev/null |
            grep '\.server=' |
            head -n 1 |
            cut -d= -f2- |
            sed "s/^'//;s/'$//"
        )"

    fi


    # ========================================================
    # 方法 3
    # ========================================================

    if [ -z "$CLOUD_SERVER" ] &&
       [ -f /etc/config/gl-cloud ]; then

        CLOUD_SERVER="$(
            sed -n \
                "s/^[[:space:]]*option[[:space:]]*server[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p" \
                /etc/config/gl-cloud 2>/dev/null |
            head -n 1
        )"

    fi


    return 0
}


# ============================================================
# 判断国内 / 海外
# ============================================================

detect_cloud_name()
{
    case "$CLOUD_SERVER" in

        "$CLOUD_SERVER_GLOBAL")

            CLOUD_NAME="海外服务器"

        ;;


        "$CLOUD_SERVER_CN")

            CLOUD_NAME="国内服务器"

        ;;


        "")

            CLOUD_NAME="未检测到服务器"

        ;;


        *)

            CLOUD_NAME="未知服务器"

        ;;

    esac
}


# ============================================================
# 获取设备绑定 URL
# ============================================================

get_cloud_url()
{
    CLOUD_URL=""


    CLOUD_JSON="$(
        ubus call gl-cloud bind_url \
        2>/dev/null
    )"


    if [ -z "$CLOUD_JSON" ]; then

        return 1

    fi


    # ========================================================
    # 优先 jsonfilter
    # ========================================================

    if command -v jsonfilter >/dev/null 2>&1; then

        CLOUD_URL="$(
            printf '%s\n' "$CLOUD_JSON" |
            jsonfilter -e '@.url' \
            2>/dev/null
        )"

    fi


    # ========================================================
    # jsonfilter 获取失败使用 sed
    # ========================================================

    if [ -z "$CLOUD_URL" ]; then

        CLOUD_URL="$(
            printf '%s\n' "$CLOUD_JSON" |
            sed -n \
                's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
            head -n 1
        )"

    fi


    if [ -n "$CLOUD_URL" ]; then

        return 0

    fi


    return 1
}


# ============================================================
# 刷新状态
# ============================================================

refresh_cloud_status()
{
    get_cloud_server

    detect_cloud_name

    get_cloud_url >/dev/null 2>&1

    return 0
}


# ============================================================
# 显示云服务连接信息
# ============================================================

show_cloud_status()
{
    refresh_cloud_status


    printf "\n"


    printf "%b\n" \
        "${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"

    printf "%b\n" \
        "${BLUE}║${GREEN}                  GL.iNet 云服务连接信息                  ${BLUE}║${RESET}"

    printf "%b\n" \
        "${BLUE}╠════════════════════════════════════════════════════════════╣${RESET}"


    # ========================================================
    # Name
    # ========================================================

    printf "%b" \
        "${BLUE}║${RESET} "

    printf "%b" \
        "${GREEN}Name   : ${RESET}"

    printf "%b" \
        "${WHITE}${CLOUD_NAME}${RESET}"

    printf "\n"


    # ========================================================
    # Server
    # ========================================================

    printf "%b" \
        "${BLUE}║${RESET} "

    printf "%b" \
        "${GREEN}Server : ${RESET}"


    if [ -n "$CLOUD_SERVER" ]; then

        printf "%b" \
            "${GREEN}${CLOUD_SERVER}${RESET}"

    else

        printf "%b" \
            "${RED}未检测到${RESET}"

    fi


    printf "\n"


    # ========================================================
    # URL
    # ========================================================

    printf "%b" \
        "${BLUE}║${RESET} "

    printf "%b" \
        "${GREEN}URL    : ${RESET}"


    if [ -n "$CLOUD_URL" ]; then

        printf "%b" \
            "${GREEN}${CLOUD_URL}${RESET}"

    else

        printf "%b" \
            "${YELLOW}暂未获取到绑定地址${RESET}"

    fi


    printf "\n"


    printf "%b\n" \
        "${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}"


    printf "\n"
}


# ============================================================
# 重启 gl-cloud
# ============================================================

restart_gl_cloud()
{
    if [ -x /etc/init.d/gl-cloud ]; then

        /etc/init.d/gl-cloud restart \
            >/dev/null 2>&1

        return $?

    fi


    _cloud_warn "没有找到 /etc/init.d/gl-cloud"

    return 1
}


# ============================================================
# 等待 gl-cloud 恢复
# ============================================================

wait_gl_cloud()
{
    COUNT=0


    while [ "$COUNT" -lt 10 ]; do

        if ubus -S list gl-cloud \
            >/dev/null 2>&1
        then

            return 0

        fi


        COUNT=$((COUNT + 1))

        sleep 1

    done


    return 1
}


# ============================================================
# 修改云服务器
# ============================================================

set_cloud_server()
{
    TARGET_SERVER="$1"
    TARGET_NAME="$2"


    if [ -z "$TARGET_SERVER" ]; then

        _cloud_error "目标服务器为空"

        return 1

    fi


    get_cloud_server


    # ========================================================
    # 已经是目标服务器
    # ========================================================

    if [ "$CLOUD_SERVER" = "$TARGET_SERVER" ]; then

        _cloud_ok "当前已经是：$TARGET_NAME"

        return 0

    fi


    printf "\n"


    _cloud_info "正在切换云服务..."

    _cloud_info "目标：$TARGET_NAME"


    printf "%b\n" \
        "${GREEN}[INFO] Server：${TARGET_SERVER}${RESET}"


    # ========================================================
    # 修改 UCI
    # ========================================================

    if ! uci -q set \
        "gl-cloud.@cloud[0].server=$TARGET_SERVER"
    then

        _cloud_error "修改 gl-cloud 配置失败"

        return 1

    fi


    # ========================================================
    # 保存配置
    # ========================================================

    if ! uci commit gl-cloud \
        >/dev/null 2>&1
    then

        _cloud_error "保存 gl-cloud 配置失败"

        return 1

    fi


    # ========================================================
    # 验证写入
    # ========================================================

    NEW_SERVER="$(
        uci -q get 'gl-cloud.@cloud[0].server' \
        2>/dev/null
    )"


    if [ "$NEW_SERVER" != "$TARGET_SERVER" ]; then

        _cloud_error "Server 写入验证失败"

        return 1

    fi


    _cloud_ok "配置保存成功"


    # ========================================================
    # 重启 gl-cloud
    # ========================================================

    _cloud_info "正在重启 gl-cloud..."


    if restart_gl_cloud; then

        _cloud_ok "gl-cloud 已重启"

    else

        _cloud_warn "gl-cloud 重启命令返回异常"

    fi


    # ========================================================
    # 等待服务恢复
    # ========================================================

    _cloud_info "正在等待云服务恢复..."


    if wait_gl_cloud; then

        _cloud_ok "云服务已经恢复"

    else

        _cloud_warn "暂时没有检测到 gl-cloud UBUS 服务"

    fi


    sleep 1


    # ========================================================
    # 最终验证
    # ========================================================

    get_cloud_server


    if [ "$CLOUD_SERVER" != "$TARGET_SERVER" ]; then

        _cloud_error "云服务器切换验证失败"

        printf "%b\n" \
            "${RED}[ERROR]${RESET} ${BOLD}当前 Server：${RESET}${GREEN}${CLOUD_SERVER}${RESET}"

        return 1

    fi


    _cloud_ok "已切换到：$TARGET_NAME"


    return 0
}


# ============================================================
# 切换国内服务器
# ============================================================

switch_cloud_cn()
{
    set_cloud_server \
        "$CLOUD_SERVER_CN" \
        "国内服务器"
}


# ============================================================
# 切换海外服务器
# ============================================================

switch_cloud_global()
{
    set_cloud_server \
        "$CLOUD_SERVER_GLOBAL" \
        "海外服务器"
}


# ============================================================
# 云服务菜单
# ============================================================

cloud_menu()
{
    clear


    # ========================================================
    # 环境检测
    # ========================================================

    if ! check_cloud_environment; then

        _cloud_pause

        return 1

    fi


    while true
    do

        clear


        # ====================================================
        # 获取当前状态
        # ====================================================

        get_cloud_server

        detect_cloud_name


        # ====================================================
        # 菜单
        # ====================================================

        printf "\n"


        printf "%b\n" \
            "${BLUE}╔══════════════════════════════════════╗${RESET}"

        printf "%b\n" \
            "${BLUE}║${GREEN}              修改云服务              ${BLUE}║${RESET}"

        printf "%b\n" \
            "${BLUE}╠══════════════════════════════════════╣${RESET}"

        printf "%b\n" \
            "${BLUE}║${CYAN}  [1] 切换国内服务器                  ${BLUE}║${RESET}"

        printf "%b\n" \
            "${BLUE}║${CYAN}  [2] 切换海外服务器                  ${BLUE}║${RESET}"

        printf "%b\n" \
            "${BLUE}║${CYAN}  [3] 查看云服务连接信息              ${BLUE}║${RESET}"

        printf "%b\n" \
            "${BLUE}║${CYAN}  [0] 返回主菜单                      ${BLUE}║${RESET}"

        printf "%b\n" \
            "${BLUE}╚══════════════════════════════════════╝${RESET}"


        # ====================================================
        # 当前服务器
        # ====================================================

        printf "\n"


        printf "%b" \
            "${GREEN}[当前]${RESET} "


        # 服务器类型：白色粗体

        printf "%b" \
            "${WHITE}${CLOUD_NAME}${RESET}"


        # Server：绿色粗体

        if [ -n "$CLOUD_SERVER" ]; then

            printf "  "

            printf "%b" \
                "${GREEN}${CLOUD_SERVER}${RESET}"

        fi


        printf "\n\n"


        # ====================================================
        # 分隔线
        # ====================================================

        printf "%b\n" \
            "${GREEN}--------------------------------------${RESET}"


        printf "\n"


        # ====================================================
        # 输入
        # ====================================================

        printf "%b" \
            "${YELLOW}选择序列 > ${RESET}"


        read CLOUD_CHOOSE </dev/tty


        case "$CLOUD_CHOOSE" in


        # ====================================================
        # 国内服务器
        # ====================================================

        1)

            clear

            printf "\n"

            switch_cloud_cn

            printf "\n"

            show_cloud_status

            _cloud_pause

        ;;


        # ====================================================
        # 海外服务器
        # ====================================================

        2)

            clear

            printf "\n"

            switch_cloud_global

            printf "\n"

            show_cloud_status

            _cloud_pause

        ;;


        # ====================================================
        # 查看连接信息
        # ====================================================

        3)

            clear

            show_cloud_status

            _cloud_pause

        ;;


        # ====================================================
        # 返回主菜单
        # ====================================================

        0)

            return 0

        ;;


        # ====================================================
        # 输入错误
        # ====================================================

        *)

            printf "%b\n" \
                "${RED}输入错误${RESET}"

            sleep 1

        ;;


        esac

    done
}

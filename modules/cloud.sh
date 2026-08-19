#!/bin/sh

# ============================================================
# Open-Pro-Installer
# GL.iNet 云服务管理模块
#
# 功能：
# 1. 自动检测 gl-cloud
# 2. 自动读取当前 Server
# 3. 自动识别国内 / 海外服务器
# 4. 获取 GoodCloud 设备绑定 URL
# 5. 一键切换国内服务器
# 6. 一键切换海外服务器
# 7. 一键解除 GoodCloud 云服务绑定
# 8. 解绑前二次确认，防止误操作
# 9. 自动 uci commit
# 10. 自动重启 gl-cloud
# 11. 修改后真实验证
# 12. URL 完整单行输出，支持直接复制
# 13. 不依赖 fold
# 14. 高亮 + 粗体终端界面
# 15. BusyBox / OpenWrt /bin/sh 兼容
#
# install.sh 调用：
# cloud_menu
# ============================================================

BOLD="$(printf '\033[1m')"
GREEN="$(printf '\033[1;92m')"
CYAN="$(printf '\033[1;96m')"
BLUE="$(printf '\033[1;94m')"
RED="$(printf '\033[1;91m')"
YELLOW="$(printf '\033[1;93m')"
WHITE="$(printf '\033[1;97m')"
RESET="$(printf '\033[0m')"

CLOUD_SERVER_CN="gslb.gl-inet.cn"
CLOUD_SERVER_GLOBAL="gslb-eu.goodcloud.xyz"

CLOUD_SERVER=""
CLOUD_NAME=""
CLOUD_URL=""

_cloud_pause()
{
    printf "\n"
    printf "%b" "${YELLOW}按回车返回...${RESET}"
    read CLOUD_DUMMY </dev/tty
}

_cloud_info()
{
    printf "%b\n" "${GREEN}[INFO]${RESET} ${BOLD}$*${RESET}"
}

_cloud_ok()
{
    printf "%b\n" "${GREEN}[OK]${RESET} ${BOLD}$*${RESET}"
}

_cloud_warn()
{
    printf "%b\n" "${YELLOW}[WARN]${RESET} ${BOLD}$*${RESET}"
}

_cloud_error()
{
    printf "%b\n" "${RED}[ERROR]${RESET} ${BOLD}$*${RESET}"
}

check_cloud_environment()
{
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        _cloud_error "请使用 root 用户运行"
        return 1
    fi

    if ! command -v uci >/dev/null 2>&1; then
        _cloud_error "当前系统没有检测到 uci"
        return 1
    fi

    if ! command -v ubus >/dev/null 2>&1; then
        _cloud_error "当前系统没有检测到 ubus"
        return 1
    fi

    if ! uci -q show gl-cloud >/dev/null 2>&1; then
        _cloud_error "没有检测到 GL.iNet gl-cloud"
        _cloud_warn "当前设备可能不是 GL.iNet 官方系统"
        return 1
    fi

    return 0
}

get_cloud_server()
{
    CLOUD_SERVER="$(uci -q get 'gl-cloud.@cloud[0].server' 2>/dev/null)"

    if [ -z "$CLOUD_SERVER" ]; then
        CLOUD_SERVER="$(
            uci -q show gl-cloud 2>/dev/null |
            grep '\.server=' |
            head -n 1 |
            cut -d= -f2- |
            sed "s/^'//;s/'$//"
        )"
    fi

    if [ -z "$CLOUD_SERVER" ] && [ -f /etc/config/gl-cloud ]; then
        CLOUD_SERVER="$(
            sed -n "s/^[[:space:]]*option[[:space:]]*server[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p" \
                /etc/config/gl-cloud 2>/dev/null |
            head -n 1
        )"
    fi

    return 0
}

detect_cloud_name()
{
    case "$CLOUD_SERVER" in
        "$CLOUD_SERVER_GLOBAL") CLOUD_NAME="海外服务器" ;;
        "$CLOUD_SERVER_CN") CLOUD_NAME="国内服务器" ;;
        "") CLOUD_NAME="未检测到服务器" ;;
        *) CLOUD_NAME="未知服务器" ;;
    esac
}

get_cloud_url()
{
    CLOUD_URL=""
    CLOUD_JSON="$(ubus call gl-cloud bind_url 2>/dev/null)"

    [ -n "$CLOUD_JSON" ] || return 1

    if command -v jsonfilter >/dev/null 2>&1; then
        CLOUD_URL="$(printf '%s\n' "$CLOUD_JSON" | jsonfilter -e '@.url' 2>/dev/null)"
    fi

    if [ -z "$CLOUD_URL" ]; then
        CLOUD_URL="$(
            printf '%s\n' "$CLOUD_JSON" |
            sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
            head -n 1
        )"
    fi

    [ -n "$CLOUD_URL" ]
}

refresh_cloud_status()
{
    get_cloud_server
    detect_cloud_name
    get_cloud_url >/dev/null 2>&1
    return 0
}

show_cloud_status()
{
    refresh_cloud_status

    printf "\n"
    printf "%b\n" "${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
    printf "%b\n" "${BLUE}║${GREEN}                  GL.iNet 云服务连接信息${RESET}"
    printf "%b\n" "${BLUE}╠════════════════════════════════════════════════════════════╣${RESET}"

    printf "%b" "${BLUE}║${RESET} ${CYAN}Name   : ${RESET}"
    case "$CLOUD_NAME" in
        "国内服务器"|"海外服务器") printf "%b\n" "${GREEN}${CLOUD_NAME}${RESET}" ;;
        "未检测到服务器") printf "%b\n" "${RED}${CLOUD_NAME}${RESET}" ;;
        *) printf "%b\n" "${YELLOW}${CLOUD_NAME}${RESET}" ;;
    esac

    printf "%b" "${BLUE}║${RESET} ${CYAN}Server : ${RESET}"
    if [ -n "$CLOUD_SERVER" ]; then
        printf "%b\n" "${GREEN}${CLOUD_SERVER}${RESET}"
    else
        printf "%b\n" "${RED}未检测到${RESET}"
    fi

    printf "%b" "${BLUE}║${RESET} ${CYAN}URL    : ${RESET}"
    if [ -n "$CLOUD_URL" ]; then
        printf "%b\n" "${GREEN}${CLOUD_URL}${RESET}"
    else
        printf "%b\n" "${YELLOW}暂未获取到绑定地址${RESET}"
    fi

    printf "%b\n" "${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}"
    printf "\n"
    return 0
}

restart_gl_cloud()
{
    if [ -x /etc/init.d/gl-cloud ]; then
        /etc/init.d/gl-cloud restart >/dev/null 2>&1
        return $?
    fi

    _cloud_warn "没有找到 /etc/init.d/gl-cloud"
    return 1
}

wait_gl_cloud()
{
    COUNT=0
    while [ "$COUNT" -lt 10 ]; do
        if ubus -S list gl-cloud >/dev/null 2>&1; then
            return 0
        fi
        COUNT=$((COUNT + 1))
        sleep 1
    done
    return 1
}

set_cloud_server()
{
    TARGET_SERVER="$1"
    TARGET_NAME="$2"

    [ -n "$TARGET_SERVER" ] || {
        _cloud_error "目标服务器为空"
        return 1
    }

    get_cloud_server

    if [ "$CLOUD_SERVER" = "$TARGET_SERVER" ]; then
        _cloud_ok "当前已经是：$TARGET_NAME"
        return 0
    fi

    printf "\n"
    _cloud_info "正在切换云服务..."
    _cloud_info "目标：$TARGET_NAME"
    _cloud_info "Server：$TARGET_SERVER"

    if ! uci -q set "gl-cloud.@cloud[0].server=$TARGET_SERVER"; then
        _cloud_error "修改 gl-cloud 配置失败"
        return 1
    fi

    if ! uci commit gl-cloud >/dev/null 2>&1; then
        _cloud_error "保存 gl-cloud 配置失败"
        return 1
    fi

    NEW_SERVER="$(uci -q get 'gl-cloud.@cloud[0].server' 2>/dev/null)"

    if [ "$NEW_SERVER" != "$TARGET_SERVER" ]; then
        _cloud_error "Server 写入验证失败"
        return 1
    fi

    _cloud_ok "配置保存成功"
    _cloud_info "正在重启 gl-cloud..."

    if restart_gl_cloud; then
        _cloud_ok "gl-cloud 已重启"
    else
        _cloud_warn "gl-cloud 重启命令返回异常"
    fi

    _cloud_info "正在等待云服务恢复..."

    if wait_gl_cloud; then
        _cloud_ok "云服务已经恢复"
    else
        _cloud_warn "暂时没有检测到 gl-cloud UBUS 服务"
    fi

    sleep 1
    get_cloud_server

    if [ "$CLOUD_SERVER" != "$TARGET_SERVER" ]; then
        _cloud_error "云服务器切换验证失败"
        _cloud_error "当前 Server：$CLOUD_SERVER"
        return 1
    fi

    _cloud_ok "已切换到：$TARGET_NAME"
    return 0
}

switch_cloud_cn()
{
    set_cloud_server "$CLOUD_SERVER_CN" "国内服务器"
}

switch_cloud_global()
{
    set_cloud_server "$CLOUD_SERVER_GLOBAL" "海外服务器"
}

unbind_cloud()
{
    printf "\n"

    if ! ubus -v list gl-cloud 2>/dev/null | grep -q '"unbind"'; then
        _cloud_error "当前 gl-cloud 没有提供 unbind 接口"
        _cloud_warn "无法通过当前系统接口自动解除绑定"
        return 1
    fi

    _cloud_warn "即将解除当前 GoodCloud 云服务绑定"
    _cloud_warn "解绑后需要重新绑定才能继续使用云服务"

    printf "\n"
    printf "%b" "${YELLOW}确认解除绑定？[y/N] > ${RESET}"
    read CLOUD_CONFIRM </dev/tty

    case "$CLOUD_CONFIRM" in
        y|Y|yes|YES) ;;
        *)
            printf "\n"
            _cloud_info "已取消解除绑定"
            return 0
        ;;
    esac

    printf "\n"
    _cloud_info "正在解除云服务绑定..."

    CLOUD_UNBIND_RESULT="$(ubus call gl-cloud unbind 2>&1)"
    CLOUD_UNBIND_CODE=$?

    if [ "$CLOUD_UNBIND_CODE" -ne 0 ]; then
        _cloud_error "云服务解绑失败"
        [ -n "$CLOUD_UNBIND_RESULT" ] && {
            printf "\n"
            printf "%s\n" "$CLOUD_UNBIND_RESULT"
        }
        return 1
    fi

    _cloud_ok "解绑请求执行成功"
    _cloud_info "正在等待云服务更新状态..."
    sleep 2

    if ubus -S list gl-cloud >/dev/null 2>&1; then
        _cloud_ok "gl-cloud 服务运行正常"
    else
        _cloud_warn "暂时没有检测到 gl-cloud UBUS 服务"
    fi

    CLOUD_URL=""
    if get_cloud_url; then
        if [ -n "$CLOUD_URL" ]; then
            _cloud_ok "设备当前可以重新绑定"
            printf "\n"
            printf "%b\n" "${CYAN}新的绑定地址：${RESET}"
            printf "%b\n" "${GREEN}${CLOUD_URL}${RESET}"
        fi
    else
        _cloud_warn "暂时没有获取到新的绑定地址"
    fi

    printf "\n"
    _cloud_ok "云服务解绑操作完成"
    return 0
}

show_current_cloud()
{
    get_cloud_server
    detect_cloud_name

    printf "\n"
    printf "%b" "${GREEN}[当前]${RESET}"
    printf " "

    case "$CLOUD_NAME" in
        "国内服务器"|"海外服务器") printf "%b" "${WHITE}${CLOUD_NAME}${RESET}" ;;
        "未检测到服务器") printf "%b" "${RED}${CLOUD_NAME}${RESET}" ;;
        *) printf "%b" "${YELLOW}${CLOUD_NAME}${RESET}" ;;
    esac

    if [ -n "$CLOUD_SERVER" ]; then
        printf "  "
        printf "%b" "${GREEN}${CLOUD_SERVER}${RESET}"
    fi

    printf "\n\n"
    printf "%b\n" "${GREEN}--------------------------------------${RESET}"
    printf "\n"
}

cloud_menu()
{
    clear

    if ! check_cloud_environment; then
        _cloud_pause
        return 1
    fi

    while true
    do
        clear
        get_cloud_server
        detect_cloud_name
        printf "\n"

        printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"
        printf "%b\n" "${BLUE}║${GREEN}              修改云服务              ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}╠══════════════════════════════════════╣${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [1] 切换国内服务器                  ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [2] 切换海外服务器                  ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [3] 解除云服务绑定                  ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [4] 查看云服务连接信息              ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [0] 返回主菜单                      ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"

        show_current_cloud

        printf "%b" "${YELLOW}选择序列 > ${RESET}"
        read CLOUD_CHOOSE </dev/tty

        case "$CLOUD_CHOOSE" in
            1)
                clear
                printf "\n"
                switch_cloud_cn
                printf "\n"
                show_cloud_status
                _cloud_pause
            ;;

            2)
                clear
                printf "\n"
                switch_cloud_global
                printf "\n"
                show_cloud_status
                _cloud_pause
            ;;

            3)
                clear
                printf "\n"
                unbind_cloud
                _cloud_pause
            ;;

            4)
                clear
                show_cloud_status
                _cloud_pause
            ;;

            0)
                return 0
            ;;

            *)
                printf "\n"
                printf "%b\n" "${RED}输入错误${RESET}"
                sleep 1
            ;;
        esac
    done
}

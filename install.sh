#!/bin/sh

# ============================================================
# Open-Pro-Installer
# Main Installer
# BusyBox / OpenWrt Compatible
# ============================================================


# ============================================================
# 获取脚本目录
# ============================================================

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"


# ============================================================
# 加载基础库
# ============================================================

. "$SCRIPT_DIR/lib/logger.sh"
. "$SCRIPT_DIR/lib/github.sh"


if [ -f "$SCRIPT_DIR/modules/depend.sh" ]; then
    . "$SCRIPT_DIR/modules/depend.sh"
fi


clear


# ============================================================
# Color
# 高亮 + 粗体
# ============================================================

BOLD="$(printf '\033[1m')"

GREEN="$(printf '\033[1;92m')"
CYAN="$(printf '\033[1;96m')"
BLUE="$(printf '\033[1;94m')"
RED="$(printf '\033[1;91m')"
YELLOW="$(printf '\033[1;93m')"
WHITE="$(printf '\033[1;97m')"

RESET="$(printf '\033[0m')"


# ============================================================
# 返回提示
# ============================================================

pause()
{
    printf "\n"
    printf "%b\n" "${GREEN}按回车返回...${RESET}"
    read dummy </dev/tty
}


# ============================================================
# 主菜单
# ============================================================

main_menu()
{
    while true
    do

        clear

        printf "\n"

        printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"
        printf "%b\n" "${BLUE}║${GREEN}             ZIMO--工具箱             ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${GREEN}               v1.0.0                 ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}╠══════════════════════════════════════╣${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [1] 一键仿 iStoreOS 主题            ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [2] 安装 iStore 商店                ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [3] 安装代理工具                    ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [4] 其他工具                        ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [5] 解锁区域限制                    ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [6] 修改云服务                      ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [0] 退出                            ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"

        printf "\n"

        printf "%b" "${YELLOW}选择序列 > ${RESET}"

        read CHOOSE </dev/tty


        case "$CHOOSE" in


        # ====================================================
        # 1. iStoreOS 主题
        # ====================================================

        1)

            if [ -f "$SCRIPT_DIR/modules/theme.sh" ]; then

                . "$SCRIPT_DIR/modules/theme.sh"

                if command -v install_theme >/dev/null 2>&1; then

                    install_theme

                else

                    printf "%b\n" \
                        "${RED}theme.sh 缺少 install_theme()${RESET}"

                fi

            else

                printf "%b\n" \
                    "${RED}theme.sh 不存在${RESET}"

            fi

            pause

        ;;


        # ====================================================
        # 2. iStore 商店
        # ====================================================

        2)

            if [ -f "$SCRIPT_DIR/modules/istore.sh" ]; then

                . "$SCRIPT_DIR/modules/istore.sh"

                if command -v install_istore >/dev/null 2>&1; then

                    install_istore

                else

                    printf "%b\n" \
                        "${RED}istore.sh 缺少 install_istore()${RESET}"

                fi

            else

                printf "%b\n" \
                    "${RED}istore.sh 不存在${RESET}"

            fi

            pause

        ;;


        # ====================================================
        # 3. 代理工具
        # ====================================================

        3)

            proxy_menu

        ;;


        # ====================================================
        # 4. 其他工具
        # ====================================================

        4)

            other_tools_menu

        ;;


        # ====================================================
        # 5. 解锁区域限制
        # ====================================================

        5)

            if [ -f "$SCRIPT_DIR/modules/unlock.sh" ]; then

                . "$SCRIPT_DIR/modules/unlock.sh"

                if command -v region_menu >/dev/null 2>&1; then

                    region_menu

                else

                    printf "%b\n" \
                        "${RED}unlock.sh 缺少 region_menu()${RESET}"

                    pause

                fi

            else

                printf "%b\n" \
                    "${RED}unlock.sh 不存在${RESET}"

                pause

            fi

        ;;


        # ====================================================
        # 6. 修改云服务
        # ====================================================

        6)

            if [ -f "$SCRIPT_DIR/modules/cloud.sh" ]; then

                . "$SCRIPT_DIR/modules/cloud.sh"

                if command -v cloud_menu >/dev/null 2>&1; then

                    cloud_menu

                else

                    printf "%b\n" \
                        "${RED}cloud.sh 缺少 cloud_menu()${RESET}"

                    pause

                fi

            else

                printf "%b\n" \
                    "${RED}cloud.sh 不存在${RESET}"

                printf "%b\n" \
                    "${YELLOW}缺少：modules/cloud.sh${RESET}"

                pause

            fi

        ;;


        # ====================================================
        # 0. 退出
        # ====================================================

        0)

            printf "%b\n" \
                "${RED}Exit.${RESET}"

            exit 0

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


# ============================================================
# 代理工具菜单
# ============================================================

proxy_menu()
{
    while true
    do

        clear

        printf "\n"

        printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"
        printf "%b\n" "${BLUE}║${GREEN}              代理工具                ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}╠══════════════════════════════════════╣${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [1] 安装 OpenClash                  ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [2] 安装 SSR Plus+                  ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [3] 安装 PassWall                   ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [4] 安装 PassWall2                  ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [0] 返回主菜单                      ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"

        printf "\n"

        printf "%b" \
            "${YELLOW}选择序列 > ${RESET}"

        read PROXY_CHOOSE </dev/tty


        case "$PROXY_CHOOSE" in


        # ====================================================
        # 1. OpenClash
        # ====================================================

        1)

            printf "\n"

            printf "%b\n" \
                "${GREEN}===== OpenClash =====${RESET}"


            if [ ! -f "$SCRIPT_DIR/modules/openclash.sh" ]; then

                printf "%b\n" \
                    "${RED}OpenClash模块不存在${RESET}"

                printf "%b\n" \
                    "${YELLOW}缺少：modules/openclash.sh${RESET}"

                pause

                continue

            fi


            if get_latest_release; then

                . "$SCRIPT_DIR/modules/openclash.sh"


                if command -v install_openclash >/dev/null 2>&1; then

                    install_openclash

                else

                    printf "%b\n" \
                        "${RED}OpenClash模块缺少 install_openclash()${RESET}"

                fi

            else

                printf "%b\n" \
                    "${RED}OpenClash版本获取失败${RESET}"

            fi


            pause

        ;;


        # ====================================================
        # 2. SSR Plus+
        # ====================================================

        2)

            printf "\n"

            printf "%b\n" \
                "${GREEN}===== SSR Plus+ =====${RESET}"


            if [ -f "$SCRIPT_DIR/modules/ssrplus.sh" ]; then

                . "$SCRIPT_DIR/modules/ssrplus.sh"


                if command -v install_ssrplus >/dev/null 2>&1; then

                    install_ssrplus

                else

                    printf "%b\n" \
                        "${RED}SSR Plus模块缺少 install_ssrplus()${RESET}"

                fi

            else

                printf "%b\n" \
                    "${RED}SSR Plus模块不存在${RESET}"

                printf "%b\n" \
                    "${YELLOW}缺少：modules/ssrplus.sh${RESET}"

            fi


            pause

        ;;


        # ====================================================
        # 3. PassWall
        # ====================================================

        3)

            printf "\n"

            printf "%b\n" \
                "${GREEN}===== PassWall =====${RESET}"


            if [ -f "$SCRIPT_DIR/modules/passwall.sh" ]; then

                . "$SCRIPT_DIR/modules/passwall.sh"


                if command -v install_passwall >/dev/null 2>&1; then

                    install_passwall

                else

                    printf "%b\n" \
                        "${RED}PassWall模块缺少 install_passwall()${RESET}"

                fi

            else

                printf "%b\n" \
                    "${RED}PassWall模块不存在${RESET}"

                printf "%b\n" \
                    "${YELLOW}缺少：modules/passwall.sh${RESET}"

            fi


            pause

        ;;


        # ====================================================
        # 4. PassWall2
        # ====================================================

        4)

            printf "\n"

            printf "%b\n" \
                "${GREEN}===== PassWall2 =====${RESET}"


            if [ -f "$SCRIPT_DIR/modules/passwall2.sh" ]; then

                . "$SCRIPT_DIR/modules/passwall2.sh"


                if command -v install_passwall2 >/dev/null 2>&1; then

                    install_passwall2

                else

                    printf "%b\n" \
                        "${RED}PassWall2模块缺少 install_passwall2()${RESET}"

                fi

            else

                printf "%b\n" \
                    "${RED}PassWall2模块不存在${RESET}"

                printf "%b\n" \
                    "${YELLOW}缺少：modules/passwall2.sh${RESET}"

            fi


            pause

        ;;


        # ====================================================
        # 0. 返回主菜单
        # ====================================================

        0)

            return

        ;;


        *)

            printf "%b\n" \
                "${RED}输入错误${RESET}"

            sleep 1

        ;;

        esac

    done
}


# ============================================================
# 其他工具菜单
# ============================================================

other_tools_menu()
{
    while true
    do

        clear

        printf "\n"

        printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"
        printf "%b\n" "${BLUE}║${GREEN}              其他工具                ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}╠══════════════════════════════════════╣${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [1] 安装 MosDNS                     ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}║${CYAN}  [0] 返回主菜单                      ${BLUE}║${RESET}"
        printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"

        printf "\n"

        printf "%b" \
            "${YELLOW}选择序列 > ${RESET}"

        read TOOL_CHOOSE </dev/tty


        case "$TOOL_CHOOSE" in


        # ====================================================
        # 1. MosDNS
        # ====================================================

        1)

            clear

            printf "\n"

            printf "%b\n" \
                "${GREEN}===== MosDNS =====${RESET}"

            printf "\n"


            if [ -f "$SCRIPT_DIR/modules/mosdns.sh" ]; then

                . "$SCRIPT_DIR/modules/mosdns.sh"


                if command -v install_mosdns >/dev/null 2>&1; then

                    install_mosdns

                else

                    printf "%b\n" \
                        "${RED}MosDNS模块缺少 install_mosdns()${RESET}"

                fi

            else

                printf "%b\n" \
                    "${RED}MosDNS模块不存在${RESET}"

                printf "%b\n" \
                    "${YELLOW}缺少：modules/mosdns.sh${RESET}"

            fi


            pause

        ;;


        # ====================================================
        # 0. 返回主菜单
        # ====================================================

        0)

            return

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


# ============================================================
# Start
# ============================================================

main_menu

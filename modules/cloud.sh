# ============================================================
# 显示云服务连接信息
# URL 自动换行 + 所有 URL 行严格对齐
# ============================================================

show_cloud_status()
{
    refresh_cloud_status

    # --------------------------------------------------------
    # 显示参数
    #
    # BOX_WIDTH  : 框体内部宽度
    # URL_WIDTH  : 每一行 URL 最多显示多少字符
    #
    # URL_PREFIX = "URL    : "
    # 后续 URL 行会自动补相同宽度的空格
    # --------------------------------------------------------

    URL_WIDTH=47
    URL_INDENT="         "


    printf "\n"


    # ========================================================
    # 标题
    # ========================================================

    printf "%b\n" \
        "${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"

    printf "%b\n" \
        "${BLUE}║${GREEN}                  GL.iNet 云服务连接信息                  ${BLUE}║${RESET}"

    printf "%b\n" \
        "${BLUE}╠════════════════════════════════════════════════════════════╣${RESET}"


    # ========================================================
    # Name
    # ========================================================

    printf "%b" "${BLUE}║${RESET} "

    printf "%b" "${CYAN}Name   : ${RESET}"

    printf "%b" "${GREEN}${CLOUD_NAME}${RESET}"

    printf "\n"


    # ========================================================
    # Server
    # ========================================================

    printf "%b" "${BLUE}║${RESET} "

    printf "%b" "${CYAN}Server : ${RESET}"


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

    if [ -n "$CLOUD_URL" ]; then

        URL_LINE_NUM=0


        # ----------------------------------------------------
        # fold 按固定宽度自动切割 URL
        #
        # 第一行：
        # ║ URL    : https://xxxx
        #
        # 后续：
        # ║          xxxxxxxxxxxx
        #             ↑
        #             与 https:// 左侧严格对齐
        # ----------------------------------------------------

        printf '%s' "$CLOUD_URL" |
        fold -w "$URL_WIDTH" |
        while IFS= read -r URL_LINE
        do

            if [ "$URL_LINE_NUM" -eq 0 ]; then

                printf "%b" "${BLUE}║${RESET} "

                printf "%b" "${CYAN}URL    : ${RESET}"

                printf "%b\n" \
                    "${GREEN}${URL_LINE}${RESET}"

            else

                printf "%b" "${BLUE}║${RESET} "

                printf "%s" "$URL_INDENT"

                printf "%b\n" \
                    "${GREEN}${URL_LINE}${RESET}"

            fi


            URL_LINE_NUM=$((URL_LINE_NUM + 1))

        done

    else

        printf "%b" "${BLUE}║${RESET} "

        printf "%b" "${CYAN}URL    : ${RESET}"

        printf "%b\n" \
            "${YELLOW}暂未获取到绑定地址${RESET}"

    fi


    # ========================================================
    # 底部边框
    # ========================================================

    printf "%b\n" \
        "${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}"


    printf "\n"
}

4)

printf "%b\n" "${GREEN}[区域] 正在解锁区域限制...${RESET}"


if [ -f "$SCRIPT_DIR/modules/unlock.sh" ]
then

    . "$SCRIPT_DIR/modules/unlock.sh"

    unlock_region


else

    printf "%b\n" "${RED}[ERROR] unlock.sh 不存在${RESET}"

fi


back_main

;;

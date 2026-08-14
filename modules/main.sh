4)


printf "%b\n" "${GREEN}[区域] 打开区域限制管理...${RESET}"



if [ -f "$SCRIPT_DIR/modules/unlock.sh" ]
then


    . "$SCRIPT_DIR/modules/unlock.sh"


    region_menu



else


    printf "%b\n" "${RED}[ERROR] unlock.sh 不存在${RESET}"


    sleep 2


fi



;;

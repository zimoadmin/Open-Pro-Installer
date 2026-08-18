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

    # ========================================================
    # Kernel / Architecture
    # ========================================================

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
        MODEL="$(tr -d '\000' < /proc/device-tree/model 2>/dev/null)"
    fi

    [ -n "$MODEL" ] || MODEL="unknown"


    # ========================================================
    # 获取 OpenWrt 信息
    # ========================================================

    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release

        OPENWRT_VERSION="${DISTRIB_RELEASE:-unknown}"
        OPENWRT_TARGET="${DISTRIB_TARGET:-unknown}"
    fi


    # ========================================================
    # UBUS 补充系统信息
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
    # 清理字符串
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
    # 检测 32 / 64 位
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
    # 标准化 Target / Model
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


    # ========================================================
    # 提取 Target Family
    #
    # ipq53xx/generic -> ipq53xx
    # mediatek/mt7987 -> mediatek
    #
    # 不再使用 ${TARGET_LOWER%%/*}
    # ========================================================

    TARGET_FAMILY="$(
        printf '%s' "$TARGET_LOWER" |
        cut -d '/' -f 1
    )"


    # ========================================================
    # 初始化平台
    # ========================================================

    PLATFORM="unknown"


    # ========================================================
    # 第一优先级：Target Family
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
    # 第二优先级：完整 Target
    # ========================================================

    if [ "$PLATFORM" = "unknown" ]; then

        case "$TARGET_LOWER" in

            ipq53xx/*|*ipq53xx*|*ipq5332*|*ipq5312*)
                PLATFORM="IPQ53XX"
                ;;

            ipq6000/*|*ipq6000*)
                PLATFORM="IPQ6000"
                ;;

            ipq5018/*|*ipq5018*)
                PLATFORM="IPQ5018"
                ;;

            ipq4019/*|ipq401x/*|*ipq4019*|*ipq401x*)
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
    # 第三优先级：设备 Model / SoC
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
    # 第四优先级：GL.iNet 型号兜底
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
    # 第五优先级：
    # IPQ53XX 特殊强力兜底
    #
    # 针对 GL-BE3600 / BE6500 / BE9300
    # 以及 IPQ5332 / IPQ5312
    # ========================================================

    if [ "$PLATFORM" = "unknown" ]; then

        if printf '%s\n%s\n' \
            "$OPENWRT_TARGET" \
            "$MODEL" |
            grep -Eqi 'ipq53xx|ipq5332|ipq5312|be3600|be6500|be9300'
        then
            PLATFORM="IPQ53XX"
        fi
    fi


    # ========================================================
    # MT798X 特殊兜底
    # ========================================================

    if [ "$PLATFORM" = "unknown" ]; then

        if printf '%s\n%s\n' \
            "$OPENWRT_TARGET" \
            "$MODEL" |
            grep -Eqi 'mt7981|mt7986|mt7987|mt7988|mt2500|mt3000|mt5000|mt6000|mt3600'
        then
            PLATFORM="MT798X"
        fi
    fi


    # ========================================================
    # 显示结果
    # ========================================================

    printf "\n"
    printf "======================================\n"
    printf "          设备检测结果\n"
    printf "======================================\n"
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


    # ========================================================
    # 最终验证
    # ========================================================

    if [ "$PLATFORM" = "unknown" ]; then
        _ssr_error "无法识别当前设备平台"

        printf "\n"
        _ssr_error "Target : $OPENWRT_TARGET"
        _ssr_error "Family : $TARGET_FAMILY"
        _ssr_error "Model  : $MODEL"

        return 1
    fi


    if [ "$BITS" = "unknown" ]; then
        _ssr_error "无法识别当前系统位数"
        return 1
    fi


    return 0
}

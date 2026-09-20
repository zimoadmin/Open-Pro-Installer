#!/bin/sh

# ======================================
# Color
# ======================================

BOLD="$(printf '\033[1m')"
GREEN="$(printf '\033[1;92m')"
BLUE="$(printf '\033[1;94m')"
CYAN="$(printf '\033[1;96m')"
YELLOW="$(printf '\033[1;93m')"
RED="$(printf '\033[1;91m')"
WHITE="$(printf '\033[1;97m')"
RESET="$(printf '\033[0m')"


# ======================================
# Config
# ======================================



WORKDIR="/tmp/Open-Pro-Installer"

AUTH_SERVER="https://auth.12334123.xyz"

ZIP_FILE="$WORKDIR/main.zip"

BOOTSTRAP_LOG="/tmp/openpro_bootstrap.log"

# 单个 opkg 操作的最长等待时间（秒）
OPKG_TIMEOUT="${OPI_OPKG_TIMEOUT:-60}"

# 是否跳过 opkg 依赖检查
SKIP_DEPS="${OPI_SKIP_DEPS:-0}"

# --------------------------------------
# 下载源（并行竞速）
#
# 一共 8 条线路同时下载，谁先拿到「完整可用」的 zip 就用谁：
#
#   SERVER   自己的服务器（国内用户主要靠它）
#   CODELOAD GitHub 直连，也就是 DIRECT 那条
#            （用 codeload 域名，比 github.com/archive 少一次 302）
#   GH01-06  和你 github.sh 里同一套 ghproxy 镜像
#            （同款"前缀式"拼接：代理地址 + 完整 GitHub 地址）
#
# 说明：GH01-06 是社区免费服务，每次安装会各请求一次（约 6 x 119KB）
#       哪个时间段哪条快不用你操心，脚本自己挑最快的
#
# 不想用的线路直接删行，并同步改下面的 DL_PRIORITY
# --------------------------------------

DL_DIR="$WORKDIR/dl"

# 单条线路的最长下载时间 / 整体等待上限（秒）
DL_DEADLINE=110

# GH01-GH06 用的归档地址（前缀式代理会把它拼在代理地址后面）
DL_ARCHIVE="https://github.com/zimoadmin/Open-Pro-Installer/archive/refs/heads/main.zip"

DL_SOURCES="
SERVER|https://auth.12334123.xyz/installer
CODELOAD|https://codeload.github.com/zimoadmin/Open-Pro-Installer/zip/refs/heads/main
GH01|https://ghproxy.net/${DL_ARCHIVE}
GH02|https://gh-proxy.org/${DL_ARCHIVE}
GH03|https://gh-proxy.com/${DL_ARCHIVE}
GH04|https://cdn.akaere.online/${DL_ARCHIVE}
GH05|https://github.mxw.qzz.io/${DL_ARCHIVE}
GH06|https://gh.07150721.xyz/${DL_ARCHIVE}
"

# 同时完成时的优先顺序（一般用不上，先到先得）
# 注意：新增 / 删除线路时，这里要和 DL_SOURCES 一起改
DL_PRIORITY="SERVER CODELOAD GH01 GH02 GH03 GH04 GH05 GH06"

# 竞速胜出的线路名（由 download_repo 写入）
DL_WIN=""

# 是否有过失败 / 超时（决定是否保留日志）
BOOTSTRAP_WARN=0

SPIN_PID=""

START_TS=""


# ======================================
# 进度 / 计时 / 超时 工具
# ======================================

now_ts()
{
    date +%s 2>/dev/null ||
        printf '0'
}


init_timer()
{
    START_TS="$(now_ts)"

    case "$START_TS" in
        ''|*[!0-9]*)
            START_TS=0
            ;;
    esac
}


elapsed_sec()
{
    ELAPSED_NOW="$(now_ts)"

    case "$ELAPSED_NOW" in
        ''|*[!0-9]*)
            ELAPSED_NOW=0
            ;;
    esac

    ELAPSED_DIFF=$((ELAPSED_NOW - START_TS))

    [ "$ELAPSED_DIFF" -ge 0 ] ||
        ELAPSED_DIFF=0

    printf '%s' "$ELAPSED_DIFF"
}


step()
{
    printf "%b\n" "${GREEN}[STEP]${RESET} $*   ${CYAN}(已用 $(elapsed_sec)s)${RESET}"
}


note()
{
    printf "%b\n" "${GREEN}[OK]${RESET} $*"
}


warn()
{
    BOOTSTRAP_WARN=1

    printf "%b\n" "${YELLOW}[WARN]${RESET} $*"
}


# 长任务心跳：每 2 秒打印一个点，
# 让用户看到脚本还活着，而不是卡死
spin_start()
{
    spin_stop

    (
        while : ; do
            sleep 2
            printf '.'
        done
    ) &

    SPIN_PID=$!
}


spin_stop()
{
    if [ -n "$SPIN_PID" ]; then

        kill "$SPIN_PID" 2>/dev/null

        wait "$SPIN_PID" 2>/dev/null

        SPIN_PID=""

        printf "\n"
    fi
}


# 带硬超时执行命令
# 有 timeout 就用 timeout，没有就用 后台+定时 kill 兜底
run_limited()
{
    LIMIT_SEC="$1"

    shift

    if [ -z "$LIMIT_SEC" ]; then
        LIMIT_SEC=60
    fi

    if command -v timeout >/dev/null 2>&1; then

        timeout "$LIMIT_SEC" "$@"

        return $?
    fi

    "$@" &

    RUN_PID=$!

    (
        sleep "$LIMIT_SEC"

        kill "$RUN_PID" 2>/dev/null
    ) &

    KILL_PID=$!

    wait "$RUN_PID"

    RUN_RC=$?

    kill "$KILL_PID" 2>/dev/null

    wait "$KILL_PID" 2>/dev/null

    return "$RUN_RC"
}


# ======================================
# Auth HTTP Request
#
# 第1次：AUTO 自动 IPv4 / IPv6
# 第2次：强制 IPv4
#
# 连接超时：3秒
# 总超时：6秒
# 失败立即切换
#
# 说明：这里故意不加 curl -f
#   服务端返回 4xx/5xx 时，-f 会把响应体直接丢掉，
#   于是"网络其实是通的、服务端也说明了原因"，
#   脚本却只报一句"连接超时"，用户永远看不到真实原因。
#   现在保留响应体，由调用方按内容判断并原样打印。
# ======================================

auth_post()
{
    AUTH_PATH="$1"
    AUTH_DATA="$2"

    AUTH_URL="$AUTH_SERVER$AUTH_PATH"

    AUTH_ERR_FILE="/tmp/openpro_auth.err"

    AUTH_LAST_ERR=""

    for AUTH_V4 in "" "-4"
    do

        rm -f "$AUTH_ERR_FILE"

        if [ -n "$AUTH_DATA" ]; then

            AUTH_RESULT="$(
                curl $AUTH_V4 \
                    -sS \
                    --connect-timeout 3 \
                    --max-time 6 \
                    -X POST \
                    -H "Content-Type: application/json" \
                    --data "$AUTH_DATA" \
                    "$AUTH_URL" \
                    2>"$AUTH_ERR_FILE"
            )"

        else

            AUTH_RESULT="$(
                curl $AUTH_V4 \
                    -sS \
                    --connect-timeout 3 \
                    --max-time 6 \
                    -X POST \
                    "$AUTH_URL" \
                    2>"$AUTH_ERR_FILE"
            )"

        fi

        AUTH_CURL_RESULT=$?

        if [ -s "$AUTH_ERR_FILE" ]; then

            AUTH_LAST_ERR="$(
                tail -n 1 "$AUTH_ERR_FILE" 2>/dev/null
            )"

        fi

        if [ "$AUTH_CURL_RESULT" -eq 0 ] &&
           [ -n "$AUTH_RESULT" ]; then

            printf '%s' "$AUTH_RESULT"
            return 0

        fi

    done

    rm -f "$AUTH_ERR_FILE" 2>/dev/null

    # 两种协议都没拿到响应：把 curl 的真实原因打出来
    # （走 stderr，避免污染被 $( ) 捕获的响应体）
    if [ -n "$AUTH_LAST_ERR" ]; then

        printf "%b\n" "${YELLOW}[WARN]${RESET} curl: $AUTH_LAST_ERR" >&2

    fi

    return 1
}


# ======================================
# Header
# ======================================

init_timer

printf "\n"


# ======================================
# Disclaimer
# ======================================

printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"
printf "%b\n" "${BLUE}║${GREEN}              免责声明                ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}╠══════════════════════════════════════╣${RESET}"

printf "%b\n" "${BLUE}║${CYAN} 本工具仅用于学习交流和个人设备管理。 ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}║${CYAN} 使用本工具产生的风险由用户承担。     ${BLUE}║${RESET}"
printf "%b\n" "${BLUE}║${CYAN} 请勿用于违反当地法律法规的用途。     ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}╠══════════════════════════════════════╣${RESET}"

printf "%b\n" "${BLUE}║${YELLOW} 是否同意以上免责声明？(Y/N)          ${BLUE}║${RESET}"

printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"

printf "\n"

printf "%b" "${YELLOW}输入 > ${RESET}"

read AGREE </dev/tty


case "$AGREE" in

Y|y)

    printf "\n"
    printf "%b\n" "${GREEN}[INFO] 已同意免责声明，继续运行...${RESET}"
    printf "\n"

    ;;

N|n)

    printf "\n"
    printf "%b\n" "${RED}[INFO] 已拒绝免责声明，程序退出。${RESET}"

    exit 0

    ;;

*)

    printf "\n"
    printf "%b\n" "${RED}[ERROR] 输入无效，程序退出。${RESET}"

    exit 1

    ;;

esac


# ======================================
# Check tools
# ======================================

step "1/6 检查运行环境"

for cmd in curl wget unzip
do

    if ! command -v "$cmd" >/dev/null 2>&1
    then

        printf "%b\n" "${RED}[ERROR] 缺少命令: $cmd${RESET}"

        exit 1

    fi

done


# ======================================
# 授权：扫码付费（本入口只走扫码）
#
# 流程：
#   1. 本地授权文件没过期 → 直接跳过付费
#   2. 否则 POST /order/create 下单
#        → 打印服务器返回的二维码（ANSI 文本）
#        → 每 2 秒轮询 /order/status
#   3. 支付成功 → 写授权文件 → 继续
#      失败 / 超时 / 按 Ctrl+C → 提示并退出（本入口不做验证码）
#
# 服务器接口约定（都在 PAY_SERVER 上，和授权服务器 auth.12334123.xyz 是两套）：
#   POST /order/create          参数：device=<设备标识>&version=<版本>
#        200 {"success":true,"order_id":"...","poll_token":"...",
#             "expire_seconds":1200,"amount":"1.00"}
#   GET  /order/qr?token=<poll_token>
#        200 text/plain：ANSI 二维码，直接打印就能扫
#   GET  /order/status?token=<poll_token>
#        200 {"success":true,"status":"pending"}
#            {"success":true,"status":"paid","license":"...","license_expire":0}
#            {"success":true,"status":"expired"}
#
# 授权文件（默认 /etc/openpro/license）：
#   device=<设备标识>
#   token=<服务器下发的令牌>
#   expire=<到期时间戳，0 = 永久>
#
# 可用环境变量：
#   OPI_LICENSE_TTL   付费后授权有效秒数（0 = 永久），默认 1200 = 20 分钟
#   OPI_ORDER_TIMEOUT 二维码/订单最长等待秒数，默认 1200
# ======================================

LICENSE_DIR="/etc/openpro"
LICENSE_FILE="$LICENSE_DIR/license"
LICENSE_FALLBACK="/tmp/openpro_license"

# ======================================
# 支付服务器
#
# 扫码版整套都在 att.12334123.xyz 上：
# 脚本下发、下单接口、二维码、支付回调。
#
# 换地址：改这行，或运行时给 OPI_PAY_SERVER=...
# ======================================

PAY_SERVER="${OPI_PAY_SERVER:-https://att.12334123.xyz}"

# 付费后授权有效期（秒）：0 = 永久
# 目前按你的要求：20 分钟 = 1200
LICENSE_TTL="${OPI_LICENSE_TTL:-1200}"

# 二维码 / 订单最长等待（秒）
PAY_ORDER_TIMEOUT="${OPI_ORDER_TIMEOUT:-1200}"

PAY_POLL_INTERVAL=2

PAY_QR_FILE="/tmp/openpro_pay_qr.txt"

AUTHORIZED=0


_pay_info()
{
    printf "%b\n" "${GREEN}[INFO]${RESET} $*"
}


_pay_ok()
{
    printf "%b\n" "${GREEN}[OK]${RESET} $*"
}


_pay_warn()
{
    printf "%b\n" "${YELLOW}[WARN]${RESET} $*"
}


# ======================================
# JSON 取字段（服务器返回的是单行 JSON）
# ======================================

json_str()
{
    printf '%s' "$1" |
        sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        head -n 1
}


json_num()
{
    printf '%s' "$1" |
        sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' |
        head -n 1
}


# ======================================
# 设备标识（优先网卡 MAC）
# ======================================

get_device_id()
{
    DEV_ID=""

    for DEV_ADDR in /sys/class/net/*/address
    do
        [ -f "$DEV_ADDR" ] ||
            continue

        case "$DEV_ADDR" in
            */lo/address)
                continue
                ;;
        esac

        DEV_ID="$(cat "$DEV_ADDR" 2>/dev/null)"

        case "$DEV_ID" in
            ''|00:00:00:00:00:00)
                DEV_ID=""
                continue
                ;;
        esac

        break
    done

    [ -n "$DEV_ID" ] ||
        DEV_ID="$(uname -n 2>/dev/null)"

    [ -n "$DEV_ID" ] ||
        DEV_ID="unknown"

    printf '%s' "$DEV_ID"
}


# ======================================
# 授权文件
# ======================================

license_file_path()
{
    if [ -d "$LICENSE_DIR" ] || mkdir -p "$LICENSE_DIR" 2>/dev/null; then

        printf '%s' "$LICENSE_FILE"

    else

        printf '%s' "$LICENSE_FALLBACK"

    fi
}


license_valid()
{
    LIC_FILE="$(license_file_path)"

    [ -s "$LIC_FILE" ] ||
        return 1

    LIC_DEVICE="$(sed -n 's/^device=//p' "$LIC_FILE" | head -n 1)"
    LIC_EXPIRE="$(sed -n 's/^expire=//p' "$LIC_FILE" | head -n 1)"

    case "$LIC_EXPIRE" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    # 绑定设备：对不上就作废
    if [ -n "$LIC_DEVICE" ] &&
       [ "$LIC_DEVICE" != "$(get_device_id)" ]; then

        return 1

    fi

    # 0 = 永久
    [ "$LIC_EXPIRE" -eq 0 ] &&
        return 0

    LIC_NOW="$(date +%s 2>/dev/null)"

    case "$LIC_NOW" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    [ "$LIC_NOW" -lt "$LIC_EXPIRE" ]
}


license_left()
{
    LIC_FILE="$(license_file_path)"

    LIC_EXPIRE="$(sed -n 's/^expire=//p' "$LIC_FILE" 2>/dev/null | head -n 1)"

    case "$LIC_EXPIRE" in
        ''|*[!0-9]*)
            printf '%s' "?"
            return 0
            ;;
    esac

    [ "$LIC_EXPIRE" -eq 0 ] && {

        printf '%s' "永久"
        return 0
    }

    LIC_NOW="$(date +%s 2>/dev/null)"

    case "$LIC_NOW" in
        ''|*[!0-9]*)
            printf '%s' "?"
            return 0
            ;;
    esac

    printf '%s' "$((LIC_EXPIRE - LIC_NOW)) 秒"
}


save_license()
{
    LIC_TOKEN="$1"
    LIC_EXPIRE="$2"

    [ -n "$LIC_EXPIRE" ] ||
        LIC_EXPIRE=0

    LIC_FILE="$(license_file_path)"

    {
        printf 'device=%s\n' "$(get_device_id)"
        printf 'token=%s\n' "$LIC_TOKEN"
        printf 'expire=%s\n' "$LIC_EXPIRE"

    } > "$LIC_FILE" 2>/dev/null ||
        return 1

    return 0
}


# ======================================
# HTTP
# ======================================

pay_post()
{
    curl \
        -fsS \
        --connect-timeout 5 \
        --max-time 15 \
        -X POST \
        --data "$2" \
        "$PAY_SERVER$1" \
        2>/dev/null
}


pay_get()
{
    curl \
        -fsS \
        --connect-timeout 5 \
        --max-time 15 \
        "$PAY_SERVER$1" \
        2>/dev/null
}


# ======================================
# 画二维码（终端里可扫）
#
# 用 qrencode 的半块字符输出（ANSIUTF8）；
# 本机没有就试着从软件源装一个（约 20KB）。
#
# 如果扫不出来（显示成反色），把 OPI_QR_TYPE 设成 ANSIUTF8i
# ======================================

render_qr()
{
    QR_TEXT="$1"
    QR_OUT="$2"
    QR_TYPE="${OPI_QR_TYPE:-ANSIUTF8}"

    [ -n "$QR_TEXT" ] ||
        return 1

    if command -v qrencode >/dev/null 2>&1; then

        qrencode -t "$QR_TYPE" -o "$QR_OUT" "$QR_TEXT" 2>/dev/null

        [ -s "$QR_OUT" ] &&
            return 0

    fi

    if ! command -v opkg >/dev/null 2>&1; then

        return 1

    fi

    _pay_info "正在准备二维码组件（qrencode）..."

    run_limited 60 opkg update >/dev/null 2>&1

    run_limited 60 opkg install qrencode >/dev/null 2>&1

    if command -v qrencode >/dev/null 2>&1; then

        qrencode -t "$QR_TYPE" -o "$QR_OUT" "$QR_TEXT" 2>/dev/null

        [ -s "$QR_OUT" ] &&
            return 0

    fi

    return 1
}


# ======================================
# 扫码付费主流程
#
# 返回 0 = 已付费并写入授权；1 = 没成功（交给验证码兜底）
# ======================================

pay_flow()
{
    DEVICE_ID="$(get_device_id)"


    # ----------------------------------
    # 支付方式（可多个时让用户选）
    #
    # OPI_PAY_CHANNELS 默认 "wxpay alipay"
    # 只想留一种就设成单个，例如 OPI_PAY_CHANNELS=wxpay
    # ----------------------------------

    PAY_CHOICES="${OPI_PAY_CHANNELS:-wxpay alipay}"

    PAY_COUNT=0

    for PAY_C in $PAY_CHOICES
    do
        PAY_COUNT=$((PAY_COUNT + 1))
    done

    PAY_CHANNEL=""

    if [ "$PAY_COUNT" -gt 1 ]; then

        printf "\n"
        printf "%b\n" "${CYAN}请选择支付方式：${RESET}"

        PAY_IDX=1

        for PAY_C in $PAY_CHOICES
        do

            case "$PAY_C" in
                wxpay)  PAY_CN="微信支付" ;;
                alipay) PAY_CN="支付宝" ;;
                *)      PAY_CN="$PAY_C" ;;
            esac

            if [ "$PAY_IDX" = "1" ]; then

                printf "%b\n" "  [$PAY_IDX] $PAY_CN   ${GREEN}（默认，直接回车）${RESET}"

            else

                printf "%b\n" "  [$PAY_IDX] $PAY_CN"

            fi

            PAY_IDX=$((PAY_IDX + 1))

        done

        printf "%b" "${YELLOW}选择 [1]（3 秒不选自动用微信支付）: ${RESET}"

        # read -t 有的 busybox 没编，超时或不可用时都按"直接回车"处理 → 默认微信
        read -t 3 PAY_PICK </dev/tty 2>/dev/null

        [ -n "$PAY_PICK" ] ||
            PAY_PICK=1

        PAY_IDX=1

        for PAY_C in $PAY_CHOICES
        do

            if [ "$PAY_PICK" = "$PAY_IDX" ]; then
                PAY_CHANNEL="$PAY_C"
            fi

            PAY_IDX=$((PAY_IDX + 1))

        done

    else

        PAY_CHANNEL="$PAY_CHOICES"

    fi


    _pay_info "正在创建支付订单..."

    ORDER_JSON="$(
        pay_post \
            "/order/create" \
            "device=$DEVICE_ID&version=1.0.0&channel=$PAY_CHANNEL"
    )"


    # 选中的渠道不可用？把列表里其它渠道再试一遍
    if [ -z "$ORDER_JSON" ] && [ "$PAY_COUNT" -gt 1 ]; then

        for PAY_C in $PAY_CHOICES
        do

            [ "$PAY_C" = "$PAY_CHANNEL" ] &&
                continue

            _pay_info "换个支付方式再试（$PAY_C）..."

            ORDER_JSON="$(
                pay_post \
                    "/order/create" \
                    "device=$DEVICE_ID&version=1.0.0&channel=$PAY_C"
            )"

            if [ -n "$ORDER_JSON" ]; then

                PAY_CHANNEL="$PAY_C"

                break

            fi

        done

    fi

    if [ -z "$ORDER_JSON" ]; then

        _pay_warn "支付服务暂时不可用"

        return 1

    fi

    POLL_TOKEN="$(json_str "$ORDER_JSON" poll_token)"
    ORDER_EXPIRE="$(json_num "$ORDER_JSON" expire_seconds)"
    ORDER_AMOUNT="$(json_str "$ORDER_JSON" amount)"
    ORDER_CHANNEL="$(json_str "$ORDER_JSON" channel_label)"

    [ -n "$ORDER_CHANNEL" ] ||
        ORDER_CHANNEL="$PAY_CHANNEL"

    if [ -z "$POLL_TOKEN" ]; then

        _pay_warn "订单创建失败"

        return 1

    fi

    [ -n "$ORDER_EXPIRE" ] ||
        ORDER_EXPIRE="$PAY_ORDER_TIMEOUT"

    [ "$ORDER_EXPIRE" -gt "$PAY_ORDER_TIMEOUT" ] &&
        ORDER_EXPIRE="$PAY_ORDER_TIMEOUT"

    [ -n "$ORDER_AMOUNT" ] ||
        ORDER_AMOUNT="?"


    # ----------------------------------
    # 二维码
    #
    # 优先用本机 qrencode 画（服务器就不必带二维码库）；
    # 本机没有就试着装；再不行让服务器渲染；最后退回纯链接。
    # ----------------------------------

    PAY_URL="$(json_str "$ORDER_JSON" pay_url)"

    rm -f "$PAY_QR_FILE"

    if [ -n "$PAY_URL" ]; then

        render_qr "$PAY_URL" "$PAY_QR_FILE"

    fi

    if [ ! -s "$PAY_QR_FILE" ]; then

        curl \
            -fsS \
            --connect-timeout 5 \
            --max-time 20 \
            "$PAY_SERVER/order/qr?token=$POLL_TOKEN" \
            -o "$PAY_QR_FILE" \
            2>/dev/null

    fi


    printf "\n"

    printf "%b\n" "${BLUE}╔══════════════════════════════════════╗${RESET}"
    printf "%b\n" "${BLUE}║${GREEN}        扫码支付后自动进入工具箱      ${BLUE}║${RESET}"
    printf "%b\n" "${BLUE}╚══════════════════════════════════════╝${RESET}"

    printf "\n"

    if [ -s "$PAY_QR_FILE" ]; then

        cat "$PAY_QR_FILE"

    elif [ -n "$PAY_URL" ]; then

        _pay_warn "二维码没画出来，用手机浏览器打开这个链接支付："

        printf "%s\n" "$PAY_URL"

    else

        _pay_warn "二维码获取失败"

    fi

    printf "\n"

    # 有效期按分钟显示（服务器给的是秒）
    case "$ORDER_EXPIRE" in
        ''|*[!0-9]*)
            ORDER_MIN=1
            ;;
        *)
            ORDER_MIN=$((ORDER_EXPIRE / 60))

            [ "$ORDER_MIN" -gt 0 ] ||
                ORDER_MIN=1
            ;;
    esac

    printf "%b\n" "${YELLOW}支付方式：${ORDER_CHANNEL}    金额：¥${ORDER_AMOUNT}    有效期：${ORDER_MIN} 分钟${RESET}"

    printf "%b\n" "${CYAN}支付完成后会自动继续，无需任何操作${RESET}"

    printf "\n"


    # ----------------------------------
    # 轮询
    # ----------------------------------

    PAY_CANCEL=""

    # 按 Ctrl+C 直接退出：清掉"等待支付中"那行，不打印任何其它提示
    trap 'trap - INT; printf "\r\033[2K"; exit 130' INT

    PAY_WAITED=0

    while [ "$PAY_WAITED" -lt "$ORDER_EXPIRE" ]
    do

        if [ -n "$PAY_CANCEL" ]; then

            break

        fi

        STATUS_JSON="$(pay_get "/order/status?token=$POLL_TOKEN")"

        STATUS="$(json_str "$STATUS_JSON" status)"

        case "$STATUS" in

            paid)

                LIC_TOKEN="$(json_str "$STATUS_JSON" license)"
                LIC_EXPIRE="$(json_num "$STATUS_JSON" license_expire)"

                trap - INT

                printf "\r\033[2K"

                # 服务器没给到期时间时，用本地配置兜底
                #（服务器给 0 表示永久，不要覆盖它）
                if [ -z "$LIC_EXPIRE" ]; then

                    if [ "$LICENSE_TTL" = "0" ]; then

                        LIC_EXPIRE=0

                    else

                        LIC_NOW="$(date +%s 2>/dev/null)"

                        case "$LIC_NOW" in
                            ''|*[!0-9]*)
                                LIC_NOW=0
                                ;;
                        esac

                        LIC_EXPIRE=$((LIC_NOW + LICENSE_TTL))

                    fi

                fi

                if save_license "$LIC_TOKEN" "$LIC_EXPIRE"; then

                    _pay_ok "支付成功，授权已保存"

                else

                    _pay_warn "支付成功，但授权文件写入失败（本次仍可继续）"

                fi

                if [ "$LICENSE_TTL" = "0" ]; then

                    printf "%b\n" "${CYAN}授权永久有效${RESET}"

                else

                    printf "%b\n" "${CYAN}授权有效期 $((LICENSE_TTL / 60)) 分钟：期间可重复运行，过期后需重新购买${RESET}"

                fi

                return 0

                ;;

            expired)

                trap - INT

                printf "\r\033[2K"

                _pay_warn "二维码已过期"

                return 1

                ;;

        esac

        printf "\r\033[2K${GREEN}[INFO]${RESET} 等待支付中... 剩余 %s 秒（按 Ctrl+C 取消）" \
            "$((ORDER_EXPIRE - PAY_WAITED))"

        sleep "$PAY_POLL_INTERVAL"

        PAY_WAITED=$((PAY_WAITED + PAY_POLL_INTERVAL))

    done

    trap - INT

    printf "\r\033[2K"

    _pay_warn "等待支付超时"

    return 1
}

# ======================================
# 扫码支付后进入
# ======================================

if license_valid; then

    _pay_ok "本地授权有效（剩余 $(license_left)），跳过支付"

else

    printf "\n"

    if ! pay_flow; then

        printf "\n"

        printf "%b\n" "${RED}[ERROR] 未完成支付，已退出${RESET}"

        printf "\n"

        exit 1

    fi

fi


# ======================================
# Prepare Workdir
# ======================================

step "2/6 准备临时目录"

rm -rf "$WORKDIR"

mkdir -p "$WORKDIR" || {

    printf "%b\n" "${RED}[ERROR] 无法创建临时目录${RESET}"

    exit 1
}


rm -f "$BOOTSTRAP_LOG"

REPO="https://auth.12334123.xyz/installer"
# ======================================
# Download Function
#
# 多源并行竞速：
#   多条线路同时下载，谁先拿到「完整可用」的 zip 就用谁，
#   其余立刻杀掉。不再为一个抖动 / 挂死的线路干等。
#
# 校验：非空 + PK 魔数 + unzip 能读出目录
#       （防止把 502 页面 / HTML 报错页当成 zip）
# ======================================

dl_is_zip()
{
    [ -s "$1" ] || return 1

    # zip 魔数 PK
    head -c 2 "$1" 2>/dev/null |
        grep -q 'PK' ||
        return 1

    # 必须是本项目归档：
    # 能读出目录清单，且里面有 install.sh
    # （顺便挡掉截断的包、HTML 错误页、别的 zip）
    unzip -l "$1" 2>/dev/null |
        grep -q 'Open-Pro-Installer-main/install.sh'
}


dl_one()
{
    DL_ONE_NAME="$1"
    DL_ONE_URL="$2"

    DL_ONE_OUT="$DL_DIR/$DL_ONE_NAME.zip"

    rm -f \
        "$DL_ONE_OUT" \
        "$DL_DIR/$DL_ONE_NAME.ok" \
        2>/dev/null

    if curl \
        -L \
        -f \
        -sS \
        --connect-timeout 8 \
        --max-time "$DL_DEADLINE" \
        -o "$DL_ONE_OUT" \
        "$DL_ONE_URL" \
        >>"$BOOTSTRAP_LOG" 2>&1
    then

        if dl_is_zip "$DL_ONE_OUT"; then

            printf 'ok\n' > "$DL_DIR/$DL_ONE_NAME.ok"

        fi

    fi
}


download_repo()
{
    DL_WIN=""

    rm -f "$ZIP_FILE"

    rm -rf "$DL_DIR"

    mkdir -p "$DL_DIR" ||
        return 1


    # ----------------------------------
    # 三路同时开跑
    # ----------------------------------

    DL_PIDS=""

    while IFS='|' read -r DL_NAME DL_URL
    do

        [ -n "$DL_NAME" ] ||
            continue

        [ -n "$DL_URL" ] ||
            continue

        dl_one "$DL_NAME" "$DL_URL" </dev/null &

        DL_PIDS="$DL_PIDS $!"

    done <<EOF
$DL_SOURCES
EOF


    # ----------------------------------
    # 等第一个可用结果
    #
    # 用计数器而不是 date 计时，避免设备没有 date +%s 时死循环
    # ----------------------------------

    DL_WAITED=0

    while : ; do

        DL_FOUND=0

        for DL_NAME in $DL_PRIORITY
        do

            # 判据1：下载器落的 .ok 标记（-f 判存在，
            # 千万不要用 -s 判非空，标记文件是空的）
            if [ -f "$DL_DIR/$DL_NAME.ok" ]; then

                DL_WIN="$DL_NAME"

                DL_FOUND=1

                break

            fi


            # 判据2：兜底，直接验一遍 zip 本身
            # （标记逻辑再出问题也不会卡在这里）
            if [ -f "$DL_DIR/$DL_NAME.zip" ] &&
               dl_is_zip "$DL_DIR/$DL_NAME.zip"; then

                DL_WIN="$DL_NAME"

                DL_FOUND=1

                break

            fi

        done

        [ "$DL_FOUND" = "1" ] &&
            break

        DL_WAITED=$((DL_WAITED + 1))

        if [ "$DL_WAITED" -ge "$((DL_DEADLINE + 10))" ]; then

            break

        fi

        sleep 1

    done


    # ----------------------------------
    # 收工：杀掉其余线路
    # ----------------------------------

    for DL_PID in $DL_PIDS
    do

        kill "$DL_PID" 2>/dev/null

    done

    for DL_PID in $DL_PIDS
    do

        wait "$DL_PID" 2>/dev/null

    done


    if [ -z "$DL_WIN" ]; then

        # 失败时把每条线路下了多少字节打出来，方便排查
        printf "%b\n" "${YELLOW}[INFO]${RESET} 各线路进度："

        for DL_F in "$DL_DIR"/*.zip
        do

            [ -f "$DL_F" ] ||
                continue

            DL_SZ="$(wc -c < "$DL_F" 2>/dev/null)"

            printf "%b\n" "${YELLOW}[INFO]${RESET}   ${DL_F##*/}  ${DL_SZ:-0} 字节"

        done

        rm -rf "$DL_DIR"

        return 1

    fi


    if ! mv -f "$DL_DIR/$DL_WIN.zip" "$ZIP_FILE"; then

        rm -rf "$DL_DIR"

        return 1

    fi

    rm -rf "$DL_DIR"

    return 0
}


# ======================================
# Download
# ======================================

step "3/6 正在下载项目文件（8 条线路并行竞速）"

spin_start

if ! download_repo
then

    spin_stop

    printf "\n"

    printf "%b\n" "${RED}[ERROR] 项目文件下载失败（已用 $(elapsed_sec)s）${RESET}"

    printf "%b\n" "${YELLOW}[INFO] 所有线路（服务器 / GitHub 直连 / GH01-GH06）都没拿到完整 zip${RESET}"

    printf "%b\n" "${YELLOW}[INFO] 请检查网络、DNS 或服务器连接${RESET}"

    if [ -s "$BOOTSTRAP_LOG" ]
    then

        printf "\n"
        printf "%b\n" "${RED}========== DOWNLOAD ERROR ==========${RESET}"

        tail -n 20 "$BOOTSTRAP_LOG"

        printf "%b\n" "${RED}====================================${RESET}"

    fi

    exit 1

fi

spin_stop

note "下载完成（线路 $DL_WIN，已用 $(elapsed_sec)s）"


# ======================================
# Check ZIP
# ======================================

if [ ! -s "$ZIP_FILE" ]
then

    printf "%b\n" "${RED}[ERROR] 下载文件为空${RESET}"

    exit 1

fi


# ======================================
# 文件大小
#
# 已隐藏
# ======================================

# FILE_SIZE="$(du -h "$ZIP_FILE" 2>/dev/null | awk '{print $1}')"
# printf "%b\n" "${GREEN}[INFO] 文件大小: ${FILE_SIZE:-未知}${RESET}"


# ======================================
# Extract
#
# "正在解压..." 已隐藏
# ======================================

step "4/6 正在解压项目文件"

spin_start

if ! run_limited 120 unzip -oq \
    "$ZIP_FILE" \
    -d "$WORKDIR" \
    >>"$BOOTSTRAP_LOG" 2>&1
then

    spin_stop

    printf "%b\n" "${RED}[ERROR] 解压失败（已用 $(elapsed_sec)s）${RESET}"

    printf "%b\n" "${YELLOW}[INFO] 下载文件可能不完整${RESET}"

    if [ -s "$BOOTSTRAP_LOG" ]
    then

        printf "\n"
        printf "%b\n" "${RED}========== EXTRACT ERROR ==========${RESET}"

        tail -n 20 "$BOOTSTRAP_LOG"

        printf "%b\n" "${RED}===================================${RESET}"

    fi

    exit 1

fi

spin_stop

note "解压完成（已用 $(elapsed_sec)s）"


# ======================================
# Check Installer
# ======================================

INSTALL_DIR="$WORKDIR/Open-Pro-Installer-main"


if [ ! -d "$INSTALL_DIR" ]
then

    printf "%b\n" "${RED}[ERROR] 项目目录不存在${RESET}"

    exit 1

fi


if [ ! -f "$INSTALL_DIR/install.sh" ]
then

    printf "%b\n" "${RED}[ERROR] install.sh 不存在${RESET}"

    exit 1

fi


# ======================================
# Permission
# ======================================

cd "$INSTALL_DIR" || {

    printf "%b\n" "${RED}[ERROR] 无法进入项目目录${RESET}"

    exit 1
}


chmod +x install.sh 2>/dev/null

chmod +x lib/*.sh 2>/dev/null

chmod +x modules/*.sh 2>/dev/null


# ======================================
# Clean ZIP
# ======================================

rm -f "$ZIP_FILE"


# ======================================
# Check LuCI Dependencies
#
# 关键修复：
#   原来 opkg update / opkg install 没有任何超时，
#   输出又全部丢进日志，软件源不通时就会
#   在 [AUTH] 正在验证... 之后静默卡几分钟甚至永久。
#
#   现在：
#     - 每一步都有提示和耗时
#     - 每条 opkg 命令都有硬超时
#     - 超时 / 失败只警告，不影响工具箱启动
# ======================================

opkg_installed()
{
    run_limited 20 opkg status "$1" 2>/dev/null |
        grep -q 'Status:.*installed'
}


check_luci_dependencies()
{

    # ----------------------------------
    # 手动跳过
    # ----------------------------------

    if [ "$SKIP_DEPS" = "1" ]
    then

        note "已通过 OPI_SKIP_DEPS=1 跳过 LuCI 依赖检查"

        return 0

    fi


    # ----------------------------------
    # 仅 OPKG 系统
    # ----------------------------------

    if ! command -v opkg >/dev/null 2>&1
    then

        note "非 opkg 系统，跳过 LuCI 依赖检查"

        return 0

    fi


    step "5/6 检查 LuCI 依赖"


    NEED_PACKAGES=""


    for PKG in luci-compat luci-lib-ipkg
    do

        if opkg_installed "$PKG"
        then

            continue

        fi

        NEED_PACKAGES="$NEED_PACKAGES $PKG"

    done


    # ----------------------------------
    # 已满足
    # ----------------------------------

    if [ -z "$NEED_PACKAGES" ]
    then

        note "LuCI 依赖已满足"

        return 0

    fi


    # printf "%b\n" "${CYAN}[INFO] 缺失:$NEED_PACKAGES（只影响 OpenClash，超时自动跳过，每条最多 ${OPKG_TIMEOUT}s）${RESET}"


    # ----------------------------------
    # 更新软件源（有超时）
    # ----------------------------------

    printf "%b" "${GREEN}[STEP]${RESET} 正在更新软件源 .. "

    spin_start

    run_limited "$OPKG_TIMEOUT" opkg update \
        >>"$BOOTSTRAP_LOG" 2>&1

    UPDATE_RC=$?

    spin_stop


    if [ "$UPDATE_RC" -ne 0 ]
    then

        warn "软件源更新失败或超时（最多 ${OPKG_TIMEOUT}s），跳过依赖安装"

        warn "这不影响工具箱启动，可稍后手动 opkg install"

        return 0

    fi

    note "软件源更新完成"


    # ----------------------------------
    # 安装缺失依赖（每条都有超时）
    # ----------------------------------

    for PKG in $NEED_PACKAGES
    do

        printf "%b" "${GREEN}[STEP]${RESET} 正在安装 $PKG .. "

        spin_start

        run_limited "$OPKG_TIMEOUT" opkg install "$PKG" \
            >>"$BOOTSTRAP_LOG" 2>&1

        INSTALL_RC=$?

        spin_stop


        if [ "$INSTALL_RC" -eq 0 ]
        then

            note "$PKG 安装完成"

        else

            warn "$PKG 安装失败或超时，已跳过"

        fi

    done


    return 0
}


# ======================================
# 项目准备完成
#
# 已隐藏
# ======================================

# printf "%b\n" "${GREEN}[SUCCESS] 项目准备完成${RESET}"


# ======================================
# Check LuCI Base Dependencies
# ======================================

check_luci_dependencies


# ======================================
# 清理 Bootstrap 日志
#
# 有失败/超时时保留日志，方便排查
# ======================================

if [ "$BOOTSTRAP_WARN" = "1" ]
then

    printf "%b\n" "${YELLOW}[INFO] 启动过程有警告，日志保留在：$BOOTSTRAP_LOG${RESET}"

else

    rm -f "$BOOTSTRAP_LOG" 2>/dev/null

fi


# ======================================
# Start ZIMO
#
# "正在启动 ZIMO--工具箱..."
# 已隐藏
# ======================================

# printf "%b\n" "${BLUE}[INFO] 正在启动 ZIMO--工具箱...${RESET}"

step "6/6 正在启动工具箱（启动总耗时 $(elapsed_sec)s）"

printf "\n"


# ======================================
# 直接进入主菜单
#
# 兼容 curl ... | sh 的调用方式：
#   脚本本身是从管道读进来的，stdin 已经耗尽，
#   这里把 stdin 接到 /dev/tty，
#   免得子模块里没写 </dev/tty 的 read 直接读到 EOF。
# ======================================

if [ -r /dev/tty ]; then

    exec ./install.sh </dev/tty

else

    exec ./install.sh

fi

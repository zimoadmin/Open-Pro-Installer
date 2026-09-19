#!/bin/sh

# ======================================
# Open-Pro-Installer Bootstrap
# BusyBox / OpenWrt Compatible
#
# 正常启动流程静默化版本
#
# 本版修复（针对 [AUTH] 正在验证... 之后长时间卡住无输出）：
#   1. 验证后的每个阶段都有可见进度（心跳点 + 耗时）
#   2. 下载 / 解压 / opkg 全部有硬超时，不再可能无限卡住
#   3. 出错或超时会打印原因，不再静默挂起
#   4. 失败时保留日志路径，方便排查
#   5. main.zip 改为 8 线路并行竞速
#      （自己的服务器 + GitHub 直连 + GH01-GH06 ghproxy 镜像，
#        谁先拿到完整可用的 zip 就用谁）
#   6. auth_post 去掉 curl -f
#      （服务端返回 4xx/5xx 时不再丢掉响应体，
#        失败原因会原样打印，不再一律谎报"连接超时"）
#
# 可用环境变量：
#   OPI_SKIP_DEPS=1   跳过 opkg 依赖检查（最快启动）
#   OPI_OPKG_TIMEOUT  单条 opkg 操作的超时秒数（默认 60）
# ======================================


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

REPO="https://auth.12334123.xyz/installer"

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
# Request Auth
# ======================================

printf "%b\n" "${GREEN}[AUTH] 正在申请授权...${RESET}"


AUTH_RESPONSE="$(
    auth_post \
        "/request" \
        ""
)"


if [ -z "$AUTH_RESPONSE" ]
then

    printf "%b\n" "${RED}[ERROR] 无法连接授权服务器${RESET}"
    printf "%b\n" "${YELLOW}[INFO] 已自动尝试 2 次，请稍后重试${RESET}"

    exit 1

fi


if ! printf "%s" "$AUTH_RESPONSE" |
    grep -q '"success"[[:space:]]*:[[:space:]]*true'
then

    printf "%b\n" "${RED}[ERROR] 申请验证码失败${RESET}"

    printf "%s\n" "$AUTH_RESPONSE"

    exit 1

fi


printf "%b\n" "${GREEN}[AUTH] 验证码已发送给管理员${RESET}"

printf "\n"


# ======================================
# Input Code
# ======================================

printf "%b" "${YELLOW}请输入验证码: ${RESET}" >/dev/tty

IFS= read -r AUTH_CODE </dev/tty


if [ -z "$AUTH_CODE" ]
then

    printf "%b\n" "${RED}[ERROR] 验证码不能为空${RESET}"

    exit 1

fi


case "$AUTH_CODE" in

    [0-9][0-9][0-9][0-9][0-9][0-9])

        ;;

    *)

        printf "%b\n" "${RED}[ERROR] 验证码必须是6位数字${RESET}"

        exit 1

        ;;

esac


printf "\n"

printf "%b\n" "${GREEN}[AUTH] 正在验证...${RESET}"


# ======================================
# Verify
# ======================================

VERIFY_DATA="$(
    printf '{"code":"%s"}' "$AUTH_CODE"
)"


# 这一行原来之后完全没有提示，
# 现在一边请求一边打点，最长等待约 24 秒
spin_start

VERIFY_RESPONSE="$(
    auth_post \
        "/verify" \
        "$VERIFY_DATA"
)"

spin_stop


if [ -z "$VERIFY_RESPONSE" ]
then

    printf "%b\n" "${RED}[ERROR] 授权服务器连接超时${RESET}"
    printf "%b\n" "${YELLOW}[INFO] 已自动尝试 2 次，请重新运行${RESET}"

    exit 1

fi


if printf '%s' "$VERIFY_RESPONSE" |
   grep -q '"success"[[:space:]]*:[[:space:]]*true'
then

    # ==================================
    # 授权成功
    #
    # 原来的：
    # [AUTH] 授权成功
    #
    # 已隐藏
    # ==================================

    :

else

    printf "%b\n" "${RED}[ERROR] 授权失败${RESET}"

    printf "%s\n" "$VERIFY_RESPONSE"

    exit 1

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

            : > "$DL_DIR/$DL_ONE_NAME.ok"

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

            if [ -s "$DL_DIR/$DL_NAME.ok" ]; then

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


    printf "%b\n" "${CYAN}[INFO] 缺失:$NEED_PACKAGES（只影响 OpenClash，超时自动跳过，每条最多 ${OPKG_TIMEOUT}s）${RESET}"


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

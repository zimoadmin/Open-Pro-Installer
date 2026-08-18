#!/bin/sh

# ============================================================
# Open-Pro-Installer
# Smart GitHub Accelerator
#
# 流程：
# 1. 获取 github.akams.cn 页面
# 2. 自动寻找 Next.js JS chunks
# 3. 提取 contribute GitHub Proxy 节点
# 4. 加入 GitHub 直连
# 5. 使用 bootstrap.sh 实际测速
# 6. 自动选择最快可用节点
# 7. 下载 bootstrap.sh
# 8. 验证内容
# 9. 执行 bootstrap.sh
# ============================================================


# ============================================================
# Config
# ============================================================

RAW="https://raw.githubusercontent.com/zimoadmin/Open-Pro-Installer/main/bootstrap.sh"

AKAMS="https://github.akams.cn"

TMP="/tmp/openpro-bootstrap.sh"

HTML_FILE="/tmp/openpro-akams.html"
CHUNK_LIST="/tmp/openpro-chunks.list"
NODE_FILE="/tmp/openpro-nodes.list"

BEST_FILE="/tmp/openpro-best"
RESULT_FILE="/tmp/openpro-results"

TEST_DIR="/tmp/openpro-speedtest"

MAX_NODES=60

CONNECT_TIMEOUT=3
TEST_TIMEOUT=7

PARALLEL=6


# ============================================================
# Color
# ============================================================

GREEN="\033[32m"
BLUE="\033[34m"
CYAN="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"


# ============================================================
# Log
# ============================================================

info()
{
    printf "%b\n" "${GREEN}[INFO]${RESET} $*"
}


ok()
{
    printf "%b\n" "${GREEN}[OK]${RESET} $*"
}


warn()
{
    printf "%b\n" "${YELLOW}[WARN]${RESET} $*"
}


error()
{
    printf "%b\n" "${RED}[ERROR]${RESET} $*"
}


# ============================================================
# Cleanup
# ============================================================

cleanup_start()
{
    rm -f "$HTML_FILE"
    rm -f "$CHUNK_LIST"
    rm -f "$NODE_FILE"
    rm -f "$BEST_FILE"
    rm -f "$RESULT_FILE"

    rm -rf "$TEST_DIR"
}


# ============================================================
# Check curl
# ============================================================

if ! command -v curl >/dev/null 2>&1
then

    error "当前系统缺少 curl"

    exit 1

fi


cleanup_start

rm -f "$TMP"

mkdir -p "$TEST_DIR"


# ============================================================
# 获取 github.akams.cn 首页
# ============================================================

info "正在获取 GitHub 加速节点..."


if curl -4 \
    -L \
    -fsS \
    --connect-timeout 5 \
    --max-time 15 \
    -o "$HTML_FILE" \
    "$AKAMS/"
then

    AKAMS_OK=1

else

    AKAMS_OK=0

    warn "github.akams.cn 获取失败"

fi


# ============================================================
# 初始化节点列表
# ============================================================

: > "$NODE_FILE"


# GitHub 直连永远加入

printf 'DIRECT|\n' >> "$NODE_FILE"


# ============================================================
# 自动寻找 JS Chunk
# ============================================================

if [ "$AKAMS_OK" -eq 1 ]
then

    info "正在解析节点数据库..."


    # --------------------------------------------------------
    # 提取：
    #
    # /_next/static/chunks/xxxx.js
    #
    # --------------------------------------------------------

    grep -oE '/_next/static/[^"]+\.js' \
        "$HTML_FILE" 2>/dev/null |
        sed 's/&amp;/\&/g' |
        sort -u \
        > "$CHUNK_LIST"


    CHUNK_COUNT="$(
        wc -l < "$CHUNK_LIST" 2>/dev/null |
        tr -d ' '
    )"


    [ -n "$CHUNK_COUNT" ] ||
        CHUNK_COUNT=0


    info "发现 ${CHUNK_COUNT} 个网页组件"


    # ========================================================
    # 下载每个 JS 并寻找 contribute 节点
    # ========================================================

    CHUNK_INDEX=0


    while IFS= read -r CHUNK
    do

        [ -n "$CHUNK" ] || continue


        CHUNK_INDEX=$((CHUNK_INDEX + 1))


        JS_FILE="$TEST_DIR/chunk_${CHUNK_INDEX}.js"


        if ! curl -4 \
            -L \
            -fsS \
            --connect-timeout 3 \
            --max-time 10 \
            -o "$JS_FILE" \
            "${AKAMS}${CHUNK}"
        then

            rm -f "$JS_FILE"

            continue

        fi


        # ====================================================
        # 提取这种结构：
        #
        # label:"contribute",value:"gh.xxx.com"
        #
        # 同时兼容一定程度的空格
        # ====================================================

        grep -oE \
            'label:[[:space:]]*"contribute"[[:space:]]*,[[:space:]]*value:[[:space:]]*"[^"]+"' \
            "$JS_FILE" 2>/dev/null |
            sed -n \
            's/.*value:[[:space:]]*"\([^"]*\)".*/\1/p' |
            while IFS= read -r NODE
            do

                [ -n "$NODE" ] || continue


                # ------------------------------------------------
                # 去除协议
                # ------------------------------------------------

                NODE="$(
                    printf '%s' "$NODE" |
                    sed \
                        -e 's#^https://##' \
                        -e 's#^http://##' \
                        -e 's#/*$##'
                )"


                [ -n "$NODE" ] || continue


                # ------------------------------------------------
                # 基本域名过滤
                # ------------------------------------------------

                case "$NODE" in

                    *.*)

                        printf '%s\n' "$NODE"

                        ;;

                esac

            done \
            >> "$TEST_DIR/nodes.tmp"


        rm -f "$JS_FILE"

    done < "$CHUNK_LIST"


    # ========================================================
    # 去重
    # ========================================================

    if [ -s "$TEST_DIR/nodes.tmp" ]
    then

        sort -u "$TEST_DIR/nodes.tmp" |
        head -n "$MAX_NODES" |
        while IFS= read -r NODE
        do

            [ -n "$NODE" ] || continue

            printf '%s|https://%s/\n' \
                "$NODE" \
                "$NODE"

        done \
        >> "$NODE_FILE"

    fi

fi


# ============================================================
# 备用节点
#
# github.akams.cn 结构变化或抓取失败时仍能使用
# ============================================================

cat >> "$NODE_FILE" <<'EOF'
ghproxy.net|https://ghproxy.net/
gh.inkchills.cn|https://gh.inkchills.cn/
EOF


# ============================================================
# 最终去重
# ============================================================

awk -F '|' '
    !seen[$1]++ {
        print
    }
' "$NODE_FILE" \
> "$NODE_FILE.tmp"


mv "$NODE_FILE.tmp" "$NODE_FILE"


NODE_COUNT="$(
    wc -l < "$NODE_FILE" 2>/dev/null |
    tr -d ' '
)"


[ -n "$NODE_COUNT" ] ||
    NODE_COUNT=0


ok "获取到 ${NODE_COUNT} 条候选线路"

printf "\n"


# ============================================================
# 单节点测速函数
# ============================================================

test_node()
{
    INDEX="$1"
    NAME="$2"
    PREFIX="$3"


    if [ "$NAME" = "DIRECT" ]
    then

        URL="$RAW"

    else

        URL="${PREFIX}${RAW}"

    fi


    TEST_FILE="$TEST_DIR/test_${INDEX}.sh"
    OUT_FILE="$TEST_DIR/result_${INDEX}"


    rm -f "$TEST_FILE" "$OUT_FILE"


    TIME="$(
        curl -4 \
            -L \
            -fsS \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$TEST_TIMEOUT" \
            -o "$TEST_FILE" \
            -w '%{time_total}' \
            "$URL" \
            2>/dev/null
    )"


    CURL_RESULT=$?


    if [ "$CURL_RESULT" -ne 0 ] ||
       [ ! -s "$TEST_FILE" ]
    then

        printf '%s|%s|FAIL|\n' \
            "$INDEX" \
            "$NAME" \
            > "$OUT_FILE"

        rm -f "$TEST_FILE"

        return

    fi


    # ========================================================
    # 防止代理返回：
    #
    # HTML
    # Cloudflare 错误页
    # 登录页
    # 广告页
    # ========================================================

    if ! grep -q \
        'Open-Pro-Installer' \
        "$TEST_FILE" 2>/dev/null
    then

        printf '%s|%s|INVALID|\n' \
            "$INDEX" \
            "$NAME" \
            > "$OUT_FILE"

        rm -f "$TEST_FILE"

        return

    fi


    # ========================================================
    # 秒 → 毫秒
    # ========================================================

    MS="$(
        awk -v t="$TIME" \
        'BEGIN {
            printf "%d", t * 1000
        }'
    )"


    printf '%s|%s|%s|%s\n' \
        "$INDEX" \
        "$NAME" \
        "$MS" \
        "$URL" \
        > "$OUT_FILE"


    rm -f "$TEST_FILE"
}


# ============================================================
# 开始测速
# ============================================================

info "正在测速 GitHub 下载线路..."

printf "\n"


INDEX=0
RUNNING=0


while IFS='|' read -r NAME PREFIX
do

    [ -n "$NAME" ] || continue


    INDEX=$((INDEX + 1))


    test_node \
        "$INDEX" \
        "$NAME" \
        "$PREFIX" &


    RUNNING=$((RUNNING + 1))


    # --------------------------------------------------------
    # 限制并发
    # 防止低配路由器同时开几十个 curl
    # --------------------------------------------------------

    if [ "$RUNNING" -ge "$PARALLEL" ]
    then

        wait

        RUNNING=0

    fi

done < "$NODE_FILE"


wait


# ============================================================
# 汇总测速结果
# ============================================================

: > "$RESULT_FILE"


INDEX=1


while [ "$INDEX" -le "$NODE_COUNT" ]
do

    RESULT="$TEST_DIR/result_${INDEX}"


    if [ -f "$RESULT" ]
    then

        cat "$RESULT" >> "$RESULT_FILE"

    fi


    INDEX=$((INDEX + 1))

done


# ============================================================
# 显示结果
# ============================================================

while IFS='|' read -r IDX NAME STATUS URL
do

    printf '  [%02d] %-30s ' \
        "$IDX" \
        "$NAME"


    case "$STATUS" in

        FAIL)

            printf "%b\n" "${RED}失败${RESET}"

            ;;


        INVALID)

            printf "%b\n" "${RED}无效${RESET}"

            ;;


        *)

            printf "%b\n" "${GREEN}${STATUS} ms${RESET}"

            ;;

    esac

done < "$RESULT_FILE"


# ============================================================
# 选择最快节点
# ============================================================

awk -F '|' '
    $3 ~ /^[0-9]+$/ {
        print $3 "|" $2 "|" $4
    }
' "$RESULT_FILE" |
sort -t '|' -k1,1n \
> "$BEST_FILE"


# ============================================================
# 没有可用节点
# ============================================================

if [ ! -s "$BEST_FILE" ]
then

    printf "\n"

    error "没有可用的 GitHub 下载线路"

    cleanup_start

    exit 1

fi


BEST_MS="$(sed -n '1{s/|.*//;p}' "$BEST_FILE")"

BEST_NAME="$(
    sed -n '1{
        s/^[^|]*|//
        s/|.*//
        p
    }' "$BEST_FILE"
)"

BEST_URL="$(
    sed -n '1{
        s/^[^|]*|[^|]*|//
        p
    }' "$BEST_FILE"
)"


printf "\n"

ok "最快线路：$BEST_NAME"

info "耗时：${BEST_MS} ms"

printf "\n"


# ============================================================
# 下载 bootstrap.sh
# ============================================================

info "正在下载 bootstrap.sh..."


if ! curl -4 \
    -L \
    -fsS \
    --connect-timeout 5 \
    --max-time 30 \
    -o "$TMP" \
    "$BEST_URL"
then

    error "bootstrap.sh 下载失败"

    rm -f "$TMP"

    cleanup_start

    exit 1

fi


# ============================================================
# 验证文件
# ============================================================

if [ ! -s "$TMP" ]
then

    error "bootstrap.sh 文件为空"

    cleanup_start

    exit 1

fi


if ! grep -q \
    'Open-Pro-Installer' \
    "$TMP" 2>/dev/null
then

    error "bootstrap.sh 内容验证失败"

    rm -f "$TMP"

    cleanup_start

    exit 1

fi


ok "bootstrap.sh 下载完成"


# ============================================================
# 清理测速数据
# ============================================================

cleanup_start


printf "\n"


# ============================================================
# 启动 bootstrap.sh
# ============================================================

exec sh "$TMP"

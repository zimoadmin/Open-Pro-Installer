#!/bin/sh

RAW="https://raw.githubusercontent.com/zimoadmin/Open-Pro-Installer/main/bootstrap.sh"

TMP="/tmp/openpro-bootstrap.sh"
BEST_FILE="/tmp/openpro-best"
TEST_FILE="/tmp/openpro-test"

rm -f "$TMP" "$BEST_FILE" "$TEST_FILE"

# ============================================================
# GitHub 下载线路
# DIRECT = GitHub 直连
# 其他 = GitHub Proxy
# ============================================================

NODES="
DIRECT|
GH01|https://ghproxy.net/
GH02|https://ghproxy.1888866.xyz/
GH03|https://gh.api.99988866.xyz/
"


printf '\033[32m[INFO]\033[0m 正在测速 GitHub 下载线路...\n'
printf '\n'


# ============================================================
# 测速
# ============================================================

printf '%s\n' "$NODES" |
while IFS='|' read -r NAME PREFIX
do

    [ -n "$NAME" ] || continue


    if [ "$NAME" = "DIRECT" ]; then
        URL="$RAW"
    else
        URL="${PREFIX}${RAW}"
    fi


    printf '  %-8s ' "$NAME"


    TIME="$(
        curl -4 \
            -L \
            -fsS \
            --connect-timeout 3 \
            --max-time 6 \
            -o "$TEST_FILE" \
            -w '%{time_total}' \
            "$URL" \
            2>/dev/null
    )"


    RESULT=$?


    if [ "$RESULT" -ne 0 ] || [ ! -s "$TEST_FILE" ]; then

        printf '\033[31m失败\033[0m\n'

        continue

    fi


    # 防止代理返回 HTML 页面
    if ! grep -q 'Open-Pro-Installer' "$TEST_FILE" 2>/dev/null; then

        printf '\033[31m无效\033[0m\n'

        continue

    fi


    MS="$(
        awk -v t="$TIME" \
        'BEGIN { printf "%d", t * 1000 }'
    )"


    printf '\033[32m%s ms\033[0m\n' "$MS"


    # --------------------------------------------------------
    # 当前最快节点
    # --------------------------------------------------------

    OLD_MS="$(
        cut -d '|' -f 1 "$BEST_FILE" 2>/dev/null
    )"


    [ -n "$OLD_MS" ] || OLD_MS=999999999


    if [ "$MS" -lt "$OLD_MS" ]; then

        printf '%s|%s|%s\n' \
            "$MS" \
            "$NAME" \
            "$URL" \
            > "$BEST_FILE"

    fi

done


rm -f "$TEST_FILE"


# ============================================================
# 获取最快节点
# ============================================================

if [ ! -s "$BEST_FILE" ]; then

    printf '\n'
    printf '\033[31m[ERROR]\033[0m 没有可用的 GitHub 下载线路\n'

    exit 1

fi


BEST_MS="$(cut -d '|' -f 1 "$BEST_FILE")"
BEST_NAME="$(cut -d '|' -f 2 "$BEST_FILE")"
BEST_URL="$(cut -d '|' -f 3- "$BEST_FILE")"


rm -f "$BEST_FILE"


printf '\n'

printf '\033[32m[OK]\033[0m 最快线路：%s\n' "$BEST_NAME"

printf '\033[32m[INFO]\033[0m 延迟：%s ms\n' "$BEST_MS"

printf '\033[32m[INFO]\033[0m 正在下载 ZIMO--工具箱...\n'


# ============================================================
# 使用最快节点下载 bootstrap.sh
# ============================================================

if ! curl -4 \
    -L \
    -fsS \
    --connect-timeout 5 \
    --max-time 30 \
    -o "$TMP" \
    "$BEST_URL"
then

    printf '\033[31m[ERROR]\033[0m bootstrap.sh 下载失败\n'

    rm -f "$TMP"

    exit 1

fi


# ============================================================
# 验证
# ============================================================

if [ ! -s "$TMP" ]; then

    printf '\033[31m[ERROR]\033[0m bootstrap.sh 文件为空\n'

    exit 1

fi


if ! grep -q 'Open-Pro-Installer' "$TMP" 2>/dev/null; then

    printf '\033[31m[ERROR]\033[0m 下载内容异常\n'

    rm -f "$TMP"

    exit 1

fi


printf '\033[32m[OK]\033[0m 下载完成\n'

printf '\n'


# ============================================================
# 启动真正的 bootstrap.sh
# ============================================================

exec sh "$TMP"

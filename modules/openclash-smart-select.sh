#!/bin/sh

# ============================================================
# OpenClash Smart Select V2.5
#
# 功能：
# 1. 自动识别「节点选择」Selector
# 2. 自动识别主「智能优选」Selector
# 3. 自动识别「智能优选1~5」Selector
# 4. 优先使用「增强选择」URLTest
# 5. 无增强选择则使用「自动选择」URLTest
# 6. 批量测试全部真实节点延迟
# 7. 取延迟最低前 15
# 8. 串行真实下载测速
# 9. 每节点目标下载 10MB
# 10. 单节点最长测速 10 秒
# 11. 10 秒超时但已下载 >=1MB 仍参与评分
# 12. 速度 70% + 延迟 30% 综合评分
# 13. 主智能优选提升 >=15% 才切换
# 14. 综合前5名自动分配给 智能优选1~5
# 15. 自动识别 OpenClash 本地代理认证
# 16. 测速期间临时 GLOBAL → 智能优选
# 17. 测速完成自动恢复 GLOBAL / 模式 / 智能优选
#
# OpenWrt / BusyBox / ash Compatible
# ============================================================


# ============================================================
# 参数
# ============================================================

TOP_N="${TOP_N:-15}"

SPEED_BYTES="${SPEED_BYTES:-10000000}"

SPEED_TIMEOUT="${SPEED_TIMEOUT:-10}"

MIN_VALID_BYTES="${MIN_VALID_BYTES:-1000000}"

SWITCH_THRESHOLD="${SWITCH_THRESHOLD:-15}"

MAX_DELAY="${MAX_DELAY:-800}"

DELAY_URL="${DELAY_URL:-https://www.gstatic.com/generate_204}"

DELAY_TIMEOUT="${DELAY_TIMEOUT:-5000}"

SPEED_URL="${SPEED_URL:-}"

LB_SLOT_COUNT="${LB_SLOT_COUNT:-5}"


# ============================================================
# 策略组关键词
# ============================================================

MAIN_KEYWORD="${MAIN_KEYWORD:-节点选择}"

TARGET_KEYWORD="${TARGET_KEYWORD:-智能优选}"

SOURCE_PRIMARY_KEYWORD="${SOURCE_PRIMARY_KEYWORD:-增强选择}"

SOURCE_FALLBACK_KEYWORD="${SOURCE_FALLBACK_KEYWORD:-自动选择}"


# ============================================================
# 颜色
# ============================================================

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[36m"
PURPLE="\033[35m"
CYAN="\033[36m"
RESET="\033[0m"

TAB="$(printf '\t')"


# ============================================================
# 状态
# ============================================================

API=""
SECRET=""

PROXIES_JSON=""
CONFIG_JSON=""

MAIN_GROUP=""
TARGET_GROUP=""
SOURCE_GROUP=""

LB_GROUP_1=""
LB_GROUP_2=""
LB_GROUP_3=""
LB_GROUP_4=""
LB_GROUP_5=""

LB_AVAILABLE=0

CURRENT_MAIN_SELECTION=""
CURRENT_TARGET_SELECTION=""
CURRENT_EFFECTIVE_NODE=""

ORIGINAL_MODE=""
ORIGINAL_GLOBAL_SELECTION=""
ORIGINAL_TARGET_SELECTION=""

LOCAL_PROXY=""

PROXY_AUTH_ENABLED="0"
PROXY_USER=""
PROXY_PASS=""
PROXY_AUTH=""

TMP_DIR=""
LOCK_DIR="/tmp/openclash-smart-select.lock"

TEST_STATE_DIRTY=0
CLEANED=0
PKG_UPDATED=0


# ============================================================
# UI
# ============================================================

line() {
    printf "${BLUE}============================================================${RESET}\n"
}

subline() {
    printf "${BLUE}------------------------------------------------------------${RESET}\n"
}

info() {
    printf "${CYAN}[INFO] %s${RESET}\n" "$1"
}

success() {
    printf "${GREEN}[OK] %s${RESET}\n" "$1"
}

warn() {
    printf "${YELLOW}[WARN] %s${RESET}\n" "$1"
}

error() {
    printf "${RED}[ERROR] %s${RESET}\n" "$1"
}

die() {
    printf "\n${RED}[ERROR] %s${RESET}\n" "$1"
    exit 1
}


# ============================================================
# 正整数检查
# ============================================================

valid_positive_integer() {

    VALUE="$1"
    DEFAULT="$2"

    case "$VALUE" in

        ''|*[!0-9]*)

            printf '%s\n' "$DEFAULT"

            ;;

        *)

            if [ "$VALUE" -gt 0 ] 2>/dev/null; then

                printf '%s\n' "$VALUE"

            else

                printf '%s\n' "$DEFAULT"

            fi

            ;;

    esac
}


TOP_N="$(valid_positive_integer "$TOP_N" 15)"

SPEED_BYTES="$(valid_positive_integer "$SPEED_BYTES" 10000000)"

SPEED_TIMEOUT="$(valid_positive_integer "$SPEED_TIMEOUT" 10)"

MIN_VALID_BYTES="$(valid_positive_integer "$MIN_VALID_BYTES" 1000000)"

SWITCH_THRESHOLD="$(valid_positive_integer "$SWITCH_THRESHOLD" 15)"

MAX_DELAY="$(valid_positive_integer "$MAX_DELAY" 800)"

DELAY_TIMEOUT="$(valid_positive_integer "$DELAY_TIMEOUT" 5000)"

LB_SLOT_COUNT="$(valid_positive_integer "$LB_SLOT_COUNT" 5)"

[ "$LB_SLOT_COUNT" -gt 5 ] && LB_SLOT_COUNT=5


if [ -z "$SPEED_URL" ]; then

    SPEED_URL="https://speed.cloudflare.com/__down?bytes=${SPEED_BYTES}"

fi


SPEED_MB=$((SPEED_BYTES / 1000000))

[ "$SPEED_MB" -le 0 ] && SPEED_MB=1


MIN_VALID_MB=$((MIN_VALID_BYTES / 1000000))

[ "$MIN_VALID_MB" -le 0 ] && MIN_VALID_MB=1


# ============================================================
# 软件依赖
# ============================================================

update_packages() {

    [ "$PKG_UPDATED" = "1" ] && return 0


    if command -v opkg >/dev/null 2>&1; then

        opkg update >/dev/null 2>&1 || true

    elif command -v apk >/dev/null 2>&1; then

        apk update >/dev/null 2>&1 || true

    fi


    PKG_UPDATED=1
}


install_package() {

    PKG="$1"

    update_packages


    if command -v opkg >/dev/null 2>&1; then

        opkg install "$PKG" >/dev/null 2>&1

        return $?

    fi


    if command -v apk >/dev/null 2>&1; then

        apk add "$PKG" >/dev/null 2>&1

        return $?

    fi


    return 1
}


ensure_dependency() {

    CMD="$1"
    PKG="$2"


    command -v "$CMD" >/dev/null 2>&1 &&
        return 0


    info "正在安装 ${PKG}..."


    install_package "$PKG" ||
        die "${PKG} 安装失败"


    command -v "$CMD" >/dev/null 2>&1 ||
        die "找不到 ${CMD}"
}


# ============================================================
# API
# ============================================================

api_curl() {

    if [ -n "$SECRET" ]; then

        curl \
            -H "Authorization: Bearer ${SECRET}" \
            "$@"

    else

        curl "$@"

    fi
}


urlencode() {

    printf '%s' "$1" |
        jq -sRr @uri
}


detect_api() {

    SECRET="${OPENCLASH_SECRET:-$(uci -q get openclash.config.dashboard_password 2>/dev/null)}"


    if [ -n "${OPENCLASH_API:-}" ]; then

        API="${OPENCLASH_API%/}"


        if api_curl \
            -fsS \
            --connect-timeout 2 \
            --max-time 4 \
            "${API}/proxies" \
            >/dev/null 2>&1
        then

            return 0

        fi

    fi


    PORT1="$(uci -q get openclash.config.cn_port 2>/dev/null)"

    PORT2="$(uci -q get openclash.config.dashboard_port 2>/dev/null)"


    CHECKED=""


    for PORT in \
        "$PORT1" \
        "$PORT2" \
        9090 \
        9091
    do

        [ -z "$PORT" ] && continue


        case "$PORT" in

            *[!0-9]*)

                continue

                ;;

        esac


        case " $CHECKED " in

            *" $PORT "*)

                continue

                ;;

        esac


        CHECKED="$CHECKED $PORT"


        API="http://127.0.0.1:${PORT}"


        if api_curl \
            -fsS \
            --connect-timeout 2 \
            --max-time 4 \
            "${API}/proxies" \
            >/dev/null 2>&1
        then

            return 0

        fi

    done


    return 1
}


select_proxy() {

    GROUP="$1"
    NODE="$2"


    GROUP_ENC="$(urlencode "$GROUP")"


    BODY="$(jq -nc \
        --arg name "$NODE" \
        '{name:$name}')"


    api_curl \
        -fsS \
        --connect-timeout 3 \
        --max-time 8 \
        -X PUT \
        -H "Content-Type: application/json" \
        -d "$BODY" \
        "${API}/proxies/${GROUP_ENC}" \
        >/dev/null 2>&1
}


set_mode() {

    MODE="$1"


    BODY="$(jq -nc \
        --arg mode "$MODE" \
        '{mode:$mode}')"


    api_curl \
        -fsS \
        --connect-timeout 3 \
        --max-time 8 \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "$BODY" \
        "${API}/configs" \
        >/dev/null 2>&1
}


# ============================================================
# 普通 Selector 查找
# ============================================================

find_selector_group() {

    KEYWORD="$1"


    printf '%s' "$PROXIES_JSON" |
    jq -r \
        --arg keyword "$KEYWORD" '
        .proxies
        | to_entries[]
        | select(
            (.key | contains($keyword))
            and
            ((.value.type // "" | ascii_downcase) == "selector")
        )
        | .key
        ' |
    head -n 1
}


# ============================================================
# 主智能优选
#
# 排除：
# 智能优选1
# 智能优选2
# ...
# ============================================================

find_main_target_group() {

    printf '%s' "$PROXIES_JSON" |
    jq -r \
        --arg keyword "$TARGET_KEYWORD" '
        .proxies
        | to_entries[]
        | select(
            (.key | contains($keyword))
            and
            ((.value.type // "" | ascii_downcase) == "selector")
            and
            (
                (
                    .key
                    | test("智能优选[0-9]+$")
                )
                | not
            )
        )
        | .key
        ' |
    head -n 1
}

# ============================================================
# 智能优选1~5
# ============================================================

find_lb_slot_group() {

    SLOT="$1"

    SLOT_KEYWORD="智能优选${SLOT}"


    printf '%s' "$PROXIES_JSON" |
    jq -r \
        --arg keyword "$SLOT_KEYWORD" '
        .proxies
        | to_entries[]
        | select(
            (.key | contains($keyword))
            and
            ((.value.type // "" | ascii_downcase) == "selector")
        )
        | .key
        ' |
    head -n 1
}


# ============================================================
# URLTest
# ============================================================

find_urltest_group() {

    KEYWORD="$1"


    printf '%s' "$PROXIES_JSON" |
    jq -r \
        --arg keyword "$KEYWORD" '
        .proxies
        | to_entries[]
        | select(
            (.key | contains($keyword))
            and
            ((.value.type // "" | ascii_downcase) == "urltest")
        )
        | .key
        ' |
    head -n 1
}


# ============================================================
# 检查 Selector 是否包含节点
# ============================================================

group_has_node() {

    GROUP="$1"
    NODE="$2"


    printf '%s' "$PROXIES_JSON" |
    jq -r \
        --arg group "$GROUP" \
        --arg node "$NODE" '
        if (
            ((.proxies[$group].all // []) | index($node))
            != null
        )
        then
            1
        else
            0
        end
        '
}


# ============================================================
# 解析当前实际节点
# ============================================================

resolve_leaf() {

    CURRENT="$1"

    DEPTH=0


    while [ "$DEPTH" -lt 15 ]; do

        TYPE="$(printf '%s' "$PROXIES_JSON" |
            jq -r \
                --arg n "$CURRENT" \
                '.proxies[$n].type // empty')"


        NOW="$(printf '%s' "$PROXIES_JSON" |
            jq -r \
                --arg n "$CURRENT" \
                '.proxies[$n].now // empty')"


        TYPE_LOWER="$(printf '%s' "$TYPE" |
            tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')"


        case "$TYPE_LOWER" in

            selector|urltest|fallback|loadbalance|relay)

                [ -z "$NOW" ] && break

                [ "$NOW" = "$CURRENT" ] && break

                CURRENT="$NOW"

                ;;

            *)

                break

                ;;

        esac


        DEPTH=$((DEPTH + 1))

    done


    printf '%s\n' "$CURRENT"
}


# ============================================================
# OpenClash 本地代理认证
# ============================================================

detect_proxy_auth() {

    PROXY_AUTH_ENABLED="$(
        uci -q get 'openclash.@authentication[0].enabled' \
            2>/dev/null
    )"


    PROXY_USER="$(
        uci -q get 'openclash.@authentication[0].username' \
            2>/dev/null
    )"


    PROXY_PASS="$(
        uci -q get 'openclash.@authentication[0].password' \
            2>/dev/null
    )"


    if [ "$PROXY_AUTH_ENABLED" = "1" ] &&
       [ -n "$PROXY_USER" ]
    then

        PROXY_AUTH="${PROXY_USER}:${PROXY_PASS}"

        return 0

    fi


    PROXY_AUTH_ENABLED="0"

    PROXY_AUTH=""


    return 0
}


# ============================================================
# 真实下载测速
#
# 输出：
# HTTP<TAB>SIZE<TAB>SPEED
# ============================================================

speed_download() {

    URL="$1"

    ERROR_FILE="$2"


    if [ "$PROXY_AUTH_ENABLED" = "1" ]; then

        curl \
            -x "$LOCAL_PROXY" \
            --proxy-user "$PROXY_AUTH" \
            --http1.1 \
            -L \
            -sS \
            -o /dev/null \
            --connect-timeout 8 \
            --max-time "$SPEED_TIMEOUT" \
            -H "Cache-Control: no-cache" \
            -w "%{http_code}\t%{size_download}\t%{speed_download}" \
            "$URL" \
            2>"$ERROR_FILE"

    else

        curl \
            -x "$LOCAL_PROXY" \
            --http1.1 \
            -L \
            -sS \
            -o /dev/null \
            --connect-timeout 8 \
            --max-time "$SPEED_TIMEOUT" \
            -H "Cache-Control: no-cache" \
            -w "%{http_code}\t%{size_download}\t%{speed_download}" \
            "$URL" \
            2>"$ERROR_FILE"

    fi
}


# ============================================================
# 恢复测速状态
# ============================================================

restore_test_state() {

    [ "$TEST_STATE_DIRTY" = "0" ] &&
        return 0


    RESTORE_OK=1


    if [ -n "$ORIGINAL_TARGET_SELECTION" ]; then

        select_proxy \
            "$TARGET_GROUP" \
            "$ORIGINAL_TARGET_SELECTION" \
            >/dev/null 2>&1 ||
        RESTORE_OK=0

    fi


    if [ -n "$ORIGINAL_GLOBAL_SELECTION" ]; then

        select_proxy \
            "GLOBAL" \
            "$ORIGINAL_GLOBAL_SELECTION" \
            >/dev/null 2>&1 ||
        RESTORE_OK=0

    fi


    if [ -n "$ORIGINAL_MODE" ]; then

        set_mode "$ORIGINAL_MODE" \
            >/dev/null 2>&1 ||
        RESTORE_OK=0

    fi


    if [ "$RESTORE_OK" = "1" ]; then

        TEST_STATE_DIRTY=0

        return 0

    fi


    return 1
}


# ============================================================
# 清理
# ============================================================

cleanup() {

    [ "$CLEANED" = "1" ] &&
        return 0


    CLEANED=1


    if [ "$TEST_STATE_DIRTY" = "1" ]; then

        printf "\n"

        warn "脚本退出，正在恢复 OpenClash 原设置..."


        restore_test_state \
            >/dev/null 2>&1 ||
            true

    fi


    if [ -n "$TMP_DIR" ] &&
       [ -d "$TMP_DIR" ]
    then

        rm -rf "$TMP_DIR"

    fi


    rmdir "$LOCK_DIR" \
        >/dev/null 2>&1 ||
        true
}


trap 'exit 129' 1

trap 'exit 130' 2

trap 'exit 143' 15

trap cleanup 0


# ============================================================
# 启动
# ============================================================

clear 2>/dev/null || true


line

printf "${GREEN}            OpenClash 智能节点优选 V2.5${RESET}\n"

printf "${PURPLE}     延迟 → 串行测速 → 综合评分 → Top5负载均衡${RESET}\n"

line


printf "\n"

printf "延迟候选：${GREEN}前 %s 个${RESET}\n" \
    "$TOP_N"

printf "测速方式：${GREEN}串行测速${RESET}\n"

printf "测速流量：${GREEN}%sMB / 节点${RESET}\n" \
    "$SPEED_MB"

printf "单节点超时：${GREEN}%s 秒${RESET}\n" \
    "$SPEED_TIMEOUT"

printf "最低有效数据：${GREEN}%sMB${RESET}\n" \
    "$MIN_VALID_MB"

printf "速度权重：${GREEN}70%%${RESET}\n"

printf "延迟权重：${GREEN}30%%${RESET}\n"

printf "主节点切换阈值：${GREEN}%s%%${RESET}\n" \
    "$SWITCH_THRESHOLD"

printf "负载均衡节点：${GREEN}Top %s${RESET}\n" \
    "$LB_SLOT_COUNT"

printf "\n"


# ============================================================
# 防重复运行
# ============================================================

if ! mkdir "$LOCK_DIR" >/dev/null 2>&1; then

    die "已有一个 openclash-smart-select 正在运行"

fi


# ============================================================
# 临时目录
# ============================================================

TMP_DIR="$(
    mktemp -d \
        /tmp/openclash-smart-select.XXXXXX \
        2>/dev/null
)"


if [ -z "$TMP_DIR" ] ||
   [ ! -d "$TMP_DIR" ]
then

    TMP_DIR="/tmp/openclash-smart-select.$$"


    mkdir -p "$TMP_DIR" ||
        die "无法创建临时目录"

fi


NODE_FILE="${TMP_DIR}/nodes.txt"

DELAY_JSON_FILE="${TMP_DIR}/group-delay.json"

DELAY_FILE="${TMP_DIR}/delay.txt"

CANDIDATE_FILE="${TMP_DIR}/candidate.txt"

SPEED_FILE="${TMP_DIR}/speed.txt"

SCORE_FILE="${TMP_DIR}/score.txt"

LB_USED_FILE="${TMP_DIR}/lb-used.txt"


# ============================================================
# 1/8 运行环境
# ============================================================

printf "[1/8] 检查运行环境...\n"


ensure_dependency curl curl

ensure_dependency jq jq


success "运行环境正常"


# ============================================================
# 2/8 API
# ============================================================

printf "\n"

printf "[2/8] 检查 OpenClash API...\n"


detect_api ||
    die "无法连接 OpenClash API"


PROXIES_JSON="$(
    api_curl \
        -fsS \
        --connect-timeout 3 \
        --max-time 10 \
        "${API}/proxies" \
        2>/dev/null
)"


[ -z "$PROXIES_JSON" ] &&
    die "无法读取 proxies"


CONFIG_JSON="$(
    api_curl \
        -fsS \
        --connect-timeout 3 \
        --max-time 10 \
        "${API}/configs" \
        2>/dev/null
)"


[ -z "$CONFIG_JSON" ] &&
    die "无法读取 configs"


success "OpenClash API 正常"

printf "API：${GREEN}%s${RESET}\n" \
    "$API"


# ============================================================
# 自动识别策略组
# ============================================================

MAIN_GROUP="$(
    find_selector_group \
        "$MAIN_KEYWORD"
)"


TARGET_GROUP="$(
    find_main_target_group
)"


LB_GROUP_1="$(find_lb_slot_group 1)"

LB_GROUP_2="$(find_lb_slot_group 2)"

LB_GROUP_3="$(find_lb_slot_group 3)"

LB_GROUP_4="$(find_lb_slot_group 4)"

LB_GROUP_5="$(find_lb_slot_group 5)"


SOURCE_GROUP="$(
    find_urltest_group \
        "$SOURCE_PRIMARY_KEYWORD"
)"


if [ -z "$SOURCE_GROUP" ]; then

    SOURCE_GROUP="$(
        find_urltest_group \
            "$SOURCE_FALLBACK_KEYWORD"
    )"

fi


# ============================================================
# 必要策略组
# ============================================================

[ -z "$MAIN_GROUP" ] &&
    die "找不到包含「${MAIN_KEYWORD}」的 Selector"


[ -z "$TARGET_GROUP" ] &&
    die "找不到主「${TARGET_KEYWORD}」Selector"


[ -z "$SOURCE_GROUP" ] &&
    die "找不到增强选择或自动选择 URLTest"


# ============================================================
# 检查 LB 1~5
# ============================================================

LB_AVAILABLE=1


for GROUP in \
    "$LB_GROUP_1" \
    "$LB_GROUP_2" \
    "$LB_GROUP_3" \
    "$LB_GROUP_4" \
    "$LB_GROUP_5"
do

    if [ -z "$GROUP" ]; then

        LB_AVAILABLE=0

        break

    fi

done


if [ "$LB_AVAILABLE" = "1" ]; then

    success "已识别智能优选1~5"

else

    warn "没有完整识别智能优选1~5"

    warn "本次仍可执行主智能优选，但不会更新负载均衡 Top5"

fi


# ============================================================
# 主组必须包含主智能优选
# ============================================================

MAIN_HAS_TARGET="$(
    group_has_node \
        "$MAIN_GROUP" \
        "$TARGET_GROUP"
)"


[ "$MAIN_HAS_TARGET" != "1" ] &&
    die "${MAIN_GROUP} 中没有 ${TARGET_GROUP}"


# ============================================================
# GLOBAL
# ============================================================

GLOBAL_OK="$(
    printf '%s' "$PROXIES_JSON" |
    jq -r '
    if (
        .proxies["GLOBAL"]
        and
        (
            (.proxies["GLOBAL"].type // "" | ascii_downcase)
            == "selector"
        )
    )
    then
        1
    else
        0
    end
    '
)"


[ "$GLOBAL_OK" != "1" ] &&
    die "GLOBAL Selector 不可用"


GLOBAL_HAS_TARGET="$(
    group_has_node \
        "GLOBAL" \
        "$TARGET_GROUP"
)"


[ "$GLOBAL_HAS_TARGET" != "1" ] &&
    die "GLOBAL 中没有 ${TARGET_GROUP}"


# ============================================================
# 当前状态
# ============================================================

CURRENT_MAIN_SELECTION="$(
    printf '%s' "$PROXIES_JSON" |
    jq -r \
        --arg g "$MAIN_GROUP" \
        '.proxies[$g].now // empty'
)"


CURRENT_TARGET_SELECTION="$(
    printf '%s' "$PROXIES_JSON" |
    jq -r \
        --arg g "$TARGET_GROUP" \
        '.proxies[$g].now // empty'
)"


ORIGINAL_TARGET_SELECTION="$CURRENT_TARGET_SELECTION"


ORIGINAL_GLOBAL_SELECTION="$(
    printf '%s' "$PROXIES_JSON" |
    jq -r \
        '.proxies["GLOBAL"].now // empty'
)"


ORIGINAL_MODE="$(
    printf '%s' "$CONFIG_JSON" |
    jq -r \
        '.mode // "rule"'
)"


CURRENT_EFFECTIVE_NODE="$(
    resolve_leaf \
        "$MAIN_GROUP"
)"


# ============================================================
# 本地代理
# ============================================================

if [ -n "${OPENCLASH_LOCAL_PROXY:-}" ]; then

    LOCAL_PROXY="$OPENCLASH_LOCAL_PROXY"

else

    MIXED_PORT="$(
        printf '%s' "$CONFIG_JSON" |
        jq -r \
            '."mixed-port" // 0'
    )"


    HTTP_PORT="$(
        printf '%s' "$CONFIG_JSON" |
        jq -r \
            '.port // 0'
    )"


    SOCKS_PORT="$(
        printf '%s' "$CONFIG_JSON" |
        jq -r \
            '."socks-port" // 0'
    )"


    case "$MIXED_PORT" in

        ''|null|*[!0-9]*)

            MIXED_PORT=0

            ;;

    esac


    case "$HTTP_PORT" in

        ''|null|*[!0-9]*)

            HTTP_PORT=0

            ;;

    esac


    case "$SOCKS_PORT" in

        ''|null|*[!0-9]*)

            SOCKS_PORT=0

            ;;

    esac


    if [ "$MIXED_PORT" -gt 0 ]; then

        LOCAL_PROXY="http://127.0.0.1:${MIXED_PORT}"

    elif [ "$HTTP_PORT" -gt 0 ]; then

        LOCAL_PROXY="http://127.0.0.1:${HTTP_PORT}"

    elif [ "$SOCKS_PORT" -gt 0 ]; then

        LOCAL_PROXY="socks5h://127.0.0.1:${SOCKS_PORT}"

    else

        die "找不到 OpenClash 本地代理端口"

    fi

fi


detect_proxy_auth


# ============================================================
# 基本信息
# ============================================================

printf "\n"

subline


printf "主策略组：${GREEN}%s${RESET}\n" \
    "$MAIN_GROUP"


printf "主智能优选：${GREEN}%s${RESET}\n" \
    "$TARGET_GROUP"


printf "测速来源：${GREEN}%s${RESET}\n" \
    "$SOURCE_GROUP"


if [ "$LB_AVAILABLE" = "1" ]; then

    printf "负载均衡槽位：${GREEN}智能优选1~5${RESET}\n"

fi


printf "\n"


printf "当前主选择：${GREEN}%s${RESET}\n" \
    "${CURRENT_MAIN_SELECTION:-未知}"


printf "当前实际节点：${GREEN}%s${RESET}\n" \
    "${CURRENT_EFFECTIVE_NODE:-未知}"


printf "GLOBAL当前：${GREEN}%s${RESET}\n" \
    "${ORIGINAL_GLOBAL_SELECTION:-未知}"


printf "当前模式：${GREEN}%s${RESET}\n" \
    "${ORIGINAL_MODE:-未知}"


printf "本地代理：${GREEN}%s${RESET}\n" \
    "$LOCAL_PROXY"


if [ "$PROXY_AUTH_ENABLED" = "1" ]; then

    printf "代理认证：${GREEN}已自动识别${RESET}\n"

else

    printf "代理认证：${GREEN}未启用${RESET}\n"

fi


subline


# ============================================================
# 3/8 获取真实节点
# ============================================================

printf "\n"

printf "[3/8] 获取可测速真实节点...\n"


printf '%s' "$PROXIES_JSON" |
jq -r \
    --arg source "$SOURCE_GROUP" \
    --arg target "$TARGET_GROUP" '

    . as $root

    | ($root.proxies[$target].all // [])
        as $target_nodes

    | $root.proxies[$source].all[]?

    | . as $node

    | ($root.proxies[$node].type // "")
        as $type

    | ($type | ascii_downcase)
        as $t

    | select(
        (
            [
                "selector",
                "urltest",
                "fallback",
                "loadbalance",
                "relay",
                "direct",
                "reject",
                "pass",
                "compatible"
            ]
            | index($t)
        )
        == null
    )

    | select(
        ($target_nodes | index($node))
        != null
    )

    | $node
' |
awk '
NF && !seen[$0]++ {
    print
}
' > "$NODE_FILE"


NODE_COUNT="$(
    wc -l < "$NODE_FILE" |
    tr -d ' '
)"


case "$NODE_COUNT" in

    ''|*[!0-9]*)

        NODE_COUNT=0

        ;;

esac


[ "$NODE_COUNT" -le 0 ] &&
    die "没有找到可测速真实节点"


success "发现 ${NODE_COUNT} 个可测速真实节点"


# ============================================================
# 4/8 批量延迟
# ============================================================

printf "\n"

printf "[4/8] 正在批量测试全部节点延迟...\n"


SOURCE_ENC="$(
    urlencode \
        "$SOURCE_GROUP"
)"


if ! api_curl \
    -fsS \
    -G \
    --connect-timeout 6 \
    --max-time 60 \
    --data-urlencode "url=${DELAY_URL}" \
    --data-urlencode "timeout=${DELAY_TIMEOUT}" \
    "${API}/group/${SOURCE_ENC}/delay" \
    > "$DELAY_JSON_FILE"
then

    die "策略组批量延迟测试失败"

fi


if ! jq -e \
    'type == "object"' \
    "$DELAY_JSON_FILE" \
    >/dev/null 2>&1
then

    die "批量延迟接口返回数据异常"

fi


jq -r \
    --rawfile nodes "$NODE_FILE" \
    --argjson max_delay "$MAX_DELAY" '

    (
        $nodes
        | split("\n")
        | map(
            select(length > 0)
        )
    )
    as $allowed

    | . as $delays

    | $allowed[]

    | . as $node

    | ($delays[$node] // 0)
        as $delay

    | select(
        ($delay | type) == "number"
        and
        $delay > 0
        and
        $delay <= $max_delay
    )

    | "\($delay)\t\($node)"
' "$DELAY_JSON_FILE" \
> "$DELAY_FILE"


[ ! -s "$DELAY_FILE" ] &&
    die "没有找到延迟正常的候选节点"


sort \
    -n \
    -k1,1 \
    "$DELAY_FILE" \
    > "${DELAY_FILE}.sorted"


mv \
    "${DELAY_FILE}.sorted" \
    "$DELAY_FILE"


head \
    -n "$TOP_N" \
    "$DELAY_FILE" \
    > "$CANDIDATE_FILE"


CANDIDATE_COUNT="$(
    wc -l < "$CANDIDATE_FILE" |
    tr -d ' '
)"


success "延迟测试完成"


# ============================================================
# 延迟排名
# ============================================================

printf "\n"


printf "${BLUE}延迟最低前 %s 个节点${RESET}\n" \
    "$CANDIDATE_COUNT"


subline


printf "%-10s %s\n" \
    "延迟" \
    "节点"


subline


while IFS="$TAB" read -r \
    DELAY \
    NODE
do

    printf "%-10s %s\n" \
        "${DELAY}ms" \
        "$NODE"

done < "$CANDIDATE_FILE"


# ============================================================
# 5/8 串行真实测速
# ============================================================

printf "\n"


printf "[5/8] 开始串行真实测速（%sMB / 节点，最多 %s 秒）...\n" \
    "$SPEED_MB" \
    "$SPEED_TIMEOUT"


printf "\n"


warn "测速期间临时使用：GLOBAL → ${TARGET_GROUP}"

warn "候选节点将逐个串行测速"

warn "${SPEED_TIMEOUT}秒超时但下载 >=${MIN_VALID_MB}MB 仍参与评分"

warn "测速结束或中断后自动恢复"


printf "\n"


FIRST_NODE="$(
    head -n 1 "$CANDIDATE_FILE" |
    cut -f2-
)"


[ -z "$FIRST_NODE" ] &&
    die "没有测速候选节点"


# ============================================================
# 进入测试状态
# ============================================================

select_proxy \
    "$TARGET_GROUP" \
    "$FIRST_NODE" ||
    die "无法设置智能优选测试节点"


TEST_STATE_DIRTY=1


select_proxy \
    "GLOBAL" \
    "$TARGET_GROUP" ||
    die "无法设置 GLOBAL → ${TARGET_GROUP}"


set_mode global ||
    die "无法进入 GLOBAL 模式"


sleep 1


# ============================================================
# 开始测速
# ============================================================

: > "$SPEED_FILE"


COUNT=0


while IFS="$TAB" read -r \
    DELAY \
    NODE
do

    COUNT=$((COUNT + 1))


    printf "${YELLOW}[%s/%s]${RESET} %s\n" \
        "$COUNT" \
        "$CANDIDATE_COUNT" \
        "$NODE"


    printf "      延迟：%sms\n" \
        "$DELAY"


    if ! select_proxy \
        "$TARGET_GROUP" \
        "$NODE"
    then

        printf "      ${RED}节点切换失败${RESET}\n"

        continue

    fi


    sleep 1


    CACHE_ID="$(date +%s)-${COUNT}"


    case "$SPEED_URL" in

        *\?*)

            TEST_URL="${SPEED_URL}&cb=${CACHE_ID}"

            ;;

        *)

            TEST_URL="${SPEED_URL}?cb=${CACHE_ID}"

            ;;

    esac


    ERROR_FILE="${TMP_DIR}/curl.${COUNT}.err"


    METRIC="$(
        speed_download \
            "$TEST_URL" \
            "$ERROR_FILE"
    )"


    CURL_RC=$?


    HTTP_CODE="$(
        printf '%s' "$METRIC" |
        cut -f1
    )"


    SIZE_DOWN="$(
        printf '%s' "$METRIC" |
        cut -f2
    )"


    SPEED_BPS="$(
        printf '%s' "$METRIC" |
        cut -f3
    )"


    case "$HTTP_CODE" in

        ''|*[!0-9]*)

            HTTP_CODE=0

            ;;

    esac


    case "$SIZE_DOWN" in

        ''|*[!0-9.]*)

            SIZE_DOWN=0

            ;;

    esac


    case "$SPEED_BPS" in

        ''|*[!0-9.]*)

            SPEED_BPS=0

            ;;

    esac


    SIZE_INT="${SIZE_DOWN%%.*}"

    SPEED_INT="${SPEED_BPS%%.*}"


    case "$SIZE_INT" in

        ''|*[!0-9]*)

            SIZE_INT=0

            ;;

    esac


    case "$SPEED_INT" in

        ''|*[!0-9]*)

            SPEED_INT=0

            ;;

    esac


    # ========================================================
    # HTTP
    # ========================================================

    case "$HTTP_CODE" in

        200|206)

            ;;

        *)

            printf "      ${RED}测速失败${RESET} HTTP:%s\n" \
                "$HTTP_CODE"

            continue

            ;;

    esac


    # ========================================================
    # CURL
    # ========================================================

    case "$CURL_RC" in

        0)

            ;;

        28)

            if [ "$SIZE_INT" -lt "$MIN_VALID_BYTES" ] ||
               [ "$SPEED_INT" -le 0 ]
            then

                DOWN_MB="$(
                    jq -nr \
                        --argjson b "$SIZE_INT" '
                        (($b / 1000000) * 100 | round) / 100
                    '
                )"


                printf "      ${RED}%s秒超时，数据不足，跳过${RESET}" \
                    "$SPEED_TIMEOUT"


                printf " | 已下载：%s MB\n" \
                    "$DOWN_MB"


                continue

            fi


            printf "      ${YELLOW}%s秒未完成，按已下载数据计算${RESET}\n" \
                "$SPEED_TIMEOUT"

            ;;

        *)

            printf "      ${RED}测速失败${RESET}"


            if [ -s "$ERROR_FILE" ]; then

                CURL_ERROR="$(
                    tail -n 1 \
                        "$ERROR_FILE"
                )"


                [ -n "$CURL_ERROR" ] &&
                    printf " | %s" \
                        "$CURL_ERROR"

            fi


            printf "\n"


            continue

            ;;

    esac


    # ========================================================
    # 最低数据
    # ========================================================

    if [ "$SIZE_INT" -lt "$MIN_VALID_BYTES" ] ||
       [ "$SPEED_INT" -le 0 ]
    then

        printf "      ${RED}有效测速数据不足，跳过${RESET}\n"

        continue

    fi


    # ========================================================
    # Mbps
    # ========================================================

    SPEED_MBPS="$(
        jq -nr \
            --argjson b "$SPEED_INT" '
            ($b * 8 / 1000000)
        '
    )"


    SPEED_MBPS_FMT="$(
        printf '%.2f' \
            "$SPEED_MBPS" \
            2>/dev/null
    )"


    [ -z "$SPEED_MBPS_FMT" ] &&
        SPEED_MBPS_FMT="$SPEED_MBPS"


    DOWN_MB="$(
        jq -nr \
            --argjson b "$SIZE_INT" '
            (($b / 1000000) * 100 | round) / 100
        '
    )"


    printf "      速度：${GREEN}%s Mbps${RESET}" \
        "$SPEED_MBPS_FMT"


    printf " | 下载：%s MB\n" \
        "$DOWN_MB"


    printf "%s\t%s\t%s\n" \
        "$DELAY" \
        "$SPEED_INT" \
        "$NODE" \
        >> "$SPEED_FILE"


done < "$CANDIDATE_FILE"


# ============================================================
# 恢复测试状态
# ============================================================

printf "\n"


info "正在恢复 OpenClash 原设置..."


restore_test_state ||
    die "测速结束，但恢复 OpenClash 设置失败"


success "原设置恢复完成"


[ ! -s "$SPEED_FILE" ] &&
    die "所有候选节点真实测速均失败"


# ============================================================
# 6/8 综合评分
# ============================================================

printf "\n"


printf "[6/8] 计算综合性能评分...\n"


MAX_SPEED="$(
    cut -f2 "$SPEED_FILE" |
    sort -nr |
    head -n 1
)"


[ -z "$MAX_SPEED" ] &&
    MAX_SPEED=0


MIN_DELAY="$(
    cut -f1 "$SPEED_FILE" |
    sort -n |
    head -n 1
)"


[ -z "$MIN_DELAY" ] &&
    MIN_DELAY=999999


: > "$SCORE_FILE"


while IFS="$TAB" read -r \
    DELAY \
    SPEED_BPS \
    NODE
do

    SCORE="$(
        jq -nr \
            --argjson speed "$SPEED_BPS" \
            --argjson maxspeed "$MAX_SPEED" \
            --argjson delay "$DELAY" \
            --argjson mindelay "$MIN_DELAY" '

            if (
                $maxspeed <= 0
                or
                $delay <= 0
            )
            then

                0

            else

                (
                    ($speed / $maxspeed) * 70
                    +
                    ($mindelay / $delay) * 30
                )

            end
            '
    )"


    SCORE_FMT="$(
        printf '%.2f' \
            "$SCORE" \
            2>/dev/null
    )"


    [ -z "$SCORE_FMT" ] &&
        SCORE_FMT="$SCORE"


    SPEED_MBPS="$(
        jq -nr \
            --argjson b "$SPEED_BPS" '
            ($b * 8 / 1000000)
        '
    )"


    SPEED_MBPS_FMT="$(
        printf '%.2f' \
            "$SPEED_MBPS" \
            2>/dev/null
    )"


    [ -z "$SPEED_MBPS_FMT" ] &&
        SPEED_MBPS_FMT="$SPEED_MBPS"


    printf "%s\t%s\t%s\t%s\t%s\n" \
        "$SCORE_FMT" \
        "$DELAY" \
        "$SPEED_BPS" \
        "$SPEED_MBPS_FMT" \
        "$NODE" \
        >> "$SCORE_FILE"


done < "$SPEED_FILE"


sort \
    -nr \
    -k1,1 \
    "$SCORE_FILE" \
    > "${SCORE_FILE}.sorted"


mv \
    "${SCORE_FILE}.sorted" \
    "$SCORE_FILE"


# ============================================================
# 综合排名
# ============================================================

printf "\n"


printf "${BLUE}综合性能排名${RESET}\n"


line


printf "%-9s %-10s %-14s %s\n" \
    "评分" \
    "延迟" \
    "实际速度" \
    "节点"


line


while IFS="$TAB" read -r \
    SCORE \
    DELAY \
    SPEED_BPS \
    SPEED_MBPS \
    NODE
do

    printf "%-9s %-10s %-14s %s\n" \
        "$SCORE" \
        "${DELAY}ms" \
        "${SPEED_MBPS}Mbps" \
        "$NODE"


done < "$SCORE_FILE"


line


# ============================================================
# 7/8 分配负载均衡 Top5
# ============================================================

printf "\n"


printf "[7/8] 更新负载均衡 Top5...\n"


if [ "$LB_AVAILABLE" = "1" ]; then

    : > "$LB_USED_FILE"


    printf "\n"

    printf "${BLUE}负载均衡智能节点分配${RESET}\n"

    subline


    SLOT=1


    while [ "$SLOT" -le "$LB_SLOT_COUNT" ]; do

        case "$SLOT" in

            1)

                SLOT_GROUP="$LB_GROUP_1"

                ;;

            2)

                SLOT_GROUP="$LB_GROUP_2"

                ;;

            3)

                SLOT_GROUP="$LB_GROUP_3"

                ;;

            4)

                SLOT_GROUP="$LB_GROUP_4"

                ;;

            5)

                SLOT_GROUP="$LB_GROUP_5"

                ;;

        esac


        SLOT_FOUND=0


        while IFS="$TAB" read -r \
            LB_SCORE \
            LB_DELAY \
            LB_SPEED_BPS \
            LB_SPEED_MBPS \
            LB_NODE
        do

            # 已使用则跳过
            if grep -Fxq \
                "$LB_NODE" \
                "$LB_USED_FILE" \
                2>/dev/null
            then

                continue

            fi


            # 必须存在于当前 Selector
            HAS_NODE="$(
                group_has_node \
                    "$SLOT_GROUP" \
                    "$LB_NODE"
            )"


            [ "$HAS_NODE" != "1" ] &&
                continue


            if select_proxy \
                "$SLOT_GROUP" \
                "$LB_NODE"
            then

                printf "${GREEN}[OK]${RESET} %s → %s\n" \
                    "$SLOT_GROUP" \
                    "$LB_NODE"


                printf "     评分：%s | 延迟：%sms | 速度：%sMbps\n" \
                    "$LB_SCORE" \
                    "$LB_DELAY" \
                    "$LB_SPEED_MBPS"


                printf '%s\n' \
                    "$LB_NODE" \
                    >> "$LB_USED_FILE"


                SLOT_FOUND=1


                break

            fi


        done < "$SCORE_FILE"


        if [ "$SLOT_FOUND" != "1" ]; then

            warn "${SLOT_GROUP} 没有找到可分配节点"

        fi


        SLOT=$((SLOT + 1))


    done


    subline


else

    warn "智能优选1~5不完整，跳过负载均衡分配"

fi


# ============================================================
# 冠军
# ============================================================

BEST_LINE="$(
    head -n 1 \
        "$SCORE_FILE"
)"


BEST_SCORE="$(
    printf '%s\n' "$BEST_LINE" |
    cut -f1
)"


BEST_DELAY="$(
    printf '%s\n' "$BEST_LINE" |
    cut -f2
)"


BEST_SPEED_MBPS="$(
    printf '%s\n' "$BEST_LINE" |
    cut -f4
)"


BEST_NODE="$(
    printf '%s\n' "$BEST_LINE" |
    cut -f5-
)"


[ -z "$BEST_NODE" ] &&
    die "无法确定最佳节点"


# ============================================================
# 当前节点评分
# ============================================================

CURRENT_SCORE=""

CURRENT_DELAY=""

CURRENT_SPEED_MBPS=""


while IFS="$TAB" read -r \
    T_SCORE \
    T_DELAY \
    T_SPEED_BPS \
    T_SPEED_MBPS \
    T_NODE
do

    if [ "$T_NODE" = "$CURRENT_EFFECTIVE_NODE" ]; then

        CURRENT_SCORE="$T_SCORE"

        CURRENT_DELAY="$T_DELAY"

        CURRENT_SPEED_MBPS="$T_SPEED_MBPS"


        break

    fi


done < "$SCORE_FILE"


IMPROVEMENT=""

SHOULD_SWITCH=0

SWITCH_REASON=""


# ============================================================
# 主智能优选切换逻辑
# ============================================================

if [ "$BEST_NODE" = "$CURRENT_EFFECTIVE_NODE" ]; then

    SHOULD_SWITCH=1

    IMPROVEMENT="0.00"

    SWITCH_REASON="当前实际节点就是综合冠军"


elif [ -n "$CURRENT_SCORE" ]; then

    IMPROVEMENT="$(
        jq -nr \
            --argjson best "$BEST_SCORE" \
            --argjson current "$CURRENT_SCORE" '

            if $current <= 0
            then

                999

            else

                (
                    ($best - $current)
                    /
                    $current
                )
                * 100

            end
            '
    )"


    IMPROVEMENT_FMT="$(
        printf '%.2f' \
            "$IMPROVEMENT" \
            2>/dev/null
    )"


    [ -z "$IMPROVEMENT_FMT" ] &&
        IMPROVEMENT_FMT="$IMPROVEMENT"


    IMPROVEMENT="$IMPROVEMENT_FMT"


    SHOULD_SWITCH="$(
        jq -nr \
            --argjson improvement "$IMPROVEMENT" \
            --argjson threshold "$SWITCH_THRESHOLD" '

            if $improvement >= $threshold
            then
                1
            else
                0
            end
            '
    )"


    if [ "$SHOULD_SWITCH" = "1" ]; then

        SWITCH_REASON="性能提升达到 ${SWITCH_THRESHOLD}%"

    else

        SWITCH_REASON="性能提升不足 ${SWITCH_THRESHOLD}%"

    fi


else

    SHOULD_SWITCH=1

    SWITCH_REASON="当前节点未进入延迟前 ${TOP_N} 或真实测速失败"

fi


# ============================================================
# 8/8 主节点决策
# ============================================================

printf "\n"


printf "[8/8] 智能切换决策...\n"


printf "\n"


printf "当前实际节点：${GREEN}%s${RESET}\n" \
    "${CURRENT_EFFECTIVE_NODE:-未知}"


if [ -n "$CURRENT_SCORE" ]; then

    printf "当前评分：%s\n" \
        "$CURRENT_SCORE"

    printf "当前延迟：%sms\n" \
        "$CURRENT_DELAY"

    printf "当前速度：%sMbps\n" \
        "$CURRENT_SPEED_MBPS"

fi


printf "\n"


printf "冠军节点：${GREEN}%s${RESET}\n" \
    "$BEST_NODE"

printf "冠军评分：${GREEN}%s${RESET}\n" \
    "$BEST_SCORE"

printf "冠军延迟：${GREEN}%sms${RESET}\n" \
    "$BEST_DELAY"

printf "冠军速度：${GREEN}%sMbps${RESET}\n" \
    "$BEST_SPEED_MBPS"


if [ -n "$IMPROVEMENT" ]; then

    printf "\n"


    printf "性能提升：${GREEN}%s%%${RESET}\n" \
        "$IMPROVEMENT"


    printf "切换阈值：${GREEN}%s%%${RESET}\n" \
        "$SWITCH_THRESHOLD"

fi


printf "\n"


printf "判断结果：${YELLOW}%s${RESET}\n" \
    "$SWITCH_REASON"


printf "\n"


# ============================================================
# 不切主节点
# ============================================================

if [ "$SHOULD_SWITCH" != "1" ]; then

    line


    printf "${GREEN}              ✓ 保持当前主节点${RESET}\n"


    line


    printf "\n"


    printf "继续使用：${GREEN}%s${RESET}\n" \
        "$CURRENT_EFFECTIVE_NODE"


    if [ "$LB_AVAILABLE" = "1" ]; then

        printf "负载均衡：${GREEN}Top5 已更新${RESET}\n"

    fi


    printf "\n"


    exit 0

fi


# ============================================================
# 设置主智能优选冠军
# ============================================================

info "设置 ${TARGET_GROUP} → ${BEST_NODE}"


select_proxy \
    "$TARGET_GROUP" \
    "$BEST_NODE" ||
    die "无法将主智能优选切换到冠军节点"


# ============================================================
# 节点选择 → 主智能优选
# ============================================================

info "设置 ${MAIN_GROUP} → ${TARGET_GROUP}"


if ! select_proxy \
    "$MAIN_GROUP" \
    "$TARGET_GROUP"
then

    warn "主策略切换失败，恢复智能优选原节点"


    if [ -n "$ORIGINAL_TARGET_SELECTION" ]; then

        select_proxy \
            "$TARGET_GROUP" \
            "$ORIGINAL_TARGET_SELECTION" \
            >/dev/null 2>&1 ||
            true

    fi


    die "无法将主策略切换到智能优选"

fi


# ============================================================
# 完成
# ============================================================

printf "\n"


line


printf "${GREEN}                 ✓ 智能优选完成${RESET}\n"


line


printf "\n"


printf "${GREEN}%s${RESET}\n" \
    "$MAIN_GROUP"

printf "   ↓\n"

printf "${GREEN}%s${RESET}\n" \
    "$TARGET_GROUP"

printf "   ↓\n"

printf "${GREEN}%s${RESET}\n" \
    "$BEST_NODE"


printf "\n"


printf "延迟：${GREEN}%s ms${RESET}\n" \
    "$BEST_DELAY"

printf "速度：${GREEN}%s Mbps${RESET}\n" \
    "$BEST_SPEED_MBPS"

printf "评分：${GREEN}%s${RESET}\n" \
    "$BEST_SCORE"


if [ -n "$IMPROVEMENT" ]; then

    printf "提升：${GREEN}%s%%${RESET}\n" \
        "$IMPROVEMENT"

fi


printf "\n"


printf "测速来源：%s\n" \
    "$SOURCE_GROUP"

printf "参与延迟测试：%s 个真实节点\n" \
    "$NODE_COUNT"

printf "实际测速候选：%s 个\n" \
    "$CANDIDATE_COUNT"

printf "单节点测速：%sMB\n" \
    "$SPEED_MB"

printf "单节点超时：%s秒\n" \
    "$SPEED_TIMEOUT"


if [ "$LB_AVAILABLE" = "1" ]; then

    printf "负载均衡：Top %s 已自动分配\n" \
        "$LB_SLOT_COUNT"

fi


if [ "$PROXY_AUTH_ENABLED" = "1" ]; then

    printf "代理认证：已自动处理\n"

fi


printf "\n"


exit 0

#!/bin/sh

# ============================================================
# Open-Pro-Installer
# OpenClash 依赖检查
#
# 由 install.sh 的「[3] 安装代理工具 → [1] 安装 OpenClash」
# 分支调用；bootstrap.sh 不再碰 opkg。
#
# 检查这两个包：
#   luci-compat    老式 LuCI 插件的兼容层
#                   （21.02 之后 LuCI 改成 JS/ucode，
#                     Lua 时代写的插件要靠它才能打开页面）
#   luci-lib-ipkg  网页端调用 opkg 的接口
#                   （OpenClash 里"更新内核/装依赖"这类按钮要用）
#
# 这两个都只影响 OpenClash 的「网页界面」，
# 不影响内核、代理转发本身。
#
# 行为：
#   1. 都装了          → 直接返回 0（本地查询，不碰网络）
#   2. 有缺的          → 带超时地 opkg update + opkg install
#   3. 源里没有/装不上 → 说清楚，再问一句，用户同意才继续
#   4. 非 opkg 系统    → 跳过
#
# 返回：0 = 可以继续安装 OpenClash，1 = 用户放弃
#
# BusyBox / OpenWrt /bin/sh Compatible
# ============================================================


# ============================================================
# 颜色（install.sh 已定义则复用）
# ============================================================

[ -n "${GREEN:-}" ]  || GREEN="$(printf '\033[1;92m')"
[ -n "${CYAN:-}" ]   || CYAN="$(printf '\033[1;96m')"
[ -n "${YELLOW:-}" ] || YELLOW="$(printf '\033[1;93m')"
[ -n "${RED:-}" ]    || RED="$(printf '\033[1;91m')"
[ -n "${RESET:-}" ]  || RESET="$(printf '\033[0m')"


# ============================================================
# 配置
# ============================================================

OC_DEP_TIMEOUT=45
OC_DEP_LIST_TIMEOUT=30

OC_DEP_LOG="/tmp/openpro_openclash_depend.log"

OPENCLASH_DEPEND_CHECKED=""


# ============================================================
# 日志
# ============================================================

_dep_info()
{
    printf "%b\n" "${GREEN}[INFO]${RESET} $*"
}


_dep_ok()
{
    printf "%b\n" "${GREEN}[OK]${RESET} $*"
}


_dep_warn()
{
    printf "%b\n" "${YELLOW}[WARN]${RESET} $*"
}


_dep_error()
{
    printf "%b\n" "${RED}[ERROR]${RESET} $*"
}


# ============================================================
# 带硬超时执行
#
# 有 timeout 就用 timeout，没有就用 后台 + 定时 kill 兜底
# ============================================================

_dep_run_limited()
{
    LIMIT="$1"

    shift

    [ -n "$LIMIT" ] ||
        LIMIT=60

    if command -v timeout >/dev/null 2>&1; then

        timeout "$LIMIT" "$@"

        return $?
    fi

    "$@" &

    DEP_RUN_PID=$!

    (
        sleep "$LIMIT"

        kill "$DEP_RUN_PID" 2>/dev/null
    ) &

    DEP_KILL_PID=$!

    wait "$DEP_RUN_PID"

    DEP_RUN_RC=$?

    kill "$DEP_KILL_PID" 2>/dev/null

    wait "$DEP_KILL_PID" 2>/dev/null

    return "$DEP_RUN_RC"
}


# ============================================================
# 是否已安装（读本地状态库，不碰网络）
# ============================================================

_dep_installed()
{
    _dep_run_limited 15 opkg status "$1" 2>/dev/null |
        grep -q 'Status:.*installed'
}


# ============================================================
# 软件源索引里有没有这个包
# ============================================================

_dep_in_feed()
{
    _dep_run_limited "$OC_DEP_LIST_TIMEOUT" opkg list 2>/dev/null |
        awk -v pkg="$1" '$1 == pkg { found = 1 } END { exit !found }'
}


# ============================================================
# 询问：是否继续
#
# 回车 / y  → 继续
# n         → 放弃
# 读不到输入（非交互）→ 按继续处理
# ============================================================

_dep_confirm_continue()
{
    printf "\n"

    printf "%b" "${YELLOW}是否继续安装 OpenClash？(Y/n) ${RESET}"

    read DEP_ANSWER </dev/tty 2>/dev/null

    case "$DEP_ANSWER" in

        n|N|no|NO|No|nO)
            return 1
            ;;

        *)
            return 0
            ;;

    esac
}


# ============================================================
# 主函数
# ============================================================

check_openclash_depend()
{
    # 已经检查并同意过，不重复打扰
    [ "$OPENCLASH_DEPEND_CHECKED" = "1" ] &&
        return 0


    printf "\n"

    _dep_info "检查 OpenClash 依赖 ..."


    # ----------------------------------
    # 仅 opkg 系统
    # ----------------------------------

    if ! command -v opkg >/dev/null 2>&1; then

        _dep_info "非 opkg 系统，跳过 OpenClash 依赖检查"

        OPENCLASH_DEPEND_CHECKED=1

        return 0

    fi


    rm -f "$OC_DEP_LOG" 2>/dev/null


    # ----------------------------------
    # 1) 先看装没装
    # ----------------------------------

    DEP_NEED=""

    for DEP_PKG in luci-compat luci-lib-ipkg
    do

        if _dep_installed "$DEP_PKG"; then

            _dep_ok "$DEP_PKG 已安装"

        else

            _dep_warn "$DEP_PKG 未安装"

            DEP_NEED="$DEP_NEED $DEP_PKG"

        fi

    done


    if [ -z "$DEP_NEED" ]; then

        _dep_ok "OpenClash 依赖已满足"

        OPENCLASH_DEPEND_CHECKED=1

        return 0

    fi


    _dep_info "需要安装:$DEP_NEED"


    # ----------------------------------
    # 2) 更新软件源（带超时）
    # ----------------------------------

    printf "%b" "${CYAN}正在更新软件源（最多 ${OC_DEP_TIMEOUT}s）... ${RESET}"

    _dep_run_limited "$OC_DEP_TIMEOUT" opkg update \
        >>"$OC_DEP_LOG" 2>&1

    DEP_UPDATE_RC=$?

    printf "\n"


    if [ "$DEP_UPDATE_RC" -ne 0 ]; then

        _dep_warn "软件源更新失败或超时"

    else

        _dep_ok "软件源更新完成"

    fi


    # ----------------------------------
    # 3) 逐个安装
    # ----------------------------------

    DEP_MISSING=""
    DEP_NOFEED=""

    for DEP_PKG in $DEP_NEED
    do

        # 也许上一步已经带上来了
        if _dep_installed "$DEP_PKG"; then

            _dep_ok "$DEP_PKG 已安装"

            continue

        fi


        # 软件源都没更新成功，就没必要去试安装
        if [ "$DEP_UPDATE_RC" -ne 0 ]; then

            DEP_MISSING="$DEP_MISSING $DEP_PKG"

            continue

        fi


        # 源里有没有这个包
        if ! _dep_in_feed "$DEP_PKG"; then

            _dep_warn "$DEP_PKG 不在你的软件源里"

            DEP_NOFEED="$DEP_NOFEED $DEP_PKG"

            DEP_MISSING="$DEP_MISSING $DEP_PKG"

            continue

        fi


        printf "%b" "${CYAN}正在安装 $DEP_PKG（最多 ${OC_DEP_TIMEOUT}s）... ${RESET}"

        _dep_run_limited "$OC_DEP_TIMEOUT" opkg install "$DEP_PKG" \
            >>"$OC_DEP_LOG" 2>&1

        DEP_INSTALL_RC=$?

        printf "\n"


        if [ "$DEP_INSTALL_RC" -eq 0 ] &&
           _dep_installed "$DEP_PKG"; then

            _dep_ok "$DEP_PKG 安装完成"

        else

            _dep_warn "$DEP_PKG 安装失败"

            if [ -s "$OC_DEP_LOG" ]; then

                tail -n 10 "$OC_DEP_LOG"

            fi

            DEP_MISSING="$DEP_MISSING $DEP_PKG"

        fi

    done


    # ----------------------------------
    # 4) 补齐了 → 继续
    # ----------------------------------

    if [ -z "$DEP_MISSING" ]; then

        _dep_ok "OpenClash 依赖已就绪"

        OPENCLASH_DEPEND_CHECKED=1

        return 0

    fi


    # ----------------------------------
    # 5) 还有缺的 → 说清楚，再问一句
    # ----------------------------------

    printf "\n"


    if [ -n "$DEP_NOFEED" ]; then

        _dep_warn "源里没有这两个包:$DEP_NOFEED"

    else

        _dep_warn "这两个包装不上:$DEP_MISSING"

    fi


    _dep_info "缺它们时 OpenClash 的网页界面可能打不开"

    _dep_info "内核和代理转发本身不受影响"

    _dep_info "稍后也可以手动执行: opkg update && opkg install$DEP_MISSING"


    if _dep_confirm_continue; then

        _dep_warn "已选择继续，网页界面可能不可用"

        OPENCLASH_DEPEND_CHECKED=1

        return 0

    fi


    _dep_error "已取消 OpenClash 安装"

    return 1
}

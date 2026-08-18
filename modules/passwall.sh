#!/bin/sh

# ============================================================
# Open-Pro-Installer
# PassWall Auto Installer
# ============================================================

PW_UPDATE_LOG="/tmp/openpro_passwall_update.log"
PW_INSTALL_LOG="/tmp/openpro_passwall_install.log"

PW_PACKAGE="luci-app-passwall"
PW_I18N="luci-i18n-passwall-zh-cn"

PW_PROGRESS_PID=""


# ============================================================
# 日志
# ============================================================

_pw_info()
{
    printf '\033[32m[INFO]\033[0m %s\n' "$*"
}

_pw_ok()
{
    printf '\033[32m[OK]\033[0m %s\n' "$*"
}

_pw_warn()
{
    printf '\033[33m[WARN]\033[0m %s\n' "$*"
}

_pw_error()
{
    printf '\033[31m[ERROR]\033[0m %s\n' "$*"
}


# ============================================================
# 判断软件包是否存在于软件源
# ============================================================

pw_package_exists()
{
    PACKAGE="$1"

    opkg list "$PACKAGE" 2>/dev/null |
        awk -v p="$PACKAGE" '$1 == p {found=1} END {exit !found}'
}


# ============================================================
# 判断软件包是否已经安装
# ============================================================

pw_package_installed()
{
    PACKAGE="$1"

    opkg status "$PACKAGE" 2>/dev/null |
        grep -q 'Status:.*installed'
}


# ============================================================
# PassWall 是否安装
# ============================================================

check_passwall()
{
    pw_package_installed "$PW_PACKAGE"
}


# ============================================================
# 简单进度条
# ============================================================

pw_make_bar()
{
    PERCENT="$1"
    WIDTH="${2:-30}"

    FILLED=$((PERCENT * WIDTH / 100))
    EMPTY=$((WIDTH - FILLED))

    BAR=""

    I=0
    while [ "$I" -lt "$FILLED" ]; do
        BAR="${BAR}#"
        I=$((I + 1))
    done

    I=0
    while [ "$I" -lt "$EMPTY" ]; do
        BAR="${BAR}-"
        I=$((I + 1))
    done

    printf '%s' "$BAR"
}


pw_show_progress()
{
    PERCENT="$1"
    TEXT="$2"

    BAR="$(pw_make_bar "$PERCENT" 30)"

    printf '\r\033[2K'
    printf '[\033[32m%s\033[0m] %3d%%  %s' \
        "$BAR" "$PERCENT" "$TEXT"
}


# ============================================================
# 静默安装单个软件包
# ============================================================

pw_install_package()
{
    PACKAGE="$1"
    DISPLAY_NAME="${2:-$PACKAGE}"

    if pw_package_installed "$PACKAGE"; then
        _pw_ok "$DISPLAY_NAME 已安装"
        return 0
    fi

    if ! pw_package_exists "$PACKAGE"; then
        _pw_warn "$DISPLAY_NAME 软件源中不存在，跳过"
        return 2
    fi

    _pw_info "正在安装 $DISPLAY_NAME..."

    rm -f "$PW_INSTALL_LOG"

    if opkg install "$PACKAGE" >"$PW_INSTALL_LOG" 2>&1; then

        if pw_package_installed "$PACKAGE"; then
            _pw_ok "$DISPLAY_NAME 安装完成"
            rm -f "$PW_INSTALL_LOG"
            return 0
        fi

    fi

    _pw_error "$DISPLAY_NAME 安装失败"

    if [ -s "$PW_INSTALL_LOG" ]; then
        printf "\n"
        printf "========== OPKG ERROR ==========\n"
        cat "$PW_INSTALL_LOG"
        printf "================================\n"
    fi

    return 1
}


# ============================================================
# 安装 PassWall 主程序 + 进度条
# ============================================================

pw_install_main()
{
    rm -f "$PW_INSTALL_LOG"

    pw_show_progress 5 "准备安装 PassWall"

    opkg install "$PW_PACKAGE" >"$PW_INSTALL_LOG" 2>&1 &

    PW_PROGRESS_PID=$!

    PERCENT=10

    while kill -0 "$PW_PROGRESS_PID" 2>/dev/null; do

        if grep -q '^Downloading ' "$PW_INSTALL_LOG" 2>/dev/null; then
            TEXT="正在下载软件包"
        else
            TEXT="正在准备软件包"
        fi

        if grep -q '^Installing ' "$PW_INSTALL_LOG" 2>/dev/null; then
            TEXT="正在安装软件包"
        fi

        if grep -q '^Configuring ' "$PW_INSTALL_LOG" 2>/dev/null; then
            TEXT="正在配置软件包"
        fi

        if [ "$PERCENT" -lt 92 ]; then
            PERCENT=$((PERCENT + 3))
        fi

        [ "$PERCENT" -gt 92 ] && PERCENT=92

        pw_show_progress "$PERCENT" "$TEXT"

        sleep 1

    done

    wait "$PW_PROGRESS_PID"
    RESULT=$?

    PW_PROGRESS_PID=""

    if [ "$RESULT" -eq 0 ] && check_passwall; then

        pw_show_progress 100 "PassWall 安装完成"
        printf "\n"

        rm -f "$PW_INSTALL_LOG"

        return 0

    fi

    printf "\n"

    _pw_error "PassWall 安装失败"

    if [ -s "$PW_INSTALL_LOG" ]; then

        printf "\n"
        printf "========== OPKG INSTALL ERROR =========\n"
        cat "$PW_INSTALL_LOG"
        printf "=======================================\n"

    fi

    return 1
}


# ============================================================
# 安装中文语言包
# ============================================================

pw_install_i18n()
{
    printf "\n"

    _pw_info "正在检测 PassWall 中文语言包..."

    if pw_package_installed "$PW_I18N"; then

        _pw_ok "PassWall 中文语言包已安装"
        return 0

    fi

    if pw_package_exists "$PW_I18N"; then

        _pw_info "发现：$PW_I18N"

        pw_install_package \
            "$PW_I18N" \
            "PassWall 中文语言包"

    else

        _pw_warn "没有发现 $PW_I18N，跳过"

    fi

    return 0
}


# ============================================================
# 自动检测 PassWall 相关组件
#
# 不固定写死 xx。
# 直接读取当前软件源中的 PassWall 相关组件。
# ============================================================

pw_detect_components()
{
    opkg list 2>/dev/null |
        awk '
        {
            pkg=$1

            if (
                pkg ~ /^xray-core$/ ||
                pkg ~ /^sing-box$/ ||
                pkg ~ /^v2ray-core$/ ||
                pkg ~ /^v2ray-plugin$/ ||
                pkg ~ /^trojan-plus$/ ||
                pkg ~ /^trojan-go$/ ||
                pkg ~ /^hysteria$/ ||
                pkg ~ /^hysteria2$/ ||
                pkg ~ /^naiveproxy$/ ||
                pkg ~ /^chinadns-ng$/ ||
                pkg ~ /^dns2socks$/ ||
                pkg ~ /^ipt2socks$/ ||
                pkg ~ /^microsocks$/ ||
                pkg ~ /^simple-obfs$/ ||
                pkg ~ /^shadowsocks-libev-/ ||
                pkg ~ /^shadowsocks-rust-/ ||
                pkg ~ /^shadowsocksr-libev-/ ||
                pkg ~ /^tuic-client$/ ||
                pkg ~ /^brook$/
            )
            {
                print pkg
            }
        }
        ' |
        sort -u
}


# ============================================================
# 自动安装发现的 PassWall 组件
# ============================================================

pw_install_components()
{
    printf "\n"

    _pw_info "正在自动检测 PassWall 可用组件..."

    COMPONENT_LIST="/tmp/openpro_passwall_components.list"

    rm -f "$COMPONENT_LIST"

    pw_detect_components > "$COMPONENT_LIST"

    if [ ! -s "$COMPONENT_LIST" ]; then

        _pw_warn "没有检测到额外 PassWall 组件"
        rm -f "$COMPONENT_LIST"
        return 0

    fi

    COUNT="$(
        wc -l < "$COMPONENT_LIST" 2>/dev/null |
        tr -d ' '
    )"

    [ -n "$COUNT" ] || COUNT=0

    _pw_ok "发现 $COUNT 个可用组件"

    printf "\n"

    while IFS= read -r PACKAGE
    do

        [ -n "$PACKAGE" ] || continue

        if pw_package_installed "$PACKAGE"; then

            _pw_ok "$PACKAGE 已安装"

            continue

        fi

        _pw_info "发现组件：$PACKAGE"

        rm -f "$PW_INSTALL_LOG"

        if opkg install "$PACKAGE" >"$PW_INSTALL_LOG" 2>&1; then

            _pw_ok "$PACKAGE 安装完成"

        else

            # 某个可选组件失败，不中断整个 PassWall 安装。
            _pw_warn "$PACKAGE 安装失败，已跳过"

        fi

    done < "$COMPONENT_LIST"

    rm -f "$COMPONENT_LIST"
    rm -f "$PW_INSTALL_LOG"

    return 0
}


# ============================================================
# 显示设备信息
# ============================================================

pw_show_system()
{
    PW_MODEL="unknown"
    PW_VERSION="unknown"
    PW_TARGET="unknown"
    PW_KERNEL="$(uname -r 2>/dev/null)"
    PW_ARCH="$(uname -m 2>/dev/null)"

    if [ -s /tmp/sysinfo/model ]; then
        PW_MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"
    elif [ -f /proc/device-tree/model ]; then
        PW_MODEL="$(tr -d '\000' </proc/device-tree/model 2>/dev/null)"
    fi

    if [ -f /etc/openwrt_release ]; then

        . /etc/openwrt_release

        PW_VERSION="${DISTRIB_RELEASE:-unknown}"
        PW_TARGET="${DISTRIB_TARGET:-unknown}"

    fi

    printf "\n"
    printf "======================================\n"
    printf "          设备检测结果\n"
    printf "======================================\n"
    printf "机型     : %s\n" "$PW_MODEL"
    printf "OpenWrt  : %s\n" "$PW_VERSION"
    printf "Target   : %s\n" "$PW_TARGET"
    printf "Kernel   : %s\n" "$PW_KERNEL"
    printf "架构     : %s\n" "$PW_ARCH"
    printf "======================================\n"
    printf "\n"
}


# ============================================================
# 中断处理
# ============================================================

pw_interrupt()
{
    printf "\n"

    _pw_warn "PassWall 安装被中断"

    if [ -n "$PW_PROGRESS_PID" ]; then

        kill "$PW_PROGRESS_PID" 2>/dev/null
        wait "$PW_PROGRESS_PID" 2>/dev/null

    fi

    rm -f "$PW_UPDATE_LOG"
    rm -f "$PW_INSTALL_LOG"
    rm -f /tmp/openpro_passwall_components.list

    trap - INT TERM

    return 130
}


# ============================================================
# 主安装函数
#
# install.sh 调用：
#
# install_passwall
#
# ============================================================

install_passwall()
{
    printf "\n"
    printf "======================================\n"
    printf "          PassWall Installer\n"
    printf "======================================\n"
    printf "\n"


    # ========================================================
    # ROOT
    # ========================================================

    if [ "$(id -u 2>/dev/null)" != "0" ]; then

        _pw_error "请使用 root 用户运行"

        return 1

    fi


    # ========================================================
    # OPKG
    # ========================================================

    if ! command -v opkg >/dev/null 2>&1; then

        if command -v apk >/dev/null 2>&1; then

            _pw_error "当前系统使用 APK 包管理器"
            _pw_warn "这个 PassWall 安装模块目前只支持 OPKG"

        else

            _pw_error "没有检测到 OPKG"

        fi

        return 1

    fi


    _pw_info "Package Manager : opkg"


    # ========================================================
    # 设备信息
    # ========================================================

    pw_show_system


    # ========================================================
    # 更新软件列表
    # ========================================================

    _pw_info "正在更新软件列表..."

    rm -f "$PW_UPDATE_LOG"


    if ! opkg update >"$PW_UPDATE_LOG" 2>&1; then

        _pw_error "软件列表更新失败"

        if [ -s "$PW_UPDATE_LOG" ]; then

            printf "\n"
            printf "========== OPKG UPDATE ERROR ==========\n"
            cat "$PW_UPDATE_LOG"
            printf "=======================================\n"

        fi

        rm -f "$PW_UPDATE_LOG"

        return 1

    fi


    rm -f "$PW_UPDATE_LOG"

    _pw_ok "软件列表更新完成"


    # ========================================================
    # 查询 PassWall
    # ========================================================

    printf "\n"

    _pw_info "正在查询 luci-app-passwall..."


    if ! pw_package_exists "$PW_PACKAGE"; then

        _pw_error "当前软件源中没有找到 luci-app-passwall"

        printf "\n"
        _pw_warn "没有修改你的原始软件源"
        _pw_warn "请先确认当前设备的软件源是否提供 PassWall"

        return 2

    fi


    _pw_ok "已找到 luci-app-passwall"


    PW_VERSION="$(
        opkg list "$PW_PACKAGE" 2>/dev/null |
        awk -F ' - ' 'NR==1 {print $2}'
    )"


    if [ -n "$PW_VERSION" ]; then

        _pw_info "PassWall Version : $PW_VERSION"

    fi


    # ========================================================
    # 主程序
    # ========================================================

    printf "\n"


    if check_passwall; then

        _pw_ok "PassWall 主程序已经安装"

    else

        _pw_info "开始安装 PassWall..."

        printf "\n"

        trap 'pw_interrupt' INT TERM

        if ! pw_install_main; then

            trap - INT TERM

            return 1

        fi

        trap - INT TERM

    fi


    # ========================================================
    # 中文包
    # ========================================================

    pw_install_i18n


    # ========================================================
    # 自动发现组件
    # ========================================================

    pw_install_components


    # ========================================================
    # 最终验证
    # ========================================================

    printf "\n"

    _pw_info "正在检查安装结果..."


    if ! check_passwall; then

        _pw_error "未检测到 luci-app-passwall"

        return 1

    fi


    _pw_ok "PassWall 安装成功"


    # ========================================================
    # 启用服务
    # ========================================================

    if [ -x /etc/init.d/passwall ]; then

        _pw_info "正在启用 PassWall 服务..."

        /etc/init.d/passwall enable >/dev/null 2>&1

        _pw_ok "PassWall 开机启动已启用"

    fi


    # ========================================================
    # 清理
    # ========================================================

    rm -f "$PW_UPDATE_LOG"
    rm -f "$PW_INSTALL_LOG"
    rm -f /tmp/openpro_passwall_components.list


    # ========================================================
    # 完成
    # ========================================================

    printf "\n"
    printf "======================================\n"
    printf "          PassWall Installed\n"
    printf "======================================\n"
    printf "\n"

    _pw_ok "PassWall 安装完成"

    if pw_package_installed "$PW_I18N"; then
        _pw_ok "PassWall 中文语言包已安装"
    fi

    printf "\n"
    printf "请进入 LuCI 后台查看：\n"
    printf "服务 → PassWall\n"
    printf "\n"

    return 0
}

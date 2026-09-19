#!/bin/sh


check_openclash_depend()
{


echo ""

echo "[INFO] 检查 OpenClash 依赖..."



# 检查包管理器

if command -v opkg >/dev/null 2>&1
then

    PM="opkg"

else

    echo "[WARN] 非 opkg 系统，跳过依赖检测"

    return

fi




# ==========================
# 检查 luci-lib-ipkg
# ==========================


if opkg list-installed | grep -q "^luci-lib-ipkg "
then


    echo "[OK] luci-lib-ipkg 已安装"



else


    echo "[WARN] luci-lib-ipkg 未安装"


    echo "[INFO] 更新软件源..."

    opkg update >/dev/null 2>&1



    if opkg list | grep -q "^luci-lib-ipkg "
    then


        echo "[INFO] 正在安装 luci-lib-ipkg..."


        opkg install luci-lib-ipkg


    else


        echo "[WARN] 软件源不存在 luci-lib-ipkg，跳过"


    fi


fi






# ==========================
# 检查 luci-compat
# ==========================


if opkg list-installed | grep -q "^luci-compat "
then


    echo "[OK] luci-compat 已安装"



else


    echo "[WARN] luci-compat 未安装"



    echo "[INFO] 更新软件源..."

    opkg update >/dev/null 2>&1



    if opkg list | grep -q "^luci-compat "
    then


        echo "[INFO] 正在安装 luci-compat..."


        opkg install luci-compat


    else


        echo "[WARN] 软件源不存在 luci-compat，跳过"


    fi


fi




echo ""

echo "[INFO] 依赖检测完成"


}

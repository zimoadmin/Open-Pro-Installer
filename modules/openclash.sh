#!/bin/sh


install_openclash()
{


    info "Ready to install OpenClash"


    info "Version : $RELEASE_TAG"



    # ==============================
    # 清理下载地址
    # ==============================


    DOWNLOAD_URL="$(printf '%s' "$DOWNLOAD_URL" | tr -d '\r\n')"



    # 去除可能存在的空格
    DOWNLOAD_URL="$(echo "$DOWNLOAD_URL" | sed 's/[[:space:]]//g')"



    if [ -z "$DOWNLOAD_URL" ]
    then

        error "Download URL is empty!"

        return 1

    fi



    info "URL : $DOWNLOAD_URL"




    # ==============================
    # 文件路径
    # ==============================


    PKG_FILE="/tmp/luci-app-openclash.${PACKAGE_EXT}"



    info "Downloading..."



    # ==============================
    # 下载
    # ==============================


    if ! wget \
        --no-check-certificate \
        -O "$PKG_FILE" \
        "$DOWNLOAD_URL"
    then

        error "Download failed!"

        error "URL: $DOWNLOAD_URL"

        return 1

    fi




    # ==============================
    # 检查文件
    # ==============================


    if [ ! -s "$PKG_FILE" ]
    then

        error "Downloaded file is empty!"

        rm -f "$PKG_FILE"

        return 1

    fi



    info "Download complete."

    ls -lh "$PKG_FILE"




    # ==============================
    # 安装
    # ==============================


    info "Installing..."



    if [ "$PACKAGE_EXT" = "apk" ]
    then


        apk add \
        --allow-untrusted \
        --force-overwrite \
        --clean-protected \
        "$PKG_FILE"



    elif [ "$PACKAGE_EXT" = "ipk" ]
    then


        opkg install "$PKG_FILE"



    else


        error "Unknown package type: $PACKAGE_EXT"

        return 1


    fi




    # ==============================
    # 安装结果
    # ==============================


    if [ $? -eq 0 ]
    then

        info "OpenClash installed successfully!"

    else

        error "OpenClash installation failed!"

        return 1

    fi


}

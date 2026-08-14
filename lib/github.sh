#!/bin/sh


# ==============================
# Open-Pro Worker
# ==============================


OPENCLASH_API="https://openpro-auth.zimo4399.workers.dev/openclash"



get_latest_release()
{


    info "Getting latest OpenClash release..."



    # ==============================
    # 获取 Worker 数据
    # ==============================


    if ! curl -fsSL "$OPENCLASH_API" -o /tmp/openclash_version
    then

        error "Failed to download release information."

        return 1

    fi



    # ==============================
    # 获取版本
    # ==============================


    RELEASE_TAG="$(
        jsonfilter \
        -i /tmp/openclash_version \
        -e '@.version'
    )"



    if [ -z "$RELEASE_TAG" ]
    then

        error "Failed to get version."

        cat /tmp/openclash_version

        return 1

    fi




    # ==============================
    # 获取 ipk / apk
    # ==============================


    IPK_URL="$(
        jsonfilter \
        -i /tmp/openclash_version \
        -e '@.ipk'
    )



    APK_URL="$(
        jsonfilter \
        -i /tmp/openclash_version \
        -e '@.apk'
    )



    # ==============================
    # 判断系统包格式
    # ==============================


    if command -v apk >/dev/null 2>&1
    then

        PACKAGE_EXT="apk"

        DOWNLOAD_URL="$APK_URL"


    elif command -v opkg >/dev/null 2>&1
    then

        PACKAGE_EXT="ipk"

        DOWNLOAD_URL="$IPK_URL"


    else

        error "Unsupported package manager."

        return 1

    fi




    if [ -z "$DOWNLOAD_URL" ]
    then

        error "Download URL empty."

        cat /tmp/openclash_version

        return 1

    fi




    info "Latest Version : $RELEASE_TAG"

    info "Package Type   : $PACKAGE_EXT"

    info "Download URL   : $DOWNLOAD_URL"



    export RELEASE_TAG

    export PACKAGE_EXT

    export DOWNLOAD_URL

    export IPK_URL

    export APK_URL



    return 0


}

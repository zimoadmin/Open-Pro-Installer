#!/bin/sh


OPENCLASH_API="https://openpro-auth.zimo4399.workers.dev/openclash"



get_latest_release()
{


    info "Getting latest OpenClash release..."



    if ! curl -fsSL "$OPENCLASH_API" -o /tmp/openclash_version
    then

        error "Failed to download release information."

        return 1

    fi



    RELEASE_TAG="$(

    jsonfilter \
    -i /tmp/openclash_version \
    -e '@.version'

    )"



    if [ -z "$RELEASE_TAG" ]
    then

        error "Version empty"

        cat /tmp/openclash_version

        return 1

    fi





    # 判断系统

    if command -v apk >/dev/null 2>&1
    then

        PACKAGE_EXT="apk"

        DOWNLOAD_URL="$(

        jsonfilter \
        -i /tmp/openclash_version \
        -e '@.apk'

        )"


    elif command -v opkg >/dev/null 2>&1
    then

        PACKAGE_EXT="ipk"

        DOWNLOAD_URL="$(

        jsonfilter \
        -i /tmp/openclash_version \
        -e '@.ipk'

        )"


    else

        error "Unsupported package manager"

        return 1

    fi





    # 清理

    DOWNLOAD_URL="$(echo "$DOWNLOAD_URL" | tr -d '\r\n ')"




    if [ -z "$DOWNLOAD_URL" ]
    then

        error "Download URL empty"

        cat /tmp/openclash_version

        return 1

    fi





    info "Latest Version : $RELEASE_TAG"

    info "Package Type   : $PACKAGE_EXT"

    info "Download URL   : $DOWNLOAD_URL"



    export RELEASE_TAG
    export PACKAGE_EXT
    export DOWNLOAD_URL



}

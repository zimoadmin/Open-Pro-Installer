#!/bin/sh


# ==============================
# OpenClash Release API
# ==============================


OPENCLASH_API="https://auth.12334123.xyz/openclash"


CACHE_FILE="/tmp/openclash_version"



get_latest_release()
{


info "Getting latest OpenClash release..."



# ==============================
# 缓存检测
# ==============================


if [ -f "$CACHE_FILE" ]
then


    CACHE_TIME=$(stat -c %Y "$CACHE_FILE" 2>/dev/null)


    NOW_TIME=$(date +%s)


    AGE=$((NOW_TIME-CACHE_TIME))


    if [ "$AGE" -lt 3600 ]
    then

        info "Using cached release information"

    else

        rm -f "$CACHE_FILE"

    fi

fi




# ==============================
# 获取 Worker
# ==============================


if [ ! -f "$CACHE_FILE" ]
then


    info "Connecting Worker..."



    if ! curl \
    -fsSL \
    --connect-timeout 10 \
    --max-time 15 \
    "$OPENCLASH_API" \
    -o "$CACHE_FILE"
    then


        error "Failed to download release information."


        return 1


    fi



fi





# ==============================
# 检查返回
# ==============================


if [ ! -s "$CACHE_FILE" ]
then


error "Release data empty"


return 1


fi





# ==============================
# 获取版本
# ==============================


RELEASE_TAG="$(

jsonfilter \
-i "$CACHE_FILE" \
-e '@.version'

)"




if [ -z "$RELEASE_TAG" ]
then


error "Version empty"


cat "$CACHE_FILE"


return 1


fi






# ==============================
# 判断系统
# ==============================


if command -v apk >/dev/null 2>&1
then


PACKAGE_EXT="apk"


DOWNLOAD_URL="$(

jsonfilter \
-i "$CACHE_FILE" \
-e '@.apk'

)"



elif command -v opkg >/dev/null 2>&1
then


PACKAGE_EXT="ipk"


DOWNLOAD_URL="$(

jsonfilter \
-i "$CACHE_FILE" \
-e '@.ipk'

)"



else


error "Unsupported package manager"


return 1


fi





# ==============================
# URL清理
# ==============================


DOWNLOAD_URL="$(

echo "$DOWNLOAD_URL" |

sed '

s/[[:space:]]//g

s/APK_URL=.*$//

s/IPK_URL=.*$//

'

)"





# ==============================
# URL检测
# ==============================


case "$DOWNLOAD_URL" in


http://*|https://*)

;;


*)

error "Invalid download URL"

printf "%s\n" "$DOWNLOAD_URL"

return 1

;;


esac





# ==============================
# 输出
# ==============================


info "Latest Version : $RELEASE_TAG"

info "Package Type   : $PACKAGE_EXT"

info "Download URL   : $DOWNLOAD_URL"





export RELEASE_TAG

export PACKAGE_EXT

export DOWNLOAD_URL



return 0



}

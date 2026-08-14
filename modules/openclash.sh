#!/bin/sh


# ==============================
# OpenClash Installer
# ==============================


install_openclash()
{


info "Ready to install OpenClash"

info "Version : $RELEASE_TAG"

info "Package : $PACKAGE_EXT"

info "URL : $DOWNLOAD_URL"



PKG_FILE="/tmp/openclash.${PACKAGE_EXT}"



# ==============================
# 下载
# ==============================


info "Downloading OpenClash..."



retry=3


while [ $retry -gt 0 ]
do


wget \
-T 10 \
-O "$PKG_FILE" \
"$DOWNLOAD_URL"


if [ $? -eq 0 ]
then

break

fi


retry=$((retry-1))


warning "Download failed, retry..."

sleep 2


done



if [ ! -f "$PKG_FILE" ]
then

error "Download failed!"

return 1

fi




SIZE=$(ls -lh "$PKG_FILE" | awk '{print $5}')


info "File size : $SIZE"




# ==============================
# 安装
# ==============================


info "Installing..."



if [ "$PACKAGE_EXT" = "apk" ]
then


apk add \
--allow-untrusted \
--force-overwrite \
"$PKG_FILE"



else


opkg install "$PKG_FILE"


fi



if [ $? -eq 0 ]
then

info "OpenClash installed successfully!"

else

error "OpenClash installation failed!"

return 1

fi



}

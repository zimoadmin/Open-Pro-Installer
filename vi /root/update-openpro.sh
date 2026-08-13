#!/bin/sh

cd /tmp || exit 1

rm -rf Open-Pro-Installer-main
rm -f main.zip

echo "Downloading latest Open-Pro-Installer..."

wget -q -O main.zip https://github.com/zimoadmin/Open-Pro-Installer/archive/refs/heads/main.zip || exit 1

unzip -oq main.zip || exit 1

cd Open-Pro-Installer-main || exit 1

chmod +x install.sh lib/*.sh modules/*.sh

exec ./install.sh

#!/bin/sh

install_openclash() {

    info "Ready to install OpenClash"
    info "Version : $RELEASE_TAG"
    info "URL : $DOWNLOAD_URL"

    PKG_FILE="/tmp/openclash.${PACKAGE_EXT}"

    info "Downloading..."

    if ! wget -O "$PKG_FILE" "$DOWNLOAD_URL"; then
        error "Download failed!"
        return 1
    fi

    info "Download complete."

    ls -lh "$PKG_FILE"

    info "Installing..."

    if [ "$PACKAGE_EXT" = "apk" ]; then
        apk add \
            --allow-untrusted \
            --force-overwrite \
            --clean-protected \
            "$PKG_FILE"
    else
        opkg install "$PKG_FILE"
    fi

    if [ $? -eq 0 ]; then
        info "OpenClash installed successfully!"
    else
        error "OpenClash installation failed!"
        return 1
    fi
}

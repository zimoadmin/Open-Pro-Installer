case "$CHOOSE" in
1)
    echo "===== STEP 1 ====="

    get_latest_release

    echo "===== STEP 2 ====="

    . "$SCRIPT_DIR/modules/openclash.sh"

    echo "===== STEP 3 ====="

    install_openclash

    echo "===== STEP 4 ====="
    ;;
esac

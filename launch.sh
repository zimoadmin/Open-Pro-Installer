#!/bin/sh
# Download a pinned, verified bootstrap before executing any authentication flow.
case "${1:-email}" in
    email) file=bootstrap.sh; expected=780558975d69d6ce5b942be3096622ba2bbc7d7c352e91404d24348164456c76 ;;
    payment) file=bootstrap-pay.sh; expected=357173f93b373aedd105c89cc430ad22915b6d2c5350e66fe9beabbf80abbdfc ;;
    *) echo 'Usage: sh launch.sh [email|payment]' >&2; exit 2 ;;
esac
for tool in curl sha256sum sh mktemp date sleep; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Missing required tool: $tool" >&2; exit 1; }
done
work=$(mktemp -d /tmp/opi-launch.XXXXXX) || exit 1
pids=''
cleanup() {
    for pid in $pids; do kill "$pid" 2>/dev/null || :; done
    for pid in $pids; do wait "$pid" 2>/dev/null || :; done
    rm -rf "$work"
}
trap cleanup 0
trap 'exit 130' INT
trap 'exit 143' TERM
worker() {
    route=$1; url=$2; request_pid=''
    trap '[ -z "$request_pid" ] || { kill "$request_pid" 2>/dev/null; wait "$request_pid" 2>/dev/null; }' 0
    trap 'exit 130' INT
    trap 'exit 143' TERM
    curl -4 -fLsS --connect-timeout 10 --max-time 30 --retry 0 \
        -o "$work/$route.part" "$url" >"$work/$route.log" 2>&1 &
    request_pid=$!
    rc=0
    wait "$request_pid" || rc=$?
    request_pid=''
    if [ "$rc" -eq 0 ]; then
        actual=$(sha256sum "$work/$route.part" | awk '{print $1}')
        if [ "$actual" = "$expected" ] && sh -n "$work/$route.part" 2>>"$work/$route.log"; then
            if mkdir "$work/winner" 2>/dev/null; then
                if mv "$work/$route.part" "$work/bootstrap.sh"; then
                    printf '%s\n' "$route" > "$work/ready"
                fi
            fi
        else
            echo 'Rejected: content does not match the pinned bootstrap' >>"$work/$route.log"
        fi
    fi
    : > "$work/$route.done"
}
raw="https://raw.githubusercontent.com/zimoadmin/Open-Pro-Installer/b639a7667949543ec9bed05d5220414ff6302c4e/$file"
count=0
while IFS='|' read -r route prefix; do
    worker "$route" "$prefix$raw" &
    pids="$pids $!"
    count=$((count + 1))
done <<'ROUTES'
GH01|https://down.mxw.xx.kg/
GH02|https://ghproxy.icu/
GH03|https://github.mxw.qzz.io/
GH04|https://xsadwsd.kdns.fr/
GH05|https://v4.gh-proxy.org/
DIRECT|
ROUTES
start=$(date +%s)
while :; do
    elapsed=$(( $(date +%s) - start ))
    printf '\rDownloading bootstrap: %s routes, %ss / 35s' "$count" "$elapsed" >&2
    if [ -s "$work/ready" ]; then
        printf '\nBootstrap verified [%s]\n' "$(cat "$work/ready")" >&2
        break
    fi
    done_count=0
    for flag in "$work"/*.done; do
        [ ! -f "$flag" ] || done_count=$((done_count + 1))
    done
    if [ "$done_count" -eq "$count" ] || [ "$elapsed" -ge 35 ]; then
        printf '\nBootstrap download failed; nothing executed.\n' >&2
        for log in "$work"/*.log; do
            printf '\n%s\n' "${log##*/}" >&2
            cat "$log" >&2
        done
        exit 1
    fi
    sleep 1
done
# Stop network workers before launching the interactive bootstrap.
for pid in $pids; do kill "$pid" 2>/dev/null || :; done
for pid in $pids; do wait "$pid" 2>/dev/null || :; done
pids=''
if [ -r /dev/tty ]; then
    sh "$work/bootstrap.sh" </dev/tty
else
    sh "$work/bootstrap.sh"
fi
exit $?

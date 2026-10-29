#!/usr/bin/env bash
# Back up the current (LineageOS) boot partition, then flash exinux boot.img.
#
# 1. Phone booted into LineageOS with "Rooted debugging" enabled: this script
#    saves backup/lineage-boot.img first (only once).
# 2. It then reboots the phone to Download mode and flashes with Heimdall.
#    (Windows: use Odin, AP slot, out/exinux-boot.tar.)
#
# Going back to LineageOS: scripts/flash.sh --restore
set -euo pipefail
. "$(dirname "$0")/../config.sh"
BACKUP=$TOP/backup/lineage-boot.img

need() { command -v "$1" >/dev/null || { echo "!! install $1"; exit 1; }; }
need heimdall

if [ "${1:-}" = --restore ]; then
    [ -f "$BACKUP" ] || { echo "!! no $BACKUP"; exit 1; }
    IMG=$BACKUP
else
    IMG=$OUT/boot.img
    [ -f "$IMG" ] || { echo "!! build out/boot.img first"; exit 1; }
    if [ ! -f "$BACKUP" ]; then
        need adb
        echo ">> backing up current boot partition"
        adb wait-for-device; adb root >/dev/null; adb wait-for-device
        mkdir -p "$(dirname "$BACKUP")"
        adb exec-out 'dd if=/dev/block/by-name/boot 2>/dev/null' > "$BACKUP"
        [ "$(stat -c %s "$BACKUP")" = "$BOOT_PARTITION_SIZE" ] ||
            { echo "!! backup has unexpected size"; rm -f "$BACKUP"; exit 1; }
        echo ">> saved $BACKUP"
    fi
fi

if command -v adb >/dev/null && adb get-state >/dev/null 2>&1; then
    adb reboot download
    sleep 10
fi
echo ">> waiting for Download mode (Vol Down + Vol Up while plugging USB)"
until heimdall detect >/dev/null 2>&1; do sleep 2; done
heimdall flash --BOOT "$IMG"
echo ">> flashed $(basename "$IMG")"

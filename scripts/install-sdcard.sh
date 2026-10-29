#!/usr/bin/env bash
# Write out/rootfs.img to a microSD card (run on your PC, as root).
# ALL DATA ON THE CARD IS ERASED.
#
#   sudo scripts/install-sdcard.sh /dev/sdX
set -euo pipefail
. "$(dirname "$0")/../config.sh"

dev=${1:-}
[ -b "$dev" ] || { echo "usage: $0 /dev/sdX   (the whole card, not a partition)"; exit 1; }
[ -f "$OUT/rootfs.img" ] || { echo "!! build out/rootfs.img first"; exit 1; }
case "$(lsblk -ndo TRAN "$dev" 2>/dev/null)" in
    usb|mmc|sd) ;;
    *) echo "!! $dev is not a USB/MMC device; refusing (edit the script if you are sure)"; exit 1 ;;
esac

lsblk "$dev"
read -r -p "Erase $dev and install exinux? Type YES: " ok
[ "$ok" = YES ] || exit 1

umount "$dev"* 2>/dev/null || true
sfdisk "$dev" <<PART
label: gpt
,,L,
PART
partprobe "$dev"; sleep 2
part=$(lsblk -nlpo NAME "$dev" | sed -n 2p)
dd if="$OUT/rootfs.img" of="$part" bs=4M conv=fsync status=progress
e2fsck -fy "$part" || true
resize2fs "$part"
e2label "$part" exinux
sync
echo ">> done: $part (label exinux). Insert the card in the phone and flash out/boot.img."

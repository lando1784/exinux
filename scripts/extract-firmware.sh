#!/usr/bin/env bash
# Copy the firmware exinux needs from the phone while it runs LineageOS.
#
# Firmware is proprietary and device-specific, so it is never committed here.
# On the phone: Settings > System > Developer options > enable
# "Rooted debugging", connect USB, accept the prompt. Then run this script.
#
# Output: $FIRMWARE_DIR/ (laid out like /lib/firmware on the phone)
set -euo pipefail
. "$(dirname "$0")/../config.sh"

command -v adb >/dev/null || { echo "!! install adb (android-tools)"; exit 1; }

adb wait-for-device
adb root >/dev/null
adb wait-for-device

model=$(adb shell getprop ro.product.device | tr -d '\r')
case "$model" in
    r8s) ;;
    *) echo "!! connected device is '$model', expected r8s (SM-G780F)"; exit 1 ;;
esac

mkdir -p "$FIRMWARE_DIR"
echo ">> pulling /vendor/firmware"
adb pull /vendor/firmware/. "$FIRMWARE_DIR/"

# Bluetooth (QCA6390): mainline btqca looks for these names under qca/.
mkdir -p "$FIRMWARE_DIR/qca"
for f in htbtfw20.tlv htnv20.bin; do
    [ -f "$FIRMWARE_DIR/$f" ] && cp "$FIRMWARE_DIR/$f" "$FIRMWARE_DIR/qca/$f"
done

# Wi-Fi MAC: Samsung keeps it in EFS; qcacld reads wlan/wlan_mac.bin.
mac=$(adb shell 'cat /mnt/vendor/efs/wifi/.mac.info 2>/dev/null || cat /efs/wifi/.mac.info 2>/dev/null' |
      tr -d '\r\n' | tr -d ':' | tr 'A-F' 'a-f')
if [ ${#mac} = 12 ]; then
    mkdir -p "$FIRMWARE_DIR/wlan"
    next=$(printf '%012x' $(( 0x$mac + 1 )))
    printf 'Intf0MacAddress=%s\nIntf1MacAddress=%s\nEND\n' "$mac" "$next" \
        > "$FIRMWARE_DIR/wlan/wlan_mac.bin"
    echo ">> Wi-Fi MAC $mac"
else
    echo "!! could not read the Wi-Fi MAC from EFS; the driver will pick a random one"
fi

for f in qca6390/amss20.bin qca6390/bdwlan.elf qca6390/m3.bin wlan/qcom_cfg.ini; do
    [ -f "$FIRMWARE_DIR/$f" ] || echo "!! missing $f, Wi-Fi will not start"
done
echo ">> firmware in $FIRMWARE_DIR ($(du -sh "$FIRMWARE_DIR" | cut -f1))"

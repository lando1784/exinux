#!/usr/bin/env bash
# Pack the exinux initramfs and boot.img.
#
# Needs: $OUT/kernel/{Image,dtb.img} from build-kernel.sh
# Output: $OUT/boot.img, $OUT/exinux-boot.tar (Odin "AP" slot)
set -euo pipefail
. "$(dirname "$0")/../config.sh"

RAMDISK=$WORK/initramfs
DEB_CACHE=$WORK/debs

# Download one arm64 package from the Debian mirror without needing apt for arm64.
fetch_deb() {
    local pkg=$1 idx=$DEB_CACHE/Packages-$DEBIAN_SUITE
    mkdir -p "$DEB_CACHE"
    if [ ! -s "$idx" ]; then
        curl -fsSL "$DEBIAN_MIRROR/dists/$DEBIAN_SUITE/main/binary-arm64/Packages.xz" | xz -d > "$idx"
    fi
    local file
    file=$(awk -v p="$pkg" '$1=="Package:"{cur=$2} cur==p && $1=="Filename:"{print $2; exit}' "$idx")
    [ -n "$file" ] || { echo "!! $pkg not found in $DEBIAN_MIRROR $DEBIAN_SUITE" >&2; exit 1; }
    [ -f "$DEB_CACHE/$(basename "$file")" ] ||
        curl -fsSL -o "$DEB_CACHE/$(basename "$file")" "$DEBIAN_MIRROR/$file"
    echo "$DEB_CACHE/$(basename "$file")"
}

build_initramfs() {
    rm -rf "$RAMDISK"
    mkdir -p "$RAMDISK"/{bin,sbin,dev,proc,sys,run,tmp,mnt,config}
    local deb tmp
    deb=$(fetch_deb busybox-static)
    tmp=$(mktemp -d)
    dpkg-deb -x "$deb" "$tmp"
    install -m755 "$(ls "$tmp"/bin/busybox "$tmp"/usr/bin/busybox 2>/dev/null | head -n1)" "$RAMDISK/bin/busybox"
    rm -rf "$tmp"
    file "$RAMDISK/bin/busybox" | grep -Eq 'ARM aarch64.*static(ally|-pie) linked' ||
        { echo "!! busybox is not a static arm64 binary"; exit 1; }
    install -m755 "$TOP/initramfs/init" "$RAMDISK/init"
    (cd "$RAMDISK" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet | gzip -9) \
        > "$WORK/initramfs.cpio.gz"
}

build_bootimg() {
    # shellcheck disable=SC2086
    mkbootimg $BOOTIMG_ARGS \
        --kernel "$OUT/kernel/Image" \
        --ramdisk "$WORK/initramfs.cpio.gz" \
        --dtb "$OUT/kernel/dtb.img" \
        --cmdline "$EXINUX_CMDLINE" \
        --os_version 16.0.0 --os_patch_level 2025-07 \
        --output "$OUT/boot.img"
    local size
    size=$(stat -c %s "$OUT/boot.img")
    [ "$size" -le "$BOOT_PARTITION_SIZE" ] ||
        { echo "!! boot.img is $size bytes, partition holds $BOOT_PARTITION_SIZE"; exit 1; }
    # Odin wants a tar; Heimdall flashes boot.img directly.
    tar -C "$OUT" -H ustar -cf "$OUT/exinux-boot.tar" boot.img
    echo ">> $OUT/boot.img ($size bytes), $OUT/exinux-boot.tar"
}

[ -f "$OUT/kernel/Image" ] || { echo "!! run scripts/build-kernel.sh first"; exit 1; }
mkdir -p "$WORK"
build_initramfs
build_bootimg

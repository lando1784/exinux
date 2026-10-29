#!/usr/bin/env bash
# Build the Debian arm64 root filesystem image (run as root on an x86 PC;
# uses qemu-user-static to run arm64 binaries in the chroot).
#
# Output: $OUT/rootfs.img (ext4, label "exinux")
set -euo pipefail
. "$(dirname "$0")/../config.sh"

ROOT=$WORK/rootfs

DESKTOP_DIR=$TOP/rootfs/desktop/$DESKTOP
[ -f "$DESKTOP_DIR/packages" ] ||
    { echo "!! unknown DESKTOP=$DESKTOP (see rootfs/desktop/)"; exit 1; }

# Base system, installed without recommends.
PACKAGES=${PACKAGES:-"
    systemd-sysv udev dbus dbus-user-session libpam-systemd sudo locales
    ca-certificates openssh-server busybox-static less nano htop
    network-manager wpasupplicant iw rfkill
    bluez
    firefox-esr fonts-noto-core
"}
# The desktop is installed with recommends: metapackages rely on them.
DESKTOP_PACKAGES=${DESKTOP_PACKAGES:-$(sed 's/#.*//' "$DESKTOP_DIR/packages")}

[ "$(id -u)" = 0 ] || { echo "!! run as root (debootstrap + chroot)"; exit 1; }

ensure_binfmt() {
    [ "$(uname -m)" = aarch64 ] && return
    if [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
        mountpoint -q /proc/sys/fs/binfmt_misc ||
            mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
        cat /usr/lib/binfmt.d/qemu-aarch64.conf > /proc/sys/fs/binfmt_misc/register
    fi
}

in_chroot() {
    chroot "$ROOT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
        DEBIAN_FRONTEND=noninteractive LC_ALL=C "$@"
}

mount_chroot() {
    for d in proc sys dev dev/pts; do mkdir -p "$ROOT/$d"; done
    mount -t proc proc "$ROOT/proc"
    mount -t sysfs sysfs "$ROOT/sys"
    mount --bind /dev "$ROOT/dev"
    mount --bind /dev/pts "$ROOT/dev/pts"
    trap umount_chroot EXIT
}

umount_chroot() {
    for d in dev/pts dev sys proc; do umount -l "$ROOT/$d" 2>/dev/null || true; done
}

bootstrap() {
    rm -rf "$ROOT"
    debootstrap --arch=arm64 --variant=minbase \
        --include=apt-utils,gnupg,ca-certificates \
        --components="$DEBIAN_COMPONENTS" \
        "$DEBIAN_SUITE" "$ROOT" "$DEBIAN_MIRROR"
}

install_packages() {
    cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
    in_chroot apt-get update
    # shellcheck disable=SC2086
    in_chroot apt-get install -y --no-install-recommends $PACKAGES
    # shellcheck disable=SC2086
    in_chroot apt-get install -y $DESKTOP_PACKAGES
    in_chroot apt-get clean
}

install_exinux_bits() {
    cp -a "$TOP/rootfs/overlay/." "$ROOT/"
    cp -a "$DESKTOP_DIR/overlay/." "$ROOT/"
    # environment.d covers systemd user units; pam_env covers the session itself.
    if [ -f "$ROOT/etc/environment.d/50-exinux.conf" ]; then
        grep -v '^#' "$ROOT/etc/environment.d/50-exinux.conf" >> "$ROOT/etc/environment"
    fi
    aarch64-linux-gnu-gcc -O2 -Wall -static \
        -o "$ROOT/usr/local/sbin/exinux-fb-refresher" \
        "$TOP/src/fb-refresher/fb-refresher.c"

    if [ -d "$FIRMWARE_DIR" ] && [ -n "$(ls -A "$FIRMWARE_DIR" 2>/dev/null)" ]; then
        mkdir -p "$ROOT/lib/firmware"
        cp -a "$FIRMWARE_DIR/." "$ROOT/lib/firmware/"
    else
        echo "!! no firmware in $FIRMWARE_DIR: Wi-Fi will not work."
        echo "!! run scripts/extract-firmware.sh with the phone on LineageOS, then rebuild."
    fi

    echo "$EXINUX_HOSTNAME" > "$ROOT/etc/hostname"
    printf '127.0.0.1\tlocalhost\n127.0.1.1\t%s\n' "$EXINUX_HOSTNAME" > "$ROOT/etc/hosts"
    echo "en_US.UTF-8 UTF-8" > "$ROOT/etc/locale.gen"
    in_chroot locale-gen
    echo 'LANG=en_US.UTF-8' > "$ROOT/etc/default/locale"
    # No /etc/fstab entries: the initramfs mounts / read-write.
    : > "$ROOT/etc/fstab"

    if ! in_chroot id "$EXINUX_USER" >/dev/null 2>&1; then
        in_chroot useradd -m -s /bin/bash \
            -G sudo,video,input,netdev,bluetooth,plugdev,dialout "$EXINUX_USER" ||
        in_chroot useradd -m -s /bin/bash -G sudo,video,input "$EXINUX_USER"
    fi
    echo "$EXINUX_USER:$EXINUX_PASSWORD" | in_chroot chpasswd

    in_chroot systemctl enable exinux-fb-refresher.service exinux-wlan.service \
        exinux-grow-rootfs.service exinux-usb-gadget.service \
        ssh.service NetworkManager.service
    in_chroot systemctl enable "$(cat "$DESKTOP_DIR/display-manager")"
    rm -f "$ROOT/etc/resolv.conf"
    ln -sf ../run/NetworkManager/resolv.conf "$ROOT/etc/resolv.conf"
}

make_image() {
    rm -f "$OUT/rootfs.img"
    mkdir -p "$OUT"
    truncate -s "$ROOTFS_SIZE" "$OUT/rootfs.img"
    # Old e2fsprogs features only: the 4.19 kernel predates some newer defaults.
    mkfs.ext4 -q -L exinux -O ^metadata_csum_seed,^orphan_file \
        -d "$ROOT" "$OUT/rootfs.img"
    echo ">> $OUT/rootfs.img"
}

mkdir -p "$WORK" "$OUT"
ensure_binfmt
bootstrap
mount_chroot
install_packages
install_exinux_bits
umount_chroot
trap - EXIT
make_image

# Pinned inputs for an exinux build. Sourced by every script in scripts/.
# Override any of these from the environment, e.g. DEBIAN_MIRROR=... make rootfs

# Device
DEVICE=r8s                       # Galaxy S20 FE 4G (SM-G780F), Exynos 990
DEVICE_SOC=exynos9830

# Kernel: LineageOS' Samsung 4.19 tree for Exynos 990 (same one your LineageOS boots)
KERNEL_REPO=${KERNEL_REPO:-https://github.com/LineageOS/android_kernel_samsung_universal9830}
KERNEL_BRANCH=${KERNEL_BRANCH:-lineage-23.2}
KERNEL_COMMIT=${KERNEL_COMMIT:-0d6cd86ea14b8ff28f9099a4c122cd7d96d71434}
KERNEL_DEFCONFIG=exynos9830_defconfig
KERNEL_FRAGMENTS="r8s.config"    # from the kernel tree, applied before ours

# mkdtboimg.py (packs the DT table that Samsung's bootloader expects)
LIBUFDT_REPO=${LIBUFDT_REPO:-https://github.com/LineageOS/android_system_libufdt}
LIBUFDT_COMMIT=${LIBUFDT_COMMIT:-df92216e3fc5f3fe289423a7819bd4a5ed3bd443}

# boot.img layout, copied from device/samsung/universal9830-common/BoardConfigCommon.mk
BOOTIMG_ARGS="--header_version 2 --base 0x10000000 --pagesize 2048 \
  --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --tags_offset 0x00000100 --dtb_offset 0x00000000"
BOOT_PARTITION_SIZE=61865984

# Kernel command line we add (the bootloader appends its own)
EXINUX_CMDLINE=${EXINUX_CMDLINE:-"console=tty0 loglevel=7 exinux.root=auto"}

# Root filesystem
DEBIAN_SUITE=${DEBIAN_SUITE:-trixie}
DEBIAN_MIRROR=${DEBIAN_MIRROR:-http://deb.debian.org/debian}
ROOTFS_SIZE=${ROOTFS_SIZE:-8G}   # size of rootfs.img
EXINUX_USER=${EXINUX_USER:-exinux}
EXINUX_PASSWORD=${EXINUX_PASSWORD:-exinux}   # change on first login
EXINUX_HOSTNAME=${EXINUX_HOSTNAME:-exinux}

# Layout
TOP=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK=${WORK:-$TOP/work}
OUT=${OUT:-$TOP/out}
FIRMWARE_DIR=${FIRMWARE_DIR:-$TOP/firmware}

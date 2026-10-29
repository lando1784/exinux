# exinux: Debian for the Samsung Galaxy S20 FE 4G (SM-G780F, Exynos 990)
#   make kernel   - kernel Image + dtb.img/dtbo.img
#   make boot     - out/boot.img (kernel + exinux initramfs)
#   sudo make rootfs - out/rootfs.img (Debian arm64)
#   make firmware - pull firmware from the phone running LineageOS (adb)

.PHONY: all kernel boot rootfs firmware clean

all: boot

kernel:
	scripts/build-kernel.sh

boot: kernel
	scripts/build-bootimg.sh

rootfs:
	scripts/build-rootfs.sh

firmware:
	scripts/extract-firmware.sh

clean:
	rm -rf work/kernel-build work/initramfs work/rootfs out

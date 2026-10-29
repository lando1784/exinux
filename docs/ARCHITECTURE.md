# Architecture and design decisions

## The device

| | |
|---|---|
| Model | Galaxy S20 FE 4G, SM-G780F, codename `r8s` |
| SoC | Exynos 990 (2× Mongoose M5, 2× Cortex-A76, 4× Cortex-A55) |
| GPU | Mali-G77 MP11 (Valhall) |
| Display | 1080×2400 AMOLED, command-mode MIPI DSI, Samsung DECON/DPU |
| Touch | STM FTS5CU56A (Zinitix ZT7650 on some panels) |
| Wi-Fi / BT | **Qualcomm QCA6390** (Wi-Fi over PCIe, BT over UART). Not Broadcom like the other S20 models |
| USB-C | DWC3 dual-role, MAX77705 PD/Type-C, DisplayPort alt mode (DeX) |

These come from the LineageOS device tree (`android_device_samsung_r8s`,
`android_device_samsung_universal9830-common`) and the kernel's `r8s.config`.

## Options we considered

### 1. Mainline Linux (rejected for now)

Upstream Linux has had an `r8s` device tree since ~6.14. It covers only the
CPU, clocks, pinctrl and a framebuffer left behind by the bootloader. There
is no upstream driver for the display controller, DSI panel, touch, UFS
tuning, PCIe for QCA6390, USB-C or DisplayPort on Exynos 990, and writing
them means years of reverse-engineering. We keep an eye on it.

### 2. Halium + libhybris: Droidian / Ubuntu Touch (rejected for now)

This approach runs Debian on top of the Android vendor partition and uses
the vendor's GPU and HAL blobs through libhybris. It would give GPU
acceleration and maybe DeX output through hwcomposer. But:

* Your phone runs LineageOS 23 (Android 16). Droidian and Ubuntu Touch
  target Halium 11–13 (Android 11–13) vendor images, and r8s has no
  maintained LineageOS 18–20 branch to build a matching Halium image from.
* It needs a full Android source checkout (~250 GB) and a lot of
  device-specific glue.

We may revisit it later just for GPU acceleration (see roadmap).

### 3. Debian on the downstream Samsung kernel (chosen)

We use the **same 4.19 kernel LineageOS boots** (`android_kernel_samsung_universal9830`,
pinned in `config.sh`), with extra options for systemd/Xorg/BlueZ
(`kernel/exinux.config`), and start Debian's systemd instead of Android's
init. The drivers we need are in that tree as normal Linux drivers:

* **Display**: `drivers/video/fbdev/exynos/dpu30_dual` registers `/dev/fb0`
  and allocates scan-out memory for the default window. Because the panel
  is command mode, a frame only reaches the glass when the driver triggers
  an update. For fbdev users it does that in `decon_pan_display()`, so
  `exinux-fb-refresher` calls `FBIOPAN_DISPLAY` at 30 fps. Xorg uses the
  plain `fbdev` driver with a shadow framebuffer.
* **Touch**: in-kernel input drivers, exposed through evdev and handled by libinput.
* **Wi-Fi**: `cnss2` + `qcacld-3.0` are built in. The driver loads
  `qca6390/amss20.bin`, `bdwlan.elf*`, `m3.bin` and `wlan/qcom_cfg.ini`
  through `request_firmware()`, so `/lib/firmware` needs a copy of
  `/vendor/firmware` (from `scripts/extract-firmware.sh`). The interface
  comes up after writing `ON` to `/dev/wlan` (`exinux-wlan.service`).
  NetworkManager then drives it through nl80211 / wpa_supplicant.
* **USB**: DWC3 + xHCI host mode for hubs, keyboards, mice and storage.
  Gadget mode (RNDIS) gives a debug network to a PC.

What we give up: GPU acceleration (Mali kbase is in the kernel, but the only
userspace driver is Android's blob), audio (Samsung ABOX needs Android HALs),
camera and sensors. None of these are requirements.

## Boot flow

1. The Samsung bootloader loads `boot.img` (header v2): the kernel `Image`,
   a DT table with `exynos9830.dtb` (keyed `custom0/custom1` like
   LineageOS), and our gzip initramfs. The board overlay comes from the
   existing `dtbo` partition, which we leave alone.
2. `initramfs/init` (busybox) mounts the ext4 filesystem labelled
   `exinux`, preferring the microSD card. LineageOS' userdata uses metadata
   encryption, so a rootfs can only live there if userdata is overwritten
   with `rootfs.img`. `exinux.root=/dev/...` overrides the search. On
   failure it starts an RNDIS + telnet debug shell at 172.16.42.1.
3. `switch_root` to Debian's systemd. Services in `rootfs/overlay` start the
   panel refresher, Wi-Fi and the USB debug network, then LightDM
   auto-logs into Xfce.

## Roadmap

### M1: first boot
Get a desktop on the panel with touch and Wi-Fi. Likely fixes:
* panel stays black → check `dmesg | grep decon` and the refresher log; the
  bootloader may hand over a different DECON state than Android's HWC expects
* pixel format / stride mismatches in Xorg fbdev
* `qcacld` waiting for `cnss-daemon` (Android userspace) for some settings

### M2: Bluetooth
QCA6390 Bluetooth sits on a UART, powered through `/dev/btpower`
(`drivers/bluetooth/bluetooth-power.c`). Android's `bluetooth@1.0-service-qti`
switches it on, sends `htbtfw20.tlv` and `htnv20.bin` with Qualcomm vendor
HCI commands, then raises the baud rate. Plan: a small `exinux-bt-attach`
tool that does the same power ioctl and TLV download (ported from mainline
`drivers/bluetooth/btqca.c`), then hands the tty to the kernel with
`btattach -P h4`. After that, BlueZ works normally.

### M3: external display over USB-C
The kernel has the DisplayPort driver (`CONFIG_EXYNOS_DISPLAYPORT`,
`decon_displayport.c`), and `decon_fb_alloc_memory()` also allocates a
framebuffer for the DP DECON. But `decon_pan_display()` returns early for
non-DSI outputs, and Android normally drives DP through HWC window-config
ioctls. Plan:
1. Patch `decon_pan_display()` to handle `DECON_OUT_DP`, taking the size
   from the EDID-chosen mode.
2. Run a second refresher on the DP framebuffer when a hotplug event
   arrives (udev rule on the `switch`/extcon DP state).
3. Run it as a second Xorg screen (or switch the session to it), so the
   phone works like a small desktop on the monitor.
This is the least certain milestone.

### M4: polish
Landscape mode, backlight, battery indicator, suspend/resume (DECON and
qcacld must survive it), and touch-friendly defaults.

### Later
* GPU acceleration: Halium-style libhybris only for the Mali blob, or
  Panfrost-on-kbase if that ever lands in Mesa.

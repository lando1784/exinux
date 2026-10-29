# exinux

Debian GNU/Linux for the **Samsung Galaxy S20 FE 4G (SM-G780F, Exynos 990,
codename `r8s`)**, built for use as a small Linux computer. It has no phone
features (calls, SMS, mobile data).

> **Status: experimental and not yet tested on hardware.** Every piece below
> builds, but nothing has booted on a phone yet. Expect several rounds of
> flashing, reading logs and fixing before the first desktop appears. Read
> [docs/INSTALL.md](docs/INSTALL.md) before flashing anything.

## How it works

exinux runs Debian directly on Samsung's Linux 4.19 kernel. It uses the same
LineageOS kernel source as your current LineageOS install, but no Android
userspace runs underneath. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
for why we chose this over Halium/libhybris (Droidian, Ubuntu Touch) or
mainline Linux.

```
boot partition  ─ exinux boot.img: LineageOS 4.19 kernel + exinux config + small initramfs
                        │ finds rootfs on
ext4 labelled "exinux": microSD card (or userdata, if you sacrifice Android)
                        │ switch_root
Debian trixie arm64 ─ systemd, Plasma Mobile (KWin/Wayland), NetworkManager, BlueZ
```

Your LineageOS install stays where it is. Only the `boot` partition gets
replaced, and `scripts/flash.sh` backs it up first.

## Hardware status

| Feature | Status | Notes |
|---|---|---|
| Boot to Debian | 🧪 untested | initramfs falls back to a USB telnet shell on failure |
| Display (internal) | 🧪 untested | `exynos-decon` DRM shim (kernel/patches/0001) for KWin; fbdev refresher as fallback |
| Touchscreen | 🧪 untested | STM FTS5CU56A / Zinitix drivers are built in; libinput |
| Desktop | 🧪 untested | Plasma Mobile by default; the Plasma (desktop) session on the same KWin gives floating windows. `DESKTOP=xfce` is the lightweight alternative |
| Wi-Fi (QCA6390) | 🧪 untested | qcacld-3.0 built in; needs firmware from your phone |
| Bluetooth (QCA6390) | 🚧 todo | needs a UART firmware loader; see roadmap |
| USB-C peripherals (host) | 🧪 untested | xHCI/DWC3 + Type-C manager built in |
| USB-C video out (DP alt mode) | 🚧 todo | kernel DP driver exists; needs a second output in the DRM shim; see roadmap |
| GPU acceleration | ❌ | Mali-G77 has no open userspace on this kernel; KWin uses QPainter, apps use llvmpipe. Expect Plasma to feel sluggish |
| Audio, camera, sensors, fingerprint, NFC | ❌ | not in scope |
| Calls / SMS / mobile data | ❌ | not wanted |

## Building

You need an x86_64 Linux PC (Debian or Ubuntu) with about 30 GB free.

```sh
sudo apt install git make bc bison flex libssl-dev libelf-dev cpio lz4 file xz-utils \
    clang-14 lld-14 llvm-14 binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu \
    gcc-arm-linux-gnueabi debootstrap qemu-user-static \
    adb heimdall-flash e2fsprogs

make firmware      # phone on LineageOS, "Rooted debugging" on; pulls Wi-Fi firmware
make boot          # -> out/boot.img   (kernel build takes ~30 min)
sudo make rootfs   # -> out/rootfs.img (Debian + Plasma Mobile; ~1-2 h under qemu)
                   #    sudo DESKTOP=xfce make rootfs  for the lighter Xfce desktop
```

Then follow [docs/INSTALL.md](docs/INSTALL.md) to put the rootfs on a
microSD card and flash `boot.img`.

## Repository layout

```
config.sh                 pinned sources (kernel commit, Debian suite, boot.img layout)
kernel/exinux.config      kernel options for a GNU/Linux userspace
kernel/patches/           kernel patches applied in order (0001: DRM shim over DECON)
initramfs/init            finds and mounts the rootfs, USB debug shell on failure
rootfs/overlay/           files copied into Debian (systemd units, NM, touch config)
rootfs/desktop/<name>/    per-desktop package list, display manager and overlay
src/fb-refresher/         fallback daemon that pushes fbdev frames to the panel
scripts/                  build, firmware extraction, SD card install, flashing
docs/                     architecture, install/recovery, roadmap
```

## Roadmap

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#roadmap). In order:
1. First boot: display, touch, USB networking, Wi-Fi.
2. Bluetooth: QCA6390 firmware download over UART, then BlueZ.
3. External display over USB-C (DisplayPort alt mode) as a second KWin output.
4. Polish: landscape mode, suspend, battery, brightness, on-screen keyboard.
5. GPU acceleration (would make Plasma smooth); see the architecture notes.

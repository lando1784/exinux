# Installing exinux

exinux only replaces the **boot** partition and lives on a microSD card.
LineageOS's system, vendor and your data stay where they are, so you can
switch back by flashing the saved LineageOS `boot.img`.

## Before you start

* Unlocked bootloader and LineageOS installed (with the vbmeta image from
  the LineageOS install guide; that's what lets a custom `boot.img` boot).
* A microSD card, 16 GB or larger (recommended: no changes to internal storage).
* On the PC: `adb`, `heimdall` (or Odin on Windows), and the build
  dependencies from the README.
* Useful key combos:
  * **Download mode**: power off, hold **Vol Up + Vol Down**, plug in the USB cable.
  * **Force reboot**: hold **Vol Down + Power** for ~7 s.
  * **Recovery**: from a forced reboot, hold **Vol Up + Power** with USB plugged into a PC.

## 1. Get the firmware (phone on LineageOS)

Settings → System → Developer options → enable **USB debugging** and
**Rooted debugging**. Plug in, accept the prompt, then:

```sh
make firmware        # fills ./firmware/ (Wi-Fi + BT firmware, Wi-Fi MAC)
```

## 2. Build

```sh
make boot            # out/boot.img
sudo make rootfs     # out/rootfs.img
```

## 3. Put the root filesystem on the microSD card

```sh
sudo scripts/install-sdcard.sh /dev/sdX     # whole card, e.g. /dev/sdb. ERASES IT
```

Then put the card in the phone.

**No SD card? (advanced, wipes Android data)** LineageOS encrypts the
`userdata` partition, so exinux can't read files that Android stored
there. Instead you can give the whole partition to exinux. This **erases
all LineageOS apps and data**, and LineageOS won't boot again until you
format data from LineageOS recovery. Boot LineageOS recovery, enable ADB
in it (Advanced → Enable ADB), then:
```sh
adb shell 'ls -l /dev/block/by-name/userdata'          # make sure it exists
adb exec-in 'dd of=/dev/block/by-name/userdata bs=4M' < out/rootfs.img
```
The initramfs finds the filesystem labelled `exinux` wherever it is (the SD
card wins if both exist). On first boot the filesystem grows to fill the
partition.

## 4. Flash boot.img

```sh
scripts/flash.sh
```
This saves `backup/lineage-boot.img` over adb first, reboots to Download
mode, and flashes `out/boot.img` with Heimdall. With Odin, put
`out/exinux-boot.tar` in the **AP** slot and untick *Auto Reboot*.

## 5. First boot

You'll see the Samsung "bootloader unlocked" warning, then the screen goes
black while the kernel starts. If all goes well, the Xfce desktop appears
(user `exinux`, password `exinux`; you'll be asked to change it at the
first terminal login).

### If the screen stays black

Leave the phone connected to the PC by USB. exinux brings up USB networking
in two places:

* **Debian booted** (screen problem only): a new network interface appears on the PC.
  ```sh
  sudo ip addr add 172.16.42.2/24 dev <usb-interface>   # e.g. enx…/usb0
  ssh exinux@172.16.42.1
  journalctl -b; dmesg; systemctl status exinux-fb-refresher
  ```
* **The initramfs could not find the rootfs**: same interface, but it's a telnet shell:
  ```sh
  telnet 172.16.42.1
  cat /run/exinux-initramfs.log; dmesg | tail -100; blkid
  ```

Please save `dmesg` and `journalctl -b` output and bring it back here. These
logs are how we get through M1.

## Going back to LineageOS

```sh
scripts/flash.sh --restore      # flashes backup/lineage-boot.img
```
If you lost the backup, extract `boot.img` from the LineageOS zip you
installed (`payload.bin`, e.g. with `payload-dumper-go`) and flash it with
`heimdall flash --BOOT boot.img`.

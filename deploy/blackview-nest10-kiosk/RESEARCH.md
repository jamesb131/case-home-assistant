# NEST 10 research record

Research date: 2026-10-27

## Device-specific findings

Blackview's product page identifies the NEST 10 as an Android 11 frame with an
RK3326S, 2 GB RAM, 32 GB storage, an 800 x 1280 display and Wi-Fi 6:

- https://www.blackview.hk/products/item/nest10

Targeted searches for `NEST10_20260508V01`, `rk3326_E80`, `rk3326_rgo`, and a
NEST 10 DTS or firmware image did not locate a public board port, verified stock
firmware, custom ROM or recovery image. Absence from search is not proof that no
vendor package exists, so Blackview/iFrameo support remains the best source.

A read-only Fastboot probe of the physical unit reported:

- Product: `evb_px30`
- Bootloader: `U-Boot 2017.09`
- Secure: `yes`
- Unlocked: `no`
- Build variant: `userdebug`
- Bootloader Fastboot, not userspace fastbootd (`is-userspace:no`)
- Super partition: 2400 MiB
- Userdata partition: approximately 25.52 GiB

The full `getvar all` response enumerated raw partitions named `security`,
`uboot`, `trust`, `misc`, `dtbo`, `vbmeta`, `boot`, `recovery`, `backup`,
`cache`, `metadata`, `fotocube`, `frp`, `baseparameter`, `super`, and
`userdata`. Notable reported sizes are 44.586 MiB each for `boot` and `dtbo`,
107.357 MiB for `recovery`, 36 MiB for the product-specific `fotocube`, and 1
MiB for `vbmeta`.

The vendor Fastboot implementation returns `U-Boot` as the partition type for
every raw partition, so that field is a placeholder rather than filesystem
information. It also reports two slots and a current slot of `a`, while saying
that every enumerated partition is unslotted and rejecting all `_a`/`_b`
partition-size queries. The slot metadata is therefore treated as generic or
internally managed state, not proof of a conventional Android A/B partition
layout.

The FCC filing is public under FCC ID `2BSW8-NEST10`; its internal-photograph
exhibit may reveal PCB labels, radio module and UART candidates:

- https://fccid.io/2BSW8-NEST10
- https://fccid.io/2BSW8-NEST10/Internal-Photos/Int-photo-9214397

The certification report identifies the tested NEST 10 hardware version as
`BND-RK3326-S101-C`. This is the strongest board-family identifier found so
far:

- https://device.report/m/ad5217b3b26ad3240a3cb3114d828b6bdf98d8ae655b0975205e162deaf9aa46

A separately documented Android 11 Frameo unit uses an S101-C build and reports
the device-tree model `Rockchip rk3326 S101 101 avb board`, compatible string
`rockchip,rk3326-s101-aic8800`, AIC8800 SDIO Wi-Fi and `gslX680-d708` touch.
It also reports raw NAND, a 1280 x 800 panel and 1 GB RAM. The NEST reports 2 GB
and an 800 x 1280 product display, so this is comparative evidence only. It
narrows firmware and driver searches but does not validate that unit's DTB,
boot image, offsets or scripts on the NEST:

- https://github.com/wesbos/photo-frame-dashboard/blob/main/docs/frameo-rk3326-s101.md

The same report identifies `com.bnd.update` and Rockchip's update service in
the related firmware. An exact Blackview signed update may therefore contain
the best remaining source for the NEST DTB, but no public package matching
`NEST10_20260508V01` was found.

## Closed USB path and recovery SD scope

Recovery ADB, ADB sideload enumeration and direct partition extraction are not
available on the tested NEST. Fastboot supplied metadata but no confirmed
readback operation. Further cable permutations are out of scope unless new
NEST-specific evidence changes the method.

Android Recovery's **Apply update from SD card** option is an external-storage
update path. AOSP's recovery configuration mounts an optional `/sdcard` from
the device recovery fstab, then applies a signed package. The file browser can
prove FAT/media visibility, but it is not a shell, partition reader or normal
Linux boot path:

- https://source.android.com/docs/core/ota/nonab/device_code

## Upstream support boundary

Mainline Linux contains `rk3326.dtsi`, which includes the shared PX30
description. This establishes SoC-family kernel support, not NEST 10 board
support:

- https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/rockchip/rk3326.dtsi

Mainline U-Boot documents RK3326 support for the ODROID-GO Advance and separate
PX30 boards, but no NEST 10 target. Board DRAM, PMIC and pin configuration make
those bootloader binaries non-interchangeable:

- https://github.com/u-boot/u-boot/blob/master/doc/board/rockchip/rockchip.rst

Rockchip's boot documentation describes loader placement on SD media and the
SoC boot flow. Rockchip/PX30 documentation places valid internal boot media
ahead of SD for parts of the Boot ROM's first-stage search. The NEST's exact
flash medium remains unconfirmed, and the related S101-C uses raw NAND rather
than eMMC. An SD bootloader may therefore never be considered while the factory
internal chain remains bootable:

- https://opensource.rock-chips.com/wiki_Boot_option
- https://rockchip.wikidot.com/boot-sequence

The smallest SD experiment therefore contains no standalone Rockchip loader at
sector 64 (32 KiB). It lets Boot ROM continue into the existing internal trust
chain and tests only whether the later factory U-Boot scans a FAT partition.
U-Boot's distro convention searches the filesystem root and `/boot` for
`boot.scr.uimg` followed by `boot.scr`, while exposing the scanned `devtype`,
`devnum` and `distro_bootpart` variables to the script:

- https://docs.u-boot.org/en/stable/develop/distro.html
- https://docs.u-boot.org/en/latest/develop/bootstd/script.html

There is a separate payload-order nuance after U-Boot is already running. A
mainline U-Boot fix explicitly corrected PX30-family MMC numbering so distro
boot tries SD before eMMC. That makes it plausible, but not proven, that the
factory loader could launch an SD `extlinux.conf` even though Boot ROM entered
through eMMC:

- https://lists.u-boot-project.org/pipermail/u-boot/2021-June/452346.html

Rockchip's secure-boot application note covers RK3326/PX30 and states that an
eFuse/OTP-enabled secure Boot ROM rejects unsigned or incorrectly signed
firmware. The observed `secure:yes` and `unlocked:no` values are therefore
treated as serious constraints, but not as a complete description of this
unit's OTP state or signature policy. Serial logs and an exact vendor update
package are needed before drawing stronger conclusions:

- https://github.com/mfkiwl/rk-open-docs/blob/master/NVM/Rockchip_Developer_Guide_Secure_Boot_Application_Note_EN.md

## Build system choice

Buildroot supports a reproducible external tree, Linux kernel fragments,
root-filesystem overlays and post-build scripts, which suit a narrow appliance
prototype:

- https://buildroot.org/downloads/manual/manual.html
- https://buildroot.org/download.html

The kiosk profile uses WPE WebKit with Cog's direct DRM backend and Mesa's
Panfrost driver. These are included to test a no-desktop browser appliance after
the board reaches DRM/KMS bring-up; their presence does not imply the unknown
panel will work.

## Decision log

1. Do not create or distribute an image using a different RK3326/PX30 DTB.
2. Close Recovery ADB and USB extraction until materially new evidence exists.
3. Close generic and unsigned SD boot experiments after the Recovery signature,
   factory-U-Boot FAT scan and BootROM SRAM probes all failed to reach their
   intended execution stages.
4. Resume SD boot work only with an exact NEST vendor boot chain or materially
   new UART evidence showing a supported external boot target.
5. Gate standalone image assembly behind exact, reviewed DTB/idbloader/U-Boot
   artifacts and SHA-256 values.
6. Build a diagnostic profile before the browser profile.
7. Keep all device interaction scripts read-only; image writing is deliberately
   left to an explicit external imaging tool.

## First SD probe result

On 2026-10-28, stock Recovery successfully displayed the
`NEST_PROBE_VISIBLE` directory from the FAT32 card. A complete cold boot with
the card inserted reached Android normally, but neither the original guarded
text marker nor another filesystem change appeared on the card. This proves
Recovery SD visibility, but not factory U-Boot script execution.

The follow-up probe removes one avoidable dependency by copying the loaded
script directly from U-Boot's standard `scriptaddr`, with both `fatwrite` and
generic `save` attempts. It also adds a non-persistent 45-second pause so script
execution remains observable if filesystem writes are unavailable.

The follow-up cold boot also reached Android normally, produced no marker, and
did not exhibit the intended 45-second pause. This is strong practical evidence
that factory U-Boot ignored the conventional FAT script path. It does not make
a generic RK3326/PX30 loader or DTB compatible with this board.

## Recovery signature probe result

On 2026-10-28, stock Recovery read the payload-free whole-file signed package
from `/mnt/external_sd`. The package used the standard public AOSP Android test
key and contained no updater, payload, image or executable content. Recovery
reported `failed to verify whole-file signature`, verification result `1`,
error `21`, install status `2`, and aborted before reaching package metadata or
update-binary handling.

This closes the generic AOSP test-key Recovery route. Trying unrelated public
Android or Rockchip keys would not establish board compatibility and is not a
useful next step. A Recovery diagnostic requires the certificate chain from an
exact NEST vendor update or other independently verified NEST signing material.

## BootROM SRAM probe result

On 2026-10-28, the dedicated card was written with the 4 KiB Rockchip-formatted
SRAM-only probe at sector 64 and passed the writer's raw readback verification.
The returned FAT filesystem also retained the probe audit marker.

The NEST booted Android normally with the card inserted, then booted Android
normally again after the card was removed. The unsigned first stage therefore
did not take observable control, while the second boot confirms that the test
caused no persistent change.

This result cannot distinguish internal-storage boot priority from secure-boot
rejection or a different BootROM media format. It does establish that the
standard unsigned RK33 SD first-stage format is not a demonstrated entry point
on this unit. In combination with the earlier results, further generic
RK3326/PX30 SD image variations are closed. The next useful evidence must come
from an exact vendor firmware/update package, the physical board and component
markings, or a UART boot log.

## Android Open Accessory and HID result

On 2026-10-28, the normal Android USB identity (`2207:0007`) reported Android
Open Accessory protocol version 2. AOA2 HID injection works without ADB, root
or an installed device application. Volume, Home, Back and mouse input were
observed on the device. Consumer usage `0x0183` also opened the installed
Android Music activity, confirming that input traverses the Linux 4.19 HID
mapping and Android 11 `Generic.kl`.

Starting accessory mode succeeded and re-enumerated the device as
`18d1:2d00`. This is accessory-only mode, not accessory plus ADB (`2d01`). The
system displayed the supplied accessory description and URI, but selecting
**View** dismissed the dialog without opening either an HTTPS hostname or a
reachable HTTP page hosted on the Mac. No enabled browser activity appears to
handle the accessory URI.

The following system escape attempts were received but suppressed by the
iFrameo kiosk/device-owner policy, generally causing only a full-screen redraw:

- notification-shade mouse drag while iFrameo was in immersive fullscreen;
- `APP_SWITCH` / Recent Apps (`KEY_APPSELECT`, consumer usage `0x01a2`);
- simultaneous Volume Up and Volume Down accessibility shortcut hold; and
- long-press Home / assistant invocation.

AOA2 is therefore useful as a non-destructive diagnostic and input mechanism,
but it does not currently provide an installation, browser, ADB or Settings
entry point. Do not repeat generic key, mouse or accessory-URI probes unless a
specific new Android activity or handler is identified.

## Firmware acquisition result

Blackview's official support catalogue contains a dedicated NEST 10 product
record (`productId` 263). Its public `/downloads/page` API returned one record:
the NEST 10 manual. It did not expose a recovery OTA or factory image.

The related S101-C firmware contains Adups FOTA 5.30 and identifies
`fota5p.adups.com` / `fota5p.adups.cn`. The public Adups update protocol was
queried without a serial number or device credential using the known current
version and six evidence-based project names. All returned status `1104`
(unknown project/build properties):

- `bnd3326$11.0_NEST10_en-US_other`
- `bndrk3326$11.0_NEST10_en-US_other`
- `rk3326$11.0_NEST10_en-US_other`
- `blackview3326$11.0_NEST10_en-US_other`
- `doke3326$11.0_NEST10_en-US_other`
- `nest3326$11.0_NEST10_en-US_other`

Do not broaden this into unbounded project-name guessing. Resume the Adups
route only after obtaining the exact `ro.fota.oem`, `ro.fota.device`, locale
and version properties from firmware, a vendor response or a materially new
read-only information source. The support request in `FIRMWARE-REQUEST.md` is
the primary acquisition path.

The running device subsequently offered and downloaded an update identified as
`V1.1.0_112609231750`. Its dialog requested a restart to perform the upgrade;
**Say it next time** was selected, so installation was not authorized. The
different version scheme does not establish whether this is an iFrameo-only
package or a system OTA, and the restart wording means it must be treated as a
potential system update until inspected.

The accessory-only USB session was ended with a USB bus reset while Android
remained powered. The resulting `18d1:0007` interface was detected by libmtp,
but Android exposed no storage. Temporarily releasing macOS camera/MTP handlers
allowed libmtp to claim the device, after which `Get Storage information`
failed. The downloaded package is therefore not retrievable through the
currently exposed USB storage interface and likely resides in protected app or
OTA storage. Do not authorize the pending restart merely to inspect it.

## Evidence still needed

- Full UART boot log with and without an SD card
- Exact factory device tree and partition metadata
- Board photographs/markings and measured UART voltage
- Panel controller and MIPI/parallel interface details
- Touch and Wi-Fi device IDs or module markings
- Factory bootloader environment and boot targets
- A vendor recovery/update package and its signature metadata
- Exact vendor Recovery signing certificate and whether its private key is
  unavailable as expected
- Whether the factory FOTA service exposes a retrievable exact update URL

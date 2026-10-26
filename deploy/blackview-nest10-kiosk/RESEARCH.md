# NEST 10 research record

Research date: 2026-10-26

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
- Current slot: `a`
- Slot count: `2`
- Super partition: 2400 MiB

The vendor Fastboot implementation returned `U-Boot` as the partition type for
several unrelated Android partitions and reported the same 44.586 MiB size for
unsuffixed `boot` and `dtbo` queries. Those responses are treated as unreliable;
the probe now asks slot-aware A/B partition names instead.

The FCC filing is public under FCC ID `2BSW8-NEST10`; its internal-photograph
exhibit may reveal PCB labels, radio module and UART candidates:

- https://fccid.io/2BSW8-NEST10
- https://fccid.io/2BSW8-NEST10/Internal-Photos/Int-photo-9214397

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
SoC boot flow. Rockchip/PX30 documentation places valid eMMC ahead of SD for the
Boot ROM's first-stage search, which is why an SD bootloader may not be
considered while the factory eMMC chain remains bootable:

- https://opensource.rock-chips.com/wiki_Boot_option
- https://rockchip.wikidot.com/boot-sequence

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
2. Try a factory-U-Boot/extlinux SD payload first because it does not replace a
   bootloader and is recoverable by card removal.
3. Gate standalone image assembly behind exact, reviewed DTB/idbloader/U-Boot
   artifacts and SHA-256 values.
4. Build a diagnostic profile before the browser profile.
5. Keep all device interaction scripts read-only; image writing is deliberately
   left to an explicit external imaging tool.

## Evidence still needed

- Full UART boot log with and without an SD card
- Exact factory device tree and partition metadata
- Board photographs/markings and measured UART voltage
- Panel controller and MIPI/parallel interface details
- Touch and Wi-Fi device IDs or module markings
- Factory bootloader environment and boot targets
- A vendor recovery/update package and its signature metadata

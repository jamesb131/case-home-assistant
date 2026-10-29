# Blackview NEST 10 CASE kiosk prototype

This directory is a cautious Buildroot bring-up kit for the Blackview NEST 10.
It is not yet a board-supported distribution and it does not contain a generic
RK3326 image disguised as one.

## Feasibility verdict

The RK3326 SoC has upstream Linux support, but the exact NEST 10 board does not
have a public upstream device tree or U-Boot target. The display panel, touch
controller, Wi-Fi module, PMIC wiring, regulators, GPIO assignments and DRAM
training configuration are not yet established.

There is a second, earlier obstacle: this Rockchip boot flow may load its first
stage from valid internal flash before considering SD. The exact NEST storage
medium is not confirmed. A locked, secure factory chain may therefore reject or
never reach an SD bootloader. Once factory U-Boot is running, its distro-boot
logic might still scan SD for a filesystem payload. That split behavior is the
safest remaining opening, but it must be demonstrated on the NEST 10 rather
than assumed.

Accordingly, the immediate target is a sequence of **demonstrable, reversible
boot gates**:

1. Use the inert [SD scan probe](SD-PROBE.md) to test whether factory U-Boot
   already scans a conventional FAT card. It contains no loader, kernel, DTB or
   root filesystem and can write only a marker to its own guarded FAT path.
2. If the scan probe is ignored, use the payload-free
   [Recovery signature probe](RECOVERY-PROBE.md) to determine whether stock
   Recovery trusts the public AOSP test key. This package can only fail and
   contains nothing executable.
3. If both paths are closed, use the [SRAM-only BootROM probe](BOOTROM-PROBE.md)
   to test genuine SD first-stage selection without initializing DRAM or
   including a generic board build.
4. Obtain and inspect the exact device tree from this NEST 10 firmware, then
   adapt downstream bindings where mainline differs.
5. Place a Linux payload on SD without replacing a bootloader (`vendor-chain`).
6. Capture a serial boot log if practical and validate storage, display, touch
   and Wi-Fi one subsystem at a time.
7. Only consider a standalone SD bootloader after exact DRAM, board and secure
   boot requirements are known.

Removing the SD card must return the device to its untouched internal Android
installation. No script here writes internal flash, invokes an unlock, or
addresses a physical block device.

## Current investigation boundary

Recovery ADB, sideload ADB and direct USB partition extraction are unavailable
on the tested unit. They are closed investigation paths unless materially new
device-specific evidence appears. The read-only Fastboot inventory has been
captured; no further cable iteration is part of the plan.

The remaining useful evidence sources are:

- Ask Blackview/iFrameo support for the exact `NEST10_20260508V01` update
  package, GPL kernel source, recovery procedure and board files for hardware
  revision `BND-RK3326-S101-C`. Use the ready-to-send request in
  `FIRMWARE-REQUEST.md`.
- The public Blackview NEST 10 downloads API currently exposes only the manual.
  A read-only Adups query helper is available as
  `scripts/probe-adups-fota.py`; it requires explicit non-secret build
  properties and never installs an update. The exact Adups project namespace
  is not yet known.
- Review the public FCC internal photographs for PCB markings, Wi-Fi module and
  likely UART pads. Use a 3.3 V USB UART only after voltage and ground have been
  measured; never connect the adapter's VCC pin.
- If an exact firmware package is obtained, extract its `dtb`, `boot`, `dtbo`,
  `vendor_boot` and `vbmeta` metadata offline. Do not flash them back.
- Use stock Recovery's **Apply update from SD card** file browser only to prove
  the card is readable. AOSP Recovery treats this as a signed update path; it
  does not expose the device tree or prove that the bootloader scans SD.

Do not repeat `fastboot oem unlock`, flash another RK3326/PX30 board image, or
use Rockchip Loader writes without an exact recovery image and verified board
procedure.

## Layout

- `configs/nest10_bringup_defconfig`: serial, input, DRM, MMC, USB and Wi-Fi
  diagnostics without a browser.
- `configs/nest10_kiosk_defconfig`: adds Mesa/Panfrost, WPE WebKit and Cog's
  direct DRM kiosk backend.
- `board/nest10/linux.fragment`: broad bring-up drivers; the exact DTB still
  decides which hardware can bind.
- `sd-probe/`: the inert FAT-card scan probe source.
- `SD-PROBE.md`: build, card inspection, test procedure and result gates.
- `recovery-probe/`: the sole inert file placed inside the signed Recovery ZIP.
- `RECOVERY-PROBE.md`: signature-probe construction, audit and result gates.
- `BOOTROM-PROBE.md`: the SRAM-only SD first-stage selection test.
- `artifacts/`: ignored exact-board files and provenance hashes.
- `scripts/build.sh`: pinned Buildroot download, verification and build.
- `scripts/assemble-sd-image.sh`: assembles an image file after artifact checks.
- `scripts/validate.sh`: syntax and destructive-command guardrails.

## Build profiles

The pinned Buildroot release is `2026.08.1`, verified against SHA-256
`34fb7bea8a213ffde39cc02e61703391560f26e0850f03138c722d0b09880f2b`.

Buildroot requires Linux. On Linux or WSL2:

```sh
cd deploy/blackview-nest10-kiosk
./scripts/validate.sh
VALIDATE_BUILDROOT_CONFIGS=yes ./scripts/validate.sh
./scripts/build.sh --profile bringup
```

The initial hardware test should use `bringup`. Build the browser profile only
after serial, storage, display and input work:

```sh
./scripts/build.sh --profile kiosk
```

On macOS or another Docker host:

```sh
./scripts/build-container.sh --profile bringup
```

WPE WebKit is a substantial compile. The kiosk image is deliberately phase two.

## First microSD test

Build the inert probe before any Buildroot image. On Windows with Docker Desktop
running:

```powershell
cd D:\path\to\case-home-assistant\deploy\blackview-nest10-kiosk
.\scripts\Build-SdProbe.ps1
```

On Linux or macOS with Docker:

```sh
./scripts/build-sd-probe-container.sh
```

On macOS, use the guided wrapper to build, verify and list candidate external
disks without writing one:

```sh
./scripts/prepare-sd-probe-macos.sh
```

The optional `write-sd-probe-macos.sh` writer accepts an explicit whole-disk
identifier only, rejects internal/virtual/oversized targets, requires a typed
confirmation and verifies the bytes after writing. Recheck the identifier with
`diskutil list external physical` every time; identifiers can change after a
reconnect or reboot.

The output is `output/images/sd-probe/nest10-sd-probe.img`. The builder verifies
that the conventional Rockchip loader window at 32 KiB is empty and never
accepts a physical-disk destination. Follow [SD-PROBE.md](SD-PROBE.md) exactly.

The presence of `case-probe/uboot-ran.txt` after a cold boot proves factory
U-Boot executed the FAT script. Its absence proves nothing and is not a reason
to try a generic loader.

On the tested unit, two cold boots produced neither a marker nor the probe's
45-second delay. Factory U-Boot therefore appears not to scan this conventional
FAT script path. The next experiment is the payload-free Recovery signature
probe, not a generic Rockchip loader.

## Exact-board artifact gate

For a vendor-chain experiment, place a reviewed, mainline-compatible NEST 10
DTB derived from this exact hardware at:

```text
artifacts/nest10.dtb
```

Then copy `artifacts/artifacts.local.env.example` to
`artifacts/artifacts.local.env`, record its SHA-256, document provenance in the
ignored `artifacts/artifacts.local.md`, and set confirmation to `yes`.

Inspect it before assembly:

```sh
./scripts/inspect-dtb.sh
```

An Android 4.19 vendor DTB is not automatically compatible with the current
mainline kernel. Treat it as the source for a port, not a drop-in guarantee.

For `standalone` mode, the gate additionally requires exact-board
`idbloader.img` and `u-boot.itb` files and their hashes. Similar-SoC artifacts
are explicitly unacceptable.

## Assemble, but do not write, an image

```sh
./scripts/assemble-sd-image.sh --profile bringup --mode vendor-chain
```

This only creates:

```text
output/images/bringup-vendor-chain/nest10-vendor-chain.img
```

It cannot accept `/dev/*`, a Windows disk number or any destination argument.
Review the adjacent SHA-256 before writing the file to a spare SD card with a
trusted graphical imager. Check the removable target twice. Do not use `dd`
instructions copied from an unrelated board guide.

After imaging, mount the boot partition and copy
`case-kiosk.env.example` to `case-kiosk.env`. Configure Wi-Fi and the local CASE
URL there. A private HTTPS certificate will need its CA installed in the image;
for an isolated first test, a local HTTP endpoint is simpler.

## Later Linux boot procedure

This procedure is gated behind a positive SD scan result and an exact, reviewed
NEST 10 DTB. It is not the first card to test.

1. Confirm Android still boots normally without SD.
2. Connect a verified 3.3 V UART receive/ground pair and start logging at
   `115200 8N1`. Do not connect VCC.
3. Power off, insert the vendor-chain SD, then power on.
4. Record the complete log and screen behavior. Do not press a recovery update
   or flashing option.
5. If Android boots unchanged and the log never scans SD, the vendor chain is
   not an SD payload path. Remove the card; do not escalate to a guessed loader.
6. If Linux starts, test serial first, then MMC, DRM (`modetest`/`kmscube`),
   touch (`evtest`) and Wi-Fi. Build the kiosk profile only after bring-up.

To recover, power off and remove the SD card. The prototype never needs to
touch internal storage.

## Known gaps

- Exact NEST 10 DTB and panel timing
- Exact NEST confirmation of the S101-family touch controller, interrupt and
  reset wiring
- Exact NEST confirmation of the likely AIC8800 Wi-Fi module, firmware and
  antenna power controls
- PMIC/regulator tree and battery/charger behavior
- DRAM type and training binary for a standalone loader
- UART location and console index
- Factory U-Boot SD scanning behavior
- Verified secure-boot/OTP policy and accepted signature chain
- Internal storage medium (the related S101-C uses raw NAND, but the NEST is
  not yet confirmed)
- Rotation and touch-coordinate transformation

These are discovery tasks, not values to borrow from a different board.

The related S101-C board report is a useful component lead, not a compatible
board port. Its different display orientation and RAM configuration are enough
to reject its DTB as a drop-in image.

See [RESEARCH.md](RESEARCH.md) for sources and the evidence behind these limits.

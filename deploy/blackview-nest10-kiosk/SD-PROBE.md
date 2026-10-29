# NEST 10 microSD investigation

This is the first microSD experiment. It tests one narrow question:

> Does the NEST 10 factory U-Boot scan a conventional FAT SD partition for a
> U-Boot distro script?

It does not attempt to boot Linux and it does not establish device-tree
compatibility.

## Why this comes before Buildroot

The Rockchip boot chain and the later U-Boot payload search are separate. A
standalone Rockchip SD image normally places an SoC-specific first-stage loader
at sector 64 (32 KiB). The NEST 10 probe deliberately leaves that region empty,
so the Boot ROM should continue using the trusted factory chain on internal
storage. If factory U-Boot later scans SD using its distro-boot support, it can
find the probe script on the FAT partition.

The script contains no boot command. Only when U-Boot identifies the currently
scanned device and partition, it first tries to copy its own already-loaded
script bytes to `case-probe/uboot-ran.bin`. It also retains the guarded
`input.txt` to `uboot-ran.txt` method as a fallback. It does not call `saveenv`,
address a raw MMC device, or name an internal partition.

The revised probe pauses for 45 seconds before returning to the factory boot
flow. This provides an observable signal if the script runs but factory U-Boot
lacks FAT write support. It changes nothing persistently and card removal still
restores the original path.

## Build on Windows

Docker Desktop must be running. From PowerShell in the repository:

```powershell
cd D:\path\to\case-home-assistant\deploy\blackview-nest10-kiosk
.\scripts\Build-SdProbe.ps1
```

The output is:

```text
output\images\sd-probe\nest10-sd-probe.img
output\images\sd-probe\nest10-sd-probe.img.sha256
```

The build fails if the image's 32 KiB Rockchip loader window is not empty. It
only creates an image file; it has no physical-disk argument.

On Linux or macOS with Docker:

```sh
./scripts/build-sd-probe-container.sh
```

On macOS, the guided build wrapper also lists external physical disks after it
validates the image:

```sh
./scripts/prepare-sd-probe-macos.sh
```

## Write and inspect the card

1. Use a spare microSD card with no needed data.
2. Write `nest10-sd-probe.img` using Balena Etcher or Raspberry Pi Imager. On
   macOS, the guarded writer can instead be given the whole external disk
   explicitly:

   ```sh
   ./scripts/write-sd-probe-macos.sh /dev/disk5
   ```

   Never copy this identifier from documentation without checking
   `diskutil list external physical` on the current Mac. The writer rejects
   internal disks and partitions, displays the full layout, requires typing
   `ERASE diskN`, verifies the written bytes, then ejects the card.
3. Remove and reinsert the card in the PC.
4. Confirm the `NEST_PROBE` FAT volume contains `README.txt`, boot scripts,
   `NEST_PROBE_VISIBLE/` and `case-probe/input.txt`.
5. Confirm `case-probe/uboot-ran.txt` does not exist before the device test.

Do not add a Rockchip loader, kernel, DTB, Android update ZIP or files copied
from another RK3326/PX30 board.

## Stage A: Recovery visibility only

1. Boot stock Android Recovery with the card inserted.
2. Open **Apply update from SD card** only far enough to view the file list.
3. Confirm that the `NEST_PROBE_VISIBLE` directory is visible. Recovery menus
   commonly hide non-update files, so the directory is the intended marker.
4. Back out. Do not select a script and do not attempt installation.

This only establishes that Recovery can mount the FAT card. Android's recovery
SD option is a signed update-package path, not a general boot or extraction
interface.

## Stage B: cold-boot scan probe

1. Verify that Android still boots normally without the card.
2. Power the NEST off completely.
3. Insert the probe card and apply power.
4. Allow up to two minutes for the normal boot path.
5. Record the screen behavior. Do not choose a Recovery update or wipe option.
6. Power off completely, then remove the card.
7. Mount the card on the PC and inspect `case-probe/`.

Interpretation:

- `uboot-ran.bin` exists, or `uboot-ran.txt` exists and matches `input.txt`:
  factory U-Boot executed the script and had filesystem write support. Preserve
  the card image and marker as evidence. The next experiment can be a
  signed/hash-reviewed RAM-only payload, but still requires an exact NEST
  device tree.
- No marker, but boot consistently takes about 45 seconds longer than the same
  boot without the card: U-Boot likely executed the script without a supported
  filesystem write command.
- No marker and no additional delay: factory U-Boot probably did not implement
  this distro-script scan, though the negative result remains inconclusive.
- No marker and boot behavior changes: remove the card and confirm normal boot
  returns. Do not try a loader from another board.

Card removal is the recovery action for this probe. It never writes internal
flash.

## Observed result on the tested NEST 10

Recovery displayed `NEST_PROBE_VISIBLE`, and Android mounted the card and added
its normal media directories. Two complete cold boots produced no marker. The
second probe included an intended 45-second pause, but no additional delay was
observed. This is strong practical evidence that factory U-Boot ignored the FAT
script. It is not evidence that a generic RK3326 loader is compatible.

Continue with [RECOVERY-PROBE.md](RECOVERY-PROBE.md).

## Signed recovery updates

The stock Recovery path becomes useful only if Blackview supplies an exact,
vendor-signed update for hardware `BND-RK3326-S101-C` and firmware
`NEST10_20260508V01`. Such a package can be inspected offline for boot images,
DTBs and signature metadata before anyone considers applying it. Creating an
unsigned test ZIP or renaming a raw image does not provide useful evidence.

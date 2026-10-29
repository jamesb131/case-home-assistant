# NEST 10 SRAM-only BootROM probe

This test asks whether the RK3326S/PX30 BootROM will select and execute an SD
first stage before the intact internal Android boot chain.

It is not U-Boot or Linux. The 4 KiB Rockchip-formatted image contains one
AArch64 instruction after its `RK33` tag: `b .`, an infinite loop. It has no
stack use, DRAM initialization, peripheral access, device tree, filesystem,
storage driver or write routine.

## What the result means

- Android does not begin booting while the card is inserted, but boots normally
  immediately after card removal: strong evidence that BootROM selected and
  executed the SD first stage.
- Android boots normally with the card inserted: inconclusive. Internal storage
  may have priority, secure boot may have rejected the unsigned first stage, or
  the SD format may not match this BootROM configuration.

There is no expected display output because the payload does not initialize the
display. Allow 90 seconds before declaring that normal Android did not start.

## Build

```sh
cd /Users/jamesbaverstock/Documents/repos/Case/deploy/blackview-nest10-kiosk
./scripts/build-bootrom-sram-probe-container.sh
```

The builder verifies that bytes after the `RK33` tag contain only the encoded
infinite loop and zero padding. Outputs are written under
`output/bootrom-sram-probe/`.

## Write on macOS

Identify the dedicated external card every time:

```sh
diskutil list external physical
./scripts/write-bootrom-sram-probe-macos.sh /dev/disk5
```

The writer requires the existing `NEST_PROBE` FAT markers, verifies that the
partition begins at or after 1 MiB, writes only 4 KiB at sector 64, reads those
sectors back, and ejects the card. The FAT partition is preserved.

## Device test

1. Confirm Android still boots without the card.
2. Power off completely.
3. Insert the SRAM probe card and apply power normally. Do not enter Recovery.
4. Wait 90 seconds and record whether any Android boot logo or interface starts.
5. Remove power and remove the card.
6. Apply power without the card and confirm Android still boots.

Do not leave the device powered indefinitely if the screen remains blank. Do
not add a generic U-Boot, DDR blob, DTB, kernel or root filesystem to this card.

## Observed result

Tested on the physical NEST 10 on 2026-10-28. The writer completed its raw
readback verification and the returned card retained the probe audit marker.
With the card inserted, the device proceeded into Android normally. After the
card was removed, it again booted Android normally.

This is an inconclusive negative at the BootROM boundary: the probe did not
take observable control. The result is consistent with internal flash taking
priority, secure boot rejecting the unsigned first stage, or this unit using a
different SD-loader format or policy. It is not evidence that another generic
RK3326/PX30 loader is compatible.

Together with the ignored factory-U-Boot FAT scripts and rejected AOSP-signed
Recovery package, this closes further generic or unsigned SD boot variations.
Keep the card unchanged as evidence and for possible reuse with an exact,
reviewed vendor boot chain.

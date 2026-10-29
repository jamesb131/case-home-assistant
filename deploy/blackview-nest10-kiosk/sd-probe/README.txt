CASE NEST 10 NON-DESTRUCTIVE SD SCAN PROBE

This is not a Linux image and not an Android update.

It contains:
- one ordinary FAT32 partition starting at 1 MiB;
- a U-Boot legacy script at the standard distro-boot paths;
- a guard file used to leave a marker on this same SD card.

It deliberately contains no Rockchip idbloader at 32 KiB, no U-Boot binary,
no kernel, no device tree and no root filesystem. The script does not use
saveenv, mmc write, erase, fastboot, rkdeveloptool, or any internal partition.

First use Android Recovery's "Apply update from SD card" file browser only to
confirm the NEST_PROBE_VISIBLE directory is visible. Back out without selecting
or installing a file. That verifies Recovery can read the card; it does not
test SD boot.

For the cold-boot test, power the NEST off, insert the card and power it on.
After the normal boot attempt, power off before removing the card. Mount it on
the PC and look for:

  case-probe/uboot-ran.bin
  case-probe/uboot-ran.txt

Either marker present: factory U-Boot ran the probe and could write to this FAT
partition. The probe also pauses for 45 seconds before returning. A repeatable
extra boot delay indicates script execution even if no marker can be written.
No marker and no delay: factory U-Boot probably did not scan this script, but
the result remains inconclusive. Do not progress to a generic RK3326 image on
the strength of a negative result.

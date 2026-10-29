# Vendor firmware request

Blackview's official support catalogue has a dedicated NEST 10 page, but its
public download API currently returns only the user manual. Send the request
below privately through the official support form, live chat or
`support@blackview.hk`. Do not publish the device serial number.

## First request

**Subject:** NEST 10 exact recovery firmware required

```text
Hello Blackview Support,

I own a Blackview NEST 10 that I need to restore using the stock recovery.
Please provide the exact full recovery firmware and vendor-signed SD-card OTA
package for this device, together with the official checksum and recovery
instructions.

Model: Blackview NEST 10
Current software version: NEST10_20260508V01
Pending downloaded update shown by the device: V1.1.0_112609231750
Hardware version: BND-RK3326-S101-C
Processor: Rockchip RK3326S
Android version: Android 11
Board identifiers reported by the device: rk3326_E80 / rk3326_rgo

The package must match this hardware revision. A firmware image for another
RK3326/PX30 product is not suitable. Please also confirm whether the supplied
file is a Recovery "Apply update from SD card" package or a complete Rockchip
factory image, and provide the correct tool/instructions for that format.

I can provide the device serial number privately if required to identify the
correct regional build.

Thank you.
```

Keep this first request focused on device recovery. If support supplies a file,
download it without applying it and retain the original message and checksum.

## Follow-up source request

After the recovery package has been identified, request the corresponding GPL
source separately:

```text
Please also provide the complete corresponding source for the Linux kernel
distributed in NEST10_20260508V01, including the build configuration and the
NEST 10 device-tree source, plus any redistributable Wi-Fi/touch firmware and
the scripts required to rebuild the kernel.
```

## Required material

1. Exact vendor-signed recovery OTA for `NEST10_20260508V01`, with checksum.
2. Matching full factory/recovery image and documented restoration procedure.
3. GPL kernel source, defconfig and exact board device-tree sources.
4. Confirmation of whether factory U-Boot supports cold boot from microSD and
   whether secure boot is fused on retail units.

## Intake rule

Do not apply a supplied update until its model, hardware revision, checksum,
package contents, signing metadata and write behavior have been reviewed. Save
the original archive under the ignored `artifacts/` directory and record its
source URL, received filename, byte size and SHA-256 digest.

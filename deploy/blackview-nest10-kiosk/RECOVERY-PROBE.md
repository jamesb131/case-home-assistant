# NEST 10 Recovery signature probe

This is a narrow trust-store test for stock Android Recovery. It answers:

> Does this NEST 10 Recovery trust the public AOSP Android test key?

The ZIP contains one text file plus the signing metadata produced by AOSP
`SignApk -w`. It contains no update binary, updater script, payload, image,
kernel, device tree, bootloader or partition command. It is deliberately unable
to install anything and is expected to fail.

## Why the result is useful

Android Recovery verifies the whole-file OTA signature before it starts the
installation path. A signature failure closes the public test-key route. If
Recovery instead prints `Installing update...` and then reports missing
metadata or a missing update binary, the signature gate has passed. That would
justify a later, separately reviewed read-only diagnostic package which copies
the running Recovery device tree and board metadata onto the SD card.

No diagnostic executable is included in this stage.

## Reproducible build

The builder downloads and SHA-256 verifies:

- AOSP `SignApk.java` from `android-6.0.1_r81`.
- The standard AOSP Android test certificate and PKCS#8 key from
  `android-11.0.0_r48`.

The AOSP test private key is public test material, not a device or user secret.
It is downloaded during the build and is not committed to this repository.

With Docker running on macOS:

```sh
cd /Users/jamesbaverstock/Documents/repos/Case/deploy/blackview-nest10-kiosk
./scripts/build-recovery-signature-probe-container.sh
```

The builder audits the final archive, checks the Android whole-file signature
footer and writes:

```text
output/recovery-signature-probe/NEST10-AOSP-TESTKEY-SIGNATURE-PROBE.zip
output/recovery-signature-probe/NEST10-AOSP-TESTKEY-SIGNATURE-PROBE.zip.sha256
output/recovery-signature-probe/CONTENTS-AUDIT.txt
```

## Copy to the proven FAT card

Mount the existing `NEST_PROBE` card and run:

```sh
./scripts/copy-recovery-probe-macos.sh
```

The script requires the existing card markers, verifies the package hash after
copying, and does not address a raw disk. Eject the card in Finder afterward.

## Device test

1. Power the NEST off completely.
2. Insert the card and enter stock Android Recovery.
3. Choose **Apply update from SD card**.
4. Select `NEST10-AOSP-TESTKEY-SIGNATURE-PROBE.zip`.
5. Photograph or transcribe the complete result.
6. Reboot normally. Do not select a wipe, bootloader update or unrelated ZIP.

Interpretation:

- `Signature verification failed`, `footer is wrong`, or a verification error:
  the AOSP test key is not trusted. Stop this route.
- `Installing update...` followed by missing `META-INF/com/android/metadata`,
  missing `META-INF/com/google/android/update-binary`, or a generic installation
  failure: signature verification passed. Preserve the exact message before
  designing the read-only device-tree exporter.
- `Install from SD card complete`: unexpected and not an acceptable result.
  Reboot and retain the package and logs for investigation. The audited package
  still contains no executable or partition data.

This test does not unlock the bootloader, alter verified boot, flash eMMC/NAND,
or prove that an SD Linux boot chain exists.

## Observed result on the tested NEST 10

Tested on 2026-10-28. Recovery found the package at
`/mnt/external_sd/NEST10-AOSP-TESTKEY-SIGNATURE-PROBE.zip` and reported:

```text
Supported API: 3
Finding update package...
Verifying update package...
E:failed to verify whole-file signature
Update package verification took 0.1 s (result 1).
E:signature verification failed
E:error: 21
Install from SD card completed with status 2.
Installation aborted.
```

This is a definitive rejection of the standard AOSP Android test key. Recovery
never reached package metadata or update-binary handling. Do not repeat this
probe with arbitrary public keys. A Recovery-based diagnostic now requires an
exact vendor-signed package or independently verified NEST signing material.

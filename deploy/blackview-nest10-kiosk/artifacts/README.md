# Required board artifacts

Nothing in this directory may be guessed from another RK3326 or PX30 board.

For the first vendor-chain SD test, provide:

- `nest10.dtb`: extracted from this NEST 10 firmware/device and reviewed.

For a later standalone SD bootloader experiment, additionally provide:

- `idbloader.img`: built or recovered for the exact board and DRAM topology.
- `u-boot.itb`: built for the exact board, with confirmed SD boot and signature policy.

Record provenance in `artifacts.local.md`, then copy
`artifacts.local.env.example` to `artifacts.local.env` and enter the reviewed
SHA-256 values. These local files and binary artifacts are ignored by Git. Do
not use ODROID-GO, generic PX30 EVB, handheld console, or other RK3326 images
merely because the SoC family matches.

# Device-tree port

This directory intentionally contains no guessed NEST 10 DTS.

An extracted vendor DTB is useful evidence, but a downstream Android 4.19 tree
may use bindings and drivers that are incompatible with the mainline kernel.
The eventual `nest10.dtb` must be derived from this exact hardware, reviewed,
and adapted to current bindings where necessary. Display, touch, Wi-Fi, PMIC,
regulator and MMC nodes need evidence from the factory tree, schematics, logs or
board inspection.

Do not start from another RK3326/PX30 board and rename its output.

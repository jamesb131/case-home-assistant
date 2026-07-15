# IoT Locality Notes

CASE should prefer direct local integrations for household devices. Home Assistant
bridges are useful while proving a device workflow, but they should be treated as
temporary unless the device itself has no reliable local API.

## AirTouch 5

- Current path: local direct is supported through `pyairtouch`.
- Runtime internet: not required for direct mode.
- Build-time internet: required when the CASE Core image installs `pyairtouch`.
- CASE settings:
  - `airtouch_backend=auto`
  - `airtouch_host=<AirTouch pad IP>` enables direct local mode.
  - without `airtouch_host`, `auto` falls back to the Home Assistant bridge.
- Direct mode supports reading AC status, zones, target/current temperatures,
  mode, and zone damper open/closed state. It also supports mode changes and
  zone on/off commands.

## Roborock Qrevo MaxQ

- Current path: Home Assistant bridge.
- Runtime internet: the Roborock/Home Assistant setup may depend on Roborock
  cloud account plumbing for setup, tokens, maps, routines, or fallback.
- Local-only replacement: not yet implemented. Modern Roborock local control is
  possible in some ecosystems, but it usually depends on cloud-derived device
  keys and model-specific command payloads. That makes it less suitable as a
  quick direct CASE integration until we can prove a stable local API for this
  exact model.
- CASE route commands should continue to map to named, preplanned HA
  buttons/scripts for now rather than arbitrary map coordinates.

## Rule Of Thumb

When adding a device, classify it in the implementation notes as:

- `local_direct`: CASE talks to the device on the LAN.
- `local_via_ha`: CASE talks to Home Assistant, which talks to the device locally.
- `cloud_dependent`: device control or data requires an internet service.


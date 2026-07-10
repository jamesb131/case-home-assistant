# Ring Doorbell Research Notes

Date: 2026-07-11

## Current view

Ring is useful for CASE, but it is not a true local-first integration. The Home Assistant Ring integration can expose Ring devices, motion events, doorbell press events, camera entities, battery level, Wi-Fi signal, switches, and related controls, but Home Assistant documents its Ring integration as cloud polling and states that all communication goes via Ring cloud.

## Recommended CASE approach

Use Home Assistant as the Ring bridge, then have CASE listen locally to Home Assistant events/state changes.

This keeps CASE simple and avoids taking direct responsibility for Ring auth/session handling. CASE can still provide a local UI experience:

- Log `doorbell_pressed` and `motion_detected` events.
- Show a front-door status tile on Home and the IoT page.
- Optionally show a CASE pop-up when motion or a doorbell press arrives.
- Offer an on-demand "look outside" action that opens the Home Assistant/Ring live view.
- Avoid constant camera streaming.

## Notes

- Realtime Ring alerts require outbound access to Ring's realtime service, including TCP port 5228 according to Home Assistant troubleshooting docs.
- Home Assistant currently exposes Ring doorbell and motion activity through event entities; older binary sensors are being replaced.
- Ring `live_view` camera entities are available, but two-way audio is not supported by the Home Assistant Ring integration.
- Viewing/downloading last recordings generally requires a Ring Protect plan.
- The unofficial `ring-client-api` package can listen to push notifications and active dings directly, but doing this inside CASE would add token management and more cloud/API fragility without making the integration genuinely local.

## Sources

- Home Assistant Ring integration: https://www.home-assistant.io/integrations/ring/
- ring-client-api README: https://raw.githubusercontent.com/dgreif/ring/main/packages/ring-client-api/README.md

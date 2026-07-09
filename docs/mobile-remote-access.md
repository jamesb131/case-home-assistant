# CASE mobile access outside the LAN

The recommended first path is a private VPN overlay, not opening CASE directly to
the public internet.

## Recommended path: Tailscale

Use Tailscale for the first remote-access version because it is quick to test,
does not need router port forwarding, and keeps CASE private.

Target shape:

- Install Tailscale on an always-on home device.
- Advertise the home subnet, for example `192.168.0.0/24`.
- Install Tailscale on the phone.
- Access CASE using the Green's LAN address while connected to Tailscale:

```text
http://192.168.0.154:8080
```

This is still HTTP, so browser microphone access may remain limited. The next
step after Tailscale is adding HTTPS for the CASE web UI.

## HTTPS requirement

Phone voice needs a secure browser context. Long term, CASE should be available
through an HTTPS URL such as:

```text
https://case.home.arpa
```

Good options:

- Caddy reverse proxy with a local CA certificate installed on trusted devices.
- Home Assistant proxy/ingress if it can preserve the CASE API paths cleanly.
- Tailscale plus HTTPS/magic DNS if that fits the final network layout.

## Avoid

- Do not port-forward CASE directly from the router.
- Do not expose the desktop LLM bridge to the internet.
- Do not rely on unauthenticated HTTP for remote access.

# CASE mobile access outside the LAN

The recommended first path is a private VPN overlay, not opening CASE directly to
the public internet.

## Recommended path: Tailscale first, HTTPS second

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

This proves remote connectivity, but it is still HTTP. Browser microphone access
needs a secure context, so the next step is an HTTPS URL.

## HTTPS requirement

Phone voice needs a secure browser context. Long term, CASE should be available
through an HTTPS URL such as:

```text
https://case.home.arpa
```

The CASE Core add-on now supports same-origin API calls through:

```text
/api
```

That means an HTTPS proxy only needs to publish the CASE web port. The browser
can load the UI and call the API on the same secure origin.

Good options, in preferred order:

1. Tailscale HTTPS or Tailscale Serve in front of the Green's CASE web port.
2. Caddy reverse proxy on an always-on host, with a trusted certificate.
3. Home Assistant proxy/ingress if it can preserve the CASE API paths cleanly.

For the first working version, Tailscale is still the lowest-risk choice:

```text
phone -> Tailscale HTTPS URL -> CASE web port 8080 -> /api proxy -> CASE API
```

CASE Core settings should use:

```yaml
case_web_api_base_url: /api
case_api_token: "<long random value>"
case_web_api_token: "<same long random value>"
```

If using a separate Caddy host, proxy only the web port:

```text
case.example.internal {
    reverse_proxy 192.168.0.154:8080
}
```

Do not proxy the desktop LLM bridge to the internet.

## Avoid

- Do not port-forward CASE directly from the router.
- Do not expose the desktop LLM bridge to the internet.
- Do not rely on unauthenticated HTTP for remote access.

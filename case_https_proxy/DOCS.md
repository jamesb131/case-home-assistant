# CASE HTTPS Proxy

This add-on provides local HTTPS for CASE without relying on Let's Encrypt.

## Required files

Upload these files to Home Assistant's SSL share:

```text
/ssl/case-home-arpa.crt
/ssl/case-home-arpa.key
```

The local CA certificate used to sign the server certificate must be trusted on
client devices:

```text
case-local-ca.crt
```

## Options

```yaml
domain: case.home.arpa
upstream_host: 192.168.0.154
upstream_port: 8080
certificate_path: /ssl/case-home-arpa.crt
private_key_path: /ssl/case-home-arpa.key
```

Use the Home Assistant Green's LAN IP for `upstream_host` when CASE Core is
running on the same device with port `8080` exposed.

## Browser URL

Open:

```text
https://case.home.arpa
```

Do not include `:8080`, because that bypasses the HTTPS proxy.

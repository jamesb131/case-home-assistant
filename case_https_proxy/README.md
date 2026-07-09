# CASE HTTPS Proxy

CASE HTTPS Proxy serves a local HTTPS URL for CASE and forwards requests to the
CASE Core web UI.

Default flow:

```text
https://case.home.arpa -> CASE HTTPS Proxy -> http://192.168.0.154:8080
```

Put the certificate and private key in Home Assistant's `/ssl` share before
starting the add-on.

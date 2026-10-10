# CASE desktop VPN download environment

This deployment runs separately from CASE and the desktop LLM bridge. Firefox
and qBittorrent share Gluetun's network namespace, so neither application has an
independent route to the internet. Gluetun's firewall remains the kill switch.

The deployment uses Gluetun's native AirVPN WireGuard provider and selects an
AirVPN server in Singapore. It is intentionally unusable until the generated
AirVPN credentials are entered locally. Placeholder credentials must never be
used to start it.

## Security boundaries

- Only `192.168.0.141:8080` and `192.168.0.141:3001` are published.
- No BitTorrent peer port is published on the LAN or WAN.
- No router configuration or public port forwarding is required.
- `FIREWALL_OUTBOUND_SUBNETS` is deliberately absent. Gluetun therefore does
  not permit Firefox or qBittorrent to initiate connections to the home LAN.
- Only Gluetun receives `NET_ADMIN` and `/dev/net/tun`.
- Firefox uses basic authentication and LinuxServer desktop hardening. Its
  terminal, sudo, file transfers, sharing and helper tools are disabled.
- qBittorrent authentication is enabled by the application. Its API remains
  available to a future trusted automation service through the authenticated
  LAN management endpoint.
- Only `D:\Downloads\Incomplete` and `D:\Downloads\Completed` are mounted.
  `Processing`, Plex storage and the existing `D:\Bit Torrent` directory are
  not visible inside any container.

Gluetun's firewall allows only the VPN endpoint and VPN interface for outbound
traffic unless an outbound subnet is explicitly configured. Do not add the home
LAN to `FIREWALL_OUTBOUND_SUBNETS`.

## One-time setup on the Windows PC

Run these commands in PowerShell from this directory:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Initialize-DownloadDirectories.ps1
Copy-Item .env.example .env
```

Generate an AirVPN WireGuard configuration for Singapore and enter the required
values in `.env`. Keep `.env` local; it is ignored by Git.

Use a long, unique `FIREFOX_PASSWORD`. Map the generated AirVPN configuration
to `.env` as follows:

- `PrivateKey` -> `WIREGUARD_PRIVATE_KEY`
- `PresharedKey` -> `WIREGUARD_PRESHARED_KEY`
- the IPv4 entry from interface `Address` -> `WIREGUARD_ADDRESSES`

Do not copy the IPv6 address from the AirVPN configuration. IPv6 is deliberately
disabled to prevent leaks, and validation accepts one IPv4 CIDR only. Keep
`AIRVPN_SERVER_COUNTRIES=Singapore`; Gluetun selects and maintains the native
AirVPN endpoint. AirVPN port forwarding is not configured in Phase 1 and
`VPN_PORT_FORWARDING` remains off.

### Migrating the existing deployment

Do not replace the existing `.env` file. Edit it in place:

1. Remove `VPN_SERVICE_PROVIDER`, `WIREGUARD_PUBLIC_KEY`,
   `WIREGUARD_ENDPOINT_IP` and `WIREGUARD_ENDPOINT_PORT`.
2. Add `AIRVPN_SERVER_COUNTRIES=Singapore`.
3. Replace the existing WireGuard values with the AirVPN private key,
   preshared key and IPv4 address/CIDR.

The validator reports retired settings by name but never prints credential
values. After editing `.env`, validate and recreate the deployment:

```powershell
.\scripts\Test-Configuration.ps1
docker compose pull
docker compose up -d --wait
.\scripts\Test-Connectivity.ps1
```

Validate before startup:

```powershell
.\scripts\Test-Configuration.ps1
docker compose pull
docker compose up -d --wait
docker compose ps
```

Before VPN credentials exist, static validation can still be run against a copy
of `.env.example` after creating the directories:

```powershell
.\scripts\Test-Configuration.ps1 -EnvFile .env.example -AllowPlaceholders
```

## Windows Firewall

The ports are bound only to the fixed LAN address. Also create inbound Windows
Firewall rules restricted to the trusted subnet. Run in an elevated PowerShell
window after reviewing the commands:

```powershell
New-NetFirewallRule -DisplayName "CASE Downloads qBittorrent" -Direction Inbound -Action Allow -Protocol TCP -LocalAddress 192.168.0.141 -LocalPort 8080 -RemoteAddress 192.168.0.0/24
New-NetFirewallRule -DisplayName "CASE Downloads Firefox" -Direction Inbound -Action Allow -Protocol TCP -LocalAddress 192.168.0.141 -LocalPort 3001 -RemoteAddress 192.168.0.0/24
```

Do not create router port forwards for either port.

## First login and download paths

Open qBittorrent at `http://192.168.0.141:8080`. The first temporary password
for user `admin` is printed in the container log:

```powershell
docker compose logs qbittorrent
```

Immediately change the username and password in qBittorrent's Web UI settings.
Then configure:

```text
Default save path: /downloads/completed
Keep incomplete torrents in: /downloads/incomplete
Web UI authentication: enabled
Bypass authentication for clients on localhost: disabled
Bypass authentication for clients in whitelisted IP subnets: disabled
CSRF protection: enabled
Host header validation: enabled
```

Keep the Web API enabled for future automation. The automation service will
authenticate through `http://192.168.0.141:8080`, stop an individual torrent,
and release its file handles before moving completed files. It will not share a
Docker network or filesystem mount with this stack.

Open Firefox at `https://192.168.0.141:3001`. Accept the local self-signed
certificate and sign in with the credentials from `.env`. Set its download
folder to `/downloads/completed` if browser downloads should persist.

## Verification

Run the normal checks after both applications are healthy:

```powershell
.\scripts\Test-Connectivity.ps1
```

This verifies that:

- qBittorrent and Firefox report the same public IP;
- that address differs from the Windows host's public IP;
- both containers fail to reach the router, CASE and Plex LAN probes;
- both management interfaces reject unauthenticated requests.

Run the disruptive kill-switch test while no downloads are active:

```powershell
.\scripts\Test-Connectivity.ps1 -TestKillSwitch
```

The script briefly blocks all output through the VPN interface, confirms neither
application falls back to the ordinary host connection, removes the temporary
rule, and waits for Gluetun to be healthy again.

Also visit an IP/DNS leak test in the containerised Firefox session. It should
show only the VPN address and VPN-provided or encrypted DNS resolvers.

## Operations

Start, stop and inspect only this deployment:

```powershell
docker compose up -d --wait
docker compose stop
docker compose ps
docker compose logs -f --tail 200
```

Because the Compose project name is `case-downloads`, these commands do not
recreate or alter the CASE LLM bridge.

Configuration persists in the named volumes:

```text
case-downloads-gluetun-state
case-downloads-qbittorrent-config
case-downloads-firefox-config
```

Downloads persist directly under `D:\Downloads`. Removing containers does not
remove downloads or named volumes. Never use `docker compose down -v` unless the
configuration volumes are intentionally being discarded.

## Upgrades

Images are pinned in `.env.example`. Review upstream release notes, update one
tag at a time in the local `.env`, then run:

```powershell
docker compose pull
docker compose up -d --wait
.\scripts\Test-Connectivity.ps1
```

Keep the previous tags available for rollback. To roll back, restore the prior
tag in `.env` and run `docker compose up -d --wait` again.

## Troubleshooting and recovery

If Gluetun is unhealthy, Firefox and qBittorrent will not be started by Compose.
Inspect `docker compose logs gluetun` first. Common causes are incorrect or
expired AirVPN keys, an incorrect WireGuard address, no server matching the
country filter, blocked VPN traffic, or an MTU that is too high. Try AirVPN's
recommended MTU before changing firewall behavior.

If a management page is unavailable:

1. Confirm the PC still owns `192.168.0.141`.
2. Run `docker compose ps` and check service health.
3. Check that ports 8080 and 3001 are not used by another application.
4. Check the two scoped Windows Firewall rules.
5. Inspect service logs without disabling Gluetun's firewall.

If Docker Desktop or Windows restarts, `restart: unless-stopped` restores the
stack. Gluetun must become healthy before either application starts.

Back up named volumes before major upgrades. Download files can be backed up
normally from `D:\Downloads`; `Processing` remains entirely outside this stack.

## Future automation boundary

Phase 1 does not include RSS monitoring, SQLite state, file validation, moving,
renaming or Plex refreshes. The future service should run outside this network,
use a dedicated qBittorrent account if supported, store credentials outside Git,
and receive access only to `Completed`, `Processing` and the required Plex paths.

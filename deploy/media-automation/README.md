# CASE media automation

This is a second, trusted Docker Compose deployment for managing the existing
Plex library. It runs on the Windows PC at `192.168.0.141` and is deliberately
separate from both CASE and the Gluetun download stack.

The deployment contains:

- **Radarr** for the existing `Movies` root;
- **Radarr 4K** for the existing `Movies 4K` root;
- **Sonarr** for `TV Shows`;
- **Bazarr** for subtitle inventory and acquisition; and
- **Seerr** as the household request interface and future CASE API boundary.

Launching these containers does not scan, rename or download anything by
itself. The first configuration should remain audit-only until the imported
library has been reviewed.

## Boundaries

- This Compose project uses its own `case-media-automation` bridge network. It
  does not join `case-downloads-vpn-edge` or any CASE network.
- qBittorrent remains behind Gluetun. Radarr and Sonarr submit jobs through its
  authenticated LAN API; torrent traffic still leaves through AirVPN.
- Only `D:\Downloads\Completed` is visible from the download area. `Incomplete`,
  `Processing` and `D:\Bit Torrent` are not mounted.
- Each manager can write only its own Plex root. Bazarr can write subtitle files
  in all three media roots. Seerr has no filesystem access.
- Management pages bind to the PC's fixed LAN address, not every host interface.
  They must not be exposed through the Omada router or a public tunnel.
- The apps use normal host internet access for metadata and APIs. They do not
  carry downloaded payload traffic and do not weaken Gluetun's kill switch.

## Host paths

The existing Plex parent directory must contain these exact child names:

```text
<PLEX_MEDIA_ROOT>\
  Movies\
  Movies 4K\
  TV Shows\

D:\Downloads\
  Completed\
  Incomplete\       not mounted here
  Processing\       not mounted here
```

Set `PLEX_MEDIA_ROOT` to that parent directory. The repository does not know or
guess its location, and the validation script will not create media folders.

The managers and qBittorrent see completed jobs at the same container path,
`/downloads/completed`. This avoids remote path mappings. Docker Desktop may
still copy rather than hardlink between distinct bind mounts; that is expected
and safer than exposing the whole `D:` drive. Keep enough free space for one
temporary extra copy while a torrent is seeding.

## Install

On the Windows PC, open PowerShell in this directory:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
Copy-Item .env.example .env
notepad .env
```

Set `PLEX_MEDIA_ROOT` to the existing Plex parent folder, using forward slashes.
Do not change `DOWNLOAD_ROOT` from `D:/Downloads` unless the deployed download
stack also changes.

Validate and start:

```powershell
.\scripts\Test-Configuration.ps1
docker compose pull
docker compose up -d --wait
docker compose ps
.\scripts\Test-Services.ps1
```

Static Compose validation can be run against the template without host-path
checks:

```powershell
.\scripts\Test-Configuration.ps1 -EnvFile .env.example -AllowPlaceholders
```

The LAN pages are:

| Service | URL | Purpose |
| --- | --- | --- |
| Radarr | `http://192.168.0.141:7878` | HD/general movies |
| Radarr 4K | `http://192.168.0.141:7879` | 4K movie copies |
| Sonarr | `http://192.168.0.141:8989` | TV series |
| Bazarr | `http://192.168.0.141:6767` | Subtitles |
| Seerr | `http://192.168.0.141:5055` | Requests |

## Windows Firewall

Create inbound allow rules restricted to the trusted LAN. Review these commands
and run them in an elevated PowerShell window:

```powershell
$ports = 7878,7879,8989,6767,5055
foreach ($port in $ports) {
    New-NetFirewallRule -DisplayName "CASE Media $port" -Direction Inbound -Action Allow -Protocol TCP -LocalAddress 192.168.0.141 -LocalPort $port -RemoteAddress 192.168.0.0/24
}
```

Do not add router port forwards. If remote requesting is wanted later, put Seerr
behind an authenticated reverse proxy after a separate security review; do not
expose Radarr, Sonarr or Bazarr.

## First-start security

Configure authentication before adding integrations or sharing the URLs:

1. In both Radarr instances and Sonarr, open **Settings > General > Security**,
   select Forms authentication, require authentication, and set unique admin
   credentials. Leave certificate validation enabled.
2. In Bazarr, open **Settings > General > Security**, enable authentication and
   set unique credentials.
3. Complete Seerr's setup with the Plex administrator account. Create ordinary
   requester accounts for household use rather than sharing administrator access.
4. Confirm a private/incognito request to protected application API endpoints is
   rejected. `Test-Services.ps1` proves availability, not authentication.

Keep API keys out of Git. CASE will eventually use a dedicated Seerr API key
from local secrets, not a Radarr or qBittorrent administrator password.

## Audit-first library setup

Do this before configuring any indexer or qBittorrent connection.

### 1. Import without changing files

In the first Radarr instance:

- set the root folder to `/media/movies`;
- use **Library Import** to inspect existing titles;
- import as unmonitored initially;
- leave **Rename Movies** off; and
- do not run an automatic search.

In Radarr 4K, repeat with `/media/movies-4k`. In Sonarr, use
`/media/tv`, import existing series as unmonitored, leave episode renaming off,
and do not search. Resolve unmatched and incorrectly matched folders manually.

Back up the configuration volumes and Plex database after matching looks right,
then enable renaming and monitoring in small batches. A library import catalogues
existing media; it does not automatically make every folder conform to best
practice safely.

### 2. Duplicated movie versions

Keep the two Radarr roots separate. Never point both Radarr instances at one
root folder. Plex can place both `Movies` and `Movies 4K` in one **Movies**
library and merge matching editions as versions. Plex normally chooses an
appropriate copy for playback; supported clients also expose **Play Version**.
That is not a universal promise that every client always picks the largest file,
so verify the clients used around the house before retiring either copy.

Use distinct Radarr quality profiles, for example:

- general Radarr: preferred 1080p, upgrade cutoff at the chosen 1080p quality;
- Radarr 4K: preferred 2160p, upgrade cutoff at the chosen 2160p quality.

Do not enable cross-instance list syncing until both imported libraries are
clean. If syncing is added later, make it intentional per title so every 1080p
movie does not automatically acquire a 4K duplicate.

### 3. Subtitles

Connect Bazarr to both Radarr instances and Sonarr using their internal service
names and API keys:

```text
Radarr:    http://radarr:7878
Radarr 4K: http://radarr-4k:7878
Sonarr:    http://sonarr:8989
```

Create a subtitle language profile with English required. Scan embedded and
external subtitles first, then review the missing list before enabling automatic
searches. Add forced English as a separate preference where useful. The initial
deployment deliberately does not strip audio tracks or remux files; retain
English, Italian, French and other existing tracks until a later, tested media
processing phase.

## qBittorrent integration

Only configure this after the audit is complete. In each manager add the
authenticated qBittorrent client:

```text
Host: 192.168.0.141
Port: 8080
Use SSL: off
URL base: blank
```

Use a unique category in each manager:

```text
Radarr:    radarr
Radarr 4K: radarr-4k
Sonarr:    sonarr
```

The completed path reported by qBittorrent must remain
`/downloads/completed`. The managers use the same path, so do not add a remote
path mapping. Keep qBittorrent Web UI authentication, CSRF protection and host
header validation enabled. UPnP/NAT-PMP remains disabled.

Configure only lawful, authorised sources. Begin with all automatic searches
disabled, submit one disposable test item per manager, and verify that:

1. the job receives the correct category;
2. qBittorrent downloads through Gluetun;
3. the manager imports into only its assigned media root;
4. Plex sees the imported item; and
5. the completed source is retained while qBittorrent is still seeding.

## Seerr and Plex

Complete Seerr's Plex sign-in and select the Plex server. Add the two Radarr
instances and Sonarr with their internal names and API keys. Choose the correct
root and quality profile for each service. Make the general Radarr instance the
default movie destination; expose 4K as an explicit option for administrators
until storage and duplicate policy are settled.

If Plex runs directly on this same Windows PC and automatic discovery does not
work, use `http://host.docker.internal:32400` as its local URL. Keep Plex's own
authentication enabled; do not publish a new Plex port for this deployment.

Seerr is the intended request boundary for CASE. A later CASE integration can
resolve speech such as “request Project Hail Mary” into a confirmation, then call
Seerr's API. CASE should not write directly to qBittorrent or media directories.

## Operations

```powershell
docker compose up -d --wait
docker compose stop
docker compose ps
docker compose logs -f --tail 200
```

Configuration persists in these named volumes:

```text
case-media-radarr-config
case-media-radarr-4k-config
case-media-sonarr-config
case-media-bazarr-config
case-media-seerr-config
```

Media remains in the host directories. Never run `docker compose down -v`
unless all five application configurations are intentionally being discarded.

## Backup and upgrades

Use the applications' built-in backup tools before upgrades, and copy the
resulting archives outside the Docker volumes. Also back up the Plex database.
The image variables use upstream stable channels; for controlled production
upgrades, replace them in local `.env` with reviewed version tags or digests.

Upgrade one application at a time:

```powershell
docker compose pull radarr
docker compose up -d --wait radarr
.\scripts\Test-Services.ps1
```

Repeat for the other services after checking release notes. A container update
must never be combined with a bulk library rename.

## Troubleshooting

- If qBittorrent cannot be reached from Radarr/Sonarr, confirm the download
  stack is healthy, port 8080 is bound to `192.168.0.141`, and its scoped Windows
  Firewall rule permits the Docker Desktop source network. Do not join the VPN
  network as a workaround.
- If an import says the path does not exist, confirm qBittorrent reports
  `/downloads/completed/...` and do not use the Windows `D:` path in an app.
- If imports copy instead of hardlink, allow for the extra disk use. Do not mount
  all of `D:` merely to obtain hardlinks.
- If Plex shows separate copies, fix metadata matching and use Plex's merge
  function where appropriate. Keep the physical HD and 4K roots separate.
- If an application is unhealthy, inspect `docker compose logs <service>` and
  verify the selected host directory is shared with Docker Desktop.

## Upstream references

- [Radarr container documentation](https://docs.linuxserver.io/images/docker-radarr/)
- [Sonarr container documentation](https://docs.linuxserver.io/images/docker-sonarr/)
- [Bazarr container documentation](https://docs.linuxserver.io/images/docker-bazarr/)
- [Seerr Docker documentation](https://docs.seerr.dev/getting-started/docker/)
- [Plex multiple-version movies](https://support.plex.tv/articles/200381043-multi-version-movies/)

[CmdletBinding()]
param(
    [string]$EnvFile = (Join-Path $PSScriptRoot "..\.env"),
    [switch]$AllowPlaceholders
)

$ErrorActionPreference = "Stop"
$DeployDirectory = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ComposeFile = Join-Path $DeployDirectory "compose.yaml"

function Read-DotEnv {
    param([string]$Path)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $parts = $trimmed.Split("=", 2)
        if ($parts.Count -eq 2) {
            $values[$parts[0].Trim()] = $parts[1].Trim()
        }
    }
    return $values
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker CLI is not installed or is not on PATH."
}

docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Docker Desktop is not running or the current user cannot access it."
}

if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw "Missing $EnvFile. Copy .env.example to .env and fill it in."
}

$envValues = Read-DotEnv -Path $EnvFile
$required = @(
    "LAN_BIND_IP",
    "DOWNLOAD_ROOT",
    "PLEX_MEDIA_ROOT",
    "RADARR_PORT",
    "RADARR_4K_PORT",
    "SONARR_PORT",
    "BAZARR_PORT",
    "PROWLARR_PORT",
    "SEERR_PORT"
)

foreach ($name in $required) {
    if (-not $envValues.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($envValues[$name])) {
        throw "Missing required value $name in $EnvFile."
    }
    if (-not $AllowPlaceholders -and $envValues[$name] -match "replace_|change[_-]?me") {
        throw "$name still contains a placeholder value."
    }
}

if ($envValues["LAN_BIND_IP"] -ne "192.168.0.141") {
    throw "LAN_BIND_IP must remain 192.168.0.141 unless the PC address changes deliberately."
}

$portNames = @("RADARR_PORT", "RADARR_4K_PORT", "SONARR_PORT", "BAZARR_PORT", "PROWLARR_PORT", "SEERR_PORT")
$ports = @{}
foreach ($name in $portNames) {
    $port = 0
    if (-not [int]::TryParse($envValues[$name], [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
        throw "$name must be a valid TCP port number."
    }
    if ($ports.ContainsKey($port)) {
        throw "$name duplicates port $port already assigned to $($ports[$port])."
    }
    $ports[$port] = $name
}

if (-not $AllowPlaceholders) {
    $lanAddress = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $envValues["LAN_BIND_IP"] -ErrorAction SilentlyContinue
    if (-not $lanAddress) {
        throw "The PC does not currently own LAN_BIND_IP $($envValues['LAN_BIND_IP'])."
    }
    if ($lanAddress.PrefixLength -ne 24) {
        throw "LAN_BIND_IP is not configured with the expected /24 prefix."
    }

    $downloadRoot = $envValues["DOWNLOAD_ROOT"].Replace("/", "\")
    $mediaRoot = $envValues["PLEX_MEDIA_ROOT"].Replace("/", "\")
    $requiredPaths = @(
        (Join-Path $downloadRoot "Completed"),
        (Join-Path $downloadRoot "Radarr-Test"),
        (Join-Path $mediaRoot "Movies"),
        (Join-Path $mediaRoot "Movies 4K"),
        (Join-Path $mediaRoot "TV Shows")
    )
    foreach ($path in $requiredPaths) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            throw "Missing required directory $path. This deployment does not create or move Plex media automatically."
        }
    }

    $normalDownloadRoot = [System.IO.Path]::GetFullPath($downloadRoot).TrimEnd("\")
    $normalMediaRoot = [System.IO.Path]::GetFullPath($mediaRoot).TrimEnd("\")
    if (
        $normalDownloadRoot -eq $normalMediaRoot -or
        $normalMediaRoot.StartsWith("$normalDownloadRoot\", [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalDownloadRoot.StartsWith("$normalMediaRoot\", [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        throw "PLEX_MEDIA_ROOT and DOWNLOAD_ROOT must be separate directory trees."
    }
}

$composeSource = Get-Content -LiteralPath $ComposeFile -Raw
if ($composeSource -match "network_mode:\s*service:gluetun|vpn-edge|case-downloads-vpn-edge") {
    throw "Media automation must not join or inherit the VPN download network."
}
if ($composeSource -match "Processing|Incomplete|Bit Torrent") {
    throw "Media automation must not mount Processing, Incomplete or the legacy Bit Torrent directory."
}
if ($composeSource -notmatch 'source:\s+\$\{DOWNLOAD_ROOT:\?Set DOWNLOAD_ROOT in \.env\}/Completed') {
    throw "Radarr and Sonarr must use the same /downloads/completed path reported by qBittorrent."
}
if ($composeSource -notmatch 'source:\s+\$\{PLEX_MEDIA_ROOT:\?Set PLEX_MEDIA_ROOT in \.env\}/Movies 4K') {
    throw "The dedicated 4K movie root is missing from Compose."
}
if ([regex]::Matches($composeSource, '"\$\{LAN_BIND_IP:\?Set LAN_BIND_IP in \.env\}:').Count -ne 6) {
    throw "Every management port must be bound explicitly to LAN_BIND_IP."
}
if ($composeSource -match '(?m)^\s*-\s+"?\d+:\d+' -or $composeSource -match '(?m)^\s*-\s+"?0\.0\.0\.0:') {
    throw "A management port is published on all host interfaces."
}

Push-Location $DeployDirectory
try {
    docker compose --env-file $EnvFile -f $ComposeFile config --quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose configuration validation failed."
    }

    $renderedComposeJson = docker compose --env-file $EnvFile -f $ComposeFile config --format json
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect the rendered Docker Compose configuration."
    }
    $renderedCompose = ($renderedComposeJson -join [Environment]::NewLine) | ConvertFrom-Json

    $prowlarr = $renderedCompose.services.prowlarr
    if (-not $prowlarr) {
        throw "Rendered Compose configuration does not contain Prowlarr."
    }
    if (@($prowlarr.volumes).Count -ne 1 -or $prowlarr.volumes[0].target -ne "/config" -or $prowlarr.volumes[0].type -ne "volume") {
        throw "Prowlarr must mount only its named /config volume."
    }
    if ($prowlarr.ports[0].host_ip -ne $envValues["LAN_BIND_IP"] -or [int]$prowlarr.ports[0].published -ne [int]$envValues["PROWLARR_PORT"]) {
        throw "Prowlarr must publish only PROWLARR_PORT on LAN_BIND_IP."
    }
    if (-not $prowlarr.networks.PSObject.Properties["media-automation"]) {
        throw "Prowlarr must connect to the media-automation network."
    }

    foreach ($serviceName in @("radarr", "radarr-4k", "sonarr", "bazarr")) {
        $service = $renderedCompose.services.PSObject.Properties[$serviceName].Value
        foreach ($mount in @($service.volumes | Where-Object { $_.source -like "$($envValues['PLEX_MEDIA_ROOT'])*" })) {
            if (-not $mount.read_only) {
                throw "Plex media mount $($mount.target) on $serviceName must remain read-only."
            }
        }
    }
}
finally {
    Pop-Location
}

if (-not $AllowPlaceholders) {
    foreach ($port in $ports.Keys) {
        $listeners = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
        if ($listeners) {
            Write-Warning "TCP port $port is already in use. Review it before starting the stack."
        }
    }
}

Write-Host "Configuration validation passed."
if ($AllowPlaceholders) {
    Write-Warning "Host address, path and placeholder checks were skipped. Do not start the stack until PLEX_MEDIA_ROOT is set correctly."
}

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
    "FIREFOX_USERNAME",
    "FIREFOX_PASSWORD",
    "WIREGUARD_PRIVATE_KEY",
    "WIREGUARD_ADDRESSES",
    "WIREGUARD_PUBLIC_KEY",
    "WIREGUARD_ENDPOINT_IP",
    "WIREGUARD_ENDPOINT_PORT"
)

foreach ($name in $required) {
    if (-not $envValues.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($envValues[$name])) {
        throw "Missing required value $name in $EnvFile."
    }
    if (-not $AllowPlaceholders -and $envValues[$name] -match "^(replace_|change[_-]?me)") {
        throw "$name still contains a placeholder value."
    }
}

if ($envValues["LAN_BIND_IP"] -ne "192.168.0.141") {
    throw "LAN_BIND_IP must remain 192.168.0.141 unless the PC address changes deliberately."
}

$lanAddress = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $envValues["LAN_BIND_IP"] -ErrorAction SilentlyContinue
if (-not $lanAddress) {
    throw "The PC does not currently own LAN_BIND_IP $($envValues['LAN_BIND_IP'])."
}
if ($lanAddress.PrefixLength -ne 24) {
    throw "LAN_BIND_IP is not configured with the expected /24 prefix."
}

$downloadRoot = $envValues["DOWNLOAD_ROOT"].Replace("/", "\")
foreach ($name in @("Incomplete", "Completed", "Processing")) {
    $path = Join-Path $downloadRoot $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing download directory $path. Run Initialize-DownloadDirectories.ps1 first."
    }
}

$composeSource = Get-Content -LiteralPath $ComposeFile -Raw
if ($composeSource -match "FIREWALL_OUTBOUND_SUBNETS") {
    throw "FIREWALL_OUTBOUND_SUBNETS must stay unset so containers cannot initiate LAN connections."
}
if ($composeSource -match "Processing|Bit Torrent|Plex") {
    throw "The Compose file must not mount Processing, the legacy Bit Torrent directory, or Plex storage."
}

Push-Location $DeployDirectory
try {
    docker compose --env-file $EnvFile -f $ComposeFile config --quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose configuration validation failed."
    }
}
finally {
    Pop-Location
}

$qbittorrentPort = if ($envValues.ContainsKey("QBITTORRENT_WEBUI_PORT")) { $envValues["QBITTORRENT_WEBUI_PORT"] } else { "8080" }
$firefoxPort = if ($envValues.ContainsKey("FIREFOX_HTTPS_PORT")) { $envValues["FIREFOX_HTTPS_PORT"] } else { "3001" }
$ports = @()
$ports += [int]$qbittorrentPort
$ports += [int]$firefoxPort
foreach ($port in $ports) {
    $listeners = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
    if ($listeners) {
        Write-Warning "TCP port $port is already in use. Review it before starting the stack."
    }
}

Write-Host "Configuration validation passed."
if ($AllowPlaceholders) {
    Write-Warning "Placeholder validation was skipped. Do not start the stack until real VPN and Firefox credentials are configured."
}

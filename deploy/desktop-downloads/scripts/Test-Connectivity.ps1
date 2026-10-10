[CmdletBinding()]
param(
    [string]$EnvFile = (Join-Path $PSScriptRoot "..\.env"),
    [string[]]$LanProbeUrls = @(
        "http://192.168.0.1",
        "http://192.168.0.154:8123",
        "http://192.168.0.141:32400"
    ),
    [switch]$TestKillSwitch
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

function Get-ContainerPublicIp {
    param([string]$Service)
    $result = & docker compose --env-file $EnvFile -f $ComposeFile exec -T $Service `
        curl -4fsS --max-time 10 https://api.ipify.org
    if ($LASTEXITCODE -ne 0) {
        throw "$Service could not reach the public IP service."
    }
    return ($result | Out-String).Trim()
}

function Assert-LanBlocked {
    param([string]$Service, [string]$Url)
    & docker compose --env-file $EnvFile -f $ComposeFile exec -T $Service `
        curl -kfsS --connect-timeout 2 --max-time 3 $Url *> $null
    if ($LASTEXITCODE -eq 0) {
        throw "$Service unexpectedly reached LAN URL $Url."
    }
}

Push-Location $DeployDirectory
try {
    if (-not (Test-Path -LiteralPath $EnvFile)) {
        throw "Missing $EnvFile."
    }
    $envValues = Read-DotEnv -Path $EnvFile
    $lanBindIp = $envValues["LAN_BIND_IP"]
    $qbittorrentPort = if ($envValues.ContainsKey("QBITTORRENT_WEBUI_PORT")) { $envValues["QBITTORRENT_WEBUI_PORT"] } else { "8080" }
    $firefoxPort = if ($envValues.ContainsKey("FIREFOX_HTTPS_PORT")) { $envValues["FIREFOX_HTTPS_PORT"] } else { "3001" }

    $status = & docker compose --env-file $EnvFile -f $ComposeFile ps --format json | Out-String
    if ($status -notmatch 'case-downloads-vpn' -or $status -notmatch 'healthy') {
        throw "The VPN container is not healthy."
    }

    $hostIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10).Trim()
    $qbittorrentIp = Get-ContainerPublicIp -Service "qbittorrent"
    $firefoxIp = Get-ContainerPublicIp -Service "firefox"

    if ($qbittorrentIp -ne $firefoxIp) {
        throw "qBittorrent and Firefox are not using the same VPN exit IP."
    }
    if ($qbittorrentIp -eq $hostIp) {
        throw "The containers are using the host public IP instead of a VPN exit IP."
    }

    foreach ($service in @("qbittorrent", "firefox")) {
        foreach ($url in $LanProbeUrls) {
            Assert-LanBlocked -Service $service -Url $url
        }
    }

    $qbAuthStatus = (& curl.exe -s -o NUL -w "%{http_code}" "http://${lanBindIp}:${qbittorrentPort}/api/v2/app/version").Trim()
    if ($qbAuthStatus -notin @("401", "403")) {
        throw "qBittorrent API did not reject an unauthenticated request (HTTP $qbAuthStatus)."
    }
    $firefoxAuthStatus = (& curl.exe -k -s -o NUL -w "%{http_code}" "https://${lanBindIp}:${firefoxPort}/").Trim()
    if ($firefoxAuthStatus -ne "401") {
        throw "Firefox did not request authentication (HTTP $firefoxAuthStatus)."
    }

    if ($TestKillSwitch) {
        Write-Host "Temporarily blocking the VPN interface to test the kill switch..."
        try {
            & docker compose --env-file $EnvFile -f $ComposeFile exec -T gluetun `
                iptables -I OUTPUT 1 -o tun0 -j REJECT
            if ($LASTEXITCODE -ne 0) { throw "Could not install the temporary VPN block." }

            foreach ($service in @("qbittorrent", "firefox")) {
                & docker compose --env-file $EnvFile -f $ComposeFile exec -T $service `
                    curl -4fsS --connect-timeout 2 --max-time 3 https://api.ipify.org *> $null
                if ($LASTEXITCODE -eq 0) {
                    throw "$service retained internet access while tun0 was down."
                }
            }
        }
        finally {
            & docker compose --env-file $EnvFile -f $ComposeFile exec -T gluetun `
                iptables -D OUTPUT -o tun0 -j REJECT
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Could not remove the temporary rule cleanly; restarting Gluetun to restore its firewall."
                & docker compose --env-file $EnvFile -f $ComposeFile restart gluetun
            }
            & docker compose --env-file $EnvFile -f $ComposeFile up -d --wait
        }
    }

    Write-Host "Connectivity checks passed. VPN exit IP: $qbittorrentIp"
}
finally {
    Pop-Location
}

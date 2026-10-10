[CmdletBinding()]
param(
    [string]$EnvFile = (Join-Path $PSScriptRoot "..\.env")
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
        if ($parts.Count -eq 2) { $values[$parts[0].Trim()] = $parts[1].Trim() }
    }
    return $values
}

function Test-HttpEndpoint {
    param(
        [string]$Name,
        [string]$Url
    )

    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.AllowAutoRedirect = $false
        $request.Timeout = 5000
        $response = $request.GetResponse()
        $status = [int]$response.StatusCode
        $response.Close()
        if ($status -ge 200 -and $status -lt 400) {
            Write-Host "PASS  $Name responded with HTTP $status at $Url"
            return $true
        }
        Write-Host "FAIL  $Name returned HTTP $status at $Url"
        return $false
    }
    catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
            $_.Exception.Response.Close()
            Write-Host "FAIL  $Name returned HTTP $status at $Url"
        }
        else {
            Write-Host "ERROR $Name could not be reached at ${Url}: $($_.Exception.Message)"
        }
        return $false
    }
}

if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw "Missing $EnvFile."
}

$envValues = Read-DotEnv -Path $EnvFile
$hostAddress = $envValues["LAN_BIND_IP"]
$checks = @(
    @{ Name = "Radarr"; Port = $envValues["RADARR_PORT"]; Path = "/ping" },
    @{ Name = "Radarr 4K"; Port = $envValues["RADARR_4K_PORT"]; Path = "/ping" },
    @{ Name = "Sonarr"; Port = $envValues["SONARR_PORT"]; Path = "/ping" },
    @{ Name = "Bazarr"; Port = $envValues["BAZARR_PORT"]; Path = "/" },
    @{ Name = "Prowlarr"; Port = $envValues["PROWLARR_PORT"]; Path = "/ping" },
    @{ Name = "Seerr"; Port = $envValues["SEERR_PORT"]; Path = "/api/v1/settings/public" }
)
$allPassed = $true

Push-Location $DeployDirectory
try {
    $services = docker compose --env-file $EnvFile -f $ComposeFile ps --services --filter status=running
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect Compose services." }
    $running = @($services)
    $expected = @("radarr", "radarr-4k", "sonarr", "bazarr", "prowlarr", "seerr")
    foreach ($service in $expected) {
        if ($running -notcontains $service) {
            Write-Host "FAIL  Compose service $service is not running."
            $allPassed = $false
        }
        else {
            Write-Host "PASS  Compose service $service is running."
        }
    }
}
finally {
    Pop-Location
}

foreach ($check in $checks) {
    $url = "http://${hostAddress}:$($check.Port)$($check.Path)"
    if (-not (Test-HttpEndpoint -Name $check.Name -Url $url)) { $allPassed = $false }
}

if (-not $allPassed) {
    throw "One or more media automation endpoint checks failed."
}

Write-Host "Service checks passed. Authentication still requires the manual checks documented in README.md."

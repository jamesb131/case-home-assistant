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
$script:PassCount = 0
$script:FailCount = 0
$script:ErrorCount = 0
$script:SkipCount = 0

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

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $result = $null
    try {
        # PowerShell 7 can promote native stderr to an ErrorRecord. Capture it
        # and classify the process exit code instead of terminating on curl 28.
        $ErrorActionPreference = "Continue"
        $output = @(& $FilePath @ArgumentList 2>&1)
        $exitCode = $LASTEXITCODE
        $result = [pscustomobject]@{
            Started = $true
            ExitCode = $exitCode
            Output = (($output | ForEach-Object { "$_" }) -join "`n").Trim()
        }
    }
    catch {
        $result = [pscustomobject]@{
            Started = $false
            ExitCode = $null
            Output = $_.Exception.Message
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    return $result
}

function Invoke-DockerCompose {
    param([string[]]$Arguments)

    $composeArguments = @("compose", "--env-file", $EnvFile, "-f", $ComposeFile) + $Arguments
    return Invoke-NativeCommand -FilePath "docker" -ArgumentList $composeArguments
}

function Write-TestResult {
    param(
        [ValidateSet("PASS", "FAIL", "ERROR", "SKIP")][string]$Status,
        [string]$Target,
        [string]$Purpose,
        [string]$Detail
    )

    $colour = switch ($Status) {
        "PASS" { $script:PassCount++; "Green" }
        "FAIL" { $script:FailCount++; "Red" }
        "ERROR" { $script:ErrorCount++; "Magenta" }
        "SKIP" { $script:SkipCount++; "Yellow" }
    }
    Write-Host "[$Status]" -ForegroundColor $colour -NoNewline
    Write-Host " $Target"
    Write-Host "       Purpose: $Purpose"
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-Host "       Detail:  $Detail"
    }
}

function Get-ValidIpv4Address {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    $parsedAddress = $null
    if (
        [System.Net.IPAddress]::TryParse($Value.Trim(), [ref]$parsedAddress) -and
        $parsedAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
    ) {
        return $parsedAddress.ToString()
    }
    return $null
}

function Invoke-ContainerCurl {
    param(
        [string]$Service,
        [string[]]$CurlArguments
    )

    return Invoke-DockerCompose -Arguments (@("exec", "-T", $Service, "curl") + $CurlArguments)
}

function Get-ContainerPublicIpProbe {
    param([string]$Service)

    $probe = Invoke-ContainerCurl -Service $Service -CurlArguments @(
        "-4fsS",
        "--connect-timeout", "5",
        "--max-time", "10",
        "https://api.ipify.org"
    )
    if (-not $probe.Started) {
        return [pscustomobject]@{ Success = $false; Ip = $null; Detail = "docker could not start: $($probe.Output)" }
    }
    if ($probe.ExitCode -ne 0) {
        return [pscustomobject]@{ Success = $false; Ip = $null; Detail = "curl exited $($probe.ExitCode): $($probe.Output)" }
    }

    $ipAddress = Get-ValidIpv4Address -Value $probe.Output
    if (-not $ipAddress) {
        return [pscustomobject]@{ Success = $false; Ip = $null; Detail = "the probe returned an invalid IPv4 address" }
    }
    return [pscustomobject]@{ Success = $true; Ip = $ipAddress; Detail = "public IPv4 $ipAddress" }
}

function Test-ExpectedBlockedProbe {
    param(
        [string]$Target,
        [string]$Purpose,
        [object]$Probe,
        [int[]]$ExpectedExitCodes
    )

    if (-not $Probe.Started) {
        Write-TestResult -Status "ERROR" -Target $Target -Purpose $Purpose -Detail "probe process did not start: $($Probe.Output)"
        return
    }
    if ($Probe.ExitCode -eq 0) {
        Write-TestResult -Status "FAIL" -Target $Target -Purpose $Purpose -Detail "connection succeeded when it should have been blocked"
        return
    }
    if ($Probe.ExitCode -in $ExpectedExitCodes) {
        Write-TestResult -Status "PASS" -Target $Target -Purpose $Purpose -Detail "connection blocked (curl exit $($Probe.ExitCode))"
        return
    }
    Write-TestResult -Status "ERROR" -Target $Target -Purpose $Purpose -Detail "unexpected probe failure (curl/docker exit $($Probe.ExitCode)): $($Probe.Output)"
}

function Test-ManagementAuthentication {
    param(
        [string]$Target,
        [string]$Purpose,
        [string]$Url,
        [string[]]$ExpectedStatusCodes,
        [switch]$SkipCertificateValidation
    )

    $arguments = @("-sS", "-o", "NUL", "-w", "%{http_code}", "--connect-timeout", "3", "--max-time", "5")
    if ($SkipCertificateValidation) { $arguments += "-k" }
    $arguments += $Url
    $probe = Invoke-NativeCommand -FilePath "curl.exe" -ArgumentList $arguments

    if (-not $probe.Started) {
        Write-TestResult -Status "ERROR" -Target $Target -Purpose $Purpose -Detail "curl.exe did not start: $($probe.Output)"
        return
    }
    if ($probe.ExitCode -ne 0) {
        Write-TestResult -Status "ERROR" -Target $Target -Purpose $Purpose -Detail "management probe exited $($probe.ExitCode): $($probe.Output)"
        return
    }

    $statusCode = $probe.Output.Trim()
    if ($statusCode -in $ExpectedStatusCodes) {
        Write-TestResult -Status "PASS" -Target $Target -Purpose $Purpose -Detail "unauthenticated request rejected with HTTP $statusCode"
    }
    else {
        Write-TestResult -Status "FAIL" -Target $Target -Purpose $Purpose -Detail "unexpected unauthenticated response HTTP $statusCode"
    }
}

function Wait-ForVpnRecovery {
    param([string]$HostPublicIp)

    $lastDetail = "no successful probe"
    for ($attempt = 1; $attempt -le 15; $attempt++) {
        $qbProbe = Get-ContainerPublicIpProbe -Service "qbittorrent"
        $firefoxProbe = Get-ContainerPublicIpProbe -Service "firefox"
        if ($qbProbe.Success -and $firefoxProbe.Success) {
            if ($qbProbe.Ip -eq $firefoxProbe.Ip -and $qbProbe.Ip -ne $HostPublicIp) {
                return [pscustomobject]@{ Success = $true; Detail = "both applications recovered on VPN IPv4 $($qbProbe.Ip)" }
            }
            $lastDetail = "applications returned different or non-VPN addresses"
        }
        else {
            $lastDetail = "qBittorrent: $($qbProbe.Detail); Firefox: $($firefoxProbe.Detail)"
        }
        Start-Sleep -Seconds 2
    }
    return [pscustomobject]@{ Success = $false; Detail = $lastDetail }
}

if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw "Missing $EnvFile."
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker CLI is not installed or is not on PATH."
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw "curl.exe is not installed or is not on PATH."
}

Push-Location $DeployDirectory
try {
    $envValues = Read-DotEnv -Path $EnvFile
    $lanBindIp = $envValues["LAN_BIND_IP"]
    $qbittorrentPort = if ($envValues.ContainsKey("QBITTORRENT_WEBUI_PORT")) { $envValues["QBITTORRENT_WEBUI_PORT"] } else { "8080" }
    $firefoxPort = if ($envValues.ContainsKey("FIREFOX_HTTPS_PORT")) { $envValues["FIREFOX_HTTPS_PORT"] } else { "3001" }

    foreach ($container in @("case-downloads-vpn", "case-downloads-qbittorrent", "case-downloads-firefox")) {
        $healthProbe = Invoke-NativeCommand -FilePath "docker" -ArgumentList @(
            "inspect", "--format", "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}", $container
        )
        if (-not $healthProbe.Started -or $healthProbe.ExitCode -ne 0) {
            Write-TestResult -Status "ERROR" -Target $container -Purpose "Confirm the container can be inspected" -Detail $healthProbe.Output
        }
        elseif ($healthProbe.Output.Trim() -eq "healthy") {
            Write-TestResult -Status "PASS" -Target $container -Purpose "Confirm the deployed service is healthy" -Detail "Docker health status is healthy"
        }
        else {
            Write-TestResult -Status "FAIL" -Target $container -Purpose "Confirm the deployed service is healthy" -Detail "Docker health status is $($healthProbe.Output.Trim())"
        }
    }

    $hostProbe = Invoke-NativeCommand -FilePath "curl.exe" -ArgumentList @(
        "-4fsS", "--connect-timeout", "5", "--max-time", "10", "https://api.ipify.org"
    )
    $hostIp = $null
    if (-not $hostProbe.Started -or $hostProbe.ExitCode -ne 0) {
        Write-TestResult -Status "ERROR" -Target "Windows host internet" -Purpose "Establish the non-VPN comparison address" -Detail "curl exited $($hostProbe.ExitCode): $($hostProbe.Output)"
    }
    else {
        $hostIp = Get-ValidIpv4Address -Value $hostProbe.Output
        if ($hostIp) {
            Write-TestResult -Status "PASS" -Target "Windows host internet" -Purpose "Establish the non-VPN comparison address" -Detail "public IPv4 $hostIp"
        }
        else {
            Write-TestResult -Status "ERROR" -Target "Windows host internet" -Purpose "Establish the non-VPN comparison address" -Detail "the probe returned an invalid IPv4 address"
        }
    }

    $qbittorrentIpProbe = Get-ContainerPublicIpProbe -Service "qbittorrent"
    $firefoxIpProbe = Get-ContainerPublicIpProbe -Service "firefox"
    foreach ($item in @(
        @{ Name = "qBittorrent internet"; Probe = $qbittorrentIpProbe },
        @{ Name = "Firefox internet"; Probe = $firefoxIpProbe }
    )) {
        if ($item.Probe.Success) {
            Write-TestResult -Status "PASS" -Target $item.Name -Purpose "Confirm external IPv4 connectivity through Gluetun" -Detail $item.Probe.Detail
        }
        else {
            Write-TestResult -Status "ERROR" -Target $item.Name -Purpose "Confirm external IPv4 connectivity through Gluetun" -Detail $item.Probe.Detail
        }
    }

    if ($qbittorrentIpProbe.Success -and $firefoxIpProbe.Success) {
        if ($qbittorrentIpProbe.Ip -eq $firefoxIpProbe.Ip) {
            Write-TestResult -Status "PASS" -Target "Shared VPN exit" -Purpose "Confirm Firefox and qBittorrent use the same VPN route" -Detail "both report $($qbittorrentIpProbe.Ip)"
        }
        else {
            Write-TestResult -Status "FAIL" -Target "Shared VPN exit" -Purpose "Confirm Firefox and qBittorrent use the same VPN route" -Detail "qBittorrent reports $($qbittorrentIpProbe.Ip); Firefox reports $($firefoxIpProbe.Ip)"
        }
    }
    else {
        Write-TestResult -Status "ERROR" -Target "Shared VPN exit" -Purpose "Confirm Firefox and qBittorrent use the same VPN route" -Detail "one or both public-IP probes failed"
    }

    foreach ($item in @(
        @{ Name = "qBittorrent VPN routing"; Probe = $qbittorrentIpProbe },
        @{ Name = "Firefox VPN routing"; Probe = $firefoxIpProbe }
    )) {
        if (-not $hostIp -or -not $item.Probe.Success) {
            Write-TestResult -Status "ERROR" -Target $item.Name -Purpose "Confirm the application is not using the Windows host connection" -Detail "a required public-IP probe failed"
        }
        elseif ($item.Probe.Ip -ne $hostIp) {
            Write-TestResult -Status "PASS" -Target $item.Name -Purpose "Confirm the application is not using the Windows host connection" -Detail "VPN IPv4 differs from host IPv4"
        }
        else {
            Write-TestResult -Status "FAIL" -Target $item.Name -Purpose "Confirm the application is not using the Windows host connection" -Detail "application and host both report $hostIp"
        }
    }

    for ($index = 0; $index -lt $LanProbeUrls.Count; $index++) {
        $url = $LanProbeUrls[$index]
        $friendlyName = if ($index -eq 0) { "router" } elseif ($index -eq 1) { "CASE" } elseif ($index -eq 2) { "Plex" } else { "LAN target $($index + 1)" }
        foreach ($service in @("qbittorrent", "firefox")) {
            $probe = Invoke-ContainerCurl -Service $service -CurlArguments @(
                "-k", "-sS", "-o", "/dev/null", "-w", "%{http_code}",
                "--connect-timeout", "2", "--max-time", "3", $url
            )
            Test-ExpectedBlockedProbe -Target "$service -> $friendlyName ($url)" -Purpose "Confirm containers cannot initiate connections to the home LAN" -Probe $probe -ExpectedExitCodes @(7, 28)
        }
    }

    Test-ManagementAuthentication `
        -Target "qBittorrent Web API" `
        -Purpose "Confirm the LAN management endpoint rejects unauthenticated access" `
        -Url "http://${lanBindIp}:${qbittorrentPort}/api/v2/app/version" `
        -ExpectedStatusCodes @("401", "403")
    Test-ManagementAuthentication `
        -Target "Firefox Web UI" `
        -Purpose "Confirm the LAN management endpoint requires authentication" `
        -Url "https://${lanBindIp}:${firefoxPort}/" `
        -ExpectedStatusCodes @("401") `
        -SkipCertificateValidation

    if ($TestKillSwitch) {
        $temporaryRuleInstalled = $false
        $cleanupNeedsRestart = $false
        try {
            $installRule = Invoke-DockerCompose -Arguments @(
                "exec", "-T", "gluetun", "iptables", "-w", "5", "-I", "OUTPUT", "1", "-o", "tun0", "-j", "REJECT"
            )
            if (-not $installRule.Started -or $installRule.ExitCode -ne 0) {
                Write-TestResult -Status "ERROR" -Target "Temporary VPN firewall rule" -Purpose "Deliberately block the VPN route for the kill-switch test" -Detail $installRule.Output
            }
            else {
                $temporaryRuleInstalled = $true
                Write-TestResult -Status "PASS" -Target "Temporary VPN firewall rule" -Purpose "Deliberately block the VPN route for the kill-switch test" -Detail "OUTPUT traffic on tun0 is temporarily rejected"

                foreach ($service in @("qbittorrent", "firefox")) {
                    $probe = Invoke-ContainerCurl -Service $service -CurlArguments @(
                        "-4", "-sS", "-o", "/dev/null", "-w", "%{http_code}",
                        "--connect-timeout", "2", "--max-time", "3", "https://api.ipify.org"
                    )
                    Test-ExpectedBlockedProbe -Target "$service kill switch" -Purpose "Confirm external connectivity is lost while the VPN route is blocked" -Probe $probe -ExpectedExitCodes @(6, 7, 28)
                }
            }
        }
        catch {
            Write-TestResult -Status "ERROR" -Target "Kill-switch test harness" -Purpose "Run the disruptive VPN-route test" -Detail $_.Exception.Message
            $cleanupNeedsRestart = $temporaryRuleInstalled
        }
        finally {
            if ($temporaryRuleInstalled) {
                $removeRule = Invoke-DockerCompose -Arguments @(
                    "exec", "-T", "gluetun", "iptables", "-w", "5", "-D", "OUTPUT", "-o", "tun0", "-j", "REJECT"
                )
                if (-not $removeRule.Started -or $removeRule.ExitCode -ne 0) {
                    $cleanupNeedsRestart = $true
                    Write-TestResult -Status "ERROR" -Target "Temporary VPN firewall rule cleanup" -Purpose "Restore the original Gluetun firewall" -Detail "rule removal failed; Gluetun will be restarted"
                }
                else {
                    Write-TestResult -Status "PASS" -Target "Temporary VPN firewall rule cleanup" -Purpose "Restore the original Gluetun firewall" -Detail "temporary rule removed"
                }
            }

            if ($cleanupNeedsRestart) {
                $restart = Invoke-DockerCompose -Arguments @("restart", "gluetun")
                if (-not $restart.Started -or $restart.ExitCode -ne 0) {
                    Write-TestResult -Status "ERROR" -Target "Gluetun recovery restart" -Purpose "Clear any temporary firewall state after cleanup failure" -Detail $restart.Output
                }
                else {
                    Write-TestResult -Status "PASS" -Target "Gluetun recovery restart" -Purpose "Clear any temporary firewall state after cleanup failure" -Detail "Gluetun restarted"
                }
            }

            $waitForStack = Invoke-DockerCompose -Arguments @("up", "-d", "--wait")
            if (-not $waitForStack.Started -or $waitForStack.ExitCode -ne 0) {
                Write-TestResult -Status "ERROR" -Target "Post-test stack health" -Purpose "Wait for the VPN-backed services after cleanup" -Detail $waitForStack.Output
            }
        }

        $recovery = Wait-ForVpnRecovery -HostPublicIp $hostIp
        if ($recovery.Success) {
            Write-TestResult -Status "PASS" -Target "VPN recovery" -Purpose "Confirm both applications regain VPN-only internet access after cleanup" -Detail $recovery.Detail
        }
        else {
            Write-TestResult -Status "FAIL" -Target "VPN recovery" -Purpose "Confirm both applications regain VPN-only internet access after cleanup" -Detail $recovery.Detail
        }
    }
    else {
        Write-TestResult -Status "SKIP" -Target "Kill switch" -Purpose "Confirm applications lose internet access when tun0 is blocked" -Detail "not run; invoke this script with -TestKillSwitch"
    }

    Write-Host ""
    Write-Host "Summary: $script:PassCount PASS, $script:FailCount FAIL, $script:ErrorCount ERROR, $script:SkipCount SKIP"
    if ($script:FailCount -gt 0 -or $script:ErrorCount -gt 0) {
        throw "Connectivity verification did not pass. Review the FAIL and ERROR results above."
    }
    if (-not $TestKillSwitch) {
        Write-Warning "Normal connectivity and isolation checks passed; the kill switch remains unverified until -TestKillSwitch passes."
    }
}
finally {
    Pop-Location
}

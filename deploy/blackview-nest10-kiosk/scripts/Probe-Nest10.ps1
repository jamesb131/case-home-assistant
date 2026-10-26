[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ProjectDirectory = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$OutputDirectory = Join-Path $ProjectDirectory "probe-output"
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$OutputPath = Join-Path $OutputDirectory "fastboot-$Timestamp.txt"

if (-not (Get-Command fastboot -ErrorAction SilentlyContinue)) {
    throw "fastboot is not installed or is not on PATH."
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$PreviousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$Devices = @(& fastboot devices 2>&1)
$ErrorActionPreference = $PreviousErrorActionPreference
if ($LASTEXITCODE -ne 0 -or -not ($Devices -match "\sfastboot\s*$")) {
    throw "No device is currently visible in fastboot mode."
}
$Variables = @(
    "product", "secure", "unlocked", "current-slot", "slot-count", "version-bootloader",
    "has-slot:boot", "has-slot:dtbo", "has-slot:vbmeta", "has-slot:vendor_boot", "has-slot:super",
    "partition-size:boot_a", "partition-size:boot_b",
    "partition-size:dtbo_a", "partition-size:dtbo_b",
    "partition-size:vbmeta_a", "partition-size:vbmeta_b",
    "partition-size:vendor_boot_a", "partition-size:vendor_boot_b",
    "partition-size:super", "max-download-size"
)

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add("Captured: $Timestamp")
foreach ($DeviceLine in $Devices) { $Lines.Add([string]$DeviceLine) }
$Lines.Add("Read-only fastboot getvars follow.")
foreach ($Variable in $Variables) {
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $Lines.Add("--- $Variable ---")
    $Result = & fastboot getvar $Variable 2>&1
    $ErrorActionPreference = $PreviousErrorActionPreference
    foreach ($Line in @($Result)) { $Lines.Add([string]$Line) }
}
$Lines | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "Wrote read-only probe: $OutputPath"

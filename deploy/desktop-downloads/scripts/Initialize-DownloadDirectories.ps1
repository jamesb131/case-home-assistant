[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DownloadRoot = "D:\Downloads"
)

$ErrorActionPreference = "Stop"

$directories = @(
    $DownloadRoot,
    (Join-Path $DownloadRoot "Incomplete"),
    (Join-Path $DownloadRoot "Completed"),
    (Join-Path $DownloadRoot "Processing")
)

foreach ($directory in $directories) {
    if (-not (Test-Path -LiteralPath $directory)) {
        if ($PSCmdlet.ShouldProcess($directory, "Create directory")) {
            New-Item -ItemType Directory -Path $directory | Out-Null
        }
    }
}

Write-Host "Download directories are ready under $DownloadRoot."
Write-Host "Only Incomplete and Completed are mounted into the VPN stack."
